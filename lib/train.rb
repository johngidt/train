# encoding: utf-8
#
# Author:: Dominik Richter (<dominik.richter@gmail.com>)

require 'train/version'
require 'train/options'
require 'train/plugins'
require 'train/errors'
require 'train/platforms'
require 'uri'

module Train
  # Create a new transport instance, with the plugin indicated by the
  # given name.
  #
  # @param [String] name of the plugin
  # @param [Array] *args list of arguments for the plugin
  # @return [Transport] instance of the new transport or nil
  def self.create(name, *args)
    cls = load_transport(name)
    cls.new(*args) unless cls.nil?
  end

  # Retrieve the configuration options of a transport plugin.
  #
  # @param [String] name of the plugin
  # @return [Hash] map of default options
  def self.options(name)
    cls = load_transport(name)
    cls.default_options unless cls.nil?
  end

  # Load the transport plugin indicated by name. If the plugin is not
  # yet found in the plugin registry, it will be attempted to load from
  # `train/transports/plugin_name`.
  #
  # @param [String] name of the plugin
  # @return [Train::Transport] the transport plugin
  def self.load_transport(transport_name)
    transport_name = transport_name.to_s
    transport_class = Train::Plugins.registry[transport_name]
    return transport_class unless transport_class.nil?

    # Try to load the transport name from the core transports...
    require 'train/transports/' + transport_name
    return Train::Plugins.registry[transport_name]
  rescue LoadError => _
    begin
      # If it's not in the core transports, try loading from a train plugin gem.
      gem_name = 'train-' + transport_name
      require gem_name
      return Train::Plugins.registry[transport_name]
      # rubocop: disable Lint/HandleExceptions
    rescue LoadError => _
      # rubocop: enable Lint/HandleExceptions
      # Intentionally empty rescue - we're handling it below anyway
    end

    ex = Train::PluginLoadError.new("Can't find train plugin #{transport_name}. Please install it first.")
    ex.transport_name = transport_name
    raise ex
  end

  # Resolve target configuration in URI-scheme into
  # all respective fields and merge with existing configuration.
  # e.g. ssh://bob@remote  =>  backend: ssh, user: bob, host: remote
  def self.target_config(config = nil) # rubocop:disable Metrics/AbcSize
    conf = config.nil? ? {} : config.dup
    conf = symbolize_keys(conf)

    group_keys_and_keyfiles(conf)

    return conf if conf[:target].to_s.empty?

    # split up the target's host/scheme configuration
    uri = parse_uri(conf[:target].to_s)
    unless uri.host.nil? and uri.scheme.nil?
      conf[:backend]  ||= uri.scheme
      conf[:host]     ||= uri.hostname
      conf[:port]     ||= uri.port
      conf[:user]     ||= uri.user
      conf[:path]     ||= uri.path
      conf[:password] ||=
        if conf[:www_form_encoded_password] && !uri.password.nil?
          URI.decode_www_form_component(uri.password)
        else
          uri.password
        end
    end

    # ensure path is nil, if its empty; e.g. required to reset defaults for winrm
    conf[:path] = nil if !conf[:path].nil? && conf[:path].to_s.empty?

    # return the updated config
    conf
  end

  # Takes a map of key-value pairs and turns all keys into symbols. For this
  # to work, only keys are supported that can be turned into symbols.
  # Example: { 'a' => 123 }  ==>  { a: 123 }
  #
  # @param map [Hash]
  # @return [Hash] new map with all keys being symbols
  def self.symbolize_keys(map)
    map.each_with_object({}) do |(k, v), acc|
      acc[k.to_sym] = v
      acc
    end
  end
  private_class_method :symbolize_keys

  # Parse a URI. Supports empty URI's with paths, e.g. `mock://`
  #
  # @param string [string] URI string, e.g. `schema://domain.com`
  # @return [URI::Generic] parsed URI object
  def self.parse_uri(string)
    URI.parse(string)
  rescue URI::InvalidURIError => e
    # A use-case we want to catch is parsing empty URIs with a schema
    # e.g. mock://. To do this, we match it manually and fake the hostname
    case string
    when %r{^([a-z]+)://$}
      string += 'dummy'
    when /^([a-z]+):$/
      string += '//dummy'
    else
      raise Train::UserError, e
    end

    u = URI.parse(string)
    u.host = nil
    u
  end
  private_class_method :parse_uri

  def self.validate_backend(conf, default = :local)
    return default if conf.nil?
    res = conf[:backend]

    if (res.nil? || res == 'localhost') && conf[:sudo]
      fail Train::UserError, 'Sudo is only valid when running against a remote host. '\
        'To run this locally with elevated privileges, run the command with `sudo ...`.'
    end

    return res if !res.nil?

    if !conf[:target].nil?
      fail Train::UserError, 'Cannot determine backend from target '\
           "configuration #{conf[:target].inspect}. Valid example: ssh://192.168.0.1."
    end

    if !conf[:host].nil?
      fail Train::UserError, 'Host configured, but no backend was provided. Please '\
           'specify how you want to connect. Valid example: ssh://192.168.0.1.'
    end

    conf[:backend] = default
  end

  def self.group_keys_and_keyfiles(conf)
    # in case the user specified a key-file, register it that way
    # we will clear the list of keys and put keys and key_files separately
    keys_mixed = conf[:keys]
    return if keys_mixed.nil?

    conf[:key_files] = []
    conf[:keys] = []
    keys_mixed.each do |key|
      if !key.nil? and File.file?(key)
        conf[:key_files].push(key)
      else
        conf[:keys].push(key)
      end
    end
  end
end
