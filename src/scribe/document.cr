# src/scribe/document.cr
module Scribe
  class Document
    alias Box = {Int32, Int32, Int32, Int32}

    record Stroke, range : Range(Int32, Int32), text : String, anchor : Int32? = nil, head : Int32? = nil

    getter graphemes   : Graphemes
    getter buffer      : Buffer
    getter history     : History
    getter carets      : Array(Caret)
    getter primary     : Int32
    getter max_length  : Int32?
    getter box         : Box?
    getter marks       : Array(Mark)

    property filter          : Filter
    property clipboard       : Clipboard
    property layout          : Layout
    property line_ending     : LineEnding
    property indent          : String
    property comment         : String?
    property tab_size        : Int32
    property? auto_indent    : Bool
    property? auto_close     : Bool
    property? copyable       : Bool
    property? copy_on_select : Bool
    property? dragging       : Bool
    property? read_only      : Bool

    @listeners     : Array(Listener)
    @depth         : Int32
    @batch         : Array(Change)
    @batch_before  : Array(Caret)
    @batch_primary : Int32
    @batch_moved   : Bool

    def initialize(@graphemes : Graphemes, text : String = "", *,
                   @filter         : Filter    = SingleLine.new,
                   @clipboard      : Clipboard = Register.new,
                   layout          : Layout?   = nil,
                   @max_length     : Int32?    = nil,
                   @indent         : String    = "  ",
                   @comment        : String?   = nil,
                   @tab_size       : Int32     = 4,
                   @auto_indent    : Bool      = false,
                   @auto_close     : Bool      = false,
                   @copyable       : Bool      = true,
                   @copy_on_select : Bool      = false,
                   @read_only      : Bool      = false)
      @line_ending = LineEnding.detect(text)
      prepared     = @filter.filter(LineEnding.normalize(text))
      if (max = @max_length) && (marks = @graphemes.boundaries(prepared)).size - 1 > max
        prepared = prepared.byte_slice(0, marks[max])
      end

      buffer         = Buffer.new(@graphemes, prepared)
      @buffer        = buffer
      @carets        = [Caret.at(buffer.size)]
      @primary       = 0
      @history       = History.new(@graphemes)
      @box           = nil
      @marks         = [] of Mark
      @dragging      = false
      @listeners     = [] of Listener
      @depth         = 0
      @batch         = [] of Change
      @batch_before  = @carets
      @batch_primary = 0
      @batch_moved   = false
      @layout        = layout || LineLayout.new(buffer)
      buffer.on_change { |change| applied(change) }
    end

    def listen(listener : Listener) : Proc(Nil)
      @listeners << listener
      -> { @listeners.delete(listener); nil }
    end

    def value : String
      @buffer.text
    end

    def export : String
      @line_ending.lf? ? value : value.gsub('\n', @line_ending.sequence)
    end

    def length : Int32
      @buffer.size
    end

    def primary_caret : Caret
      @carets[@primary]
    end

    def cursor : Int32
      primary_caret.head
    end

    def selection? : Bool
      !primary_caret.empty?
    end

    def selection : Range(Int32, Int32)
      primary_caret.range
    end

    def selected_text : String
      @buffer.slice_text(selection)
    end

    def selected_texts : Array(String)
      @carets.reject(&.empty?).map { |caret| @buffer.slice_text(caret.range) }
    end

    def selected?(offset : Int32) : Bool
      index = @carets.bsearch_index { |caret| caret.stop > offset } || return false
      @carets.unsafe_fetch(index).includes?(offset)
    end

    def multiple? : Bool
      @carets.size > 1
    end

    def modified? : Bool
      @history.modified?
    end

    def mark_saved : Nil
      @history.mark_saved
    end

    def value=(value : String) : String
      @line_ending = LineEnding.detect(value) if value.includes?('\n') || value.includes?('\r')
      text = limit(prepare(value))

      if text == @buffer.text
        seat([Caret.at(length)], 0)
        return self.value
      end

      before  = @carets
      primary = @primary
      change  = @buffer.replace(0...length, text)
      seat([Caret.at(length)], 0)
      record(History::Kind::Other, [change], before, primary)
      changed([change])
      self.value
    end

    def max_length=(value : Int32?) : Int32?
      return value if @max_length == value

      @max_length = value
      self.value = self.value if value && length > value
      value
    end

    def clear : Nil
      self.value = ""
    end

    def mark(offset : Int32, gravity : Gravity = Gravity::Left) : Mark
      found = Mark.new(offset.clamp(0, length), gravity)
      @marks << found
      found
    end

    def unmark(mark : Mark) : Nil
      @marks.delete(mark)
    end

    def transaction(& : -> T) : T forall T
      outer = @depth == 0
      if outer
        @batch         = [] of Change
        @batch_before  = @carets
        @batch_primary = @primary
        @batch_moved   = false
      end

      @depth += 1
      begin
        yield
      ensure
        @depth -= 1
        finish if outer
      end
    end

    def run(command : Command, selecting : Bool = false) : Bool
      return false if @read_only && command.edits?

      case command
      in .left?                   then move_carets(selecting) { |caret| step(caret, -1, false, selecting) }
      in .right?                  then move_carets(selecting) { |caret| step(caret, 1, false, selecting) }
      in .word_left?              then move_carets(selecting) { |caret| step(caret, -1, true, selecting) }
      in .word_right?             then move_carets(selecting) { |caret| step(caret, 1, true, selecting) }
      in .row_start?              then move_carets(selecting) { |caret| @layout.row_start(@layout.row_of(caret.head)) }
      in .smart_row_start?        then move_carets(selecting) { |caret| smart_start(caret.head) }
      in .row_end?                then move_carets(selecting) { |caret| @layout.row_end(@layout.row_of(caret.head)) }
      in .up?                     then move_vertically(-1, selecting)
      in .down?                   then move_vertically(1, selecting)
      in .page_up?                then move_vertically(-page, selecting)
      in .page_down?              then move_vertically(page, selecting)
      in .document_start?         then move_carets(selecting) { |_caret| 0 }
      in .document_end?           then move_carets(selecting) { |_caret| length }
      in .select_all?             then select_all
      in .select_word?            then select_word
      in .select_line?            then select_line
      in .collapse?               then return collapse
      in .add_next_occurrence?    then return add_next_occurrence
      in .skip_occurrence?        then return skip_occurrence
      in .select_all_occurrences? then return select_all_occurrences
      in .add_caret_above?        then add_beside(@carets.first.head, -1)
      in .add_caret_below?        then add_beside(@carets.last.head, 1)
      in .remove_last_caret?      then return remove_last_caret
      in .box_up?                 then box_step(-1, 0)
      in .box_down?               then box_step(1, 0)
      in .box_left?               then box_step(0, -1)
      in .box_right?              then box_step(0, 1)
      in .delete_backward?        then delete_backward
      in .delete_forward?         then delete_forward
      in .delete_word_backward?   then delete_word(-1)
      in .delete_word_forward?    then delete_word(1)
      in .delete_to_row_start?    then delete_to_row(start: true)
      in .delete_to_row_end?      then delete_to_row(start: false)
      in .new_line?               then return new_line
      in .tab?                    then tab
      in .indent?                 then return indent_lines
      in .outdent?                then return outdent_lines
      in .toggle_comment?         then return toggle_comment
      in .move_lines_up?          then return move_lines(-1)
      in .move_lines_down?        then return move_lines(1)
      in .duplicate_lines?        then return duplicate_lines
      in .delete_lines?           then return delete_lines
      in .copy?                   then copy
      in .cut?                    then cut
      in .paste?                  then paste_clipboard
      in .undo?                   then return undo
      in .redo?                   then return redo
      end
      true
    end

    def undo : Bool
      return false if @depth > 0

      step, applied = @history.undo(@buffer) || return false
      seat(step.before, step.before_primary)
      changed(applied)
      true
    end

    def redo : Bool
      return false if @depth > 0

      step, applied = @history.redo(@buffer) || return false
      seat(step.after, step.after_primary)
      changed(applied)
      true
    end

    def replace_ranges(edits : Array(Edit), kind : History::Kind = History::Kind::Other,
                       after : Array(Caret)? = nil) : Bool
      ordered = edits.sort_by { |edit| {edit.range.begin, edit.range.end} }
      floor   = 0
      kept    = [] of Edit

      ordered.each do |edit|
        from  = edit.range.begin.clamp(floor, length)
        to    = edit.range.end.clamp(from, length)
        floor = to
        kept << Edit.new(from...to, edit.text) unless from == to && edit.text.empty?
      end

      return false if kept.empty?

      before  = @carets
      primary = @primary
      sizes   = kept.map { |edit| {edit.range, count(edit.text)} }
      applied = [] of Change
      kept.reverse_each { |edit| applied << @buffer.replace(edit.range, edit.text) }

      after ||= before.map { |caret| Caret.new(carry(caret.anchor, sizes), carry(caret.head, sizes)) }

      seat(after, primary)
      record(kind, applied, before, primary)
      changed(applied)
      true
    end

    private def apply(kind : History::Kind, & : Caret, Int32 -> Stroke?) : Bool
      return false if @read_only

      before  = @carets
      primary = @primary
      strokes = Array(Stroke?).new(before.size)
      before.each_with_index { |caret, index| strokes << yield(caret, index) }

      room  = @max_length.try { |max| max - length + strokes.sum { |stroke| stroke ? stroke.range.size : 0 } }
      floor = 0

      strokes.map! do |stroke|
        next nil unless stroke

        from  = Math.max(stroke.range.begin, floor)
        to    = Math.max(stroke.range.end, from)
        floor = to
        text  = stroke.text

        if left = room
          size = count(text)
          if size > left
            text = take(text, Math.max(left, 0))
            size = Math.max(left, 0)
          end
          room = left - size
        end

        from == to && text.empty? ? nil : stroke.copy_with(range: from...to, text: text)
      end

      return false if strokes.all?(&.nil?)

      changes = Array(Change?).new(strokes.size, nil)
      applied = [] of Change
      (strokes.size - 1).downto(0) do |index|
        if stroke = strokes[index]
          change = @buffer.replace(stroke.range, stroke.text)
          changes[index] = change
          applied << change
        end
      end

      delta = 0
      after = before.map_with_index do |caret, index|
        stroke = strokes[index]
        change = changes[index]
        if stroke && change
          base   = stroke.range.begin + delta
          anchor = stroke.anchor
          head   = stroke.head
          placed = anchor && head ? Caret.new(base + anchor, base + head) : Caret.at(change.from + change.inserted_size + delta)
          delta += change.delta
          placed
        else
          caret.shift(delta)
        end
      end

      seat(after, primary)
      record(kind, applied, before, primary)
      changed(applied)
      true
    end

    private def seat(list : Array(Caret), lead : Int32) : Nil
      list   = [Caret.at(length)] if list.empty?
      limit  = length
      leader = list[lead.clamp(0, list.size - 1)].clamp(limit)
      sorted = list.map(&.clamp(limit)).sort_by! { |caret| {caret.start, caret.stop} }
      merged = [] of Caret

      sorted.each do |caret|
        last = merged.last?
        if last && (caret.start < last.stop || caret.start == last.start)
          merged[-1] = last.union(caret)
        else
          merged << caret
        end
      end

      @carets  = merged
      @primary = merged.index { |caret| caret.start <= leader.head <= caret.stop } || merged.size - 1

      if @depth > 0
        @batch_moved = true
      else
        @listeners.dup.each(&.moved(self))
      end
    end

    private def record(kind : History::Kind, changes : Array(Change), before : Array(Caret), primary : Int32) : Nil
      if @depth > 0
        @batch.concat(changes)
      else
        @history.record(kind, changes, before, primary, @carets, @primary)
      end
    end

    private def changed(changes : Array(Change)) : Nil
      @listeners.dup.each(&.edited(self, changes)) if @depth == 0
    end

    private def finish : Nil
      batch  = @batch
      @batch = [] of Change
      @history.record(History::Kind::Other, batch, @batch_before, @batch_primary, @carets, @primary) unless batch.empty?
      @listeners.dup.each(&.moved(self)) if @batch_moved
      @listeners.dup.each(&.edited(self, batch)) unless batch.empty?
    end

    private def applied(change : Change) : Nil
      @marks.each(&.follow(change))
      @listeners.dup.each(&.applied(self, change))
    end

    private def carry(offset : Int32, sizes : Array({Range(Int32, Int32), Int32})) : Int32
      delta = 0
      sizes.each do |(range, inserted)|
        return range.begin + delta + inserted if range.begin < offset < range.end
        break if offset < range.end || (offset == range.begin && range.size > 0)

        delta += inserted - range.size
      end
      offset + delta
    end

    private def prepare(text : String) : String
      @filter.filter(LineEnding.normalize(text))
    end

    private def count(text : String) : Int32
      text.empty? ? 0 : @graphemes.boundaries(text).size - 1
    end

    private def take(text : String, clusters : Int32) : String
      text.byte_slice(0, @graphemes.boundaries(text)[clusters])
    end

    private def limit(text : String) : String
      max = @max_length
      max && count(text) > max ? take(text, max) : text
    end
  end
end
