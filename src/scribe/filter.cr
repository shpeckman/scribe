# src/scribe/filter.cr
module Scribe
  module Filter
    abstract def filter(text : String) : String
  end

  struct SingleLine
    include Filter

    def filter(text : String) : String
      return text unless text.each_char.any?(&.control?)

      String.build do |io|
        text.each_char do |char|
          if char == '\n' || char == '\t'
            io << ' '
          elsif !char.control?
            io << char
          end
        end
      end
    end
  end

  struct MultiLine
    include Filter

    getter tab : String

    def initialize(@tab : String = " ")
    end

    def filter(text : String) : String
      String.build do |io|
        text.each_char do |char|
          if char == '\n'
            io << char
          elsif char == '\t'
            io << @tab
          elsif !char.control?
            io << char
          end
        end
      end
    end
  end
end
