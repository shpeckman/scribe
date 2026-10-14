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

    def initialize(@buffer : Buffer)
    end

    def row_count : Int32
      @buffer.line_count
    end

    def row_of(offset : Int32) : Int32
      @buffer.position(offset).line
    end

    def row_start(row : Int32) : Int32
      @buffer.line_start(clamp(row))
    end

    def row_end(row : Int32) : Int32
      @buffer.line_end(clamp(row))
    end

    def cell_of(offset : Int32) : Cell
      found = @buffer.position(offset)
      Cell.new(@buffer.width(found.line, 0, found.column), found.line)
    end

    def offset_in(row : Int32, column : Int32) : Int32
      line = clamp(row)
      @buffer.line_start(line) + @buffer.index(line, column)
    end

    def page_rows : Int32
      1
    end

    private def clamp(row : Int32) : Int32
      row.clamp(0, @buffer.line_count - 1)
    end
  end
end
