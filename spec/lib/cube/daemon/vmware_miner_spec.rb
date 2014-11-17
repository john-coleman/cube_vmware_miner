require 'logger'
require 'spec_helper'
require_relative '../../../../lib/cube/daemon/vmware_miner.rb'

describe Cube::Daemon::VmwareMiner do
  let(:api_client) { double }
  let(:api_response) { '{}' }
  let(:child_vm) do
    vm = instance_double(RbVmomi::VIM::VirtualMachine).as_null_object
    allow(RbVmomi::VIM::VirtualMachine).to receive(:===).with(vm).and_return(true)
    allow(vm).to receive(:===).with(RbVmomi::VIM::VirtualMachine).and_return(true)
    vm
  end
  let(:child_folder) do
    folder = instance_double(RbVmomi::VIM::Folder, childEntity: []).as_null_object
    allow(RbVmomi::VIM::Folder).to receive(:===).with(folder).and_return(true)
    allow(folder).to receive(:===).with(RbVmomi::VIM::Folder).and_return(true)
    folder
  end
  let(:child_unrecognized) { double }
  let(:child_entity) { [] }
  let(:config) do
    {
      'cube' => {
        'api_batch_post' => true,
        'api_key' => 'some-api-key',
        'api_timeout' => 10,
        'api_url' => 'http://cube.example.com'
      },
      'vmware' => {
        'host' => 'vcenter.example.com',
        'insecure' => true,
        'password' => 'password',
        'path' => '/sdk',
        'port' => 443,
        'ssl' => true,
        'user' => 'username'
      }
    }
  end
  let(:dc) { double }
  let(:folder) { double }
  let(:logger) { instance_double(Logger).as_null_object }
  let(:message) do
    {
      'hostname' => 'dummy-vm-1',
      'domain' => 'example.com',
      'ipv4_addresses' => [
        { 'ipv4_address' => '1.2.3.4', 'mac_address' => '01:23:45:67:89:10' }
      ],
      'os' => 'windows'
    }
  end
  let(:vms) do
    {
      'DummyVM1' => {
        hostname: 'dummy-vm-1',
        domain: 'example.com',
        ipv4_addresses: [
          { ipv4_address: '1.2.3.4', mac_address: '01:23:45:67:89:10' }
        ],
        os: 'windows',
        tools_running_status: 'guestToolsRunning',
        tools_status: 'toolsOk'
      }
    }
  end
  let(:vsphere) { double }
  subject { described_class.new(config, api_client, logger) }

  before(:each) do
    allow(api_client).to receive(:send_post_request).and_return(api_response)
    allow(folder).to receive(:childEntity).and_return(child_entity)
    allow(dc).to receive(:vmFolder).and_return(folder)
    subject.instance_variable_set(:@api_client, api_client)
    subject.instance_variable_set(:@dc, dc)
    subject.instance_variable_set(:@vms, vms)
    subject.instance_variable_set(:@vsphere, vsphere)
  end

  describe '#run' do
    it 'calls #parse_folder' do
      expect(subject).to receive(:parse_folder).with(dc.vmFolder)
      subject.run
    end

    context 'without any vms parsed' do
      let(:vms) { {} }

      it 'does not make api requests' do
        expect(api_client).to_not receive(:send_post_request)
        expect(logger).to_not receive(:error)
        subject.run
      end
    end

    context 'with at least one vm parsed' do
      it 'sends vms as requests to api' do
        expect(subject).to receive(:post_vm)
        subject.run
      end
    end
  end

  describe '#parse_folder' do
    context 'when are are no children' do
      let(:child_entity) { [] }

      it 'processes each childEntity' do
        allow(child_entity).to receive(:each)
        expect(child_entity).to receive(:each)
        expect(subject).to_not receive(:parse_vm)
        subject.parse_folder(folder)
      end
    end

    context 'when child is VirtualMachine' do
      let(:child_entity) { [child_vm] }

      it 'processes with parse_vm' do
        expect(subject).to receive(:parse_vm).exactly(1)
        subject.parse_folder(folder)
      end

      context 'when API batch post enabled' do
        it 'calls #post_vm'
      end

    end

    context 'when child is Folder' do
      let(:child_entity) { [child_folder] }

      it 'processes with parse_folder' do
        subject.parse_folder(folder)
        expect(child_folder).to have_received(:childEntity)
      end
    end

    context 'when child is not recognised' do
      let(:child_entity) { [child_unrecognized] }
      it 'logs debug message' do
        expect(logger).to receive(:debug)
        subject.parse_folder(folder)
      end
    end
  end

  describe '#parse_vm' do
    it 'adds vm to vms collection'
    # it 'adds vm to vms collection' do
    #   expect{subject.parse_folder(folder)}.to change{vms.keys.count}.by(1)
    # end
    it 'adds vm_name key to vmhash'

    context 'recognised os' do
      it 'adds os key to vmhash'
    end

    context 'unrecognised os' do
      it 'does not add os key to vmhash'
    end
  end

  describe '#post_vm' do
    context 'with hostname and domain present' do
      it 'posts vm to api'
      # it 'adds vm to vms collection' do
      #   expect{subject.parse_folder(folder)}.to change{vms.keys.count}.by(1)
      # end
    end

    context 'when response not empty' do
      it 'logs debug message'
    end

    context 'without hostname and domain present' do
      it 'logs error message'
    end
  end
end
