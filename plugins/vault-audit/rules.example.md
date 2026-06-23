# Judgment checks (read by the `judge` agent)

Each check = a rule you declared somewhere + how to detect a violation + severity.
These are GENERIC EXAMPLES. Replace with your own.

## anti-patterns

- id: no-raw-chat-imports
  rule: "Research notes are curated extracts, not raw chat dumps."
  detect: "Glob `research/*.md`; read first 30 lines; flag any whose structure is a repeating `User:`/`Assistant:` transcript."
  severity: warning

## drift-checks

- id: declared-folders-vs-actual
  rule: "Top-level folders named in CLAUDE.md routing must exist, and existing ones should be declared."
  detect: "Parse the folder list from CLAUDE.md; diff against actual top-level dirs (exclude dotfiles)."
  severity: warning

- id: declared-commands-vs-files
  rule: "Every slash command named in the user manual must exist as a command file."
  detect: "List `commands/*.md`; for each `/name` mentioned in `docs/user-manual.md`, confirm a matching file exists, and vice-versa. If neither path exists in the vault, this check is a no-op."
  severity: critical
