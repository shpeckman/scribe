# src/scribe/change.cr
module Scribe
  record Change, from : Int32, removed : Array(String), inserted : Array(String) do
    def undo(buffer : Buffer) : Nil
      buffer.replace(@from...(@from + @inserted.size), @removed)
    end

    def redo(buffer : Buffer) : Nil
      buffer.replace(@from...(@from + @removed.size), @inserted)
    end
  end
end
