# encoding: utf-8

require 'train/platforms/common'
require 'train/platforms/family'
require 'train/platform'

module Train::Platforms
  class << self
    # Retrieve the current platform list
    #
    # @return [Hash] map with platform names and their objects
    def list
      @list ||= {}
    end

    # Retrieve the current family list
    #
    # @return [Hash] map with family names and their objects
    def families
      @families ||= {}
    end
  end

  # Create or update a platform
  #
  # @return Train::Platform
  def self.name(name, condition = {})
    # Check the list to see if one is already created
    plat = list[name]
    unless plat.nil?
      # Pass the condition incase we are adding a family relationship
      plat.condition = condition unless condition.nil?
      return plat
    end

    Train::Platform.new(name, condition)
  end

  # Create or update a family
  #
  # @return Train::Platforms::Family
  def self.family(name, condition = {})
    # Check the families to see if one is already created
    family = families[name]
    unless family.nil?
      # Pass the condition incase we are adding a family relationship
      family.condition = condition unless condition.nil?
      return family
    end

    Train::Platforms::Family.new(name, condition)
  end

  # Find the families or top level platforms
  #
  # @return [Hash] with top level family and platforms
  def self.top_platforms
    top_platforms = list.select { |_key, value| value.families.empty? }
    top_platforms.merge!(families.select { |_key, value| value.families.empty? })
    top_platforms
  end

  # Add genaric family? and platform methods to an existing platform
  #
  # This is done later to add any custom
  # families/properties that were created
  def self.add_platform_methods(plat)
    families.each_value do |k|
      plat.class.send(:define_method, k.name + '?') {
        plat.family_hierarchy.include?(k.name)
      }
    end

    # Helper methods for direct platform info
    # Note: this can override platform.name if a
    # custom one was found during detect block
    plat.platform.each_key do |m|
      plat.class.send(:define_method, m) {
        @platform[m]
      }
    end
  end

  # List all platforms and families in a readable output
  def self.list_all
    top_platforms = self.top_platforms
    top_platforms.each_value do |platform|
      puts "#{platform.title} (#{platform.class})"
      print_children(platform) if defined?(platform.children) end
  end

  def self.print_children(parent, pad = 2)
    parent.children.each do |key, value|
      obj = key
      puts "#{' ' * pad}-> #{obj.title}#{value unless value.empty?}"
      print_children(obj, pad + 2) unless !defined?(obj.children) || obj.children.nil?
    end
  end
end
