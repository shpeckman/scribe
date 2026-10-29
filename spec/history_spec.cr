# spec/history_spec.cr
require "./spec_helper"

private class Clock
  getter now : Time::Instant = Time.instant

  def advance(span : Time::Span) : Nil
    @now += span
  end

  def proc : Proc(Time::Instant)
    -> { @now }
  end
end

private def edit(text : Scribe::Buffer, at : Int32, inserted : String) : Scribe::Change
  text.replace(at...at, inserted)
end

private def carets(*offsets : Int32) : Array(Scribe::Caret)
  offsets.to_a.map { |offset| Scribe::Caret.at(offset) }
end

private def typing : Scribe::History::Kind
  Scribe::History::Kind::Typing
end

private def other : Scribe::History::Kind
  Scribe::History::Kind::Other
end

describe Scribe::History do
  it "undoes and redoes steps with their carets and reports the changes it applied" do
    text    = buffer("")
    history = Scribe::History.new(GRAPHEMES)
    history.record(other, [edit(text, 0, "abc")], carets(0), 0, carets(3), 0)
    text.text.should eq("abc")
    step, applied = history.undo(text).not_nil!
    text.text.should eq("")
    step.before.should eq(carets(0))
    applied.should eq([change(0, "abc", "")])
    history.can_redo?.should be_true
    history.redo(text).not_nil![0].after.should eq(carets(3))
    text.text.should eq("abc")
    history.undo(text)
    history.undo(text).should be_nil
  end

  it "joins typing into one step and breaks it at word starts" do
    text    = buffer("")
    history = Scribe::History.new(GRAPHEMES)
    "ab c".each_char_with_index do |char, index|
      history.record(typing, [edit(text, index, char.to_s)], carets(index), 0, carets(index + 1), 0)
    end
    history.undo(text)
    text.text.should eq("ab ")
    history.undo(text)
    text.text.should eq("")
  end

  it "starts a new step when the carets moved, the kind changed or the window passed" do
    clock   = Clock.new
    text    = buffer("")
    history = Scribe::History.new(GRAPHEMES, clock: clock.proc)
    history.record(typing, [edit(text, 0, "a")], carets(0), 0, carets(1), 0)
    history.record(typing, [edit(text, 0, "b")], carets(0), 0, carets(1), 0)
    history.undo(text)
    text.text.should eq("a")

    history.record(Scribe::History::Kind::Deleting, [text.replace(0...1, "")], carets(1), 0, carets(0), 0)
    history.undo(text)
    text.text.should eq("a")

    history.record(typing, [edit(text, 1, "x")], carets(1), 0, carets(2), 0)
    clock.advance(2.seconds)
    history.record(typing, [edit(text, 2, "y")], carets(2), 0, carets(3), 0)
    history.undo(text)
    text.text.should eq("ax")
  end

  it "forgets the redo stack on a new edit and keeps at most its limit" do
    text    = buffer("")
    history = Scribe::History.new(GRAPHEMES, limit: 2)
    3.times do |index|
      history.record(other, [edit(text, index, "x")], carets(index), 0, carets(index + 1), 0)
    end
    history.undo(text)
    history.undo(text)
    history.undo(text).should be_nil
    text.text.should eq("x")
    history.record(other, [edit(text, 1, "y")], carets(1), 0, carets(2), 0)
    history.can_redo?.should be_false
  end

  it "tracks a save point through undo, redo and further typing" do
    text    = buffer("")
    history = Scribe::History.new(GRAPHEMES)
    history.modified?.should be_false
    history.record(typing, [edit(text, 0, "a")], carets(0), 0, carets(1), 0)
    history.modified?.should be_true
    history.mark_saved
    history.modified?.should be_false
    history.record(typing, [edit(text, 1, "b")], carets(1), 0, carets(2), 0)
    history.modified?.should be_true
    history.undo(text)
    history.modified?.should be_false
    history.undo(text)
    history.modified?.should be_true
    history.redo(text)
    history.modified?.should be_false
  end
end
