require 'set'
require 'stringio'

require 'CFG/config/version'

module CFG
  module Config
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
        @pushed_back.push([chr, Location.from(@char_location)]) if !chr.nil? && ((chr == "\n") || !white_space?(chr))
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

    class UnaryNode < ASTNode
      attr_reader :operand

      def initialize(kind, operand)
        super(kind)
        @operand = operand
      end

      def to_s
        "UnaryNode(#{@kind}, #{@operand})"
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
        kind == :LEFT_BRACKET ? nil : _get_slice_element
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
        MappingNode.new result
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
        while EXPRESSION_STARTERS.include? kind
          result.push(expr)
          kind = @next_token.kind
          break unless %i[NEWLINE COMMA].include? kind

          advance
          kind = consume_newlines
        end
        ListNode.new result
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
  end
end
