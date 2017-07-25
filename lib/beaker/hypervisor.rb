[ 'host_prebuilt_steps' ].each do |lib|
  require "beaker/#{lib}"
end

module Beaker
  #The Beaker class that interacts to all the supported hypervisors
  class Hypervisor
    include HostPrebuiltSteps

    #Generates an array with all letters a thru z and numbers 0 thru 9
    CHARMAP = ('a'..'z').to_a + ('0'..'9').to_a

    #Hypervisor creator method.  Creates the appropriate hypervisor class object based upon
    #the provided hypervisor type selected, then provisions hosts with hypervisor.
    #@param [String] type The type of hypervisor to create - one of aix, solaris, vsphere, fusion,
    #                     blimpy, vcloud or vagrant
    #@param [Array<Host>] hosts_to_provision The hosts to be provisioned with the selected hypervisor
    #@param [Hash] options options Options to alter execution
    #@option options [String] :host_name_prefix (nil) Prefix host name if set
    def self.create(type, hosts_to_provision, options)
      @logger = options[:logger]
      @logger.notify("Beaker::Hypervisor, found some #{type} boxes to create")

      hyper_class = case type
        when /^aix$/
          Beaker::Aixer
        when /^solaris$/
          Beaker::Solaris
        when /^docker$/
          Beaker::Docker
        when /^noop$/
          Beaker::Noop
        when /^(default)|(none)$/
          Beaker::Hypervisor
        else
          # Custom hypervisor
          begin
            require "beaker/hypervisor/#{type}"
          rescue LoadError
            raise "Invalid hypervisor: #{type}"
          end
          Beaker.const_get(type.split('_').collect(&:capitalize).join)
        end

      hypervisor = hyper_class.new(hosts_to_provision, options)
      self.set_ssh_connection_preference(hosts_to_provision, hypervisor)
      hypervisor.provision if options[:provision]
      hypervisor
    end

    def initialize(hosts, options)
      @hosts = hosts
      @options = options
    end

    #Provisioning steps for be run for a given hypervisor.  Default is nil.
    def provision
      nil
    end

    #Cleanup steps to be run for a given hypervisor.  Default is nil.
    def cleanup
      nil
    end

    DEFAULT_CONNECTION_PREFERENCE = ['ip', 'vmhostname', 'hostname']
    #SSH connection method preference. Can be overwritten by hypervisor to change the order
    def connection_preference
      DEFAULT_CONNECTION_PREFERENCE
    end

    #Check if overriding method returns correct array with ip, vmhostname hostname as elements
    def self.set_ssh_connection_preference(hosts_to_provision, hypervisor)
      if hypervisor.connection_preference.sort == DEFAULT_CONNECTION_PREFERENCE.sort
        hosts_to_provision.each{ |h| h[:ssh_connection_preference] = hypervisor.connection_preference}
      else
        raise ArgumentError, <<-HEREDOC
Hypervisor's overriding connection_pereference method is not matching the API.

Make sure your hypervisor's connection_preference returns an array
containing the following elements in any order you prefer:
"ip", "hostname", "vmhostname"

Please check hypervisor.rb file's "self.connection_preference" method for an example
        HEREDOC
      end
    end

    #Proxy package managers on tests hosts created by this hypervisor, runs before validation and configuration.
    def proxy_package_manager
      if @options[:package_proxy]
        package_proxy(@hosts, @options)
      end
    end

    #Default configuration steps to be run for a given hypervisor.  Any additional configuration to be done
    #to the provided SUT for test execution to be successful.
    def configure(opts = {})
      return unless @options[:configure]
      run_in_parallel = run_in_parallel? opts, @options, 'configure'
      block_on @hosts, { :run_in_parallel => run_in_parallel} do |host|
        if host[:timesync]
          timesync(host, @options)
        end
      end
      if @options[:root_keys]
        sync_root_keys(@hosts, @options)
      end
      if @options[:add_el_extras]
        add_el_extras(@hosts, @options)
      end
      if @options[:disable_iptables]
        disable_iptables @hosts, @options
      end
      if @options[:set_env]
        set_env(@hosts, @options)
      end
      if @options[:disable_updates]
        disable_updates(@hosts, @options)
      end
    end

    #Default validation steps to be run for a given hypervisor.  Ensures that SUTs meet requirements to be
    #beaker test nodes.
    def validate
      if @options[:validate]
        validate_host(@hosts, @options)
      end
    end

    #Generate a random string composted of letter and numbers
    #prefixed with value of {Beaker::Hypervisor::create} option :host_name_prefix
    def generate_host_name
      n = CHARMAP[rand(25)] + (0...14).map{CHARMAP[rand(CHARMAP.length)]}.join
      if @options[:host_name_prefix]
        return @options[:host_name_prefix] + n
      end
      n
    end

  end
end

[
  'docker',
  'noop'
].each do |lib|
  require "beaker/hypervisor/#{lib}"
end
