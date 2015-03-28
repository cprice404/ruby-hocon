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
require 'hocon/impl/parseable'
require 'hocon/config_factory'

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

    context "should concatenate values when there is no newline or comma" do
      it "with no newline in array" do
        expect(TestUtils.parse_config(" { c : [ 1 2 3 ] } ").
                   get_string_list("c")).to eq (["1 2 3"])
      end

      it "with no newline in array with quoted strings" do
        expect(TestUtils.parse_config(' { c : [ "4" "5" "6" ] } ').
                   get_string_list("c")).to eq (["4 5 6"])
      end

      it "with no newline in object" do
        expect(TestUtils.parse_config(' { a : b c } ').
                   get_string("a")).to eq ("b c")
      end

      it "with no newline at end" do
        expect(TestUtils.parse_config('a: b').
                   get_string("a")).to eq ("b")
      end

      it "errors when no newline between keys" do
        TestUtils.intercept(Hocon::ConfigError) {
          TestUtils.parse_config('{ a : y b : z }')
        }
      end

      it "errors when no newline between quoted keys" do
        TestUtils.intercept(Hocon::ConfigError) {
          TestUtils.parse_config('{ "a" : "y" "b" : "z" }')
        }
      end
    end
  end

  it "should support keys with slashes" do
    obj = TestUtils.parse_config('/a/b/c=42, x/y/z : 32')
    expect(obj.get_int("/a/b/c")).to eq(42)
    expect(obj.get_int("x/y/z")).to eq(32)
  end
end

def line_number_test(num, text)
  it "should include the line number #{num} in the error message for invalid string '#{text}'" do
    e = TestUtils.intercept(Hocon::ConfigError) {
      TestUtils.parse_config(text)
    }
    if ! (e.message.include?("#{num}:"))
      raise ScriptError, "error message did not contain line '#{num}' '#{text.gsub("\n", "\\n")}' (#{e})"
    end
  end
end

describe "Config Parser" do
  context "line_numbers_in_errors" do
    # error is at the last char
    line_number_test(1, "}")
    line_number_test(2, "\n}")
    line_number_test(3, "\n\n}")

    # error is before a final newline
    line_number_test(1, "}\n")
    line_number_test(2, "\n}\n")
    line_number_test(3, "\n\n}\n")

    # with unquoted string
    line_number_test(1, "foo")
    line_number_test(2, "\nfoo")
    line_number_test(3, "\n\nfoo")

    # with quoted string
    line_number_test(1, "\"foo\"")
    line_number_test(2, "\n\"foo\"")
    line_number_test(3, "\n\n\"foo\"")

    # newlines in triple-quoted string should not hose up the numbering
    line_number_test(1, "a : \"\"\"foo\"\"\"}")
    line_number_test(2, "a : \"\"\"foo\n\"\"\"}")
    line_number_test(3, "a : \"\"\"foo\nbar\nbaz\"\"\"}")
    #   newlines after the triple quoted string
    line_number_test(5, "a : \"\"\"foo\nbar\nbaz\"\"\"\n\n}")
    #   triple quoted string ends in a newline
    line_number_test(6, "a : \"\"\"foo\nbar\nbaz\n\"\"\"\n\n}")
    #   end in the middle of triple-quoted string
    line_number_test(5, "a : \"\"\"foo\n\n\nbar\n")
  end

  context "to_string_for_parseables" do
    # just to be sure the to_string don't throw, to get test coverage
    options = Hocon::ConfigParseOptions.defaults
    it "should allow to_s on File Parseable" do
      Hocon::Impl::Parseable.new_file("foo", options).to_s
    end

    it "should allow to_s on Resources Parseable" do
      Hocon::Impl::Parseable.new_resources("foo", options).to_s
    end

    it "should allow to_s on Resources Parseable" do
      Hocon::Impl::Parseable.new_string("foo", options).to_s
    end

    # NOTE: Skipping 'newURL', 'newProperties', 'newReader' tests here
    # because we don't implement them
  end
end

def assert_comments(comments, conf)
  it "should have comments #{comments} at root" do
    expect(conf.root.origin.comments).to eq(comments)
  end
end

def assert_comments_at_path(comments, conf, path)
  it "should have comments #{comments} at path #{path}" do
    expect(conf.get_value(path).origin.comments).to eq(comments)
  end
end

def assert_comments_at_path_index(comments, conf, path, index)
  it "should have comments #{comments} at path #{path} and index #{index}" do
    expect(conf.get_list(path).get(index).origin.comments).to eq(comments)
  end
end

describe "Config Parser" do
  context "track_comments_for_single_field" do
    # no comments
    conf0 = TestUtils.parse_config('
                {
                foo=10 }
                ')
    assert_comments_at_path([], conf0, "foo")

    # comment in front of a field is used
    conf1 = TestUtils.parse_config('
                { # Before
                foo=10 }
                ')
    assert_comments_at_path([" Before"], conf1, "foo")

    # comment with a blank line after is dropped
    conf2 = TestUtils.parse_config('
                { # BlankAfter

                foo=10 }
                ')
    assert_comments_at_path([], conf2, "foo")

    # comment in front of a field is used with no root {}
    conf3 = TestUtils.parse_config('
                # BeforeNoBraces
                foo=10
                ')
    assert_comments_at_path([" BeforeNoBraces"], conf3, "foo")

    # comment with a blank line after is dropped with no root {}
    conf4 = TestUtils.parse_config('
                # BlankAfterNoBraces

                foo=10
                ')
    assert_comments_at_path([], conf4, "foo")

    # comment same line after field is used
    conf5 = TestUtils.parse_config('
                {
                foo=10 # SameLine
                }
                ')
    assert_comments_at_path([" SameLine"], conf5, "foo")

    # comment before field separator is used
    conf6 = TestUtils.parse_config('
                {
                foo # BeforeSep
                =10
                }
                ')
    assert_comments_at_path([" BeforeSep"], conf6, "foo")

    # comment after field separator is used
    conf7 = TestUtils.parse_config('
                {
                foo= # AfterSep
                10
                }
                ')
    assert_comments_at_path([" AfterSep"], conf7, "foo")

    # comment on next line is NOT used
    conf8 = TestUtils.parse_config('
                {
                foo=10
                # NextLine
                }
                ')
    assert_comments_at_path([], conf8, "foo")

    # comment before field separator on new line
    conf9 = TestUtils.parse_config('
                {
                foo
                # BeforeSepOwnLine
                =10
                }
                ')
    assert_comments_at_path([" BeforeSepOwnLine"], conf9, "foo")

    # comment after field separator on its own line
    conf10 = TestUtils.parse_config('
                {
                foo=
                # AfterSepOwnLine
                10
                }
                ')
    assert_comments_at_path([" AfterSepOwnLine"], conf10, "foo")

    # comments comments everywhere
    conf11 = TestUtils.parse_config('
                {# Before
                foo
                # BeforeSep
                = # AfterSepSameLine
                # AfterSepNextLine
                10 # AfterValue
                # AfterValueNewLine (should NOT be used)
                }
                ')
    assert_comments_at_path([" Before", " BeforeSep", " AfterSepSameLine", " AfterSepNextLine", " AfterValue"], conf11, "foo")

    # empty object
    conf12 = TestUtils.parse_config('# BeforeEmpty
                {} #AfterEmpty
                # NewLine
                ')
    assert_comments([" BeforeEmpty", "AfterEmpty"], conf12)

    # empty array
    conf13 = TestUtils.parse_config('
                foo=
                # BeforeEmptyArray
                  [] #AfterEmptyArray
                # NewLine
                ')
    assert_comments_at_path([" BeforeEmptyArray", "AfterEmptyArray"], conf13, "foo")

    # array element
    conf14 = TestUtils.parse_config('
                foo=[
                # BeforeElement
                10 # AfterElement
                ]
                ')
    assert_comments_at_path_index(
        [" BeforeElement", " AfterElement"], conf14, "foo", 0)

    # field with comma after it
    conf15 = TestUtils.parse_config('
                foo=10, # AfterCommaField
                ')
    assert_comments_at_path([" AfterCommaField"], conf15, "foo")

    # element with comma after it
    conf16 = TestUtils.parse_config('
                foo=[10, # AfterCommaElement
                ]
                ')
    assert_comments_at_path_index([" AfterCommaElement"], conf16, "foo", 0)

    # field with comma after it but comment isn't on the field's line, so not used
    conf17 = TestUtils.parse_config('
                foo=10
                , # AfterCommaFieldNotUsed
                ')
    assert_comments_at_path([], conf17, "foo")

    # element with comma after it but comment isn't on the field's line, so not used
    conf18 = TestUtils.parse_config('
                foo=[10
                , # AfterCommaElementNotUsed
                ]
                ')
    assert_comments_at_path_index([], conf18, "foo", 0)

    # comment on new line, before comma, should not be used
    conf19 = TestUtils.parse_config('
                foo=10
                # BeforeCommaFieldNotUsed
                ,
                ')
    assert_comments_at_path([], conf19, "foo")

    # comment on new line, before comma, should not be used
    conf20 = TestUtils.parse_config('
                foo=[10
                # BeforeCommaElementNotUsed
                ,
                ]
                ')
    assert_comments_at_path_index([], conf20, "foo", 0)

    # comment on same line before comma
    conf21 = TestUtils.parse_config('
                foo=10 # BeforeCommaFieldSameLine
                ,
                ')
    assert_comments_at_path([" BeforeCommaFieldSameLine"], conf21, "foo")

    # comment on same line before comma
    conf22 = TestUtils.parse_config('
                foo=[10 # BeforeCommaElementSameLine
                ,
                ]
                ')
    assert_comments_at_path_index([" BeforeCommaElementSameLine"], conf22, "foo", 0)
  end

  context "track_comments_for_multiple_fields" do
    # nested objects
    conf5 = TestUtils.parse_config('
             # Outside
             bar {
                # Ignore me

                # Middle
                # two lines
                baz {
                    # Inner
                    foo=10 # AfterInner
                    # This should be ignored
                } # AfterMiddle
                # ignored
             } # AfterOutside
             # ignored!
             ')
    assert_comments_at_path([" Inner", " AfterInner"], conf5, "bar.baz.foo")
    assert_comments_at_path([" Middle", " two lines", " AfterMiddle"], conf5, "bar.baz")
    assert_comments_at_path([" Outside", " AfterOutside"], conf5, "bar")

    # multiple fields
    conf6 = TestUtils.parse_config('{
                # this is not with a field

                # this is field A
                a : 10,
                # this is field B
                b : 12 # goes with field B which has no comma
                # this is field C
                c : 14, # goes with field C after comma
                # not used
                # this is not used
                # nor is this
                # multi-line block

                # this is with field D
                # this is with field D also
                d : 16

                # this is after the fields
    }')
    assert_comments_at_path([" this is field A"], conf6, "a")
    assert_comments_at_path([" this is field B", " goes with field B which has no comma"], conf6, "b")
    assert_comments_at_path([" this is field C", " goes with field C after comma"], conf6, "c")
    assert_comments_at_path([" this is with field D", " this is with field D also"], conf6, "d")

    # array
    conf7 = TestUtils.parse_config('
                # before entire array
                array = [
                # goes with 0
                0,
                # goes with 1
                1, # with 1 after comma
                # goes with 2
                2 # no comma after 2
                # not with anything
                ] # after entire array
                ')
    assert_comments_at_path_index([" goes with 0"], conf7, "array", 0)
    assert_comments_at_path_index([" goes with 1", " with 1 after comma"], conf7, "array", 1)
    assert_comments_at_path_index([" goes with 2", " no comma after 2"], conf7, "array", 2)
    assert_comments_at_path([" before entire array", " after entire array"], conf7, "array")

    # properties-like syntax
    conf8 = TestUtils.parse_config('
                # ignored comment
                
                # x.y comment
                x.y = 10
                # x.z comment
                x.z = 11
                # x.a comment
                x.a = 12
                # a.b comment
                a.b = 14
                a.c = 15
                a.d = 16 # a.d comment
                # ignored comment
                ')

    assert_comments_at_path([" x.y comment"], conf8, "x.y")
    assert_comments_at_path([" x.z comment"], conf8, "x.z")
    assert_comments_at_path([" x.a comment"], conf8, "x.a")
    assert_comments_at_path([" a.b comment"], conf8, "a.b")
    assert_comments_at_path([], conf8, "a.c")
    assert_comments_at_path([" a.d comment"], conf8, "a.d")
    # here we're concerned that comments apply only to leaf
    # nodes, not to parent objects.
    assert_comments_at_path([], conf8, "x")
    assert_comments_at_path([], conf8, "a")
  end


  it "includeFile" do
    conf = Hocon::ConfigFactory.parse_string("include file(" +
              TestUtils.json_quoted_resource_file("test01") + ")")

    # should have loaded conf, json... skipping properties
    expect(conf.get_int("ints.fortyTwo")).to eq(42)
    expect(conf.get_int("fromJson1")).to eq(1)
  end

  it "includeFileWithExtension" do
    conf = Hocon::ConfigFactory.parse_string("include file(" +
              TestUtils.json_quoted_resource_file("test01.conf") + ")")

    expect(conf.get_int("ints.fortyTwo")).to eq(42)
    expect(conf.has_path?("fromJson1")).to eq(false)
    expect(conf.has_path?("fromProps.abc")).to eq(false)
  end

  it "includeFileWhitespaceInsideParens" do
    conf = Hocon::ConfigFactory.parse_string("include file(  \n  " +
              TestUtils.json_quoted_resource_file("test01") + "  \n  )")

    # should have loaded conf, json... NOT properties
    expect(conf.get_int("ints.fortyTwo")).to eq(42)
    expect(conf.get_int("fromJson1")).to eq(1)
  end

  it "includeFileNoWhitespaceOutsideParens" do
    e = TestUtils.intercept(Hocon::ConfigError::ConfigParseError) {
      Hocon::ConfigFactory.parse_string("include file (" +
        TestUtils.json_quoted_resource_file("test01") + ")")
    }
    expect(e.message.include?("expecting include parameter")).to eq(true)
  end

  it "includeFileNotQuoted" do
    # this test cannot work on Windows
    f = TestUtils.resource_file("test01")
    if (f.to_s.include?("\\"))
      $stderr.puts("includeFileNotQuoted test skipped on Windows")
    else
      e = TestUtils.intercept(Hocon::ConfigError::ConfigParseError) {
        Hocon::ConfigFactory.parse_string("include file(" + f + ")")
      }
      expect(e.message.include?("expecting include parameter")).to eq(true)
    end
  end

  it "includeFileNotQuotedAndSpecialChar" do
    f = TestUtils.resource_file("test01")
    if (f.to_s.include?("\\"))
      $stderr.puts("includeFileNotQuoted test skipped on Windows")
    else
      e = TestUtils.intercept(Hocon::ConfigError::ConfigParseError) {
        Hocon::ConfigFactory.parse_string("include file(:" + f + ")")
      }
      expect(e.message.include?("expecting a quoted string")).to eq(true)
    end

  end

  it "includeFileUnclosedParens" do
    e = TestUtils.intercept(Hocon::ConfigError::ConfigParseError) {
      Hocon::ConfigFactory.parse_string("include file(" + TestUtils.json_quoted_resource_file("test01") + " something")
    }
    expect(e.message.include?("expecting a close paren")).to eq(true)
  end

  # Skipping 'includeURLBasename' because we don't support URLs
  # Skipping 'includeURLWithExtension' because we don't support URLs
  # Skipping 'includeURLInvalid' because we don't support URLs
  # Skipping 'includeResources' because we don't support classpath resources
  # Skipping 'includeURLHeuristically' because we don't support URLs
  # Skipping 'includeURLBasenameHeuristically' because we don't support URLs

  it "acceptBOMStartingFile" do
    skip("BOM not parsing properly yet") do
      # BOM at start of file should be ignored
      conf = Hocon::ConfigFactory.parse_file(TestUtils.resource_file("bom.conf"))
      expect(conf.get_string("foo")).to eq("bar")
    end
  end

  it "acceptBOMStartOfStringConfig" do
    skip("BOM not parsing properly yet") do
      # BOM at start of file is just whitespace, so ignored
      conf = Hocon::ConfigFactory.parse_string("\uFEFFfoo=bar")
      expect(conf.get_string("foo")).to eq("bar")
    end
  end

  it "acceptBOMInStringValue" do
    # BOM inside quotes should be preserved, just as other whitespace would be
    conf = Hocon::ConfigFactory.parse_string("foo=\"\uFEFF\uFEFF\"")
    expect(conf.get_string("foo")).to eq("\uFEFF\uFEFF")
  end

  it "acceptBOMWhitespace" do
    skip("BOM not parsing properly yet") do
      # BOM here should be treated like other whitespace (ignored, since no quotes)
      conf = Hocon::ConfigFactory.parse_string("foo= \uFEFFbar\uFEFF")
      expect(conf.get_string("foo")).to eq("bar")
    end
  end

  it "acceptMultiPeriodNumericPath" do
    conf1 = Hocon::ConfigFactory.parse_string("0.1.2.3=foobar1")
    expect(conf1.get_string("0.1.2.3")).to eq("foobar1")
    conf2 = Hocon::ConfigFactory.parse_string("0.1.2.3.ABC=foobar2")
    expect(conf2.get_string("0.1.2.3.ABC")).to eq("foobar2")
    conf3 = Hocon::ConfigFactory.parse_string("ABC.0.1.2.3=foobar3")
    expect(conf3.get_string("ABC.0.1.2.3")).to eq("foobar3")
  end
end