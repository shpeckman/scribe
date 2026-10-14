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
      getter kind            : Kind
      getter changes         : Array(Change)
      getter before          : Array(Caret)
      getter before_primary  : Int32
      property after         : Array(Caret)
      property after_primary : Int32
      property at            : Time::Instant

      def initialize(@kind : Kind, @changes : Array(Change), @before : Array(Caret), @before_primary : Int32,
                     @after : Array(Caret), @after_primary : Int32, @at : Time::Instant)
      end
    end

    property limit  : Int32
    property window : Time::Span

    @undo : Array(Step)
    @redo : Array(Step)

    def initialize(@graphemes : Graphemes, @limit : Int32 = LIMIT, @window : Time::Span = WINDOW)
      @undo = [] of Step
      @redo = [] of Step
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
    end

    def record(kind : Kind, changes : Array(Change), before : Array(Caret), before_primary : Int32,
               after : Array(Caret), after_primary : Int32) : Nil
      return if changes.empty?

      now = Time.instant
      @redo.clear

      if (last = @undo.last?) && joins?(last, kind, changes, before, now)
        last.changes.concat(changes)
        last.after         = after
        last.after_primary = after_primary
        last.at            = now
        return
      end

      @undo << Step.new(kind, changes, before, before_primary, after, after_primary, now)
      @undo.shift if @undo.size > @limit
    end

    def undo(buffer : Buffer) : Step?
      step = @undo.pop? || return
      step.changes.reverse_each(&.undo(buffer))
      @redo << step
      step
    end

    def redo(buffer : Buffer) : Step?
      step = @redo.pop? || return
      step.changes.each(&.redo(buffer))
      @undo << step
      step
    end

    private def joins?(last : Step, kind : Kind, changes : Array(Change), before : Array(Caret), now : Time::Instant) : Bool
      return false if kind.other? || last.kind != kind
      return false if now - last.at > @window
      return false unless last.after == before
      return true unless kind.typing?

      previous = last.changes.last?.try(&.inserted.last?) || return true
      upcoming = changes.first?.try(&.inserted.first?) || return true
      !(blank?(previous) && !blank?(upcoming))
    end

    private def blank?(cluster : String) : Bool
      @graphemes.kind(cluster).space?
    end
  end
end
