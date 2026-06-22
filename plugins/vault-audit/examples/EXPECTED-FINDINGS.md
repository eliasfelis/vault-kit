# Expected findings — running vault-audit on `demo-vault/`

Acceptance ground-truth. Lives OUTSIDE `demo-vault/` so it is not itself audited.

## Junker (deterministic) — exactly 5 findings
- broken_refs: `notes/broken-link 2026-06-01.md` -> `./nope.md` (no such file)
- frontmatter: `notes/no-frontmatter 2026-06-01.md` (missing `tags` and `date`)
- naming: `notes/BadName.md` (filename does not match the dated pattern)
- duplicates: `projects/alpha/report 2026-06-01.md` == `projects/beta/report 2026-06-01.md`
- staleness: `inbox/stale 2020-01-01.md` (frontmatter `date` older than 7 days)

## Builder (judgment) — exactly 1 finding
- drift `declared-folders-vs-actual`: `CLAUDE.md` declares `widgets/` which does not exist

## Must NOT be flagged
- `CLAUDE.md` — governance path (skipped by all Junker checks)
- `rules.yaml` — not a markdown file
- `projects/alpha/STATE.md`, `projects/beta/STATE.md` — exempt basename, valid frontmatter
- `notes/good-note 2026-06-01.md` — fully compliant
