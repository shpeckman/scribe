# spec/highlighter_spec.cr
require "./spec_helper"

private def kinds(found : {Array(Scribe::Highlighter::Token), Int32}, text : String) : Array({String, String})
  row = line(text)
  found[0].map { |token| {row.slice(token.start, token.stop), token.kind} }
end

describe Scribe::KeywordHighlighter do
  it "marks keywords, types, numbers, strings and comments" do
    marker = Scribe::KeywordHighlighter.new(%w(def end), comment: "#", suffixes: "?")
    text   = "def ok?(x : Int32) \"a\\\"b\" 0x1F # note"
    kinds(marker.highlight(line(text), 0), text).should eq([
      {"def", "keyword"}, {"Int32", "type"}, {"\"a\\\"b\"", "string"}, {"0x1F", "number"}, {"# note", "comment"},
    ])
  end

  it "counts columns in clusters" do
    marker = Scribe::KeywordHighlighter.new(%w(if))
    text   = "é👍🏽 if"
    kinds(marker.highlight(line(text), 0), text).should eq([{"if", "keyword"}])
    marker.highlight(line(text), 0)[0].first.start.should eq(3)
  end

  it "carries unterminated strings to the next line when asked" do
    marker = Scribe::KeywordHighlighter.new(multiline_strings: true)
    first  = marker.highlight(line("x = \"abc"), 0)
    first[1].should eq('"'.ord)
    second = marker.highlight(line("def\" + 1"), first[1])
    kinds(second, "def\" + 1").should eq([{"def\"", "string"}, {"1", "number"}])
    second[1].should eq(0)
    Scribe::KeywordHighlighter.new.highlight(line("\"open"), 0)[1].should eq(0)
  end

  it "leaves plain identifiers alone" do
    marker = Scribe::KeywordHighlighter.new(%w(if), types: false)
    kinds(marker.highlight(line("Foo if bar"), 0), "Foo if bar").should eq([{"if", "keyword"}])
  end
end

describe Scribe::HighlightCache do
  it "highlights lines on demand and rehighlights the lines after an edit" do
    text  = lines("a\nb\nc")
    cache = Scribe::HighlightCache.new(Scribe::KeywordHighlighter.new(multiline_strings: true))
    text.listen(cache)
    cache.tokens(text.buffer, 2).should be_empty
    text.move(0)
    text.insert("\"")
    cache.tokens(text.buffer, 2).map(&.kind).should eq(["string"])
  end

  it "forgets its tokens when the highlighter changes and returns none without one" do
    text  = document("if x")
    cache = Scribe::HighlightCache.new
    text.listen(cache)
    cache.tokens(text.buffer, 0).should be_empty
    cache.highlighter = Scribe::KeywordHighlighter.new(%w(if))
    cache.tokens(text.buffer, 0).map(&.kind).should eq(["keyword"])
  end
end
