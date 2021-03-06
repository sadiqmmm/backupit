Dir[File.join(File.dirname(__FILE__),'*.rb')].map {|f| require f}

module Backup
  module Configuration
    class Base
      extend Backup::Attribute

      def storage(name=nil,&block)
        @storages ||= {}

        if block
          name ||= "storage_#{@storages.keys.size}"
          @storages[name] = Backup::Configuration::Storage.new
          @storages[name].instance_eval &block
        end

        @storages
      end

      def server(name=nil,&block)
        @servers  ||= {}

        if block
          name ||= "server_#{@servers.keys.size}"
          @servers[name] = Backup::Configuration::Server.new
          @servers[name].instance_eval &block
        end

        @servers
      end

      def check(name=nil,&block)
        @check ||= {}

        if block
          name ||= "check_#{@check.keys.size}"
          @check[name] = Backup::Configuration::Check.new 
          @check[name].instance_eval &block
        end

        @check
      end
    end
  end
end
