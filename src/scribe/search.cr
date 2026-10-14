# src/scribe/search.cr
module Scribe
  class Search
    REFERENCE = /\$(\$|\d+)/

    getter query           : String
    getter? case_sensitive : Bool
    getter? whole_word     : Bool
    getter? regex          : Bool
    getter error           : String?

    @pattern : Regex?
    @cache   : {Buffer, Int32, Array(Range(Int32, Int32))}?

    def initialize(@query : String = "", *, @case_sensitive : Bool = false,
                   @whole_word : Bool = false, @regex : Bool = false)
      @pattern = nil
      @error   = nil
      @cache   = nil
      compile
    end

    def query=(value : String) : String
      return value if value == @query

      @query = value
      compile
      value
    end

    def case_sensitive=(value : Bool) : Bool
      @case_sensitive = value
      compile
      value
    end

    def whole_word=(value : Bool) : Bool
      @whole_word = value
      compile
      value
    end

    def regex=(value : Bool) : Bool
      @regex = value
      compile
      value
    end

    def active? : Bool
      !@pattern.nil?
    end

    def matches(buffer : Buffer) : Array(Range(Int32, Int32))
      if (cache = @cache) && cache[0].same?(buffer) && cache[1] == buffer.revision
        return cache[2]
      end

      found  = scan(buffer)
      @cache = {buffer, buffer.revision, found}
      found
    end

    def next(buffer : Buffer, from : Int32) : Range(Int32, Int32)?
      found = matches(buffer)
      found.find { |range| range.begin >= from } || found.first?
    end

    def previous(buffer : Buffer, from : Int32) : Range(Int32, Int32)?
      found = matches(buffer)
      found.reverse_each { |range| return range if range.begin < from }
      found.last?
    end

    def index(buffer : Buffer, range : Range(Int32, Int32)) : Int32?
      matches(buffer).index(range)
    end

    def expand(buffer : Buffer, range : Range(Int32, Int32), template : String) : String
      pattern = @pattern
      return template unless @regex && pattern

      text  = buffer.text
      found = pattern.match_at_byte_index(text, buffer.byte_offset(range.begin), Regex::MatchOptions::ANCHORED) || return template

      template.gsub(REFERENCE) do |_text, capture|
        name = capture[1]
        name == "$" ? "$" : (found[name.to_i]? || "")
      end
    end

    private def compile : Nil
      @cache   = nil
      @error   = nil
      @pattern = nil
      return if @query.empty?

      source  = @regex ? @query : Regex.escape(@query)
      source  = "\\b(?:#{source})\\b" if @whole_word
      options = Regex::CompileOptions::MULTILINE_ONLY
      options |= Regex::CompileOptions::IGNORE_CASE unless @case_sensitive
      @pattern = Regex.new(source, options)
    rescue error : ArgumentError
      @error = error.message
    end

    private def scan(buffer : Buffer) : Array(Range(Int32, Int32))
      found   = [] of Range(Int32, Int32)
      pattern = @pattern || return found
      text    = buffer.text
      byte    = 0

      while byte <= text.bytesize
        match = pattern.match_at_byte_index(text, byte) || break
        head  = match.byte_begin
        tail  = match.byte_end
        from  = buffer.offset_at_byte(head)
        to    = buffer.offset_at_byte(tail, ceil: true)
        found << (from...to) if to > from
        byte = tail > head ? tail : buffer.byte_offset(from + 1)
        break if tail == head && from >= buffer.size
      end

      found
    end
  end
end
