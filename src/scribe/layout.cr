# src/scribe/layout.cr
module Scribe
  module Layout
    abstract def row_count : Int32
    abstract def row_of(offset : Int32) : Int32
    abstract def row_start(row : Int32) : Int32
    abstract def row_end(row : Int32) : Int32
    abstract def cell_of(offset : Int32) : Cell
    abstract def offset_in(row : Int32, column : Int32) : Int32
    abstract def page_rows : Int32
  end

  class LineLayout
    include Layout

    property folds : Folds?

    def initialize(@buffer : Buffer, @folds : Folds? = nil)
    end

    def row_count : Int32
      folded? ? visible.size : @buffer.line_count
    end

    def row_of(offset : Int32) : Int32
      line = @buffer.position(offset).line
      return line unless folded?

      shown = visible
      found = shown.bsearch_index { |candidate| candidate >= line }
      found ? (shown[found] == line ? found : Math.max(found - 1, 0)) : shown.size - 1
    end

    def row_start(row : Int32) : Int32
      @buffer.line_start(line_of(row))
    end

    def row_end(row : Int32) : Int32
      @buffer.line_end(line_of(row))
    end

    def cell_of(offset : Int32) : Cell
      found = @buffer.position(offset)
      Cell.new(@buffer.width(found.line, 0, found.column), row_of(offset))
    end

    def offset_in(row : Int32, column : Int32) : Int32
      line = line_of(row)
      @buffer.line_start(line) + @buffer.index(line, column)
    end

    def page_rows : Int32
      1
    end

    private def line_of(row : Int32) : Int32
      return row.clamp(0, @buffer.line_count - 1) unless folded?

      shown = visible
      shown[row.clamp(0, shown.size - 1)]
    end

    private def folded? : Bool
      found = @folds
      !found.nil? && !found.empty?
    end

    private def visible : Array(Int32)
      @folds.try(&.rows) || (0...@buffer.line_count).to_a
    end
  end
end
