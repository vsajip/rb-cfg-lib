require 'set'
require 'stringio'

require 'CFG/config/version'

module CFG
  module Config

    module Utils
      def white_space?(c)
        c =~ /[[:space:]]/
      end

      def letter?(c)
        c =~ /[[:alpha:]]/
      end

      def digit?(c)
        c =~ /[[:digit:]]/
      end

      def alnum?(c)
        c =~ /[[:alnum:]]/
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
      ':': :COLON,
      '-': :MINUS,
      '+': :PLUS,
      '*': :STAR,
      '/': :SLASH,
      '%': :MODULO,
      ',': :COMMA,
      '{': :LEFT_CURLY,
      '}': :RIGHT_CURLY,
      '[': :LEFT_BRACKET,
      ']': :RIGHT_BRACKET,
      '(': :LEFT_PARENTHESIS,
      ')': :RIGHT_PARENTHESIS,
      '@': :AT,
      '$': :DOLLAR,
      '<': :LESS_THAN,
      '>': :GREATER_THAN,
      '!': :NOT,
      '~': :BITWISE_COMPLEMENT,
      '&': :BITWISE_AND,
      '|': :BITWISE_OR,
      '^': :BITWISEX_OR,
      '.': :DOT
    }.freeze

    KEYWORDS = {
      'true': :TRUE,    # rubocop:disable Lint/BooleanSymbol
      'false': :FALSE,  # rubocop:disable Lint/BooleanSymbol
      'null': :NONE,
      'is': :IS,
      'in': :IN,
      'not': :NOT,
      'and': :AND,
      'or': :OR
    }.freeze

    ESCAPES = {
      'a':  "\u0007",   # rubocop: disable Layout/HashAlignment
      'b':  "\b",       # rubocop: disable Layout/HashAlignment
      'f':  "\u000C",   # rubocop: disable Layout/HashAlignment
      'n':  "\n",       # rubocop: disable Layout/HashAlignment
      'r':  "\r",       # rubocop: disable Layout/HashAlignment
      't':  "\t",       # rubocop: disable Layout/HashAlignment
      'v':  "\u000B",   # rubocop: disable Layout/HashAlignment
      '\\': '\\',
      '\'': "'",
      '"':  '"'         # rubocop: disable Layout/HashAlignment
    }.freeze

    NULL_VALUE = Object.new

    KEYWORD_VALUES = {
      :TRUE => true,        # rubocop: disable Style/HashSyntax
      :FALSE => false,      # rubocop: disable Style/HashSyntax
      :NONE => NULL_VALUE   # rubocop: disable Style/HashSyntax
    }.freeze

    class Tokenizer
      include Utils

      def initialize(stream)
        @stream = stream
        @location = Location.new
        @char_location = Location.new
        @pushed_back = []
      end

      def push_back(c)
        if ((c != nil) && ((c == "\n") || !white_space?(c)))
          @pushed_back.push([c, Location.from(@char_location)])
        end
      end

      def get_char
        if @pushed_back.length > 0
          result, loc = @pushed_back.pop
          @char_location.update loc
          @location.update loc          # will be bumped later
        else
          @char_location.update @location
          result = @stream.read 1
        end
        if result != nil
          if result == "\n"
            @location.next_line
          else
            @location.column += 1
          end
        end
        result
      end

      def get_number
      end

      def parse_escapes(s)
        i = s.index '\\'
        if i == nil
          result = s
        else
          failed = false
          result = ''
          while i != nil
            result += s[0..i - 1]
            c = s[i + 1]
            if ESCAPES.key?(c)
              result += ESCAPES[c]
              i += 2
            elsif c =~ /xu/i
              if c == 'x' or c == 'X'
                slen = 4
              else
                slen = c == 'u' ? 6 : 10
              end
              if i + n > s.length
                failed = true
                break
              end
              p = s[i + 2 .. i + slen - 1]
              if p =~/^[[:xdigit:]]$/i
                failed = true
                break
              end
              j = p.to_i(base=16)
              if j.between?(0xd800, 0xdfff) or (j >= 0x110000)
                failed = true
                break
              end
              result += j.chr 'utf-8'
              i += slen
            end
            s = s[i..]
            i = s.index '\\'
          end
          if failed
            e = TokenizerError.new "Invalid escape sequence at index #{i}"
            raise e
          end
        end
        result
      end

      def append_char(token, c, end_location)
        token += c
        end_location.update @char_location
        token
      end

      def get_token
        start_location = Location.new
        end_location = Location.new
        kind = :EOF
        token = ''
        value = nil

        while true
          c = get_char

          start_location.update @char_location
          end_location.update @char_location

          if c == nil
            break
          end
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
            if c != "\n"
                push_back c
            end
            kind = :NEWLINE
            break
          elsif c == "\\"
            c = get_char
            if c != "\n"
              e = TokenizerError.new "Unexpected character: \\"
              e.location = @char_location
              raise e
            end
            end_location.update @char_location
            next
          elsif white_space?(c)
            next
          elsif c == "_" or letter?c
            kind = :WORD
            token = append_char token, c, end_location
            c = get_char
            while ((c != nil) && (alnum?(c) || (c == '_')))
                token = append_char token, c, end_location
                c = get_char
            end
            push_back c
            value = token
            if KEYWORDS.key?(value)
              kind = KEYWORDS[value]
              if KEYWORD_VALUES.key?(kind)
                value = KEYWORD_VALUES[kind]
              end
            end
            break
          elsif c == '`'
            kind = :BACKTICK
            token = append_char token, c, end_location
            while true
              c = get_char
              if c == nil
                break
              end
              token = append_char token, c, end_location
              if c == '`'
                break
              end
            end
            if c == nil
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
          elsif c == '"' or c == "'"
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
                if c2 == nil
                  @char_location.update c1_loc
                end
                push_back c1
              else
                multi_line = true
                token = append_char token, quote, end_location
                token = append_char token, quote, end_location
              end
            end

            quoter = token[0..]

            while true
              c = get_char
              if (c == nil)
                break
              end
              token = append_char token, c, end_location
              if ((c == quote) && !escaped)
                n = token.length

                if (!multi_line || (n >= 6) && (token[n - 3.. n - 1] == quoter) && token[n - 4] != '\\')
                  break
                end
              end
              escaped = (c == '\\') ? !escaped : false
            end
            if (c == '\u0000')
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
