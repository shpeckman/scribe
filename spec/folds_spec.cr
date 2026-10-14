# spec/folds_spec.cr
require "./spec_helper"

private def folded(text : String) : {Scribe::Document, Scribe::Folds}
  subject = lines(text)
  {subject, subject.view.folds}
end

describe Scribe::Folds do
  it "folds a line range and reports what is hidden" do
    text, folds = folded("a\nb\nc\nd\ne")
    folds.fold(1, 3).should_not be_nil
    folds.size.should eq(1)

    folds.collapsed?(1).should be_true
    folds.hidden?(1).should be_false
    folds.hidden?(2).should be_true
    folds.hidden?(3).should be_true
    folds.hidden?(4).should be_false
    folds.rows.should eq([0, 1, 4])
  end

  it "refuses an empty or out-of-range fold and keeps one fold per header" do
    text, folds = folded("a\nb\nc")
    folds.fold(1, 1).should be_nil
    folds.fold(2, 1).should be_nil
    folds.fold(9, 10).should be_nil

    first = folds.fold(0, 2)
    folds.fold(0, 1).should be(first)
    folds.size.should eq(1)
  end

  it "expands, collapses and toggles" do
    text, folds = folded("a\nb\nc")
    folds.fold(0, 2)
    folds.expand(0).should be_true
    folds.collapsed?(0).should be_false
    folds.hidden?(1).should be_false

    folds.collapse(0).should be_true
    folds.hidden?(1).should be_true
    folds.toggle(0).should be_true
    folds.collapsed?(0).should be_false
    folds.expand(0).should be_false
    folds.toggle(7).should be_false
  end

  it "unfolds and clears, dropping its marks" do
    text, folds = folded("a\nb\nc")
    folds.fold(0, 2)
    text.marks.size.should eq(2)

    folds.unfold(0).should be_true
    folds.empty?.should be_true
    text.marks.should be_empty
    folds.unfold(0).should be_false

    folds.fold(0, 1)
    folds.fold(1, 2)
    folds.clear
    text.marks.should be_empty
  end

  it "replaces every fold at once, as a query would" do
    text, folds = folded("a\nb\nc\nd\ne")
    folds.replace([{0, 1}, {2, 4}])
    folds.size.should eq(2)
    folds.rows.should eq([0, 2])
  end

  it "follows the text through edits above it" do
    text, folds = folded("a\nb\nc\nd")
    folds.fold(2, 3)
    folds.rows.should eq([0, 1, 2])

    text.run(Scribe::Command::DocumentStart)
    text.insert("x\n")
    text.value.should eq("x\na\nb\nc\nd")
    folds.collapsed?(3).should be_true
    folds.hidden?(4).should be_true
    folds.rows.should eq([0, 1, 2, 3])
  end

  it "makes vertical motion skip the hidden lines" do
    text, folds = folded("one\ntwo\nthree\nfour")
    folds.fold(1, 2)

    text.run(Scribe::Command::DocumentStart)
    text.view.layout.row_count.should eq(3)
    text.run(Scribe::Command::Down)
    text.cursor.should eq(4)
    text.run(Scribe::Command::Down)
    text.cursor.should eq(14)
    text.run(Scribe::Command::Up)
    text.cursor.should eq(4)
  end

  it "leaves motion untouched while nothing is folded" do
    text = lines("one\ntwo\nthree")
    text.view.layout.row_count.should eq(3)
    text.run(Scribe::Command::DocumentStart)
    text.run(Scribe::Command::Down)
    text.cursor.should eq(4)
  end

  it "is per view" do
    text  = lines("a\nb\nc")
    other = Scribe::View.new(text)
    text.view.folds.fold(0, 2)

    text.view.folds.hidden?(1).should be_true
    other.folds?.should be_nil
    other.folds.hidden?(1).should be_false
    other.layout.row_count.should eq(3)
    text.view.layout.row_count.should eq(1)
  end
end
