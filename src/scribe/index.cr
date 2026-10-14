# src/scribe/index.cr
module Scribe
  class Index
    BLOCK = 512
    LIMIT = 1024

    getter count : Int32
    getter total : Int32

    @blocks : Array(Array(Int32))
    @counts : Array(Int32)
    @sums   : Array(Int32)

    def initialize(weights : Array(Int32) = [] of Int32)
      @blocks = [] of Array(Int32)
      @counts = [] of Int32
      @sums   = [] of Int32
      @count  = 0
      @total  = 0
      build(weights)
    end

    def [](line : Int32) : Int32
      block, offset = seat(line)
      @blocks[block][offset]? || 0
    end

    def prefix(line : Int32) : Int32
      line = line.clamp(0, @count)
      return @total if line == @count

      block, offset = seat(line)
      found = ahead(@sums, block)
      rows  = @blocks[block]
      offset.times { |index| found += rows.unsafe_fetch(index) }
      found
    end

    def locate(value : Int32) : {Int32, Int32}
      return {Math.max(@count - 1, 0), 0} if @count == 0

      if value >= @total
        last = @count - 1
        return {last, self[last]}
      end

      rest = Math.max(value, 0)

      block, rest = descend(@sums, rest)
      block = Math.min(block, @blocks.size - 1)
      rows  = @blocks[block]
      line  = ahead(@counts, block)

      index = 0
      while index < rows.size - 1 && rest >= rows.unsafe_fetch(index)
        rest -= rows.unsafe_fetch(index)
        index += 1
      end
      {line + index, rest}
    end

    def set(line : Int32, weight : Int32) : Nil
      return if line < 0 || line >= @count

      block, offset = seat(line)
      rows  = @blocks[block]
      delta = weight - rows[offset]
      return if delta == 0

      rows[offset] = weight
      @sums[block] += delta
      adjust(@sums, block, delta)
      @total += delta
    end

    def replace(first : Int32, last : Int32, weights : Array(Int32)) : Nil
      removed = Math.max(last - first + 1, 0)
      if removed == weights.size
        weights.each_with_index { |weight, index| set(first + index, weight) }
        return
      end

      drop(first, removed)
      insert(first, weights)
    end

    def insert(line : Int32, weights : Array(Int32)) : Nil
      return if weights.empty?

      if @count == 0
        build(weights)
        return
      end

      line = line.clamp(0, @count)
      if line == @count
        block  = @blocks.size - 1
        offset = @blocks[block].size
      else
        block, offset = seat(line)
      end

      rows = @blocks[block]
      weights.each_with_index { |weight, index| rows.insert(offset + index, weight) }
      added   = weights.sum
      @count += weights.size
      @total += added

      if rows.size > LIMIT
        split(block)
      else
        adjust(@counts, block, weights.size)
        adjust(@sums, block, added)
      end
    end

    def drop(line : Int32, removed : Int32) : Nil
      return if removed <= 0 || @count == 0

      line  = line.clamp(0, @count - 1)
      count = Math.min(removed, @count - line)
      left  = count

      while left > 0
        block, offset = seat(line)
        rows = @blocks[block]
        take = Math.min(left, rows.size - offset)
        break if take <= 0

        gone = 0
        take.times { gone += rows.delete_at(offset) }
        @count -= take
        @total -= gone
        left   -= take

        if rows.empty? && @blocks.size > 1
          @blocks.delete_at(block)
          rebuild
        else
          adjust(@counts, block, -take)
          adjust(@sums, block, -gone)
        end
      end

      build([] of Int32) if @count == 0
    end

    def to_a : Array(Int32)
      found = Array(Int32).new(@count)
      @blocks.each { |rows| rows.each { |weight| found << weight } }
      found
    end

    private def build(weights : Array(Int32)) : Nil
      @blocks = [] of Array(Int32)
      weights.each_slice(BLOCK) { |slice| @blocks << slice.dup }
      @blocks << [] of Int32 if @blocks.empty?
      @count = weights.size
      @total = weights.sum
      rebuild
    end

    private def split(block : Int32) : Nil
      rows = @blocks[block]
      half = rows.size // 2
      tail = rows[half, rows.size - half]
      rows.pop(rows.size - half)
      @blocks.insert(block + 1, tail)
      rebuild
    end

    private def rebuild : Nil
      @counts = Array(Int32).new(@blocks.size + 1, 0)
      @sums   = Array(Int32).new(@blocks.size + 1, 0)
      fill(@counts, @blocks.map(&.size))
      fill(@sums, @blocks.map(&.sum))
    end

    private def seat(line : Int32) : {Int32, Int32}
      line = line.clamp(0, Math.max(@count - 1, 0))
      block, offset = descend(@counts, line)
      block = Math.min(block, @blocks.size - 1)
      {block, offset}
    end

    private def fill(tree : Array(Int32), values : Array(Int32)) : Nil
      size = values.size
      tree.fill(0)
      values.each_with_index do |value, index|
        node = index + 1
        tree[node] += value
        parent = node + (node & -node)
        tree[parent] += tree[node] if parent <= size
      end
    end

    private def ahead(tree : Array(Int32), index : Int32) : Int32
      total = 0
      node  = index.clamp(0, @blocks.size)
      while node > 0
        total += tree.unsafe_fetch(node)
        node -= node & -node
      end
      total
    end

    private def descend(tree : Array(Int32), rest : Int32) : {Int32, Int32}
      size = @blocks.size
      node = 0
      step = 1
      while step <= size
        step <<= 1
      end
      step >>= 1

      while step > 0
        ahead = node + step
        if ahead <= size && tree.unsafe_fetch(ahead) <= rest
          node = ahead
          rest -= tree.unsafe_fetch(ahead)
        end
        step >>= 1
      end
      {node, rest}
    end

    private def adjust(tree : Array(Int32), index : Int32, delta : Int32) : Nil
      size = @blocks.size
      node = index + 1
      while node <= size
        tree[node] += delta
        node += node & -node
      end
    end
  end
end
