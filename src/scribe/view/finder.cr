# src/scribe/view/finder.cr
module Scribe
  class View
    OPENERS = {"(" => ")", "[" => "]", "{" => "}"}
    CLOSERS = {")" => "(", "]" => "[", "}" => "{"}
    REACH   = 20_000

    def find(search : Search, backward : Bool = false, from : Int32? = nil) : Range(Int32, Int32)?
      lead  = primary_caret
      start = from || (lead.empty? ? lead.head : lead.start + 1)
      found = backward ? search.previous(@buffer, from || lead.start) : search.next(@buffer, start)
      select_range(found.begin, found.end) if found
      found
    end

    def replace_match(search : Search, match : Range(Int32, Int32), template : String) : Bool
      return false if @document.read_only?
      return false unless match == selection && search.index(@buffer, match)

      replace_ranges([Edit.new(match, @document.prepare(search.expand(@buffer, match, template)))])
      true
    end

    def replace_all(search : Search, template : String) : Int32
      return 0 if @document.read_only?

      found = search.matches(@buffer)
      return 0 if found.empty?

      replace_ranges(found.map { |range| Edit.new(range, @document.prepare(search.expand(@buffer, range, template))) })
      found.size
    end

    def brackets : {Int32, Int32}?
      lead = primary_caret
      return nil unless lead.empty?

      {lead.head - 1, lead.head}.each do |offset|
        cluster = @buffer.cluster(offset) || next
        if closer = OPENERS[cluster]?
          found = scan(offset, 1, cluster, closer)
          return {offset, found} if found
        elsif opener = CLOSERS[cluster]?
          found = scan(offset, -1, cluster, opener)
          return {found, offset} if found
        end
      end
      nil
    end

    private def select_brackets(around : Bool) : Bool
      select_objects { |caret| bracket_object(caret, around) }
    end

    private def select_quotes(around : Bool) : Bool
      select_objects { |caret| quote_object(caret, around) }
    end

    private def select_objects(& : Caret -> Range(Int32, Int32)?) : Bool
      list = @carets.map do |caret|
        found = yield caret
        found ? Caret.new(found.begin, found.end) : caret
      end
      return false if list == @carets

      seat(list, @primary)
      auto_copy
      true
    end

    private def bracket_object(caret : Caret, around : Bool) : Range(Int32, Int32)?
      best = nil.as({Int32, Int32}?)

      OPENERS.each do |opener, closer|
        opening_before(caret, opener, closer).each do |start|
          stop = scan(start, 1, opener, closer) || next
          next unless stop >= caret.stop
          best = {start, stop} if best.nil? || start > best[0]
          break
        end
      end

      best.try do |(start, stop)|
        around ? start...(stop + 1) : (start + 1)...stop
      end
    end

    private def opening_before(caret : Caret, opener : String, closer : String) : Array(Int32)
      direct = caret.empty? ? [caret.head, caret.start, caret.start - 1] : [caret.start, caret.start - 1]
      direct.each do |offset|
        return [offset] if @buffer.cluster(offset) == opener
      end

      depth  = 0
      offset = caret.start - 1
      limit  = REACH
      while offset >= 0 && limit > 0
        cluster = @buffer.cluster(offset)
        if cluster == closer
          depth += 1
        elsif cluster == opener
          return [offset] if depth == 0
          depth -= 1
        end
        offset -= 1
        limit -= 1
      end
      [] of Int32
    end

    private def quote_object(caret : Caret, around : Bool) : Range(Int32, Int32)?
      first = @buffer.position(caret.start)
      last  = @buffer.position(caret.stop)
      return nil unless first.line == last.line

      start = @buffer.line_start(first.line)
      stop  = @buffer.line_end(first.line)
      {'"', '\''}.each do |quote|
        marks = [] of Int32
        offset = start
        while offset < stop
          marks << offset if @buffer.cluster(offset) == quote.to_s && !escaped?(offset, start)
          offset += 1
        end
        marks.each_slice(2) do |pair|
          next unless pair.size == 2
          opening, closing = pair
          next unless opening <= caret.start && closing >= caret.stop
          return around ? opening...(closing + 1) : (opening + 1)...closing
        end
      end
      nil
    end

    private def escaped?(offset : Int32, floor : Int32) : Bool
      count = 0
      offset -= 1
      while offset >= floor && @buffer.cluster(offset) == "\\"
        count += 1
        offset -= 1
      end
      count.odd?
    end

    private def scan(from : Int32, step : Int32, own : String, other : String) : Int32?
      depth  = 0
      offset = from
      limit  = REACH

      while limit > 0
        offset += step
        cluster = @buffer.cluster(offset) || return
        if cluster == own
          depth += 1
        elsif cluster == other
          return offset if depth == 0
          depth -= 1
        end
        limit -= 1
      end
      nil
    end
  end
end
