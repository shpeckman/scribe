# spec/units_spec.cr
require "./spec_helper"

describe Scribe::Units do
  it "counts a line in every unit and maps unit offsets back to clusters" do
    row = line("aé👍🏽x")
    row.units(Scribe::Units::Clusters).should eq(4)
    row.units(Scribe::Units::Bytes).should eq(12)
    row.units(Scribe::Units::CodePoints).should eq(5)
    row.units(Scribe::Units::Utf16).should eq(7)
    row.units(Scribe::Units::Utf16, 2, 3).should eq(4)
    row.column_for(3, Scribe::Units::Utf16).should eq(2)
    row.column_for(6, Scribe::Units::Utf16).should eq(3)
    row.column_for(4, Scribe::Units::Utf16).should eq(2)
    row.column_for(3, Scribe::Units::Bytes).should eq(2)
    row.column_for(99, Scribe::Units::CodePoints).should eq(4)
  end

  it "converts offsets to points and back through the buffer" do
    text = buffer("ab\n👍🏽c")
    text.point(4, Scribe::Units::Utf16).should eq(Scribe::Point.new(1, 4))
    text.point(4, Scribe::Units::Bytes).should eq(Scribe::Point.new(1, 8))
    text.offset_at(Scribe::Point.new(1, 4), Scribe::Units::Utf16).should eq(4)
    text.offset_at(Scribe::Point.new(9, 0), Scribe::Units::Utf16).should eq(3)
    text.measure("👍🏽\nx", Scribe::Units::Clusters).should eq(3)
  end
end

describe Scribe::Change do
  it "describes where it starts and where it ended before and after, in any unit" do
    text  = buffer("ab\ncd")
    found = text.replace(1...4, "é\n👍🏽\nxy")
    found.start_point(text, Scribe::Units::Utf16).should eq(Scribe::Point.new(0, 1))
    found.old_end_point(text, Scribe::Units::Utf16).should eq(Scribe::Point.new(1, 1))
    found.new_end_point(text, Scribe::Units::Utf16).should eq(Scribe::Point.new(2, 2))
    found.new_end_point(text, Scribe::Units::Bytes).should eq(Scribe::Point.new(2, 2))
    single = text.replace(0...0, "é")
    single.new_end_point(text, Scribe::Units::Bytes).should eq(Scribe::Point.new(0, 2))
  end
end

describe Scribe::Decoration do
  it "follows edits without growing at its edges and is replaced per source" do
    text   = document("one two three")
    events = Recorder.new
    text.listen(events)
    text.decorate("lsp", [Scribe::Decoration.new(4...7, "error", "bad"), Scribe::Decoration.new(8...8, "hint")])
    text.decorate("spell", [Scribe::Decoration.new(0...3, "warning")])
    text.decorations.map(&.range).should eq([0...3, 4...7, 8...8])
    text.move(4)
    text.insert("XX")
    text.move(9)
    text.insert("Y")
    text.decorations.map(&.range).should eq([0...3, 6...9, 11...11])
    text.decorations_at(7).map(&.message).should eq(["bad"])
    text.decorations(0, 5).map(&.kind).should eq(["warning"])
    text.decorations(11, 11).map(&.kind).should eq(["hint"])
    text.decorate("lsp", [] of Scribe::Decoration)
    text.decorations.map(&.source).should eq(["spell"])
    events.moves.should be > 0
  end
end
