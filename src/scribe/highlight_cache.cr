# src/scribe/highlight_cache.cr
module Scribe
  class HighlightCache
    include Listener

    NONE = [] of Highlighter::Token

    getter highlighter : Highlighter?

    @tokens : Array(Array(Highlighter::Token)?)
    @ends   : Array(Int32)
    @valid  : Int32

    def initialize(@highlighter : Highlighter? = nil)
      @tokens = [] of Array(Highlighter::Token)?
      @ends   = [] of Int32
      @valid  = 0
    end

    def highlighter=(value : Highlighter?) : Highlighter?
      @highlighter = value
      reset
      value
    end

    def reset : Nil
      @tokens.clear
      @ends.clear
      @valid = 0
    end

    def tokens(buffer : Buffer, line : Int32) : Array(Highlighter::Token)
      catch_up(buffer, line)
      @tokens[line]? || NONE
    end

    def applied(document : Document, change : Change) : Nil
      line     = document.buffer.position(change.from)[0]
      removed  = change.removed.count(Buffer::BREAK)
      inserted = change.inserted.count(Buffer::BREAK)

      @tokens[line..Math.min(line + removed, @tokens.size - 1)] = Array(Array(Highlighter::Token)?).new(inserted + 1, nil) if line < @tokens.size
      @ends[line..Math.min(line + removed, @ends.size - 1)] = Array(Int32).new(inserted + 1, 0) if line < @ends.size
      @valid = Math.min(@valid, line)
    end

    private def catch_up(buffer : Buffer, line : Int32) : Nil
      marker = @highlighter || return

      while @valid <= line && @valid < buffer.line_count
        state          = @valid == 0 ? 0 : @ends[@valid - 1]
        found, closing = marker.highlight(buffer.line(@valid), state)
        store(@tokens, @valid, found)
        store(@ends, @valid, closing)
        @valid += 1
      end
    end

    private def store(list : Array(T), index : Int32, value : T) : Nil forall T
      if index < list.size
        list[index] = value
      else
        list << value
      end
    end
  end
end
