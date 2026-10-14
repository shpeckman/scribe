# src/scribe/graphemes.cr
module Scribe
  enum ClusterKind
    Other
    Space
    Word
    Punct
  end

  module Graphemes
    abstract def boundaries(text : String) : Array(Int32)
    abstract def kind(cluster : Bytes) : ClusterKind
    abstract def width(cluster : Bytes) : Int32
  end
end
