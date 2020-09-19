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
          result = @stream.read 1
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

      def get_number(text, endloc)
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
          if (c != '.') && !alnum?(c)  # rubocop:disable Style/IfInsideElse
            push_back c
          else
            e = TokenizerError.new "Invalid character in number: #{c}"

            e.location = @char_location
            raise e
          end
        end

        s = text.gsub(/_/, '')

        if radix != 0
          value = s[2..-1].to_i radix
        elsif kind == :COMPLEX
          imaginary = s[0..-2].to_f
          value = Complex(0.0, imaginary)
        elsif in_exponent || dot_seen
          kind = :FLOAT
          value = s.to_f
        else
          radix = s[0] == '0' ? 8 : 10
          value = s.to_i radix
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
            result += str[0..i - 1]
            c = str[i + 1]
            if ESCAPES.key?(c)
              result += ESCAPES[c]
              i += 2
            elsif c =~ /xu/i
              slen = if c.upcase == 'X'
                       4
                     else
                       c == 'u' ? 6 : 10
                     end
              if i + n > str.length
                failed = true
                break
              end
              p = str[i + 2..i + slen - 1]
              if p =~ /^[[:xdigit:]]$/i
                failed = true
                break
              end
              j = p.to_i 16
              if j.between?(0xd800, 0xdfff) || (j >= 0x110000)
                failed = true
                break
              end
              result += j.chr 'utf-8'
              i += slen
            end
            str = str[i..-1]
            i = str.index '\\'
          end
          if failed
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

            while true
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
            rescue RecognizerError
              e.location = start_location
              raise e
            end
            break
          elsif digit?(c)
            token = append_char token, c, end_location
            token, kind, value = get_number token, end_location
            break
          elsif c == '='
            nc = get_char

            if nc != '='
              kind = :ASSIGN
              token = append_char token, c, end_location
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
                token, kind, value = get_number token, end_location
              end
            elsif c == '-'
              c = get_char
              if !digit?(c) && (c != '.')
                push_back c
              else
                token = append_char token, c, end_location
                token, kind, value = get_number token, end_location
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
  end
end
