# src/scribe/mark.cr
module Scribe
  class Mark
    getter offset  : Int32
    getter gravity : Gravity

    def initialize(@offset : Int32, @gravity : Gravity = Gravity::Left)
    end

    protected def follow(change : Change) : Nil
      from = change.from
      stop = from + change.removed_size

      @offset =
        if @offset < from
          @offset
        elsif @offset > stop || (@offset == stop && change.removed_size > 0)
          @offset + change.delta
        elsif @gravity.right?
          from + change.inserted_size
        else
          from
        end
    end
  end
end
