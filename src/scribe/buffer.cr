# src/scribe/buffer.cr
module Scribe
  class Buffer
    BREAK   = "\n"
    JOURNAL = 256

    record Entry, revision : Int32, line : Int32, removed : Int32, inserted : Int32

    getter graphemes : Graphemes
    getter size      : Int32
    getter revision  : Int32

    @lines     : Array(Line)
    @sizes     : Array(Int32)
    @tree      : Array(Int32)
    @text      : String?
    @bytes     : Array(Int32)?
    @journal   : Deque(Entry)
    @listeners : Array(Proc(Change, Nil))

    def initialize(@graphemes : Graphemes, text : String = "")
      @lines     = Buffer.split(text).map { |part| Line.new(part, @graphemes) }
      @sizes     = @lines.map(&.size)
      @tree      = [] of Int32
      @size      = 0
      @revision  = 0
      @text      = nil
      @bytes     = nil
      @journal   = Deque(Entry).new
      @listeners = [] of Proc(Change, Nil)
      @size      = @sizes.sum + @sizes.size - 1
      rebuild
    end

    def self.split(text : String) : Array(String)
      text.empty? ? [""] : text.split('\n')
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
      total = 0
      node  = index.clamp(0, @lines.size)
      while node > 0
        total += @tree.unsafe_fetch(node)
        node  -= node & -node
      end
      total
    end

    def line_end(index : Int32) : Int32
      line_start(index) + @sizes[index]
    end

    def position(offset : Int32) : Position
      rest  = offset.clamp(0, @size)
      count = @lines.size
      node  = 0
      step  = 1
      while step <= count
        step <<= 1
      end
      step >>= 1

      while step > 0
        next_node = node + step
        if next_node <= count && @tree.unsafe_fetch(next_node) <= rest
          node  = next_node
          rest -= @tree.unsafe_fetch(next_node)
        end
        step >>= 1
      end

      Position.new(node, rest)
    end

    def offset(line : Int32, column : Int32) : Int32
      line = line.clamp(0, @lines.size - 1)
      line_start(line) + column.clamp(0, @lines[line].size)
    end

    def offset(position : Position) : Int32
      offset(position.line, position.column)
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
      bytes[found.line] + @lines[found.line].byte_at(found.column)
    end

    def offset_at_byte(byte : Int32, ceil : Bool = false) : Int32
      marks = bytes
      line  = Math.max((marks.bsearch_index { |mark| mark > byte } || marks.size) - 1, 0)
      row   = @lines[line]
      local = (byte - marks[line]).clamp(0, row.bytesize)
      line_start(line) + row.column_at(local, ceil)
    end

    def find(needle : String, from : Int32 = 0) : Range(Int32, Int32)?
      return nil if needle.empty? || needle.bytesize > text.bytesize

      start = byte_offset(from)
      locate(needle, start, text.bytesize) || locate(needle, 0, start + needle.bytesize - 1)
    end

    def find_all(needle : String) : Array(Range(Int32, Int32))
      found = [] of Range(Int32, Int32)
      return found if needle.empty?

      byte = 0
      while range = locate(needle, byte, text.bytesize)
        found << range
        byte = byte_offset(range.end)
      end
      found
    end

    def journal_since(revision : Int32) : Array(Entry)?
      return [] of Entry if revision == @revision
      return nil if revision > @revision
      first = @journal.first? || return nil
      return nil if first.revision > revision + 1

      @journal.select { |entry| entry.revision > revision }
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

      replace_lines(head.line, tail.line, fresh)
      @size     += new_total - old_total
      @revision += 1
      @text      = nil
      @bytes     = nil
      @journal << Entry.new(@revision, head.line, tail.line - head.line, fresh.size - 1)
      @journal.shift if @journal.size > JOURNAL

      inserted_size = new_total - lead - trail
      change = Change.new(start, removed, slice_text(start...(start + inserted_size)), old_total - lead - trail, inserted_size)
      @listeners.dup.each(&.call(change))
      change
    end

    private def locate(needle : String, from : Int32, limit : Int32) : Range(Int32, Int32)?
      haystack = text
      byte     = from
      while byte <= limit - needle.bytesize && (head = haystack.byte_index(needle, byte))
        break if head + needle.bytesize > limit

        tail  = head + needle.bytesize
        start = offset_at_byte(head)
        stop  = offset_at_byte(tail)
        return start...stop if byte_offset(start) == head && byte_offset(stop) == tail

        byte = head + 1
      end
      nil
    end

    private def common_lead(before : Line, after : Line, limit : Int32) : Int32
      count = 0
      while count < before.size && count < after.size
        stop = before.marks.unsafe_fetch(count + 1)
        break if stop > limit || stop != after.marks.unsafe_fetch(count + 1)
        count += 1
      end
      count
    end

    private def common_trail(before : Line, after : Line, limit : Int32, lead : Int32, same : Bool, single : Bool) : Int32
      count = 0
      floor = same ? lead : 0
      edge  = single ? lead : 0
      while count < before.size - floor && count < after.size - edge
        start = before.marks.unsafe_fetch(before.size - count - 1)
        break if start < limit
        break if before.bytesize - start != after.bytesize - after.marks.unsafe_fetch(after.size - count - 1)
        count += 1
      end
      count
    end

    private def replace_lines(first : Int32, last : Int32, fresh : Array(Line)) : Nil
      if fresh.size == last - first + 1
        fresh.each_with_index do |line, index|
          delta = line.size - @sizes[first + index]
          @lines[first + index] = line
          @sizes[first + index] = line.size
          adjust(first + index, delta) unless delta == 0
        end
      else
        @lines[first..last] = fresh
        @sizes[first..last] = fresh.map(&.size)
        rebuild
      end
    end

    private def adjust(index : Int32, delta : Int32) : Nil
      count = @lines.size
      node  = index + 1
      while node <= count
        @tree[node] += delta
        node += node & -node
      end
    end

    private def rebuild : Nil
      count = @lines.size
      tree  = @tree
      tree.pop(tree.size - count - 1) if tree.size > count + 1
      tree.fill(0)
      (count + 1 - tree.size).times { tree << 0 }
      @sizes.each_with_index do |size, index|
        node   = index + 1
        tree[node] += size + 1
        parent = node + (node & -node)
        tree[parent] += tree[node] if parent <= count
      end
      @tree = tree
    end

    private def bytes : Array(Int32)
      @bytes ||= begin
        marks = Array(Int32).new(@lines.size)
        total = 0
        @lines.each do |line|
          marks << total
          total += line.bytesize + 1
        end
        marks
      end
    end
  end
end
