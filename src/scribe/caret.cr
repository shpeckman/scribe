# src/scribe/caret.cr
module Scribe
  record Caret, anchor : Int32, head : Int32, goal : Int32? = nil do
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
      copy_with(anchor: @anchor.clamp(0, limit), head: @head.clamp(0, limit))
    end

    def shift(delta : Int32) : Caret
      copy_with(anchor: @anchor + delta, head: @head + delta)
    end

    def union(other : Caret) : Caret
      low  = Math.min(start, other.start)
      high = Math.max(stop, other.stop)
      backward? ? Caret.new(high, low) : Caret.new(low, high)
    end
  end
end
