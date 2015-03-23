require 'hocon/impl'
require 'hocon/impl/unmergeable'

class Hocon::Impl::ConfigDelayedMergeObject < Hocon::Impl::AbstractConfigObject
  include Hocon::Impl::Unmergeable
  include Hocon::Impl::ReplaceableMergeStack

  def initialize(origin, stack)
    super(origin)

    @stack = stack

    if stack.empty?
      raise Hocon::ConfigError::ConfigBugOrBrokenError.new("creating empty delayed merge value", nil)
    end

    if !@stack[0].is_a? Hocon::Impl::AbstractConfigObject
      error_message = "created a delayed merge object not guaranteed to be an object"
      raise Hocon::ConfigError::ConfigBugOrBrokenError.new(error_message, nil)
    end

    stack.each do |v|
      if v.is_a?(Hocon::Impl::ConfigDelayedMergeObject) || v.is_a?(Hocon::Impl::ConfigDelayedMergeObject)
        error_message = "placed nested DelayedMerge in a ConfigDelayedMerge, should have consolidated stack"
        raise Hocon::ConfigError::ConfigBugOrBrokenError.new(error_message, nil)
      end
    end
  end

  attr_reader :stack

  def self.not_resolved
    error_message = "need to Config#resolve() before using this object, see the API docs for Config#resolve()"
    Hocon::ConfigError::ConfigNotResolvedError.new(error_message, nil)
  end

  def unwrapped
    raise self.class.not_resolved
  end

  def [](key)
    raise self.class.not_resolved
  end

  def has_key?(key)
    raise self.class.not_resolved
  end

  def has_value?(value)
    raise self.class.not_resolved
  end

  def each
    raise self.class.not_resolved
  end

  def empty?
    raise self.class.not_resolved
  end

  def keys
    raise self.class.not_resolved
  end

  def values
    raise self.class.not_resolved
  end

  def size
    raise self.class.not_resolved
  end

  def self.unmergeable?(object)
    # Ruby note: This is the best way I could find to simulate
    # else if (layer instanceof Unmergeable) in java since we're including
    # the Unmergeable module instead of extending an Unmergeable class
    object.class.included_modules.include?(Hocon::Impl::Unmergeable)
  end

  def attempt_peek_with_partial_resolve(key)
    # a partial resolve of a ConfigDelayedMergeObject always results in a
    # SimpleConfigObject because all the substitutions in the stack get
    # resolved in order to look up the partial.
    # So we know here that we have not been resolved at all even
    # partially.
    # Given that, all this code is probably gratuitous, since the app code
    # is likely broken. But in general we only throw NotResolved if you try
    # to touch the exact key that isn't resolved, so this is in that
    # spirit.

    # we'll be able to return a key if we have a value that ignores
    # fallbacks, prior to any unmergeable values.
    @stack.each do |layer|
      if layer.is_a?(Hocon::Impl::AbstractConfigObject)
        v = layer.attempt_peek_with_partial_resolve(key)

        if !v.nil?
          if v.ignores_fallbacks
            # we know we won't need to merge anything in to this
            # value
            return v
          else
            # we can't return this value because we know there are
            # unmergeable values later in the stack that may
            # contain values that need to be merged with this
            # value. we'll throw the exception when we get to those
            # unmergeable values, so continue here.
            next
          end
        elsif self.class.unmergeable?(layer)
          error_message = "should not be reached: unmergeable object returned null value"
          raise Hocon::ConfigError::ConfigBugOrBrokenError.new(error_message, nil)
        else
          # a non-unmergeable AbstractConfigObject that returned null
          # for the key in question is not relevant, we can keep
          # looking for a value.
          next
        end
      elsif self.class.unmergeable?(layer)
        error_message = "Key '#{key}' is not available at '#{origin.description}'" +
            "because value at '#{layer.origin.description}' has not been resolved" +
            " and may turn out to contain or hide '#{key}'. Be sure to Config#resolve()" +
            " before using a config object"
        raise Hocon::ConfigError::ConfigNotResolvedError.new(error_message, nil)
      elsif layer.resolved_status == ResolveStatus::UNRESOLVED
        # if the layer is not an object, and not a substitution or
        # merge,
        # then it's something that's unresolved because it _contains_
        # an unresolved object... i.e. it's an array
        if !layer.is_a?(Hocon::Impl::ConfigList)
          error_message = "Expecting a list here, not #{layer}"
          raise Hocon::ConfigError::ConfigBugOrBrokenError.new(error_message, nil)
        end
        return nil
      else
        # non-object, but resolved, like an integer or something.
        # has no children so the one we're after won't be in it.
        # we would only have this in the stack in case something
        # else "looks back" to it due to a cycle.
        # anyway at this point we know we can't find the key anymore.
        if !layer.ignores_fallbacks
          error_message = "resolved non-object should ignore fallbacks"
          raise Hocon::ConfigError::ConfigBugOrBrokenError.new(error_message, nil)
        end
        return nil
      end
    end

    # If we get here, then we never found anything unresolved which means
    # the ConfigDelayedMergeObject should not have existed. some
    # invariant was violated.
    error_message = "Delayed merge stack does not contain any unmergeable values"
    raise Hocon::ConfigError::ConfigBugOrBrokenError.new(error_message, nil)
  end

  def can_equal(other)
    other.is_a? Hocon::Impl::ConfigDelayedMergeObject
  end

  def ==(other)
    # note that "origin" is deliberately NOT part of equality
    if other.is_a? Hocon::Impl::ConfigDelayedMergeObject
      can_equal(other) && (@stack == other.stack || @stack.equal?(other.stack))
    else
      false
    end
  end

  def hash
    # note that "origin" is deliberately NOT part of equality
    @stack.hash
  end
end
