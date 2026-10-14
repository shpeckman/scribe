# src/scribe/command.cr
module Scribe
  enum Command
    Left
    Right
    WordLeft
    WordRight
    RowStart
    SmartRowStart
    RowEnd
    Up
    Down
    PageUp
    PageDown
    DocumentStart
    DocumentEnd
    SelectAll
    SelectWord
    SelectLine
    Collapse
    AddNextOccurrence
    SkipOccurrence
    SelectAllOccurrences
    AddCaretAbove
    AddCaretBelow
    RemoveLastCaret
    BoxUp
    BoxDown
    BoxLeft
    BoxRight
    DeleteBackward
    DeleteForward
    DeleteWordBackward
    DeleteWordForward
    DeleteToRowStart
    DeleteToRowEnd
    NewLine
    Tab
    Indent
    Outdent
    ToggleComment
    MoveLinesUp
    MoveLinesDown
    DuplicateLines
    DeleteLines
    Copy
    Cut
    Paste
    Undo
    Redo

    def edits? : Bool
      in?(DeleteBackward, DeleteForward, DeleteWordBackward, DeleteWordForward, DeleteToRowStart, DeleteToRowEnd,
        NewLine, Tab, Indent, Outdent, ToggleComment, MoveLinesUp, MoveLinesDown, DuplicateLines, DeleteLines,
        Cut, Paste, Undo, Redo)
    end
  end
end
