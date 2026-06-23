# Judgment checks - opinionated starter (read by the `judge` agent)

Proven, structure-agnostic checks for any Claude-Code knowledge vault. Each entry:
`id`, `rule`, `detect`, `severity`. Copy to `rules.md` and adjust; for a bare 3-example
set instead, see rules.example.md.

## anti-patterns

- id: no-raw-chat-imports
  rule: "Research/reference notes are curated extracts, not raw chat dumps."
  detect: "Glob research-like folders for `*.md`; read first 30 lines; flag any whose structure is a repeating `User:`/`Assistant:` transcript."
  severity: warning

## drift-checks

- id: declared-folders-vs-actual
  rule: "Top-level folders named in CLAUDE.md routing must exist, and existing ones should be declared."
  detect: "Parse the folder list from CLAUDE.md; diff against actual top-level dirs (exclude dotfiles)."
  severity: warning

- id: user-manual-commands-exist
  rule: "Every slash command named in your user manual must exist as a command file, and vice-versa."
  detect: "List command files; for each `/name` mentioned in the user-manual doc, confirm a matching file; flag mismatches. No-op if neither path exists."
  severity: critical

- id: update-protocol-gap
  rule: "A commit that adds a command/skill/hook/rule should also touch a doc (changelog/architecture/user-manual)."
  detect: "Read the last ~30 commits; for any whose subject matches add(command|skill|hook|rule), check the same commit touched a docs file; flag misses."
  severity: warning

- id: session-summary-present
  rule: "Active working days have a dated session summary."
  detect: "For recent dates with commits, check for a matching dated summary file in your logs/summaries folder; flag missing ones."
  severity: suggestion

- id: one-source-of-truth-contested
  rule: "A fact lives in one place; conflicts are marked, not duplicated silently."
  detect: "Grep for files tagged `status/contested`; surface them for resolution."
  severity: warning
