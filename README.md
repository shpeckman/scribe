# scribe

A multi-caret text editing model for Crystal.

scribe holds the text, the carets and the undo history, and carries out editing commands: typing, deleting, word and line motion, multiple carets, box selection, clipboard, line operations, comments, auto-closing brackets, find and replace, and syntax highlighting. It draws nothing and reads no input. The host — a terminal UI, a GUI, a test — implements a few small interfaces, sends commands, and listens for changes.

It has no dependencies beyond the standard library.

## Requirements

- Crystal 1.21 or newer

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  scribe:
    github: shpeckman/scribe
```

Then run `shards install` and require it:

```crystal
require "scribe"
```

## Quick start

A document needs one thing from its host: a `Scribe::Graphemes`, which finds the grapheme cluster boundaries in a string, classifies a cluster and measures its display width.

```crystal
require "scribe"

struct Clusters
  include Scribe::Graphemes

  def boundaries(text : String) : Array(Int32)
    marks = [0]
    text.each_grapheme { |grapheme| marks << marks.last + grapheme.to_s.bytesize }
    marks
  end

  def kind(cluster : Bytes) : Scribe::ClusterKind
    char = String.new(cluster)[0]? || return Scribe::ClusterKind::Other
    return Scribe::ClusterKind::Space if char.whitespace?
    return Scribe::ClusterKind::Word if char.alphanumeric? || char == '_'

    Scribe::ClusterKind::Punct
  end

  def width(cluster : Bytes) : Int32
    1
  end
end

text = Scribe::Document.new(Clusters.new, "hello world", filter: Scribe::MultiLine.new)
text.run(Scribe::Command::WordLeft)
text.insert("big ")
text.value # => "hello big world"
text.undo
text.value # => "hello world"
```

## The document

`Scribe::Document` owns a `Buffer`, the carets and a `History`. Offsets everywhere count grapheme clusters, not bytes or characters; a line break counts as one cluster.

```crystal
text = Scribe::Document.new(graphemes, "one two", max_length: 80, copy_on_select: true)

text.value                 # the text, with \n line breaks
text.value = "replaced"    # undoable; the caret moves to the end
text.cursor                # the head of the primary caret
text.carets                # Array(Scribe::Caret), sorted and merged
text.select_range(0, 3)
text.selected_text
text.place_carets([Scribe::Caret.at(0), Scribe::Caret.at(4)])
text.insert("x")           # typed text, at every caret
text.paste("a\nb")         # one line per caret when the counts match
text.undo
text.redo
```

| Option | Default | Effect |
| --- | --- | --- |
| `filter` | `SingleLine.new` | What happens to incoming text (see Filters) |
| `clipboard` | `Register.new` | Where copy, cut and paste go |
| `layout` | `LineLayout` | How offsets map to rows and columns |
| `max_length` | `nil` | Limit in clusters, shared across carets |
| `indent` | `"  "` | Inserted by `Tab` and `Indent`, removed by `Outdent` |
| `comment` | `nil` | Line comment prefix for `ToggleComment` |
| `tab_size` | `4` | How many leading spaces `Outdent` removes when `indent` is a tab |
| `auto_indent` | `false` | `NewLine` keeps the current line's leading whitespace |
| `auto_close` | `false` | Typing a bracket or quote inserts its pair (see Typing aids) |
| `copyable` | `true` | `false` disables copy and cut, for example for a masked password |
| `copy_on_select` | `false` | Copy a selection as soon as it is made |
| `read_only` | `false` | Refuse edits from commands, `insert`, `paste`, `replace_match` and `replace_all`; motion, selection and copy still work, and `value=` and `replace_ranges` from code still apply |

Every option except `max_length` is also a property; `max_length=` truncates the text when it shrinks. `dragging=` tells the document a pointer drag is in progress, which holds back `copy_on_select` until the host calls `auto_copy` on release.

### Line endings

Text is always held with `\n` breaks. The ending found in the text a document is created with, or given through `value=`, is kept as `line_ending` (`LF`, `CRLF` or `CR`), and `export` returns the text with it:

```crystal
text = Scribe::Document.new(graphemes, "a\r\nb", filter: Scribe::MultiLine.new)
text.value        # => "a\nb"
text.line_ending  # => Scribe::LineEnding::CRLF
text.export       # => "a\r\nb"
```

Pasted and typed `\r\n` and `\r` become `\n` as well.

### Saving, transactions and read-only

```crystal
text.mark_saved
text.modified?     # false until the text changes again; undoing back to the save point clears it

text.transaction do
  text.run(Scribe::Command::DocumentEnd)
  text.insert("\n")
  text.insert("appended")
end                # one undo step, one `moved` and one `edited` notification
```

`transaction` returns the block's value and can be nested; `undo` and `redo` are refused inside one.

### Marks

A `Mark` is an offset that follows edits, for bookmarks, diagnostics or search highlights:

```crystal
spot  = text.mark(10)                              # Scribe::Gravity::Left by default
after = text.mark(10, Scribe::Gravity::Right)
spot.offset
text.unmark(spot)
```

Text inserted exactly at a mark goes after a `Left` mark and before a `Right` mark. A mark inside deleted text moves to where the deletion happened.

## Commands

`run(command, selecting = false)` carries out one `Scribe::Command`. Motion commands extend the selection when `selecting` is true.

| Group | Commands |
| --- | --- |
| Motion | `Left`, `Right`, `WordLeft`, `WordRight`, `RowStart`, `SmartRowStart`, `RowEnd`, `Up`, `Down`, `PageUp`, `PageDown`, `DocumentStart`, `DocumentEnd` |
| Selection | `SelectAll`, `SelectWord`, `SelectLine`, `Collapse` |
| Carets | `AddNextOccurrence`, `SkipOccurrence`, `SelectAllOccurrences`, `AddCaretAbove`, `AddCaretBelow`, `RemoveLastCaret` |
| Box | `BoxUp`, `BoxDown`, `BoxLeft`, `BoxRight` |
| Deleting | `DeleteBackward`, `DeleteForward`, `DeleteWordBackward`, `DeleteWordForward`, `DeleteToRowStart`, `DeleteToRowEnd` |
| Editing | `NewLine`, `Tab`, `Indent`, `Outdent`, `ToggleComment` |
| Lines | `MoveLinesUp`, `MoveLinesDown`, `DuplicateLines`, `DeleteLines` |
| Clipboard | `Copy`, `Cut`, `Paste` |
| History | `Undo`, `Redo` |

`run` returns `true` when the command applied and `false` when it did not, so a host can let the key go on to something else:

- Always `true`: motion, `SelectAll`, `SelectWord`, `SelectLine`, `AddCaretAbove`, `AddCaretBelow`, the `Box` commands, the `Delete` commands, `Tab`, `Copy`, `Cut` and `Paste` — even when there was nothing to delete or copy.
- `false` when there was nothing to do: `Collapse` and `RemoveLastCaret` with one caret; `AddNextOccurrence`, `SkipOccurrence` and `SelectAllOccurrences` without a match; `NewLine`, `Indent`, `Outdent`, `ToggleComment` and the `Lines` commands when the text did not change; `Undo` and `Redo` with an empty stack.
- `false` for every command that edits while the document is read-only.

Notes on individual commands:

- `Up`, `Down`, `PageUp` and `PageDown` remember the column a caret started in, so moving through a short line and on to a long one returns to that column. Any other move or edit forgets it.
- `SmartRowStart` goes to the first non-blank cluster of the row, or to the row start when already there.
- `Tab` indents every line when a selection spans lines, and inserts the indent otherwise. `Outdent` removes one indent, a leading tab, or up to that many spaces.
- `ToggleComment` comments every non-blank line under the carets at their shallowest indentation, or uncomments them when all are commented. It needs the `comment` option.
- `MoveLines*`, `Indent`, `Outdent`, `ToggleComment`, `DuplicateLines` and `DeleteLines` act once per block of lines under the carets.
- `AddNextOccurrence` first selects the word under an empty caret. `SkipOccurrence` moves the most recent caret on to the next occurrence. `SelectAllOccurrences` puts a caret on every occurrence of the selection, or of the word under the caret.
- `Box*` grows a rectangular selection from the primary caret. `start_box(row, column)`, `select_box(anchor_row, anchor_column, head_row, head_column)` and `clear_box` let a host drive it from a pointer; `box` returns the current corners.

Typing is not a command: send `insert(text)`. Pressing Enter in a single-line field is not a command either; the host decides what it means.

### Typing aids

With `auto_close` on, typing `(`, `[`, `{`, `"` or `'` inserts the pair and leaves the caret between them; with a selection it wraps the selection and keeps it selected. Typing a closing character in front of the same character steps over it, a quote typed right after a word stays single, and `DeleteBackward` between an empty pair removes both. Pasted text is never paired.

## Interfaces

The host plugs into a document through these modules. Each is small, and all but `Graphemes` come with a default.

| Interface | Methods | Default |
| --- | --- | --- |
| `Graphemes` | `boundaries(text)`, `kind(cluster : Bytes)`, `width(cluster : Bytes)` | none |
| `Filter` | `filter(text)` | `SingleLine`, `MultiLine(tab)` |
| `Clipboard` | `write(text)`, `read { \|text\| }` | `Register` (in memory) |
| `Layout` | `row_count`, `row_of`, `row_start`, `row_end`, `cell_of`, `offset_in`, `page_rows` | `LineLayout` (one row per line) |
| `Listener` | `applied`, `edited`, `moved` | no-ops to override |

**Graphemes.** `boundaries` returns the byte offset where each cluster starts, followed by the string's byte size, so `""` gives `[0]` and `"ab"` gives `[0, 1, 2]`. `kind` returns a `ClusterKind` (`Space`, `Word`, `Punct` or `Other`), which drives word motion and deletion, word selection, smart Home, auto-indent and how typing is grouped for undo. `width` is the display width in columns. Clusters are passed as byte slices into the document's own storage, so a host can classify and measure them without allocating. Give the document the same measurements your renderer uses.

**Filters.** `SingleLine` turns line breaks and tabs into spaces and drops other control characters. `MultiLine.new(tab)` keeps line breaks and replaces tabs with `tab`. Any struct or class that includes `Filter` works, for example one that only lets digits through.

**Clipboard.** `read` takes a block so a clipboard can answer later, for example after asking a terminal; the paste happens when the block is called.

**Layout.** `cell_of(offset)` returns a `Cell` (`column`, `row`) in display columns, and `offset_in(row, column)` goes back. A host that wraps lines implements `Layout` over its wrapped rows and assigns it with `document.layout = …`; vertical motion, paging (`page_rows`), smart Home, carets above and below and box selection then follow the wrapped rows.

**Listener.** `document.listen(listener)` returns a proc that removes it again.

- `applied(document, change)` runs for each `Change` as it lands, with the buffer in the state right after it. This is the place to update per-line caches such as wrapping.
- `edited(document, changes)` runs once per edit or transaction, after the carets are placed, with every change in the order it was applied. Undo reports the changes it applied.
- `moved(document)` runs whenever the carets change, including after every edit.

## Buffer and changes

`document.buffer` stores each line as one UTF-8 string with its cluster boundaries, and keeps line offsets in a Fenwick tree, so finding a line, its start, or the line of an offset takes logarithmic time.

```crystal
buffer = text.buffer
buffer.line_count
buffer.position(42)          # Scribe::Position(line, column)
buffer.offset(position)
buffer.line_start(3)
buffer.line(3)               # Scribe::Line: text, size, cluster(column), bytes(column), slice(from, to), each_cluster
buffer.width(3, 0, 10)       # display width of columns 0...10 on line 3
buffer.index(3, 12)          # the column under display column 12 on line 3
buffer.find("needle", 10)    # next literal match as a cluster range, wrapping around
buffer.find_all("needle")
```

A `Change` records `from`, the `removed` and `inserted` text, and their sizes in clusters; `removed_lines` and `inserted_lines` count line breaks. When an edit merges with a neighbouring cluster — a combining accent typed after a letter — the change is widened to whole clusters, so undoing it is exact.

`replace_ranges` applies several `Edit`s (a range and its new text) as one undo step and moves the carets with the text:

```crystal
text.replace_ranges([Scribe::Edit.new(0...3, "one"), Scribe::Edit.new(10...10, "!")])
```

Its text is used as given, without the filter.

## Find and replace

`Search` finds matches in a buffer, case-insensitively by default, with optional whole-word and regular-expression modes. Matches are cluster ranges, cached until the buffer changes. A literal search keeps its matches per line and, after an edit, rescans only the lines the edit touched; a regular expression can span lines, so it rescans the whole text.

```crystal
search = Scribe::Search.new("(\\w+)=(\\d)", regex: true)
found  = text.find(search)                          # selects the next match
text.replace_match(search, found.not_nil!, "$2=$1") # only if that match is still selected
text.find(search, backward: true)                   # selects the previous match
text.replace_all(search, "$2=$1")                   # one undo step; returns the count
search.error                                        # the message for an invalid pattern
```

## Highlighting

A `Highlighter` turns one `Line` and a carried-over state into tokens whose columns count clusters. `KeywordHighlighter` covers keywords, capitalised types, numbers, strings (optionally spanning lines) and line comments:

```crystal
marker = Scribe::KeywordHighlighter.new(%w(def end if), comment: "#", suffixes: "?!", multiline_strings: true)
cache  = Scribe::HighlightCache.new(marker)
text.listen(cache)
cache.tokens(text.buffer, 3)   # Array(Scribe::Highlighter::Token): start, count, kind
```

`HighlightCache` highlights lines on demand and forgets only the lines an edit touches. To highlight text outside a document, build a line with `Scribe::Line.new(text, graphemes)`. `text.brackets` returns the offsets of the bracket pair beside an empty primary caret.

## Input recall

`Recall` keeps the entries submitted from a single-line field and steps through them, remembering the draft:

```crystal
past = Scribe::Recall.new(limit: 100)
past.push("ls")
past.back("dra")   # => "ls"
past.forward       # => "dra"
```

## Development

```sh
crystal spec
```

The specs drive documents directly, with a small `Graphemes` built on the standard library in `spec/spec_helper.cr`. `History` takes an optional clock, which the specs use instead of sleeping.

## License

MIT
