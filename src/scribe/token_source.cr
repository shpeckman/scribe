# src/scribe/token_source.cr
module Scribe
  module TokenSource
    abstract def tokens(buffer : Buffer, line : Int32) : Array(Highlighter::Token)
  end
end
