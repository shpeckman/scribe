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

  def position_of(offset : Int32) : {Int32, Int32}
    @lines.position_of(offset)
  end

  def offset_in(row : Int32, column : Int32) : Int32
    @lines.offset_in(row, column)
  end

  def page_rows : Int32
    @page
  end
end

describe Scribe::SingleLine do
  it "turns line breaks and tabs into spaces and drops other control characters" do
    Scribe::SingleLine.new.filter("a\r\nb\tc\e").should eq("a b c")
    Scribe::SingleLine.new.filter("plain").should eq("plain")
  end
end

describe Scribe::MultiLine do
  it "keeps line breaks, replaces tabs and drops other control characters" do
    Scribe::MultiLine.new.filter("a\r\nb\tc\e").should eq("a\nb c")
    Scribe::MultiLine.new("    ").filter("\tx").should eq("    x")
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
    layout.position_of(2).should eq({3, 0})
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
    text.layout = Paged.new(Scribe::LineLayout.new(text.buffer, GRAPHEMES), 2)
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
    events.applied.should eq([Scribe::Change.new(2, [] of String, ["X"]), Scribe::Change.new(1, [] of String, ["X"])])
    events.edited.should eq([events.applied])
    events.moves.should eq(2)
    text.undo
    events.edited.last.should eq([Scribe::Change.new(1, ["X"], [] of String), Scribe::Change.new(2, ["X"], [] of String)])
    stop.call
    text.insert("Y")
    events.edited.size.should eq(2)
  end
end
