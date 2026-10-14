# spec/search_spec.cr
require "./spec_helper"

private def buffer(text : String) : Scribe::Buffer
  Scribe::Buffer.new(clusters(text))
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

  it "anchors ^ and $ to lines" do
    text   = buffer("ab\nab")
    search = Scribe::Search.new("^a", regex: true)
    search.matches(text).should eq([0...1, 3...4])
  end

  it "reports invalid patterns" do
    search = Scribe::Search.new("(", regex: true)
    search.active?.should be_false
    search.error.should_not be_nil
    search.matches(buffer("(")).should be_empty
  end

  it "maps matches onto grapheme clusters" do
    text   = buffer("é👍🏽x é")
    search = Scribe::Search.new("é")
    search.matches(text).should eq([0...1, 4...5])
    Scribe::Search.new("x").matches(text).should eq([2...3])
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
    text   = buffer("key=value")
    search = Scribe::Search.new("(\\w+)=(\\w+)", regex: true)
    range  = search.matches(text).first
    search.expand(text, range, "$2:$1 $$").should eq("value:key $")
    Scribe::Search.new("key").expand(text, 0...3, "$1").should eq("$1")
  end

  it "refreshes its matches when the buffer changes" do
    text   = buffer("aa")
    search = Scribe::Search.new("a")
    search.matches(text).size.should eq(2)
    text.replace(2...2, ["a"])
    search.matches(text).size.should eq(3)
  end
end
