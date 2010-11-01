require 'puppet/node/inventory'
require 'puppet/indirector/yaml'

class Puppet::Node::Inventory::Yaml < Puppet::Indirector::Yaml
  desc "Return node names matching the fact query"

  # Return the path to a given node's file.
  def yaml_dir_path
    base = Puppet.run_mode.master? ? Puppet[:yamldir] : Puppet[:clientyamldir]
    File.join(base, 'facts', '*.yaml')
  end

  def node_matches?(facts, options)
    options.each do |key, value|
      type, name, operator = key.to_s.split(".")
      operator ||= 'eq'

      return false unless node_matches_option?(type, name, operator, value, facts)
    end
    return true
  end

  def search(request)
    node_names = []
    Dir.glob(yaml_dir_path).each do |file|
      facts = YAML.load_file(file)
      node_names << facts.name if node_matches?(facts, request.options)
    end
    node_names
  end

  private

  def node_matches_option?(type, name, operator, value, facts)
    case type
    when "facts"
      compare_facts(operator, facts.values[name], value)
    end
  end

  def compare_facts(operator, value1, value2)
    return false unless value1

    case operator
    when "eq"
      value1.to_s == value2.to_s
    when "le"
      value1.to_f <= value2.to_f
    when "ge"
      value1.to_f >= value2.to_f
    when "lt"
      value1.to_f < value2.to_f
    when "gt"
      value1.to_f > value2.to_f
    when "ne"
      value1.to_s != value2.to_s
    end
  end
end
