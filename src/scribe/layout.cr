# src/scribe/layout.cr
module Scribe
  module Layout
    abstract def row_count : Int32
    abstract def row_of(offset : Int32) : Int32
    abstract def row_start(row : Int32) : Int32
    abstract def row_end(row : Int32) : Int32
    abstract def position_of(offset : Int32) : {Int32, Int32}
    abstract def offset_in(row : Int32, column : Int32) : Int32
    abstract def page_rows : Int32
  end

  class LineLayout
    include Layout

    def initialize(@buffer : Buffer, @graphemes : Graphemes)
    end

    def row_count : Int32
      @buffer.line_count
    end

    def row_of(offset : Int32) : Int32
      @buffer.position(offset)[0]
    end

    def row_start(row : Int32) : Int32
      @buffer.line_start(clamp(row))
    end

    def row_end(row : Int32) : Int32
      @buffer.line_end(clamp(row))
    end

    def position_of(offset : Int32) : {Int32, Int32}
      line, column = @buffer.position(offset)
      cells = @buffer.line(line)
      width = 0
      column.times { |index| width += @graphemes.width(cells.unsafe_fetch(index)) }
      {width, line}
    end

    def offset_in(row : Int32, column : Int32) : Int32
      line  = clamp(row)
      cells = @buffer.line(line)
      edge  = 0
      cells.each_with_index do |cluster, index|
        extent = @graphemes.width(cluster)
        return @buffer.line_start(line) + index if column < edge + extent
        edge += extent
      end
      @buffer.line_end(line)
    end

    def page_rows : Int32
      1
    end

    private def clamp(row : Int32) : Int32
      row.clamp(0, @buffer.line_count - 1)
    end
  end
end
