# src/scribe/clipboard.cr
module Scribe
  module Clipboard
    abstract def write(text : String) : Nil
    abstract def read(&block : String? -> Nil) : Nil
  end

  class Register
    include Clipboard

    getter text : String

    def initialize(@text : String = "")
    end

    def write(text : String) : Nil
      @text = text
    end

    def read(&block : String? -> Nil) : Nil
      block.call(@text)
    end
  end
end
