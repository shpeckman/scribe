# scribe

A multi-caret text editing model for Crystal.

scribe holds the text, the carets and the undo history, and carries out editing commands: typing, deleting, word and subword motion, multiple carets, box selection, clipboard, line operations and transforms, comments, auto-closing brackets, snippets with tabstops, folding, and find and replace. One document can carry several views, each with its own carets and layout. It draws nothing, reads no input and highlights nothing: syntax tokens come from a host-supplied `TokenSource`, such as the one in [treesitter](https://github.com/shpeckman/treesitter.cr). The host — a terminal UI, a GUI, a test — implements a few small interfaces, sends commands, and listens for changes.

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

## Documents and views

A `Document` owns the text, the undo `History`, the marks, the decorations and the annotations. A `View` owns the carets, the goal column, the box selection and the `Layout`, and carries out every command. A document has one view from the start, and `Document` delegates the whole caret and editing API to it, so a single-view host never mentions `View` at all.

```crystal
text  = Scribe::Document.new(graphemes, "one two", filter: Scribe::MultiLine.new)
text.insert("x")             # goes to text.view
other = Scribe::View.new(text)
other.select_range(0, 3)     # its own carets, its own layout
text.views.size              # => 2
other.close                  # stops following the document
```

Two views share the text and the history: an edit from either one shows in both, the other's carets are carried through it as marks are, and `undo` from either one seats the carets it recorded. `view.layout = …` is per view, so two panes can wrap the same document at different widths.

Offsets everywhere count grapheme clusters, not bytes or characters; a line break counts as one cluster.

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
| `final_newline` | `false` | `export` ends the text with one line ending |

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
| Motion | `Left`, `Right`, `WordLeft`, `WordRight`, `SubwordLeft`, `SubwordRight`, `RowStart`, `SmartRowStart`, `RowEnd`, `Up`, `Down`, `PageUp`, `PageDown`, `DocumentStart`, `DocumentEnd` |
| Selection | `SelectAll`, `SelectWord`, `SelectLine`, `SelectInsideBrackets`, `SelectAroundBrackets`, `SelectInsideQuotes`, `SelectAroundQuotes`, `Collapse` |
| Carets | `AddNextOccurrence`, `SkipOccurrence`, `SelectAllOccurrences`, `AddCaretAbove`, `AddCaretBelow`, `AddCaretPerLine`, `RemoveLastCaret` |
| Box | `BoxUp`, `BoxDown`, `BoxLeft`, `BoxRight` |
| Deleting | `DeleteBackward`, `DeleteForward`, `DeleteWordBackward`, `DeleteWordForward`, `DeleteSubwordBackward`, `DeleteSubwordForward`, `DeleteToRowStart`, `DeleteToRowEnd` |
| Editing | `NewLine`, `Tab`, `Indent`, `Outdent`, `ToggleComment`, `DuplicateSelection` |
| Lines | `MoveLinesUp`, `MoveLinesDown`, `DuplicateLines`, `DeleteLines`, `SortLines`, `ReverseLines`, `UniqueLines`, `JoinLines`, `TrimTrailingWhitespace` |
| Case | `UpperCase`, `LowerCase`, `TitleCase` |
| Clipboard | `Copy`, `Cut`, `Paste`, `PastePrevious` |
| History | `Undo`, `Redo` |

`run` returns `true` when the command applied and `false` when it did not, so a host can let the key go on to something else:

- Always `true`: motion, `SelectAll`, `SelectWord`, `SelectLine`, `AddCaretAbove`, `AddCaretBelow`, the `Box` commands, the `Delete` commands, `Tab`, `Copy`, `Cut` and `Paste` — even when there was nothing to delete or copy.
- `false` when there was nothing to do: `Collapse` and `RemoveLastCaret` with one caret; the bracket and quote selection commands with no target; `AddNextOccurrence`, `SkipOccurrence` and `SelectAllOccurrences` without a match; `DuplicateSelection` with no selections; `PastePrevious` without an active paste or older entry; `NewLine`, `Indent`, `Outdent`, `ToggleComment` and the `Lines` commands when the text did not change; `Undo` and `Redo` with an empty stack.
- `false` for every command that edits while the document is read-only.

Notes on individual commands:

- `Up`, `Down`, `PageUp` and `PageDown` remember the column a caret started in, so moving through a short line and on to a long one returns to that column. Any other move or edit forgets it.
- `SmartRowStart` goes to the first non-blank cluster of the row, or to the row start when already there.
- `SelectInsideBrackets` and `SelectAroundBrackets` select the innermost balanced pair around every caret, excluding or including its delimiters. The quote equivalents pair unescaped single or double quotes on one line.
- `DuplicateSelection` inserts a copy immediately after every nonempty selection and selects the copies, preserving their direction. Empty carets stay unchanged.
- `Tab` indents every line when a selection spans lines, and inserts the indent otherwise. `Outdent` removes one indent, a leading tab, or up to that many spaces.
- `ToggleComment` comments every non-blank line under the carets at their shallowest indentation, or uncomments them when all are commented. It needs the `comment` option.
- `MoveLines*`, `Indent`, `Outdent`, `ToggleComment`, `DuplicateLines` and `DeleteLines` act once per block of lines under the carets.
- `AddNextOccurrence` first selects the word under an empty caret. `SkipOccurrence` moves the most recent caret on to the next occurrence. `SelectAllOccurrences` puts a caret on every occurrence of the selection, or of the word under the caret.
- `SubwordLeft` and `SubwordRight` stop at camelCase humps, underscores and the start of a word, so `fooBar_baz` has four stops.
- `SortLines`, `ReverseLines`, `UniqueLines` and `TrimTrailingWhitespace` act on the whole block of lines under the carets and return `false` when nothing changed. `JoinLines` joins the block, or the next line when a caret is empty.
- `UpperCase`, `LowerCase` and `TitleCase` transform each selection and keep it selected; without a selection they do nothing.
- `AddCaretPerLine` puts a caret at the end of every line a selection spans.
- `PastePrevious` replaces the immediately preceding paste with the next older clipboard entry; repeated calls keep cycling. Moving, editing or starting another paste ends that session.
- `Box*` grows a rectangular selection from the primary caret. `start_box(row, column)`, `select_box(anchor_row, anchor_column, head_row, head_column)` and `clear_box` let a host drive it from a pointer; `box` returns the current corners.

Typing is not a command: send `insert(text)`. Pressing Enter in a single-line field is not a command either; the host decides what it means.

### Typing aids

With `auto_close` on, typing `(`, `[`, `{`, `"` or `'` inserts the pair and leaves the caret between them; with a selection it wraps the selection and keeps it selected. Typing a closing character in front of the same character steps over it, a quote typed right after a word stays single, and `DeleteBackward` between an empty pair removes both. Pasted text is never paired.

## Interfaces

The host plugs into a document through these modules. Each is small, and all but `Graphemes` come with a default.

| Interface | Methods | Default |
| --- | --- | --- |
| `Graphemes` | `boundaries(text)`, optional `boundaries(bytes)`, `kind(cluster : Bytes)`, `width(cluster : Bytes)` | byte boundaries fall back to a string copy |
| `Filter` | `filter(text)` | `SingleLine`, `MultiLine(tab)` |
| `Clipboard` | `write(text)`, `read { \|text\| }` | `Register` (in memory) |
| `Layout` | `row_count`, `row_of`, `row_start`, `row_end`, `cell_of`, `offset_in`, `page_rows` | `LineLayout` (one row per line) |
| `Listener` | `applied`, `edited`, `moved`, `decorated` | no-ops to override |
| `TokenSource` | `tokens(buffer, line)` | none |
| `Tokenizer` | `tokens(text)` | none |

**Graphemes.** `boundaries` returns the byte offset where each cluster starts, followed by the text's byte size, so `""` gives `[0]` and `"ab"` gives `[0, 1, 2]`. Implement the `String` form; the `Bytes` form is used for mapped lines and defaults to `boundaries(String.new(bytes))`, so existing producers keep working. Override it to index non-ASCII mapped lines without that temporary copy. `kind` returns a `ClusterKind` (`Space`, `Word`, `Punct` or `Other`), which drives word motion and deletion, word selection, smart Home, auto-indent and how typing is grouped for undo. `width` is the display width in columns. Clusters are passed as byte slices into the document's own storage, so a host can classify and measure them without allocating. Give the document the same measurements your renderer uses.

**Filters.** `SingleLine` turns line breaks and tabs into spaces and drops other control characters. `MultiLine.new(tab)` keeps line breaks and replaces tabs with `tab`. Any struct or class that includes `Filter` works, for example one that only lets digits through.

**Clipboard.** `read` takes a block so a clipboard can answer later, for example after asking a terminal; the paste happens when the block is called.

**Layout.** `cell_of(offset)` returns a `Cell` (`column`, `row`) in display columns, and `offset_in(row, column)` goes back. A host that wraps lines implements `Layout` over its wrapped rows and assigns it with `document.layout = …`; vertical motion, paging (`page_rows`), smart Home, carets above and below and box selection then follow the wrapped rows.

**Listener.** `document.listen(listener)` returns a proc that removes it again.

- `applied(document, change)` runs for each `Change` as it lands, with the buffer in the state right after it. This is the place to update per-line caches such as wrapping.
- `edited(document, changes)` runs once per edit or transaction, after the carets are placed, with every change in the order it was applied. Undo reports the changes it applied.
- `moved(view)` runs whenever that view's carets change, including after every edit. The view it is given carries `view.document`.
- `decorated(document)` runs when a source replaces its decorations, and `annotated(document)` when a source replaces its annotations.

**TokenSource.** Anything that can return the tokens of a line in a buffer includes `TokenSource`, so a renderer takes a source without knowing what produced it. `TreeSitter::Syntax` is one. A `Token` is a `start`, a `count` and a `kind`, with columns counting clusters, and `TokenSource::NO_TOKENS` is the shared empty result.

**Tokenizer.** Anything that can tokenize standalone text, with no document behind it, includes `Tokenizer`: `tokens(text)` returns one array of `Token` per line. This is what a renderer needs for a fenced code block or any other snippet it holds as a string. `TreeSitter::Tokenizer` is one.

## Buffer and changes

`document.buffer` stores each line as UTF-8 bytes with its cluster boundaries, and keeps line offsets in a `Scribe::Index`: lines in blocks, with a Fenwick tree over the block sums. String-backed lines retain their string; mapped lines retain the mapping and materialize `text` only on demand. Finding a line, its start, or the line of an offset is logarithmic in the number of blocks plus a scan inside one, and inserting or removing a line costs the same instead of rebuilding the whole index. On a million-line document, 200 edits that each add a line take about 76 ms rather than 1.3 s. A line whose bytes are all ASCII keeps no boundary table at all — its columns are its byte offsets — so ordinary source code costs nothing per cluster; `line.ascii?` says which kind a line is. Searching is line by line and never builds the whole text.

```crystal
buffer = text.buffer
buffer.line_count
buffer.position(42)          # Scribe::Position(line, column)
buffer.offset(position)
buffer.line_start(3)
buffer.line(3)               # Scribe::Line: text, to_slice, mapped?, size, ascii?, cluster(column), bytes(column), boundary(column), slice(from, to), each_cluster
buffer.width(3, 0, 10)       # display width of columns 0...10 on line 3
buffer.index(3, 12)          # the column under display column 12 on line 3
buffer.find("needle", 10)    # next literal match as a cluster range, wrapping around
buffer.find_all("needle")
buffer.revision              # how many edits the buffer has seen
buffer.changes_since(7)      # the Changes since a revision, or nil when the journal does not reach back
```

Line byte offsets are kept in a second Fenwick tree, so moving between cluster offsets and UTF-8 byte offsets is logarithmic too. This is what parsers and language servers that count bytes need:

```crystal
buffer.bytesize              # the text's size in bytes, with \n line breaks
buffer.byte_offset(42)       # cluster offset → byte offset
buffer.offset_at_byte(97)    # byte offset → cluster offset (rounded down; ceil: true rounds up)
buffer.line_byte(3)          # the byte offset where line 3 starts
buffer.byte_position(97)     # Scribe::Position(line, byte within the line)
buffer.byte_text(10, 20)     # the text between two byte offsets
buffer.chunk(97)             # the rest of that line as Bytes, "\n" at a line end, empty at the end
```

`chunk` reads the text without copying it, one line at a time, for parsers that pull their input.

**Units and points.** Other tools count positions in other units. `Scribe::Units` is `Bytes`, `Utf16`, `CodePoints` or `Clusters`, and a `Point` is a line and a column in one of them:

```crystal
point = buffer.point(42, Scribe::Units::Utf16)    # Scribe::Point(line, column in UTF-16 code units)
buffer.offset_at(point, Scribe::Units::Utf16)     # back to a cluster offset (a column inside a cluster rounds down)
buffer.measure("é👍", Scribe::Units::Utf16)       # => 3
buffer.line(3).units(Scribe::Units::Bytes, 0, 5)  # the size of columns 0...5 in bytes
```

A `Change` records `from`, the `removed` and `inserted` text, and their sizes in clusters; `removed_lines` and `inserted_lines` count line breaks. `start_point(buffer, unit)`, `old_end_point` and `new_end_point` describe where it starts and where it ended before and after, as a language server or an incremental parser expects; call them from `Listener#applied`, while the buffer is in the state right after the change. When an edit merges with a neighbouring cluster — a combining accent typed after a letter — the change is widened to whole clusters, so undoing it is exact.

`replace_ranges` applies several `Edit`s (a range and its new text) as one undo step and moves the carets with the text:

```crystal
text.replace_ranges([Scribe::Edit.new(0...3, "one"), Scribe::Edit.new(10...10, "!")])
```

Its text is used as given, without the filter.

## Decorations

A decoration marks a range of the text with a `kind` and a `message`, for example a compiler error. Its edges move with edits like marks do, without growing when text is typed right at them, and a decoration whose range shrinks to nothing remains, empty, until it is replaced.

```crystal
text.decorate("lsp", [Scribe::Decoration.new(4...9, "error", "undefined method")])
text.decorations             # every decoration, sorted by start
text.decorations(0, 20)      # those overlapping 0...20
text.decorations_at(6)       # those covering offset 6
text.decorate("lsp", [] of Scribe::Decoration)   # clears that source's decorations
```

Each call replaces every decoration from the same `source`, so several producers can share a document, and tells listeners through `decorated`.

## Annotations

An annotation is text shown beside the document rather than in it — an inlay hint, a git blame, a line note. Its offset follows edits like a mark, and each source replaces its own set, as decorations do.

```crystal
text.annotate("lsp", [Scribe::Annotation.new(7, ": Int32", Scribe::Placement::After, "type")])
text.annotations                 # every annotation, sorted by offset
text.annotations(0, 20)          # those between two offsets
text.annotations_at(7)
text.annotations_on(3)           # those on line 3
text.annotate("lsp", [] of Scribe::Annotation)   # clears that source
```

`Placement` is `Before`, `After` or `RowEnd`, and decides which side of the offset the host draws the text on; a `Before` annotation keeps its place when text is typed at it, the others move with it. Listeners hear `annotated`.

## Folding

Folds belong to a view, so two panes can fold a document differently. A fold is a line range held by marks, so it follows edits.

```crystal
folds = text.view.folds
folds.fold(2, 8)             # collapsed by default; nil for an empty or out-of-range range
folds.collapsed?(2)          # the header line
folds.hidden?(5)             # a line inside a collapsed fold
folds.toggle(2)
folds.expand(2)
folds.unfold(2)
folds.rows                   # the visible lines, in order
folds.replace([{0, 4}, {6, 9}])   # every fold at once, as a query would supply them
folds.clear
```

`LineLayout` consults the view's folds, so `row_count`, vertical motion, paging, smart Home and carets above and below all skip hidden lines. A host with its own `Layout` reads `folds.hidden?` itself. `view.folds` creates the set on first use and `view.folds?` tells whether one exists.

## Snippets

A snippet is text with tabstops. `Snippet.parse` turns LSP snippet syntax into plain text plus stop spans, and `View#insert_snippet` inserts it and selects the first stop.

```crystal
snippet = text.view.insert_snippet("def ${1:name}($2)\n  $0\nend")
text.selected_text          # => "name"
text.insert("run")          # fills the stop
snippet.next_stop(text.view)
snippet.previous_stop(text.view)
snippet.active?
snippet.close               # drops its marks
```

- `$1`, `${1}`, `${1:placeholder}`, `$0` (the final stop), `${1|one,two|}` (the first option) and `\$` are understood. A `${VAR:default}` resolves to its default and an unknown `$VAR` to nothing.
- A stop that appears more than once becomes one caret per occurrence, so typing fills every mirror at once.
- The stops are held by marks, so filling an early stop carries the later ones.
- Inserting a snippet replaces the primary caret's selection as one undo step. A snippet with no stops is inserted and `nil` comes back.

## Diffing

`Scribe.diff` turns an old and a new text into the smallest set of line edits, for `replace_ranges`:

```crystal
text.replace_ranges(Scribe.diff(text.value, formatted, graphemes))
```

The carets, marks, decorations and annotations outside the changed lines stay where they are, which is what `value=` cannot do. It is a Myers line diff with common ends trimmed; past `limit` lines of difference it falls back to one edit covering the changed region.

## Opening and saving a file

`Document.open` keeps a read-only mapping of the file and finds the lines in its bytes. Unchanged lines stay in the mapping with no per-line string; an edit copies only the lines it touches into ordinary editable storage. The caret starts at the beginning, and `path` remembers the file.

```crystal
text = Scribe::Document.open(graphemes, "src/app.cr", filter: Scribe::MultiLine.new)
text.buffer.mapped?        # true
text.buffer.line(0).to_slice  # read-only Bytes into the mapping
text.buffer.line(0).text      # materializes and caches a String only when asked
text.line_ending           # taken from the file

text.insert("// edited\n")
text.save                   # writes path and clears modified?
text.save("other/app.cr")   # save-as; updates path
```

`save` writes through a writable mapping of a temporary file in the destination directory, closes it, then renames it over the destination. The live source mapping is never truncated, and a failed save leaves the destination and document save point unchanged. Existing destination permissions are preserved. Saving a document without a path requires an explicit one.

`Scribe::Mapped` is the mapping itself, for a host that wants the bytes:

```crystal
Scribe::Mapped.open(path) do |mapped|
  mapped.bytesize
  mapped.bytes            # a read-only Bytes view; invalid once closed
  mapped.sequential       # tells the kernel the reads will be sequential
end

Scribe::Mapped.open(path, writable: true) do |mapped|
  mapped.bytes[0] = 'x'.ord.to_u8  # MAP_SHARED: writes reach the file
end
```

Mappings need a POSIX system and refuse a file larger than `Int32::MAX`. A persistent mapping is released once its buffer and extracted lines are no longer referenced. Do not truncate a mapped file externally while it is in use. String-returning operations such as `value`, regex search, and line transforms still allocate; byte chunks, motion, and literal search do not need to materialize mapped lines.

## Revisions

`Buffer#revision` counts edits, and the buffer keeps the last 256 of them. `Document#map` carries an offset or a range from an older revision to the current one, for a result that arrives late:

```crystal
mark = text.revision
# … a language server answers three keystrokes later …
text.map(offset, mark)        # => the offset now, or nil if the journal no longer reaches back
text.map(range, mark)         # a range, which does not grow at its edges
```

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

## Tokens

scribe defines the token vocabulary and the two interfaces that carry it; it produces no tokens itself.

```crystal
Scribe::Token.new(0, 3, "keyword")   # start, count, kind — columns count clusters
```

A `TokenSource` serves one line of a buffer and is what a renderer reads through:

```crystal
syntax = TreeSitter::Syntax.for(text, "src/app.cr")   # includes Scribe::TokenSource
syntax.tokens(text.buffer, 3)                          # => Array(Scribe::Token)
```

A `Tokenizer` serves standalone text, one array of tokens per line, for a snippet with no document behind it:

```crystal
marker = TreeSitter.language("crystal").tokenizer(graphemes)   # includes Scribe::Tokenizer
marker.tokens("def f\nend")                                    # => [[Token], [Token]]
```

To examine text outside a document, build a line with `Scribe::Line.new(text, graphemes)`. `text.brackets` returns the offsets of the bracket pair beside an empty primary caret.

## Input recall

`Recall` keeps the entries submitted from a single-line field and steps through them, remembering the draft:

```crystal
past = Scribe::Recall.new(limit: 100)
past.push("ls")
past.back("dra")   # => "ls"
past.forward       # => "dra"
```

## Macros

`MacroLog` records the commands and the text a view receives, and replays them:

```crystal
log = Scribe::MacroLog.new
text.view.macros = log

log.record
text.run(Scribe::Command::RowEnd)
text.insert(";")
log.stop

log.replay(text.view)            # once, as one undo step
log.replay(text.view, 10)        # ten more times
```

A replay records nothing itself, and each pass is one undo step.

## Development

```sh
crystal spec
```

The specs drive documents directly, with a small `Graphemes` built on the standard library in `spec/spec_helper.cr`. `History` takes an optional clock, which the specs use instead of sleeping.

## License

MIT
