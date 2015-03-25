# encoding: utf-8

require 'spec_helper'
require 'hocon'
require 'test_utils'
require 'pp'


describe Hocon::Impl::Tokenizer do
  Tokens = Hocon::Impl::Tokens

  shared_examples_for "token_matching" do
    it "should match the tokenized string to the list of expected tokens" do
      tokenized_from_string = TestUtils.tokenize_as_list(test_string)
      tokenized_as_string = TestUtils.tokenize_as_string(test_string)

      # Add START and EOF tokens
      wrapped_tokens = TestUtils.wrap_tokens(expected_tokens)

      # Compare the two lists of tokens
      expect(tokenized_from_string).to eq(wrapped_tokens)
      expect(tokenized_as_string).to eq(test_string)
    end
  end

  shared_examples_for "strings_with_problems" do
    it "should find a problem when tokenizing" do
      token_list = TestUtils.tokenize_as_list(test_string)
      expect(token_list.map { |token| Tokens.problem?(token) }).to include(true)
    end
  end

  ####################
  # Whitespace
  ####################
  context "tokenizing whitespace" do
    context "tokenize empty string" do
      let(:test_string) { "" }
      let(:expected_tokens) { [] }

      include_examples "token_matching"
    end

    context "tokenize newlines" do
      let(:test_string) { "\n\n" }
      let(:expected_tokens) { [TestUtils.token_line(1),
                               TestUtils.token_line(2)] }

      include_examples "token_matching"
    end

    context "tokenize unquoted text should keep spaces" do
      let(:test_string) { "    foo     \n" }
      let(:expected_tokens) { [TestUtils.token_whitespace("    "),
                               TestUtils.token_unquoted("foo"),
                               TestUtils.token_whitespace("     "),
                               TestUtils.token_line(1)] }

      include_examples "token_matching"
    end

    context "tokenize unquoted text with internal spaces should keep spaces" do
      let(:test_string) { "    foo bar baz   \n" }
      let(:expected_tokens) { [TestUtils.token_whitespace("    "),
                               TestUtils.token_unquoted("foo"),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_unquoted("bar"),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_unquoted("baz"),
                               TestUtils.token_whitespace("   "),
                               TestUtils.token_line(1)] }

      include_examples "token_matching"
    end
  end

  ####################
  # Booleans and Null
  ####################
  context "tokenizing booleans and null" do
    context "tokenize true and unquoted text" do
      let(:test_string) { "truefoo" }
      let(:expected_tokens) { [TestUtils.token_true,
                               TestUtils.token_unquoted("foo")] }

      include_examples "token_matching"
    end

    context "tokenize false and unquoted text" do
      let(:test_string) { "falsefoo" }
      let(:expected_tokens) { [TestUtils.token_false,
                               TestUtils.token_unquoted("foo")] }

      include_examples "token_matching"
    end

    context "tokenize null and unquoted text" do
      let(:test_string) { "nullfoo" }
      let(:expected_tokens) { [TestUtils.token_null,
                               TestUtils.token_unquoted("foo")] }

      include_examples "token_matching"
    end

    context "tokenize unquoted text containing true" do
      let(:test_string) { "footrue" }
      let(:expected_tokens) { [TestUtils.token_unquoted("footrue")] }

      include_examples "token_matching"
    end

    context "tokenize unquoted text containing space and true" do
      let(:test_string) { "foo true" }
      let(:expected_tokens) { [TestUtils.token_unquoted("foo"),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_true] }

      include_examples "token_matching"
    end

    context "tokenize true and space and unquoted text" do
      let(:test_string) { "true foo" }
      let(:expected_tokens) { [TestUtils.token_true,
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_unquoted("foo")] }

      include_examples "token_matching"
    end
  end

  ####################
  # Slashes
  ####################
  context "tokenizing slashes" do
    context "tokenize unquoted text containing slash" do
      let(:test_string) { "a/b/c/" }
      let(:expected_tokens) { [TestUtils.token_unquoted("a/b/c/")] }

      include_examples "token_matching"
    end

    context "tokenize slash" do
      let(:test_string) { "/" }
      let(:expected_tokens) { [TestUtils.token_unquoted("/")] }

      include_examples "token_matching"
    end

    context "tokenize slash space slash" do
      let(:test_string) { "/ /" }
      let(:expected_tokens) { [TestUtils.token_unquoted("/"),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_unquoted("/")] }

      include_examples "token_matching"
    end

    ####################
    # Quotes
    ####################
    context "tokenize mixed unquoted and quoted" do
      let(:test_string) { "    foo\"bar\"baz   \n" }
      let(:expected_tokens) { [TestUtils.token_whitespace("    "),
                               TestUtils.token_unquoted("foo"),
                               TestUtils.token_string("bar"),
                               TestUtils.token_unquoted("baz"),
                               TestUtils.token_whitespace("   "),
                               TestUtils.token_line(1)] }

      include_examples "token_matching"
    end

    context "tokenize empty triple quoted string" do
      let(:test_string) { '""""""' }
      let(:expected_tokens) { [TestUtils.token_string("")] }

      include_examples "token_matching"
    end

    context "tokenize trivial triple quoted string" do
      let(:test_string) { '"""bar"""' }
      let(:expected_tokens) { [TestUtils.token_string("bar")] }

      include_examples "token_matching"
    end

    context "tokenize no escapes in triple quoted string" do
      let(:test_string) { '"""\n"""' }
      let(:expected_tokens) { [TestUtils.token_string('\n')] }

      include_examples "token_matching"
    end

    context "tokenize trailing quotes in triple quoted string" do
      let(:test_string) { '"""""""""' }
      let(:expected_tokens) { [TestUtils.token_string('"""')] }

      include_examples "token_matching"
    end

    context "tokenize new line in triple quoted string" do
      let(:test_string) { '"""foo\nbar"""' }
      let(:expected_tokens) { [TestUtils.token_string('foo\nbar')] }

      include_examples "token_matching"
    end
  end

  ####################
  # Find problems when tokenizing
  ####################
  context "finding problems when tokenizing" do
    context "nothing after backslash" do
      let(:test_string) { ' "\" ' }
      include_examples "strings_with_problems"
    end

    context "there is no \q escape sequence" do
      let(:test_string) { ' "\q" ' }
      include_examples "strings_with_problems"
    end

    context "unicode byte sequence missing a byte" do
      let(:test_string) { '"\u123"' }
      include_examples "strings_with_problems"
    end

    context "unicode byte sequence missing two bytes" do
      let(:test_string) { '"\u12"' }
      include_examples "strings_with_problems"
    end

    context "unicode byte sequence missing three bytes" do
      let(:test_string) { '"\u1"' }
      include_examples "strings_with_problems"
    end

    context "unicode byte missing" do
      let(:test_string) { '"\u"' }
      include_examples "strings_with_problems"
    end

    context "just a single quote" do
      let(:test_string) { '"' }
      include_examples "strings_with_problems"
    end

    context "no end quote" do
      let(:test_string) { ' "abcdefg' }
      include_examples "strings_with_problems"
    end

    context "file ends with a backslash" do
      let(:test_string) { '\"\\' }
      include_examples "strings_with_problems"
    end

    context "file ends with a $" do
      let(:test_string) { "$" }
      include_examples "strings_with_problems"
    end

    context "file ends with a ${" do
      let(:test_string) { "${" }
      include_examples "strings_with_problems"
    end
  end

  ####################
  # Numbers
  ####################
  context "tokenizing numbers" do
    context "parse positive float" do
      let(:test_string) { "1.2" }
      let(:expected_tokens) { [TestUtils.token_double(1.2)] }
      include_examples "token_matching"
    end

    context "parse negative float" do
      let(:test_string) { "-1.2" }
      let(:expected_tokens) { [TestUtils.token_double(-1.2)] }
      include_examples "token_matching"
    end

    context "parse exponent notation" do
      let(:test_string) { "1e6" }
      let(:expected_tokens) { [TestUtils.token_double(1e6)] }
      include_examples "token_matching"
    end

    context "parse negative exponent" do
      let(:test_string) { "1e-6" }
      let(:expected_tokens) { [TestUtils.token_double(1e-6)] }
      include_examples "token_matching"
    end

    context "parse exponent with capital E" do
      let(:test_string) { "1E-6" }
      let(:expected_tokens) { [TestUtils.token_double(1e-6)] }
      include_examples "token_matching"
    end

    context "parse negative int" do
      let(:test_string) { "-1" }
      let(:expected_tokens) { [TestUtils.token_int(-1)] }
      include_examples "token_matching"
    end
  end

  ####################
  # Comments
  ####################
  context "tokenizing comments" do
    context "tokenize two slashes as comment" do
      let(:test_string) { "//" }
      let(:expected_tokens) { [TestUtils.token_comment_double_slash("")] }

      include_examples "token_matching"
    end

    context "tokenize two slashes in string as string" do
      let(:test_string) { '"//bar"' }
      let(:expected_tokens) { [TestUtils.token_string("//bar")] }

      include_examples "token_matching"
    end

    context "tokenize hash in string as string" do
      let(:test_string) { '"#bar"' }
      let(:expected_tokens) { [TestUtils.token_string("#bar")] }

      include_examples "token_matching"
    end

    context "tokenize slash comment after unquoted text" do
      let(:test_string) { "bar//comment" }
      let(:expected_tokens) { [TestUtils.token_unquoted("bar"),
                               TestUtils.token_comment_double_slash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize hash comment after unquoted text" do
      let(:test_string) { "bar#comment" }
      let(:expected_tokens) { [TestUtils.token_unquoted("bar"),
                               TestUtils.token_comment_hash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize slash comment after int" do
      let(:test_string) { "10//comment" }
      let(:expected_tokens) { [TestUtils.token_int(10),
                               TestUtils.token_comment_double_slash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize hash comment after int" do
      let(:test_string) { "10#comment" }
      let(:expected_tokens) { [TestUtils.token_int(10),
                               TestUtils.token_comment_hash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize hash comment after int" do
      let(:test_string) { "10#comment" }
      let(:expected_tokens) { [TestUtils.token_int(10),
                               TestUtils.token_comment_hash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize slash comment after float" do
      let(:test_string) { "3.14//comment" }
      let(:expected_tokens) { [TestUtils.token_double(3.14),
                               TestUtils.token_comment_double_slash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize hash comment after float" do
      let(:test_string) { "3.14#comment" }
      let(:expected_tokens) { [TestUtils.token_double(3.14),
                               TestUtils.token_comment_hash("comment")] }

      include_examples "token_matching"
    end

    context "tokenize slash comment with newline" do
      let(:test_string) { "10//comment\n12" }
      let(:expected_tokens) { [TestUtils.token_int(10),
                               TestUtils.token_comment_double_slash("comment"),
                               TestUtils.token_line(1),
                               TestUtils.token_int(12)] }

      include_examples "token_matching"
    end

    context "tokenize hash comment with newline" do
      let(:test_string) { "10#comment\n12" }
      let(:expected_tokens) { [TestUtils.token_int(10),
                               TestUtils.token_comment_hash("comment"),
                               TestUtils.token_line(1),
                               TestUtils.token_int(12)] }

      include_examples "token_matching"
    end

    context "tokenize slash comments on two consecutive lines" do
      let(:test_string) { "//comment\n//comment2" }
      let(:expected_tokens) { [TestUtils.token_comment_double_slash("comment"),
                               TestUtils.token_line(1),
                               TestUtils.token_comment_double_slash("comment2")] }

      include_examples "token_matching"
    end

    context "tokenize hash comments on two consecutive lines" do
      let(:test_string) { "#comment\n#comment2" }
      let(:expected_tokens) { [TestUtils.token_comment_hash("comment"),
                               TestUtils.token_line(1),
                               TestUtils.token_comment_hash("comment2")] }
      include_examples "token_matching"
    end

    context "tokenize slash comments on multiple lines with whitespace" do
      let(:test_string) { "        //comment\r\n        //comment2        \n//comment3        \n\n//comment4" }
      let(:expected_tokens) { [TestUtils.token_whitespace("        "),
                               TestUtils.token_comment_double_slash("comment\r"),
                               TestUtils.token_line(1),
                               TestUtils.token_whitespace("        "),
                               TestUtils.token_comment_double_slash("comment2        "),
                               TestUtils.token_line(2),
                               TestUtils.token_comment_double_slash("comment3        "),
                               TestUtils.token_line(3),
                               TestUtils.token_line(4),
                               TestUtils.token_comment_double_slash("comment4")] }

      include_examples "token_matching"
    end

    context "tokenize hash comments on multiple lines with whitespace" do
      let(:test_string) { "        #comment\r\n        #comment2        \n#comment3        \n\n#comment4" }
      let(:expected_tokens) { [TestUtils.token_whitespace("        "),
                               TestUtils.token_comment_hash("comment\r"),
                               TestUtils.token_line(1),
                               TestUtils.token_whitespace("        "),
                               TestUtils.token_comment_hash("comment2        "),
                               TestUtils.token_line(2),
                               TestUtils.token_comment_hash("comment3        "),
                               TestUtils.token_line(3),
                               TestUtils.token_line(4),
                               TestUtils.token_comment_hash("comment4")] }

      include_examples "token_matching"
    end
  end

  ####################
  # Brackets, braces
  ####################
  context "tokenizing brackets and braces" do
    context "tokenize open curly braces" do
      let(:test_string) { "{{" }
      let(:expected_tokens) { [Tokens::OPEN_CURLY, Tokens::OPEN_CURLY] }

      include_examples "token_matching"
    end

    context "tokenize close curly braces" do
      let(:test_string) { "}}" }
      let(:expected_tokens) { [Tokens::CLOSE_CURLY, Tokens::CLOSE_CURLY] }

      include_examples "token_matching"
    end

    context "tokenize open and close curly braces" do
      let(:test_string) { "{}" }
      let(:expected_tokens) { [Tokens::OPEN_CURLY, Tokens::CLOSE_CURLY] }

      include_examples "token_matching"
    end

    context "tokenize open and close curly braces" do
      let(:test_string) { "{}" }
      let(:expected_tokens) { [Tokens::OPEN_CURLY, Tokens::CLOSE_CURLY] }

      include_examples "token_matching"
    end

    context "tokenize open square brackets" do
      let(:test_string) { "[[" }
      let(:expected_tokens) { [Tokens::OPEN_SQUARE, Tokens::OPEN_SQUARE] }

      include_examples "token_matching"
    end

    context "tokenize close square brackets" do
      let(:test_string) { "]]" }
      let(:expected_tokens) { [Tokens::CLOSE_SQUARE, Tokens::CLOSE_SQUARE] }

      include_examples "token_matching"
    end

    context "tokenize open and close square brackets" do
      let(:test_string) { "[]" }
      let(:expected_tokens) { [Tokens::OPEN_SQUARE, Tokens::CLOSE_SQUARE] }

      include_examples "token_matching"
    end
  end

  ####################
  # comma, colon, equals, plus equals
  ####################
  context "tokenizing comma, colon, equals, and plus equals" do
    context "tokenize comma" do
      let(:test_string) { "," }
      let(:expected_tokens) { [Tokens::COMMA] }

      include_examples "token_matching"
    end

    context "tokenize colon" do
      let(:test_string) { ":" }
      let(:expected_tokens) { [Tokens::COLON] }

      include_examples "token_matching"
    end

    context "tokenize equals" do
      let(:test_string) { "=" }
      let(:expected_tokens) { [Tokens::EQUALS] }

      include_examples "token_matching"
    end

    context "tokenize plus equals" do
      let(:test_string) { "+=" }
      let(:expected_tokens) { [Tokens::PLUS_EQUALS] }

      include_examples "token_matching"
    end

    context "tokenize comma, colon, plus equals, and equals together" do
      let(:test_string) { "=:,+=" }
      let(:expected_tokens) { [Tokens::EQUALS,
                               Tokens::COLON,
                               Tokens::COMMA,
                               Tokens::PLUS_EQUALS] }

      include_examples "token_matching"
    end
  end

  ####################
  # Substitutions
  ####################
  context "tokenizing substitutions" do
    context "tokenize substitution" do
      let(:test_string) { "${a.b}" }
      let(:expected_tokens) { [TestUtils.token_substitution(TestUtils.token_unquoted("a.b"))] }

      include_examples "token_matching"
    end

    context "tokenize optional substitution" do
      let(:test_string) { "${?x.y}" }
      let(:expected_tokens) { [TestUtils.token_optional_substitution(TestUtils.token_unquoted("x.y"))] }

      include_examples "token_matching"
    end

    context "tokenize key substitution" do
      let(:test_string) { '${"c.d"}' }
      let(:expected_tokens) { [TestUtils.token_key_substitution("c.d")] }

      include_examples "token_matching"
    end
  end

  ####################
  # Unicode and escape characters
  ####################
  context "tokenizing unicode and escape characters" do
    context "tokenize unicode infinity symbol" do
      let(:test_string) { '"\u221E"' }
      let(:expected_tokens) { [TestUtils.token_string("\u{221E}")] }

      include_examples "token_matching"
    end

    context "tokenize null byte" do
      let(:test_string) { ' "\u0000" ' }
      let(:expected_tokens) { [TestUtils.token_whitespace(" "),
                               TestUtils.token_string("\u0000"),
                               TestUtils.token_whitespace(" ")] }

      include_examples "token_matching"
    end

    context "tokenize various espace codes" do
      let(:test_string) { ' "\"\\\/\b\f\n\r\t" ' }
      let(:expected_tokens) { [TestUtils.token_whitespace(" "),
                              TestUtils.token_string("\"\\/\b\f\n\r\t"),
                              TestUtils.token_whitespace(" ")] }

      include_examples "token_matching"
    end

    context "tokenize unicode F" do
      let(:test_string) { ' "\u0046" ' }
      let(:expected_tokens) { [TestUtils.token_whitespace(" "),
                               TestUtils.token_string("F"),
                               TestUtils.token_whitespace(" ")] }

      include_examples "token_matching"
    end

    context "tokenize two unicode Fs" do
      let(:test_string) { ' "\u0046\u0046" ' }
      let(:expected_tokens) { [TestUtils.token_whitespace(" "),
                               TestUtils.token_string("FF"),
                               TestUtils.token_whitespace(" ")] }

      include_examples "token_matching"
    end
  end

  ####################
  # Reserved Characters
  ####################
  context "Finding problems with using reserved characters" do
    context "problem with reserved character +" do
      let(:test_string) { "+" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character `" do
      let(:test_string) { "`" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character ^" do
      let(:test_string) { "^" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character ?" do
      let(:test_string) { "?" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character !" do
      let(:test_string) { "!" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character @" do
      let(:test_string) { "@" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character *" do
      let(:test_string) { "*" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character &" do
      let(:test_string) { "&" }
      include_examples "strings_with_problems"
    end

    context "problem with reserved character \\" do
      let(:test_string) { "\\" }
      include_examples "strings_with_problems"
    end
  end

  ####################
  # Combine all types
  ####################
  context "Tokenizing all types together" do
    context "tokenize all types no spaces" do
      let(:test_string) { ',:=}{][+="foo""""bar"""true3.14false42null${a.b}${?x.y}${"c.d"}' + "\n" }
      let(:expected_tokens) { [Tokens::COMMA,
                               Tokens::COLON,
                               Tokens::EQUALS,
                               Tokens::CLOSE_CURLY,
                               Tokens::OPEN_CURLY,
                               Tokens::CLOSE_SQUARE,
                               Tokens::OPEN_SQUARE,
                               Tokens::PLUS_EQUALS,
                               TestUtils.token_string("foo"),
                               TestUtils.token_string("bar"),
                               TestUtils.token_true,
                               TestUtils.token_double(3.14),
                               TestUtils.token_false,
                               TestUtils.token_int(42),
                               TestUtils.token_null,
                               TestUtils.token_substitution(TestUtils.token_unquoted("a.b")),
                               TestUtils.token_optional_substitution(TestUtils.token_unquoted("x.y")),
                               TestUtils.token_key_substitution("c.d"),
                               TestUtils.token_line(1)] }

      include_examples "token_matching"
    end

    context "tokenize all types single spaces" do
      let(:test_string) { ' , : = } { ] [ += "foo" """bar""" 42 true 3.14 false null ${a.b} ${?x.y} ${"c.d"} ' + "\n " }
      let(:expected_tokens) { [TestUtils.token_whitespace(" "),
                               Tokens::COMMA,
                               TestUtils.token_whitespace(" "),
                               Tokens::COLON,
                               TestUtils.token_whitespace(" "),
                               Tokens::EQUALS,
                               TestUtils.token_whitespace(" "),
                               Tokens::CLOSE_CURLY,
                               TestUtils.token_whitespace(" "),
                               Tokens::OPEN_CURLY,
                               TestUtils.token_whitespace(" "),
                               Tokens::CLOSE_SQUARE,
                               TestUtils.token_whitespace(" "),
                               Tokens::OPEN_SQUARE,
                               TestUtils.token_whitespace(" "),
                               Tokens::PLUS_EQUALS,
                               TestUtils.token_whitespace(" "),
                               TestUtils.token_string("foo"),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_string("bar"),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_int(42),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_true,
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_double(3.14),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_false,
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_null,
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_substitution(TestUtils.token_unquoted("a.b")),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_optional_substitution(TestUtils.token_unquoted("x.y")),
                               TestUtils.token_unquoted(" "),
                               TestUtils.token_key_substitution("c.d"),
                               TestUtils.token_whitespace(" "),
                               TestUtils.token_line(1),
                               TestUtils.token_whitespace(" ")] }

      include_examples "token_matching"
    end

    context "tokenize all types multiple spaces" do
      let(:test_string) { '   ,   :   =   }   {   ]   [   +=   "foo"   """bar"""   42   true   3.14   false   null   ${a.b}   ${?x.y}   ${"c.d"}   ' + "\n   " }
      let(:expected_tokens) { [TestUtils.token_whitespace("   "),
                               Tokens::COMMA,
                               TestUtils.token_whitespace("   "),
                               Tokens::COLON,
                               TestUtils.token_whitespace("   "),
                               Tokens::EQUALS,
                               TestUtils.token_whitespace("   "),
                               Tokens::CLOSE_CURLY,
                               TestUtils.token_whitespace("   "),
                               Tokens::OPEN_CURLY,
                               TestUtils.token_whitespace("   "),
                               Tokens::CLOSE_SQUARE,
                               TestUtils.token_whitespace("   "),
                               Tokens::OPEN_SQUARE,
                               TestUtils.token_whitespace("   "),
                               Tokens::PLUS_EQUALS,
                               TestUtils.token_whitespace("   "),
                               TestUtils.token_string("foo"),
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_string("bar"),
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_int(42),
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_true,
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_double(3.14),
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_false,
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_null,
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_substitution(TestUtils.token_unquoted("a.b")),
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_optional_substitution(TestUtils.token_unquoted("x.y")),
                               TestUtils.token_unquoted("   "),
                               TestUtils.token_key_substitution("c.d"),
                               TestUtils.token_whitespace("   "),
                               TestUtils.token_line(1),
                               TestUtils.token_whitespace("   ")] }

      include_examples "token_matching"
    end
  end
end
