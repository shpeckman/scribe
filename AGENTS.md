# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`scribe` is a Crystal shard holding a multi-caret text editing model: a grapheme-cluster buffer, carets, undo history, search, highlighting, marks and a set of editing commands. It draws nothing and reads no input. Hosts (for example the `tui` shard) plug in through interfaces and drive it with `Scribe::Command` values. It has no dependencies beyond the standard library, and must stay that way.

## Layout

- `src/scribe.cr` — requires every file in load order.
- `src/scribe/values.cr` — the small value types: `Position`, `Cell`, `Edit`, `Gravity`, `LineEnding`.
- `src/scribe/line.cr` — `Line`: one line of UTF-8 text plus its cluster byte boundaries.
- `src/scribe/buffer.cr` — `Buffer`: the lines, a Fenwick tree over line sizes (plus a contiguous `@sizes` array it is rebuilt from), cluster-aligned `replace`, literal `find`, byte mapping, and a journal of touched lines.
- `src/scribe/caret.cr`, `change.cr`, `mark.cr` — caret ranges with an optional goal column, one reversible replacement, and offsets that follow changes.
- `src/scribe/history.cr` — undo and redo steps, typing and deleting grouped within a time window, a save point, and an injectable clock.
- `src/scribe/search.cr` — regex and literal search; literal searches are kept per line and updated from the buffer's journal.
- `src/scribe/highlighter.cr`, `highlight_cache.cr` — line tokenizers and a per-line token cache that listens to a document.
- `src/scribe/recall.cr` — input history for single-line fields.
- `src/scribe/command.cr` — the `Command` enum and `edits?`.
- `src/scribe/document.cr` — `Document`'s core: options, value and line endings, marks, transactions, `run` dispatch, and the internal edit planner (`apply`, `replace_ranges`, `seat`, `record`, `changed`).
- `src/scribe/document/` — the rest of `Document`, split by concern by reopening the class:
  - `carets.cr` — motion, goal column, selection, occurrences, box.
  - `editing.cr` — `insert`, `paste`, auto-closing, deleting, new line, tab.
  - `lines.cr` — indent, outdent, comments, moving, duplicating and deleting lines.
  - `clipboard.cr` — copy, cut, paste, auto-copy.
  - `finder.cr` — find, replace, bracket matching.
- Interfaces the host implements, each with its defaults:
  - `graphemes.cr` — `Graphemes` and `ClusterKind`; no default.
  - `filter.cr` — `Filter`, `SingleLine`, `MultiLine`.
  - `clipboard.cr` — `Clipboard`, `Register`.
  - `layout.cr` — `Layout`, `LineLayout`.
  - `listener.cr` — `Listener` with no-op hooks.
- `spec/` — one file per area. `spec/spec_helper.cr` defines a standard-library `Graphemes` (`Plain`), a deferred clipboard, a recording listener, and the `buffer`, `line`, `document`, `lines`, `code` and `change` helpers.

## Commands

- `crystal spec` — run the suite.
- `crystal spec spec/document_spec.cr` — run one file.
- `crystal build --no-codegen src/scribe.cr` — fast compile check.

## Rules

- Offsets count grapheme clusters, and a line break counts as one. Text inside the buffer always uses `\n`; other endings live only in `Document#line_ending` and `export`.
- `Graphemes#boundaries` returns cluster start offsets plus the byte size; clusters reach `kind` and `width` as byte slices into the line, so never allocate a `String` per cluster on a hot path.
- `Buffer#replace` widens a change to whole clusters when an edit merges with a neighbour. Never assume `inserted_size` equals the cluster count of the text passed in; place carets from the returned `Change`.
- All grapheme, width, clipboard, layout and input-filtering knowledge comes through the interfaces. Never add a dependency on a terminal or width library.
- New editing behaviour is a `Command` member handled in `Document#run` (and listed in `Command#edits?` when it changes text), plus specs in `spec/document_spec.cr` and a line in the README's command notes.
- `run` returns whether the command applied; keep the README's list of which commands can return `false` accurate.
- Listener order is fixed: `applied` for each change as it lands, then `moved` once the carets are placed, then `edited` with the whole batch. Inside a transaction, `moved` and `edited` are held until it ends.
- A `Document` method that changes the text goes through `apply` (user edits, which honour `read_only` and `max_length`) or `replace_ranges` (structural edits), or records history and notifies listeners itself as `value=` does. Never call `Buffer#replace` directly from new `Document` code.

## Code standards

- Compiler-friendly, performance-focused, idiomatic and data-driven.
- The usage-facing API must be ergonomic.
- Avoid shotgun surgery: one change should land in one place.
- No comments, except every file starts with a comment containing its own path (e.g. `# src/scribe.cr`).
- Never use `out` as an identifier.
- Never edit the `version` field in `shard.yml`.
- Keep `README.md` (usage and public API) and this file in sync with the code.
