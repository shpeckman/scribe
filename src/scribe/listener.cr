# src/scribe/listener.cr
module Scribe
  module Listener
    def applied(document : Document, change : Change) : Nil
    end

    def edited(document : Document, changes : Array(Change)) : Nil
    end

    def moved(view : View) : Nil
    end

    def decorated(document : Document) : Nil
    end

    def annotated(document : Document) : Nil
    end
  end
end
