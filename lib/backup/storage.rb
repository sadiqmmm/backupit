require 'tempfile'

module Backup
  class Storage
    extend Backup::Attribute
    attr_accessor :name, :config, :changes, :subject_prefix

    def initialize(name, config)
      self.name   = name
      self.config = config
    end

    def backup(server)
      @server        = server
      @server_config = @server.config
      @backup_path   = "#{config.path}/#{@server.name}"

      @ssh_host      = "-p#{@server_config.port || 22} #{@server_config.host}"
      @scp_host      = "-P#{@server_config.port || 22} #{@server_config.host}"
      @rsync_host    = "-e 'ssh -p#{@server_config.port || 22}' #{@server_config.host}"

      self.changes   = []

      backup_rsync
      backup_mysql
      commit_changes
      send_mail(changes.join("\n"))
    end

    def backup_rsync
      target_path = File.join(@backup_path, "rsync")

      FileUtils.mkdir_p target_path

      @server_config.rsync.to_a.map do |path|
        remote_path = path.is_a?(Hash) ? path.first[0] : path
        target_name = File.basename(path.is_a?(Hash) ? path.first[1] : path)
        run_with_changes("rsync -ravk #{@rsync_host}:#{remote_path.sub(/\/?$/,'/')} '#{File.join(target_path, target_name)}'")
      end
    end

    def backup_mysql
      target_path = File.join(@backup_path, "mysql")
      FileUtils.mkdir_p target_path

      @server_config.mysql.map do |key, mysql|
        mysql_config = ""
        mysql_config += " -u#{mysql.user}" if mysql.user
        mysql_config += " -p#{mysql.password}" if mysql.password
        mysql_config += " --databases #{mysql.databases.to_a.join(' ')}" if mysql.databases
        mysql_config += " --tables #{mysql.tables.to_a.join(' ')}" if mysql.tables
        mysql_config += " #{mysql.options}" if mysql.options

        tmpfile = Tempfile.new('mysql.sql')
        run_with_changes("ssh #{@ssh_host} 'mysqldump #{mysql_config} > #{tmpfile.path}'") &&
        run_with_changes("scp #{@scp_host}:#{tmpfile.path} '#{target_path}/#{key}.sql'") &&
        run_with_changes("ssh #{@ssh_host} 'rm #{tmpfile.path}'")

        check_backuped_mysql(target_path, key) if config.mysql_check and (mysql.check || mysql.check.nil?)
      end
    end

    def check_backuped_mysql(target_path, key)
      dbconfig = config.mysql_config

      self.changes << "DBCheck running -- checking #{target_path}/#{key}.sql #{Time.now}"

      mysql_command = "mysql -h#{dbconfig[:host]} -u#{dbconfig[:user]} #{dbconfig[:password] ? "-p#{dbconfig[:password]}" : ""}"
      system("#{mysql_command} -e 'drop database #{dbconfig[:database]};'")
      system("#{mysql_command} -e 'create database #{dbconfig[:database]};'")

      status = run_with_changes("#{mysql_command} #{dbconfig[:database]} < #{target_path}/#{key}.sql") ? "SUCCESSFUL" : "FAILURE"
      self.changes << "DBCheck finished #{status} -- #{Time.now}"
    end

    def commit_changes
      Dir.chdir(@backup_path) do
        run_with_changes("git init") unless system("git status")
        run_with_changes("git add .")
        run_with_changes("git commit -am '#{Time.now.strftime("%Y-%m-%d %H:%M")}'")
      end
    end

    def run_with_changes(shell)
      self.changes << "== #{shell}"
      result = Backup::Main.run(shell)
      self.subject_prefix = "[ERROR]" unless result
      self.changes << result
      result
    end

    def send_mail(message)
      Dir.chdir(@backup_path) do
        smtp_config = config.smtp
        Mail.defaults { delivery_method :smtp, smtp_config } if smtp_config

        Backup::Main.email(:from => @server_config.email,
                           :to => @server_config.email,
                           :subject => "#{self.subject_prefix} #{@server.name} backed up at #{Time.now}",
                           :body => message,
                           :charset => 'utf-8', :content_type => 'text/plain; charset=utf-8'
                          ) if @server_config.email
      end
    end
  end
end
