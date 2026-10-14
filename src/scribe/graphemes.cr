# src/scribe/graphemes.cr
module Scribe
  enum ClusterKind
    Other
    Space
    Word
    Punct
  end

  module Graphemes
    abstract def clusters(text : String) : Array(String)
    abstract def kind(cluster : String) : ClusterKind
    abstract def width(cluster : String) : Int32
  end
end
