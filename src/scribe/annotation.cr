# src/scribe/annotation.cr
module Scribe
  enum Placement
    Before
    After
    RowEnd
  end

  class Annotation
    getter text      : String
    getter kind      : String
    getter placement : Placement
    getter source    : String

    def initialize(offset : Int32, @text : String, @placement : Placement = Placement::After,
                   @kind : String = "", @source : String = "")
      @mark = Mark.new(offset, @placement.before? ? Gravity::Right : Gravity::Left)
    end

    def offset : Int32
      @mark.offset
    end

    def before? : Bool
      @placement.before?
    end

    def after? : Bool
      @placement.after?
    end

    def row_end? : Bool
      @placement.row_end?
    end

    protected def source=(value : String) : String
      @source = value
    end

    protected def follow(change : Change) : Nil
      @mark.follow(change)
    end
  end
end
