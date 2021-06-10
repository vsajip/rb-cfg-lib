require 'date'
require 'set'
require 'stringio'

require 'CFG/version'

module CFG
  module Utils
    def white_space?(chr)
      chr =~ /[[:space:]]/
    end

    def letter?(chr)
      chr =~ /[[:alpha:]]/
    end

    def digit?(chr)
      chr =~ /[[:digit:]]/
    end

    def alnum?(chr)
      chr =~ /[[:alnum:]]/
    end

    def hexdigit?(chr)
      chr =~ /[[:xdigit:]]/
    end

    ISO_DATETIME_PATTERN = /^(\d{4})-(\d{2})-(\d{2})
                            (([ T])(((\d{2}):(\d{2}):(\d{2}))(\.\d{1,6})?
                            (([+-])(\d{2}):(\d{2})(:(\d{2})(\.\d{1,6})?)?)?))?$/x.freeze
    ENV_VALUE_PATTERN = /^\$(\w+)(\|(.*))?$/.freeze
    COLON_OBJECT_PATTERN = /^(\p{L}\w*(\/\p{L}\w*)*:::)?(\p{Lu}\w*(::\p{Lu}\w*)*)
                            (\.([\p{L}_]\w*(\.[\p{L}_]\w*)*))?$/xu.freeze
    INTERPOLATION_PATTERN = /(\$\{([^}]+)\})/.freeze

    def default_string_converter(str, cfg)
      result = str
      m = ISO_DATETIME_PATTERN.match str

      if !m.nil?
        year = m[1].to_i
        month = m[2].to_i
        day = m[3].to_i
        has_time = !m[5].nil?
        if !has_time
          result = Date.new year, month, day
        else
          hour = m[8].to_i
          minute = m[9].to_i
          second = m[10].to_i
          fracseconds = if m[11].nil?
                          0
                        else
                          m[11].to_f
                        end
          offset = if m[13].nil?
                     0
                   else
                     sign = m[13] == '-' ? -1 : 1
                     ohour = m[14].to_i
                     ominute = m[15].to_i
                     osecond = m[17] ? m[17].to_i : 0
                     (osecond + ominute * 60 +
                      ohour * 3600) * sign / 86_400.0
                   end
          result = DateTime.new(year, month, day, hour, minute,
                                fracseconds + second, offset)
        end
      else
        m = ENV_VALUE_PATTERN.match str
        if !m.nil?
          var_name = m[1]
          has_pipe = !m[2].nil?
          dv = if !has_pipe
                 NULL_VALUE
               else
                 m[3]
               end
          result = ENV.include?(var_name) ? ENV[var_name] : dv
        else
          m = COLON_OBJECT_PATTERN.match str
          if !m.nil?
            require(m[1][0..-4]) unless m[1].nil?
            result = Object.const_get m[3]
            unless m[5].nil?
              parts = m[6].split('.')
              parts.each do |part|
                result = result.send(part)
              end
            end
          else
            m = INTERPOLATION_PATTERN.match str
            unless m.nil?
              matches = str.enum_for(:scan, INTERPOLATION_PATTERN).map do
                [Regexp.last_match.offset(0), Regexp.last_match.captures[1]]
              end
              cp = 0
              failed = false
              parts = []
              matches.each do |off, path|
                first = off[0]
                last = off[1]
                parts.push str[cp..first - 1] if first > cp
                begin
                  parts.push string_for(cfg.get(path))
                  cp = last
                rescue StandardError
                  failed = true
                  break
                end
              end
              unless failed
                parts.push str[cp..str.length - 1] if cp < str.length
                result = parts.join('')
              end
            end
          end
        end
      end
      result
    end
  end

  class RecognizerError < StandardError
    attr_accessor :location
  end

  class TokenizerError < RecognizerError; end

  class ParserError < RecognizerError; end

  class ConfigError < RecognizerError; end

  class InvalidPathError < ConfigError; end

  class BadIndexError < ConfigError; end

  class CircularReferenceError < ConfigError; end

  class Location
    attr_accessor :line
    attr_accessor :column

    def self.from(other)
      Location.new other.line, other.column
    end

    def initialize(line = 1, column = 1)
      @line = line
      @column = column
    end

    def next_line
      self.line += 1
      self.column = 1
    end

    def update(other)
      @line = other.line
      @column = other.column
    end

    def to_s
      "(#{@line}, #{@column})"
    end

    def ==(other)
      @line == other.line && @column == other.column
    end
  end

  # Kinds of token
  # :EOF
  # :WORD
  # :INTEGER
  # :FLOAT
  # :STRING
  # :NEWLINE
  # :LEFT_CURLY
  # :RIGHT_CURLY
  # :LEFT_BRACKET
  # :RIGHT_BRACKET
  # :LEFT_PARENTHESIS
  # :RIGHT_PARENTHESIS
  # :LESS_THAN
  # :GREATER_THAN
  # :LESS_THAN_OR_EQUAL
  # :GREATER_THAN_OR_EQUAL
  # :ASSIGN
  # :EQUAL
  # :UNEQUAL
  # :ALT_UNEQUAL
  # :LEFT_SHIFT
  # :RIGHT_SHIFT
  # :DOT
  # :COMMA
  # :COLON
  # :AT
  # :PLUS
  # :MINUS
  # :STAR
  # :POWER
  # :SLASH
  # :SLASH_SLASH
  # :MODULO
  # :BACKTICK
  # :DOLLAR
  # :TRUE
  # :FALSE
  # :NONE
  # :IS
  # :IN
  # :NOT
  # :AND
  # :OR
  # :BITWISE_AND
  # :BITWISE_OR
  # :BITWISE_XOR
  # :BITWISE_COMPLEMENT
  # :COMPLEX
  # :IS_NOT
  # :NOT_IN

  class ASTNode
    attr_accessor :kind
    attr_accessor :start
    attr_accessor :end

    def initialize(kind)
      @kind = kind
    end
  end

  class Token < ASTNode
    attr_accessor :text
    attr_accessor :value

    def initialize(kind, text, value = nil)
      super(kind)
      @text = text
      @value = value
    end

    def to_s
      "Token(#{@kind}, #{text.inspect}, #{value.inspect})"
    end

    def ==(other)
      @kind == other.kind && @text == other.text && @value == other.value &&
        @start == other.start && @end == other.end
    end
  end

  PUNCTUATION = {
    ':' => :COLON,
    '-' => :MINUS,
    '+' => :PLUS,
    '*' => :STAR,
    '/' => :SLASH,
    '%' => :MODULO,
    ',' => :COMMA,
    '{' => :LEFT_CURLY,
    '}' => :RIGHT_CURLY,
    '[' => :LEFT_BRACKET,
    ']' => :RIGHT_BRACKET,
    '(' => :LEFT_PARENTHESIS,
    ')' => :RIGHT_PARENTHESIS,
    '@' => :AT,
    '$' => :DOLLAR,
    '<' => :LESS_THAN,
    '>' => :GREATER_THAN,
    '!' => :NOT,
    '~' => :BITWISE_COMPLEMENT,
    '&' => :BITWISE_AND,
    '|' => :BITWISE_OR,
    '^' => :BITWISE_XOR,
    '.' => :DOT
  }.freeze

  KEYWORDS = {
    'true' => :TRUE,
    'false' => :FALSE,
    'null' => :NONE,
    'is' => :IS,
    'in' => :IN,
    'not' => :NOT,
    'and' => :AND,
    'or' => :OR
  }.freeze

  ESCAPES = {
    'a' =>  "\u0007",   # rubocop: disable Layout/HashAlignment
    'b' =>  "\b",       # rubocop: disable Layout/HashAlignment
    'f' =>  "\u000C",   # rubocop:disable Layout/HashAlignment
    'n' =>  "\n",       # rubocop:disable Layout/HashAlignment
    'r' =>  "\r",       # rubocop:disable Layout/HashAlignment
    't' =>  "\t",       # rubocop:disable Layout/HashAlignment
    'v' =>  "\u000B",   # rubocop:disable Layout/HashAlignment
    '\\' => '\\',
    '\'' => "'",
    '"' =>  '"'         # rubocop:disable Layout/HashAlignment
  }.freeze

  NULL_VALUE = Object.new

  KEYWORD_VALUES = {
    TRUE: true,
    FALSE: false,
    NONE: NULL_VALUE
  }.freeze

  class Tokenizer
    include Utils

    def initialize(stream)
      @stream = stream
      @location = Location.new
      @char_location = Location.new
      @pushed_back = []
    end

    def tokens
      result = []
      loop do
        t = get_token
        result.push t
        break if t.kind == :EOF
      end
      result
    end

    def push_back(chr)
      @pushed_back.push([chr, Location.from(@char_location)]) unless chr.nil?
    end

    def get_char
      if !@pushed_back.empty?
        result, loc = @pushed_back.pop
        @char_location.update loc
        @location.update loc # will be bumped later
      else
        @char_location.update @location
        result = @stream.getc
      end
      unless result.nil?
        if result == "\n"
          @location.next_line
        else
          @location.column += 1
        end
      end
      result
    end

    def get_number(text, startloc, endloc)
      kind = :INTEGER
      in_exponent = false
      radix = 0
      dot_seen = !text.index('.').nil?
      last_was_digit = digit?(text[-1])

      while true
        c = get_char

        break if c.nil?

        dot_seen = true if c == '.'
        if c == '_'
          if last_was_digit
            text = append_char text, c, endloc
            last_was_digit = false
            next
          end
          e = TokenizerError.new "Invalid '_' in number: #{text}#{c}"

          e.location = @char_location
          raise e
        end
        last_was_digit = false # unless set in one of the clauses below
        if (radix.zero? && (c >= '0') && (c <= '9')) ||
           ((radix == 2) && (c >= '0') && (c <= '1')) ||
           ((radix == 8) && (c >= '0') && (c <= '7')) ||
           ((radix == 16) && hexdigit?(c))
          text = append_char text, c, endloc
          last_was_digit = true
        elsif ((c == 'o') || (c == 'O') || (c == 'x') ||
              (c == 'X') || (c == 'b') || (c == 'B')) &&
              (text.length == 1) && (text[0] == '0')
          radix = if c.upcase == 'X'
                    16
                  else
                    (c == 'o') || (c == 'O') ? 8 : 2
                  end
          text = append_char text, c, endloc
        elsif radix.zero? && (c == '.') && !in_exponent && text.index(c).nil?
          text = append_char text, c, endloc
        elsif radix.zero? && (c == '-') && text.index('-', 1).nil? && in_exponent
          text = append_char text, c, endloc
        elsif radix.zero? && ((c == 'e') || (c == 'E')) && text.index('e').nil? &&
              text.index('E').nil? && (text[-1] != '_')
          text = append_char text, c, endloc
          in_exponent = true
        else
          break
        end
      end

      # Reached the end of the actual number part. Before checking
      # for complex, ensure that the last char wasn't an underscore.
      if text[-1] == '_'
        e = TokenizerError.new "Invalid '_' at end of number: #{text}"

        e.location = endloc
        raise e
      end
      if radix.zero? && ((c == 'j') || (c == 'J'))
        text = append_char text, c, endloc
        kind = :COMPLEX
      else
        # not allowed to have a letter or digit which wasn't accepted
        if (c != '.') && !alnum?(c) # rubocop:disable Style/IfInsideElse
          push_back c
        else
          e = TokenizerError.new "Invalid character in number: #{c}"

          e.location = @char_location
          raise e
        end
      end

      s = text.gsub(/_/, '')

      if radix != 0
        value = Integer s[2..-1], radix
      elsif kind == :COMPLEX
        imaginary = s[0..-2].to_f
        value = Complex(0.0, imaginary)
      elsif in_exponent || dot_seen
        kind = :FLOAT
        value = s.to_f
      else
        radix = s[0] == '0' ? 8 : 10
        begin
          value = Integer s, radix
        rescue ArgumentError
          e = TokenizerError.new "Invalid character in number: #{s}"
          e.location = startloc
          raise e
        end
      end
      [text, kind, value]
    end

    def parse_escapes(str)
      i = str.index '\\'
      if i.nil?
        result = str
      else
        failed = false
        result = ''
        until i.nil?
          result += str[0..i - 1] if i.positive?
          c = str[i + 1]
          if ESCAPES.key?(c)
            result += ESCAPES[c]
            i += 2
          elsif c =~ /[xu]/i
            slen = if c.upcase == 'X'
                     4
                   else
                     c == 'u' ? 6 : 10
                   end
            if i + slen > str.length
              failed = true
              break
            end
            p = str[i + 2..i + slen - 1]
            if p =~ /^[[:xdigit:]]$/i
              failed = true
              break
            end
            begin
              j = Integer p, 16
            rescue ArgumentError
              failed = true
              break
            end
            if j.between?(0xd800, 0xdfff) || (j >= 0x110000)
              failed = true
              break
            end
            result += j.chr 'utf-8'
            i += slen
          else
            failed = true
            break
          end
          str = str[i..-1]
          i = str.index '\\'
        end
        if !failed
          result += str
        else
          e = TokenizerError.new "Invalid escape sequence at index #{i}"
          raise e
        end
      end
      result
    end

    def append_char(token, chr, end_location)
      token += chr
      end_location.update @char_location
      token
    end

    def get_token
      start_location = Location.new
      end_location = Location.new
      kind = :EOF
      token = ''
      value = nil

      loop do
        c = get_char

        start_location.update @char_location
        end_location.update @char_location

        break if c.nil?

        if c == '#'
          token += c + @stream.readline.rstrip
          kind = :NEWLINE
          @location.next_line
          end_location.update(@location)
          end_location.column -= 1
          break
        elsif c == "\n"
          token += c
          end_location.update @location
          end_location.column -= 1
          kind = :NEWLINE
          break
        elsif c == "\r"
          c = get_char
          push_back c if c != "\n"
          kind = :NEWLINE
          break
        elsif c == '\\'
          c = get_char
          if c != "\n"
            e = TokenizerError.new 'Unexpected character: \\'
            e.location = @char_location
            raise e
          end
          end_location.update @char_location
          next
        elsif white_space?(c)
          next
        elsif c == '_' || letter?(c)
          kind = :WORD
          token = append_char token, c, end_location
          c = get_char
          while !c.nil? && (alnum?(c) || (c == '_'))
            token = append_char token, c, end_location
            c = get_char
          end
          push_back c
          value = token
          if KEYWORDS.key?(value)
            kind = KEYWORDS[value]
            value = KEYWORD_VALUES[kind] if KEYWORD_VALUES.key?(kind)
          end
          break
        elsif c == '`'
          kind = :BACKTICK
          token = append_char token, c, end_location
          loop do
            c = get_char
            break if c.nil?

            token = append_char token, c, end_location
            break if c == '`'
          end
          if c.nil?
            e = TokenizerError.new "Unterminated `-string: #{token}"
            e.location = start_location
            raise e
          end
          begin
            value = parse_escapes token[1..token.length - 2]
          rescue RecognizerError
            e.location = start_location
            raise e
          end
          break
        elsif !'"\''.index(c).nil?
          quote = c
          multi_line = false
          escaped = false
          kind = :STRING

          token = append_char token, c, end_location
          c1 = get_char
          c1_loc = Location.from @char_location

          if c1 != quote
            push_back c1
          else
            c2 = get_char
            if c2 != quote
              push_back c2
              @char_location.update c1_loc if c2.nil?
              push_back c1
            else
              multi_line = true
              token = append_char token, quote, end_location
              token = append_char token, quote, end_location
            end
          end

          quoter = token[0..-1]

          loop do
            c = get_char
            break if c.nil?

            token = append_char token, c, end_location
            if (c == quote) && !escaped
              n = token.length

              break if !multi_line || (n >= 6) && (token[n - 3..n - 1] == quoter) && token[n - 4] != '\\'
            end
            escaped = c == '\\' ? !escaped : false
          end
          if c.nil?
            e = TokenizerError.new "Unterminated quoted string: #{token}"

            e.location = start_location
            raise e
          end
          n = quoter.length
          begin
            value = parse_escapes token[n..token.length - n - 1]
          rescue RecognizerError => e
            e.location = start_location
            raise e
          end
          break
        elsif digit?(c)
          token = append_char token, c, end_location
          token, kind, value = get_number token, start_location, end_location
          break
        elsif c == '='
          nc = get_char

          if nc != '='
            kind = :ASSIGN
            token += c
            push_back nc
          else
            kind = :EQUAL
            token += c
            token = append_char token, c, end_location
          end
          break
        elsif PUNCTUATION.key?(c)
          kind = PUNCTUATION[c]
          token = append_char token, c, end_location
          if c == '.'
            c = get_char
            if !digit?(c)
              push_back c
            else
              token = append_char token, c, end_location
              token, kind, value = get_number token, start_location, end_location
            end
          elsif c == '-'
            c = get_char
            if !digit?(c) && (c != '.')
              push_back c
            else
              token = append_char token, c, end_location
              token, kind, value = get_number token, start_location, end_location
            end
          elsif c == '<'
            c = get_char
            if c == '='
              kind = :LESS_THAN_OR_EQUAL
              token = append_char token, c, end_location
            elsif c == '>'
              kind = :ALT_UNEQUAL
              token = append_char token, c, end_location
            elsif c == '<'
              kind = :LEFT_SHIFT
              token = append_char token, c, end_location
            else
              push_back c
            end
          elsif c == '>'
            c = get_char
            if c == '='
              kind = :GREATER_THAN_OR_EQUAL
              token = append_char token, c, end_location
            elsif c == '>'
              kind = :RIGHT_SHIFT
              token = append_char token, c, end_location
            else
              push_back c
            end
          elsif c == '!'
            c = get_char
            if c == '='
              kind = :UNEQUAL
              token = append_char token, c, end_location
            else
              push_back c
            end
          elsif c == '/'
            c = get_char
            if c != '/'
              push_back c
            else
              kind = :SLASH_SLASH
              token = append_char token, c, end_location
            end
          elsif c == '*'
            c = get_char
            if c != '*'
              push_back c
            else
              kind = :POWER
              token = append_char token, c, end_location
            end
          elsif (c == '&') || (c == '|')
            c2 = get_char

            if c2 != c
              push_back c2
            else
              kind = c2 == '&' ? :AND : :OR
              token = append_char token, c, end_location
            end
          end
          break
        else
          e = TokenizerError.new "Unexpected character: #{c}"
          e.location = @char_location
          raise e
        end
      end
      result = Token.new kind, token, value
      result.start = Location.from start_location
      result.end = Location.from end_location
      result
    end
  end

  def make_tokenizer(src)
    stream = StringIO.new src, 'r:utf-8'
    Tokenizer.new stream
  end

  class UnaryNode < ASTNode
    attr_reader :operand

    def initialize(kind, operand)
      super(kind)
      @operand = operand
    end

    def to_s
      "UnaryNode(#{@kind}, #{@operand})"
    end

    def ==(other)
      @kind == other.kind && @operand == other.operand
    end
  end

  class BinaryNode < ASTNode
    attr_reader :lhs
    attr_reader :rhs

    def initialize(kind, lhs, rhs)
      super(kind)
      @lhs = lhs
      @rhs = rhs
    end

    def to_s
      "BinaryNode(#{@kind}, #{@lhs}, #{@rhs})"
    end

    def ==(other)
      @kind == other.kind && @lhs == other.lhs && @rhs == other.rhs
    end
  end

  class SliceNode < ASTNode
    attr_reader :start_index
    attr_reader :stop_index
    attr_reader :step

    def initialize(start_index, stop_index, step)
      super(:COLON)
      @start_index = start_index
      @stop_index = stop_index
      @step = step
    end

    def to_s
      "SliceNode(#{@start_index}:#{@stop_index}:#{@step})"
    end

    def ==(other)
      @kind == other.kind && @start_index == other.start_index &&
        @stop_index == other.stop_index && @step == other.step
    end
  end

  class ListNode < ASTNode
    attr_reader :elements

    def initialize(elements)
      super(:LEFT_BRACKET)
      @elements = elements
    end
  end

  class MappingNode < ASTNode
    attr_reader :elements

    def initialize(elements)
      super(:LEFT_CURLY)
      @elements = elements
    end
  end

  class Parser
    attr_reader :tokenizer
    attr_reader :next_token

    def initialize(stream)
      @tokenizer = Tokenizer.new stream
      @next_token = @tokenizer.get_token
    end

    def at_end
      @next_token.kind == :EOF
    end

    def advance
      @next_token = @tokenizer.get_token
      @next_token.kind
    end

    def expect(kind)
      if @next_token.kind != kind
        e = ParserError.new "Expected #{kind} but got #{@next_token.kind}"
        e.location = @next_token.start
        # require 'byebug'; byebug
        raise e
      end
      result = @next_token
      advance
      result
    end

    def consume_newlines
      result = @next_token.kind

      result = advance while result == :NEWLINE
      result
    end

    EXPRESSION_STARTERS = Set[
      :LEFT_CURLY, :LEFT_BRACKET, :LEFT_PARENTHESIS,
      :AT, :DOLLAR, :BACKTICK, :PLUS, :MINUS, :BITWISE_COMPLEMENT,
      :INTEGER, :FLOAT, :COMPLEX, :TRUE, :FALSE,
      :NONE, :NOT, :STRING, :WORD
    ]

    VALUE_STARTERS = Set[
      :WORD, :INTEGER, :FLOAT, :COMPLEX, :STRING, :BACKTICK,
      :NONE, :TRUE, :FALSE
    ]

    def strings
      result = @next_token
      if advance == :STRING
        all_text = ''
        all_value = ''
        t = result.text
        v = result.value
        start = result.start
        endpos = result.end

        loop do
          all_text += t
          all_value += v
          t = @next_token.text
          v = @next_token.value
          endpos = @next_token.end
          kind = advance
          break if kind != :STRING
        end
        all_text += t # the last one
        all_value += v
        result = Token.new :STRING, all_text, all_value
        result.start = start
        result.end = endpos
      end
      result
    end

    def value
      kind = @next_token.kind
      unless VALUE_STARTERS.include? kind
        e = ParserError.new "Unexpected when looking for value: #{kind}"
        e.location = @next_token.start
        raise e
      end
      if kind == :STRING
        result = strings
      else
        result = @next_token
        advance
      end
      result
    end

    def atom
      kind = @next_token.kind
      case kind
      when :LEFT_CURLY
        result = mapping
      when :LEFT_BRACKET
        result = list
      when :DOLLAR
        expect :DOLLAR
        expect :LEFT_CURLY
        spos = @next_token.start
        result = UnaryNode.new :DOLLAR, primary
        result.start = spos
        expect :RIGHT_CURLY
      when :WORD, :INTEGER, :FLOAT, :COMPLEX, :STRING, :BACKTICK, :TRUE, :FALSE, :NONE
        result = value
      when :LEFT_PARENTHESIS
        expect :LEFT_PARENTHESIS
        result = expr
        expect :RIGHT_PARENTHESIS
      else
        e = ParserError.new "Unexpected: #{kind}"
        e.location = @next_token.start
        raise e
      end
      result
    end

    def _invalid_index(num, pos)
      e = ParserError.new "Invalid index at #{pos}: expected 1 expression, found #{num}"
      e.location = pos
      raise e
    end

    def _get_slice_element
      lb = list_body
      size = lb.elements.length

      _invalid_index(size, lb.start) unless size == 1
      lb.elements[0]
    end

    def _try_get_step
      kind = advance
      kind == :RIGHT_BRACKET ? nil : _get_slice_element
    end

    def trailer
      op = @next_token.kind

      if op != :LEFT_BRACKET
        expect :DOT
        result = expect :WORD
      else
        kind = advance
        is_slice = false
        start_index = nil
        stop_index = nil
        step = nil

        if kind == :COLON
          # it's a slice like [:xyz:abc]
          is_slice = true
        else
          elem = _get_slice_element

          kind = @next_token.kind
          if kind != :COLON
            result = elem
          else
            start_index = elem
            is_slice = true
          end
        end
        if is_slice
          op = :COLON
          # at this point startIndex is either nil (if foo[:xyz]) or a
          # value representing the start. We are pointing at the COLON
          # after the start value
          kind = advance
          if kind == :COLON # no stop, but there might be a step
            s = _try_get_step
            step = s unless s.nil?
          elsif kind != :RIGHT_BRACKET
            stop_index = _get_slice_element
            kind = @next_token.kind
            if kind == :COLON
              s = _try_get_step
              step = s unless s.nil?
            end
          end
          result = SliceNode.new start_index, stop_index, step
        end
        expect :RIGHT_BRACKET
      end
      [op, result]
    end

    def primary
      result = atom
      kind = @next_token.kind
      while %i[DOT LEFT_BRACKET].include? kind
        op, rhs = trailer
        result = BinaryNode.new op, result, rhs
        kind = @next_token.kind
      end
      result
    end

    def object_key
      if @next_token.kind == :STRING
        result = strings
      else
        result = @next_token
        advance
      end
      result
    end

    def mapping_body
      result = []
      kind = consume_newlines
      spos = @next_token.start
      if kind != :RIGHT_CURLY && kind != :EOF
        if kind != :WORD && kind != :STRING
          e = ParserError.new "Unexpected type for key: #{kind}"

          e.location = @next_token.start
          raise e
        end
        while %i[WORD STRING].include? kind
          key = object_key
          kind = @next_token.kind
          if kind != :COLON && kind != :ASSIGN
            e = ParserError.new "Expected key-value separator, found: #{kind}"

            e.location = @next_token.start
            raise e
          end
          advance
          consume_newlines
          result.push [key, expr]
          kind = @next_token.kind
          if %i[NEWLINE COMMA].include? kind
            advance
            kind = consume_newlines
          end
        end
      end
      result = MappingNode.new result
      result.start = spos
      result
    end

    def mapping
      expect :LEFT_CURLY
      result = mapping_body
      expect :RIGHT_CURLY
      result
    end

    def list_body
      result = []
      kind = consume_newlines
      spos = @next_token.start
      while EXPRESSION_STARTERS.include? kind
        result.push(expr)
        kind = @next_token.kind
        break unless %i[NEWLINE COMMA].include? kind

        advance
        kind = consume_newlines
      end
      result = ListNode.new result
      result.start = spos
      result
    end

    def list
      expect :LEFT_BRACKET
      result = list_body
      expect :RIGHT_BRACKET
      result
    end

    def container
      kind = consume_newlines

      case kind
      when :LEFT_CURLY
        result = mapping
      when :LEFT_BRACKET
        result = list
      when :WORD, :STRING, :EOF
        result = mapping_body
      else
        e = ParserError.new "Unexpected type for container: #{kind}"

        e.location = @next_token.start
        raise e
      end
      consume_newlines
      result
    end

    def power
      result = primary
      while @next_token.kind == :POWER
        advance
        result = BinaryNode.new :POWER, result, unary_expr
      end
      result
    end

    def unary_expr
      kind = @next_token.kind
      spos = @next_token.start
      result = if !%i[PLUS MINUS BITWISE_COMPLEMENT AT].include? kind
                 power
               else
                 advance
                 UnaryNode.new kind, unary_expr
               end
      result.start = spos
      result
    end

    def mul_expr
      result = unary_expr
      kind = @next_token.kind

      while %i[STAR SLASH SLASH_SLASH MODULO].include? kind
        advance
        result = BinaryNode.new kind, result, unary_expr
        kind = @next_token.kind
      end
      result
    end

    def add_expr
      result = mul_expr
      kind = @next_token.kind

      while %i[PLUS MINUS].include? kind
        advance
        result = BinaryNode.new kind, result, mul_expr
        kind = @next_token.kind
      end
      result
    end

    def shift_expr
      result = add_expr
      kind = @next_token.kind

      while %i[LEFT_SHIFT RIGHT_SHIFT].include? kind
        advance
        result = BinaryNode.new kind, result, add_expr
        kind = @next_token.kind
      end
      result
    end

    def bitand_expr
      result = shift_expr

      while @next_token.kind == :BITWISE_AND
        advance
        result = BinaryNode.new :BITWISE_AND, result, shift_expr
      end
      result
    end

    def bitxor_expr
      result = bitand_expr

      while @next_token.kind == :BITWISE_XOR
        advance
        result = BinaryNode.new :BITWISE_XOR, result, bitand_expr
      end
      result
    end

    def bitor_expr
      result = bitxor_expr

      while @next_token.kind == :BITWISE_OR
        advance
        result = BinaryNode.new :BITWISE_OR, result, bitxor_expr
      end
      result
    end

    def comp_op
      result = @next_token.kind
      should_advance = false
      advance
      if result == :IS && @next_token.kind == :NOT
        result = :IS_NOT
        should_advance = true
      elsif result == :NOT && @next_token.kind == :IN
        result = :NOT_IN
        should_advance = true
      end
      advance if should_advance
      result
    end

    COMPARISON_OPERATORS = Set[
      :LESS_THAN, :LESS_THAN_OR_EQUAL, :GREATER_THAN, :GREATER_THAN_OR_EQUAL,
      :EQUAL, :UNEQUAL, :ALT_UNEQUAL, :IS, :IN, :NOT
    ]

    def comparison
      result = bitor_expr
      while COMPARISON_OPERATORS.include? @next_token.kind
        op = comp_op
        result = BinaryNode.new op, result, bitor_expr
      end
      result
    end

    def not_expr
      if @next_token.kind != :NOT
        comparison
      else
        advance
        UnaryNode.new :NOT, not_expr
      end
    end

    def and_expr
      result = not_expr
      while @next_token.kind == :AND
        advance
        result = BinaryNode.new :AND, result, not_expr
      end
      result
    end

    def expr
      result = and_expr
      while @next_token.kind == :OR
        advance
        result = BinaryNode.new :OR, result, and_expr
      end
      result
    end
  end

  def make_parser(src)
    stream = StringIO.new src, 'r:utf-8'
    Parser.new stream
  end

  def string_for(obj)
    if obj.is_a? Array
      parts = obj.map { |it| string_for it }
      "[#{parts.join ', '}]"
    elsif obj.is_a? Hash
      parts = obj.map { |k, v| "#{k}: #{string_for v}" }
      "{#{parts.join ', '}}"
    else
      obj.to_s
    end
  end

  class Evaluator
    attr_reader :config
    attr_reader :refs_seen

    def initialize(config)
      @config = config
      @refs_seen = Set.new
    end

    def eval_at(node)
      fn = evaluate node.operand
      unless fn.is_a? String
        e = ConfigError.new "@ operand must be a string, but is #{fn}"
        e.location = node.operand.start
        raise e
      end
      found = false
      p = Pathname.new fn
      if p.absolute? && p.exist?
        found = true
      else
        p = Pathname.new(@config.root_dir).join fn
        if p.exist?
          found = true
        else
          @config.include_path.each do |d|
            p = Pathname.new(d).join(fn)
            if p.exist?
              found = true
              break
            end
          end
        end
      end
      unless found
        e = ConfigError.new "Unable to locate #{fn}"
        e.location = node.operand.start
        raise e
      end
      f = File.open p, 'r:utf-8'
      parser = Parser.new f
      cnode = parser.container
      if !cnode.is_a? MappingNode
        result = cnode
      else
        result = Config.new
        result.no_duplicates = @config.no_duplicates
        result.strict_conversions = @config.strict_conversions
        result.context = @config.context
        result.cached = @config.cached
        result.set_path p
        result.parent = @config
        result.include_path = @config.include_path
        result.data = result.wrap_mapping cnode
      end
      result
    end

    def eval_reference(node)
      get_from_path node.operand
    end

    def to_complex(num)
      if num.is_a? Complex
        num
      elsif num.is_a? Numeric
        Complex(num, 0)
      else
        raise ConfigError, "cannot convert #{num} to a complex number"
      end
    end

    def to_float(num)
      if num.is_a? Float
        num
      elsif num.is_a? Numeric
        num.to_f
      else
        raise ConfigError, "cannot convert #{num} to a floating-point number"
      end
    end

    def merge_dicts(target, source)
      source.each do |k, v|
        if target.include?(k) && target[k].is_a?(Hash) && v.is_a?(Hash)
          merge_dicts target[k], v
        else
          target[k] = v
        end
      end
    end

    def merge_dict_wrappers(lhs, rhs)
      r = lhs.as_dict
      source = rhs.as_dict
      merge_dicts r, source
      result = DictWrapper.new @config
      result.update r
      result
    end

    def eval_add(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      result = nil
      if lhs.is_a?(DictWrapper) && rhs.is_a?(DictWrapper)
        result = merge_dict_wrappers lhs, rhs
      elsif lhs.is_a?(ListWrapper) && rhs.is_a?(ListWrapper)
        result = ListWrapper.new lhs.config
        result.concat lhs.as_list
        result.concat rhs.as_list
      elsif lhs.is_a?(String) && rhs.is_a?(String)
        result = lhs + rhs
      elsif lhs.is_a?(Numeric) && rhs.is_a?(Numeric)
        result = lhs + rhs
      elsif lhs.is_a?(Complex) || rhs.is_a?(Complex)
        result = to_complex(lhs) + to_complex(rhs)
      else
        raise ConfigError, "cannot add #{rhs} to #{lhs}"
      end
      result
    end

    def eval_subtract(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      result = nil
      if lhs.is_a?(DictWrapper) && rhs.is_a?(DictWrapper)
        result = DictWrapper.new @config
        r = lhs.as_dict
        s = rhs.as_dict
        r.each do |k, v|
          result[k] = v unless s.include? k
        end
      elsif lhs.is_a?(Numeric) && rhs.is_a?(Numeric)
        result = lhs - rhs
      elsif lhs.is_a?(ListWrapper) && rhs.is_a?(ListWrapper)
        raise NotImplementedError
      elsif lhs.is_a?(Complex) || rhs.is_a?(Complex)
        result = to_complex(lhs) - to_complex(rhs)
      else
        raise ConfigError, "unable to add #{lhs} and #{rhs}"
      end
      result
    end

    def eval_multiply(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      result = nil
      if lhs.is_a?(Numeric) && rhs.is_a?(Numeric)
        result = lhs * rhs
      elsif lhs.is_a?(Complex) || rhs.is_a?(Complex)
        result = to_complex(lhs) * to_complex(rhs)
      else
        raise ConfigError, "unable to multiply #{lhs} by #{rhs}"
      end
      result
    end

    def eval_divide(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      result = nil
      if lhs.is_a?(Numeric) && rhs.is_a?(Numeric)
        result = to_float(lhs) / rhs
      elsif lhs.is_a?(Complex) || rhs.is_a?(Complex)
        result = to_complex(lhs) / to_complex(rhs)
      else
        raise ConfigError, "unable to divide #{lhs} by #{rhs}"
      end
      result
    end

    def eval_integer_divide(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to integer-divide #{lhs} by #{rhs}" unless lhs.is_a?(Integer) && rhs.is_a?(Integer)

      lhs / rhs
    end

    def eval_modulo(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to compute #{lhs} modulo #{rhs}" unless lhs.is_a?(Integer) && rhs.is_a?(Integer)

      lhs % rhs
    end

    def eval_left_shift(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to left-shift #{lhs} by #{rhs}" unless lhs.is_a?(Integer) && rhs.is_a?(Integer)

      lhs << rhs
    end

    def eval_right_shift(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to right-shift #{lhs} by #{rhs}" unless lhs.is_a?(Integer) && rhs.is_a?(Integer)

      lhs >> rhs
    end

    def eval_logical_and(node)
      lhs = !!evaluate(node.lhs) # rubocop:disable Style/DoubleNegation
      return false unless lhs

      !!evaluate(node.rhs)
    end

    def eval_logical_or(node)
      lhs = !!evaluate(node.lhs) # rubocop:disable Style/DoubleNegation
      return true if lhs

      !!evaluate(node.rhs)
    end

    def eval_bitwise_or(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      result = nil
      if lhs.is_a?(DictWrapper) && rhs.is_a?(DictWrapper)
        result = merge_dict_wrappers lhs, rhs
      elsif lhs.is_a?(Integer) && rhs.is_a?(Integer)
        result = lhs | rhs
      else
        raise ConfigError, "unable to bitwise-or #{lhs} and #{rhs}"
      end
      result
    end

    def eval_bitwise_and(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to bitwise-and #{lhs} and #{rhs}" unless lhs.is_a?(Integer) && rhs.is_a?(Integer)

      lhs & rhs
    end

    def eval_bitwise_xor(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to bitwise-xor #{lhs} and #{rhs}" unless lhs.is_a?(Integer) && rhs.is_a?(Integer)

      lhs ^ rhs
    end

    def negate(node)
      operand = evaluate(node.operand)
      result = nil
      if operand.is_a?(Integer)
        result = -operand
      elsif operand.is_a? Complex
        result = Complex(-operand.real, -operand.imag)
      else
        raise ConfigError, "unable to negate #{operand}"
      end
      result
    end

    def eval_power(node)
      lhs = evaluate(node.lhs)
      rhs = evaluate(node.rhs)
      raise ConfigError, "unable to raise #{lhs} to power #{rhs}" unless lhs.is_a?(Numeric) && rhs.is_a?(Numeric)

      lhs**rhs
    end

    def evaluate(node)
      if node.is_a? Token
        value = node.value
        if SCALAR_TOKENS.include? node.kind
          result = value
        elsif node.kind == :WORD
          if @config.context.include? value
            result = @config.context[value]
          else
            e = ConfigError.new "Unknown variable '#{value}'"
            e.location = node.start
            raise e
          end
        elsif node.kind == :BACKTICK
          result = @config.convert_string value
        else
          e = ConfigError.new "Unable to evaluate #{node}"
          e.location = node.start
          raise e
        end
      elsif node.is_a? MappingNode
        result = @config.wrap_mapping node
      elsif node.is_a? ListNode
        result = @config.wrap_list node
      else
        case node.kind
        when :AT
          result = eval_at node
        when :DOLLAR
          result = eval_reference node
        when :LEFT_CURLY
          result = @config.wrap_mapping node
        when :PLUS
          result = eval_add node
        when :MINUS
          result = if node.is_a? BinaryNode
                     eval_subtract node
                   else
                     negate node
                   end
        when :STAR
          result = eval_multiply node
        when :SLASH
          result = eval_divide node
        when :SLASH_SLASH
          result = eval_integer_divide node
        when :MODULO
          result = eval_modulo node
        when :LEFT_SHIFT
          result = eval_left_shift node
        when :RIGHT_SHIFT
          result = eval_right_shift node
        when :POWER
          result = eval_power node
        when :AND
          result = eval_logical_and node
        when :OR
          result = eval_logical_or node
        when :BITWISE_OR
          result = eval_bitwise_or node
        when :BITWISE_AND
          result = eval_bitwise_and node
        when :BITWISE_XOR
          result = eval_bitwise_xor node
        else
          e = ConfigError.new "Unable to evaluate #{node}"
          e.location = node.start
          raise e
        end
      end
      result
    end

    def get_slice(container, slice)
      size = container.length
      step = slice.step.nil? ? 1 : evaluate(slice.step)
      raise BadIndexError, 'slice step cannot be zero' if step.zero?

      start_index = if slice.start_index.nil?
                      0
                    else
                      n = evaluate slice.start_index
                      if n.negative?
                        if n >= -size
                          n += size
                        else
                          n = 0
                        end
                      elsif n >= size
                        n = size - 1
                      end
                      n
                    end

      stop_index = if slice.stop_index.nil?
                     size - 1
                   else
                     n = evaluate slice.stop_index
                     if n.negative?
                       if n >= -size
                         n += size
                       else
                         n = 0
                       end
                     end
                     n = size if n > size
                     step.negative? ? (n + 1) : (n - 1)
                   end

      stop_index, start_index = start_index, stop_index if step.negative? && start_index < stop_index

      result = ListWrapper.new @config
      i = start_index
      not_done = step.positive? ? i <= stop_index : i >= stop_index
      while not_done
        result.push container[i]
        i += step
        not_done = step.positive? ? i <= stop_index : i >= stop_index
      end
      result
    end

    def ref?(node)
      node.is_a?(ASTNode) && node.kind == :DOLLAR
    end

    def get_from_path(path_node)
      parts = unpack_path path_node
      result = @config.base_get parts.shift.value

      # We start the evaluation with the current instance, but a path may
      # cross sub-configuration boundaries, and references must always be
      # evaluated in the context of the immediately enclosing configuration,
      # not the top-level configuration (references are relative to the
      # root of the enclosing configuration - otherwise configurations would
      # not be standalone. So whenever we cross a sub-configuration boundary,
      # the current_evaluator has to be pegged to that sub-configuration.

      current_evaluator = result.is_a?(Config) ? result.evaluator : self

      parts.each do |part|
        op, operand = part
        sliced = operand.is_a? SliceNode
        operand = current_evaluator.evaluate(operand) if !sliced && op != :DOT && operand.is_a?(ASTNode)
        list_error = sliced && !result.is_a?(ListWrapper)
        raise BadIndexError, 'slices can only operate on lists' if list_error

        map_error = (result.is_a?(DictWrapper) || result.is_a?(Config)) && !operand.is_a?(String)
        raise BadIndexError, "string required, but found #{operand}" if map_error

        if result.is_a? DictWrapper
          raise ConfigError, "Not found in configuration: #{operand}" unless result.include? operand

          result = result.base_get operand
        elsif result.is_a? Config
          current_evaluator = result.evaluator
          result = result.base_get operand
        elsif result.is_a? ListWrapper
          n = result.length
          if operand.is_a? Integer
            operand += n if operand.negative? && operand >= -n
            msg = "index out of range: is #{operand}, must be between 0 and #{n - 1}"
            raise BadIndexError, msg if operand >= n || operand.negative?

            result = result.base_get operand
          elsif sliced
            result = get_slice result, operand
          else
            raise BadIndexError, "integer required, but found #{operand}"
          end
        else
          # result is not a Config, DictWrapper or ListWrapper.
          # Just throw a generic "not in configuration" error
          raise ConfigError, "Not found in configuration: #{to_source path_node}"
        end
        if ref? result
          if current_evaluator.refs_seen.include? result
            parts = current_evaluator.refs_seen.map { |item| "#{to_source item} #{item.start}" }
            ps = parts.sort.join(', ')
            raise CircularReferenceError, "Circular reference: #{ps}"
          end
          current_evaluator.refs_seen.add result
        end
        if result.is_a? MappingNode
          result = @config.wrap_mapping result
        elsif result.is_a? ListNode
          result = @config.wrap_list result
        end
        if result.is_a? ASTNode
          e = current_evaluator.evaluate result
          result = e unless e.equal? result
        end
      end
      @refs_seen.clear
      result
    end
  end

  class DictWrapper < Hash
    attr_reader :config

    alias base_get []

    def initialize(config)
      @config = config
    end

    def as_dict
      result = {}

      each do |k, v|
        rv = @config.evaluated v
        if rv.is_a?(DictWrapper) || rv.is_a?(Config)
          rv = rv.as_dict
        elsif rv.is_a? ListWrapper
          rv = rv.as_list
        end
        result[k] = rv
      end
      result
    end

    def [](key)
      raise ConfigError, "Not found in configuration: #{key}" unless include? key

      @config.evaluated base_get(key)
    end
  end

  class ListWrapper < Array
    attr_reader :config

    alias base_get []

    def initialize(config)
      @config = config
    end

    def as_list
      result = []
      each do |v|
        rv = @config.evaluated(v)
        if rv.is_a?(DictWrapper) || rv.is_a?(Config)
          rv = rv.as_dict
        elsif rv.is_a? ListWrapper
          rv = rv.as_list
        end
        result.push rv
      end
      result
    end

    def [](index)
      result = base_get index

      self[index] = result = @config.evaluated(result)
      result
    end
  end

  def unwrap(obj)
    if obj.is_a? DictWrapper
      obj.as_dict
    elsif obj.is_a? ListWrapper
      obj.as_list
    else
      obj
    end
  end

  def parse_path(src)
    parser = make_parser src

    raise InvalidPathError, "Invalid path: #{src}" if parser.next_token.kind != :WORD

    begin
      result = parser.primary
    rescue RecognizerError
      raise InvalidPathError, "Invalid path: #{src}"
    end
    raise InvalidPathError, "Invalid path: #{src}" unless parser.at_end

    result
  end

  def to_source(node)
    if node.is_a? Token
      node.value.to_s
    elsif !node.is_a? ASTNode
      node.to_s
    else
      result = []
      parts = unpack_path node
      result.push parts.shift.value
      parts.each do |part|
        op, operand = part
        case op
        when :DOT
          result.push ".#{operand}"
        when :COLON
          result.append '['
          result.append to_source(operand.start_index) unless operand.start_index.nil?
          result.append ':'
          result.append to_source(operand.stop_index) unless operand.stop_index.nil?
          result.append ":#{to_source operand.step}" unless operand.step.nil?
          result.append ']'
        when :LEFT_BRACKET
          result.append "[#{to_source operand}]"
        else
          raise ConfigError, "unable to compute source for #{node}"
        end
      end
      result.join('')
    end
  end

  def _visit(node, collector)
    if node.is_a? Token
      collector.push node
    elsif node.is_a? UnaryNode
      _visit(node.operand, collector)
    elsif node.is_a? BinaryNode
      _visit(node.lhs, collector)
      case node.kind
      when :DOT
        collector.push [node.kind, node.rhs.value]
      when :COLON # it's a slice
        collector.push [node.kind, node.rhs]
      else # it's an array access
        collector.push [node.kind, node.rhs.value]
      end
    end
  end

  def unpack_path(start)
    result = []
    _visit(start, result)
    result
  end

  SCALAR_TOKENS = Set[
    :STRING,
    :INTEGER,
    :FLOAT,
    :COMPLEX,
    :FALSE,
    :TRUE,
    :NONE
  ]

  class Config
    include Utils

    attr_accessor :no_duplicates
    attr_accessor :strict_conversions
    attr_accessor :context
    attr_accessor :include_path
    attr_accessor :path
    attr_accessor :root_dir
    attr_accessor :string_converter
    attr_accessor :parent
    attr_accessor :data
    attr_accessor :evaluator

    def initialize(path_or_reader = nil)
      @no_duplicates = true
      @strict_conversions = true
      @context = {}
      @include_path = []
      @path = nil
      @root_dir = nil
      @evaluator = Evaluator.new self
      @string_converter = method :default_string_converter

      @cache = nil
      @data = nil
      @parent = nil

      return if path_or_reader.nil?

      if path_or_reader.is_a? String
        load_file path_or_reader
      else
        load path_or_reader
      end
    end

    def cached
      !@cache.nil?
    end

    def cached=(cache)
      if !cache
        @cache = nil
      elsif @cache.nil?
        @cache = {}
      end
    end

    def self.identifier?(str)
      !/^[\p{L}_]([\p{L}\p{Nd}_]*)$/u.match(str).nil?
    end

    def load_file(path)
      f = File.open path, 'r:utf-8'
      load f
      f.close
    end

    def set_path(path)
      @path = path
      @root_dir = Pathname.new(path).parent
    end

    def wrap_mapping(node)
      result = DictWrapper.new self
      seen = @no_duplicates ? {} : nil
      node.elements.each do |t, v|
        k = t.value
        unless seen.nil?
          raise ConfigError, "Duplicate key #{k} seen at #{t.start} (previously at #{seen[k]})" if seen.include? k

          seen[k] = t.start
        end
        result[k] = v
      end
      result
    end

    def wrap_list(node)
      result = ListWrapper.new self
      result.concat node.elements
      result
    end

    def load(stream)
      parser = Parser.new stream
      node = parser.container
      unless node.is_a? MappingNode
        e = ConfigError.new 'Root configuration must be a mapping'

        e.location = node.start
        raise e
      end
      set_path stream.path if stream.is_a? File
      @data = wrap_mapping node
      @cache&.clear
    end

    def get_from_path(path)
      @evaluator.refs_seen.clear
      @evaluator.get_from_path parse_path(path)
    end

    def convert_string(str)
      result = @string_converter.call str, self
      raise ConfigError, "Unable to convert string #{str}" if strict_conversions && result.equal?(str)

      result
    end

    def evaluated(value, evaluator = nil)
      result = value
      if value.is_a? ASTNode
        e = evaluator.nil? ? @evaluator : evaluator
        result = e.evaluate value
      end
      result
    end

    MISSING = Object.new

    def base_get(key, default = MISSING)
      if @cache&.include?(key)
        result = @cache[key]
      elsif @data.nil?
        raise ConfigError, 'No data in configuration'
      else
        if @data.include? key
          result = evaluated @data[key]
        elsif Config.identifier? key
          raise ConfigError, "Not found in configuration: #{key}" if default.equal?(MISSING)

          result = default
        else
          # not an identifier. Treat as a path
          begin
            result = get_from_path key
          rescue InvalidPathError, BadIndexError, CircularReferenceError
            raise
          rescue ConfigError
            if default.equal? MISSING
              #e = ConfigError.new "Not found in configuration: #{key}"
              #raise e
              raise
            end
            result = default
          end
        end
        # if user specified a cache, populate it
        @cache[key] = result unless @cache.nil?
      end
      result
    end

    def get(key, default = MISSING)
      unwrap base_get(key, default)
    end

    def [](key)
      get key
    end

    def as_dict
      @data.nil? ? {} : @data.as_dict
    end
  end
end
