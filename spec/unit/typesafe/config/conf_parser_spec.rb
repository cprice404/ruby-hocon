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
require 'hocon/config_list'
require 'hocon/impl/config_reference'
require 'hocon/impl/path_parser'


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

def parse_path(s)
  first_excepton = nil
  second_exception = nil
  # parser first by wrapping into a whole document and using the regular parser
  result =
      begin
        tree = parse_without_resolving("[${#{s}}]")
        if tree.is_a?(Hocon::ConfigList)
          ref = tree[0]
          if ref.is_a?(Hocon::Impl::ConfigReference)
            ref.expression.path
          end
        end
      rescue Hocon::ConfigError => e
        first_excepton = e
        nil
      end

  # also parse with the standalone path parser and be sure the outcome is the same
  begin
    should_be_same = Hocon::Impl::PathParser.parse_path(s)
    unless result == should_be_same
      raise ScriptError, "expected '#{result}' to equal '#{should_be_same}'"
    end
  rescue Hocon::ConfigError => e
    second_exception = e
  end

  if first_excepton.nil? && (!second_exception.nil?)
    raise ScriptError, "only the standalone path parser threw: #{second_exception}"
  end

  if (!first_excepton.nil?) && second_exception.nil?
    raise ScriptError, "only the whole-document parser threw: #{first_exception}"
  end

  if !first_excepton.nil?
    raise first_excepton
  end
  if !second_exception.nil?
    raise ScriptError, "wtf, should have thrown because not equal"
  end

  result
end

def test_path_parsing(first, second)
  it "'#{first}' should parse to same path as '#{second}'" do
    expect(TestUtils.path(*first)).to eq(parse_path(second))
  end
end

describe "Config Parser" do
  context "path_parsing" do
    test_path_parsing(["a"], "a")
    test_path_parsing(["a", "b"], "a.b")
    test_path_parsing(["a.b"], "\"a.b\"")
    test_path_parsing(["a."], "\"a.\"")
    test_path_parsing([".b"], "\".b\"")
    test_path_parsing(["true"], "true")
    test_path_parsing(["a"], " a ")
    test_path_parsing(["a ", "b"], " a .b")
    test_path_parsing(["a ", " b"], " a . b")
    test_path_parsing(["a  b"], " a  b")
    test_path_parsing(["a", "b.c", "d"], "a.\"b.c\".d")
    test_path_parsing(["3", "14"], "3.14")
    test_path_parsing(["3", "14", "159"], "3.14.159")
    test_path_parsing(["a3", "14"], "a3.14")
    test_path_parsing([""], "\"\"")
    test_path_parsing(["a", "", "b"], "a.\"\".b")
    test_path_parsing(["a", ""], "a.\"\"")
    test_path_parsing(["", "b"], "\"\".b")
    test_path_parsing(["", "", ""], ' "".""."" ')
    test_path_parsing(["a-c"], "a-c")
    test_path_parsing(["a_c"], "a_c")
    test_path_parsing(["-"], "\"-\"")
    test_path_parsing(["-"], "-")
    test_path_parsing(["-foo"], "-foo")
    test_path_parsing(["-10"], "-10")

    # here 10.0 is part of an unquoted string
    test_path_parsing(["foo10", "0"], "foo10.0")
    # here 10.0 is a number that gets value-concatenated
    test_path_parsing(["10", "0foo"], "10.0foo")
    # just a number
    test_path_parsing(["10", "0"], "10.0")
    # multiple-decimal number
    test_path_parsing(["1", "2", "3", "4"], "1.2.3.4")

    ["", " ", "  \n   \n  ", "a.", ".b", "a..b", "a${b}c", "\"\".", ".\"\""].each do |invalid|
      begin
        it "should raise a ConfigBadPathError for '#{invalid}'" do
          TestUtils.intercept(Hocon::ConfigError::ConfigBadPathError) {
            parse_path(invalid)
          }
        end
      rescue => e
        $stderr.puts("failed on '#{invalid}'")
        raise e
      end
    end
  end

  it "should allow the last instance to win when duplicate keys are found" do
    obj = TestUtils.parse_config('{ "a" : 10, "a" : 11 } ')

    expect(obj.root.size).to eq(1)
    expect(obj.get_int("a")).to eq(11)
  end

  it "should merge maps when duplicate keys are found" do
    obj = TestUtils.parse_config('{ "a" : { "x" : 1, "y" : 2 }, "a" : { "x" : 42, "z" : 100 } }')

    expect(obj.root.size).to eq(1)
    expect(obj.get_object("a").size).to eq(3)
    expect(obj.get_int("a.x")).to eq(42)
    expect(obj.get_int("a.y")).to eq(2)
    expect(obj.get_int("a.z")).to eq(100)
  end

  it "should merge maps recursively when duplicate keys are found" do
    obj = TestUtils.parse_config('{ "a" : { "b" : { "x" : 1, "y" : 2 } }, "a" : { "b" : { "x" : 42, "z" : 100 } } }')

    expect(obj.root.size).to eq(1)
    expect(obj.get_object("a").size).to eq(1)
    expect(obj.get_object("a.b").size).to eq(3)
    expect(obj.get_int("a.b.x")).to eq(42)
    expect(obj.get_int("a.b.y")).to eq(2)
    expect(obj.get_int("a.b.z")).to eq(100)
  end

  it "should merge maps recursively when three levels of duplicate keys are found" do
    obj = TestUtils.parse_config('{ "a" : { "b" : { "c" : { "x" : 1, "y" : 2 } } }, "a" : { "b" : { "c" : { "x" : 42, "z" : 100 } } } }')

    expect(obj.root.size).to eq(1)
    expect(obj.get_object("a").size).to eq(1)
    expect(obj.get_object("a.b").size).to eq(1)
    expect(obj.get_object("a.b.c").size).to eq(3)
    expect(obj.get_int("a.b.c.x")).to eq(42)
    expect(obj.get_int("a.b.c.y")).to eq(2)
    expect(obj.get_int("a.b.c.z")).to eq(100)
  end

  it "should 'reset' a key when a null is found" do
    obj = TestUtils.parse_config('{ a : { b : 1 }, a : null, a : { c : 2 } }')

    expect(obj.root.size).to eq(1)
    expect(obj.get_object("a").size).to eq(1)
    expect(obj.get_int("a.c")).to eq(2)
  end

  it "should 'reset' a map key when a scalar is found" do
    obj = TestUtils.parse_config('{ a : { b : 1 }, a : 42, a : { c : 2 } }')

    expect(obj.root.size).to eq(1)
    expect(obj.get_object("a").size).to eq(1)
    expect(obj.get_int("a.c")).to eq(2)
  end
end

def drop_curlies(s)
  # drop the outside curly braces
  first = s.index('{')
  last = s.rindex('}')
  "#{s.slice(0..first)}#{s.slice(first+1..last)}#{s.slice(last + 1)}"
end

describe "Config Parser" do
  context "implied_comma_handling" do
    valids = ['
// one line
{
  a : y, b : z, c : [ 1, 2, 3 ]
}', '
// multiline but with all commas
{
  a : y,
  b : z,
  c : [
    1,
    2,
    3,
  ],
}
', '
// multiline with no commas
{
  a : y
  b : z
  c : [
    1
    2
    3
  ]
}
']

    changes =   [
        Proc.new { |s| s },
        Proc.new { |s| s.gsub("\n", "\n\n") },
        Proc.new { |s| s.gsub("\n", "\n\n\n") },
        Proc.new { |s| s.gsub(",\n", "\n,\n")},
        Proc.new { |s| s.gsub(",\n", "\n\n,\n\n") },
        Proc.new { |s| s.gsub("\n", " \n ") },
        Proc.new { |s| s.gsub(",\n", "  \n  \n  ,  \n  \n  ") },
        Proc.new { |s| drop_curlies(s) }
    ]

    tested = 0
    changes.each do |change|
      valids.each do |v|
        tested += 1
        s = change.call(v)
        it "should handle commas and whitespaces properly for string '#{s}'" do
          obj = TestUtils.parse_config(s)
          expect(obj.root.size).to eq(3)
          expect(obj.get_string("a")).to eq("y")
          expect(obj.get_string("b")).to eq("z")
          expect(obj.get_int_list("c")).to eq([1,2,3])
        end
      end
    end

    it "should have run one test per change per valid string" do
      expect(tested).to eq(changes.length * valids.length)
    end
  end
end
