# spec/snippet_spec.cr
require "./spec_helper"

private def template(source : String) : Scribe::Snippet::Template
  Scribe::Snippet.parse(source, GRAPHEMES)
end

describe Scribe::Snippet do
  it "parses tabstops, placeholders, the final stop and mirrors" do
    found = template("def $1($2)\n  $0\nend")
    found.text.should eq("def ()\n  \nend")
    found.spans.map { |span| {span.index, span.from, span.to} }.should eq([{1, 4, 4}, {2, 5, 5}, {0, 9, 9}])

    placed = template("${1:name} = ${2:value}")
    placed.text.should eq("name = value")
    placed.spans.map { |span| {span.index, span.from, span.to} }.should eq([{1, 0, 4}, {2, 7, 12}])

    mirrored = template("$1 and $1 again")
    mirrored.text.should eq(" and  again")
    mirrored.spans.size.should eq(2)
  end

  it "keeps escapes, resolves a variable default and takes a choice's first option" do
    template("literal \\$5").text.should eq("literal $5")
    template("${TM_FILE:fallback}").text.should eq("fallback")
    template("$UNKNOWN end").text.should eq(" end")
    template("${1|one,two|}").text.should eq("one")
    template("plain").text.should eq("plain")
  end

  it "counts stop offsets in clusters, not bytes" do
    found = template("é${1:ü}")
    found.text.should eq("éü")
    found.spans.map { |span| {span.from, span.to} }.should eq([{1, 2}])
  end

  it "inserts the text and selects the first stop" do
    text    = lines("")
    snippet = text.view.insert_snippet("def ${1:name}($2)\n  $0\nend").not_nil!

    text.value.should eq("def name()\n  \nend")
    text.selection.should eq(4...8)
    text.selected_text.should eq("name")
    snippet.size.should eq(3)
    snippet.active?.should be_true
  end

  it "steps through the stops and finishes at the final one" do
    text    = lines("")
    snippet = text.view.insert_snippet("${1:a}-${2:b}-$0").not_nil!

    text.selected_text.should eq("a")
    snippet.next_stop(text.view).should be_true
    text.selected_text.should eq("b")
    snippet.next_stop(text.view).should be_true
    text.cursor.should eq(4)
    text.selection?.should be_false
    snippet.next_stop(text.view).should be_false
    snippet.active?.should be_false
  end

  it "steps backwards" do
    text    = lines("")
    snippet = text.view.insert_snippet("${1:a}-${2:b}").not_nil!

    snippet.next_stop(text.view)
    text.selected_text.should eq("b")
    snippet.previous_stop(text.view).should be_true
    text.selected_text.should eq("a")
    snippet.previous_stop(text.view).should be_false
  end

  it "puts a caret on every mirror of a stop so typing fills them together" do
    text    = lines("")
    snippet = text.view.insert_snippet("$1 = $1 + 1").not_nil!

    text.carets.size.should eq(2)
    text.insert("count")
    text.value.should eq("count = count + 1")
    snippet.active?.should be_true
  end

  it "follows the stops through edits made at an earlier stop" do
    text    = lines("")
    snippet = text.view.insert_snippet("${1:a}(${2:b})").not_nil!

    text.insert("longer")
    text.value.should eq("longer(b)")
    snippet.next_stop(text.view).should be_true
    text.selected_text.should eq("b")
  end

  it "replaces the selection it is inserted over, as one undo step" do
    text = lines("old")
    text.select_all
    text.view.insert_snippet("${1:new}").not_nil!
    text.value.should eq("new")

    text.undo
    text.value.should eq("old")
  end

  it "returns nil for a snippet with no stops and still inserts it" do
    text = lines("")
    text.view.insert_snippet("plain text").should be_nil
    text.value.should eq("plain text")
  end

  it "drops its marks when closed" do
    text    = lines("")
    snippet = text.view.insert_snippet("${1:a}${2:b}").not_nil!
    text.marks.size.should eq(4)

    snippet.close
    text.marks.should be_empty
    snippet.active?.should be_false
  end
end
