# spec/buffer_spec.cr
require "./spec_helper"

describe Scribe::Buffer do
  it "splits its text into lines and maps offsets to positions" do
    text = buffer("ab\ncde\n")
    text.size.should eq(7)
    text.line_count.should eq(3)
    text.line(1).text.should eq("cde")
    text.line_start(2).should eq(7)
    text.line_end(1).should eq(6)
    text.position(0).should eq(Scribe::Position.new(0, 0))
    text.position(2).should eq(Scribe::Position.new(0, 2))
    text.position(3).should eq(Scribe::Position.new(1, 0))
    text.position(7).should eq(Scribe::Position.new(2, 0))
    text.position(99).should eq(Scribe::Position.new(2, 0))
    text.offset(1, 2).should eq(5)
    text.offset(1, 9).should eq(6)
    text.offset(Scribe::Position.new(2, 0)).should eq(7)
    text.cluster(2).should eq("\n")
    text.cluster(4).should eq("d")
    text.cluster(7).should be_nil
    text.kind(2).should eq(Scribe::ClusterKind::Space)
  end

  it "keeps an empty document as one empty line" do
    text = buffer("")
    text.size.should eq(0)
    text.line_count.should eq(1)
    text.position(0).should eq(Scribe::Position.new(0, 0))
    text.text.should eq("")
  end

  it "slices across lines" do
    text = buffer("ab\ncde\nf")
    text.slice_text(1...5).should eq("b\ncd")
    text.slice_text(3...6).should eq("cde")
    text.slice_text(4...4).should eq("")
    text.slice_text(0...99).should eq("ab\ncde\nf")
  end

  it "replaces ranges spanning lines and reports the change" do
    text    = buffer("ab\ncde\nf")
    changes = [] of Scribe::Change
    stop    = text.on_change { |found| changes << found; nil }
    found   = text.replace(1...5, "X\nY")
    text.text.should eq("aX\nYe\nf")
    text.line_count.should eq(3)
    text.line_start(2).should eq(6)
    found.should eq(change(1, "b\ncd", "X\nY"))
    found.removed_lines.should eq(1)
    found.inserted_lines.should eq(1)
    changes.should eq([found])
    stop.call
    text.replace(0...text.size, "")
    changes.size.should eq(1)
    text.text.should eq("")
    text.line_count.should eq(1)
    text.size.should eq(0)
  end

  it "keeps line offsets right through many edits" do
    text = buffer((1..200).join('\n'))
    text.replace(text.line_start(10)...text.line_start(10), "x\ny\n")
    text.replace(text.line_start(150)...text.line_end(152), "z")
    text.replace(text.line_start(3)...text.line_start(3), "123")
    expected = text.text.split('\n')
    text.line_count.should eq(expected.size)
    start = 0
    expected.each_with_index do |part, index|
      text.line_start(index).should eq(start)
      text.position(start).should eq(Scribe::Position.new(index, 0))
      start += part.size + 1
    end
    text.size.should eq(text.text.size)
  end

  it "widens a change to whole clusters when an edit merges with its neighbours" do
    text  = buffer("cafe!")
    found = text.replace(4...4, "́")
    text.text.should eq("café!")
    text.size.should eq(5)
    found.should eq(change(3, "e", "é"))
    found.undo(text)
    text.text.should eq("cafe!")
    text.size.should eq(5)
  end

  it "undoes and redoes its changes" do
    text   = buffer("hello")
    found  = text.replace(1...4, "E\n")
    text.text.should eq("hE\no")
    found.undo(text)
    text.text.should eq("hello")
    found.redo(text)
    text.text.should eq("hE\no")
  end

  it "maps byte offsets onto clusters" do
    text = buffer("aé👍🏽b\nx")
    text.byte_offset(2).should eq(3)
    text.offset_at_byte(3).should eq(2)
    text.offset_at_byte(4).should eq(2)
    text.offset_at_byte(4, ceil: true).should eq(3)
    text.offset_at_byte(text.text.bytesize).should eq(text.size)
    text.byte_offset(5).should eq(text.text.byte_index('x'))
  end

  it "measures display widths and finds columns within a line" do
    text = buffer("a日本x\nb")
    text.width(0).should eq(6)
    text.width(0, 1, 3).should eq(4)
    text.index(0, 2).should eq(1)
    text.index(0, 3).should eq(2)
    text.index(0, 99).should eq(4)
    text.index(0, 0, from: 2).should eq(2)
  end

  it "finds literal text after an offset, wraps around, and skips matches that split a cluster" do
    text = buffer("ab ab\nab")
    text.find("ab", 0).should eq(0...2)
    text.find("ab", 1).should eq(3...5)
    text.find("ab", 4).should eq(6...8)
    text.find("ab", 7).should eq(0...2)
    text.find("b\na", 0).should eq(4...7)
    text.find("x", 0).should be_nil
    text.find("", 0).should be_nil
    text.find_all("ab").should eq([0...2, 3...5, 6...8])
    buffer("é e").find("e").should eq(2...3)
  end

  it "journals the lines each revision touched" do
    text = buffer("a\nb\nc")
    text.replace(2...3, "x\ny")
    text.replace(0...1, "q")
    text.journal_since(0).should eq([
      Scribe::Buffer::Entry.new(1, 1, 0, 1),
      Scribe::Buffer::Entry.new(2, 0, 0, 0),
    ])
    text.journal_since(2).should eq([] of Scribe::Buffer::Entry)
    text.journal_since(5).should be_nil
  end
end

describe Scribe::Line do
  it "reads clusters, characters and slices by column" do
    row = line("aé👍🏽b")
    row.size.should eq(4)
    row.cluster(2).should eq("👍🏽")
    row.char(1).should eq('é')
    row.slice(1, 3).should eq("é👍🏽")
    row.clusters.should eq(["a", "é", "👍🏽", "b"])
    row.column_at(row.byte_at(3)).should eq(3)
    row.starts_with?("é", 1).should be_true
    row.starts_with?("b", 1).should be_false
    seen = [] of Int32
    row.each_cluster(1, 3) { |_bytes, column| seen << column }
    seen.should eq([1, 2])
  end
end
