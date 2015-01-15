require 'logger'
require 'rest_client'
require 'spec_helper'
require_relative '../../../../lib/cube/daemon/vmware_miner.rb'

describe Cube::Daemon::VmwareMiner do
  let(:api_batch_post) { false }
  let(:api_client) { double }
  let(:api_response) { '{}' }
  let(:child_vm) do
    vm = instance_double(RbVmomi::VIM::VirtualMachine).as_null_object
    allow(RbVmomi::VIM::VirtualMachine).to receive(:===).with(vm).and_return(true)
    allow(vm).to receive(:===).with(RbVmomi::VIM::VirtualMachine).and_return(true)
    vm
  end
  let(:child_vm_config) do
    config = instance_double(RbVmomi::VIM::VirtualMachineConfigInfo).as_null_object
    allow(config).to receive(:[]).with(:guestFullName).and_return(vm[:guestFullName])
    allow(config).to receive(:[]).with(:name).and_return(vm[:name])
    config
  end
  let(:child_vm_guest) do
    guest = instance_double(RbVmomi::VIM::GuestInfo).as_null_object
    allow(guest).to receive(:net).and_return(child_vm_net)
    allow(guest).to receive(:[]).with(:toolsRunningStatus).and_return(vm[:toolsRunningStatus])
    allow(guest).to receive(:[]).with(:toolsStatus).and_return(vm[:toolsStatus])
    allow(guest).to receive(:[]).with(:hostName).and_return(vm[:hostName])
    guest
  end
  let(:child_vm_net) do
    net = { ipAddress: [vm[:ipv4_addresses].first[:ipv4_address]],
            macAddress: vm[:ipv4_addresses].first[:mac_address]
    }
    [net]
  end
  let(:child_vm_summary) do
    summary = instance_double(RbVmomi::VIM::VirtualMachineSummary).as_null_object
    allow(summary).to receive(:config).and_return(child_vm_config)
    summary
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
        'api_batch_post' => api_batch_post,
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
  let(:vm) do
    {
      name: 'DummyVM1',
      guestFullName: 'Ubuntu Linux (64-bit)',
      hostName: 'dummy-vm-1.example.com',
      ipv4_addresses: [
        { ipv4_address: '1.2.3.2', mac_address: '01:23:45:67:89:02' }
      ],
      toolsRunningStatus: 'guestToolsRunning',
      toolsStatus: 'toolsOk'
    }
  end
  let(:vms) do
    {
      'DummyVM2' => {
        hostname: 'dummy-vm-2',
        domain: 'example.com',
        ipv4_addresses: [
          { ipv4_address: '1.2.3.2', mac_address: '01:23:45:67:89:02' }
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
    before(:each) do
      allow(subject).to receive(:post_vm)
    end

    it 'calls #parse_folder' do
      expect(subject).to receive(:parse_folder).with(dc.vmFolder)
      subject.run
    end

    it 'does not make api requests' do
      expect(api_client).to_not receive(:send_post_request)
      subject.run
    end

    context 'without parsed vm' do
      let(:vms) { {} }

      it 'does not make api requests' do
        expect(api_client).to_not receive(:send_post_request)
        subject.run
      end
    end

    context 'with api_batch_post enabled' do
      let(:api_batch_post) { true }

      it 'makes api requests' do
        expect(subject).to receive(:post_vm)
        subject.run
      end
    end
  end

  describe '#parse_folder' do
    before(:each) do
      allow(subject).to receive(:post_vm)
    end

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

      it 'calls #post_vm' do
        expect(subject).to receive(:post_vm).exactly(:once)
        subject.parse_folder(folder)
      end

      context 'when API batch post enabled' do
        let(:api_batch_post) { true }

        it 'does not call #post_vm' do
          expect(subject).to_not receive(:post_vm)
          subject.parse_folder(folder)
        end
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
    let(:child_vm) do
      vm = instance_double(RbVmomi::VIM::VirtualMachine).as_null_object
      allow(RbVmomi::VIM::VirtualMachine).to receive(:===).with(vm).and_return(true)
      allow(vm).to receive(:===).with(RbVmomi::VIM::VirtualMachine).and_return(true)
      allow(vm).to receive(:guest).and_return(child_vm_guest)
      allow(vm).to receive(:summary).and_return(child_vm_summary)
      vm
    end

    it 'adds vm to vms collection' do
      expect { subject.parse_vm(child_vm) }.to change { vms.keys.count }.by(1)
    end

    it 'adds vm_name key to vmhash' do
      subject.parse_vm(child_vm)
      expect(vms).to have_key(child_vm_config[:name])
    end

    context 'recognised os' do
      it 'adds os key to vmhash' do
        subject.parse_vm(child_vm)
        expect(vms[child_vm_config[:name]][:os]).to eq 'linux'
      end
    end

    context 'unrecognised os' do
      it 'does not add os key to vmhash' do
        vm[:guestFullName] = 'NeXTSTEP 3.3'
        subject.parse_vm(child_vm)
        expect(vms[child_vm_config[:name]]).to_not have_key(:os)
      end
    end
  end

  describe '#post_vm' do
    it 'posts vm to api' do
      expect(api_client).to receive(:send_post_request)
      subject.post_vm('DummyVM2', vms['DummyVM2'])
    end

    context 'when response not empty' do
      let(:api_response) { '{ "this":"changed" }' }

      it 'logs debug message' do
        expect(logger).to receive(:debug)
        subject.post_vm('DummyVM2', vms['DummyVM2'])
      end
    end

    context 'when response not successful' do
      let(:http_code) { 500 }
      let(:response) { 'oops' }
      before(:each) do
        allow_any_instance_of(RestClient::Exception).to receive_messages(http_code: http_code,
                                                                         response: response)
        allow(api_client).to receive(:send_post_request).and_raise(RestClient::Exception)
      end

      context 'and HTTP 500' do
        it 'logs error and debug message' do
          expect(logger).to receive(:error)
          expect(logger).to receive(:debug).exactly(:twice)
          subject.post_vm('DummyVM2', vms['DummyVM2'])
        end
      end

      context 'and HTTP 400' do
        let(:http_code) { 400 }
        it 'logs error message' do
          expect(logger).to receive(:error)
          expect(logger).to receive(:debug).exactly(:once)
          subject.post_vm('DummyVM2', vms['DummyVM2'])
        end
      end
    end

    context 'without hostname and domain present' do
      it 'logs error message' do
        expect(logger).to receive(:error)
        subject.post_vm('DummyVM2', {})
      end

      it 'does not post vm to api' do
        expect(api_client).to_not receive(:send_post_request)
        subject.post_vm('DummyVM2', {})
      end
    end
  end
end
