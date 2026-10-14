# spec/history_spec.cr
require "./spec_helper"

private def edit(buffer : Scribe::Buffer, at : Int32, text : String) : Scribe::Change
  buffer.replace(at...at, text.chars.map(&.to_s))
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
  it "undoes and redoes steps with their carets" do
    buffer  = Scribe::Buffer.new
    history = Scribe::History.new(GRAPHEMES)
    history.record(other, [edit(buffer, 0, "abc")], carets(0), 0, carets(3), 0)
    buffer.text.should eq("abc")
    step = history.undo(buffer).not_nil!
    buffer.text.should eq("")
    step.before.should eq(carets(0))
    history.can_redo?.should be_true
    history.redo(buffer).not_nil!.after.should eq(carets(3))
    buffer.text.should eq("abc")
    history.undo(buffer)
    history.undo(buffer).should be_nil
  end

  it "joins typing into one step and breaks it at word starts" do
    buffer  = Scribe::Buffer.new
    history = Scribe::History.new(GRAPHEMES)
    "ab c".each_char_with_index do |char, index|
      history.record(typing, [edit(buffer, index, char.to_s)], carets(index), 0, carets(index + 1), 0)
    end
    history.undo(buffer)
    buffer.text.should eq("ab ")
    history.undo(buffer)
    buffer.text.should eq("")
  end

  it "starts a new step when the carets moved, the kind changed or the window passed" do
    buffer  = Scribe::Buffer.new
    history = Scribe::History.new(GRAPHEMES)
    history.record(typing, [edit(buffer, 0, "a")], carets(0), 0, carets(1), 0)
    history.record(typing, [edit(buffer, 0, "b")], carets(0), 0, carets(1), 0)
    history.undo(buffer)
    buffer.text.should eq("a")

    history.record(Scribe::History::Kind::Deleting, [buffer.replace(0...1, [] of String)], carets(1), 0, carets(0), 0)
    history.undo(buffer)
    buffer.text.should eq("a")

    history.window = 0.seconds
    history.record(typing, [edit(buffer, 1, "x")], carets(1), 0, carets(2), 0)
    sleep 1.millisecond
    history.record(typing, [edit(buffer, 2, "y")], carets(2), 0, carets(3), 0)
    history.undo(buffer)
    buffer.text.should eq("ax")
  end

  it "forgets the redo stack on a new edit and keeps at most its limit" do
    buffer  = Scribe::Buffer.new
    history = Scribe::History.new(GRAPHEMES, limit: 2)
    3.times do |index|
      history.record(other, [edit(buffer, index, "x")], carets(index), 0, carets(index + 1), 0)
    end
    history.undo(buffer)
    history.undo(buffer)
    history.undo(buffer).should be_nil
    buffer.text.should eq("x")
    history.record(other, [edit(buffer, 1, "y")], carets(1), 0, carets(2), 0)
    history.can_redo?.should be_false
  end
end
