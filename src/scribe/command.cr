# src/scribe/command.cr
module Scribe
  enum Command
    Left
    Right
    WordLeft
    WordRight
    SubwordLeft
    SubwordRight
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
    SelectInsideBrackets
    SelectAroundBrackets
    SelectInsideQuotes
    SelectAroundQuotes
    Collapse
    AddNextOccurrence
    SkipOccurrence
    SelectAllOccurrences
    AddCaretAbove
    AddCaretBelow
    AddCaretPerLine
    RemoveLastCaret
    BoxUp
    BoxDown
    BoxLeft
    BoxRight
    DeleteBackward
    DeleteForward
    DeleteWordBackward
    DeleteWordForward
    DeleteSubwordBackward
    DeleteSubwordForward
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
    DuplicateSelection
    DeleteLines
    SortLines
    ReverseLines
    UniqueLines
    JoinLines
    TrimTrailingWhitespace
    UpperCase
    LowerCase
    TitleCase
    Copy
    Cut
    Paste
    Undo
    Redo

    def edits? : Bool
      in?(DeleteBackward, DeleteForward, DeleteWordBackward, DeleteWordForward, DeleteSubwordBackward,
        DeleteSubwordForward, DeleteToRowStart, DeleteToRowEnd, NewLine, Tab, Indent, Outdent, ToggleComment,
        MoveLinesUp, MoveLinesDown, DuplicateLines, DeleteLines, SortLines, ReverseLines, UniqueLines,
        JoinLines, TrimTrailingWhitespace, UpperCase, LowerCase, TitleCase, Cut, Paste, Undo, Redo)
    end
  end
end
