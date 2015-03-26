# encoding: utf-8

#require 'hocon/config_factory'
#require 'hocon/config_render_options'
#
#render_options = Hocon::ConfigRenderOptions.defaults
#render_options.origin_comments = false
#render_options.json = false
#conf = Hocon::ConfigFactory.parse_file("./spec/fixtures/parse_render/example1/input.conf")
#rendered = conf.root.render(render_options)
#puts "rendered: #{rendered}"

require 'hocon/config_parse_options'
require 'hocon/config_syntax'
require 'hocon/impl/parseable'
require 'hocon/impl/resolve_context'
require 'hocon/config_resolve_options'

#s = %q|{ "a" : [1,2], "b" : y${a}z }|
#s = %q|{ "foo" : { "bar" : "baz", "woo" : "w00t" }, "baz" : { "bar" : "baz", "woo" : [1,2,3,4], "w00t" : true, "a" : false, "b" : 3.14, "c" : null } }|
# s = %q|{ "c" : null }|
# s = "a = [], a += b"
s = "a = [], a += b"
options = Hocon::ConfigParseOptions.defaults.
              set_origin_description("test conf string").
              set_syntax(Hocon::ConfigSyntax::CONF)
obj = Hocon::Impl::Parseable.new_string(s, options).parse_value
resolved = Hocon::Impl::ResolveContext.resolve(obj, obj,
		Hocon::ConfigResolveOptions.no_system)
rendered = resolved.render
reparsed = Hocon::Impl::Parseable.new_string(rendered, options).parse_value
Hocon::Impl::ResolveContext.resolve(reparsed, reparsed,
		Hocon::ConfigResolveOptions.no_system)

