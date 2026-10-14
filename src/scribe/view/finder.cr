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
