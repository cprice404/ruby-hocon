# encoding: utf-8

require 'hocon'
require 'hocon/impl/parseable'
require 'hocon/config_parse_options'
require 'hocon/impl/config_impl'

class Hocon::ConfigFactory
  def self.parse_file(file_path, options = Hocon::ConfigParseOptions.defaults)
    Hocon::Impl::Parseable.new_file(file_path, options).parse.to_config
  end

  def self.parse_string(string, options = Hocon::ConfigParseOptions.defaults)
    Hocon::Impl::Parseable.new_string(string, options).parse.to_config
  end

  def self.parse_file_any_syntax(file_base_name, options)
    Hocon::Impl::ConfigImpl.parse_file_any_syntax(file_base_name, options).to_config
  end
end
