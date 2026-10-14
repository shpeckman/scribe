# spec/document_spec.cr
require "./spec_helper"

private def run(text : Scribe::Document, *commands : Scribe::Command) : Bool
  commands.map { |command| text.run(command) }.last
end

private def code(text : String) : Scribe::Document
  document(text, filter: Scribe::MultiLine.new("  "), auto_indent: true)
end

describe Scribe::Document do
  describe "typing and deleting" do
    it "inserts at the cursor and deletes around it" do
      text = document("abc")
      text.cursor.should eq(3)
      run(text, Scribe::Command::DeleteBackward).should be_true
      text.value.should eq("ab")
      text.run(Scribe::Command::Left)
      text.cursor.should eq(1)
      text.run(Scribe::Command::DeleteForward)
      text.value.should eq("a")
      text.run(Scribe::Command::RowStart)
      text.insert("x").should be_true
      text.value.should eq("xa")
    end

    it "filters what it is given" do
      text = document
      text.insert("a\r\nb\tc\e")
      text.value.should eq("a b c")
      text.value = "x\ny"
      text.value.should eq("x y")
      document("a\r\nb\tc", filter: Scribe::MultiLine.new).value.should eq("a\nb c")
    end

    it "enforces max_length across every caret" do
      text = document("ab", max_length: 3)
      text.place_carets([Scribe::Caret.at(1), Scribe::Caret.at(2)])
      text.insert("x").should be_true
      text.value.should eq("axb")
      text.insert("y").should be_false
      text.value = "abcdef"
      text.value.should eq("abc")
      long = document("abcdef")
      long.max_length = 3
      long.value.should eq("abc")
    end

    it "clears the value and reports nothing when it is unchanged" do
      text   = document("abc")
      events = Recorder.new
      text.listen(events)
      text.value = "abc"
      events.edited.should be_empty
      text.clear
      text.value.should eq("")
      text.cursor.should eq(0)
      events.edited.size.should eq(1)
    end
  end

  describe "moving" do
    it "jumps by word, treating underscores and combining marks as word characters" do
      text = document("snake_case café")
      text.cursor.should eq(15)
      text.run(Scribe::Command::WordLeft)
      text.cursor.should eq(11)
      text.run(Scribe::Command::WordLeft)
      text.cursor.should eq(0)
      text.run(Scribe::Command::WordRight)
      text.cursor.should eq(10)
    end

    it "collapses a selection to its edge before moving" do
      text = document("hello")
      text.select_range(1, 4)
      text.run(Scribe::Command::Left)
      text.cursor.should eq(1)
      text.select_range(1, 4)
      text.run(Scribe::Command::Right)
      text.cursor.should eq(4)
    end

    it "extends the selection while selecting" do
      text = document("hello world")
      5.times { text.run(Scribe::Command::Left, selecting: true) }
      text.selected_text.should eq("world")
      text.run(Scribe::Command::RowStart, selecting: true)
      text.selected_text.should eq("hello world")
      text.run(Scribe::Command::WordRight, selecting: true)
      text.selected_text.should eq(" world")
    end

    it "moves vertically by display column and to row edges" do
      text = lines("a日本x\nabcd")
      text.move(2)
      text.run(Scribe::Command::Down)
      text.cursor.should eq(8)
      text.run(Scribe::Command::Up)
      text.cursor.should eq(2)
      text.run(Scribe::Command::RowEnd)
      text.cursor.should eq(4)
      text.run(Scribe::Command::Down)
      text.cursor.should eq(9)
      text.run(Scribe::Command::RowStart)
      text.cursor.should eq(5)
    end
  end

  describe "selecting" do
    it "reports the selection and its text" do
      text = lines("ab\ncd")
      text.select_range(0, 4)
      text.selection?.should be_true
      text.selection.should eq(0...4)
      text.selected_text.should eq("ab\nc")
      text.selected?(3).should be_true
      text.selected?(4).should be_false
      text.run(Scribe::Command::SelectAll)
      text.selected_text.should eq("ab\ncd")
    end

    it "merges carets that meet" do
      text = document("abc")
      text.place_carets([Scribe::Caret.at(1), Scribe::Caret.at(2)])
      text.run(Scribe::Command::RowStart)
      text.carets.should eq([Scribe::Caret.at(0)])
      text.place_carets([Scribe::Caret.new(0, 2), Scribe::Caret.at(1)])
      text.carets.should eq([Scribe::Caret.new(0, 2)])
    end

    it "selects the word and then its next occurrences" do
      text = document("foo bar foo foo")
      text.move(1)
      run(text, Scribe::Command::AddNextOccurrence).should be_true
      text.selected_text.should eq("foo")
      run(text, Scribe::Command::AddNextOccurrence, Scribe::Command::AddNextOccurrence)
      text.carets.size.should eq(3)
      text.run(Scribe::Command::AddNextOccurrence).should be_false
      text.insert("x")
      text.value.should eq("x bar x x")
    end

    it "collapses to the primary caret and reports when there was nothing to collapse" do
      text = document("abc")
      text.place_carets([Scribe::Caret.at(0), Scribe::Caret.at(3)], 0)
      text.run(Scribe::Command::Collapse).should be_true
      text.carets.should eq([Scribe::Caret.at(0)])
      text.run(Scribe::Command::Collapse).should be_false
    end

    it "adds carets on the rows above and below" do
      text = lines("ab\ncd\nef")
      text.move(1)
      run(text, Scribe::Command::AddCaretBelow, Scribe::Command::AddCaretBelow)
      heads(text).should eq([1, 4, 7])
      text.run(Scribe::Command::AddCaretBelow)
      heads(text).should eq([1, 4, 7])
      text.insert("-")
      text.value.should eq("a-b\nc-d\ne-f")
    end

    it "selects a box of rows and columns and starts a fresh box once cleared" do
      text = lines("abcd\nefgh\nijkl")
      text.move(1)
      run(text, Scribe::Command::BoxDown, Scribe::Command::BoxDown, Scribe::Command::BoxRight, Scribe::Command::BoxRight)
      text.selected_texts.should eq(["bc", "fg", "jk"])
      text.box.should eq({0, 1, 2, 3})
      text.run(Scribe::Command::DeleteForward)
      text.value.should eq("ad\neh\nil")
      text.clear_box
      text.move(0)
      text.run(Scribe::Command::BoxDown)
      text.box.should eq({0, 0, 1, 0})
    end

    it "selects a box dragged from a start point" do
      text = lines("abcd\nefgh")
      text.start_box(0, 1)
      text.carets.should eq([Scribe::Caret.at(9)])
      text.select_box(0, 1, 1, 3)
      text.selected_texts.should eq(["bc", "fg"])
      text.primary.should eq(1)
    end
  end

  describe "history" do
    it "undoes typing at every caret as one step and redoes it" do
      text = document("ab ab")
      text.place_carets([Scribe::Caret.at(2), Scribe::Caret.at(5)])
      text.insert("!")
      text.value.should eq("ab! ab!")
      heads(text).should eq([3, 7])
      run(text, Scribe::Command::DeleteBackward, Scribe::Command::DeleteBackward)
      text.value.should eq("a a")
      run(text, Scribe::Command::Undo).should be_true
      text.value.should eq("ab! ab!")
      text.undo
      text.value.should eq("ab ab")
      heads(text).should eq([2, 5])
      run(text, Scribe::Command::Redo).should be_true
      text.value.should eq("ab! ab!")
      text.undo
      text.undo.should be_false
    end

    it "undoes values set from code" do
      text = document("one")
      text.value = "two"
      text.undo.should be_true
      text.value.should eq("one")
      text.redo.should be_true
      text.value.should eq("two")
    end

    it "replaces several ranges as one step and carries the carets" do
      text = document("a-b-c")
      text.place_carets([Scribe::Caret.at(2), Scribe::Caret.at(5)])
      text.replace_ranges([{1...2, ["+", "+"]}, {3...4, ["+", "+"]}]).should be_true
      text.value.should eq("a++b++c")
      heads(text).should eq([3, 7])
      text.replace_ranges([{0...0, [] of String}]).should be_false
      text.undo
      text.value.should eq("a-b-c")
    end
  end

  describe "clipboard" do
    it "copies every selection, pastes one line per caret, and cuts" do
      text = document("ab cd")
      text.place_carets([Scribe::Caret.new(0, 2), Scribe::Caret.new(3, 5)])
      text.run(Scribe::Command::Copy)
      text.clipboard.as(Scribe::Register).text.should eq("ab\ncd")
      text.place_carets([Scribe::Caret.at(2), Scribe::Caret.at(5)])
      text.run(Scribe::Command::Paste)
      text.value.should eq("abab cdcd")
      text.collapse
      text.move(0)
      text.run(Scribe::Command::Paste)
      text.value.should eq("ab cdabab cdcd")
      text.place_carets([Scribe::Caret.new(0, 1), Scribe::Caret.new(5, 6)])
      text.run(Scribe::Command::Cut)
      text.value.should eq("b cdbab cdcd")
    end

    it "pastes once an asynchronous clipboard answers" do
      board = Deferred.new("later")
      text  = document(clipboard: board)
      text.run(Scribe::Command::Paste)
      text.value.should eq("")
      board.deliver
      text.value.should eq("later")
    end

    it "never copies or cuts when it is not copyable" do
      board = Scribe::Register.new
      text  = document("secret", clipboard: board, copyable: false)
      text.run(Scribe::Command::SelectAll)
      run(text, Scribe::Command::Copy, Scribe::Command::Cut)
      text.value.should eq("secret")
      board.text.should eq("")
    end

    it "copies a selection as it is made unless a drag is still under way" do
      board = Scribe::Register.new
      text  = document("hello world", clipboard: board, copy_on_select: true)
      text.dragging = true
      text.move(6)
      text.move(11, selecting: true)
      board.text.should eq("")
      text.dragging = false
      text.auto_copy
      board.text.should eq("world")
      text.run(Scribe::Command::WordLeft, selecting: true)
      board.text.should eq("world")
      text.run(Scribe::Command::SelectAll)
      board.text.should eq("hello world")
    end
  end

  describe "lines" do
    it "inserts plain line breaks or keeps the indentation" do
      plain = document("  foo", filter: Scribe::MultiLine.new)
      plain.run(Scribe::Command::NewLine).should be_true
      plain.value.should eq("  foo\n")
      text = code("  foo")
      text.run(Scribe::Command::NewLine)
      text.insert("x")
      text.value.should eq("  foo\n  x")
    end

    it "indents with tab and outdents every selected line" do
      text = code("a\nb\nc")
      text.move(0)
      text.run(Scribe::Command::Tab).should be_true
      text.value.should eq("  a\nb\nc")
      text.select_range(0, 5)
      text.run(Scribe::Command::Tab)
      text.value.should eq("    a\n  b\nc")
      run(text, Scribe::Command::Outdent, Scribe::Command::Outdent)
      text.value.should eq("a\nb\nc")
      text.run(Scribe::Command::Outdent).should be_false
      text.undo
      text.value.should eq("  a\nb\nc")
    end

    it "moves, duplicates and deletes the lines under every caret" do
      text = code("a\nb\nc\nd")
      text.move(2)
      text.run(Scribe::Command::MoveLinesDown).should be_true
      text.value.should eq("a\nc\nb\nd")
      text.cursor.should eq(4)
      run(text, Scribe::Command::MoveLinesUp, Scribe::Command::MoveLinesUp)
      text.value.should eq("b\na\nc\nd")
      text.run(Scribe::Command::MoveLinesUp).should be_false
      text.place_carets([Scribe::Caret.at(0), Scribe::Caret.at(4)])
      text.run(Scribe::Command::DuplicateLines).should be_true
      text.value.should eq("b\nb\na\nc\nc\nd")
      heads(text).should eq([2, 8])
      text.run(Scribe::Command::DeleteLines).should be_true
      text.value.should eq("b\na\nc\nd")
      text.undo
      text.value.should eq("b\nb\na\nc\nc\nd")
    end

    it "turns pasted tabs into its indent" do
      text = document("", filter: Scribe::MultiLine.new("    "), indent: "    ")
      text.paste("\tx")
      text.value.should eq("    x")
    end
  end

  describe "find and replace" do
    it "selects matches forward and backward" do
      text   = document("one two one\ntwo one")
      search = Scribe::Search.new("one")
      text.move(0)
      text.find(search).should eq(0...3)
      text.find(search).should eq(8...11)
      text.find(search).should eq(16...19)
      text.find(search, backward: true).should eq(8...11)
      text.selection.should eq(8...11)
      text.find(Scribe::Search.new("zzz")).should be_nil
    end

    it "replaces the selected match and every match as one step, expanding captures" do
      text   = document("a=1 b=2 c=3")
      search = Scribe::Search.new("(\\w+)=(\\d)", regex: true)
      text.move(0)
      found = text.find(search).not_nil!
      text.replace_match(search, found, "$2=$1").should be_true
      text.value.should eq("1=a b=2 c=3")
      text.replace_match(search, 0...1, "x").should be_false
      text.replace_all(search, "$2=$1").should eq(2)
      text.value.should eq("1=a 2=b 3=c")
      text.undo
      text.value.should eq("1=a b=2 c=3")
      text.replace_all(Scribe::Search.new("zzz"), "x").should eq(0)
    end
  end

  it "finds the bracket matching the one beside an empty primary caret" do
    text = document("if (a(b)) x")
    text.move(4)
    text.brackets.should eq({3, 8})
    text.move(8)
    text.brackets.should eq({5, 7})
    text.move(1)
    text.brackets.should be_nil
    text.select_range(3, 4)
    text.brackets.should be_nil
  end
end
