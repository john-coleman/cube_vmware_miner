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
        @dns = dns
        @vms = {}
        @triage = {}
      end

      def dc
        @dc || initialize_dc
      end

      def dns
        @dns || initialize_dns
      end

      # Attempt to discover full valid FQDN using DNS and VM Name
      def enhance_vm_fqdn(vm, vmhash)
        vmhash[:domains], vmhash[:hostnames] = [], []
        vmhash[:vm_name], vmhash[:vmhname] = vm.summary.config[:name], parse_vm_name(vm.summary.config[:name])
        vmhash[:vmhname].downcase! if vmhash[:vmhname].is_a?(String)
        vmhash = query_dns_with_vm_hostname(vmhash)
        vmhash = query_dns_with_vm_ipv4(vmhash)
        vmhash = select_hostname(vmhash)
        vmhash = select_domain(vmhash)
        vmhash
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
              @logger.debug "Unrecognized childEntity #{child.class} #{child.name}"
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
        vmhash[:tools_status], vmhash[:tools_running_status] = vm.guest[:toolsStatus], vm.guest[:toolsRunningStatus]
        vmhash[:tools_version], vmhash[:tools_version_status] = vm.guest[:toolsVersion], vm.guest[:toolsVersionStatus]
        vmhash[:tools_version_status2] = vm.guest[:toolsVersionStatus2]
        vmhash[:ipv4_addresses] = parse_ipv4_addresses(vm)
        unless vm.guest.ipStack.empty?
          vmhash[:hostname] = vm.guest.ipStack.first.dnsConfig.hostName
          vmhash[:domain] = vm.guest.ipStack.first.dnsConfig.domainName
        end
        if vm.guest[:hostName]
          vmhash[:hostname] = parse_hostname(vm.guest[:hostName]) if !vmhash[:hostname] || vmhash[:hostname].empty?
          vmhash[:domain] = parse_domain(vm.guest[:hostName]) if !vmhash[:domain] || vmhash[:domain].empty?
        end
        if !vmhash[:domain] || !vmhash[:hostname] || vmhash[:domain].empty? || vmhash[:hostname].empty?
          enhance_vm_fqdn(vm, vmhash)
        end
        vmhash
      end

      def post_vm(vm_name, v)
        if v[:hostname] && v[:domain] && !v[:hostname].empty? && !v[:domain].empty?
          @logger.debug "VM #{vm_name} POST to API"
          response = @api_client.send_post_request('/api/devices', prepare_device_params(v))
          @logger.debug "VM #{vm_name} Updates: #{response}" unless JSON.parse(response).empty?
        else
          @triage[vm_name] = v
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

      def query_dns_with_vm_hostname(vmhash)
        hostname = vmhash[:hostname] || vmhash[:vmhname]
        @config['dns']['known_domains'].each do |dom|
          begin
            result = @dns.getaddresses("#{hostname}.#{dom}") if hostname && !hostname.empty?
            unless result.nil? || result.empty?
              if vmhash[:ipv4_addresses].any? { |int| interface_dns_a_record(int, result, "#{hostname}.#{dom}") }
                @logger.info "VM #{vmhash[:vm_name]}: Verified DNS A record #{hostname}.#{dom}"
              else
                @logger.warn "VM #{vmhash[:vm_name]}: Unverified DNS A record #{hostname}.#{dom}: Resolved to #{result.join(' ')}"
              end
              vmhash[:domains].push(dom.downcase).uniq
            end
          rescue Resolv::ResolvError => e
            @logger.debug e.exception
          end
        end
        vmhash
      end

      def query_dns_with_vm_ipv4(vmhash)
        vmhash[:ipv4_addresses].each do |int|
          begin
            @dns.getnames(int[:ipv4_address]).each do |dns_name|
              int[:ptr_records] << dns_name
              vmhash[:hostnames].push(parse_hostname(dns_name.downcase)).uniq
              vmhash[:domains].push(parse_domain(dns_name.downcase)).uniq
            end
          rescue Resolv::ResolvError => e
            @logger.debug e.exception
          end
        end if vmhash[:ipv4_addresses] && !vmhash[:ipv4_addresses].empty?
        vmhash
      end

      def run
        parse_folder(dc.vmFolder)
        @vms.each { |k, v| post_vm(k, v) } if @config['cube']['api_batch_post'] == true
        @logger.warn "Triage: #{@triage.keys.count} VMs: #{@triage.keys}"
        @triage.each { |k, v| @logger.debug "Triage #{k}: #{v.inspect}" }
      end

      def select_domain(vmhash)
        case
        when vmhash[:domains].empty?
          @logger.error "VM #{vmhash[:vm_name]}: Unable to reliably determine domain. Fix VMware Guest Tools and DNS Records."
        when vmhash[:domains].count == 1
          @logger.info "VM #{vmhash[:vm_name]}: Domain found through DNS: #{vmhash[:domains].first}"
          vmhash[:domain] = vmhash[:domains].first if !vmhash[:domain] || vmhash[:domain].empty?
        when vmhash[:domains].count > 1
          @logger.error "VM #{vmhash[:vm_name]}: Multiple Domains found through DNS: #{vmhash[:domains].inspect}"
        end
        vmhash
      end

      def select_hostname(vmhash)
        case
        when vmhash[:hostnames].empty?
          @logger.error "VM #{vmhash[:vm_name]}: Using VM Name parsed as #{vmhash[:vmhname]}: Fix VMware Guest Tools and DNS Records."
          vmhash[:hostname] = vmhash[:vmhname] if !vmhash[:hostname] || vmhash[:hostname].empty?
        when vmhash[:hostnames].count == 1
          @logger.info "VM #{vmhash[:vm_name]}: Hostname found through DNS: #{vmhash[:hostnames].first}"
          vmhash[:hostname] = vmhash[:hostnames].first unless vmhash[:hostname]
        when vmhash[:hostnames].count > 1
          @logger.error "VM #{vmhash[:vm_name]}: Multiple Hostnames found through DNS: #{vmhash[:hostnames].inspect}"
          if vmhash[:hostnames].include?(vmhash[:vmhname]) && (!vmhash[:hostname] || vmhash[:hostname].empty?)
            @logger.warn "VM #{vmhash[:vm_name]}: Selecting Hostname #{vmhash[:vmhname]} from multiple DNS results"
            vmhash[:hostname] = vmhash[:vmhname]
          end
        end
        vmhash
      end

      def vsphere
        @vsphere || initialize_vsphere
      end

      private

      def initialize_dc
        vsphere.serviceInstance.find_datacenter(@config['vmware']['datacenter']) || vsphere.serviceInstance.find_datacenter
      end

      def initialize_dns
        Resolv.new
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

      def interface_dns_a_record(int, result, fqdn)
        if result.include?(int[:ipv4_address])
          int[:a_records] = fqdn
        else
          false
        end
      end

      def map_os_guest_full_name(guest_full_name)
        mapping = { windows: ['Microsoft Windows Server 2008 R2 (64-bit)'],
                    linux: ['Ubuntu Linux (64-bit)'] }
        mapping.each_pair do |k, v|
          return k.to_s if v.include?(guest_full_name.to_s)
        end
        nil
      end

      def parse_domain(fqdn)
        /\A(?<hostname>[[:alnum:]\-]+)(\.(?<domain>[[:alnum:]\-.]+))?\z/.match(fqdn)[:domain]
      end

      def parse_hostname(fqdn)
        /\A(?<hostname>[[:alnum:]\-]+)(\.(?<domain>[[:alnum:]\-.]+))?\z/.match(fqdn)[:hostname]
      end

      def parse_ipv4_addresses(vm)
        ipv4_addresses = []
        if vm.guest[:toolsRunningStatus] == 'guestToolsRunning'
          vm.guest.net.each do |vnic|
            vnic[:ipAddress].each do |vnic_ip|
              ipv4_addresses << { a_records: [],
                                  ipv4_address: vnic_ip,
                                  mac_address: vnic[:macAddress],
                                  ptr_records: [] } if valid_ipv4_address(vm, vnic_ip)
            end
          end
        end
        ipv4_addresses
      end

      def parse_vm_name(vmname)
        result = /\A(?<vm_name>[[:alnum:]\-]+){1}(\.[[:alnum:]\-_]+)*\z/.match(vmname)
        (result && result.names.include?('vm_name')) ? result[:vm_name] : nil
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
