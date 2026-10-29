# spec/search_spec.cr
require "./spec_helper"

class Scribe::Search
  getter line_scans : Int32 = 0
  getter text_scans : Int32 = 0

  private def scan_line(line : Line, pattern : Regex) : Array(Range(Int32, Int32))
    @line_scans += 1
    previous_def
  end

  private def scan_text(buffer : Buffer, pattern : Regex) : Array(Range(Int32, Int32))
    @text_scans += 1
    previous_def
  end
end

describe Scribe::Search do
  it "finds literal matches case-insensitively by default" do
    text   = buffer("Foo foo\nfOO bar")
    search = Scribe::Search.new("foo")
    search.matches(text).should eq([0...3, 4...7, 8...11])
    search.case_sensitive = true
    search.matches(text).should eq([4...7])
  end

  it "matches whole words and regular expressions" do
    text   = buffer("cat concat cat5 cat")
    search = Scribe::Search.new("cat", whole_word: true)
    search.matches(text).should eq([0...3, 16...19])
    search.whole_word = false
    search.regex      = true
    search.query      = "c[a-z]+t"
    search.matches(text).should eq([0...3, 4...10, 11...14, 16...19])
  end

  it "anchors ^ and $ to lines and lets a regex span lines" do
    text   = buffer("ab\nab")
    search = Scribe::Search.new("^a", regex: true)
    search.matches(text).should eq([0...1, 3...4])
    search.query = "b\\sa"
    search.matches(text).should eq([1...4])
  end

  it "reports invalid patterns" do
    search = Scribe::Search.new("(", regex: true)
    search.active?.should be_false
    search.error.should_not be_nil
    search.matches(buffer("(")).should be_empty
  end

  it "maps matches onto grapheme clusters" do
    text   = buffer("é👍🏽x é\né")
    search = Scribe::Search.new("é")
    search.matches(text).should eq([0...1, 4...5, 6...7])
    Scribe::Search.new("x").matches(text).should eq([2...3])
    Scribe::Search.new("x", regex: true).matches(text).should eq([2...3])
  end

  it "steps forward and backward with wrapping" do
    text   = buffer("a.a.a")
    search = Scribe::Search.new("a")
    search.next(text, 1).should eq(2...3)
    search.next(text, 5).should eq(0...1)
    search.previous(text, 2).should eq(0...1)
    search.previous(text, 0).should eq(4...5)
    search.index(text, 2...3).should eq(1)
  end

  it "expands capture references in regex replacements" do
    text   = buffer("x\nkey=value")
    search = Scribe::Search.new("(\\w+)=(\\w+)", regex: true)
    range  = search.matches(text).first
    search.expand(text, range, "$2:$1 $$").should eq("value:key $")
    Scribe::Search.new("key").expand(text, 2...5, "$1").should eq("$1")
  end

  it "updates literal matches from the lines an edit touched" do
    text   = buffer("aa\nb\naa")
    search = Scribe::Search.new("a")
    search.matches(text).size.should eq(4)
    text.replace(4...4, "a\nza")
    text.text.should eq("aa\nba\nza\naa")
    search.matches(text).should eq([0...1, 1...2, 4...5, 7...8, 9...10, 10...11])
    text.replace(0...3, "")
    search.matches(text).should eq([1...2, 4...5, 6...7, 7...8])
    search.matches(text).should eq(Scribe::Search.new("a").matches(text))
  end

  it "rescans fully when its journal no longer reaches back" do
    text   = buffer("a")
    search = Scribe::Search.new("a")
    search.matches(text).size.should eq(1)
    (Scribe::Buffer::JOURNAL + 5).times { text.replace(0...0, "a") }
    search.matches(text).size.should eq(text.size)
  end

  it "rescans only touched lines for provably line-local regexes" do
    text   = buffer("a1\nb2\nc3")
    search = Scribe::Search.new("[a-z]\\d", regex: true)
    search.matches(text).should eq([0...2, 3...5, 6...8])
    search.line_scans.should eq(3)
    search.text_scans.should eq(0)

    text.replace(4...4, "x\nz")
    search.matches(text).should eq(Scribe::Search.new("[a-z]\\d", regex: true).matches(text))
    search.line_scans.should eq(5)
    text.replace(0...2, "A9")
    search.matches(text).should eq(Scribe::Search.new("[a-z]\\d", regex: true).matches(text))
    search.line_scans.should eq(6)
  end

  it "keeps potentially multiline regexes on the whole-text path" do
    ["b\\sa", "[^x]", "(?s).*", "\\x0a"].each do |query|
      text   = buffer("ab\nab")
      search = Scribe::Search.new(query, regex: true)
      search.matches(text)
      search.text_scans.should eq(1)
      search.line_scans.should eq(0)
      text.replace(0...0, "x")
      search.matches(text).should eq(Scribe::Search.new(query, regex: true).matches(text))
      search.text_scans.should eq(2)
    end
  end

  it "matches fresh searches after edits and journal overflow" do
    ["^a", "a.*b", "a*", "(\\w+)=(\\d)"].each do |query|
      text   = buffer("ab\na=1\nzz")
      search = Scribe::Search.new(query, regex: true)
      search.matches(text)
      text.replace(2...2, "c\nb")
      text.replace(0...1, "")
      search.matches(text).should eq(Scribe::Search.new(query, regex: true).matches(text))
      (Scribe::Buffer::JOURNAL + 5).times { text.replace(0...0, "a") }
      search.matches(text).should eq(Scribe::Search.new(query, regex: true).matches(text))
    end
  end
end
