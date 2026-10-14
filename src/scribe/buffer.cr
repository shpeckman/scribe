# src/scribe/buffer.cr
module Scribe
  class Buffer
    BREAK = "\n"

    getter size     : Int32
    getter revision : Int32

    @lines     : Array(Array(String))
    @starts    : Array(Int32)
    @text      : String?
    @flat      : Array(String)?
    @bytes     : Array(Int32)?
    @listeners : Array(Proc(Change, Nil))

    def initialize(clusters : Array(String) = [] of String)
      @lines     = [[] of String]
      @starts    = [0]
      @size      = 0
      @revision  = 0
      @text      = nil
      @flat      = nil
      @bytes     = nil
      @listeners = [] of Proc(Change, Nil)
      load(clusters)
    end

    def on_change(&block : Change -> Nil) : Proc(Nil)
      @listeners << block
      -> { @listeners.delete(block); nil }
    end

    def text : String
      @text ||= String.build do |io|
        @lines.each_with_index do |line, index|
          io << BREAK if index > 0
          line.each { |cluster| io << cluster }
        end
      end
    end

    def clusters : Array(String)
      @flat ||= begin
        flat = Array(String).new(@size)
        @lines.each_with_index do |line, index|
          flat << BREAK if index > 0
          flat.concat(line)
        end
        flat
      end
    end

    def byte_offset(offset : Int32) : Int32
      bytes[offset.clamp(0, @size)]
    end

    def offset_at_byte(byte : Int32, ceil : Bool = false) : Int32
      marks = bytes
      index = marks.bsearch_index { |mark| mark > byte } || marks.size
      floor = Math.max(index - 1, 0)
      ceil && marks[floor] < byte ? Math.min(floor + 1, @size) : floor
    end

    def empty? : Bool
      @size == 0
    end

    def line_count : Int32
      @lines.size
    end

    def line(index : Int32) : Array(String)
      @lines[index]
    end

    def line_start(index : Int32) : Int32
      @starts[index]
    end

    def line_end(index : Int32) : Int32
      @starts[index] + @lines[index].size
    end

    def position(offset : Int32) : {Int32, Int32}
      offset = offset.clamp(0, @size)
      line   = (@starts.bsearch_index { |start| start > offset } || @starts.size) - 1
      {line, offset - @starts[line]}
    end

    def offset(line : Int32, column : Int32) : Int32
      line = line.clamp(0, @lines.size - 1)
      @starts[line] + column.clamp(0, @lines[line].size)
    end

    def cluster(offset : Int32) : String?
      return nil unless 0 <= offset < @size

      line, column = position(offset)
      @lines[line][column]? || BREAK
    end

    def slice(range : Range(Int32, Int32)) : Array(String)
      from = range.begin.clamp(0, @size)
      to   = range.end.clamp(from, @size)
      return [] of String if from == to

      first, head = position(from)
      last, tail  = position(to)
      return @lines[first][head, tail - head] if first == last

      result = @lines[first][head..]
      (first + 1...last).each do |index|
        result << BREAK
        result.concat(@lines[index])
      end
      result << BREAK
      result.concat(@lines[last][0, tail])
      result
    end

    def slice_text(range : Range(Int32, Int32)) : String
      slice(range).join
    end

    def replace(range : Range(Int32, Int32), inserted : Array(String)) : Change
      from    = range.begin.clamp(0, @size)
      to      = range.end.clamp(from, @size)
      removed = slice(from...to)
      first, head = position(from)
      last, tail  = position(to)

      fresh = [@lines[first][0, head]]
      inserted.each do |cluster|
        if cluster == BREAK
          fresh << [] of String
        else
          fresh.last << cluster
        end
      end
      fresh.last.concat(@lines[last][tail..])

      @lines[first..last] = fresh
      @size     += inserted.size - removed.size
      @revision += 1
      @text      = nil
      @flat      = nil
      @bytes     = nil
      restart(first)

      change = Change.new(from, removed, inserted.dup)
      @listeners.dup.each(&.call(change))
      change
    end

    def find(needle : Array(String), from : Int32 = 0) : Int32?
      count = needle.size
      return nil if count == 0 || count > @size

      flat  = clusters
      limit = @size - count
      start = from.clamp(0, limit + 1)

      (start..limit).each { |offset| return offset if match?(flat, offset, needle) }
      (0...Math.min(start, limit + 1)).each { |offset| return offset if match?(flat, offset, needle) }
      nil
    end

    private def bytes : Array(Int32)
      @bytes ||= begin
        marks = Array(Int32).new(@size + 1)
        total = 0
        marks << 0
        clusters.each do |cluster|
          total += cluster.bytesize
          marks << total
        end
        marks
      end
    end

    private def load(clusters : Array(String)) : Nil
      clusters.each do |cluster|
        if cluster == BREAK
          @lines << [] of String
        else
          @lines.last << cluster
        end
      end
      @size = clusters.size
      restart(0)
    end

    private def restart(line : Int32) : Nil
      count = @lines.size
      @starts.pop(@starts.size - count) if @starts.size > count

      (line...count).each do |index|
        start = index == 0 ? 0 : @starts[index - 1] + @lines[index - 1].size + 1
        if index < @starts.size
          @starts[index] = start
        else
          @starts << start
        end
      end
    end

    private def match?(flat : Array(String), at : Int32, needle : Array(String)) : Bool
      needle.each_with_index do |cluster, offset|
        return false unless flat.unsafe_fetch(at + offset) == cluster
      end
      true
    end
  end
end
