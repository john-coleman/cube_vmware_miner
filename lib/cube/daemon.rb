require 'daemons'
require 'logger'
require 'rufus-scheduler'
require 'syslogger'
require_relative 'daemon/config.rb'
require_relative 'daemon/cube_api_client.rb'

module Cube
  module Daemon
    class << self
      attr_reader :config

      def load_config(filename)
        @config = Cube::Daemon::Config.load(filename)
      end

      def run(handler)
        Daemons.run_proc(config['daemon']['app_name'], config.daemon_config) do
          run_with_scheduler(handler)
        end
      end

      def run_with_scheduler(handler)
        scheduler.interval(config['scheduler']['interval'], first: :immediately, overlap: false, timeout: config['scheduler']['timeout']) do
          time_start = Time.now.utc
          logger.warn "Starting job at #{time_start}"
          handler.run
          time_finish = Time.now.utc
          logger.warn "Completed job at #{time_finish} in #{time_finish - time_start} secs"
        end
        scheduler.join
      rescue => e
        logger.error e.inspect
        retry
      end

      def logger
        @logger ||= initialize_logger
      end

      def scheduler
        @scheduler ||= initialize_scheduler
      end

      def api_client
        Cube::Daemon::CubeApiClient.new(config['cube']['api_url'], config['cube']['api_key'], Cube::Daemon.logger, config['cube']['api_timeout'])
      end

      private

      def initialize_logger
        log_config = config['daemon']['log']
        logger = if log_config
                   if log_config['logger'] == 'file'
                     Logger.new(log_config['log_file'], log_config['shift_age'])
                   elsif log_config['logger'] == 'syslog'
                     facility = Syslog.const_get("LOG_#{log_config['log_facility'].upcase}")
                     Syslogger.new(config['daemon']['app_name'], Syslog::LOG_PID | Syslog::LOG_CONS, facility)
                   end
                 end
        logger || Logger.new(STDOUT)
      end

      def initialize_scheduler
        Rufus::Scheduler.new(frequency: config['scheduler']['frequency'])
      end
    end
  end
end

at_exit do
  if Cube::Daemon.config
    Cube::Daemon.logger.info "Stopped at #{Time.now}"
    if $ERROR_INFO && !($ERROR_INFO.is_a?(SystemExit) && $ERROR_INFO.success?)
      Cube::Daemon.logger.error $ERROR_INFO
      Cube::Daemon.logger.error $ERROR_INFO.backtrace.join("\n") if $ERROR_INFO.respond_to? :backtrace
    end
  end
end
