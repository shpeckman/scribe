# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`scribe` is a Crystal shard holding a multi-caret text editing model: a grapheme-cluster buffer, views with their own carets, undo history, search, marks, decorations, annotations, folds, snippets and a set of editing commands. It produces no syntax tokens of its own: it defines the `Token` value and the `TokenSource`/`Tokenizer` interfaces, and a host plugs in a producer such as `TreeSitter::Syntax`. It draws nothing and reads no input. Hosts (for example the `tui` shard) plug in through interfaces and drive it with `Scribe::Command` values. It has no dependencies beyond the standard library, and must stay that way.

## Layout

- `src/scribe.cr` — requires every file in load order.
- `src/scribe/values.cr` — the small value types: `Position`, `Point`, `Cell`, `Edit`, `Stroke`, `Gravity`, `LineEnding`, and `Units` (bytes, UTF-16, code points, clusters).
- `src/scribe/line.cr` — `Line`: one line of UTF-8 bytes plus, only when it needs one, its cluster byte boundaries and a lazily materialized `String`. An all-ASCII line stores no boundaries and maps column to byte with the identity; everything goes through `boundary`, `byte_at` and `column_at`, never a raw marks array. A mapped line also retains its `Mapped` owner, so its bytes stay valid while the line is referenced.
- `src/scribe/index.cr` — `Index`: the line-offset structure. Weights live in blocks of at most `LIMIT`, with two Fenwick trees over the blocks (one of line counts, one of weight sums), so `prefix`, `locate`, `set`, `insert` and `drop` are logarithmic in the block count plus a scan inside one block. Only a block split or an emptied block rebuilds the trees. `spec/index_spec.cr` holds a differential test against a naive array over 3000 random edits; extend it rather than reasoning about the structure by hand.
- `src/scribe/mapped.cr` — `Mapped`: a POSIX `mmap` of a file, private/read-only by default or shared/read-write with `writable: true`, with `bytes`, `sequential` and an idempotent `close`. `Buffer.map` and `Document.open` retain the read-only mapping; `Document#save` uses a block-scoped writable mapping.
- `src/scribe/buffer.cr` — `Buffer`: the lines, their optional persistent mapping, and two `Index`es over them, one in clusters and one in bytes (each weight is the line's size plus its separator); cluster-aligned per-line copy-on-write `replace`, line-by-line literal `find` over bytes, byte and unit mapping (`byte_offset`, `offset_at_byte`, `byte_text`, `chunk`, `point`, `offset_at`), a journal of touched lines carrying each `Change`, and `changes_since`.
- `src/scribe/caret.cr`, `change.cr`, `mark.cr` — caret ranges with an optional goal column, one reversible replacement (with its start and end points in any unit), and offsets that follow changes.
- `src/scribe/decoration.cr`, `annotation.cr` — `Decoration` (a kind and message over a range held by two marks) and `Annotation` (text beside the document at one offset, with a `Placement`). `Document#decorate` and `#annotate` replace them per source.
- `src/scribe/folds.cr` — `Folds`: collapsible line ranges held by marks, owned by a `View`; `LineLayout` consults them so motion skips hidden lines.
- `src/scribe/snippet.cr` — `Snippet`: the LSP snippet parser (`Snippet::Parser`) producing a `Template`, and the live session holding each stop as a pair of marks. Mirrored stops become several carets, so typing fills them together.
- `src/scribe/diff.cr` — `Diff.hunks` (a Myers line diff with common ends trimmed and a fallback past `limit`) and `Scribe.diff`, which turns two texts into `Edit`s in the old text's cluster offsets.
- `src/scribe/macro_log.cr` — `MacroLog`: records the commands and text a view receives and replays them; a replay records nothing itself.
- `src/scribe/history.cr` — undo and redo steps, typing and deleting grouped within a time window, a save point, and an injectable clock.
- `src/scribe/search.cr` — regex and literal search; literal searches are kept per line and updated from the buffer's journal.
- `src/scribe/token.cr`, `token_source.cr` — the `Token` value (start, count, kind; columns count clusters), and the two interfaces that carry it: `TokenSource` (`tokens(buffer, line)`, for a document) and `Tokenizer` (`tokens(text)`, for standalone text). Neither has an implementation here.
- `src/scribe/recall.cr` — input history for single-line fields.
- `src/scribe/command.cr` — the `Command` enum and `edits?`.
- `src/scribe/document.cr` — `Document`: the text, options, path, line endings, history, marks, decorations, annotations, transactions, revision mapping (`map`), atomic writable-mmap `save`, and the edit planner views go through (`apply`, `replace_ranges`, `record`, `changed`). It holds a lazily built primary `View` and delegates the whole caret and editing API to it.
- `src/scribe/view.cr` — `View`: carets, primary index, box, layout, folds, the macro log, `run` dispatch, `seat` (which places carets and tells listeners) and `follow` (which carries this view's carets through a change another view made).
- `src/scribe/view/` — the rest of `View`, split by concern by reopening the class:
  - `carets.cr` — motion, goal column, selection, occurrences, box.
  - `editing.cr` — `insert`, `paste`, `insert_snippet`, auto-closing, deleting, new line, tab.
  - `lines.cr` — indent, outdent, comments, moving, duplicating and deleting lines.
  - `transforms.cr` — sort, reverse, unique, join, trim, case, surround, carets per line and per match, subword edges.
  - `clipboard.cr` — copy, cut, paste, auto-copy.
  - `finder.cr` — find, replace, bracket matching.
- Interfaces the host implements, each with its defaults:
  - `graphemes.cr` — `Graphemes` and `ClusterKind`; string boundaries are abstract, and byte boundaries default to one temporary string copy.
  - `filter.cr` — `Filter`, `SingleLine`, `MultiLine`.
  - `clipboard.cr` — `Clipboard`, `Register`.
  - `layout.cr` — `Layout`, `LineLayout`.
  - `listener.cr` — `Listener` with no-op hooks.
  - `token_source.cr` — `TokenSource` and `Tokenizer`; implemented outside this shard, by `TreeSitter::Syntax` and `TreeSitter::Tokenizer`.
- `spec/` — one file per area. `spec/spec_helper.cr` defines a standard-library `Graphemes` (`Plain`), a deferred clipboard, a recording listener, and the `buffer`, `line`, `document`, `lines`, `code` and `change` helpers.

## Commands

- `crystal spec` — run the suite.
- `crystal spec spec/document_spec.cr` — run one file.
- `crystal build --no-codegen src/scribe.cr` — fast compile check.

## Rules

- Offsets count grapheme clusters, and a line break counts as one. Text inside the buffer always uses `\n`; other endings live only in `Document#line_ending`, `export` and `save`.
- `Graphemes#boundaries` returns cluster start offsets plus the byte size; clusters reach `kind` and `width` as byte slices into the line, so never allocate a `String` per cluster on a hot path. Buffer read paths use `Line#to_slice`; call `Line#text` only when a `String` is genuinely required.
- Both `Index`es change together in `replace_lines`; any new per-line weight goes through an `Index` rather than a new copy of the tree code. `Buffer` never touches a Fenwick array directly.
- `@lines` is still a flat `Array(Line)`, so an edit that changes the line count memmoves it. That is what remains of the per-edit cost at a million lines (about 0.4 ms), and blocking it is the next step if that matters. A single very long line is also still one byte sequence with one boundary table, so an edit inside a 50 MB line is linear in the line; intra-line chunking is not done.
- Mapped lines and their `Bytes` are read-only and retain the mapping owner. Edits create ordinary string-backed replacement lines; never mutate mapped storage or close the persistent mapping explicitly.
- `Document#save` writes a same-directory temporary file through a shared writable mapping, closes it, then renames it. Never truncate or overwrite the file a live buffer is reading; update `path` and the save point only after a successful rename.
- Positions for other tools go through `Units`, `Buffer#point`/`offset_at` and `Change#start_point`/`old_end_point`/`new_end_point`; never count bytes or UTF-16 units by hand elsewhere.
- `Buffer#replace` widens a change to whole clusters when an edit merges with a neighbour. Never assume `inserted_size` equals the cluster count of the text passed in; place carets from the returned `Change`.
- All grapheme, width, clipboard, layout, tokenizing and input-filtering knowledge comes through the interfaces. Never add a dependency on a terminal or width library, and never add a tokenizer, highlighter or language table here: `Token`, `TokenSource` and `Tokenizer` are the whole surface, and producers live in their own shards.
- New editing behaviour is a `Command` member handled in `Document#run` (and listed in `Command#edits?` when it changes text), plus specs in `spec/document_spec.cr` and a line in the README's command notes.
- `run` returns whether the command applied; keep the README's list of which commands can return `false` accurate.
- Listener order is fixed: `applied` for each change as it lands, then `moved` once the carets are placed, then `edited` with the whole batch. Inside a transaction, `moved` and `edited` are held until it ends. `moved` takes the `View` whose carets moved, not the document.
- Anything that changes the text goes through `Document#apply` (user edits, which honour `read_only` and `max_length`) or `Document#replace_ranges` (structural edits), or records history and notifies listeners itself as `value=` does. Never call `Buffer#replace` directly from new code.
- The split is the rule: text, history, marks, decorations and annotations belong to the `Document`; carets, the goal column, the box, the layout and the folds belong to a `View`. A new caret-driven operation is a `View` method in `src/scribe/view/`, not a `Document` one, and `Document` reaches it only through the delegation list.
- Every edit names the view that made it, so `Document#applied` can carry the other views' carets with `View#follow` and skip the acting one. A new edit path sets `@acting` the same way or other views will not follow.
- `Document`'s internals that a `View` needs (`apply`, `prepare`, `count`, `attach`, `stirred`) are `protected`, which Crystal allows between classes in one namespace. Keep them protected rather than widening the public API.
- `Document#view` is lazy, because a `View` takes the document in its constructor and Crystal will not let an ivar be assigned after `self` escapes. Anything that must see every view calls the `views` method, which forces the primary first.

## Code standards

- Compiler-friendly, performance-focused, idiomatic and data-driven.
- The usage-facing API must be ergonomic.
- Avoid shotgun surgery: one change should land in one place.
- No comments, except every file starts with a comment containing its own path (e.g. `# src/scribe.cr`).
- Never use `out` as an identifier.
- Never edit the `version` field in `shard.yml`.
- Keep `README.md` (usage and public API) and this file in sync with the code.
