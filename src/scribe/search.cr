# src/scribe/search.cr
module Scribe
  class Search
    REFERENCE = /\$(\$|\d+)/
    NO_RANGES = [] of Range(Int32, Int32)

    getter query           : String
    getter? case_sensitive : Bool
    getter? whole_word     : Bool
    getter? regex          : Bool
    getter error           : String?

    @pattern    : Regex?
    @buffer     : Buffer?
    @revision   : Int32
    @found      : Array(Range(Int32, Int32))
    @lines      : Array(Array(Range(Int32, Int32))?)
    @line_local : Bool

    def initialize(@query : String = "", *, @case_sensitive : Bool = false,
                   @whole_word : Bool = false, @regex : Bool = false)
      @pattern    = nil
      @error      = nil
      @buffer     = nil
      @revision   = -1
      @found      = NO_RANGES
      @lines      = [] of Array(Range(Int32, Int32))?
      @line_local = false
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

    def lined? : Bool
      @regex ? @line_local : !@query.includes?('\n')
    end

    def matches(buffer : Buffer) : Array(Range(Int32, Int32))
      cached = @buffer
      return @found if cached && cached.same?(buffer) && @revision == buffer.revision

      pattern = @pattern
      @found =
        if pattern.nil?
          NO_RANGES
        elsif lined?
          scan_lines(buffer, pattern, cached && cached.same?(buffer) ? buffer.journal_since(@revision) : nil)
        else
          scan_text(buffer, pattern)
        end
      @buffer   = buffer
      @revision = buffer.revision
      @found
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
      @buffer     = nil
      @found      = NO_RANGES
      @lines      = [] of Array(Range(Int32, Int32))?
      @error      = nil
      @pattern    = nil
      @line_local = false
      return if @query.empty?

      source  = @regex ? @query : Regex.escape(@query)
      source  = "\\b(?:#{source})\\b" if @whole_word
      options = Regex::CompileOptions::MULTILINE_ONLY
      options |= Regex::CompileOptions::IGNORE_CASE unless @case_sensitive
      @pattern = Regex.new(source, options)
      @line_local = @regex && local_source?(source)
    rescue error : ArgumentError
      @error = error.message
    end

    private def local_source?(source : String) : Bool
      index = 0
      while index < source.bytesize
        byte = source.byte_at(index)
        return false if byte == 0x0a || byte == 0x0d

        case byte
        when '\\'.ord
          index += 1
          return false if index >= source.bytesize || !local_escape?(source.byte_at(index))
        when '['.ord
          index = local_class(source, index + 1) || return false
          next
        when '('.ord
          if source.byte_at(index + 1)? == '?'.ord
            marker = source.byte_at(index + 2)?
            return false if marker && "aiJmsUx-".includes?(marker.chr)
          end
        end
        index += 1
      end
      true
    end

    private def local_class(source : String, index : Int32) : Int32?
      return nil if source.byte_at(index)? == '^'.ord

      while index < source.bytesize
        byte = source.byte_at(index)
        return nil if byte == 0x0a || byte == 0x0d || byte == '['.ord
        return index + 1 if byte == ']'.ord

        if byte == '\\'.ord
          index += 1
          return nil if index >= source.bytesize || !local_escape?(source.byte_at(index))
        end
        index += 1
      end
      nil
    end

    private def local_escape?(byte : UInt8) : Bool
      char = byte.chr
      return false if "nrsWDRNXCpPxuUov0".includes?(char)

      !char.alphanumeric? || "AbBzZGKEQghkSVwdtfea123456789".includes?(char)
    end

    private def scan_lines(buffer : Buffer, pattern : Regex, journal : Array(Buffer::Entry)?) : Array(Range(Int32, Int32))
      if journal && @lines.size > 0
        journal.each do |entry|
          @lines[entry.line..entry.line + entry.removed] = Array(Array(Range(Int32, Int32))?).new(entry.inserted + 1, nil)
        end
      else
        @lines = Array(Array(Range(Int32, Int32))?).new(buffer.line_count, nil)
      end

      found = [] of Range(Int32, Int32)
      start = 0
      @lines.each_with_index do |cached, index|
        local = cached || (@lines[index] = scan_line(buffer.line(index), pattern))
        local.each { |range| found << ((start + range.begin)...(start + range.end)) }
        start += buffer.line(index).size + 1
      end
      found
    end

    private def scan_line(line : Line, pattern : Regex) : Array(Range(Int32, Int32))
      found = [] of Range(Int32, Int32)
      text  = line.text
      byte  = 0

      while byte <= text.bytesize
        match = pattern.match_at_byte_index(text, byte) || break
        head  = match.byte_begin
        tail  = match.byte_end
        from  = line.column_at(head)
        to    = line.column_at(tail, ceil: true)
        found << (from...to) if to > from
        break if tail == head && from >= line.size
        byte = tail > head ? tail : line.byte_at(from + 1)
      end

      found
    end

    private def scan_text(buffer : Buffer, pattern : Regex) : Array(Range(Int32, Int32))
      found = [] of Range(Int32, Int32)
      text  = buffer.text
      byte  = 0

      while byte <= text.bytesize
        match = pattern.match_at_byte_index(text, byte) || break
        head  = match.byte_begin
        tail  = match.byte_end
        from  = buffer.offset_at_byte(head)
        to    = buffer.offset_at_byte(tail, ceil: true)
        found << (from...to) if to > from
        break if tail == head && from >= buffer.size
        byte = tail > head ? tail : buffer.byte_offset(from + 1)
      end

      found
    end
  end
end
