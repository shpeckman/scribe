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

    def boundaries(bytes : Bytes) : Array(Int32)
      boundaries(String.new(bytes))
    end

    abstract def kind(cluster : Bytes) : ClusterKind
    abstract def width(cluster : Bytes) : Int32
  end
end
