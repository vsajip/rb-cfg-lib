require "CFG/config/version"

module CFG
  module Config
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

      def initialize(line=1, column=1)
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

      def initialize(kind, text, value=nil)
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
    }

    KEYWORDS = {
      "true": :TRUE,
      "false": :FALSE,
      "null": :NONE,
      "is": :IS,
      "in": :IN,
      "not": :NOT,
      "and": :AND,
      "or": :OR
    }
  end
end
