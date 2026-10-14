# src/scribe/view/editing.cr
module Scribe
  class View
    PAIRS   = {"(" => ")", "[" => "]", "{" => "}", "\"" => "\"", "'" => "'"}
    CLOSING = {")", "]", "}", "\"", "'"}

    def insert(text : String) : Bool
      @macros.try(&.push(text))
      prepared = @document.prepare(text)
      if @document.auto_close? && (PAIRS.has_key?(prepared) || CLOSING.includes?(prepared))
        return pair(prepared)
      end

      put(prepared)
    end

    def insert_snippet(source : String) : Snippet?
      template = Snippet.parse(@document.prepare(source), @graphemes)
      start    = primary_caret.start
      return nil unless replace_ranges([Edit.new(primary_caret.range, template.text)],
                          History::Kind::Other, [Caret.at(start + count(template.text))])
      return nil if template.spans.empty?

      snippet = Snippet.new(@document, start, template)
      snippet.next_stop(self)
      snippet
    end

    def paste(text : String) : Bool
      normal = LineEnding.normalize(text)
      parts  = normal.chomp.split('\n')
      return put(@document.filter.filter(normal)) unless multiple? && parts.size == @carets.size

      pieces = parts.map { |part| @document.filter.filter(part) }
      @document.apply(self, History::Kind::Other) { |caret, index| Stroke.new(caret.range, pieces[index]) }
    end

    private def put(prepared : String) : Bool
      return false if prepared.empty?

      kind = count(prepared) == 1 && prepared != Buffer::BREAK ? History::Kind::Typing : History::Kind::Other
      @document.apply(self, kind) { |caret, _index| Stroke.new(caret.range, prepared) }
    end

    private def pair(char : String) : Bool
      closer = PAIRS[char]?

      @document.apply(self, History::Kind::Typing) do |caret, _index|
        if caret.empty? && CLOSING.includes?(char) && @buffer.cluster(caret.head) == char
          Stroke.new(caret.head...(caret.head + 1), char)
        elsif closer.nil?
          Stroke.new(caret.range, char)
        elsif !caret.empty?
          Stroke.new(caret.range, char + @buffer.slice_text(caret.range) + closer, 1, 1 + caret.range.size)
        elsif closer == char && kind_at(caret.head - 1).try(&.word?)
          Stroke.new(caret.range, char)
        else
          Stroke.new(caret.range, char + closer, 1, 1)
        end
      end
    end

    private def delete_backward : Nil
      @document.apply(self, History::Kind::Deleting) do |caret, _index|
        head = caret.head
        if !caret.empty?
          Stroke.new(caret.range, "")
        elsif head > 0
          before = @buffer.cluster(head - 1)
          paired = @document.auto_close? && before && PAIRS[before]? == @buffer.cluster(head)
          Stroke.new((head - 1)...(paired ? head + 1 : head), "")
        end
      end
    end

    private def delete_forward : Nil
      @document.apply(self, History::Kind::Deleting) do |caret, _index|
        if !caret.empty?
          Stroke.new(caret.range, "")
        elsif caret.head < length
          Stroke.new(caret.head...(caret.head + 1), "")
        end
      end
    end

    private def delete_subword(direction : Int32) : Nil
      @document.apply(self, History::Kind::Deleting) do |caret, _index|
        if !caret.empty?
          Stroke.new(caret.range, "")
        else
          edge = subword_edge(caret.head, direction)
          edge == caret.head ? nil : Stroke.new(Math.min(edge, caret.head)...Math.max(edge, caret.head), "")
        end
      end
    end

    private def delete_word(direction : Int32) : Nil
      @document.apply(self, History::Kind::Deleting) do |caret, _index|
        if !caret.empty?
          Stroke.new(caret.range, "")
        else
          edge = word_edge(caret.head, direction)
          edge == caret.head ? nil : Stroke.new(Math.min(edge, caret.head)...Math.max(edge, caret.head), "")
        end
      end
    end

    private def delete_to_row(start : Bool) : Nil
      @document.apply(self, History::Kind::Deleting) do |caret, _index|
        if !caret.empty?
          Stroke.new(caret.range, "")
        else
          row  = @layout.row_of(caret.head)
          edge = start ? @layout.row_start(row) : @layout.row_end(row)
          edge == caret.head ? nil : Stroke.new(Math.min(edge, caret.head)...Math.max(edge, caret.head), "")
        end
      end
    end

    private def new_line : Bool
      @document.apply(self, History::Kind::Other) do |caret, _index|
        if @document.auto_indent?
          found = @buffer.position(caret.start)
          line  = @buffer.line(found.line)
          lead  = 0
          while lead < found.column && lead < line.size && @graphemes.kind(line.bytes(lead)).space?
            lead += 1
          end
          Stroke.new(caret.range, Buffer::BREAK + line.slice(0, lead))
        else
          Stroke.new(caret.range, Buffer::BREAK)
        end
      end
    end

    private def tab : Nil
      if @carets.any? { |caret| @buffer.position(caret.start).line != @buffer.position(caret.stop).line }
        indent_lines
      else
        insert(@document.indent)
      end
    end
  end
end
