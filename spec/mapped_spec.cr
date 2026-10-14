# spec/mapped_spec.cr
require "./spec_helper"

WORK = File.join(Dir.tempdir, "scribe-mapped-#{Process.pid}")

private def written(name : String, body : String) : String
  Dir.mkdir_p(WORK)
  path = File.join(WORK, name)
  File.write(path, body)
  path
end

describe Scribe::Mapped do
  after_each { FileUtils.rm_rf(WORK) }

  it "maps a file and hands back its bytes" do
    path = written("a.txt", "hello\nworld")
    Scribe::Mapped.open(path) do |mapped|
      mapped.bytesize.should eq(11)
      mapped.open?.should be_true
      String.new(mapped.bytes).should eq("hello\nworld")
    end
  end

  it "maps an empty file" do
    path = written("empty.txt", "")
    Scribe::Mapped.open(path) do |mapped|
      mapped.bytesize.should eq(0)
      mapped.bytes.should be_empty
    end
  end

  it "closes once and refuses its bytes afterwards" do
    path   = written("b.txt", "x")
    mapped = Scribe::Mapped.new(path)
    mapped.close
    mapped.open?.should be_false
    mapped.close
    expect_raises(Scribe::Mapped::Error) { mapped.bytes }
  end

  it "raises for a file that is not there" do
    expect_raises(File::NotFoundError) { Scribe::Mapped.new(File.join(WORK, "gone")) }
  end
end

describe "Scribe::Buffer.split over bytes" do
  it "splits exactly as the string form does" do
    ["", "a", "a\nb", "\n", "a\n", "\na", "a\n\nb", "one\ntwo\nthree"].each do |text|
      Scribe::Buffer.split(text.to_slice).should eq(Scribe::Buffer.split(text))
    end
  end

  it "keeps multi-byte clusters whole" do
    Scribe::Buffer.split("é\n日本".to_slice).should eq(["é", "日本"])
  end
end

describe "Scribe::Document.open" do
  after_each { FileUtils.rm_rf(WORK) }

  it "builds a document from a mapped file" do
    path = written("c.cr", "def run\n  1\nend")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)

    text.value.should eq("def run\n  1\nend")
    text.buffer.line_count.should eq(3)
    text.buffer.line(1).text.should eq("  1")
    text.cursor.should eq(0)
    text.length.should eq(15)
  end

  it "stays editable, undoable and searchable" do
    path = written("d.cr", "alpha\nbeta")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)

    text.run(Scribe::Command::DocumentEnd)
    text.insert("!")
    text.value.should eq("alpha\nbeta!")
    text.undo
    text.value.should eq("alpha\nbeta")
    text.buffer.find("beta").should eq(6...10)
  end

  it "keeps a CRLF file's ending for export" do
    path = written("e.txt", "one\r\ntwo")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)
    text.line_ending.should eq(Scribe::LineEnding::CRLF)
  end

  it "opens an empty file" do
    path = written("f.txt", "")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)
    text.value.should eq("")
    text.buffer.line_count.should eq(1)
  end

  it "serves every line of a large file" do
    body = Array.new(20_000) { |index| "line #{index}" }.join('\n')
    path = written("big.txt", body)
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)

    text.buffer.line_count.should eq(20_000)
    text.buffer.line(0).text.should eq("line 0")
    text.buffer.line(19_999).text.should eq("line 19999")
    text.length.should eq(body.size)
    text.buffer.position(text.buffer.line_start(500)).line.should eq(500)
  end
end
