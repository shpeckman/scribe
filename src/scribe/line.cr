# src/scribe/line.cr
module Scribe
  class Line
    CHUNK = 64 * 1024

    getter size : Int32

    @storage     : Bytes
    @text        : String?
    @marks       : Array(Int32)?
    @owner       : Mapped?
    @pieces      : Array(Bytes)
    @piece_marks : Array(Array(Int32)?)
    @rows        : Index?
    @bytes       : Index?
    @owners      : Array(String)
    @mixed       : Bool
    @chunk       : Int32

    def self.new(text : String, graphemes : Graphemes, chunk : Int32 = CHUNK) : Line
      chunk = Math.max(chunk, 1)
      marks = text.ascii_only? ? nil : graphemes.boundaries(text)
      return new(text, marks, chunk) if text.bytesize <= chunk

      pieces, local = divide(text.to_slice, marks, chunk)
      new(pieces, local, nil, false, chunk, [text])
    end

    def self.new(bytes : Bytes, graphemes : Graphemes, owner : Mapped? = nil, chunk : Int32 = CHUNK) : Line
      chunk = Math.max(chunk, 1)
      marks = bytes.all? { |byte| byte < 0x80 } ? nil : graphemes.boundaries(bytes)
      return new(bytes, marks, owner, chunk) if bytes.size <= chunk

      pieces, local = divide(bytes, marks, chunk)
      new(pieces, local, owner, false, chunk, [] of String)
    end

    def initialize(text : String, @marks : Array(Int32)?, @chunk : Int32 = CHUNK)
      @storage     = text.to_slice
      @text        = text
      @owner       = nil
      @size        = (found = @marks) ? found.size - 1 : text.bytesize
      @pieces      = [] of Bytes
      @piece_marks = [] of Array(Int32)?
      @rows        = nil
      @bytes       = nil
      @owners      = [text]
      @mixed       = false
    end

    def initialize(@storage : Bytes, @marks : Array(Int32)?, @owner : Mapped?, @chunk : Int32 = CHUNK)
      @text        = nil
      @size        = (found = @marks) ? found.size - 1 : @storage.size
      @pieces      = [] of Bytes
      @piece_marks = [] of Array(Int32)?
      @rows        = nil
      @bytes       = nil
      @owners      = [] of String
      @mixed       = false
    end

    private def initialize(@pieces : Array(Bytes), @piece_marks : Array(Array(Int32)?), @owner : Mapped?,
                           @mixed : Bool, @chunk : Int32, @owners : Array(String))
      @storage = Bytes.empty
      @text    = nil
      @marks   = nil
      @rows    = Index.new(@pieces.map_with_index { |piece, index| (found = @piece_marks[index]) ? found.size - 1 : piece.size })
      @bytes   = Index.new(@pieces.map(&.size))
      @size    = @rows.not_nil!.total
    end

    private def self.divide(storage : Bytes, marks : Array(Int32)?, chunk : Int32)
      pieces = [] of Bytes
      local  = [] of Array(Int32)?
      start  = 0

      while start < storage.size
        stop = Math.min(start + chunk, storage.size)
        if marks
          edge = marks.bsearch_index { |mark| mark > stop } || marks.size - 1
          stop = marks[Math.max(edge - 1, 0)]
          if stop <= start
            edge = marks.bsearch_index { |mark| mark > start } || marks.size - 1
            stop = marks[edge]
          end
        end

        pieces << storage[start, stop - start]
        if marks
          first = marks.bsearch_index { |mark| mark >= start } || 0
          last  = marks.bsearch_index { |mark| mark >= stop } || marks.size - 1
          local << marks[first..last].map { |mark| mark - start }
        else
          local << nil
        end
        start = stop
      end
      {pieces, local}
    end

    def self.splice(first : Line, head : Int32, last : Line, tail : Int32, text : String,
                    graphemes : Graphemes) : Line
      unless first.ascii? && last.ascii? && text.ascii_only?
        combined = String.build(head + text.bytesize + last.bytesize - tail) do |io|
          first.each_chunk(0, head) { |piece, _start| io.write(piece) }
          io << text
          last.each_chunk(tail, last.bytesize) { |piece, _start| io.write(piece) }
        end
        return Line.new(combined, graphemes, first.@chunk)
      end

      pieces = [] of Bytes
      first.each_chunk(0, head) { |piece, _start| pieces << piece }
      start = 0
      while start < text.bytesize
        stop = Math.min(start + first.@chunk, text.bytesize)
        pieces << text.to_slice[start, stop - start]
        start = stop
      end
      last.each_chunk(tail, last.bytesize) { |piece, _start| pieces << piece }
      pieces.reject!(&.empty?)

      total = pieces.sum(&.size)
      if total <= first.@chunk
        combined = String.build(total) { |io| pieces.each { |piece| io.write(piece) } }
        return Line.new(combined, graphemes, first.@chunk)
      end

      owners = first.@owners + last.@owners + [text]
      new(pieces, Array(Array(Int32)?).new(pieces.size, nil), first.@owner || last.@owner,
        true, first.@chunk, owners)
    end

    def text : String
      @text ||= String.build(bytesize) do |io|
        each_chunk { |piece, _start| io.write(piece) }
      end
    end

    def to_slice : Bytes
      return @storage if @pieces.empty?

      @storage = text.to_slice
    end

    def each_chunk(from : Int32 = 0, to : Int32 = bytesize, & : Bytes, Int32 -> Nil) : Nil
      from = from.clamp(0, bytesize)
      to   = to.clamp(from, bytesize)
      return if from == to

      if @pieces.empty?
        yield @storage[from, to - from], from
        return
      end

      index = @bytes.not_nil!
      piece, local = index.locate(from)
      while piece < @pieces.size && from < to
        bytes  = @pieces[piece]
        start  = index.prefix(piece)
        stop   = Math.min(local + (to - from), bytes.size)
        length = stop - local
        yield bytes[local, length], start + local if length > 0
        from += length
        piece += 1
        local = 0
      end
    end

    def byte(index : Int32) : UInt8?
      return nil unless 0 <= index < bytesize
      return @storage.unsafe_fetch(index) if @pieces.empty?

      piece, local = @bytes.not_nil!.locate(index)
      @pieces[piece].unsafe_fetch(local)
    end

    def mapped? : Bool
      !@mixed && !@owner.nil?
    end

    def chunked? : Bool
      !@pieces.empty?
    end

    def ascii? : Bool
      @pieces.empty? ? @marks.nil? : @piece_marks.all?(&.nil?)
    end

    def empty? : Bool
      @size == 0
    end

    def bytesize : Int32
      @pieces.empty? ? @storage.size : @bytes.not_nil!.total
    end

    def boundary(column : Int32) : Int32
      if @pieces.empty?
        (found = @marks) ? found.unsafe_fetch(column) : column
      else
        piece, local = @rows.not_nil!.locate(column)
        marks = @piece_marks[piece]
        offset = marks ? marks.unsafe_fetch(local) : local
        @bytes.not_nil!.prefix(piece) + offset
      end
    end

    def byte_at(column : Int32) : Int32
      boundary(column.clamp(0, @size))
    end

    def column_at(byte : Int32, ceil : Bool = false) : Int32
      if @pieces.empty?
        found = @marks || return byte.clamp(0, @size)
        index = found.bsearch_index { |mark| mark > byte } || found.size
        floor = Math.max(index - 1, 0)
        return ceil && found.unsafe_fetch(floor) < byte ? Math.min(floor + 1, @size) : Math.min(floor, @size)
      end

      byte = byte.clamp(0, bytesize)
      piece, local = @bytes.not_nil!.locate(byte)
      marks = @piece_marks[piece]
      column =
        if marks
          index = marks.bsearch_index { |mark| mark > local } || marks.size
          floor = Math.max(index - 1, 0)
          ceil && marks.unsafe_fetch(floor) < local ? Math.min(floor + 1, marks.size - 1) : Math.min(floor, marks.size - 1)
        else
          local
        end
      @rows.not_nil!.prefix(piece) + column
    end

    def bytes(column : Int32) : Bytes
      if @pieces.empty?
        start = boundary(column)
        return @storage[start, boundary(column + 1) - start]
      end

      piece, local = @rows.not_nil!.locate(column)
      marks = @piece_marks[piece]
      start = marks ? marks.unsafe_fetch(local) : local
      stop  = marks ? marks.unsafe_fetch(local + 1) : local + 1
      @pieces[piece][start, stop - start]
    end

    def cluster(column : Int32) : String
      String.new(bytes(column))
    end

    def char(column : Int32) : Char
      Char::Reader.new(bytes(column)).current_char
    end

    def slice(from : Int32 = 0, to : Int32 = size) : String
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      String.build(byte_at(to) - byte_at(from)) do |io|
        each_chunk(byte_at(from), byte_at(to)) { |piece, _start| io.write(piece) }
      end
    end

    def clusters(from : Int32 = 0, to : Int32 = size) : Array(String)
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      Array(String).new(to - from) { |index| cluster(from + index) }
    end

    def each_cluster(from : Int32 = 0, to : Int32 = size, & : Bytes, Int32 ->) : Nil
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      return if from == to

      if @pieces.empty?
        column = from
        while column < to
          start = boundary(column)
          yield @storage[start, boundary(column + 1) - start], column
          column += 1
        end
        return
      end

      piece, local = @rows.not_nil!.locate(from)
      column = from
      while column < to
        marks = @piece_marks[piece]
        count = marks ? marks.size - 1 : @pieces[piece].size
        while local < count && column < to
          start = marks ? marks.unsafe_fetch(local) : local
          stop  = marks ? marks.unsafe_fetch(local + 1) : local + 1
          yield @pieces[piece][start, stop - start], column
          local += 1
          column += 1
        end
        piece += 1
        local = 0
      end
    end

    def units(unit : Units, from : Int32 = 0, to : Int32 = size) : Int32
      from = from.clamp(0, @size)
      to   = to.clamp(from, @size)
      return to - from if unit.clusters? || ascii?
      return boundary(to) - boundary(from) if unit.bytes?
      return short_units(unit, from, to) if @pieces.empty?

      total = 0
      each_cluster(from, to) do |bytes, _column|
        reader = Char::Reader.new(bytes)
        while reader.pos < bytes.size
          total += unit.width(reader.current_char)
          reader.next_char
        end
      end
      total
    end

    private def short_units(unit : Units, from : Int32, to : Int32) : Int32
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
      return amount.clamp(0, @size) if unit.clusters? || ascii?
      return column_at(amount.clamp(0, bytesize)) if unit.bytes?
      return short_column_for(amount, unit) if @pieces.empty?

      total = 0
      each_cluster do |bytes, column|
        width = 0
        reader = Char::Reader.new(bytes)
        while reader.pos < bytes.size
          width += unit.width(reader.current_char)
          reader.next_char
        end
        return column if total + width > amount
        total += width
      end
      @size
    end

    private def short_column_for(amount : Int32, unit : Units) : Int32
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

      prefix.to_slice.each_with_index do |byte, index|
        return false unless self.byte(start + index) == byte
      end
      true
    end
  end
end
