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

    def undo(buffer : Buffer) : Change
      buffer.replace(@from...(@from + @inserted_size), @removed)
    end

    def redo(buffer : Buffer) : Change
      buffer.replace(@from...(@from + @removed_size), @inserted)
    end
  end
end
