# encoding: utf-8

require 'hocon/impl'
require 'hocon/impl/tokens'

class Hocon::Impl::ConfigNodePath
  Tokens = Hocon::Impl::Tokens

  def initialize(path, tokens)
    @path = path
    @tokens = tokens
  end

  attr_reader :tokens

  def value
    @path
  end

  def sub_path(to_remove)
    period_count = 0
    tokens_copy = tokens.clone
    (0..tokens_copy.size - 1).each do |i|
      if Tokens.unquoted_text?(tokens_copy[i]) &&
          t.token_text == "."
        period_count += 1
      end

      if period_count == to_remove
        return ConfigNodePath.new(@path.sub_path(to_remove), tokens_copy[i + 1..tokens_copy.size])
      end
    end
    raise ConfigBugOrBrokenError, "Tried to remove too many elements from a Path node"
  end

  def first
    tokens_copy = tokens.clone
    (0..tokens_copy.size - 1).each do |i|
      if Tokens.is_unquoted_text(tokens_copy[i]) &&
          tokens_copy[i].token_text == "."
        ConfigNodePath.new(@path[0, 1], tokens_copy[0, 1])
      end
    end
    self
  end
end
