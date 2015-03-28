# encoding: utf-8

require 'spec_helper'
require 'hocon/config_factory'
require 'hocon/config_render_options'
require 'hocon/config_value_factory'

describe Hocon::Impl::SimpleConfig do
  let(:render_options) { Hocon::ConfigRenderOptions.defaults }

  before do
    render_options.origin_comments = false
    render_options.json = false
  end

  shared_examples_for "config_value_retrieval_single_value" do
    let(:input_file)  { "#{FIXTURE_DIR}/parse_render/#{example[:name]}/input.conf" }
    it "should allow you to get a value for a specific configuration setting" do
      expect(conf.get_value(setting).transform_to_string).to eq(expected_setting)
    end
  end

  shared_examples_for "config_value_retrieval_config_list" do
    let(:input_file)  { "#{FIXTURE_DIR}/parse_render/#{example[:name]}/input.conf" }
    it "should allow you to get a value for a setting whose value is a data structure" do
      expect(conf.get_value(setting).
                 render_value_to_sb(StringIO.new, 2, nil,
                                    Hocon::ConfigRenderOptions.new(false, false, false, false)).
                 string).to eq(expected_setting)
    end
  end

  shared_examples_for "has_path_check" do
    let(:input_file) { "#{FIXTURE_DIR}/parse_render/#{example[:name]}/input.conf" }
    it "should return true if a path exists" do
      expect(conf.has_path?(setting)).to eql(true)
    end

    it "should return false if a path does not exist" do
      expect(conf.has_path?(false_setting)).to eq(false)
    end
  end

  shared_examples_for "add_value_to_config" do
    let(:input_file) { "#{FIXTURE_DIR}/parse_render/#{example[:name]}/input.conf" }
    it "should add desired setting with desired value" do
      modified_conf = conf.with_value(setting_to_add, value_to_add)
      expect(modified_conf.get_value(setting_to_add)).to eq(value_to_add)
    end
  end

  shared_examples_for "add_data_structures_to_config" do
    let(:input_file) { "#{FIXTURE_DIR}/parse_render/#{example[:name]}/input.conf" }
    it "should add a nested map to a config" do
      map = Hocon::ConfigValueFactory.from_any_ref({"a" => "b", "c" => {"d" => "e"}}, nil)
      modified_conf = conf.with_value(setting_to_add, map)
      expect(modified_conf.get_value(setting_to_add)).to eq(map)
    end

    it "should add an array to a config" do
      array = Hocon::ConfigValueFactory.from_any_ref([1,2,3,4,5], nil)
      modified_conf = conf.with_value(setting_to_add, array)
      expect(modified_conf.get_value(setting_to_add)).to eq(array)
    end
  end

  shared_examples_for "remove_value_from_config" do
    let(:input_file) { "#{FIXTURE_DIR}/parse_render/#{example[:name]}/input.conf" }
    it "should remove desired setting" do
      modified_conf = conf.without_path(setting_to_remove)
      expect(modified_conf.has_path?(setting_to_remove)).to be false
    end
  end

  context "example1" do
    let(:example) { EXAMPLE1 }
    let(:setting) { "foo.bar.yahoo" }
    let(:expected_setting) { "yippee" }
    let(:false_setting) { "non-existent" }
    let(:setting_to_add) { "foo.bar.test" }
    let(:value_to_add) { Hocon::Impl::ConfigString.new(nil, "This is a test string") }
    let(:setting_to_remove) { "foo.bar" }

    context "parsing a .conf file" do
      let(:conf) { Hocon::ConfigFactory.parse_file(input_file) }
      include_examples "config_value_retrieval_single_value"
      include_examples "has_path_check"
      include_examples "add_value_to_config"
      include_examples "add_data_structures_to_config"
      include_examples "remove_value_from_config"
    end
  end

  context "example2" do
    let(:example) { EXAMPLE2 }
    let(:setting) { "jruby-puppet.jruby-pools" }
    let(:expected_setting) { "[{environment=production}]" }
    let(:false_setting) { "jruby-puppet-false" }
    let(:setting_to_add) { "top" }
    let(:value_to_add) { Hocon::Impl::ConfigInt.new(nil, 12345, "12345") }
    let(:setting_to_remove) { "jruby-puppet.master-conf-dir" }

    context "parsing a .conf file" do
      let(:conf) { Hocon::ConfigFactory.parse_file(input_file) }
      include_examples "config_value_retrieval_config_list"
      include_examples "has_path_check"
      include_examples "add_value_to_config"
      include_examples "add_data_structures_to_config"
      include_examples "remove_value_from_config"
    end
  end
end
