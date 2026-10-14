# spec/bytes_spec.cr
require "./spec_helper"

private def check(subject : Scribe::Buffer) : Nil
  text = subject.text
  subject.bytesize.should eq(text.bytesize)
  start = 0
  text.split('\n').each_with_index do |part, index|
    subject.line_byte(index).should eq(start)
    start += part.bytesize + 1
  end
  (0..subject.size).each do |offset|
    byte = subject.byte_offset(offset)
    byte.should eq(subject.slice_text(0...offset).bytesize)
    subject.offset_at_byte(byte).should eq(offset)
  end
end

private def read_all(subject : Scribe::Buffer) : String
  io   = IO::Memory.new
  byte = 0
  loop do
    piece = subject.chunk(byte)
    break if piece.empty?
    io.write(piece)
    byte += piece.size
  end
  io.to_s
end

describe "Scribe::Buffer bytes" do
  it "keeps byte offsets right through single-line and multi-line edits" do
    subject = Scribe::Buffer.new(Plain.new, "héllo\nwörld 👍\n\nend")
    check(subject)
    subject.replace(1...2, "éë")
    check(subject)
    subject.replace(3...12, "x\ny\nzé")
    check(subject)
    subject.replace(0...subject.size, "")
    check(subject)
    subject.replace(0...0, "a\n\nb👍")
    check(subject)
  end

  it "survives random edits" do
    random  = Random.new(7)
    pieces  = ["", "a", "é", "👍", "\n", "xy\nz", "\n\n", "é"]
    subject = Scribe::Buffer.new(Plain.new, "start\nmiddle\nend")
    200.times do
      from = random.rand(0..subject.size)
      to   = random.rand(from..Math.min(from + 6, subject.size))
      subject.replace(from...to, pieces.sample(random))
      subject.bytesize.should eq(subject.text.bytesize)
    end
    check(subject)
  end

  it "maps bytes inside a cluster down, or up when asked" do
    subject = Scribe::Buffer.new(Plain.new, "a👍b")
    subject.offset_at_byte(3).should eq(1)
    subject.offset_at_byte(3, ceil: true).should eq(2)
    subject.byte_position(5).should eq(Scribe::Position.new(0, 5))
  end

  it "slices text by byte range" do
    subject = Scribe::Buffer.new(Plain.new, "ab\n\ncé\nz")
    text    = subject.text
    (0..text.bytesize).each do |from|
      (from..text.bytesize).each do |to|
        subject.byte_text(from, to).to_slice.should eq(text.to_slice[from, to - from])
      end
    end
  end

  it "reads the text back in chunks of a line or a break" do
    subject = Scribe::Buffer.new(Plain.new, "ab\n\ncé")
    subject.chunk(0).should eq("ab".to_slice)
    subject.chunk(1).should eq("b".to_slice)
    subject.chunk(2).should eq("\n".to_slice)
    subject.chunk(3).should eq("\n".to_slice)
    subject.chunk(4).should eq("cé".to_slice)
    subject.chunk(subject.bytesize).should be_empty
    read_all(subject).should eq(subject.text)
  end
end

describe Scribe::TokenSource do
  it "is how a highlight cache serves tokens" do
    source = Scribe::HighlightCache.new(Scribe::KeywordHighlighter.new(%w(if))).as(Scribe::TokenSource)
    source.tokens(Scribe::Buffer.new(Plain.new, "if x"), 0).map(&.kind).should eq(["keyword"])
  end
end
