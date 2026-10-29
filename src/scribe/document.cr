# src/scribe/document.cr
module Scribe
  class Document
    getter graphemes   : Graphemes
    getter buffer      : Buffer
    getter history     : History
    getter max_length  : Int32?
    getter path        : String?
    getter marks       : Array(Mark)
    getter decorations : Array(Decoration)
    getter annotations : Array(Annotation)
    getter view        : View { View.new(self, layout: @seed_layout, copy_on_select: @seed_copy_on_select) }

    property filter       : Filter
    property clipboard    : Clipboard
    property selection_clipboard : Clipboard?
    property line_ending  : LineEnding
    property indent       : String
    property comment      : String?
    property tab_size     : Int32
    property? auto_indent : Bool
    property? auto_close  : Bool
    property? copyable    : Bool
    property? final_newline : Bool
    property? read_only   : Bool

    def views : Array(View)
      view
      @views
    end

    delegate carets, primary, primary_caret, cursor, box, layout, dragging?, copy_on_select?,
      selection, selection?, selected_text, selected_texts, selected?, multiple?, run, move, move_carets,
      select_range, select_all, select_word, select_line, place_carets, add_caret, collapse,
      remove_last_caret, add_next_occurrence, skip_occurrence, select_all_occurrences, start_box,
      select_box, clear_box, insert, paste, auto_copy, find, replace_match, replace_all, brackets,
      to: view

    def layout=(value : Layout) : Layout
      view.layout = value
    end

    def dragging=(value : Bool) : Bool
      view.dragging = value
    end

    def copy_on_select=(value : Bool) : Bool
      view.copy_on_select = value
    end

    @listeners     : Array(Listener)
    @depth         : Int32
    @batch         : Array(Change)
    @batch_before  : Array(Caret)
    @batch_primary : Int32
    @batch_moved   : Bool
    @batch_view    : View?
    @acting        : View?
    @seed_layout   : Layout?
    @seed_copy_on_select : Bool

    def initialize(@graphemes : Graphemes, text : String = "", *,
                   @filter         : Filter    = SingleLine.new,
                   @clipboard      : Clipboard = Register.new,
                   @selection_clipboard : Clipboard? = nil,
                   layout          : Layout?   = nil,
                   @max_length     : Int32?    = nil,
                   @indent         : String    = "  ",
                   @comment        : String?   = nil,
                   @tab_size       : Int32     = 4,
                   @auto_indent    : Bool      = false,
                   @auto_close     : Bool      = false,
                   @copyable       : Bool      = true,
                   @final_newline  : Bool      = false,
                   copy_on_select  : Bool      = false,
                   @read_only      : Bool      = false)
      @line_ending = LineEnding.detect(text)
      prepared     = @filter.filter(LineEnding.normalize(text))
      if (max = @max_length) && (marks = @graphemes.boundaries(prepared)).size - 1 > max
        prepared = prepared.byte_slice(0, marks[max])
      end

      buffer         = Buffer.new(@graphemes, prepared)
      @buffer        = buffer
      @history       = History.new(@graphemes)
      @path          = nil
      @marks         = [] of Mark
      @decorations   = [] of Decoration
      @annotations   = [] of Annotation
      @listeners     = [] of Listener
      @depth         = 0
      @batch         = [] of Change
      @batch_before  = [] of Caret
      @batch_primary = 0
      @batch_moved   = false
      @batch_view    = nil
      @acting        = nil
      @views         = [] of View
      @seed_layout   = layout
      @seed_copy_on_select = copy_on_select
      buffer.on_change { |change| applied(change) }
    end

    protected def attach(view : View) : Nil
      @views << view
    end

    protected def detach(view : View) : Nil
      @views.delete(view)
    end

    protected def stirred(view : View) : Nil
      if @depth > 0
        @batch_moved = true
      else
        @listeners.dup.each(&.moved(view))
      end
    end

    def self.open(graphemes : Graphemes, path : String, **options) : Document
      buffer = Buffer.map(graphemes, path)
      found  = new(graphemes, "", **options)
      found.adopt(buffer, LineEnding.detect_in(buffer), path)
      found
    end

    protected def adopt(buffer : Buffer, ending : LineEnding, path : String? = nil) : Nil
      @buffer      = buffer
      @line_ending = ending
      @path        = path
      views.each(&.rebind(buffer))
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
      String.build(export_size) do |io|
        each_export_chunk { |chunk| io.write(chunk) }
      end
    end

    def save(path : String? = nil) : Nil
      target = path || @path || raise ArgumentError.new("save needs a path for a document without one")
      size   = export_size
      raise Mapped::Error.new("exported text is larger than this build can map") if size > Int32::MAX

      temporary = File.tempfile(".#{File.basename(target)}", ".tmp", dir: File.dirname(target))
      temp_path = temporary.path
      begin
        temporary.chmod(File.info(target).permissions) if File.exists?(target)
        temporary.truncate(size)
        temporary.close
        Mapped.open(temp_path, writable: true) do |mapped|
          bytes  = mapped.bytes
          offset = 0
          each_export_chunk do |chunk|
            chunk.copy_to(bytes[offset, chunk.size])
            offset += chunk.size
          end
        end
        File.rename(temp_path, target)
        @path = target
        mark_saved
      rescue error
        temporary.close unless temporary.closed?
        File.delete(temp_path) if File.exists?(temp_path)
        raise error
      end
    end

    private def export_size : Int64
      breaks = @buffer.line_count.to_i64 - 1
      size   = @buffer.bytesize.to_i64 + breaks * (@line_ending.sequence.bytesize - 1)
      final_break? ? size + @line_ending.sequence.bytesize : size
    end

    private def each_export_chunk(& : Bytes -> Nil) : Nil
      ending = @line_ending.sequence.to_slice
      last   = @buffer.line_count - 1
      @buffer.line_count.times do |index|
        @buffer.line(index).each_chunk { |chunk, _start| yield chunk }
        yield ending if index < last
      end
      yield ending if final_break?
    end

    private def final_break? : Bool
      @final_newline && !@buffer.empty? && !(@buffer.line_count > 1 && @buffer.line(@buffer.line_count - 1).empty?)
    end

    def length : Int32
      @buffer.size
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

      seat = self.view

      if text == @buffer.text
        seat.seat([Caret.at(length)], 0)
        return self.value
      end

      before  = seat.carets
      primary = seat.primary
      @acting = seat
      change  = @buffer.replace(0...length, text)
      seat.seat([Caret.at(length)], 0)
      record(History::Kind::Other, [change], before, primary, seat)
      @acting = nil
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

    def decorate(source : String, entries : Array(Decoration)) : Nil
      @decorations.reject!(&.source.==(source))
      entries.each do |entry|
        entry.source = source
        @decorations << entry
      end
      @decorations.sort_by!(&.start)
      @listeners.dup.each(&.decorated(self))
    end

    def annotate(source : String, entries : Array(Annotation)) : Nil
      @annotations.reject!(&.source.==(source))
      entries.each do |entry|
        entry.source = source
        @annotations << entry
      end
      @annotations.sort_by!(&.offset)
      @listeners.dup.each(&.annotated(self))
    end

    def annotations(from : Int32, to : Int32) : Array(Annotation)
      @annotations.select { |entry| from <= entry.offset <= to }
    end

    def annotations_at(offset : Int32) : Array(Annotation)
      @annotations.select(&.offset.==(offset))
    end

    def annotations_on(line : Int32) : Array(Annotation)
      return [] of Annotation unless 0 <= line < @buffer.line_count

      first = @buffer.line_start(line)
      last  = @buffer.line_end(line)
      @annotations.select { |entry| first <= entry.offset <= last }
    end

    def decorations(from : Int32, to : Int32) : Array(Decoration)
      @decorations.select(&.overlaps?(from, to))
    end

    def decorations_at(offset : Int32) : Array(Decoration)
      @decorations.select(&.covers?(offset))
    end

    def revision : Int32
      @buffer.revision
    end

    def map(offset : Int32, from : Int32, gravity : Gravity = Gravity::Left) : Int32?
      changes = @buffer.changes_since(from) || return nil
      spot    = Mark.new(offset.clamp(0, length), gravity)
      changes.each { |change| spot.follow(change) }
      spot.offset
    end

    def map(range : Range(Int32, Int32), from : Int32) : Range(Int32, Int32)?
      start = map(range.begin, from, Gravity::Right) || return nil
      stop  = map(Math.max(range.end, range.begin), from, Gravity::Left) || return nil
      start...Math.max(stop, start)
    end

    def transaction(& : -> T) : T forall T
      outer = @depth == 0
      if outer
        @batch         = [] of Change
        @batch_before  = view.carets
        @batch_primary = view.primary
        @batch_moved   = false
        @batch_view    = nil
      end

      @depth += 1
      begin
        yield
      ensure
        @depth -= 1
        finish if outer
      end
    end

    def undo(view : View = self.view) : Bool
      return false if @depth > 0

      @acting = view
      step, applied = @history.undo(@buffer) || begin
        @acting = nil
        return false
      end
      view.seat(step.before, step.before_primary)
      @acting = nil
      changed(applied)
      true
    end

    def redo(view : View = self.view) : Bool
      return false if @depth > 0

      @acting = view
      step, applied = @history.redo(@buffer) || begin
        @acting = nil
        return false
      end
      view.seat(step.after, step.after_primary)
      @acting = nil
      changed(applied)
      true
    end

    def replace_ranges(edits : Array(Edit), kind : History::Kind = History::Kind::Other,
                       after : Array(Caret)? = nil, *, view : View = self.view) : Bool
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

      before  = view.carets
      primary = view.primary
      sizes   = kept.map { |edit| {edit.range, count(edit.text)} }
      applied = [] of Change
      @acting = view
      kept.reverse_each { |edit| applied << @buffer.replace(edit.range, edit.text) }

      after ||= before.map { |caret| Caret.new(carry(caret.anchor, sizes), carry(caret.head, sizes)) }

      view.seat(after, primary)
      record(kind, applied, before, primary, view)
      @acting = nil
      changed(applied)
      true
    end

    protected def apply(view : View, kind : History::Kind, & : Caret, Int32 -> Stroke?) : Bool
      return false if @read_only

      before  = view.carets
      primary = view.primary
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
      @acting = view
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

      view.seat(after, primary)
      record(kind, applied, before, primary, view)
      @acting = nil
      changed(applied)
      true
    end

    private def record(kind : History::Kind, changes : Array(Change), before : Array(Caret),
                       primary : Int32, view : View) : Nil
      if @depth > 0
        @batch.concat(changes)
        @batch_view ||= view
      else
        @history.record(kind, changes, before, primary, view.carets, view.primary)
      end
    end

    private def changed(changes : Array(Change)) : Nil
      @listeners.dup.each(&.edited(self, changes)) if @depth == 0
    end

    private def finish : Nil
      batch       = @batch
      acting      = @batch_view || self.view
      @batch      = [] of Change
      @batch_view = nil
      @history.record(History::Kind::Other, batch, @batch_before, @batch_primary, acting.carets, acting.primary) unless batch.empty?
      @listeners.dup.each(&.moved(acting)) if @batch_moved
      @batch_moved = false
      @listeners.dup.each(&.edited(self, batch)) unless batch.empty?
    end

    private def applied(change : Change) : Nil
      @marks.each(&.follow(change))
      @decorations.each(&.follow(change))
      @annotations.each(&.follow(change))
      acting = @acting
      @views.each { |view| view.follow(change) unless acting && view.same?(acting) }
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

    protected def prepare(text : String) : String
      @filter.filter(LineEnding.normalize(text))
    end

    protected def count(text : String) : Int32
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
