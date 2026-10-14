# src/scribe/macro_log.cr
module Scribe
  class MacroLog
    alias Entry = Command | String

    getter entries : Array(Entry)
    getter? recording : Bool
    getter? replaying : Bool

    def initialize
      @entries   = [] of Entry
      @recording = false
      @replaying = false
    end

    def record : Nil
      return if @replaying

      @entries   = [] of Entry
      @recording = true
    end

    def stop : Nil
      @recording = false
    end

    def empty? : Bool
      @entries.empty?
    end

    def size : Int32
      @entries.size
    end

    def push(entry : Entry) : Nil
      return unless @recording && !@replaying

      @entries << entry
    end

    def replay(view : View, times : Int32 = 1) : Bool
      return false if @entries.empty? || @replaying

      @replaying = true
      applied    = false
      begin
        times.times do
          view.document.transaction do
            @entries.each do |entry|
              applied = (entry.is_a?(Command) ? view.run(entry) : view.insert(entry)) || applied
            end
          end
        end
      ensure
        @replaying = false
      end
      applied
    end
  end
end
