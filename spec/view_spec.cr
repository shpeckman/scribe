# spec/view_spec.cr
require "./spec_helper"

describe Scribe::View do
  it "gives a document a primary view and delegates the caret API to it" do
    text = document("hello world")
    text.view.should be_a(Scribe::View)
    text.view.document.should be(text)
    text.cursor.should eq(text.view.cursor)
    text.select_range(0, 5)
    text.view.selection.should eq(0...5)
  end

  it "keeps carets independent between views of one document" do
    text  = document("one two three")
    other = Scribe::View.new(text)

    text.select_range(0, 3)
    other.select_range(4, 7)

    text.selection.should eq(0...3)
    other.selection.should eq(4...7)
    text.selected_text.should eq("one")
    other.selected_text.should eq("two")
  end

  it "carries the other views' carets through an edit" do
    text  = document("one two three")
    other = Scribe::View.new(text)
    other.select_range(8, 13)

    text.run(Scribe::Command::DocumentStart)
    text.insert("zero ")

    text.value.should eq("zero one two three")
    text.cursor.should eq(5)
    other.selection.should eq(13...18)
    other.selected_text.should eq("three")
  end

  it "collapses a carried caret that sat inside removed text" do
    text  = document("alpha beta gamma")
    other = Scribe::View.new(text)
    other.select_range(6, 10)

    text.select_range(0, 11)
    text.run(Scribe::Command::DeleteForward)

    text.value.should eq("gamma")
    other.cursor.should eq(0)
    other.selection.should eq(0...0)
  end

  it "seats the undoing view's carets and carries the rest" do
    text  = document("one two")
    other = Scribe::View.new(text)
    other.select_range(4, 7)

    text.run(Scribe::Command::DocumentEnd)
    text.insert("!")
    other.cursor.should eq(7)

    text.undo.should be_true
    text.value.should eq("one two")
    text.cursor.should eq(7)
    other.selection.should eq(4...7)
  end

  it "lets a second view undo with its own carets" do
    text  = document("abc")
    other = Scribe::View.new(text)

    other.run(Scribe::Command::DocumentEnd)
    other.insert("d")
    text.value.should eq("abcd")

    other.undo.should be_true
    text.value.should eq("abc")
    other.cursor.should eq(3)
  end

  it "shares one history across the views of a document" do
    text  = document("a")
    other = Scribe::View.new(text)

    text.run(Scribe::Command::DocumentEnd)
    text.replace_ranges([Scribe::Edit.new(1...1, "b")])
    other.run(Scribe::Command::DocumentEnd)
    other.replace_ranges([Scribe::Edit.new(2...2, "c")])
    text.value.should eq("abc")

    other.undo.should be_true
    text.value.should eq("ab")
    text.undo.should be_true
    text.value.should eq("a")
    text.undo.should be_false
  end

  it "gives each view its own layout and box selection" do
    text  = document("one\ntwo\nthree")
    other = Scribe::View.new(text)

    text.start_box(0, 0)
    text.select_box(0, 0, 1, 2)
    text.box.should eq({0, 0, 1, 2})
    other.box.should be_nil
  end

  it "stops following the document once closed" do
    text  = document("one two")
    other = Scribe::View.new(text)
    text.views.size.should eq(2)

    other.close
    text.views.size.should eq(1)

    other.select_range(0, 3)
    text.select_range(0, 7)
    text.insert("x")
    other.selection.should eq(0...3)
  end

  it "reports caret moves per view to listeners" do
    text   = document("one two")
    events = Recorder.new
    other  = Scribe::View.new(text)
    text.listen(events)

    other.run(Scribe::Command::DocumentEnd)
    events.moves.should eq(1)
    events.last_view.should be(other)

    text.run(Scribe::Command::DocumentStart)
    events.moves.should eq(2)
    events.last_view.should be(text.view)
  end
end
