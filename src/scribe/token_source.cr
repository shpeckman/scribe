# src/scribe/token_source.cr
module Scribe
  module TokenSource
    NO_TOKENS = [] of Token

    abstract def tokens(buffer : Buffer, line : Int32) : Array(Token)
  end

  module Tokenizer
    abstract def tokens(text : String) : Array(Array(Token))
  end
end
