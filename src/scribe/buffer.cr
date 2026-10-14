# src/scribe/buffer.cr
module Scribe
  class Buffer
    BREAK   = "\n"
    JOURNAL = 256

    record Entry, revision : Int32, line : Int32, removed : Int32, inserted : Int32, change : Change

    getter graphemes : Graphemes
    getter size      : Int32
    getter bytesize  : Int32
    getter revision  : Int32

    @lines     : Array(Line)
    @rows      : Index
    @bytes     : Index
    @bytesize  : Int32
    @text      : String?
    @journal   : Deque(Entry)
    @listeners : Array(Proc(Change, Nil))

    def initialize(@graphemes : Graphemes, text : String = "")
      @lines     = Buffer.split(text).map { |part| Line.new(part, @graphemes) }
      @rows      = Index.new(@lines.map { |line| line.size + 1 })
      @bytes     = Index.new(@lines.map { |line| line.bytesize + 1 })
      @size      = @rows.total - 1
      @bytesize  = @bytes.total - 1
      @revision  = 0
      @text      = nil
      @journal   = Deque(Entry).new
      @listeners = [] of Proc(Change, Nil)
    end

    def self.split(text : String) : Array(String)
      text.empty? ? [""] : text.split('\n')
    end

    def self.split(bytes : Bytes) : Array(String)
      return [""] if bytes.empty?

      found = [] of String
      start = 0
      index = 0
      while index < bytes.size
        if bytes.unsafe_fetch(index) == 0x0a
          found << String.new(bytes[start, index - start])
          start = index + 1
        end
        index += 1
      end
      found << String.new(bytes[start, bytes.size - start])
      found
    end

    def self.map(graphemes : Graphemes, path : String) : Buffer
      Mapped.open(path) do |mapped|
        mapped.sequential
        new(graphemes, Buffer.split(mapped.bytes).map { |part| Line.new(part, graphemes) })
      end
    end

    def initialize(@graphemes : Graphemes, lines : Array(Line))
      @lines     = lines.empty? ? [Line.new("", nil)] : lines
      @rows      = Index.new(@lines.map { |line| line.size + 1 })
      @bytes     = Index.new(@lines.map { |line| line.bytesize + 1 })
      @size      = @rows.total - 1
      @bytesize  = @bytes.total - 1
      @revision  = 0
      @text      = nil
      @journal   = Deque(Entry).new
      @listeners = [] of Proc(Change, Nil)
    end

    def on_change(&block : Change -> Nil) : Proc(Nil)
      @listeners << block
      -> { @listeners.delete(block); nil }
    end

    def empty? : Bool
      @size == 0
    end

    def line_count : Int32
      @lines.size
    end

    def line(index : Int32) : Line
      @lines[index]
    end

    def line_start(index : Int32) : Int32
      @rows.prefix(index.clamp(0, @lines.size))
    end

    def line_byte(index : Int32) : Int32
      @bytes.prefix(index.clamp(0, @lines.size))
    end

    def line_end(index : Int32) : Int32
      line_start(index) + @lines[index].size
    end

    def position(offset : Int32) : Position
      line, column = @rows.locate(offset.clamp(0, @size))
      Position.new(line, column)
    end

    def byte_position(byte : Int32) : Position
      line, column = @bytes.locate(byte.clamp(0, @bytesize))
      Position.new(line, column)
    end

    def offset(line : Int32, column : Int32) : Int32
      line = line.clamp(0, @lines.size - 1)
      line_start(line) + column.clamp(0, @lines[line].size)
    end

    def offset(position : Position) : Int32
      offset(position.line, position.column)
    end

    def point(offset : Int32, unit : Units) : Point
      found = position(offset)
      Point.new(found.line, @lines[found.line].units(unit, 0, found.column))
    end

    def offset_at(point : Point, unit : Units) : Int32
      line = point.line.clamp(0, @lines.size - 1)
      line_start(line) + @lines[line].column_for(point.column, unit)
    end

    def measure(text : String, unit : Units) : Int32
      case unit
      in .clusters?    then text.empty? ? 0 : @graphemes.boundaries(text).size - 1
      in .bytes?       then text.bytesize
      in .code_points? then text.size
      in .utf16?       then text.each_char.sum { |char| unit.width(char) }
      end
    end

    def cluster(offset : Int32) : String?
      return nil unless 0 <= offset < @size

      found = position(offset)
      line  = @lines[found.line]
      found.column < line.size ? line.cluster(found.column) : BREAK
    end

    def kind(offset : Int32) : ClusterKind?
      return nil unless 0 <= offset < @size

      found = position(offset)
      line  = @lines[found.line]
      @graphemes.kind(found.column < line.size ? line.bytes(found.column) : BREAK.to_slice)
    end

    def width(line : Int32, from : Int32 = 0, to : Int32 = Int32::MAX) : Int32
      total = 0
      @lines[line].each_cluster(from, to) { |bytes, _column| total += @graphemes.width(bytes) }
      total
    end

    def index(line : Int32, width : Int32, from : Int32 = 0, to : Int32 = Int32::MAX) : Int32
      row    = @lines[line]
      stop   = to.clamp(0, row.size)
      column = Math.max(from, 0)
      edge   = 0
      while column < stop
        extent = @graphemes.width(row.bytes(column))
        return column if width < edge + extent
        edge   += extent
        column += 1
      end
      Math.min(column, stop)
    end

    def text : String
      @text ||= String.build do |io|
        @lines.each_with_index do |line, index|
          io << BREAK if index > 0
          io << line.text
        end
      end
    end

    def slice_text(range : Range(Int32, Int32)) : String
      from = range.begin.clamp(0, @size)
      to   = range.end.clamp(from, @size)
      return "" if from == to

      first = position(from)
      last  = position(to)
      return @lines[first.line].slice(first.column, last.column) if first.line == last.line

      String.build do |io|
        io << @lines[first.line].slice(first.column)
        (first.line + 1...last.line).each { |index| io << BREAK << @lines[index].text }
        io << BREAK << @lines[last.line].slice(0, last.column)
      end
    end

    def byte_offset(offset : Int32) : Int32
      found = position(offset)
      line_byte(found.line) + @lines[found.line].byte_at(found.column)
    end

    def offset_at_byte(byte : Int32, ceil : Bool = false) : Int32
      found = byte_position(byte)
      row   = @lines[found.line]
      line_start(found.line) + row.column_at(found.column.clamp(0, row.bytesize), ceil)
    end

    def byte_text(from : Int32, to : Int32) : String
      from = from.clamp(0, @bytesize)
      to   = to.clamp(from, @bytesize)
      return "" if from == to

      head = byte_position(from)
      tail = byte_position(to)
      return @lines[head.line].text.byte_slice(head.column, tail.column - head.column) if head.line == tail.line

      String.build do |io|
        first = @lines[head.line].text
        io.write(first.to_slice[head.column, first.bytesize - head.column])
        (head.line + 1...tail.line).each { |index| io << BREAK << @lines[index].text }
        io << BREAK
        io.write(@lines[tail.line].text.to_slice[0, tail.column])
      end
    end

    def chunk(byte : Int32) : Bytes
      return Bytes.empty unless 0 <= byte < @bytesize

      found = byte_position(byte)
      row   = @lines[found.line]
      return BREAK.to_slice if found.column >= row.bytesize

      row.text.to_slice[found.column, row.bytesize - found.column]
    end

    def find(needle : String, from : Int32 = 0) : Range(Int32, Int32)?
      return nil if needle.empty? || needle.bytesize > @bytesize

      start = from.clamp(0, @size)
      at    = position(start)
      each_match(needle, at.line, at.column) { |range| return range }
      each_match(needle, 0, 0) { |range| return range if range.begin < start }
      nil
    end

    def find_all(needle : String) : Array(Range(Int32, Int32))
      found = [] of Range(Int32, Int32)
      return found if needle.empty? || needle.bytesize > @bytesize

      each_match(needle, 0, 0) { |range| found << range }
      found
    end

    private def each_match(needle : String, line : Int32, column : Int32, & : Range(Int32, Int32) -> Nil) : Nil
      parts = needle.split(BREAK)
      return each_flat(parts.first, line, column) { |range| yield range } if parts.size == 1

      tail = parts.size - 1
      row  = line
      while row + tail < @lines.size
        head = ends_at(@lines[row], parts.first, row == line ? column : 0)
        if head && spans?(parts, row)
          last  = row + tail
          stop  = starts_at(@lines[last], parts.last)
          start = line_start(row) + head
          if stop
            yield start...(line_start(last) + stop)
            row = last
            next
          end
        end
        row += 1
      end
    end

    private def each_flat(needle : String, line : Int32, column : Int32, & : Range(Int32, Int32) -> Nil) : Nil
      row = line
      at  = column
      while row < @lines.size
        if found = match_in(@lines[row], needle, at)
          start = line_start(row) + found[0]
          yield start...(start + found[1])
          at = found[0] + found[1]
        else
          row += 1
          at = 0
        end
      end
    end

    private def match_in(row : Line, needle : String, from : Int32) : {Int32, Int32}?
      byte  = row.byte_at(from)
      limit = row.bytesize - needle.bytesize
      while byte <= limit
        head = row.text.byte_index(needle, byte) || return nil
        return nil if head > limit

        start = row.column_at(head)
        stop  = row.column_at(head + needle.bytesize)
        return {start, stop - start} if row.boundary(start) == head && row.boundary(stop) == head + needle.bytesize

        byte = head + 1
      end
      nil
    end

    private def ends_at(row : Line, part : String, from : Int32) : Int32?
      return row.size if part.empty? && from <= row.size
      return nil if part.bytesize > row.bytesize

      head = row.bytesize - part.bytesize
      return nil unless row.text.to_slice[head, part.bytesize] == part.to_slice

      start = row.column_at(head)
      return nil unless row.boundary(start) == head && start >= from

      start
    end

    private def starts_at(row : Line, part : String) : Int32?
      return 0 if part.empty?
      return nil unless row.starts_with?(part)

      stop = row.column_at(part.bytesize)
      row.boundary(stop) == part.bytesize ? stop : nil
    end

    private def spans?(parts : Array(String), row : Int32) : Bool
      (1...parts.size - 1).all? { |index| @lines[row + index].text == parts[index] }
    end

    def journal_since(revision : Int32) : Array(Entry)?
      return [] of Entry if revision == @revision
      return nil if revision > @revision
      first = @journal.first? || return nil
      return nil if first.revision > revision + 1

      @journal.select { |entry| entry.revision > revision }
    end

    def changes_since(revision : Int32) : Array(Change)?
      journal_since(revision).try(&.map(&.change))
    end

    def replace(range : Range(Int32, Int32), text : String) : Change
      from  = range.begin.clamp(0, @size)
      to    = range.end.clamp(from, @size)
      head  = position(from)
      tail  = position(to)
      first = @lines[head.line]
      last  = @lines[tail.line]

      head_byte = first.byte_at(head.column)
      tail_byte = last.byte_at(tail.column)
      combined  = first.text.byte_slice(0, head_byte) + text + last.text.byte_slice(tail_byte, last.bytesize - tail_byte)
      fresh     = Buffer.split(combined).map { |part| Line.new(part, @graphemes) }

      lead  = common_lead(first, fresh.first, head_byte)
      trail = common_trail(last, fresh.last, tail_byte, lead, head.line == tail.line, fresh.size == 1)

      old_total = (head.line..tail.line).sum { |index| @lines[index].size } + (tail.line - head.line)
      new_total = fresh.sum(&.size) + (fresh.size - 1)
      start     = line_start(head.line) + lead
      removed   = slice_text(start...(start + old_total - lead - trail))

      old_bytes = (head.line..tail.line).sum { |index| @lines[index].bytesize } + (tail.line - head.line)
      replace_lines(head.line, tail.line, fresh)
      @size     += new_total - old_total
      @bytesize += fresh.sum(&.bytesize) + (fresh.size - 1) - old_bytes
      @revision += 1
      @text      = nil

      inserted_size = new_total - lead - trail
      change = Change.new(start, removed, slice_text(start...(start + inserted_size)), old_total - lead - trail, inserted_size)
      @journal << Entry.new(@revision, head.line, tail.line - head.line, fresh.size - 1, change)
      @journal.shift if @journal.size > JOURNAL
      @listeners.dup.each(&.call(change))
      change
    end

    private def common_lead(before : Line, after : Line, limit : Int32) : Int32
      count = 0
      while count < before.size && count < after.size
        stop = before.boundary(count + 1)
        break if stop > limit || stop != after.boundary(count + 1)
        count += 1
      end
      count
    end

    private def common_trail(before : Line, after : Line, limit : Int32, lead : Int32, same : Bool, single : Bool) : Int32
      count = 0
      floor = same ? lead : 0
      edge  = single ? lead : 0
      while count < before.size - floor && count < after.size - edge
        start = before.boundary(before.size - count - 1)
        break if start < limit
        break if before.bytesize - start != after.bytesize - after.boundary(after.size - count - 1)
        count += 1
      end
      count
    end

    private def replace_lines(first : Int32, last : Int32, fresh : Array(Line)) : Nil
      if fresh.size == last - first + 1
        fresh.each_with_index do |line, index|
          at         = first + index
          @lines[at] = line
          @rows.set(at, line.size + 1)
          @bytes.set(at, line.bytesize + 1)
        end
      else
        @lines[first..last] = fresh
        @rows.replace(first, last, fresh.map { |line| line.size + 1 })
        @bytes.replace(first, last, fresh.map { |line| line.bytesize + 1 })
      end
    end
  end
end
