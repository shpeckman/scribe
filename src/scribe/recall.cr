# src/scribe/recall.cr
module Scribe
  class Recall
    LIMIT = 100

    getter entries : Array(String)
    getter limit   : Int32

    @index : Int32
    @draft : String

    def initialize(entries : Array(String) = [] of String, @limit : Int32 = LIMIT)
      @limit   = Math.max(@limit, 1)
      @entries = entries.last(@limit)
      @index   = @entries.size
      @draft   = ""
    end

    def limit=(value : Int32) : Int32
      @limit = Math.max(value, 1)
      @entries.shift(@entries.size - @limit) if @entries.size > @limit
      reset
      @limit
    end

    def push(entry : String) : Nil
      unless entry.strip.empty?
        @entries.delete(entry)
        @entries << entry
        @entries.shift if @entries.size > @limit
      end
      reset
    end

    def back(current : String) : String?
      return nil if @index == 0

      @draft = current if @index == @entries.size
      @index -= 1
      @entries[@index]
    end

    def forward : String?
      return nil if @index >= @entries.size

      @index += 1
      @index == @entries.size ? @draft : @entries[@index]
    end

    def browsing? : Bool
      @index < @entries.size
    end

    def reset : Nil
      @index = @entries.size
      @draft = ""
    end
  end
end
