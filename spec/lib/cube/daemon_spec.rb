require 'spec_helper'
require_relative '../../../lib/cube/daemon.rb'

describe Cube::Daemon do
  let(:api_client) { double }
  let(:app_name) { 'test-cube' }
  let(:config) do
    config = Cube::Daemon::Config.new('cube' => {
                                        'api_key' => 'some-api-key',
                                        'api_timeout' => 10,
                                        'api_url' => 'http://cube.domain.com'
                                      },
                                      'daemon' => {
                                        'app_name' => app_name
                                      },
                                      'scheduler' => {
                                        'frequency' => '0.3s',
                                        'interval' => '10s',
                                        'timeout' => '30s'
                                      })
    allow(config).to receive(:daemon_config).and_return(daemon_config)
    config
  end
  let(:daemon_config) do
    {
      multiple: false,
      backtrace: false,
      dir_mode: :normal,
      dir: '/tmp',
      monitor: false
    }
  end
  let(:handler) { double.as_null_object }
  let(:logger) { double }

  before(:each) do
    allow(Cube::Daemon).to receive(:config).and_return(config)
  end

  describe '#api_client' do
    it 'creates api client using config' do
      allow(Cube::Daemon).to receive(:logger).and_return(logger)
      allow(Cube::Daemon::CubeApiClient).to receive(:new).with(
        config['cube']['api_url'],
        config['cube']['api_key'],
        logger,
        config['cube']['api_timeout']
      ).and_return(api_client)
      expect(Cube::Daemon.api_client).to eql(api_client)
    end
  end

  describe '#logger' do
    let(:config) { { 'daemon' => { 'log' => logger_config, 'app_name' => app_name } } }

    before(:each) do
      Cube::Daemon.instance_variable_set(:@logger, nil)
    end

    context 'when logger type in config is file' do
      let(:file_name) { 'log.log' }
      let(:shift_age) { 'daily' }
      let(:logger_config) do
        {
          'logger' => 'file',
          'log_file' => file_name,
          'shift_age' => shift_age
        }
      end

      it 'creates regular logger' do
        expect(Logger).to receive(:new).with(file_name, shift_age).and_return(logger)
        expect(Cube::Daemon.logger).to eql(logger)
      end
    end

    context 'when logger type in config is syslog' do
      let(:logger_config) do
        {
          'logger' => 'syslog',
          'log_facility' => 'daemon'
        }
      end

      it 'creates syslogger' do
        expect(Syslogger).to receive(:new).with(app_name, Syslog::LOG_PID | Syslog::LOG_CONS, Syslog::LOG_DAEMON).and_return(logger)
        expect(Cube::Daemon.logger).to eql(logger)
      end
    end
  end

  describe '#run' do
    let(:config) do
      config = Cube::Daemon::Config.new('daemon' => { 'app_name' => 'test' })
      allow(config).to receive(:daemon_config).and_return({})
      config
    end

    before(:each) do
      allow(Cube::Daemon).to receive(:logger).and_return(logger)
      allow(Daemons).to receive(:run_proc)
    end

    it 'starts daemon' do
      Cube::Daemon.run(handler)
      expect(Daemons).to have_received(:run_proc)
    end

    it 'runs with scheduler' do
      allow(Daemons).to receive(:run_proc).and_yield
      expect(Cube::Daemon).to receive(:run_with_scheduler)
      Cube::Daemon.run(handler)
    end
  end

  describe '#run_with_scheduler' do
    let(:scheduler) { instance_double('Rufus::Scheduler').as_null_object }
    let(:daemon_config) { {} }

    before(:each) do
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
      allow(Cube::Daemon).to receive(:logger).and_return(logger)
      Cube::Daemon.instance_variable_set(:@scheduler, scheduler)
    end

    it 'schedules handler to run at intervals' do
      Cube::Daemon.run_with_scheduler(handler)
      expect(scheduler).to have_received(:interval).with(
        config['scheduler']['interval'],
        first: :immediately,
        overlap: false,
        timeout: config['scheduler']['timeout']
      )
    end

    it 'scheduler joins thread' do
      Cube::Daemon.run_with_scheduler(handler)
      expect(scheduler).to have_received(:join)
    end
  end

  describe '#scheduler' do
    context 'when no scheduler exists' do
      let(:scheduler) { instance_double('Rufus::Scheduler').as_null_object }

      before(:each) do
        Cube::Daemon.instance_variable_set(:@scheduler, nil)
        allow(Rufus::Scheduler).to receive(:new).with(frequency: config['scheduler']['frequency']).and_return(scheduler)
      end

      it 'configures new scheduler' do
        expect(Rufus::Scheduler).to receive(:new)
        # expect(Rufus::Scheduler).to receive(:new).with(frequency: config['scheduler']['frequency'])
        Cube::Daemon.scheduler
      end
    end

    context 'when scheduler exists' do
      let(:scheduler) { instance_double('Rufus::Scheduler').as_null_object }

      before(:each) do
        Cube::Daemon.instance_variable_set(:@scheduler, scheduler)
      end

      it 'does not create new scheduler instance' do
        expect(Rufus::Scheduler).to_not receive(:new)
        expect(Cube::Daemon.scheduler).to eq(scheduler)
      end
    end

    # it 'returns scheduler' do
    #  expect(Cube::Daemon.scheduler).to eq(scheduler)
    # end
  end
end
