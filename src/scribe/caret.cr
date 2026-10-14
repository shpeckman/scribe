# src/scribe/caret.cr
module Scribe
  record Caret, anchor : Int32, head : Int32 do
    def self.at(offset : Int32) : Caret
      new(offset, offset)
    end

    def start : Int32
      Math.min(@anchor, @head)
    end

    def stop : Int32
      Math.max(@anchor, @head)
    end

    def range : Range(Int32, Int32)
      start...stop
    end

    def empty? : Bool
      @anchor == @head
    end

    def backward? : Bool
      @head < @anchor
    end

    def includes?(offset : Int32) : Bool
      start <= offset < stop
    end

    def clamp(limit : Int32) : Caret
      Caret.new(@anchor.clamp(0, limit), @head.clamp(0, limit))
    end

    def shift(delta : Int32) : Caret
      Caret.new(@anchor + delta, @head + delta)
    end

    def union(other : Caret) : Caret
      low  = Math.min(start, other.start)
      high = Math.max(stop, other.stop)
      backward? ? Caret.new(high, low) : Caret.new(low, high)
    end
  end
end
