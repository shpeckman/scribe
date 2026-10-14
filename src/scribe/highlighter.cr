# src/scribe/highlighter.cr
module Scribe
  abstract class Highlighter
    record Token, start : Int32, count : Int32, kind : String do
      def stop : Int32
        @start + @count
      end
    end

    abstract def highlight(line : Array(String), state : Int32) : {Array(Token), Int32}
  end

  class KeywordHighlighter < Highlighter
    KEYWORD = "keyword"
    STRING  = "string"
    COMMENT = "comment"
    NUMBER  = "number"
    TYPE    = "type"
    ESCAPE  = '\\'
    DIGITS  = "0123456789abcdefABCDEFxXoObB_."

    getter keywords           : Set(String)
    getter comment            : Array(String)
    getter quotes             : String
    getter suffixes           : String
    getter? multiline_strings : Bool
    getter? types             : Bool

    def initialize(keywords : Enumerable(String) = [] of String, *, comment : String? = nil,
                   @quotes : String = "\"'", @suffixes : String = "", @multiline_strings : Bool = false,
                   @types : Bool = true)
      @keywords = keywords.to_set
      @comment  = comment.try { |prefix| prefix.chars.map(&.to_s) } || [] of String
    end

    def highlight(line : Array(String), state : Int32) : {Array(Token), Int32}
      tokens = [] of Token
      size   = line.size
      index  = 0

      if state != 0
        stop = close(line, 0, state.unsafe_chr)
        tokens << Token.new(0, (stop || size), STRING)
        return {tokens, state} unless stop

        index = stop
      end

      while index < size
        char = lead(line, index)

        if comment?(line, index)
          tokens << Token.new(index, size - index, COMMENT)
          break
        elsif @quotes.includes?(char)
          stop = close(line, index + 1, char)
          if stop
            tokens << Token.new(index, stop - index, STRING)
            index = stop
          else
            tokens << Token.new(index, size - index, STRING)
            return {tokens, @multiline_strings ? char.ord : 0}
          end
        elsif char.ascii_number?
          stop = index + 1
          while stop < size && DIGITS.includes?(lead(line, stop))
            stop += 1
          end
          tokens << Token.new(index, stop - index, NUMBER)
          index = stop
        elsif char.letter? || char == '_'
          stop = index + 1
          while stop < size && word?(lead(line, stop))
            stop += 1
          end
          name = line[index, stop - index].join
          kind = @keywords.includes?(name) ? KEYWORD : (@types && char.uppercase? ? TYPE : nil)
          tokens << Token.new(index, stop - index, kind) if kind
          index = stop
        else
          index += 1
        end
      end

      {tokens, 0}
    end

    private def lead(line : Array(String), index : Int32) : Char
      line.unsafe_fetch(index)[0]? || ' '
    end

    private def word?(char : Char) : Bool
      char.alphanumeric? || char == '_' || @suffixes.includes?(char)
    end

    private def comment?(line : Array(String), index : Int32) : Bool
      return false if @comment.empty? || index + @comment.size > line.size

      @comment.each_with_index.all? { |cluster, offset| line.unsafe_fetch(index + offset) == cluster }
    end

    private def close(line : Array(String), from : Int32, quote : Char) : Int32?
      index = from
      while index < line.size
        char = lead(line, index)
        return index + 1 if char == quote
        index += char == ESCAPE ? 2 : 1
      end
      nil
    end
  end
end
