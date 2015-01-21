require 'logger'
require 'rest_client'
require 'spec_helper'
require_relative '../../../../lib/cube/daemon/vmware_miner.rb'

describe Cube::Daemon::VmwareMiner do
  let(:api_batch_post) { false }
  let(:api_client) { double }
  let(:api_response) { '{}' }
  let(:child_vm) do
    child_vm = spy(RbVmomi::VIM::VirtualMachine)
    allow(RbVmomi::VIM::VirtualMachine).to receive(:===).with(child_vm).and_return(true)
    allow(child_vm).to receive(:===).with(RbVmomi::VIM::VirtualMachine).and_return(true)
    allow(child_vm).to receive(:guest).and_return(child_vm_guest)
    allow(child_vm).to receive(:summary).and_return(child_vm_summary)
    child_vm
  end
  let(:child_vm_guest) do
    guest = spy(RbVmomi::VIM::GuestInfo)
    allow(guest).to receive(:net).and_return(child_vm_net)
    allow(guest).to receive(:ipStack).and_return([child_vm_guest_stack_info])
    allow(guest).to receive(:[]).with(:hostName).and_return(vm[:hostName])
    allow(guest).to receive(:[]).with(:toolsRunningStatus).and_return(vm[:toolsRunningStatus])
    allow(guest).to receive(:[]).with(:toolsStatus).and_return(vm[:toolsStatus])
    allow(guest).to receive(:[]).with(:toolsVersion).and_return(vm[:toolsVersion])
    allow(guest).to receive(:[]).with(:toolsVersionStatus).and_return(vm[:toolsVersionStatus])
    allow(guest).to receive(:[]).with(:toolsVersionStatus2).and_return(vm[:toolsVersionStatus2])
    guest
  end
  let(:child_vm_guest_stack_info) do
    stack_info = spy(RbVmomi::VIM::GuestStackInfo)
    allow(stack_info).to receive(:dnsConfig).and_return(child_vm_net_dns_config_info)
    stack_info
  end
  let(:child_vm_net) do
    net = { ipAddress: [vm[:ipv4_addresses].first[:ipv4_address]],
            macAddress: vm[:ipv4_addresses].first[:mac_address]
    }
    [net]
  end
  let(:child_vm_net_dns_config_info) do
    dns_config = spy(RbVmomi::VIM::NetDnsConfigInfo)
    allow(dns_config).to receive(:hostName).and_return(vm[:hostName])
    allow(dns_config).to receive(:domainName).and_return(vm[:domainName])
    dns_config
  end
  let(:child_vm_summary) do
    summary = spy(RbVmomi::VIM::VirtualMachineSummary)
    allow(summary).to receive(:config).and_return(child_vm_summary_config)
    summary
  end
  let(:child_vm_summary_config) do
    config = spy(RbVmomi::VIM::VirtualMachineConfigInfo)
    allow(config).to receive(:[]).with(:guestFullName).and_return(vm[:guestFullName])
    allow(config).to receive(:[]).with(:name).and_return(vm[:name])
    config
  end
  let(:child_folder) do
    folder = spy(RbVmomi::VIM::Folder, childEntity: [])
    allow(RbVmomi::VIM::Folder).to receive(:===).with(folder).and_return(true)
    allow(folder).to receive(:===).with(RbVmomi::VIM::Folder).and_return(true)
    folder
  end
  let(:child_unrecognized) { double }
  let(:child_unrecognized_name) do
    child_unrecognized_name = spy(RbVmomi::VIM::VirtualApp)
    allow(child_unrecognized_name).to receive(:name).and_return('Unrecognized childEntity Class')
    child_unrecognized_name
  end
  let(:child_entity) { [] }
  let(:config) do
    {
      'cube' => {
        'api_batch_post' => api_batch_post,
        'api_key' => 'some-api-key',
        'api_timeout' => 10,
        'api_url' => 'http://cube.example.com'
      },
      'dns' => {
        'known_domains' => dns_known_domains
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
  let(:dns) { spy(Resolv) }
  let(:dns_addresses) { [] }
  let(:dns_known_domains) { ['example.com'] }
  let(:dns_names) { [] }
  let(:folder) { double }
  let(:logger) { spy(Logger) }
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
  let(:triage) { {} }
  let(:vm) do
    {
      name: 'DummyVM1',
      guestFullName: 'Ubuntu Linux (64-bit)',
      hostName: 'dummy-vm-1.example.com',
      domainName: 'example.com',
      ipv4_addresses: [
        { ipv4_address: '1.2.3.2', mac_address: '01:23:45:67:89:02' }
      ],
      toolsRunningStatus: 'guestToolsRunning',
      toolsStatus: 'toolsOk'
    }
  end
  let(:vmhash) do
    {
      hostname: 'DummyVM3',
      hostnames: [],
      domains: [],
      ipv4_addresses: [
        {
          a_records: [],
          ipv4_address: '1.2.3.3',
          mac_address: '00:11:22:33:33:33',
          ptr_records: []
        }
      ]
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
    allow(dns).to receive(:getaddresses).and_return(dns_addresses)
    allow(dns).to receive(:getnames).and_return(dns_names)
    subject.instance_variable_set(:@api_client, api_client)
    subject.instance_variable_set(:@dc, dc)
    subject.instance_variable_set(:@dns, dns)
    subject.instance_variable_set(:@triage, triage)
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
      context 'and responds to :name' do
        let(:child_entity) { [child_unrecognized_name] }

        it 'logs debug message' do
          expect(logger).to receive(:debug).with(/Unrecognized childEntity.*Unrecognized childEntity Class/).at_least(:once)
          subject.parse_folder(folder)
        end
      end

      context 'and does not respond to :name' do
        let(:child_entity) { [child_unrecognized] }

        it 'logs debug message' do
          expect(logger).to receive(:debug).with(/Unknown childEntity/).at_least(:once)
          subject.parse_folder(folder)
        end
      end
    end
  end

  describe '#parse_vm' do
    it 'adds vm to vms collection' do
      expect { subject.parse_vm(child_vm) }.to change { vms.keys.count }.by(1)
    end

    it 'adds vm_name key to vmhash' do
      subject.parse_vm(child_vm)
      expect(vms).to have_key(child_vm_summary_config[:name])
    end

    context 'recognised os' do
      it 'adds os key to vmhash' do
        subject.parse_vm(child_vm)
        expect(vms[child_vm_summary_config[:name]][:os]).to eq 'linux'
      end
    end

    context 'unrecognised os' do
      it 'adds os key to vmhash with null value' do
        vm[:guestFullName] = 'NeXTSTEP 3.3'
        subject.parse_vm(child_vm)
        expect(vms[child_vm_summary_config[:name]][:os]).to eq nil
      end
    end

    context 'guest tools not installed' do
      let(:vm) do
        {
          name: 'NoToolsVM1',
          guestFullName: 'Ubuntu Linux (64-bit)',
          ipv4_addresses: [
            { ipv4_address: '1.2.4.1', mac_address: '01:23:45:67:89:02' }
          ]
        }
      end

      it 'calls enhance_vm_fqdn' do
        expect(subject).to receive(:enhance_vm_fqdn)
        subject.parse_vm(child_vm)
      end

      it 'adds hostname key to vmhash with normalized VM name value' do
        subject.parse_vm(child_vm)
        expect(vms[child_vm_summary_config[:name]][:hostname]).to eq 'notoolsvm1'
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

  describe '#enhance_vm_fqdn' do
    context 'for a cleanly-named VM' do
      it 'parses VM name to vmhname' do
        vm[:name] = 'Cleanly-Named.example.com'
        subject.enhance_vm_fqdn(child_vm, vmhash)
        expect(vmhash[:vm_name]).to eq vm[:name]
        expect(vmhash[:vmhname]).to eq 'cleanly-named'
      end
    end

    context 'for an uncleanly-named VM' do
      it 'parses VM name to vmhname' do
        vm[:name] = '(NOT A) Cleanly-Nameed.example.com VM'
        subject.enhance_vm_fqdn(child_vm, vmhash)
        expect(vmhash[:vm_name]).to eq vm[:name]
        expect(vmhash[:vmhname]).to eq nil
      end
    end

    it 'calls #query_dns_with_vm_hostname' do
      expect(subject).to receive(:query_dns_with_vm_hostname).and_return(vmhash)
      subject.enhance_vm_fqdn(child_vm, vmhash)
    end

    it 'calls #query_dns_with_vm_ipv4' do
      expect(subject).to receive(:query_dns_with_vm_ipv4).and_return(vmhash)
      subject.enhance_vm_fqdn(child_vm, vmhash)
    end

    it 'calls #select_hostname' do
      expect(subject).to receive(:select_hostname).and_return(vmhash)
      subject.enhance_vm_fqdn(child_vm, vmhash)
    end

    it 'calls #select_domain' do
      expect(subject).to receive(:select_domain).and_return(vmhash)
      subject.enhance_vm_fqdn(child_vm, vmhash)
    end
  end

  describe '#query_dns_with_vm_hostname' do
    it 'queries dns for hostname' do
      expect(dns).to receive(:getaddresses)
      subject.query_dns_with_vm_hostname(vmhash)
    end

    context 'fqdn returns IP' do
      before(:each) do
        allow(dns).to receive(:getaddresses).and_return([vmhash[:ipv4_addresses][0][:ipv4_address]])
      end

      it 'adds fqdn to vmhash ipv4_address a_records' do
        subject.query_dns_with_vm_hostname(vmhash)
        expect(vmhash[:ipv4_addresses][0][:a_records]).to include("#{vmhash[:hostname]}.example.com")
      end

      it 'adds domain to vmhash domains' do
        subject.query_dns_with_vm_hostname(vmhash)
        expect(vmhash[:domains]).to include('example.com')
      end
    end
  end

  describe '#query_dns_with_vm_ipv4' do
    it 'queries dns for ipv4' do
      expect(dns).to receive(:getnames)
      subject.query_dns_with_vm_ipv4(vmhash)
    end

    context 'ipv4 returns names' do
      before(:each) do
        allow(dns).to receive(:getnames).and_return(["#{vmhash[:hostname]}.example.com"])
      end

      it 'adds fqdn to vmhash ipv4_address ptr_records' do
        subject.query_dns_with_vm_ipv4(vmhash)
        expect(vmhash[:ipv4_addresses][0][:ptr_records]).to include("#{vmhash[:hostname]}.example.com")
      end

      it 'adds domain to vmhash domains' do
        subject.query_dns_with_vm_ipv4(vmhash)
        expect(vmhash[:domains]).to include('example.com')
      end
    end

  end

  describe '#select_domain' do
    let(:vmhash) { { domain: 'example.com', domains: [], vm_name: 'DummyVM3' } }

    context 'no domains found' do
      it 'logs error message' do
        expect(logger).to receive(:error)
        subject.select_domain(vmhash)
      end
    end

    context 'single domain found' do
      context 'vmhash domain key defined' do
        let(:vmhash) { { domain: 'example.com', domains: ['example1.com'], vm_name: 'DummyVM3' } }

        it 'logs info message' do
          expect(logger).to receive(:info)
          subject.select_domain(vmhash)
        end

        it 'does not change vmhash domain key' do
          subject.select_domain(vmhash)
          expect(vmhash[:domain]).to eq 'example.com'
        end
      end

      context 'vmhash domain key not defined' do
        let(:vmhash) { { domains: ['example1.com'], vm_name: 'DummyVM3' } }

        it 'logs info message' do
          expect(logger).to receive(:info)
          subject.select_domain(vmhash)
        end

        it 'sets vmhash domain key' do
          subject.select_domain(vmhash)
          expect(vmhash[:domain]).to eq 'example1.com'
        end
      end
    end

    context 'multiple domains found' do
      let(:vmhash) { { domains: ['example.com', 'example2.com'], vm_name: 'DummyVM3' } }

      it 'logs error message' do
        expect(logger).to receive(:error)
        subject.select_domain(vmhash)
      end

      it 'does not change vmhash domain key' do
        subject.select_domain(vmhash)
        expect(vmhash).to_not have_key(:domain)
      end
    end
  end

  describe '#select_hostname' do
    let(:vmhash) { { hostnames: [], vmhname: 'dummyvm3', vm_name: 'DummyVM3' } }

    context 'no hostnames found' do
      it 'logs error message' do
        expect(logger).to receive(:error)
        subject.select_hostname(vmhash)
      end

      it 'sets vmhash hostname to vmhname' do
        subject.select_hostname(vmhash)
        expect(vmhash[:hostname]).to eq vmhash[:vmhname]
      end
    end

    context 'single hostname found' do
      context 'vmhash hostname key defined' do
        let(:vmhash) { { hostnames: ['dummyvm4'], hostname: 'dummyvm3', vmhname: 'dummyvm3', vm_name: 'DummyVM3' } }

        it 'logs info message' do
          expect(logger).to receive(:info)
          subject.select_hostname(vmhash)
        end

        it 'does not change vmhash hostname key' do
          subject.select_hostname(vmhash)
          expect(vmhash[:hostname]).to eq 'dummyvm3'
        end
      end

      context 'vmhash hostname key not defined' do
        let(:vmhash) { { hostnames: ['dummyvm3'], vmhname: 'dummyvm3', vm_name: 'DummyVM3' } }

        it 'logs info message' do
          expect(logger).to receive(:info)
          subject.select_hostname(vmhash)
        end

        it 'sets vmhash hostname key' do
          subject.select_hostname(vmhash)
          expect(vmhash[:hostname]).to eq 'dummyvm3'
        end
      end
    end

    context 'multiple hostnames found' do
      let(:vmhash) { { hostnames: %w(dummyvm3 othervm), vmhname: 'dummyvm3', vm_name: 'DummyVM3' } }

      it 'logs error message' do
        expect(logger).to receive(:error)
        subject.select_hostname(vmhash)
      end

      context 'with matching parsed VM name' do
        it 'logs warning message' do
          expect(logger).to receive(:warn)
          subject.select_hostname(vmhash)
        end

        it 'sets vmhash hostname key' do
          subject.select_hostname(vmhash)
          expect(vmhash[:hostname]).to eq(vmhash[:vmhname])
        end
      end

      context 'without matching parsed VM name' do
        let(:vmhash) { { hostnames: %w(dummyvm4 othervm), vmhname: 'dummyvm3', vm_name: 'DummyVM3' } }

        it 'does not log warning message' do
          expect(logger).to_not receive(:warn)
          subject.select_hostname(vmhash)
        end

        it 'does not set vmhash hostname key' do
          subject.select_hostname(vmhash)
          expect(vmhash).to_not have_key(:hostname)
        end
      end
    end
  end
end
