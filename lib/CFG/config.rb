require "CFG/config/version"

module CFG
  module Config
    class Error < StandardError; end

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
        "(#{line}, #{column})"
      end
    end
  end
end
