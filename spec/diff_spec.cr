# spec/diff_spec.cr
require "./spec_helper"

private def roundtrip(old : String, new : String) : {Int32, String}
  edits   = Scribe.diff(old, new, GRAPHEMES)
  subject = lines(old)
  subject.replace_ranges(edits) unless edits.empty?
  {edits.size, subject.value}
end

describe "Scribe.diff" do
  it "returns nothing for identical text" do
    Scribe.diff("a\nb", "a\nb", GRAPHEMES).should be_empty
    Scribe.diff("", "", GRAPHEMES).should be_empty
  end

  it "produces one edit for one changed line" do
    roundtrip("a\nb\nc", "a\nB\nc").should eq({1, "a\nB\nc"})
  end

  it "produces one edit per changed region, not one for the whole text" do
    roundtrip("a\nb\nc\nd\ne", "a\nx\nc\ny\ne").should eq({2, "a\nx\nc\ny\ne"})
  end

  it "handles insertions and deletions at both ends" do
    roundtrip("a\nc", "a\nb\nc").should eq({1, "a\nb\nc"})
    roundtrip("a\nb\nc", "a\nc").should eq({1, "a\nc"})
    roundtrip("a", "a\nb").should eq({1, "a\nb"})
    roundtrip("a\nb", "a").should eq({1, "a"})
    roundtrip("", "hello").should eq({1, "hello"})
    roundtrip("hello", "").should eq({1, ""})
  end

  it "handles scattered edits and reordering" do
    roundtrip("1\n2\n3\n4\n5\n6", "1\n3\n4\n6\n7").last.should eq("1\n3\n4\n6\n7")
    roundtrip("a\nb\nc", "c\nb\na").last.should eq("c\nb\na")
    roundtrip("one  \ntwo  \nthree  ", "one\ntwo\nthree").last.should eq("one\ntwo\nthree")
  end

  it "counts offsets in clusters, not bytes" do
    edits = Scribe.diff("é\nb", "é\nB", GRAPHEMES)
    edits.size.should eq(1)
    edits.first.range.begin.should eq(2)
  end

  it "falls back to one edit past its limit" do
    old = (0...80).map(&.to_s).join('\n')
    new = (0...80).map { |index| index == 40 ? "x" : index.to_s }.join('\n')
    Scribe.diff(old, new, GRAPHEMES, limit: 4).size.should eq(1)
    subject = lines(old)
    subject.replace_ranges(Scribe.diff(old, new, GRAPHEMES, limit: 4))
    subject.value.should eq(new)
  end

  it "keeps carets, marks and decorations outside the changed region" do
    subject = lines("keep\nchange me\nkeep too")
    spot    = subject.mark(2)
    subject.decorate("lsp", [Scribe::Decoration.new(0...4, "error", "boom")])
    subject.select_range(0, 4)

    subject.replace_ranges(Scribe.diff(subject.value, "keep\nchanged\nkeep too", GRAPHEMES))
    subject.value.should eq("keep\nchanged\nkeep too")
    spot.offset.should eq(2)
    subject.decorations.first.range.should eq(0...4)
    subject.selection.should eq(0...4)
  end

  it "is one undo step" do
    subject = lines("a\nb\nc")
    subject.replace_ranges(Scribe.diff(subject.value, "a\nx\nc", GRAPHEMES))
    subject.undo
    subject.value.should eq("a\nb\nc")
  end
end

describe "Scribe::Document#map" do
  it "maps an offset forward across later edits" do
    subject = lines("one two three")
    mark    = subject.revision
    subject.run(Scribe::Command::DocumentStart)
    subject.insert("zero ")

    subject.map(4, mark).should eq(9)
    subject.map(0, mark).should eq(0)
  end

  it "maps a range and keeps it from growing at its edges" do
    subject = lines("one two three")
    mark    = subject.revision
    subject.run(Scribe::Command::DocumentStart)
    subject.insert("xx")

    subject.map(4...7, mark).should eq(6...9)
  end

  it "collapses an offset inside removed text" do
    subject = lines("alpha beta gamma")
    mark    = subject.revision
    subject.select_range(0, 11)
    subject.run(Scribe::Command::DeleteForward)

    subject.map(6, mark).should eq(0)
  end

  it "returns the offset unchanged at the current revision" do
    subject = lines("one")
    subject.map(2, subject.revision).should eq(2)
  end

  it "gives up when the journal no longer reaches back" do
    subject = lines("x")
    subject.map(0, subject.revision + 5).should be_nil
    300.times { subject.insert("a") }
    subject.map(0, 0).should be_nil
  end
end
