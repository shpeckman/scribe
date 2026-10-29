# src/scribe/change.cr
module Scribe
  record Change, from : Int32, removed : String, inserted : String, removed_size : Int32, inserted_size : Int32 do
    def removed_lines : Int32
      @removed.count('\n')
    end

    def inserted_lines : Int32
      @inserted.count('\n')
    end

    def delta : Int32
      @inserted_size - @removed_size
    end

    def start_point(buffer : Buffer, unit : Units) : Point
      buffer.point(@from, unit)
    end

    def old_end_point(buffer : Buffer, unit : Units) : Point
      advance(buffer, start_point(buffer, unit), @removed, unit)
    end

    def new_end_point(buffer : Buffer, unit : Units) : Point
      advance(buffer, start_point(buffer, unit), @inserted, unit)
    end

    def undo(buffer : Buffer) : Change
      buffer.replace(@from...(@from + @inserted_size), @removed)
    end

    def redo(buffer : Buffer) : Change
      buffer.replace(@from...(@from + @removed_size), @inserted)
    end

    private def advance(buffer : Buffer, start : Point, text : String, unit : Units) : Point
      last = text.to_slice.rindex(0x0A_u8) || return Point.new(start.line, start.column + buffer.measure(text, unit))

      tail = text.byte_slice(last + 1, text.bytesize - last - 1)
      Point.new(start.line + text.count('\n'), buffer.measure(tail, unit))
    end
  end
end
