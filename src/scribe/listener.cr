# src/scribe/listener.cr
module Scribe
  module Listener
    def applied(document : Document, change : Change) : Nil
    end

    def edited(document : Document, changes : Array(Change)) : Nil
    end

    def moved(document : Document) : Nil
    end
  end
end
