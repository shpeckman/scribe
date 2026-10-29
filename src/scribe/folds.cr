# src/scribe/folds.cr
module Scribe
  class Folds
    class Fold
      getter? collapsed : Bool

      def initialize(@head : Mark, @tail : Mark, @collapsed : Bool = true)
      end

      def head : Int32
        @head.offset
      end

      def tail : Int32
        Math.max(@tail.offset, @head.offset)
      end

      protected def collapsed=(value : Bool) : Bool
        @collapsed = value
      end

      protected def marks : {Mark, Mark}
        {@head, @tail}
      end
    end

    getter document : Document
    getter folds    : Array(Fold)

    def initialize(@document : Document)
      @folds = [] of Fold
    end

    def empty? : Bool
      @folds.empty?
    end

    def size : Int32
      @folds.size
    end

    def fold(first : Int32, last : Int32, collapsed : Bool = true) : Fold?
      return nil if last <= first || first < 0 || first >= buffer.line_count

      last  = Math.min(last, buffer.line_count - 1)
      found = at(first)
      return found if found

      entry = Fold.new(@document.mark(buffer.line_end(first), Gravity::Left),
        @document.mark(buffer.line_end(last), Gravity::Right), collapsed)
      @folds << entry
      sort
      notify
      entry
    end

    def unfold(line : Int32) : Bool
      entry = at(line) || return false

      drop(entry)
      notify
      true
    end

    def collapse(line : Int32) : Bool
      entry = at(line) || return false
      return false if entry.collapsed?

      entry.collapsed = true
      notify
      true
    end

    def expand(line : Int32) : Bool
      entry = at(line) || return false
      return false unless entry.collapsed?

      entry.collapsed = false
      notify
      true
    end

    def toggle(line : Int32) : Bool
      entry = at(line) || return false

      entry.collapsed = !entry.collapsed?
      notify
      true
    end

    def at(line : Int32) : Fold?
      @folds.find { |entry| buffer.position(entry.head).line == line }
    end

    def collapsed?(line : Int32) : Bool
      at(line).try(&.collapsed?) || false
    end

    def hidden?(line : Int32) : Bool
      @folds.any? do |entry|
        next false unless entry.collapsed?

        first = buffer.position(entry.head).line
        last  = buffer.position(entry.tail).line
        first < line <= last
      end
    end

    def rows : Array(Int32)
      (0...buffer.line_count).reject { |line| hidden?(line) }
    end

    def clear : Nil
      return if @folds.empty?

      @folds.dup.each { |entry| drop(entry) }
      notify
    end

    def replace(entries : Array({Int32, Int32})) : Nil
      @folds.dup.each { |entry| drop(entry) }
      entries.each { |(first, last)| fold(first, last) }
      notify
    end

    private def drop(entry : Fold) : Nil
      head, tail = entry.marks
      @document.unmark(head)
      @document.unmark(tail)
      @folds.delete(entry)
    end

    private def sort : Nil
      @folds.sort_by!(&.head)
    end

    private def notify : Nil
      sort
    end

    private def buffer : Buffer
      @document.buffer
    end
  end
end
