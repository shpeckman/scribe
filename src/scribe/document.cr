# src/scribe/document.cr
module Scribe
  class Document
    alias Plan = {Range(Int32, Int32), Array(String)}
    alias Box  = {Int32, Int32, Int32, Int32}

    NONE    = [] of String
    OPENERS = {"(" => ")", "[" => "]", "{" => "}"}
    CLOSERS = {")" => "(", "]" => "[", "}" => "{"}
    REACH   = 20_000

    getter graphemes  : Graphemes
    getter buffer     : Buffer
    getter history    : History
    getter carets     : Array(Caret)
    getter primary    : Int32
    getter max_length : Int32?
    getter box        : Box?

    property filter          : Filter
    property clipboard       : Clipboard
    property layout          : Layout
    property indent          : String
    property? auto_indent    : Bool
    property? copyable       : Bool
    property? copy_on_select : Bool
    property? dragging       : Bool

    @listeners : Array(Listener)

    def self.carry(offset : Int32, plans : Array(Plan)) : Int32
      delta = 0
      plans.each do |plan|
        range, inserted = plan
        return range.begin + delta + inserted.size if range.begin < offset < range.end
        break if offset < range.end || (offset == range.begin && range.size > 0)

        delta += inserted.size - range.size
      end
      offset + delta
    end

    def initialize(@graphemes : Graphemes, text : String = "", *,
                   @filter         : Filter    = SingleLine.new,
                   @clipboard      : Clipboard = Register.new,
                   layout          : Layout?   = nil,
                   @max_length     : Int32?    = nil,
                   @indent         : String    = "  ",
                   @auto_indent    : Bool      = false,
                   @copyable       : Bool      = true,
                   @copy_on_select : Bool      = false)
      clusters = @graphemes.clusters(@filter.filter(text))
      if (max = @max_length) && clusters.size > max
        clusters = clusters[0, max]
      end

      buffer     = Buffer.new(clusters)
      @buffer    = buffer
      @carets    = [Caret.at(buffer.size)]
      @primary   = 0
      @history   = History.new(@graphemes)
      @box       = nil
      @dragging  = false
      @listeners = [] of Listener
      @layout    = layout || LineLayout.new(buffer, @graphemes)
      buffer.on_change { |change| @listeners.dup.each(&.applied(self, change)) }
    end

    def listen(listener : Listener) : Proc(Nil)
      @listeners << listener
      -> { @listeners.delete(listener); nil }
    end

    def value : String
      @buffer.text
    end

    def length : Int32
      @buffer.size
    end

    def primary_caret : Caret
      @carets[@primary]
    end

    def cursor : Int32
      primary_caret.head
    end

    def selection? : Bool
      !primary_caret.empty?
    end

    def selection : Range(Int32, Int32)
      primary_caret.range
    end

    def selected_text : String
      @buffer.slice_text(selection)
    end

    def selected_texts : Array(String)
      @carets.reject(&.empty?).map { |caret| @buffer.slice_text(caret.range) }
    end

    def selected?(offset : Int32) : Bool
      index = @carets.bsearch_index { |caret| caret.stop > offset } || return false
      @carets.unsafe_fetch(index).includes?(offset)
    end

    def multiple? : Bool
      @carets.size > 1
    end

    def value=(value : String) : String
      clusters = limit(split(value))

      if clusters == @buffer.clusters
        seat([Caret.at(length)], 0)
        return self.value
      end

      before  = @carets
      primary = @primary
      change  = @buffer.replace(0...length, clusters)
      seat([Caret.at(length)], 0)
      @history.record(History::Kind::Other, [change], before, primary, @carets, @primary)
      changed([change])
      self.value
    end

    def max_length=(value : Int32?) : Int32?
      return value if @max_length == value

      @max_length = value
      self.value = self.value if value && length > value
      value
    end

    def clear : Nil
      self.value = ""
    end

    def run(command : Command, selecting : Bool = false) : Bool
      case command
      in .left?                then move_carets(selecting) { |caret| step(caret, -1, false, selecting) }
      in .right?               then move_carets(selecting) { |caret| step(caret, 1, false, selecting) }
      in .word_left?           then move_carets(selecting) { |caret| step(caret, -1, true, selecting) }
      in .word_right?          then move_carets(selecting) { |caret| step(caret, 1, true, selecting) }
      in .row_start?           then move_carets(selecting) { |caret| @layout.row_start(@layout.row_of(caret.head)) }
      in .row_end?             then move_carets(selecting) { |caret| @layout.row_end(@layout.row_of(caret.head)) }
      in .up?                  then move_carets(selecting) { |caret| vertical(caret.head, -1) }
      in .down?                then move_carets(selecting) { |caret| vertical(caret.head, 1) }
      in .page_up?             then move_carets(selecting) { |caret| vertical(caret.head, -page) }
      in .page_down?           then move_carets(selecting) { |caret| vertical(caret.head, page) }
      in .select_all?          then select_all
      in .collapse?            then return collapse
      in .add_next_occurrence? then return add_next_occurrence
      in .add_caret_above?     then add_beside(@carets.first.head, -1)
      in .add_caret_below?     then add_beside(@carets.last.head, 1)
      in .box_up?              then box_step(-1, 0)
      in .box_down?            then box_step(1, 0)
      in .box_left?            then box_step(0, -1)
      in .box_right?           then box_step(0, 1)
      in .delete_backward?     then delete_backward
      in .delete_forward?      then delete_forward
      in .new_line?            then return new_line
      in .tab?                 then tab
      in .indent?              then return indent_lines
      in .outdent?             then return outdent_lines
      in .move_lines_up?       then return move_lines(-1)
      in .move_lines_down?     then return move_lines(1)
      in .duplicate_lines?     then return duplicate_lines
      in .delete_lines?        then return delete_lines
      in .copy?                then copy
      in .cut?                 then cut
      in .paste?               then paste_clipboard
      in .undo?                then return undo
      in .redo?                then return redo
      end
      true
    end

    def insert(text : String) : Bool
      clusters = split(text)
      return false if clusters.empty?

      kind = clusters.size == 1 && clusters[0] != Buffer::BREAK ? History::Kind::Typing : History::Kind::Other
      apply(kind) { |caret, _index| {caret.range, clusters} }
    end

    def paste(text : String) : Bool
      parts = text.chomp.split('\n')
      return insert(text) unless multiple? && parts.size == @carets.size

      pieces = parts.map { |part| split(part) }
      apply(History::Kind::Other) { |caret, index| {caret.range, pieces[index]} }
    end

    def replace_ranges(plans : Array(Plan), kind : History::Kind = History::Kind::Other,
                       after : Array(Caret)? = nil) : Bool
      ordered = plans.sort_by { |plan| {plan[0].begin, plan[0].end} }
      floor   = 0
      kept    = [] of Plan

      ordered.each do |plan|
        range, inserted = plan
        from  = range.begin.clamp(floor, length)
        to    = range.end.clamp(from, length)
        floor = to
        kept << {from...to, inserted} unless from == to && inserted.empty?
      end

      return false if kept.empty?

      before  = @carets
      primary = @primary
      changes = [] of Change
      kept.reverse_each { |plan| changes << @buffer.replace(plan[0], plan[1]) }

      after ||= before.map do |caret|
        Caret.new(Document.carry(caret.anchor, kept), Document.carry(caret.head, kept))
      end

      seat(after, primary)
      @history.record(kind, changes, before, primary, @carets, @primary)
      changed(changes)
      true
    end

    def move(index : Int32, selecting : Bool = false) : Nil
      anchor = selecting ? primary_caret.anchor : index
      seat([Caret.new(anchor, index)], 0)
      auto_copy if selecting && !@dragging
    end

    def move_carets(selecting : Bool, & : Caret -> Int32) : Nil
      list = @carets.map do |caret|
        head = yield caret
        selecting ? Caret.new(caret.anchor, head) : Caret.at(head)
      end
      seat(list, @primary)
      auto_copy if selecting && !@dragging
    end

    def select_range(from : Int32, to : Int32) : Nil
      seat([Caret.new(from, to)], 0)
    end

    def select_all : Nil
      select_range(0, length)
      auto_copy
    end

    def place_carets(carets : Array(Caret), primary : Int32 = carets.size - 1) : Nil
      seat(carets, primary)
    end

    def add_caret(head : Int32, anchor : Int32 = head) : Nil
      list = @carets + [Caret.new(anchor, head)]
      seat(list, list.size - 1)
    end

    def collapse : Bool
      return false unless multiple?

      seat([primary_caret], 0)
      true
    end

    def add_next_occurrence : Bool
      lead = primary_caret

      if lead.empty?
        span = word_at(lead.head) || return false
        list = @carets.dup
        list[@primary] = Caret.new(span.begin, span.end)
        seat(list, @primary)
        return true
      end

      search = Search.new(@buffer.slice_text(lead.range), case_sensitive: true)
      found  = search.next(@buffer, lead.stop) || return false
      return false if @carets.any? { |caret| caret.range == found }

      add_caret(found.end, found.begin)
      true
    end

    def undo : Bool
      step = @history.undo(@buffer) || return false
      seat(step.before, step.before_primary)
      changed(step.changes.reverse.map { |change| Change.new(change.from, change.inserted, change.removed) })
      true
    end

    def redo : Bool
      step = @history.redo(@buffer) || return false
      seat(step.after, step.after_primary)
      changed(step.changes)
      true
    end

    def auto_copy : Nil
      copy if @copy_on_select && @carets.any? { |caret| !caret.empty? }
    end

    def start_box(row : Int32, column : Int32) : Nil
      @box = {row, column, row, column}
    end

    def select_box(anchor_row : Int32, anchor_column : Int32, head_row : Int32, head_column : Int32) : Nil
      @box = {anchor_row, anchor_column, head_row, head_column}
      low  = Math.min(anchor_row, head_row)
      high = Math.max(anchor_row, head_row)
      list = (low..high).map do |row|
        Caret.new(@layout.offset_in(row, anchor_column), @layout.offset_in(row, head_column))
      end
      place_carets(list, head_row - low)
    end

    def clear_box : Nil
      @box = nil
    end

    def find(search : Search, backward : Bool = false, from : Int32? = nil) : Range(Int32, Int32)?
      lead  = primary_caret
      start = from || (lead.empty? ? lead.head : lead.start + 1)
      found = backward ? search.previous(@buffer, from || lead.start) : search.next(@buffer, start)
      select_range(found.begin, found.end) if found
      found
    end

    def replace_match(search : Search, match : Range(Int32, Int32), template : String) : Bool
      return false unless match == selection && search.index(@buffer, match)

      replace_ranges([{match, split(search.expand(@buffer, match, template))}])
      true
    end

    def replace_all(search : Search, template : String) : Int32
      found = search.matches(@buffer)
      return 0 if found.empty?

      plans = found.map { |range| {range, split(search.expand(@buffer, range, template))} }
      replace_ranges(plans)
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

    private def delete_backward : Nil
      apply(History::Kind::Deleting) do |caret, _index|
        if !caret.empty?
          {caret.range, NONE}
        elsif caret.head > 0
          {(caret.head - 1)...caret.head, NONE}
        end
      end
    end

    private def delete_forward : Nil
      apply(History::Kind::Deleting) do |caret, _index|
        if !caret.empty?
          {caret.range, NONE}
        elsif caret.head < length
          {caret.head...(caret.head + 1), NONE}
        end
      end
    end

    private def new_line : Bool
      apply(History::Kind::Other) do |caret, _index|
        if @auto_indent
          line, column = @buffer.position(caret.start)
          cells        = @buffer.line(line)
          lead         = 0
          while lead < column && lead < cells.size && @graphemes.kind(cells[lead]).space?
            lead += 1
          end
          {caret.range, [Buffer::BREAK] + cells[0, lead]}
        else
          {caret.range, [Buffer::BREAK]}
        end
      end
    end

    private def tab : Nil
      if @carets.any? { |caret| @buffer.position(caret.start)[0] != @buffer.position(caret.stop)[0] }
        indent_lines
      else
        insert(@indent)
      end
    end

    private def indent_lines : Bool
      indentation = @graphemes.clusters(@indent)
      plans = blocks.flat_map do |(first, last)|
        (first..last).map { |line| {@buffer.line_start(line)...@buffer.line_start(line), indentation} }
      end
      replace_ranges(plans)
    end

    private def outdent_lines : Bool
      plans = [] of Plan
      blocks.each do |(first, last)|
        (first..last).each do |line|
          cells = @buffer.line(line)
          count = 0
          while count < @indent.size && count < cells.size && cells[count] == " "
            count += 1
          end
          start = @buffer.line_start(line)
          plans << {start...(start + count), NONE} if count > 0
        end
      end
      replace_ranges(plans)
    end

    private def move_lines(step : Int32) : Bool
      spans = blocks
      return false if spans.empty?
      return false if step < 0 && spans.first[0] == 0
      return false if step > 0 && spans.last[1] == @buffer.line_count - 1

      plans  = [] of Plan
      shifts = [] of {Int32, Int32, Int32}

      spans.each do |(first, last)|
        block = @buffer.slice(@buffer.line_start(first)...@buffer.line_end(last))
        if step < 0
          other = @buffer.line(first - 1)
          plans << {@buffer.line_start(first - 1)...@buffer.line_end(last), block + [Buffer::BREAK] + other}
          shifts << {@buffer.line_start(first), @buffer.line_end(last), -(other.size + 1)}
        else
          other = @buffer.line(last + 1)
          plans << {@buffer.line_start(first)...@buffer.line_end(last + 1), other + [Buffer::BREAK] + block}
          shifts << {@buffer.line_start(first), @buffer.line_end(last), other.size + 1}
        end
      end

      replace_ranges(plans, after: @carets.map { |caret| Caret.new(shift_by(caret.anchor, shifts), shift_by(caret.head, shifts)) })
    end

    private def duplicate_lines : Bool
      plans  = [] of Plan
      shifts = [] of {Int32, Int32, Int32}
      total  = 0

      blocks.each do |(first, last)|
        start = @buffer.line_start(first)
        stop  = @buffer.line_end(last)
        block = @buffer.slice(start...stop)
        plans << {stop...stop, [Buffer::BREAK] + block}
        shifts << {start, stop, total + block.size + 1}
        total += block.size + 1
      end

      after = @carets.map do |caret|
        Caret.new(shift_by(caret.anchor, shifts), shift_by(caret.head, shifts))
      end
      replace_ranges(plans, after: after)
    end

    private def delete_lines : Bool
      plans = blocks.map do |(first, last)|
        start = @buffer.line_start(first)
        stop  = @buffer.line_end(last)
        if last < @buffer.line_count - 1
          stop += 1
        elsif first > 0
          start -= 1
        end
        {start...stop, NONE}
      end
      replace_ranges(plans)
    end

    private def blocks : Array({Int32, Int32})
      spans = [] of {Int32, Int32}

      @carets.each do |caret|
        first = @buffer.position(caret.start)[0]
        last, column = @buffer.position(caret.stop)
        last -= 1 if last > first && column == 0 && !caret.empty?

        if (previous = spans.last?) && first <= previous[1] + 1
          spans[-1] = {previous[0], Math.max(previous[1], last)}
        else
          spans << {first, last}
        end
      end

      spans
    end

    private def shift_by(offset : Int32, shifts : Array({Int32, Int32, Int32})) : Int32
      shifts.each do |(start, stop, delta)|
        return offset + delta if start <= offset <= stop
      end
      offset
    end

    private def step(caret : Caret, delta : Int32, word : Bool, grow : Bool) : Int32
      if !caret.empty? && !grow && !word
        return delta < 0 ? caret.start : caret.stop
      end

      return (caret.head + delta).clamp(0, length) unless word

      index = caret.head

      if delta < 0
        while index > 0 && kind_at(index - 1).try(&.space?)
          index -= 1
        end
        while index > 0 && kind_at(index - 1).try(&.word?)
          index -= 1
        end
      else
        total = length
        while index < total && kind_at(index).try(&.space?)
          index += 1
        end
        while index < total && kind_at(index).try(&.word?)
          index += 1
        end
      end

      index
    end

    private def vertical(offset : Int32, step : Int32) : Int32
      column, row = @layout.position_of(offset)
      @layout.offset_in((row + step).clamp(0, Math.max(@layout.row_count - 1, 0)), column)
    end

    private def page : Int32
      Math.max(@layout.page_rows, 1)
    end

    private def add_beside(edge : Int32, step : Int32) : Nil
      target = vertical(edge, step)
      add_caret(target) unless @layout.row_of(target) == @layout.row_of(edge)
    end

    private def box_step(rows : Int32, columns : Int32) : Nil
      anchor_row, anchor_column, head_row, head_column = @box || begin
        column, row = @layout.position_of(cursor)
        {row, column, row, column}
      end

      head_row    = (head_row + rows).clamp(0, Math.max(@layout.row_count - 1, 0))
      head_column = Math.max(head_column + columns, 0)
      select_box(anchor_row, anchor_column, head_row, head_column)
    end

    private def seat(list : Array(Caret), lead : Int32) : Nil
      list   = [Caret.at(length)] if list.empty?
      limit  = length
      leader = list[lead.clamp(0, list.size - 1)].clamp(limit)
      sorted = list.map(&.clamp(limit)).sort_by! { |caret| {caret.start, caret.stop} }
      merged = [] of Caret

      sorted.each do |caret|
        last = merged.last?
        if last && (caret.start < last.stop || caret.start == last.start)
          merged[-1] = last.union(caret)
        else
          merged << caret
        end
      end

      @carets  = merged
      @primary = merged.index { |caret| caret.start <= leader.head <= caret.stop } || merged.size - 1
      @listeners.dup.each(&.moved(self))
    end

    private def apply(kind : History::Kind, & : Caret, Int32 -> Plan?) : Bool
      before  = @carets
      primary = @primary
      plans   = Array(Plan?).new(before.size)
      before.each_with_index { |caret, index| plans << yield(caret, index) }

      room  = @max_length.try { |max| max - length + plans.sum { |plan| plan ? plan[0].size : 0 } }
      floor = 0

      plans.map! do |plan|
        next nil unless plan

        range, inserted = plan
        from  = Math.max(range.begin, floor)
        to    = Math.max(range.end, from)
        floor = to

        if left = room
          inserted = inserted[0, Math.max(left, 0)] if inserted.size > left
          room     = left - inserted.size
        end

        from == to && inserted.empty? ? nil : {from...to, inserted}
      end

      return false if plans.all?(&.nil?)

      changes = [] of Change
      plans.reverse_each do |plan|
        changes << @buffer.replace(plan[0], plan[1]) if plan
      end

      delta = 0
      after = before.map_with_index do |caret, index|
        if plan = plans[index]
          range, inserted = plan
          at     = range.begin + delta + inserted.size
          delta += inserted.size - range.size
          Caret.at(at)
        else
          caret.shift(delta)
        end
      end

      seat(after, primary)
      @history.record(kind, changes, before, primary, @carets, @primary)
      changed(changes)
      true
    end

    private def changed(changes : Array(Change)) : Nil
      @listeners.dup.each(&.edited(self, changes))
    end

    private def split(text : String) : Array(String)
      @graphemes.clusters(@filter.filter(text))
    end

    private def limit(clusters : Array(String)) : Array(String)
      max = @max_length
      max && clusters.size > max ? clusters[0, max] : clusters
    end

    private def kind_at(offset : Int32) : ClusterKind?
      @buffer.cluster(offset).try { |cluster| @graphemes.kind(cluster) }
    end

    private def word_at(offset : Int32) : Range(Int32, Int32)?
      left  = offset
      right = offset
      total = length

      while left > 0 && kind_at(left - 1).try(&.word?)
        left -= 1
      end
      while right < total && kind_at(right).try(&.word?)
        right += 1
      end

      left < right ? left...right : nil
    end

    private def copy : Nil
      return unless @copyable

      texts = selected_texts
      @clipboard.write(texts.join('\n')) unless texts.empty?
    end

    private def cut : Nil
      return if !@copyable || @carets.all?(&.empty?)

      copy
      apply(History::Kind::Other) { |caret, _index| caret.empty? ? nil : {caret.range, NONE} }
    end

    private def paste_clipboard : Nil
      @clipboard.read do |text|
        text.try { |found| paste(found) }
        nil
      end
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
