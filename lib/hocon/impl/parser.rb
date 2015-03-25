# encoding: utf-8

require 'stringio'
require 'hocon/impl'
require 'hocon/impl/tokens'
require 'hocon/impl/path_builder'
require 'hocon/config_syntax'
require 'hocon/config_value_type'
require 'hocon/impl/config_string'
require 'hocon/impl/config_concatenation'
require 'hocon/config_error'
require 'hocon/impl/simple_config_list'
require 'hocon/impl/simple_config_object'
require 'hocon/impl/config_impl_util'
require 'hocon/impl/tokenizer'
require 'hocon/impl/simple_config_origin'
require 'hocon/impl/path'
require 'hocon/impl/url'
require 'hocon/impl/config_reference'
require 'hocon/impl/substitution_expression'
require 'hocon/impl/path_parser'
require 'hocon/impl/array_iterator'

class Hocon::Impl::Parser
  
  Tokens = Hocon::Impl::Tokens
  ConfigSyntax = Hocon::ConfigSyntax
  ConfigValueType = Hocon::ConfigValueType
  ConfigConcatenation = Hocon::Impl::ConfigConcatenation
  ConfigReference = Hocon::Impl::ConfigReference
  ConfigParseError = Hocon::ConfigError::ConfigParseError
  ConfigBugOrBrokenError = Hocon::ConfigError::ConfigBugOrBrokenError
  ConfigBadPathError = Hocon::ConfigError::ConfigBadPathError
  SimpleConfigObject = Hocon::Impl::SimpleConfigObject
  SimpleConfigList = Hocon::Impl::SimpleConfigList
  SimpleConfigOrigin = Hocon::Impl::SimpleConfigOrigin
  ConfigImplUtil = Hocon::Impl::ConfigImplUtil
  PathBuilder = Hocon::Impl::PathBuilder
  Tokenizer = Hocon::Impl::Tokenizer
  Path = Hocon::Impl::Path

  def self.parse(tokens, origin, options, include_context)
    context = Hocon::Impl::Parser::ParseContext.new(
        options.syntax, origin, tokens,
        Hocon::Impl::SimpleIncluder.make_full(options.includer),
        include_context)
    context.parse
  end
  
  class TokenWithComments
    def initialize(token, comments = [])
      @token = token
      @comments = comments

      if Tokens.comment?(token)
        raise Hocon::ConfigError::ConfigBugOrBrokenError, "tried to annotate a comment with a comment"
      end
    end

    attr_reader :token, :comments

    def remove_all
      if @comments.empty?
        self
      else
        TokenWithComments.new(@token)
      end
    end

    def prepend(earlier)
      if earlier.empty?
        self
      elsif @comments.empty?
        TokenWithComments.new(@token, earlier)
      else
        merged = []
        merged.concat(earlier)
        merged.concat(@comments)
        TokenWithComments.new(@token, merged)
      end
    end

    def add(after)
      if @comments.empty?
        TokenWithComments.new(@token, [after])
      else
        merged = Array.new
        merged += @comments
        merged.push(after)
        TokenWithComments.new(@token, merged)
      end
    end

    def prepend_comments(origin)
      if @comments.empty?
        origin
      else
        new_comments = @comments.map { |c| Tokens.comment_text(c) }
        origin.prepend_comments(new_comments)
      end
    end

    def append_comments(origin)
      if @comments.empty?
        origin
      else
        new_comments = @comments.map { |c| Tokens.comment_text(c) }
        origin.append_comments(new_comments)
      end
    end

    def to_s
      # this ends up in user-visible error messages, so we don't want the
      # comments
      @token.to_s
    end
  end

  class ParseContext
    def initialize(flavor, origin, tokens, includer, include_context)
      @line_number = 1
      @buffer = []
      @tokens = tokens
      @flavor = flavor
      @base_origin = origin
      @includer = includer
      @include_context = include_context
      @path_stack = []
      # this is the number of "equals" we are inside,
      # used to modify the error message to reflect that
      # someone may think this is .properties format.
      @equals_count = 0
      # the number of lists we are inside; this is used to detect the "cannot
      # generate a reference to a list element" problem, and once we fix that
      # problem we should be able to get rid of this variable.
      @array_count = 0
    end

    def self.attracts_trailing_comments?(token)
      # EOF can't have a trailing comment; START, OPEN_CURLY, and
      # OPEN_SQUARE followed by a comment should behave as if the comment
      # went with the following field or element. Associating a comment
      # with a newline would mess up all the logic for comment tracking,
      # so don't do that either.
      !(Tokens.newline?(token) ||
        token == Tokens::START ||
        token == Tokens::OPEN_CURLY ||
        token == Tokens::OPEN_SQUARE ||
        token == Tokens::EOF)
    end

    def self.attracts_leading_comments?(token)
      # a comment just before a close } generally doesn't go with the
      # value before it, unless it's on the same line as that value
      !(Tokens.newline?(token) ||
          token == Tokens::START ||
          token == Tokens::CLOSE_CURLY ||
          token == Tokens::CLOSE_SQUARE ||
          token == Tokens::EOF)
    end

    def consolidate_comment_block(comment_token)
      # a comment block "goes with" the following token
      # unless it's separated from it by a blank line.
      # we want to build a list of newline tokens followed
      # by a non-newline non-comment token; with all comments
      # associated with that final non-newline non-comment token.
      # a comment AFTER a token, without an intervening newline,
      # also goes with that token, but isn't handled in this method,
      # instead we handle it later by peeking ahead.
      new_lines = []
      comments = []

      previous_token = nil
      next_token = comment_token
      while true
        if Tokens.newline?(next_token)
          if (previous_token != nil) && Tokens.newline?(previous_token)
            # blank line; drop all comments to this point and
            # start a new comment block
            comments.clear
          end
          new_lines.push(next_token)
        elsif Tokens.comment?(next_token)
          comments.push(next_token)
        else
          # a non-newline non-comment token

          # comments before a close brace or bracket just get dumped
          unless self.class.attracts_leading_comments?(next_token)
            comments.clear
          end
          break
        end

        previous_token = next_token
        next_token = next_token_ignoring_whitespace
      end

      # put our concluding token in the queue with all the comments
      # attached
      @buffer.push(TokenWithComments.new(next_token, comments))

      # now put all the newlines back in front of it
      new_lines.reverse.each do |nl|
        @buffer.push(TokenWithComments.new(nl))
      end
    end

    def pop_token_without_trailing_comment
      if @buffer.empty?
        t = next_token_ignoring_whitespace
        if Tokens.comment?(t)
          consolidate_comment_block(t)
          @buffer.pop
        else
          TokenWithComments.new(t)
        end
      else
        @buffer.pop
      end
    end

    def pop_token
      with_preceding_comments = pop_token_without_trailing_comment
      # handle a comment AFTER the other token,
      # but before a newline. If the next token is not
      # a comment, then any comment later on the line is irrelevant
      # since it would end up going with that later token, not
      # this token. Comments are supposed to be processed prior
      # to adding stuff to the buffer, so they can only be found
      # in "tokens" not in "buffer" in theory.
      if !self.class.attracts_trailing_comments?(with_preceding_comments.token)
        with_preceding_comments
      elsif @buffer.empty?
        after = next_token_ignoring_whitespace
        if Tokens.comment?(after)
          with_preceding_comments.add(after)
        else
          @buffer << TokenWithComments.new(after)
          with_preceding_comments
        end
      else
        # comments are supposed to get attached to a token,
        # not put back in the buffer. Assert this as an invariant.
        if Tokens.comment?(@buffer.last.token)
          raise Hocon::ConfigError::ConfigBugOrBrokenError, "comment token should not have been in buffer: #{@buffer}"
        end
        with_preceding_comments
      end
    end

    def next_token
      with_comments = pop_token
      t = with_comments.token

      if Tokens.problem?(t)
        origin = t.origin
        message = Tokens.get_problem_message(t)
        cause = Tokens.get_problem_cause(t)
        suggest_quotes = Tokens.get_problem_suggest_quotes(t)
        if suggest_quotes
          message = add_quote_suggestion(t.to_s, message)
        else
          message = add_key_name(message)
        end
        raise ConfigParseError.new(origin, message, cause)
      else
        if @syntax == ConfigSyntax::JSON
          if Tokens.unquoted_text?(t)
            raise parse_error(add_key_name("Token not allowed in valid JSON: '#{Tokens.unquoted_text(t)}'"))
          elsif Tokens.substitution?(t)
            raise parse_error(add_key_name("Substitutions (${} syntax) not allowed in JSON"))
          end
        end

        with_comments
      end
    end

    def put_back(token)
      if Tokens.comment?(token.token)
        raise Hocon::ConfigError::ConfigBugOrBrokenError, "comment token should have been stripped before it was available to put back"
      end
      @buffer.push(token)
    end

    def next_token_ignoring_newline
      t = next_token
      while Tokens.newline?(t.token)
        # line number tokens have the line that was _ended_ by the
        # newline, so we have to add one. We have to update lineNumber
        # here and also below, because not all tokens store a line
        # number, but newline tokens always do.
        @line_number = t.token.line_number + 1

        t = next_token
      end

      # update line number again, if we have one
      new_number = t.token.line_number
      if new_number >= 0
        @line_number = new_number
      end

      t
    end

    # Grabs the next Token off of the TokenIterator, ignoring
    # IgnoredWhitespace tokens
    def next_token_ignoring_whitespace
      t = @tokens.next
      while Tokens.ignore_whitespace?(t)
        t = @tokens.next
      end
      t
    end

    def add_any_comments_after_any_comma(v)
      t = next_token  # do NOT skip newlines, we only
      # want same-line comments
      if t.token == Tokens::COMMA
        # steal the comments from after the comma
        put_back(t.remove_all)
        v.with_origin(t.append_comments(v.origin))
      else
        put_back(t)
        v
      end
    end

    # In arrays and objects, comma can be omitted
    # as long as there's at least one newline instead.
    # this skips any newlines in front of a comma,
    # skips the comma, and returns true if it found
    # either a newline or a comma. The iterator
    # is left just after the comma or the newline.
    def check_element_separator
      if @flavor == ConfigSyntax::JSON
        t = next_token_ignoring_newline
        if (t.token == Tokens::COMMA)
          true
        else
          put_back(t)
          false
        end
      else
        saw_separator_or_newline = false
        t = next_token
        while true
          if Tokens.newline?(t.token)
            # newline number is the line just ended, so add one
            @line_number = t.token.line_number + 1
            saw_separator_or_newline = true

            # we want to continue to also eat a comma if there is one
          elsif t.token == Tokens::COMMA
            return true
          else
            # non-newline-or-comma
            put_back(t)
            return saw_separator_or_newline
          end
          t = next_token
        end
      end
    end

    def self.token_to_substitution_expression(value_token)
      expression = Tokens.get_substitution_path_expression(value_token)
      path = Hocon::Impl::PathParser.parse_path_expression(
          Hocon::Impl::ArrayIterator.new(expression),
          value_token.origin)
      optional = Tokens.get_substitution_optional(value_token)

      Hocon::Impl::SubstitutionExpression.new(path, optional)
    end

    # merge a bunch of adjacent values into one
    # value; change unquoted text into a string
    # value.
    def consolidate_value_tokens
      # this trick is not done in JSON
      return if @flavor == ConfigSyntax::JSON

      # create only if we have value tokens
      values = nil

      # ignore a newline up front
      t = next_token_ignoring_newline
      while true
        v = nil
        if (Tokens.value?(t.token)) || (Tokens.unquoted_text?(t.token)) ||
            (Tokens.substitution?(t.token)) || (t.token == Tokens::OPEN_CURLY) ||
            (t.token == Tokens::OPEN_SQUARE)
          # there may be newlines _within_ the objects and arrays
          v = parse_value(t)
        else
          break
        end

        if v.nil?
          raise Hocon::ConfigError::ConfigBugOrBrokenError, "no value"
        end

        if values.nil?
          values = []
        end
        values.push(v)

        t = next_token # but don't consolidate across a newline
      end
      # the last one wasn't a value token
      put_back(t)

      return if values.nil?

      consolidated = ConfigConcatenation.concatenate(values)

      put_back(TokenWithComments.new(Tokens.new_value(consolidated)))
    end

    def line_origin
      @base_origin.with_line_number(@line_number)
    end

    def parse_error(message, cause = nil)
      ConfigParseError.new(line_origin, message, cause)
    end

    def previous_field_name(last_path = nil)
      if !last_path.nil?
        last_path.render
      elsif @path_stack.empty?
        nil
      else
        @path_stack[0].render
      end
    end

    def full_current_path()
      # pathStack has top of stack at front
      if @path_stack.empty?
        raise Hocon::ConfigError::ConfigBugOrBrokenError,
              "Bug in parser; tried to get current path when at root"
      else
        Path.new(@path_stack.descending_iterator)
      end
    end

    def add_key_name(message)
      prev_field_name = previous_field_name
      if !prev_field_name.nil?
        "in value for key '#{prev_field_name}': #{message}"
      else
        message
      end
    end

    def add_quote_suggestion(bad_token, message, last_path = nil, inside_equals = (@equals_count > 0))
      prev_field_name = previous_field_name(last_path)
      part =
          if bad_token == Tokens::EOF.to_s
            # EOF requires special handling for the error to make sense.
            if !prev_field_name.nil?
              "#{message} (if you intended '#{prev_field_name}' " +
                  "to be part of a value, instead of a key, " +
                  "try adding double quotes around the whole value"
            else
              message
            end
          else
            if !prev_field_name.nil?
              "#{message} (if you intended #{bad_token} " +
                  "to be part of the value for '#{prev_field_name}', " +
                  "try enclosing the value in double quotes"
            else
              "#{message} (if you intended #{bad_token} " +
                  "to be part of a key or string value, " +
                  "try enclosing the key or value in double quotes"
            end
          end

      if inside_equals
        "#{part}, or you may be able to rename the file .properties rather than .conf)"
      else
        "#{part})"
      end
    end

    def parse_value(t)
      v = nil

      starting_array_count = @array_count
      starting_equals_count = @equals_count

      if Tokens.value?(t.token)
        # if we consolidateValueTokens() multiple times then
        # this value could be a concatenation, object, array,
        # or substitution already.
        v = Tokens.value(t.token)
      elsif Tokens.unquoted_text?(t.token)
        v = Hocon::Impl::ConfigString.new(t.token.origin, Tokens.unquoted_text(t.token))
      elsif Tokens.substitution?(t.token)
        v = ConfigReference.new(t.token.origin,
                                self.class.token_to_substitution_expression(t.token))
      elsif t.token == Tokens::OPEN_CURLY
        v = parse_object(true)
      elsif t.token == Tokens::OPEN_SQUARE
        v = parse_array
      else
        raise parse_error(
                  add_quote_suggestion(t.token.to_s,
                                       "Expecting a value but got wrong token: #{t.token}"))
      end

      v = v.with_origin(t.prepend_comments(v.origin))

      if @array_count != starting_array_count
        raise Hocon::ConfigError::ConfigBugOrBrokenError, "Bug in config parser: unbalanced array count"
      end
      if @equals_count != starting_equals_count
        raise Hocon::ConfigError::ConfigBugOrBrokenError, "Bug in config parser: unbalanced equals count"
      end

      v
    end

    def create_value_under_path(path, value)
      # for path foo.bar, we are creating
      # { "foo" : { "bar" : value } }
      keys = []

      key = path.first
      remaining = path.remainder
      while !key.nil?
        # for ruby: convert string keys to symbols
        if key.is_a?(String)
          key = key
        end
        keys.push(key)
        if remaining.nil?
          break
        else
          key = remaining.first
          remaining = remaining.remainder
        end
      end

      # the setComments(null) is to ensure comments are only
      # on the exact leaf node they apply to.
      # a comment before "foo.bar" applies to the full setting
      # "foo.bar" not also to "foo"
      keys = keys.reverse
      # this is just a ruby means for doing first/rest
      deepest, *rest = *keys
      o = SimpleConfigObject.new(value.origin.with_comments(nil),
                                 {deepest => value})
      while !rest.empty?
        deepest, *rest = *rest
        o = SimpleConfigObject.new(value.origin.with_comments(nil),
                                   {deepest => o})
      end

      o
    end

    def parse_key(token)
      if @flavor == ConfigSyntax::JSON
        if Tokens.value_with_type?(token.token, ConfigValueType::STRING)
          key = Tokens.value(token.token).unwrapped
          Path.new_key(key)
        else
          raise parse_error(add_key_name("Expecting close brace } or a field name here, got #{token}"))
        end
      else
        expression = []
        t = token
        while Tokens.value?(t.token) || Tokens.unquoted_text?(t.token)
          expression.push(t.token)
          t = next_token # note: don't cross a newline
        end

        if expression.empty?
          raise parse_error(add_key_name("expecting a close brace or a field name here, got #{t}"))
        end

        put_back(t)
        Hocon::Impl::PathParser.parse_path_expression(
            Hocon::Impl::ArrayIterator.new(expression),
            line_origin)
      end
    end

    def self.include_keyword?(token)
      Tokens.unquoted_text?(token) &&
          (Tokens.unquoted_text(token) == "include")
    end

    def unquoted_whitespace?(t)
      if !(Tokens.unquoted_text?(t))
        return false
      end

      s = Tokens.unquoted_text(t)

      s.each_char do |c|
        if ! Hocon::Impl::ConfigImplUtil.whitespace?(c)
          return false
        end
      end

      true
    end

    def parse_include(values)
      t = next_token_ignoring_newline
      while unquoted_whitespace?(t.token)
        t = next_token_ignoring_newline
      end

      obj = nil

      # we either have a quoted string or the "file()" syntax
      if Tokens.unquoted_text?(t.token)
        kind = Tokens.unquoted_text(t.token)

        if kind == "url("
        elsif kind == "file("
        elsif kind == "classpath("
        else
          raise parse_error("expecting include parameter to be quoted filename, file(), classpath(), or url(). No spaces are allowed before the open paren. Not expecting: #{t}")
        end

        # skip space inside parens
        t = next_token_ignoring_newline
        while unquoted_whitespace?(t.token)
          t = next_token_ignoring_newline
        end

        # quoted string
        name = nil
        if Tokens.value_with_type?(t.token, ConfigValueType::String)
          name = Tokens.get_value(t.token).unwrapped
        else
          raise parse_error("expecting a quoted string inside file(), classpath(), or url(), rather than: " + t)
        end

        # skip space after string, inside parens
        t = next_token_ignoring_newline
        while unquoted_whitespace(t.token)
          t = next_token_ignoring_newline
        end

        if Tokens.unquoted_text?(t.token) && (Tokens.unquoted_text(t.token) == ")")
          # OK, close paren
        else
          raise parse_error("expecting a close parentheses ')' here, not: " + t)
        end

        if kind == "url("
          url = nil
          begin
            url = Hocon::Impl::Url.new(name)
          rescue Hocon::Impl::Url::MalformedUrlError => e
            raise parse_error("include url() specifies an invalid URL: " + name, e)
          end
          obj = @includer.include_url(@include_context, url)
        elsif kind == "file("
          obj = @includer.include_file(@include_context, File.new(name))
        elsif kind == "classpath("
          obj = @includer.include_resources(@include_context, name)
        else
          raise Hocon::ConfigError::ConfigBugOrBrokenError, "should not be reached"
        end
      elsif Tokens.value_with_type?(t.token, ConfigValueType::STRING)
        name = Tokens.value(t.token).unwrapped
        obj = @includer.include(@include_context, name)
      else
        raise parse_error("include keyword is not followed by a quoted string, but by: " + t.to_s)
      end

      # we really should make this work, but for now throwing an
      # exception is better than producing an incorrect result.
      # See https://github.com/typesafehub/config/issues/160
      if @array_count > 0 && (obj.resolve_status != ResolveStatus::RESOLVED)
        raise parse_error("Due to current limitations of the config parser, when an include statement is nested inside a list value, " +
                              "${} substitutions inside the included file cannot be resolved correctly. Either move the include outside of the list value or " +
                              "remove the ${} statements from the included file.")
      end

      if !(@path_stack.is_empty?)
        prefix = full_current_path
        obj = obj.relativized(prefix)
      end

      obj.key_set.each do |key|
        v = obj.get(key)
        existing = values.get(key)
        if !(existing.nil?)
          values.put(key, v.with_fallback(existing))
        else
          values.put(key, v)
        end
      end
    end

    def key_value_separator_token?(t)
      if @flavor == ConfigSyntax::JSON
        t == Tokens::COLON
      else
        [Tokens::COLON, Tokens::EQUALS, Tokens::PLUS_EQUALS].any? { |sep| sep == t }
      end
    end

    def parse_object(had_open_curly)
      # invoked just after the OPEN_CURLY (or START, if !hadOpenCurly)
      values = {}
      object_origin = line_origin
      after_comma = false
      last_path = nil
      last_inside_equals = false

      while true
        t = next_token_ignoring_newline
        if t.token == Tokens::CLOSE_CURLY
          if (@flavor == ConfigSyntax::JSON) && after_comma
            raise parse_error(
                      add_quote_suggestion(t,
                                           "expecting a field name after a comma, got a close brace } instead"))
          elsif !had_open_curly
            raise parse_error(
                      add_quote_suggestion(t,
                                           "unbalanced close brace '}' with no open brace"))
          end

          object_origin = t.append_comments(object_origin)
          break
        elsif (t.token == Tokens::EOF) && !had_open_curly
          put_back(t)
          break
        elsif (@flavor != ConfigSyntax::JSON) &&
            self.class.include_keyword?(t.token)
          parse_include(values)
          after_comma = false
        else
          key_token = t
          path = parse_key(key_token)
          after_key = next_token_ignoring_newline
          inside_equals = false

          # path must be on-stack while we parse the value
          @path_stack.push(path)

          if after_key.token == Tokens::PLUS_EQUALS
            # we really should make this work, but for now throwing
            # an exception is better than producing an incorrect
            # result. See
            # https://github.com/typesafehub/config/issues/160
            if @array_count > 0
              raise parse_error("Due to current limitations of the config parser, += does not work nested inside a list. " +
                "+= expands to a ${} substitution and the path in ${} cannot currently refer to list elements. " +
                "You might be able to move the += outside of the list and then refer to it from inside the list with ${}.")
            end

            # because we will put it in an array after the fact so
            # we want this to be incremented during the parseValue
            # below in order to throw the above exception.
            @array_count += 1
          end

          value_token = nil
          new_value = nil
          if (@flavor == ConfigSyntax::CONF) &&
              (after_key.token == Tokens::OPEN_CURLY)
            # can omit the ':' or '=' before an object value
            value_token = after_key
          else
            if !key_value_separator_token?(after_key.token)
              raise parse_error(
                        add_quote_suggestion(after_key,
                                             "Key '#{path.render}' may not be followed by token: #{after_key}"))
            end

            if after_key.token == Tokens::EQUALS
              inside_equals = true
              @equals_count += 1
            end

            consolidate_value_tokens
            value_token = next_token_ignoring_newline

            # put comments from separator token on the value token
            value_token = value_token.prepend(after_key.comments)
          end

          # comments from the key token go to the value token
          new_value = parse_value(value_token.prepend(key_token.comments))

          if after_key.token == Tokens::PLUS_EQUALS
            @array_count -= 1

            previous_ref = ConfigReference.new(
                new_value.origin,
                Hocon::Impl::SubstitutionExpression.new(full_current_path, true))
            list = SimpleConfigList.new(new_value.origin, [new_value])
            concat = []
            concat << previous_ref
            concat << list
            new_value = ConfigConcatenation.concatenate(concat)
          end

          new_value = add_any_comments_after_any_comma(new_value)

          last_path = @path_stack.pop
          if inside_equals
            @equals_count -= 1
          end
          last_inside_equals = inside_equals

          key = path.first

          # # for ruby: convert string keys to symbols
          # if key.is_a?(String)
          #   key = key
          # end

          remaining = path.remainder

          if !remaining
            existing = values[key]
            if existing
              # In strict JSON, dups should be an error; while in
              # our custom config language, they should be merged
              # if the value is an object (or substitution that
              # could become an object).

              if @flavor == ConfigSyntax::JSON
                raise parse_error("JSON does not allow duplicate fields: '#{key}'" +
                                      " was already seen at #{existing.origin().description()}")
              else
                new_value = new_value.with_fallback(existing)
              end
            end
            values[key] = new_value
          else
            if @flavor == ConfigSyntax::JSON
              raise Hocon::ConfigError::ConfigBugOrBrokenError, "somehow got multi-element path in JSON mode"
            end

            obj = create_value_under_path(remaining, new_value)
            existing = values[key]
            if !existing.nil?
              obj = obj.with_fallback(existing)
            end
            values[key] = obj
          end

          after_comma = false
        end

        if check_element_separator
          # continue looping
          after_comma = true
        else
          t = next_token_ignoring_newline
          if t.token == Tokens::CLOSE_CURLY
            if !had_open_curly
              raise parse_error(
                        add_quote_suggestion(t, "unbalanced close brace '}' with no open brace",
                                             last_path, last_inside_equals))
            end

            object_origin = t.append_comments(object_origin)
            break
          elsif had_open_curly
            raise parse_error(
                      add_quote_suggestion(t, "Expecting close brace } or a comma, got #{t}",
                                           last_path, last_inside_equals))
          else
            if t.token == Tokens::EOF
              put_back(t)
              break
            else
              raise parse_error(
                        add_quote_suggestion(t, "Expecting end of input or a comma, got #{t}",
                                             last_path, last_inside_equals))
            end
          end
        end
      end

      SimpleConfigObject.new(object_origin, values)

    end

    def parse_array
      # invoked just after the OPEN_SQUARE
      @array_count += 1

      array_origin = line_origin
      values = []

      consolidate_value_tokens

      t = next_token_ignoring_newline

      # special-case the first element
      if t.token == Tokens::CLOSE_SQUARE
        @array_count -= 1
        return SimpleConfigList.new(t.append_comments(array_origin), [])
      elsif (Tokens.value?(t.token)) ||
          (t.token == Tokens::OPEN_CURLY) ||
          (t.token == Tokens::OPEN_SQUARE)
        v = parse_value(t)
        v = add_any_comments_after_any_comma(v)
        values.push(v)
      else
        raise parse_error(add_key_name("List should have ] or a first element after the open [, instead had token: " +
                                           "#{t} (if you want #{t} to be part of a string value, then double-quote it)"))
      end

      # now remaining elements
      while true
        # just after a value
        if check_element_separator
          # comma (or newline equivalent) consumed
        else
          t = next_token_ignoring_newline
          if t.token == Tokens::CLOSE_SQUARE
            @array_count -= 1
            return SimpleConfigList.new(t.append_comments(array_origin), values)
          else
            raise parse_error(add_key_name("List should have ended with ] or had a comma, instead had token: " +
                                               "#{t} (if you want #{t} to be part of a string value, then double-quote it)"))
          end
        end

        # now just after a comma
        consolidate_value_tokens

        t = next_token_ignoring_newline

        if (Tokens.value?(t.token)) ||
            (t.token == Tokens::OPEN_CURLY) ||
            (t.token == Tokens::OPEN_SQUARE)
          v = parse_value(t)
          v = add_any_comments_after_any_comma(v)
          values.push(v)
        elsif (@flavor != ConfigSyntax::JSON) &&
            (t.token == Tokens::CLOSE_SQUARE)
          # we allow one trailing comma
          put_back(t)
        else
          raise parse_error(add_key_name("List should have had new element after a comma, instead had token: " +
                                             "#{t} (if you want the comma or #{t} to be part of a string value, then double-quote it)"))
        end
      end
    end

    def parse
      t = next_token_ignoring_newline
      if t.token != Tokens::START
        raise Hocon::ConfigError::ConfigBugOrBrokenError, "token stream did not begin with START, had #{t}"
      end

      t = next_token_ignoring_newline
      if (t.token == Tokens::OPEN_CURLY) or (t.token == Tokens::OPEN_SQUARE)
        result = parse_value(t)
      else
        if @syntax == ConfigSyntax::JSON
          if t.token == Tokens::EOF
            raise parse_error("Empty document")
          else
            raise parse_error("Document must have an object or array at root, unexpected token: #{t}")
          end
        else
          ## the root object can omit the surrounding braces.
          ## this token should be the first field's key, or part
          ## of it, so put it back.
          put_back(t)
          result = parse_object(false)
          ## in this case we don't try to use commentsStack comments
          ## since they would all presumably apply to fields not the
          ## root object
        end
      end

      t = next_token_ignoring_newline
      if t.token == Tokens::EOF
        result
      else
        raise parse_error("Document has trailing tokens after first object or array: #{t}")
      end
    end
  end
end
