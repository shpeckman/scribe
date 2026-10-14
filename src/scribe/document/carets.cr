# src/scribe/document/carets.cr
module Scribe
  class Document
    def move(index : Int32, selecting : Bool = false) : Nil
      anchor = selecting ? primary_caret.anchor : index
      seat([Caret.new(anchor, index)], 0)
      auto_copy if selecting && !@dragging
    end

    def move_carets(selecting : Bool, & : Caret -> Int32) : Nil
      list = @carets.map do |caret|
        head = yield caret
        selecting ? Caret.new(caret.anchor, head) : Caret.at(head)
      end
      seat(list, @primary)
      auto_copy if selecting && !@dragging
    end

    def select_range(from : Int32, to : Int32) : Nil
      seat([Caret.new(from, to)], 0)
    end

    def select_all : Nil
      select_range(0, length)
      auto_copy
    end

    def select_word : Nil
      list = @carets.map do |caret|
        span = word_at(caret.head)
        span ? Caret.new(span.begin, span.end) : caret
      end
      seat(list, @primary)
      auto_copy
    end

    def select_line : Nil
      list = @carets.map do |caret|
        first = @buffer.position(caret.start).line
        stop  = @buffer.position(caret.stop)
        last  = stop.line
        last -= 1 if last > first && stop.column == 0 && !caret.empty?
        tail  = last + 1 < @buffer.line_count ? @buffer.line_start(last + 1) : @buffer.line_end(last)
        Caret.new(@buffer.line_start(first), tail)
      end
      seat(list, @primary)
      auto_copy
    end

    def place_carets(carets : Array(Caret), primary : Int32 = carets.size - 1) : Nil
      seat(carets, primary)
    end

    def add_caret(head : Int32, anchor : Int32 = head) : Nil
      list = @carets + [Caret.new(anchor, head)]
      seat(list, list.size - 1)
    end

    def collapse : Bool
      return false unless multiple?

      seat([primary_caret], 0)
      true
    end

    def remove_last_caret : Bool
      return false unless multiple?

      list = @carets.dup
      list.delete_at(@primary)
      seat(list, Math.max(@primary - 1, 0))
      true
    end

    def add_next_occurrence : Bool
      lead = primary_caret

      if lead.empty?
        span = word_at(lead.head) || return false
        list = @carets.dup
        list[@primary] = Caret.new(span.begin, span.end)
        seat(list, @primary)
        return true
      end

      found = @buffer.find(@buffer.slice_text(lead.range), lead.stop) || return false
      return false if @carets.any? { |caret| caret.range == found }

      add_caret(found.end, found.begin)
      true
    end

    def skip_occurrence : Bool
      lead = primary_caret
      return false if lead.empty?

      found = @buffer.find(@buffer.slice_text(lead.range), lead.stop) || return false
      return false if @carets.any? { |caret| caret.range == found }

      list = @carets.reject { |caret| caret == lead } + [Caret.new(found.begin, found.end)]
      seat(list, list.size - 1)
      true
    end

    def select_all_occurrences : Bool
      lead = primary_caret.range

      if lead.empty?
        lead = word_at(lead.begin) || return false
      end

      found = @buffer.find_all(@buffer.slice_text(lead))
      return false if found.empty?

      seat(found.map { |range| Caret.new(range.begin, range.end) }, found.index(lead) || 0)
      true
    end

    def start_box(row : Int32, column : Int32) : Nil
      @box = {row, column, row, column}
    end

    def select_box(anchor_row : Int32, anchor_column : Int32, head_row : Int32, head_column : Int32) : Nil
      @box = {anchor_row, anchor_column, head_row, head_column}
      low  = Math.min(anchor_row, head_row)
      high = Math.max(anchor_row, head_row)
      list = (low..high).map do |row|
        Caret.new(@layout.offset_in(row, anchor_column), @layout.offset_in(row, head_column))
      end
      place_carets(list, head_row - low)
    end

    def clear_box : Nil
      @box = nil
    end

    private def step(caret : Caret, delta : Int32, word : Bool, grow : Bool) : Int32
      if !caret.empty? && !grow && !word
        return delta < 0 ? caret.start : caret.stop
      end

      return (caret.head + delta).clamp(0, length) unless word

      word_edge(caret.head, delta)
    end

    private def word_edge(from : Int32, delta : Int32) : Int32
      index = from

      if delta < 0
        while index > 0 && kind_at(index - 1).try(&.space?)
          index -= 1
        end
        while index > 0 && kind_at(index - 1).try(&.word?)
          index -= 1
        end
      else
        total = length
        while index < total && kind_at(index).try(&.space?)
          index += 1
        end
        while index < total && kind_at(index).try(&.word?)
          index += 1
        end
      end

      index
    end

    private def smart_start(head : Int32) : Int32
      row   = @layout.row_of(head)
      start = @layout.row_start(row)
      stop  = @layout.row_end(row)
      first = start
      while first < stop && kind_at(first).try(&.space?)
        first += 1
      end
      head == first ? start : first
    end

    private def move_vertically(rows : Int32, selecting : Bool) : Nil
      last = Math.max(@layout.row_count - 1, 0)
      list = @carets.map do |caret|
        cell = @layout.cell_of(caret.head)
        goal = caret.goal || cell.column
        head = @layout.offset_in((cell.row + rows).clamp(0, last), goal)
        Caret.new(selecting ? caret.anchor : head, head, goal)
      end
      seat(list, @primary)
      auto_copy if selecting && !@dragging
    end

    private def vertical(offset : Int32, rows : Int32) : Int32
      cell = @layout.cell_of(offset)
      @layout.offset_in((cell.row + rows).clamp(0, Math.max(@layout.row_count - 1, 0)), cell.column)
    end

    private def page : Int32
      Math.max(@layout.page_rows, 1)
    end

    private def add_beside(edge : Int32, rows : Int32) : Nil
      target = vertical(edge, rows)
      add_caret(target) unless @layout.row_of(target) == @layout.row_of(edge)
    end

    private def box_step(rows : Int32, columns : Int32) : Nil
      anchor_row, anchor_column, head_row, head_column = @box || begin
        cell = @layout.cell_of(cursor)
        {cell.row, cell.column, cell.row, cell.column}
      end

      head_row    = (head_row + rows).clamp(0, Math.max(@layout.row_count - 1, 0))
      head_column = Math.max(head_column + columns, 0)
      select_box(anchor_row, anchor_column, head_row, head_column)
    end

    private def kind_at(offset : Int32) : ClusterKind?
      @buffer.kind(offset)
    end

    private def word_at(offset : Int32) : Range(Int32, Int32)?
      left  = offset
      right = offset
      total = length

      while left > 0 && kind_at(left - 1).try(&.word?)
        left -= 1
      end
      while right < total && kind_at(right).try(&.word?)
        right += 1
      end

      left < right ? left...right : nil
    end
  end
end
