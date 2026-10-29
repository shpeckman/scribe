# src/scribe/clipboard.cr
module Scribe
  module Clipboard
    abstract def write(text : String) : Nil
    abstract def read(&block : String? -> Nil) : Nil
  end

  module ClipboardHistory
    abstract def size : Int32
    abstract def read(index : Int32, &block : String? -> Nil) : Nil
  end

  class Register
    include Clipboard
    include ClipboardHistory

    LIMIT = 100

    getter text    : String
    getter entries : Array(String)

    def initialize(@text : String = "", limit : Int32 = LIMIT)
      @entries = @text.empty? ? [] of String : [@text]
      @limit   = Math.max(limit, 0)
    end

    def size : Int32
      @entries.size
    end

    def write(text : String) : Nil
      @text = text
      @entries.delete(text)
      @entries.unshift(text)
      while @entries.size > @limit
        @entries.pop
      end
    end

    def read(&block : String? -> Nil) : Nil
      read(0, &block)
    end

    def read(index : Int32, &block : String? -> Nil) : Nil
      block.call(@entries[index]?)
    end
  end
end
