# spec/annotation_spec.cr
require "./spec_helper"

private def hint(offset : Int32, text : String, placement = Scribe::Placement::After) : Scribe::Annotation
  Scribe::Annotation.new(offset, text, placement, "type")
end

describe Scribe::Annotation do
  it "replaces every annotation from the same source and keeps them sorted" do
    text = document("let x = 1")
    text.annotate("lsp", [hint(5, ": Int32"), hint(0, "let")])
    text.annotations.map(&.offset).should eq([0, 5])
    text.annotations.map(&.source).should eq(["lsp", "lsp"])

    text.annotate("lsp", [hint(5, ": Int64")])
    text.annotations.size.should eq(1)
    text.annotations.first.text.should eq(": Int64")

    text.annotate("blame", [hint(0, "you, 2 days ago", Scribe::Placement::RowEnd)])
    text.annotations.size.should eq(2)

    text.annotate("lsp", [] of Scribe::Annotation)
    text.annotations.map(&.source).should eq(["blame"])
  end

  it "moves with the text like a mark does" do
    text = lines("one\ntwo")
    text.annotate("lsp", [hint(3, "end"), hint(4, "start")])
    text.run(Scribe::Command::DocumentStart)
    text.insert("xx")
    text.annotations.map(&.offset).should eq([5, 6])
  end

  it "takes gravity from its placement" do
    text = document("ab")
    text.annotate("lsp", [hint(1, "after", Scribe::Placement::After), hint(1, "before", Scribe::Placement::Before)])
    text.select_range(1, 1)
    text.insert("-")

    found = text.annotations.sort_by(&.text)
    found.map { |entry| {entry.text, entry.offset} }.should eq([{"after", 1}, {"before", 2}])
  end

  it "finds annotations by offset, range and line" do
    text = lines("one\ntwo\nthree")
    text.annotate("lsp", [hint(1, "a"), hint(5, "b"), hint(9, "c")])
    text.annotations_at(5).map(&.text).should eq(["b"])
    text.annotations(0, 5).map(&.text).should eq(["a", "b"])
    text.annotations_on(1).map(&.text).should eq(["b"])
    text.annotations_on(2).map(&.text).should eq(["c"])
    text.annotations_on(9).should be_empty
  end

  it "tells listeners when a source replaces its annotations" do
    text   = lines("one")
    events = Noticed.new
    text.listen(events)
    text.annotate("lsp", [hint(0, "a")])
    events.annotations.should eq(1)
    text.annotate("lsp", [] of Scribe::Annotation)
    events.annotations.should eq(2)
  end

  it "reports its placement" do
    hint(0, "x", Scribe::Placement::Before).before?.should be_true
    hint(0, "x", Scribe::Placement::After).after?.should be_true
    hint(0, "x", Scribe::Placement::RowEnd).row_end?.should be_true
  end
end
