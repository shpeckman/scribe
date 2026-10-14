# src/scribe/view/lines.cr
module Scribe
  class View
    private def indent_lines : Bool
      edits = blocks.flat_map do |(first, last)|
        (first..last).map { |line| Edit.new(@buffer.line_start(line)...@buffer.line_start(line), @document.indent) }
      end
      replace_ranges(edits)
    end

    private def outdent_lines : Bool
      edits = [] of Edit
      blocks.each do |(first, last)|
        (first..last).each do |line|
          size  = outdent_size(@buffer.line(line))
          start = @buffer.line_start(line)
          edits << Edit.new(start...(start + size), "") if size > 0
        end
      end
      replace_ranges(edits)
    end

    private def outdent_size(line : Line) : Int32
      return count(@document.indent) if !@document.indent.empty? && line.starts_with?(@document.indent)
      return 1 if !line.empty? && line.char(0) == '\t'

      limit = @document.indent.includes?('\t') ? @document.tab_size : count(@document.indent)
      size  = 0
      while size < limit && size < line.size && line.char(size) == ' '
        size += 1
      end
      size
    end

    private def toggle_comment : Bool
      prefix  = @document.comment || return false
      lines   = blocks.flat_map { |(first, last)| (first..last).to_a }
      targets = lines.reject { |line| blank?(@buffer.line(line)) }
      return false if targets.empty?

      size      = count(prefix)
      commented = targets.all? { |line| @buffer.line(line).starts_with?(prefix, leading(@buffer.line(line))) }

      edits =
        if commented
          targets.map do |line|
            row    = @buffer.line(line)
            column = leading(row)
            span   = size
            span  += 1 if column + size < row.size && row.char(column + size) == ' '
            start  = @buffer.line_start(line) + column
            Edit.new(start...(start + span), "")
          end
        else
          column = targets.min_of { |line| leading(@buffer.line(line)) }
          targets.map do |line|
            start = @buffer.line_start(line) + column
            Edit.new(start...start, prefix + " ")
          end
        end

      replace_ranges(edits)
    end

    private def move_lines(step : Int32) : Bool
      spans = blocks
      return false if spans.empty?
      return false if step < 0 && spans.first[0] == 0
      return false if step > 0 && spans.last[1] == @buffer.line_count - 1

      edits  = [] of Edit
      shifts = [] of {Int32, Int32, Int32}

      spans.each do |(first, last)|
        block = @buffer.slice_text(@buffer.line_start(first)...@buffer.line_end(last))
        if step < 0
          other = @buffer.line(first - 1)
          edits << Edit.new(@buffer.line_start(first - 1)...@buffer.line_end(last), block + Buffer::BREAK + other.text)
          shifts << {@buffer.line_start(first), @buffer.line_end(last), -(other.size + 1)}
        else
          other = @buffer.line(last + 1)
          edits << Edit.new(@buffer.line_start(first)...@buffer.line_end(last + 1), other.text + Buffer::BREAK + block)
          shifts << {@buffer.line_start(first), @buffer.line_end(last), other.size + 1}
        end
      end

      replace_ranges(edits, after: @carets.map { |caret| Caret.new(shift_by(caret.anchor, shifts), shift_by(caret.head, shifts)) })
    end

    private def duplicate_lines : Bool
      edits  = [] of Edit
      shifts = [] of {Int32, Int32, Int32}
      total  = 0

      blocks.each do |(first, last)|
        start = @buffer.line_start(first)
        stop  = @buffer.line_end(last)
        edits << Edit.new(stop...stop, Buffer::BREAK + @buffer.slice_text(start...stop))
        shifts << {start, stop, total + (stop - start) + 1}
        total += (stop - start) + 1
      end

      after = @carets.map do |caret|
        Caret.new(shift_by(caret.anchor, shifts), shift_by(caret.head, shifts))
      end
      replace_ranges(edits, after: after)
    end

    private def delete_lines : Bool
      edits = blocks.map do |(first, last)|
        start = @buffer.line_start(first)
        stop  = @buffer.line_end(last)
        if last < @buffer.line_count - 1
          stop += 1
        elsif first > 0
          start -= 1
        end
        Edit.new(start...stop, "")
      end
      replace_ranges(edits)
    end

    private def blocks : Array({Int32, Int32})
      spans = [] of {Int32, Int32}

      @carets.each do |caret|
        first = @buffer.position(caret.start).line
        stop  = @buffer.position(caret.stop)
        last  = stop.line
        last -= 1 if last > first && stop.column == 0 && !caret.empty?

        if (previous = spans.last?) && first <= previous[1] + 1
          spans[-1] = {previous[0], Math.max(previous[1], last)}
        else
          spans << {first, last}
        end
      end

      spans
    end

    private def shift_by(offset : Int32, shifts : Array({Int32, Int32, Int32})) : Int32
      shifts.each do |(start, stop, delta)|
        return offset + delta if start <= offset <= stop
      end
      offset
    end

    private def leading(line : Line) : Int32
      column = 0
      while column < line.size && @graphemes.kind(line.bytes(column)).space?
        column += 1
      end
      column
    end

    private def blank?(line : Line) : Bool
      leading(line) == line.size
    end
  end
end
