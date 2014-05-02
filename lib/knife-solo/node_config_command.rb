module KnifeSolo
  module NodeConfigCommand

    def self.load_deps
      require 'fileutils'
      require 'pathname'
    end

    def self.included(other)
      other.class_eval do
        # Lazy load our dependencies if the including class did not call
        # Knife#deps yet. See KnifeSolo::SshCommand for more information.
        deps { KnifeSolo::NodeConfigCommand.load_deps } unless @dependency_loader

        option :chef_node_name,
          :short       => '-N NAME',
          :long        => '--node-name NAME',
          :description => 'The Chef node name for your new node'

        option :run_list,
          :short       => '-r RUN_LIST',
          :long        => '--run-list RUN_LIST',
          :description => 'Comma separated list of roles/recipes to put to node config (if it does not exist)',
          :proc        => lambda { |o| o.split(/[\s,]+/) },
          :default     => []

        option :json_attributes,
          :short       => '-j JSON_ATTRIBS',
          :long        => '--json-attributes',
          :description => 'A JSON string to be added to node config (if it does not exist)',
          :proc        => lambda { |o| JSON.parse(o) },
          :default     => nil

        option :environment,
          :short       => '-E ENVIRONMENT',
          :long        => '--environment ENVIRONMENT',
          :description => 'The Chef environment for your node'

      end
    end

    def node_dna_file
      @node_dna_file ||= ":-("
    end

    def nodes_path
      path = Chef::Config[:node_path]
      path && File.exist?(path) ? path : 'nodes'
    end

    def node_config
      Pathname.new(@name_args[1] || "#{nodes_path}/#{node_name}.json")
    end

    def get_node_config_json
      JSON.parse(File.read(node_config))
    end

    def node_name
      # host method must be defined by the including class
      config[:chef_node_name] || host
    end

    def node_environment
      node = node_config.exist? ? JSON.parse(IO.read(node_config)) : {}
      config[:environment] || node['environment'] || '_default'
    end

    def generate_node_config
      if node_config.exist?
        Chef::Log.debug "Node config '#{node_config}' already exists"
      else
        ui.msg "Generating node config '#{node_config}'..."
        FileUtils.mkdir_p(node_config.dirname)
        File.open(node_config, 'w') do |f|
          attributes = config[:json_attributes] || config[:first_boot_attributes] || {}
          run_list = { :run_list => config[:run_list] || [] }
          environment = config[:environment] ? { :environment => config[:environment] } : {}
          f.print attributes.merge(run_list).merge(environment).to_json
        end
      end
      generate_node_dna
    end

    def generate_node_dna
      node = Chef::Node.json_create(get_node_config_json)
      node.default_attrs = get_non_namespaced_attributes.merge(node.default_attrs)

      @node_dna_file = Tempfile.new(['dna', '.json'])

      dna_hash = node.attributes.to_hash
      dna_hash['run_list'] = JSON.parse(node.run_list.to_json)
      @node_dna_file.write(JSON.pretty_generate(dna_hash))

      @node_dna_file.rewind
      puts @node_dna_file.read


    end

    def get_non_namespaced_attributes
      node_config_json = get_node_config_json
      %w(
        name
        chef_environment
        json_class
        automatic
        normal
        chef_type
        default
        override
        run_list
      ).each { |k| node_config_json.delete k }
      node_config_json
    end

  end
end
