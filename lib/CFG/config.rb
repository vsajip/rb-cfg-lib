require 'set'
require 'stringio'

require 'CFG/config/version'

module CFG
  module Config

    def white_space?(c)
      c =~ /[[:space:]]/
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
      def initialize(stream)
        @stream = stream
        @location = Location.new
        @char_location = Location.new
        @pushed_back = []
      end

      def push_back(c)
        if ((c != nil) && ((c == "\n") || !c.white_space?))
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

      def append_char
      end

      def get_number
      end

      def parse_escapes
      end

      def get_token
      end

    end
  end
end
