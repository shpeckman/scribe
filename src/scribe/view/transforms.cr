# src/scribe/view/transforms.cr
module Scribe
  class View
    def surround(opener : String) : Bool
      closer = PAIRS[opener]? || return false

      @document.apply(self, History::Kind::Other) do |caret, _index|
        next nil if caret.empty?

        Stroke.new(caret.range, opener + @buffer.slice_text(caret.range) + closer, 1, 1 + caret.range.size)
      end
    end

    def unsurround : Bool
      @document.apply(self, History::Kind::Other) do |caret, _index|
        next nil if caret.range.size < 2

        opener = @buffer.cluster(caret.start) || next nil
        next nil unless PAIRS[opener]? == @buffer.cluster(caret.stop - 1)

        inner = @buffer.slice_text((caret.start + 1)...(caret.stop - 1))
        Stroke.new(caret.range, inner, 0, caret.range.size - 2)
      end
    end

    def add_caret_per_line : Bool
      spread = [] of Caret

      @carets.each do |caret|
        first = @buffer.position(caret.start).line
        stop  = @buffer.position(caret.stop)
        last  = stop.line
        last -= 1 if last > first && stop.column == 0 && !caret.empty?

        if first == last
          spread << caret
        else
          (first..last).each { |line| spread << Caret.at(@buffer.line_end(line)) }
        end
      end

      return false if spread.size <= @carets.size

      seat(spread, spread.size - 1)
      true
    end

    def add_caret_at_every_match(search : Search) : Bool
      found = search.matches(@buffer)
      return false if found.empty?

      seat(found.map { |range| Caret.new(range.begin, range.end) }, found.size - 1)
      true
    end

    private def transform_lines(& : Array(String) -> Array(String)) : Bool
      edits = [] of Edit

      blocks.each do |(first, last)|
        rows  = (first..last).map { |line| @buffer.line(line).text }
        fresh = yield rows
        next if fresh == rows

        edits << Edit.new(@buffer.line_start(first)...@buffer.line_end(last), fresh.join(Buffer::BREAK))
      end

      return false if edits.empty?

      replace_ranges(edits)
    end

    private def sort_lines : Bool
      transform_lines(&.sort)
    end

    private def reverse_lines : Bool
      transform_lines(&.reverse)
    end

    private def unique_lines : Bool
      transform_lines(&.uniq)
    end

    private def trim_trailing_whitespace : Bool
      transform_lines { |rows| rows.map { |row| row.rstrip(" \t") } }
    end

    private def join_lines : Bool
      edits = [] of Edit

      blocks.each do |(first, last)|
        stop = first == last ? Math.min(first + 1, @buffer.line_count - 1) : last
        next if stop == first

        rows   = (first..stop).map { |line| @buffer.line(line).text }
        joined = rows.first.rstrip(" \t")
        rows.skip(1).each do |row|
          piece = row.lstrip(" \t")
          next if piece.empty?

          joined = joined.empty? ? piece : "#{joined} #{piece}"
        end

        edits << Edit.new(@buffer.line_start(first)...@buffer.line_end(stop), joined)
      end

      return false if edits.empty?

      replace_ranges(edits)
    end

    private def recase(mode : Command) : Bool
      @document.apply(self, History::Kind::Other) do |caret, _index|
        next nil if caret.empty?

        text  = @buffer.slice_text(caret.range)
        fresh = case mode
                when .upper_case? then text.upcase
                when .lower_case? then text.downcase
                else                   titlecase(text)
                end
        next nil if fresh == text

        Stroke.new(caret.range, fresh, 0, count(fresh))
      end
    end

    private def titlecase(text : String) : String
      String.build do |io|
        start = true
        text.each_char do |char|
          io << (start ? char.upcase : char.downcase)
          start = !(char.alphanumeric? || char == '_')
        end
      end
    end

    private def subword_edge(from : Int32, delta : Int32) : Int32
      total = length

      if delta < 0
        index = from - 1
        return 0 if index <= 0

        while index > 0 && !subword_start?(index)
          index -= 1
        end
        index
      else
        index = from + 1
        return total if index >= total

        while index < total && !subword_start?(index)
          index += 1
        end
        index
      end
    end

    private def subword_start?(index : Int32) : Bool
      here = char_at(index) || return true
      back = char_at(index - 1) || return true
      return true if (kind_at(index).try(&.word?) || false) && !(kind_at(index - 1).try(&.word?) || false)
      return true if here != '_' && back == '_'

      here.uppercase? && !back.uppercase?
    end

    private def char_at(offset : Int32) : Char?
      return nil unless 0 <= offset < length

      found = @buffer.position(offset)
      row   = @buffer.line(found.line)
      found.column < row.size ? row.char(found.column) : '\n'
    end
  end
end
