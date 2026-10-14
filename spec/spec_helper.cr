# spec/spec_helper.cr
require "spec"
require "../src/scribe"

struct Plain
  include Scribe::Graphemes

  WIDE = [0x1100..0x115F, 0x2E80..0xA4CF, 0xAC00..0xD7A3, 0xF900..0xFAFF, 0xFF00..0xFF60, 0x1F300..0x1FAFF]

  def boundaries(text : String) : Array(Int32)
    marks = [0]
    text.each_grapheme { |grapheme| marks << marks.last + grapheme.to_s.bytesize }
    marks
  end

  def kind(cluster : Bytes) : Scribe::ClusterKind
    char = String.new(cluster)[0]? || return Scribe::ClusterKind::Other
    return Scribe::ClusterKind::Space if char.whitespace?
    return Scribe::ClusterKind::Word if char.alphanumeric? || char == '_'
    return Scribe::ClusterKind::Other if char.control?

    Scribe::ClusterKind::Punct
  end

  def width(cluster : Bytes) : Int32
    code = String.new(cluster)[0]?.try(&.ord) || return 0
    WIDE.any?(&.includes?(code)) ? 2 : 1
  end
end

class Deferred
  include Scribe::Clipboard

  getter text    : String
  getter pending : Array(Proc(String?, Nil))

  def initialize(@text : String = "")
    @pending = [] of Proc(String?, Nil)
  end

  def write(text : String) : Nil
    @text = text
  end

  def read(&block : String? -> Nil) : Nil
    @pending << block
  end

  def deliver : Nil
    @pending.each(&.call(@text))
    @pending.clear
  end
end

class Recorder
  include Scribe::Listener

  getter applied = [] of Scribe::Change
  getter edited  = [] of Array(Scribe::Change)
  getter moves   = 0
  getter last_view : Scribe::View? = nil

  def applied(document : Scribe::Document, change : Scribe::Change) : Nil
    @applied << change
  end

  def edited(document : Scribe::Document, changes : Array(Scribe::Change)) : Nil
    @edited << changes
  end

  def moved(view : Scribe::View) : Nil
    @moves += 1
    @last_view = view
  end
end

GRAPHEMES = Plain.new

def buffer(text : String) : Scribe::Buffer
  Scribe::Buffer.new(GRAPHEMES, text)
end

def line(text : String) : Scribe::Line
  Scribe::Line.new(text, GRAPHEMES)
end

def document(text : String = "", **options) : Scribe::Document
  Scribe::Document.new(GRAPHEMES, text, **options)
end

def lines(text : String = "", **options) : Scribe::Document
  Scribe::Document.new(GRAPHEMES, text, **options, filter: Scribe::MultiLine.new)
end

def code(text : String = "", **options) : Scribe::Document
  Scribe::Document.new(GRAPHEMES, text, **options, filter: Scribe::MultiLine.new("  "), auto_indent: true)
end

def heads(document : Scribe::Document) : Array(Int32)
  document.carets.map(&.head)
end

def change(from : Int32, removed : String, inserted : String) : Scribe::Change
  Scribe::Change.new(from, removed, inserted, GRAPHEMES.boundaries(removed).size - 1, GRAPHEMES.boundaries(inserted).size - 1)
end

class Noticed
  include Scribe::Listener

  getter annotations = 0

  def annotated(document : Scribe::Document) : Nil
    @annotations += 1
  end
end
