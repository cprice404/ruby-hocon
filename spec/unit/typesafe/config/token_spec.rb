# encoding: utf-8

require 'spec_helper'
require 'hocon'
require 'test_utils'
require 'pp'


describe Hocon::Impl::Token do
  Tokens = Hocon::Impl::Tokens

  ####################
  # Equality
  ####################
  context "check token equality" do
    context "syntax tokens" do
      let(:first_object) { Tokens::START }
      let(:second_object) { Tokens::START }

      include_examples "object_equality"
    end

    context "integer tokens" do
      let(:first_object) { TestUtils.token_int(42) }
      let(:second_object) { TestUtils.token_int(42) }

      include_examples "object_equality"
    end

    context "truth tokens" do
      let(:first_object) { TestUtils.token_true }
      let(:second_object) { TestUtils.token_true }

      include_examples "object_equality"
    end

    context "int and double of the same value" do
      let(:first_object) { TestUtils.token_int(10) }
      let(:second_object) { TestUtils.token_double(10.0) }

      include_examples "object_equality"
    end

    context "double tokens" do
      let(:first_object) { TestUtils.token_int(3.14) }
      let(:second_object) { TestUtils.token_int(3.14) }

      include_examples "object_equality"
    end

    context "quoted string tokens" do
      let(:first_object) { TestUtils.token_string("foo") }
      let(:second_object) { TestUtils.token_string("foo") }

      include_examples "object_equality"
    end

    context "unquoted string tokens" do
      let(:first_object) { TestUtils.token_unquoted("foo") }
      let(:second_object) { TestUtils.token_unquoted("foo") }

      include_examples "object_equality"
    end

    context "key substitution tokens" do
      let(:first_object) { TestUtils.token_key_substitution("foo") }
      let(:second_object) { TestUtils.token_key_substitution("foo") }

      include_examples "object_equality"
    end

    context "null tokens" do
      let(:first_object) { TestUtils.token_null }
      let(:second_object) { TestUtils.token_null }

      include_examples "object_equality"
    end

    context "newline tokens" do
      let(:first_object) { TestUtils.token_line(10) }
      let(:second_object) { TestUtils.token_line(10) }

      include_examples "object_equality"
    end
  end


  ####################
  # Inequality
  ####################
  context "check token inequality" do
    context "syntax tokens" do
      let(:first_object) { Tokens::START }
      let(:second_object) { Tokens::OPEN_CURLY }

      include_examples "object_inequality"
    end

    context "integer tokens" do
      let(:first_object) { TestUtils.token_int(42) }
      let(:second_object) { TestUtils.token_int(43) }

      include_examples "object_inequality"
    end

    context "double tokens" do
      let(:first_object) { TestUtils.token_int(3.14) }
      let(:second_object) { TestUtils.token_int(4.14) }

      include_examples "object_inequality"
    end

    context "truth tokens" do
      let(:first_object) { TestUtils.token_true }
      let(:second_object) { TestUtils.token_false }

      include_examples "object_inequality"
    end

    context "quoted string tokens" do
      let(:first_object) { TestUtils.token_string("foo") }
      let(:second_object) { TestUtils.token_string("bar") }

      include_examples "object_inequality"
    end

    context "unquoted string tokens" do
      let(:first_object) { TestUtils.token_unquoted("foo") }
      let(:second_object) { TestUtils.token_unquoted("bar") }

      include_examples "object_inequality"
    end

    context "key substitution tokens" do
      let(:first_object) { TestUtils.token_key_substitution("foo") }
      let(:second_object) { TestUtils.token_key_substitution("bar") }

      include_examples "object_inequality"
    end

    context "newline tokens" do
      let(:first_object) { TestUtils.token_line(10) }
      let(:second_object) { TestUtils.token_line(11) }

      include_examples "object_inequality"
    end

    context "true and int tokens" do
      let(:first_object) { TestUtils.token_true }
      let(:second_object) { TestUtils.token_int(1) }

      include_examples "object_inequality"
    end

    context "string 'true' and true tokens" do
      let(:first_object) { TestUtils.token_true }
      let(:second_object) { TestUtils.token_string("true") }

      include_examples "object_inequality"
    end

    context "int and double of slightly different values" do
      let(:first_object) { TestUtils.token_int(10) }
      let(:second_object) { TestUtils.token_double(10.000001) }

      include_examples "object_inequality"
    end
  end

  context "Check that to_s doesn't throw exception" do
    it "shouldn't throw an exception" do
      # just be sure to_s doesn't throw an exception. It's for debugging
      # so its exact output doesn't matter a lot
      TestUtils.token_true.to_s
      TestUtils.token_false.to_s
      TestUtils.token_int(42).to_s
      TestUtils.token_double(3.14).to_s
      TestUtils.token_null.to_s
      TestUtils.token_unquoted("foo").to_s
      TestUtils.token_string("bar").to_s
      TestUtils.token_key_substitution("a").to_s
      TestUtils.token_line(10).to_s
      Tokens::START.to_s
      Tokens::EOF.to_s
      Tokens::COLON.to_s
    end
  end
end
