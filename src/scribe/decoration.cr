# src/scribe/decoration.cr
module Scribe
  class Decoration
    getter kind    : String
    getter message : String
    getter source  : String

    def initialize(range : Range(Int32, Int32), @kind : String, @message : String = "", @source : String = "")
      @start = Mark.new(range.begin, Gravity::Right)
      @stop  = Mark.new(Math.max(range.end, range.begin), Gravity::Left)
    end

    def start : Int32
      @start.offset
    end

    def stop : Int32
      Math.max(@stop.offset, @start.offset)
    end

    def range : Range(Int32, Int32)
      start...stop
    end

    def covers?(offset : Int32) : Bool
      start <= offset < stop || (start == stop && offset == start)
    end

    def overlaps?(from : Int32, to : Int32) : Bool
      start < to && from < stop || (start == stop && from <= start <= to)
    end

    protected def source=(value : String) : String
      @source = value
    end

    protected def follow(change : Change) : Nil
      @start.follow(change)
      @stop.follow(change)
    end
  end
end
