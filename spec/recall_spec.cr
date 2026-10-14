# spec/recall_spec.cr
require "./spec_helper"

describe Scribe::Recall do
  it "recalls entries back and forth, keeps the draft and drops duplicates" do
    history = Scribe::Recall.new(["a", "b"], limit: 3)
    history.back("draft").should eq("b")
    history.back("ignored").should eq("a")
    history.back("x").should be_nil
    history.forward.should eq("b")
    history.forward.should eq("draft")
    history.forward.should be_nil
    history.push("a")
    history.push(" ")
    history.push("c")
    history.push("d")
    history.entries.should eq(["a", "c", "d"])
  end

  it "trims its entries when the limit is lowered" do
    history = Scribe::Recall.new(["a", "b", "c"])
    history.limit = 2
    history.entries.should eq(["b", "c"])
    history.browsing?.should be_false
  end
end
