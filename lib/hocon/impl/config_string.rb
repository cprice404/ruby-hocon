# encoding: utf-8

require 'hocon/impl'
require 'hocon/impl/abstract_config_value'
require 'hocon/config_value_type'
require 'hocon/impl/config_impl_util'

class Hocon::Impl::ConfigString
  include Hocon::Impl::AbstractConfigValue

  ConfigImplUtil = Hocon::Impl::ConfigImplUtil

  attr_accessor :value

  def initialize(origin, value)
    super(origin)
    @value = value
  end

  def value_type
    Hocon::ConfigValueType::STRING
  end

  def unwrapped
    @value
  end

  def transform_to_string
    @value
  end

  def render_value_to_sb(sb, indent_size, at_root, options)
    if options.json?
      sb << ConfigImplUtil.render_json_string(@value)
    else
      sb << ConfigImplUtil.render_string_unquoted_if_possible(@value)
    end
  end

  def new_copy(origin)
    Hocon::Impl::ConfigString.new(origin, @value)
  end
end
