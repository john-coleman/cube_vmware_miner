require 'spec_helper'
require_relative '../../../../lib/cube/daemon/config.rb'
require 'fakefs/safe'

describe Cube::Daemon::Config do
  subject { described_class.new config }
  let(:config) { { 'daemon' => daemons_config, 'aws' => {} } }
  let(:daemons_config) { { 'daemons_count' => daemons_count, 'dir' => file, 'dir_mode' => 'dir' } }
  let(:daemons_count) { 1 }
  let(:file) { 'here' }

  context '.load' do
    before(:all) do
      FakeFS.activate!
    end

    after(:all) do
      FakeFS.deactivate!
    end

    before(:each) do
      File.open(file, 'w') do |file|
        file.puts YAML.dump(environment => config)
      end
      stub_const('ENV',  'ENVIRONMENT' => environment)
    end

    subject { described_class.load(file) }
    let(:environment) { 'development' }

    it 'uses part of config for current environment' do
      expect(subject['daemon']).to eq(daemons_config)
    end
  end

  context '#daemons_config' do
    it 'sets dir_mode value from config' do
      expect(subject.daemon_config[:dir_mode]).to eq(:dir)
    end

    context 'if daemons_count is not in config' do
      let(:daemon_config) { { 'dir' => file, 'dir_mode' => 'dir' } }

      it 'sets multiple to false' do
        expect(subject.daemon_config[:multiple]).to be_falsey
      end
    end

    context 'if daemons_count equals 1' do
      let(:daemons_count) { 1 }

      it 'sets multiple to false' do
        expect(subject.daemon_config[:multiple]).to be_falsey
      end
    end

    context 'if daemons_count is 2' do
      let(:daemons_count) { 2 }

      it 'sets multiple to true' do
        expect(subject.daemon_config[:multiple]).to be_truthy
      end
    end
  end
end
