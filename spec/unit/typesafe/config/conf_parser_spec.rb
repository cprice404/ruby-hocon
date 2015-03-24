# encoding: utf-8

require 'spec_helper'
require 'test_utils'
require 'hocon/config_parse_options'
require 'hocon/config_syntax'
require 'hocon/impl/abstract_config_object'
require 'hocon/impl/resolve_context'
require 'hocon/config_resolve_options'
require 'hocon/config_error'
require 'hocon/impl/simple_config_origin'


def parse_without_resolving(s)
  options = Hocon::ConfigParseOptions.defaults.
              set_origin_description("test conf string").
              set_syntax(Hocon::ConfigSyntax::CONF)
  Hocon::Impl::Parseable.new_string(s, options).parse_value
end

def parse(s)
  tree = parse_without_resolving(s)

  if tree.is_a?(Hocon::Impl::AbstractConfigObject)
    Hocon::Impl::ResolveContext.resolve(tree, tree,
      Hocon::ConfigResolveOptions.no_system)
  else
    tree
  end
end


describe "Config Parser" do
  context "invalid_conf_throws" do
    TestUtils.whitespace_variations(TestUtils::InvalidConf, false).each do |invalid|
      it "should raise an error for invalid config string '#{invalid.test}'" do
        TestUtils.add_offending_json_to_exception("config", invalid.test) {
          TestUtils.intercept(Hocon::ConfigError) {
            parse(invalid.test)
          }
        }
      end
    end
  end

  context "valid_conf_works" do
    TestUtils.whitespace_variations(TestUtils::ValidConf, true).each do |valid|
      it "should successfully parse config string '#{valid.test}'" do
        our_ast = TestUtils.add_offending_json_to_exception("config-conf", valid.test) {
          parse(valid.test)
        }
        # let's also check round-trip rendering
        rendered = our_ast.render
        reparsed = TestUtils.add_offending_json_to_exception("config-conf-reparsed", rendered) {
          parse(rendered)
        }
        expect(our_ast).to eq(reparsed)
      end
    end
  end
end
