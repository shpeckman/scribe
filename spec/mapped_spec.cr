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
      mapped.writable?.should be_false
      String.new(mapped.bytes).should eq("hello\nworld")
    end
  end

  it "writes through a shared mapping" do
    path = written("write.txt", "abc")
    Scribe::Mapped.open(path, writable: true) do |mapped|
      mapped.writable?.should be_true
      mapped.bytes[1] = 'Z'.ord.to_u8
    end
    File.read(path).should eq("aZc")
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
    text.path.should eq(path)
    text.buffer.mapped?.should be_true
    text.buffer.line_count.should eq(3)
    text.buffer.line(1).text.should eq("  1")
    text.buffer.line(1).mapped?.should be_true
    text.cursor.should eq(0)
    text.length.should eq(15)
  end

  it "keeps unchanged lines mapped through edits and undo" do
    path = written("cow.cr", "alpha\nbeta\ngamma")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)

    text.run(Scribe::Command::DocumentEnd)
    text.move(8)
    text.insert("!")
    text.value.should eq("alpha\nbe!ta\ngamma")
    text.buffer.line(0).mapped?.should be_true
    text.buffer.line(1).mapped?.should be_false
    text.buffer.line(2).mapped?.should be_true
    text.undo
    text.value.should eq("alpha\nbeta\ngamma")
    text.buffer.line(0).mapped?.should be_true
    text.buffer.line(1).mapped?.should be_false
    text.buffer.line(2).mapped?.should be_true
  end

  it "reads chunks and literal matches without materializing a line" do
    path = written("lazy.txt", "alpha\nbeta")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)
    row  = text.buffer.line(1)

    row.@text.should be_nil
    text.buffer.chunk(6).should eq("beta".to_slice)
    text.buffer.find("beta").should eq(6...10)
    text.buffer.find_all("a").should eq([0...1, 4...5, 9...10])
    row.@text.should be_nil
    row.text.should eq("beta")
    row.@text.should eq("beta")
  end

  it "indexes and reads non-ASCII mapped lines without caching their text" do
    path = written("unicode.txt", "é👍\n日本")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)
    row  = text.buffer.line(0)

    row.@text.should be_nil
    row.size.should eq(2)
    row.char(1).should eq('👍')
    text.buffer.find("👍").should eq(1...2)
    row.@text.should be_nil
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
    text.buffer.line(0).mapped?.should be_true
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

describe "Scribe::Document#save" do
  after_each { FileUtils.rm_rf(WORK) }

  it "saves to an explicit path, marks the save point, and reloads" do
    text = lines("a\nb")
    text.insert("!")
    expect_raises(ArgumentError) { text.save }
    Dir.mkdir_p(WORK)
    path = File.join(WORK, "new.txt")
    text.save(path)

    File.read(path).should eq("a\nb!")
    text.path.should eq(path)
    text.modified?.should be_false
    reopened = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)
    reopened.value.should eq("a\nb!")
    text.undo
    text.value.should eq("a\nb")
    text.modified?.should be_true
  end

  it "saves a mapped document back to the same file after growth and shrinkage" do
    path = written("same.txt", "one\ntwo\nthree")
    text = Scribe::Document.open(GRAPHEMES, path, filter: Scribe::MultiLine.new)
    text.replace_ranges([Scribe::Edit.new(3...3, "long")])
    text.save

    File.read(path).should eq("onelong\ntwo\nthree")
    text.path.should eq(path)
    text.modified?.should be_false
    text.buffer.line(1).mapped?.should be_true
    text.value = "x"
    text.save
    File.read(path).should eq("x")
    text.value.should eq("x")
    text.undo
    text.value.should eq("onelong\ntwo\nthree")
  end

  it "writes exact LF, CRLF and CR output with a final newline" do
    {Scribe::LineEnding::LF, Scribe::LineEnding::CRLF, Scribe::LineEnding::CR}.each do |ending|
      text = lines("a\nb", final_newline: true)
      text.line_ending = ending
      Dir.mkdir_p(WORK)
      Dir.mkdir_p(WORK)
    path = File.join(WORK, "#{ending.value}.txt")
      text.save(path)
      File.read(path).should eq(lines("a\nb", final_newline: true).tap { |other| other.line_ending = ending }.export)
    end
    File.read(File.join(WORK, "0.txt")).should eq("a\nb\n")
    File.read(File.join(WORK, "1.txt")).should eq("a\r\nb\r\n")
    File.read(File.join(WORK, "2.txt")).should eq("a\rb\r")
  end

  it "saves an empty document as an empty file" do
    text = lines("", final_newline: true)
    Dir.mkdir_p(WORK)
    path = File.join(WORK, "empty-save.txt")
    text.save(path)
    File.read(path).should eq("")
  end

  it "preserves permissions when replacing a file" do
    path = written("permissions.txt", "old")
    File.chmod(path, 0o640)
    text = Scribe::Document.open(GRAPHEMES, path)
    text.insert("new")
    text.save
    File.info(path).permissions.value.should eq(0o640)
    File.read(path).should eq("newold")
  end

  it "cleans up a failed save without changing the document" do
    target = File.join(WORK, "directory")
    Dir.mkdir_p(target)
    text = lines("changed")
    text.insert("!")
    expect_raises(File::Error) { text.save(target) }
    text.modified?.should be_true
    text.path.should be_nil
    Dir.children(WORK).should eq(["directory"])
  end
end
