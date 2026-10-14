# src/scribe/history.cr
module Scribe
  class History
    LIMIT  = 500
    WINDOW = 1.second

    enum Kind
      Typing
      Deleting
      Other
    end

    class Step
      getter id              : Int32
      getter kind            : Kind
      getter changes         : Array(Change)
      getter before          : Array(Caret)
      getter before_primary  : Int32
      property after         : Array(Caret)
      property after_primary : Int32
      property at            : Time::Instant

      def initialize(@id : Int32, @kind : Kind, @changes : Array(Change), @before : Array(Caret), @before_primary : Int32,
                     @after : Array(Caret), @after_primary : Int32, @at : Time::Instant)
      end
    end

    property limit  : Int32
    property window : Time::Span

    @undo   : Array(Step)
    @redo   : Array(Step)
    @serial : Int32
    @saved  : Int32
    @sealed : Bool

    def initialize(@graphemes : Graphemes, @limit : Int32 = LIMIT, @window : Time::Span = WINDOW,
                   @clock : Proc(Time::Instant) = -> { Time.instant })
      @undo   = [] of Step
      @redo   = [] of Step
      @serial = 0
      @saved  = -1
      @sealed = false
    end

    def can_undo? : Bool
      !@undo.empty?
    end

    def can_redo? : Bool
      !@redo.empty?
    end

    def clear : Nil
      @undo.clear
      @redo.clear
      @saved = -1
    end

    def mark_saved : Nil
      @saved  = top
      @sealed = true
    end

    def modified? : Bool
      top != @saved
    end

    def record(kind : Kind, changes : Array(Change), before : Array(Caret), before_primary : Int32,
               after : Array(Caret), after_primary : Int32) : Nil
      return if changes.empty?

      now = @clock.call
      @redo.clear

      if !@sealed && (last = @undo.last?) && joins?(last, kind, changes, before, now)
        last.changes.concat(changes)
        last.after         = after
        last.after_primary = after_primary
        last.at            = now
        return
      end

      @sealed  = false
      @serial += 1
      @undo << Step.new(@serial, kind, changes, before, before_primary, after, after_primary, now)
      @undo.shift if @undo.size > @limit
    end

    def undo(buffer : Buffer) : {Step, Array(Change)}?
      step    = @undo.pop? || return
      applied = step.changes.reverse.map(&.undo(buffer))
      @redo << step
      @sealed = true
      {step, applied}
    end

    def redo(buffer : Buffer) : {Step, Array(Change)}?
      step    = @redo.pop? || return
      applied = step.changes.map(&.redo(buffer))
      @undo << step
      @sealed = true
      {step, applied}
    end

    private def top : Int32
      @undo.last?.try(&.id) || -1
    end

    private def joins?(last : Step, kind : Kind, changes : Array(Change), before : Array(Caret), now : Time::Instant) : Bool
      return false if kind.other? || last.kind != kind
      return false if now - last.at > @window
      return false unless last.after == before
      return true unless kind.typing?

      previous = last.changes.last?.try(&.inserted) || return true
      upcoming = changes.first?.try(&.inserted) || return true
      return true if previous.empty? || upcoming.empty?

      !(blank?(previous, last: true) && !blank?(upcoming, last: false))
    end

    private def blank?(text : String, last : Bool) : Bool
      marks = @graphemes.boundaries(text)
      start = last ? marks[-2] : 0
      stop  = last ? marks[-1] : marks[1]
      @graphemes.kind(text.to_slice[start, stop - start]).space?
    end
  end
end
