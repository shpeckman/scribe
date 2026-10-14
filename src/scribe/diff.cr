# src/scribe/diff.cr
module Scribe
  module Diff
    record Hunk, old_start : Int32, old_count : Int32, new_start : Int32, new_count : Int32

    LIMIT = 4096

    def self.hunks(old : Array(String), new : Array(String), limit : Int32 = LIMIT) : Array(Hunk)
      lead = 0
      while lead < old.size && lead < new.size && old[lead] == new[lead]
        lead += 1
      end

      trail = 0
      while trail < old.size - lead && trail < new.size - lead &&
            old[old.size - trail - 1] == new[new.size - trail - 1]
        trail += 1
      end

      head = old[lead, old.size - lead - trail]
      tail = new[lead, new.size - lead - trail]
      return [] of Hunk if head.empty? && tail.empty?

      script(head, tail, limit).try { |found| return shift(found, lead) }

      [Hunk.new(lead, head.size, lead, tail.size)]
    end

    private def self.shift(found : Array(Hunk), lead : Int32) : Array(Hunk)
      found.map do |hunk|
        Hunk.new(hunk.old_start + lead, hunk.old_count, hunk.new_start + lead, hunk.new_count)
      end
    end

    private def self.script(a : Array(String), b : Array(String), limit : Int32) : Array(Hunk)?
      return [] of Hunk if a.empty? && b.empty?
      return [Hunk.new(0, 0, 0, b.size)] if a.empty?
      return [Hunk.new(0, a.size, 0, 0)] if b.empty?

      total = a.size + b.size
      return nil if total > limit

      offset = total
      ahead  = Array(Int32).new(2 * total + 1, 0)
      trace  = [] of Array(Int32)

      (0..total).each do |depth|
        trace << ahead.dup
        step = -depth
        while step <= depth
          x = if step == -depth || (step != depth && ahead[step - 1 + offset] < ahead[step + 1 + offset])
                ahead[step + 1 + offset]
              else
                ahead[step - 1 + offset] + 1
              end
          y = x - step
          while x < a.size && y < b.size && a[x] == b[y]
            x += 1
            y += 1
          end
          ahead[step + offset] = x
          return walk(trace, a.size, b.size, offset) if x >= a.size && y >= b.size

          step += 2
        end
      end

      nil
    end

    private def self.walk(trace : Array(Array(Int32)), n : Int32, m : Int32, offset : Int32) : Array(Hunk)
      moves = [] of {Int32, Int32, Int32, Int32}
      x     = n
      y     = m

      (trace.size - 1).downto(0) do |depth|
        ahead = trace[depth]
        step  = x - y
        prior = if step == -depth || (step != depth && ahead[step - 1 + offset] < ahead[step + 1 + offset])
                  step + 1
                else
                  step - 1
                end
        previous_x = ahead[prior + offset]
        previous_y = previous_x - prior

        while x > previous_x && y > previous_y
          x -= 1
          y -= 1
        end

        moves << {previous_x, previous_y, x, y} if depth > 0
        x = previous_x
        y = previous_y
      end

      hunks = [] of Hunk
      moves.reverse_each do |(from_x, from_y, to_x, to_y)|
        removed  = to_x - from_x
        inserted = to_y - from_y
        next if removed == 0 && inserted == 0

        last = hunks.last?
        if last && last.old_start + last.old_count == from_x && last.new_start + last.new_count == from_y
          hunks[-1] = Hunk.new(last.old_start, last.old_count + removed, last.new_start, last.new_count + inserted)
        else
          hunks << Hunk.new(from_x, removed, from_y, inserted)
        end
      end
      hunks
    end
  end

  def self.diff(old : String, new : String, graphemes : Graphemes, limit : Int32 = Diff::LIMIT) : Array(Edit)
    return [] of Edit if old == new

    old_lines = old.split('\n')
    new_lines = new.split('\n')
    starts    = Array(Int32).new(old_lines.size + 1)
    at        = 0
    old_lines.each_with_index do |line, index|
      starts << at
      at += line.empty? ? 0 : graphemes.boundaries(line).size - 1
      at += 1 if index < old_lines.size - 1
    end
    starts << at
    total = at

    Diff.hunks(old_lines, new_lines, limit).map do |hunk|
      first  = hunk.old_start
      last   = hunk.old_start + hunk.old_count
      tail   = last >= old_lines.size
      pieces = new_lines[hunk.new_start, hunk.new_count]
      from   = starts[first]
      to     = tail ? total : starts[last]
      text   = pieces.join('\n')

      if tail
        if hunk.old_count == 0
          text = "\n" + text unless first == 0
        elsif pieces.empty? && first > 0
          from -= 1
        end
      elsif !pieces.empty?
        text += '\n'
      end

      Edit.new(from...to, text)
    end
  end
end
