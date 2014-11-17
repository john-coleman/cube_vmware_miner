require 'yaml'

module Cube
  module Daemon
    class Config
      def self.load(config_file)
        config = read_config(config_file)
        new(config)
      end

      def initialize(config)
        @config = config
      end

      def [](value)
        @config[value]
      end

      def daemon_config
        {
          multiple: @config['daemon']['daemons_count'].to_i > 1,
          backtrace: @config['daemon']['backtrace'],
          dir_mode: @config['daemon']['dir_mode'].to_sym,
          dir: "#{File.expand_path(@config['daemon']['dir'])}",
          monitor: @config['daemon']['monitor']
        }
      end

      def self.read_config(config_file)
        env = ENV['ENVIRONMENT'] || 'development'
        YAML.load_file(config_file)[env]
      end
    end
  end
end
