# spec/buffer_spec.cr
require "./spec_helper"

private def buffer(text : String) : Scribe::Buffer
  Scribe::Buffer.new(text.chars.map(&.to_s))
end

describe Scribe::Buffer do
  it "splits its text into lines and maps offsets to positions" do
    text = buffer("ab\ncde\n")
    text.size.should eq(7)
    text.line_count.should eq(3)
    text.line(1).should eq(["c", "d", "e"])
    text.line_start(2).should eq(7)
    text.line_end(1).should eq(6)
    text.position(0).should eq({0, 0})
    text.position(2).should eq({0, 2})
    text.position(3).should eq({1, 0})
    text.position(7).should eq({2, 0})
    text.position(99).should eq({2, 0})
    text.offset(1, 2).should eq(5)
    text.offset(1, 9).should eq(6)
    text.cluster(2).should eq("\n")
    text.cluster(4).should eq("d")
    text.cluster(7).should be_nil
  end

  it "slices across lines" do
    text = buffer("ab\ncde\nf")
    text.slice_text(1...5).should eq("b\ncd")
    text.slice_text(3...6).should eq("cde")
    text.slice(4...4).should be_empty
    text.slice_text(0...99).should eq("ab\ncde\nf")
  end

  it "replaces ranges spanning lines and reports the change" do
    text    = buffer("ab\ncde\nf")
    changes = [] of Scribe::Change
    stop    = text.on_change { |change| changes << change; nil }
    change  = text.replace(1...5, ["X", "\n", "Y"])
    text.text.should eq("aX\nYe\nf")
    text.line_count.should eq(3)
    text.line_start(2).should eq(6)
    change.should eq(Scribe::Change.new(1, ["b", "\n", "c", "d"], ["X", "\n", "Y"]))
    changes.should eq([change])
    stop.call
    text.replace(0...text.size, [] of String)
    changes.size.should eq(1)
    text.text.should eq("")
    text.line_count.should eq(1)
    text.clusters.should be_empty
  end

  it "undoes and redoes its changes" do
    text   = buffer("hello")
    change = text.replace(1...4, ["E", "\n"])
    text.text.should eq("hE\no")
    change.undo(text)
    text.text.should eq("hello")
    change.redo(text)
    text.text.should eq("hE\no")
  end

  it "maps byte offsets onto clusters" do
    text = Scribe::Buffer.new(clusters("aé👍🏽b"))
    text.byte_offset(2).should eq(3)
    text.offset_at_byte(3).should eq(2)
    text.offset_at_byte(4).should eq(2)
    text.offset_at_byte(4, ceil: true).should eq(3)
  end

  it "finds clusters after an offset and wraps around" do
    text = buffer("ab ab\nab")
    text.find(["a", "b"], 0).should eq(0)
    text.find(["a", "b"], 1).should eq(3)
    text.find(["a", "b"], 4).should eq(6)
    text.find(["a", "b"], 7).should eq(0)
    text.find(["b", "\n", "a"], 0).should eq(4)
    text.find(["x"], 0).should be_nil
    text.find([] of String, 0).should be_nil
  end
end
