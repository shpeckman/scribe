# src/scribe/view.cr
module Scribe
  class View
    alias Box = {Int32, Int32, Int32, Int32}

    getter document : Document
    getter buffer   : Buffer
    getter carets   : Array(Caret)
    getter primary  : Int32
    getter box      : Box?

    property layout          : Layout
    property macros          : MacroLog?
    property? dragging       : Bool
    property? copy_on_select : Bool

    @graphemes : Graphemes
    @folds     : Folds?

    def initialize(@document : Document, *, layout : Layout? = nil, @copy_on_select : Bool = false)
      @buffer    = @document.buffer
      @graphemes = @document.graphemes
      @carets    = [Caret.at(@buffer.size)]
      @primary   = 0
      @box       = nil
      @dragging  = false
      @folds     = nil
      @layout    = layout || LineLayout.new(@buffer)
      @document.attach(self)
    end

    def close : Nil
      @document.detach(self)
    end

    protected def rebind(buffer : Buffer) : Nil
      @buffer = buffer
      @layout = LineLayout.new(buffer, @folds) if @layout.is_a?(LineLayout)
      @carets  = [Caret.at(0)]
      @primary = 0
    end

    def length : Int32
      @buffer.size
    end

    def folds : Folds
      found = @folds
      return found if found

      made    = Folds.new(@document)
      @folds  = made
      @layout.as?(LineLayout).try { |rows| rows.folds = made }
      made
    end

    def folds? : Folds?
      @folds
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

    def undo : Bool
      @document.undo(self)
    end

    def redo : Bool
      @document.redo(self)
    end

    def replace_ranges(edits : Array(Edit), kind : History::Kind = History::Kind::Other,
                       after : Array(Caret)? = nil) : Bool
      @document.replace_ranges(edits, kind, after, view: self)
    end

    def run(command : Command, selecting : Bool = false) : Bool
      return false if @document.read_only? && command.edits?

      @macros.try(&.push(command))

      case command
      in .left?                   then move_carets(selecting) { |caret| step(caret, -1, false, selecting) }
      in .right?                  then move_carets(selecting) { |caret| step(caret, 1, false, selecting) }
      in .word_left?              then move_carets(selecting) { |caret| step(caret, -1, true, selecting) }
      in .word_right?             then move_carets(selecting) { |caret| step(caret, 1, true, selecting) }
      in .subword_left?           then move_carets(selecting) { |caret| subword_edge(caret.head, -1) }
      in .subword_right?          then move_carets(selecting) { |caret| subword_edge(caret.head, 1) }
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
      in .select_inside_brackets? then return select_brackets(false)
      in .select_around_brackets? then return select_brackets(true)
      in .select_inside_quotes?   then return select_quotes(false)
      in .select_around_quotes?   then return select_quotes(true)
      in .collapse?               then return collapse
      in .add_next_occurrence?    then return add_next_occurrence
      in .skip_occurrence?        then return skip_occurrence
      in .select_all_occurrences? then return select_all_occurrences
      in .add_caret_above?        then add_beside(@carets.first.head, -1)
      in .add_caret_below?        then add_beside(@carets.last.head, 1)
      in .add_caret_per_line?     then return add_caret_per_line
      in .remove_last_caret?      then return remove_last_caret
      in .box_up?                 then box_step(-1, 0)
      in .box_down?               then box_step(1, 0)
      in .box_left?               then box_step(0, -1)
      in .box_right?              then box_step(0, 1)
      in .delete_backward?        then delete_backward
      in .delete_forward?         then delete_forward
      in .delete_word_backward?   then delete_word(-1)
      in .delete_word_forward?    then delete_word(1)
      in .delete_subword_backward? then delete_subword(-1)
      in .delete_subword_forward?  then delete_subword(1)
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
      in .sort_lines?             then return sort_lines
      in .reverse_lines?          then return reverse_lines
      in .unique_lines?           then return unique_lines
      in .join_lines?             then return join_lines
      in .trim_trailing_whitespace? then return trim_trailing_whitespace
      in .upper_case?             then return recase(command)
      in .lower_case?             then return recase(command)
      in .title_case?             then return recase(command)
      in .copy?                   then copy
      in .cut?                    then cut
      in .paste?                  then paste_clipboard
      in .undo?                   then return undo
      in .redo?                   then return redo
      end
      true
    end

    protected def seat(list : Array(Caret), lead : Int32) : Nil
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
      @document.stirred(self)
    end

    protected def follow(change : Change) : Nil
      @carets  = @carets.map { |caret| caret.copy_with(anchor: trail(caret.anchor, change), head: trail(caret.head, change), goal: nil) }
      @primary = @primary.clamp(0, @carets.size - 1)
    end

    private def trail(offset : Int32, change : Change) : Int32
      return offset if offset <= change.from

      stop = change.from + change.removed_size
      return change.from + change.inserted_size if offset <= stop

      offset + change.delta
    end

    private def count(text : String) : Int32
      text.empty? ? 0 : @graphemes.boundaries(text).size - 1
    end
  end
end
