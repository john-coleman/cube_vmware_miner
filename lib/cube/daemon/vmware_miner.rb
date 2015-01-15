require 'ipaddr'
require 'json'
require 'rbvmomi'
require 'rest_client'

module Cube
  module Daemon
    class VmwareMiner
      def initialize(config, api_client, logger)
        @config = config
        @api_client = api_client
        @logger = logger
        @vms = {}
      end

      def run
        parse_folder(dc.vmFolder)
        @vms.each { |k, v| post_vm(k, v) } if @config['cube']['api_batch_post'] == true
      end

      def parse_folder(folder)
        folder.childEntity.each do |child|
          case child
          when RbVmomi::VIM::VirtualMachine
            vmhash = parse_vm(child)
            post_vm(child.name, vmhash) unless @config['cube']['api_batch_post'] == true
          when RbVmomi::VIM::Folder
            @logger.debug 'Folder found - recursing'
            parse_folder(child)
          else
            if child.respond_to?(:name)
              @logger.debug "Unknown childEntity #{child.class} #{child.name}"
            else
              @logger.debug "Unknown childEntity #{child.class}"
            end
          end
        end
        @logger.debug "#{@vms.length} VMs: #{@vms.keys}"
      end

      def parse_vm(vm)
        vmhash = @vms[vm.summary.config[:name]] = {}
        vmhash[:os] = map_os_guest_full_name(vm.summary.config[:guestFullName]) if map_os_guest_full_name(vm.summary.config[:guestFullName])
        vmhash[:tools_status] = vm.guest[:toolsStatus]
        vmhash[:tools_running_status] = vm.guest[:toolsRunningStatus]
        vmhash[:hostname] = parse_hostname(vm)
        vmhash[:domain] = parse_domain(vm)
        vmhash[:ipv4_addresses] = parse_ipv4_addresses(vm)
        vmhash
      end

      def post_vm(vm_name, v)
        if v[:hostname] && v[:domain]
          @logger.debug "VM #{vm_name} POST to API"
          response = @api_client.send_post_request('/api/devices', prepare_device_params(v))
          @logger.debug "VM #{vm_name} Updates: #{response}" unless JSON.parse(response).empty?
        else
          @logger.error "VM #{vm_name} FQDN: #{v[:hostname]}.#{v[:domain]}, GuestTools: #{v[:tools_status]}, GuestToolsRunning: #{v[:tools_running_status]}"
        end
      rescue ::RestClient::Exception => e
        if e.http_code >= 500
          @logger.error "VM #{vm_name} #{e.message}: #{e.response.split(/\n/).values_at(0, 5).join(':').gsub(/\(\) /, '')}"
          @logger.debug "VM #{vm_name} #{e.message}: #{e.response}"
        else
          @logger.error "VM #{vm_name} #{e.message}: #{e.response}"
        end
      end

      def dc
        @dc || initialize_dc
      end

      def vsphere
        @vsphere || initialize_vsphere
      end

      private

      def initialize_dc
        vsphere.serviceInstance.find_datacenter(@config['vmware']['datacenter']) || vsphere.serviceInstance.find_datacenter
      end

      def initialize_vsphere
        RbVmomi::VIM.connect(host: @config['vmware']['host'],
                             insecure: @config['vmware']['insecure'] || false,
                             password: @config['vmware']['password'],
                             path: @config['vmware']['path'] || 'sdk',
                             port: @config['vmware']['port'] || 443,
                             ssl: @config['vmware']['ssl'] || true,
                             user: @config['vmware']['user']
                            )
      end

      def map_os_guest_full_name(guest_full_name)
        mapping = { windows: ['Microsoft Windows Server 2008 R2 (64-bit)'],
                    linux: ['Ubuntu Linux (64-bit)'] }
        mapping.each_pair do |k, v|
          return k.to_s if v.include?(guest_full_name.to_s)
        end
        nil
      end

      def parse_domain(vm)
        if vm.guest[:toolsRunningStatus] == 'guestToolsRunning' && vm.guest[:hostName]
          /\A(?<hostname>[\w\-]+)(\.(?<domain>[\w\-.]+))?\z/.match(vm.guest[:hostName])[:domain]
        else
          nil
        end
      end

      def parse_hostname(vm)
        if vm.guest[:toolsRunningStatus] == 'guestToolsRunning' && vm.guest[:hostName]
          /\A(?<hostname>[\w\-]+)(\.(?<domain>[\w\-.]+))?\z/.match(vm.guest[:hostName])[:hostname]
        else
          nil
        end
      end

      def parse_ipv4_addresses(vm)
        ipv4_addresses = []
        if vm.guest[:toolsRunningStatus] == 'guestToolsRunning'
          vm.guest.net.each do |vnic|
            vnic[:ipAddress].each do |vnic_ip|
              ipv4_addresses << { ipv4_address: vnic_ip, mac_address: vnic[:macAddress] } if valid_ipv4_address(vm, vnic_ip)
            end
          end
        end
        ipv4_addresses
      end

      def prepare_device_params(vmhash)
        vmhash.select do |k, _v|
          %w(hostname domain os pci_scope ipv4_addresses).include?(k.to_s)
        end
      end

      def valid_ipv4_address(vm, ip_address)
        return false if /\A127\.0\./.match(ip_address) || /\A169\./.match(ip_address)
        if IPAddr.new(ip_address).ipv4?
          true
        else
          @logger.warn "#{vm.summary.config[:name]}: #{ip_address} is not a valid IPv4 Address"
          false
        end
      rescue IPAddr::InvalidAddressError
        @logger.warn "#{vm.summary.config[:name]}: #{ip_address} is not a valid IPv4 Address"
        false
      end
    end
  end
end
