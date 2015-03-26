# encoding: utf-8

require 'hocon/impl'
require 'hocon/config_value_type'
require 'hocon/config_resolve_options'
require 'hocon/impl/path'
require 'hocon/impl/default_transformer'
require 'hocon/impl/config_impl'
require 'hocon/impl/resolve_context'
require 'hocon/config_mergeable'

class Hocon::Impl::SimpleConfig < Hocon::ConfigMergeable

  ConfigMissingError = Hocon::ConfigError::ConfigMissingError
  ConfigNotResolvedError = Hocon::ConfigError::ConfigNotResolvedError
  ConfigNullError = Hocon::ConfigError::ConfigNullError
  ConfigWrongTypeError = Hocon::ConfigError::ConfigWrongTypeError
  ConfigValueType = Hocon::ConfigValueType
  Path = Hocon::Impl::Path
  DefaultTransformer = Hocon::Impl::DefaultTransformer

  attr_reader :object

  def initialize(object)
    @object = object
  end
  attr_reader :object

  def root
    @object
  end

  def resolve(options = Hocon::ConfigResolveOptions.defaults)
    resolve_with(self, options)
  end

  def resolve_with(source, options)
    resolved = Hocon::Impl::ResolveContext.resolve(@object, source.object, options)
    if resolved.eql?(@object)
      self
    else
      Hocon::Impl::SimpleConfig.new(resolved)
    end
  end

  def find_key(me, key, expected, original_path)
    v = me.peek_assuming_resolved(key, original_path)
    if v.nil?
      raise ConfigMissingError.new(nil, "No configuration setting found for key '#{original_path.render}'", nil)
    end

    if not expected.nil?
      v = DefaultTransformer.transform(v, expected)
    end

    if v.value_type == ConfigValueType::NULL
      raise ConfigNullError.new(v.origin,
                                (ConfigNullError.make_message(original_path.render,
                                                              (not expected.nil?) ? ConfigValueType.name(expected) : nil)),
                                nil)
    elsif (not expected.nil?) && v.value_type != expected
      raise ConfigWrongTypeError.new(v.origin,
                                     "#{original_path.render} has type #{ConfigValueType.name(v.value_type)} " +
                                         "rather than #{ConfigValueType.name(expected)}",
                                     nil)
    else
      return v
    end
  end

  def find(me, path, expected, original_path)
    key = path.first
    rest = path.remainder
    if rest.nil?
      find_key(me, key, expected, original_path)
    else
      o = find_key(me, key, ConfigValueType::OBJECT,
                   original_path.sub_path(0, original_path.length - rest.length))
      raise "Error: object o is nil" unless not o.nil?
      find(o, rest, expected, original_path)
    end
  end

  def find3(path_expression, expected, original_path)
    find(@object, path_expression, expected, original_path)
  end

  def find2(path_expression, expected)
    path = Path.new_path(path_expression)
    find3(path, expected, path)
  end

  def ==(other)
    if other.is_a? Hocon::Impl::SimpleConfig
      @object == other.object
    else
      false
    end
  end

  def hash
    41 * @object.hash
  end

  def get_value(path)
    parsed_path = Path.new_path(path)
    find(@object, parsed_path, nil, parsed_path)
  end

  def get_boolean(path)
    v = find2(path, ConfigValueType::BOOLEAN)
    v.unwrapped
  end

  def get_config_number(path_expression)
    path = Path.new_path(path_expression)
    v = find(@object, path, ConfigValueType::NUMBER, path)
    v.unwrapped
  end

  def get_int(path)
    get_config_number(path)
  end

  def get_string(path)                                                                                                                                                                                                                                                                 
    v = find2(path, ConfigValueType::STRING)
    v.unwrapped
  end

  def has_path(path_expression)
    path = Path.new_path(path_expression)
    begin
      peeked = @object.peek_path(path)
    rescue ConfigNotResolvedError => e
      raise Hocon::Impl::ConfigImpl.improve_not_resolved(path, e)
    end
    (not peeked.nil?) && peeked.value_type != ConfigValueType::NULL
  end

  def with_only_path(path_expression)
    path = Path.new_path(path_expression)
    self.class.new(root.with_only_path(path))
  end

  def without_path(path_expression)
    path = Path.new_path(path_expression)
    self.class.new(root.without_path(path))
  end

  def with_value(path_expression, v)
    path = Path.new_path(path_expression)
    self.class.new(root.with_value(path, v))
  end
end
