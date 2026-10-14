# scribe

A multi-caret text editing model for Crystal.

scribe holds the text, the carets and the undo history, and carries out editing commands: typing, deleting, word and line motion, multiple carets, box selection, clipboard, line operations, find and replace, and syntax highlighting. It draws nothing and reads no input. The host — a terminal UI, a GUI, a test — implements a few small interfaces, sends commands, and listens for changes.

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

A document needs one thing from its host: a `Scribe::Graphemes`, which splits text into grapheme clusters, classifies them and measures their display width.

```crystal
require "scribe"

struct Clusters
  include Scribe::Graphemes

  def clusters(text : String) : Array(String)
    text.graphemes.map(&.to_s)
  end

  def kind(cluster : String) : Scribe::ClusterKind
    char = cluster[0]? || return Scribe::ClusterKind::Other
    return Scribe::ClusterKind::Space if char.whitespace?
    return Scribe::ClusterKind::Word if char.alphanumeric? || char == '_'

    Scribe::ClusterKind::Punct
  end

  def width(cluster : String) : Int32
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

`Scribe::Document` owns a `Buffer` (the text as grapheme clusters, split into lines), the carets, and a `History`. Offsets everywhere count clusters, not bytes or characters.

```crystal
text = Scribe::Document.new(graphemes, "one two", max_length: 80, copy_on_select: true)

text.value                 # the text
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
| `auto_indent` | `false` | `NewLine` keeps the current line's leading spaces |
| `copyable` | `true` | `false` disables copy and cut, for example for a masked password |
| `copy_on_select` | `false` | Copy a selection as soon as it is made |

Every option except `max_length` is also a property; `max_length=` truncates the text when it shrinks. `dragging=` tells the document a pointer drag is in progress, which holds back `copy_on_select` until the host calls `auto_copy` on release.

## Commands

`run(command, selecting = false)` carries out one `Scribe::Command` and returns whether it did anything that should stop the key from being handled further. Motion commands extend the selection when `selecting` is true.

| Group | Commands |
| --- | --- |
| Motion | `Left`, `Right`, `WordLeft`, `WordRight`, `RowStart`, `RowEnd`, `Up`, `Down`, `PageUp`, `PageDown` |
| Carets | `SelectAll`, `Collapse`, `AddNextOccurrence`, `AddCaretAbove`, `AddCaretBelow`, `BoxUp`, `BoxDown`, `BoxLeft`, `BoxRight` |
| Editing | `DeleteBackward`, `DeleteForward`, `NewLine`, `Tab`, `Indent`, `Outdent` |
| Lines | `MoveLinesUp`, `MoveLinesDown`, `DuplicateLines`, `DeleteLines` |
| Clipboard | `Copy`, `Cut`, `Paste` |
| History | `Undo`, `Redo` |

- `Collapse` reports `false` when there is only one caret, so a host can let Escape through.
- `Tab` indents every line when a selection spans lines, and inserts the indent otherwise.
- `MoveLines*`, `Indent`, `Outdent`, `DuplicateLines` and `DeleteLines` act once per block of lines under the carets.
- `Box*` grows a rectangular selection from the primary caret. `start_box(row, column)`, `select_box(anchor_row, anchor_column, head_row, head_column)` and `clear_box` let a host drive it from a pointer; `box` returns the current corners.

Typing is not a command: send `insert(text)`. Pressing Enter in a single-line field is not a command either; the host decides what it means.

## Interfaces

The host plugs into a document through these modules. Each is small, and all but `Graphemes` come with a default.

| Interface | Methods | Default |
| --- | --- | --- |
| `Graphemes` | `clusters(text)`, `kind(cluster)`, `width(cluster)` | none |
| `Filter` | `filter(text)` | `SingleLine`, `MultiLine(tab)` |
| `Clipboard` | `write(text)`, `read { \|text\| }` | `Register` (in memory) |
| `Layout` | `row_count`, `row_of`, `row_start`, `row_end`, `position_of`, `offset_in`, `page_rows` | `LineLayout` (one row per line) |
| `Listener` | `applied`, `edited`, `moved` | no-ops to override |

**Graphemes.** `kind` returns a `ClusterKind` (`Space`, `Word`, `Punct` or `Other`), which drives word motion, word selection, auto-indent and how typing is grouped for undo. `width` is the display width in columns, used by the default layout. Give the document the same measurements your renderer uses.

**Filters.** `SingleLine` turns line breaks and tabs into spaces and drops other control characters. `MultiLine.new(tab)` keeps line breaks and replaces tabs with `tab`. Any struct or class that includes `Filter` works, for example one that only lets digits through.

**Clipboard.** `read` takes a block so a clipboard can answer later, for example after asking a terminal; the paste happens when the block is called.

**Layout.** Positions are `{column, row}` in display columns. A host that wraps lines implements `Layout` over its wrapped rows and assigns it with `document.layout = …`; vertical motion, paging (`page_rows`), carets above and below and box selection then follow the wrapped rows.

**Listener.** `document.listen(listener)` returns a proc that removes it again.

- `applied(document, change)` runs for each `Change` as it lands, with the buffer in the state right after it. This is the place to update per-line caches such as wrapping.
- `edited(document, changes)` runs once per edit, after the carets are placed, with every change in the order it was applied. Undo reports the inverse changes.
- `moved(document)` runs whenever the carets change, including after every edit.

## Find and replace

`Search` finds matches in a buffer, case-insensitively by default, with optional whole-word and regular-expression modes. Matches are cluster ranges and are cached until the buffer changes.

```crystal
search = Scribe::Search.new("(\\w+)=(\\d)", regex: true)
found  = text.find(search)                          # selects the next match
text.replace_match(search, found.not_nil!, "$2=$1") # only if that match is still selected
text.find(search, backward: true)                   # selects the previous match
text.replace_all(search, "$2=$1")                   # one undo step; returns the count
search.error                                        # the message for an invalid pattern
```

## Highlighting

A `Highlighter` turns one line of clusters and a carried-over state into tokens. `KeywordHighlighter` covers keywords, capitalised types, numbers, strings (optionally spanning lines) and line comments:

```crystal
marker = Scribe::KeywordHighlighter.new(%w(def end if), comment: "#", suffixes: "?!", multiline_strings: true)
cache  = Scribe::HighlightCache.new(marker)
text.listen(cache)
cache.tokens(text.buffer, 3)   # Array(Scribe::Highlighter::Token): start, count, kind
```

`HighlightCache` highlights lines on demand and forgets only the lines an edit touches. `text.brackets` returns the offsets of the bracket pair beside an empty primary caret.

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

The specs drive documents directly, with a small `Graphemes` built on the standard library in `spec/spec_helper.cr`.

## License

MIT
