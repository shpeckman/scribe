# src/scribe/line.cr
module Scribe
  class Line
    getter text  : String
    getter marks : Array(Int32)

    def self.new(text : String, graphemes : Graphemes) : Line
      new(text, graphemes.boundaries(text))
    end

    def initialize(@text : String, @marks : Array(Int32))
    end

    def size : Int32
      @marks.size - 1
    end

    def empty? : Bool
      @marks.size == 1
    end

    def bytesize : Int32
      @text.bytesize
    end

    def byte_at(column : Int32) : Int32
      @marks[column.clamp(0, size)]
    end

    def column_at(byte : Int32, ceil : Bool = false) : Int32
      index = @marks.bsearch_index { |mark| mark > byte } || @marks.size
      floor = Math.max(index - 1, 0)
      ceil && @marks[floor] < byte ? Math.min(floor + 1, size) : Math.min(floor, size)
    end

    def bytes(column : Int32) : Bytes
      start = @marks[column]
      @text.to_slice[start, @marks[column + 1] - start]
    end

    def cluster(column : Int32) : String
      start = @marks[column]
      @text.byte_slice(start, @marks[column + 1] - start)
    end

    def char(column : Int32) : Char
      Char::Reader.new(@text, @marks[column]).current_char
    end

    def slice(from : Int32 = 0, to : Int32 = size) : String
      from = from.clamp(0, size)
      to   = to.clamp(from, size)
      @text.byte_slice(@marks[from], @marks[to] - @marks[from])
    end

    def clusters(from : Int32 = 0, to : Int32 = size) : Array(String)
      from = from.clamp(0, size)
      to   = to.clamp(from, size)
      Array(String).new(to - from) { |index| cluster(from + index) }
    end

    def each_cluster(from : Int32 = 0, to : Int32 = size, & : Bytes, Int32 ->) : Nil
      bytes  = @text.to_slice
      column = from.clamp(0, size)
      stop   = to.clamp(column, size)
      while column < stop
        start = @marks.unsafe_fetch(column)
        yield bytes[start, @marks.unsafe_fetch(column + 1) - start], column
        column += 1
      end
    end

    def starts_with?(prefix : String, column : Int32 = 0) : Bool
      start = byte_at(column)
      return false if start + prefix.bytesize > bytesize

      @text.to_slice[start, prefix.bytesize] == prefix.to_slice
    end
  end
end
