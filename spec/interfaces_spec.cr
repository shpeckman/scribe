# spec/interfaces_spec.cr
require "./spec_helper"

private class Paged
  include Scribe::Layout

  def initialize(@lines : Scribe::LineLayout, @page : Int32)
  end

  def row_count : Int32
    @lines.row_count
  end

  def row_of(offset : Int32) : Int32
    @lines.row_of(offset)
  end

  def row_start(row : Int32) : Int32
    @lines.row_start(row)
  end

  def row_end(row : Int32) : Int32
    @lines.row_end(row)
  end

  def cell_of(offset : Int32) : Scribe::Cell
    @lines.cell_of(offset)
  end

  def offset_in(row : Int32, column : Int32) : Int32
    @lines.offset_in(row, column)
  end

  def page_rows : Int32
    @page
  end
end

private struct Digits
  include Scribe::Filter

  def filter(text : String) : String
    text.delete { |char| !char.ascii_number? }
  end
end

describe Scribe::SingleLine do
  it "turns line breaks and tabs into spaces and drops other control characters" do
    Scribe::SingleLine.new.filter("a\nb\tc\e").should eq("a b c")
    Scribe::SingleLine.new.filter("plain").should eq("plain")
  end
end

describe Scribe::MultiLine do
  it "keeps line breaks, replaces tabs and drops other control characters" do
    Scribe::MultiLine.new.filter("a\nb\tc\e").should eq("a\nb c")
    Scribe::MultiLine.new("    ").filter("\tx").should eq("    x")
  end
end

describe Scribe::Filter do
  it "lets a host decide what text a document accepts" do
    text = document("a1b2", filter: Digits.new)
    text.value.should eq("12")
    text.insert("x3")
    text.value.should eq("123")
  end
end

describe Scribe::LineEnding do
  it "detects the most common line ending and normalizes to line feeds" do
    Scribe::LineEnding.detect("a\r\nb\r\nc\nd").should eq(Scribe::LineEnding::CRLF)
    Scribe::LineEnding.detect("a\rb").should eq(Scribe::LineEnding::CR)
    Scribe::LineEnding.detect("a\nb").should eq(Scribe::LineEnding::LF)
    Scribe::LineEnding.normalize("a\r\nb\rc").should eq("a\nb\nc")
  end
end

describe Scribe::Register do
  it "keeps the last text written and reads it back at once" do
    register = Scribe::Register.new
    register.write("hey")
    found = nil.as(String?)
    register.read { |text| found = text; nil }
    found.should eq("hey")
  end
end

describe Scribe::LineLayout do
  it "maps offsets to rows and display columns, counting wide clusters twice" do
    text   = lines("a日本\nxy")
    layout = text.layout
    layout.row_count.should eq(2)
    layout.row_of(4).should eq(1)
    layout.row_start(1).should eq(4)
    layout.row_end(0).should eq(3)
    layout.row_end(9).should eq(6)
    layout.cell_of(2).should eq(Scribe::Cell.new(3, 0))
    layout.offset_in(0, 2).should eq(1)
    layout.offset_in(0, 3).should eq(2)
    layout.offset_in(0, 99).should eq(3)
    layout.offset_in(1, 1).should eq(5)
    layout.page_rows.should eq(1)
  end
end

describe Scribe::Layout do
  it "drives vertical motion and paging through the host's layout" do
    text = lines((1..6).join('\n'))
    text.layout = Paged.new(Scribe::LineLayout.new(text.buffer), 2)
    text.move(0)
    text.run(Scribe::Command::PageDown)
    text.layout.row_of(text.cursor).should eq(2)
    text.run(Scribe::Command::PageDown, selecting: true)
    text.selected_text.should eq("3\n4\n")
    text.run(Scribe::Command::PageUp)
    text.layout.row_of(text.cursor).should eq(2)
  end
end

describe Scribe::Listener do
  it "hears every change as it lands, every batch once its carets are seated, and every caret move" do
    text   = document("ab")
    events = Recorder.new
    stop   = text.listen(events)
    text.place_carets([Scribe::Caret.at(1), Scribe::Caret.at(2)])
    text.insert("X")
    events.applied.should eq([change(2, "", "X"), change(1, "", "X")])
    events.edited.should eq([events.applied])
    events.moves.should eq(2)
    text.undo
    events.edited.last.should eq([change(1, "X", ""), change(2, "X", "")])
    stop.call
    text.insert("Y")
    events.edited.size.should eq(2)
  end
end
