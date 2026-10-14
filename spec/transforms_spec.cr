# spec/transforms_spec.cr
require "./spec_helper"

describe "Scribe::View subword motion" do
  it "steps through camelCase, snake_case and punctuation" do
    text = document("fooBarBaz snake_case_name")
    text.run(Scribe::Command::DocumentStart)
    text.run(Scribe::Command::SubwordRight)
    text.cursor.should eq(3)
    text.run(Scribe::Command::SubwordRight)
    text.cursor.should eq(6)
    text.run(Scribe::Command::SubwordRight)
    text.cursor.should eq(10)
    text.run(Scribe::Command::SubwordRight)
    text.cursor.should eq(16)
    text.run(Scribe::Command::SubwordRight)
    text.cursor.should eq(21)
  end

  it "steps back the same way and selects while shifted" do
    text = document("fooBarBaz")
    text.run(Scribe::Command::DocumentEnd)
    text.run(Scribe::Command::SubwordLeft)
    text.cursor.should eq(6)
    text.run(Scribe::Command::SubwordLeft, true)
    text.selection.should eq(3...6)
  end

  it "deletes a subword either way" do
    text = document("fooBarBaz")
    text.run(Scribe::Command::DocumentEnd)
    text.run(Scribe::Command::DeleteSubwordBackward).should be_true
    text.value.should eq("fooBar")

    text.run(Scribe::Command::DocumentStart)
    text.run(Scribe::Command::DeleteSubwordForward)
    text.value.should eq("Bar")
  end
end

describe "Scribe::View line transforms" do
  it "sorts, reverses and uniques the lines under the carets" do
    text = lines("c\na\nb\na")
    text.select_range(0, 7)
    text.run(Scribe::Command::SortLines).should be_true
    text.value.should eq("a\na\nb\nc")

    text.run(Scribe::Command::ReverseLines)
    text.value.should eq("c\nb\na\na")

    text.run(Scribe::Command::UniqueLines)
    text.value.should eq("c\nb\na")
  end

  it "trims trailing whitespace and reports when there is none" do
    text = lines("one  \ntwo\t\nthree")
    text.select_all
    text.run(Scribe::Command::TrimTrailingWhitespace).should be_true
    text.value.should eq("one\ntwo\nthree")
    text.run(Scribe::Command::TrimTrailingWhitespace).should be_false
  end

  it "joins the lines in the block, or the next line with an empty caret" do
    text = lines("one\n  two\nthree")
    text.select_range(0, 9)
    text.run(Scribe::Command::JoinLines).should be_true
    text.value.should eq("one two\nthree")

    text.run(Scribe::Command::DocumentStart)
    text.run(Scribe::Command::JoinLines)
    text.value.should eq("one two three")
    text.run(Scribe::Command::JoinLines).should be_false
  end

  it "leaves sorted lines alone" do
    text = lines("a\nb")
    text.select_all
    text.run(Scribe::Command::SortLines).should be_false
  end
end

describe "Scribe::View case transforms" do
  it "upper, lower and title case every selection" do
    text = document("hello wide world")
    text.select_range(0, 5)
    text.run(Scribe::Command::UpperCase).should be_true
    text.value.should eq("HELLO wide world")
    text.selection.should eq(0...5)

    text.run(Scribe::Command::LowerCase)
    text.value.should eq("hello wide world")

    text.select_range(0, 16)
    text.run(Scribe::Command::TitleCase)
    text.value.should eq("Hello Wide World")
  end

  it "does nothing without a selection" do
    text = document("abc")
    text.run(Scribe::Command::UpperCase).should be_false
  end
end

describe "Scribe::View carets" do
  it "puts a caret on every line of a spanning selection" do
    text = lines("one\ntwo\nthree")
    text.select_range(0, 13)
    text.run(Scribe::Command::AddCaretPerLine).should be_true
    text.carets.size.should eq(3)
    text.carets.map(&.head).should eq([3, 7, 13])
    text.run(Scribe::Command::AddCaretPerLine).should be_false
  end

  it "puts a caret on every match of a search" do
    text   = lines("one two\none")
    search = Scribe::Search.new("one")
    text.view.add_caret_at_every_match(search).should be_true
    text.carets.size.should eq(2)
    text.selected_texts.should eq(["one", "one"])
    text.view.add_caret_at_every_match(Scribe::Search.new("zzz")).should be_false
  end
end

describe "Scribe::View surround" do
  it "wraps each selection and keeps it selected" do
    text = document("one two")
    text.select_range(0, 3)
    text.view.surround("(").should be_true
    text.value.should eq("(one) two")
    text.selected_text.should eq("one")
  end

  it "removes a matching pair around the selection" do
    text = document("(one) two")
    text.select_range(0, 5)
    text.view.unsurround.should be_true
    text.value.should eq("one two")
    text.selected_text.should eq("one")
  end

  it "refuses an unknown opener and a selection without a pair" do
    text = document("one")
    text.select_range(0, 3)
    text.view.surround("<").should be_false
    text.view.unsurround.should be_false
  end
end

describe Scribe::MacroLog do
  it "records commands and typed text, then replays them" do
    text  = lines("alpha\nbeta")
    log   = Scribe::MacroLog.new
    text.view.macros = log

    log.record
    text.run(Scribe::Command::DocumentStart)
    text.run(Scribe::Command::RowEnd)
    text.insert("!")
    log.stop
    log.size.should eq(3)

    text.run(Scribe::Command::DocumentEnd)
    log.replay(text.view).should be_true
    text.value.should eq("alpha!!\nbeta")
  end

  it "replays several times as one undo step each and never records itself" do
    text = lines("a")
    log  = Scribe::MacroLog.new
    text.view.macros = log

    log.record
    text.insert("x")
    log.stop
    log.size.should eq(1)

    log.replay(text.view, 3).should be_true
    text.value.should eq("axxxx")
    log.size.should eq(1)
    text.undo
    text.value.should eq("axxx")
  end

  it "refuses to replay nothing" do
    text = lines("a")
    Scribe::MacroLog.new.replay(text.view).should be_false
  end
end

describe "Scribe::Document#final_newline" do
  it "adds one line ending on export without touching the text" do
    text = Scribe::Document.new(GRAPHEMES, "a\nb", filter: Scribe::MultiLine.new, final_newline: true)
    text.value.should eq("a\nb")
    text.export.should eq("a\nb\n")

    text.final_newline = false
    text.export.should eq("a\nb")
  end

  it "leaves an empty document and an already-terminated one alone" do
    empty = Scribe::Document.new(GRAPHEMES, "", filter: Scribe::MultiLine.new, final_newline: true)
    empty.export.should eq("")

    ended = Scribe::Document.new(GRAPHEMES, "a\n", filter: Scribe::MultiLine.new, final_newline: true)
    ended.export.should eq("a\n")
  end

  it "uses the document's own line ending" do
    text = Scribe::Document.new(GRAPHEMES, "a\r\nb", filter: Scribe::MultiLine.new, final_newline: true)
    text.export.should eq("a\r\nb\r\n")
  end
end
