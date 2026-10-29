# src/scribe/line.cr
module Scribe
  class Line
    getter size : Int32

    @storage : Bytes
    @text    : String?
    @marks   : Array(Int32)?
    @owner   : Mapped?

    def self.new(text : String, graphemes : Graphemes) : Line
      text.ascii_only? ? new(text, nil) : new(text, graphemes.boundaries(text))
    end

    def self.new(bytes : Bytes, graphemes : Graphemes, owner : Mapped? = nil) : Line
      ascii = bytes.all? { |byte| byte < 0x80 }
      new(bytes, ascii ? nil : graphemes.boundaries(bytes), owner)
    end

    def initialize(text : String, @marks : Array(Int32)?)
      @storage = text.to_slice
      @text    = text
      @owner   = nil
      @size    = (found = @marks) ? found.size - 1 : text.bytesize
    end

    def initialize(@storage : Bytes, @marks : Array(Int32)?, @owner : Mapped?)
      @text = nil
      @size = (found = @marks) ? found.size - 1 : @storage.size
    end

    def text : String
      @text ||= String.new(@storage)
    end

    def to_slice : Bytes
      @storage
    end

    def mapped? : Bool
      !@owner.nil?
    end

    def ascii? : Bool
      @marks.nil?
    end

    def empty? : Bool
      @size == 0
    end

    def bytesize : Int32
      @storage.size
    end

    @[AlwaysInline]
    def boundary(column : Int32) : Int32
      (found = @marks) ? found.unsafe_fetch(column) : column
    end

    def byte_at(column : Int32) : Int32
      boundary(column.clamp(0, @size))
    end

    def column_at(byte : Int32, ceil : Bool = false) : Int32
      found = @marks || return byte.clamp(0, @size)
      index = found.bsearch_index { |mark| mark > byte } || found.size
      floor = Math.max(index - 1, 0)
      ceil && found.unsafe_fetch(floor) < byte ? Math.min(floor + 1, @size) : Math.min(floor, @size)
    end

    def bytes(column : Int32) : Bytes
      start = boundary(column)
      @storage[start, boundary(column + 1) - start]
    end

    def cluster(column : Int32) : String
      start = boundary(column)
      String.new(@storage[start, boundary(column + 1) - start])
    end

    def char(column : Int32) : Char
      Char::Reader.new(@storage, boundary(column)).current_char
    end

    def slice(from : Int32 = 0, to : Int32 = size) : String
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      String.new(@storage[boundary(from), boundary(to) - boundary(from)])
    end

    def clusters(from : Int32 = 0, to : Int32 = size) : Array(String)
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      Array(String).new(to - from) { |index| cluster(from + index) }
    end

    def each_cluster(from : Int32 = 0, to : Int32 = size, & : Bytes, Int32 ->) : Nil
      column = from.clamp(0, @size)
      stop   = to.clamp(column, @size)
      while column < stop
        start = boundary(column)
        yield @storage[start, boundary(column + 1) - start], column
        column += 1
      end
    end

    def units(unit : Units, from : Int32 = 0, to : Int32 = size) : Int32
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      return to - from if unit.clusters? || @marks.nil?
      return boundary(to) - boundary(from) if unit.bytes?

      total  = 0
      reader = Char::Reader.new(@storage, boundary(from))
      stop   = boundary(to)
      while reader.pos < stop
        total += unit.width(reader.current_char)
        reader.next_char
      end
      total
    end

    def column_for(amount : Int32, unit : Units) : Int32
      return amount.clamp(0, @size) if unit.clusters? || @marks.nil?
      return column_at(amount.clamp(0, bytesize)) if unit.bytes?

      total  = 0
      column = 0
      reader = Char::Reader.new(@storage)
      while column < @size
        stop  = boundary(column + 1)
        width = 0
        while reader.pos < stop
          width += unit.width(reader.current_char)
          reader.next_char
        end
        break if total + width > amount

        total  += width
        column += 1
      end
      column
    end

    def starts_with?(prefix : String, column : Int32 = 0) : Bool
      start = byte_at(column)
      return false if start + prefix.bytesize > bytesize

      @storage[start, prefix.bytesize] == prefix.to_slice
    end
  end
end
