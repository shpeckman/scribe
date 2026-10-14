# AGENTS.md

Orientation for AI agents working on this repository.

## What this is

`scribe` is a Crystal shard holding a multi-caret text editing model: a grapheme-cluster buffer, carets, undo history, search, highlighting and a set of editing commands. It draws nothing and reads no input. Hosts (for example the `tui` shard) plug in through interfaces and drive it with `Scribe::Command` values. It has no dependencies beyond the standard library, and must stay that way.

## Layout

- `src/scribe.cr` — requires every file.
- `src/scribe/document.cr` — `Document`, the editing model: carets, the edit planner (`apply`, `replace_ranges`, `carry`), `run(command)`, line operations, box selection, find and replace, bracket matching, and listener notification.
- `src/scribe/buffer.cr`, `caret.cr`, `change.cr` — the text as lines of clusters, caret ranges, and one reversible replacement.
- `src/scribe/history.cr` — undo and redo steps, grouping typing and deleting within a time window.
- `src/scribe/search.cr` — regex and literal search over a buffer, cached per buffer revision.
- `src/scribe/highlighter.cr`, `highlight_cache.cr` — line tokenizers and a per-line token cache that listens to a document.
- `src/scribe/recall.cr` — input history for single-line fields.
- `src/scribe/command.cr` — the `Command` enum.
- Interfaces the host implements, each with its defaults:
  - `graphemes.cr` — `Graphemes` and `ClusterKind`; no default.
  - `filter.cr` — `Filter`, `SingleLine`, `MultiLine`.
  - `clipboard.cr` — `Clipboard`, `Register`.
  - `layout.cr` — `Layout`, `LineLayout`.
  - `listener.cr` — `Listener` with no-op hooks.
- `spec/` — one file per area; `spec/spec_helper.cr` defines a standard-library `Graphemes` (`Plain`), a deferred clipboard and a recording listener, plus the `document` and `lines` helpers.

## Commands

- `crystal spec` — run the suite.
- `crystal spec spec/document_spec.cr` — run one file.
- `crystal build --no-codegen src/scribe.cr` — fast compile check.

## Rules

- Offsets count grapheme clusters. Positions from `Layout#position_of` are `{column, row}` in display columns.
- All grapheme, width, clipboard, layout and input-filtering knowledge comes through the interfaces. Never add a dependency on a terminal or width library.
- New editing behaviour is a `Command` member handled in `Document#run`, plus specs in `spec/document_spec.cr`.
- Listener order is fixed: `applied` for each change as it lands, then `moved` once the carets are placed, then `edited` with the whole batch.
- A `Document` method that changes the text records a history step and notifies listeners, as `apply`, `replace_ranges` and `value=` do; build new edits on `apply` or `replace_ranges` rather than calling `Buffer#replace` directly.

## Code standards

- Compiler-friendly, performance-focused, idiomatic and data-driven.
- The usage-facing API must be ergonomic.
- Avoid shotgun surgery: one change should land in one place.
- No comments, except every file starts with a comment containing its own path (e.g. `# src/scribe.cr`).
- Never use `out` as an identifier.
- Never edit the `version` field in `shard.yml`.
- Keep `README.md` (usage and public API) and this file in sync with the code.
