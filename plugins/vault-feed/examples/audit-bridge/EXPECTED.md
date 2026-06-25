# Expected `/vault-feed:import-audit` output

## On `findings-fixture.json` (first import)
5 entries written to `paths.inbox`, all `type: audit-finding`, `source: vault-audit`,
`status: inbox`, `effort: med`, `confidence: high`, `decision_reason: ""`.

| origin | finding_id | title (= rule/issue) | value | severity | related_files |
|---|---|---|---|---|---|
| judge | declared-folders-vs-actual | Declared folders in the constitution must exist on disk. | med (warning) | warning | [CLAUDE.md] |
| judge | stale-pinned-doc | Pinned reference docs should be refreshed within the declared window. | low (suggestion) | suggestion | [reference/pinned-map.md] |
| judge | one-source-of-truth-contested | Each fact has exactly one source of truth. | high (critical) | critical | [projects/alpha/STATE.md, projects/beta/STATE.md] |
| linter | naming:notes/BadName.md | Filename does not match the declared naming pattern. | med | (none) | [notes/BadName.md] |
| linter | duplicates:projects/alpha/STATE.md | Basename STATE.md appears in two or more directories. | med | (none) | [projects/alpha/STATE.md] |

Body of a judge entry: lines `**Severity:** … / **Rule:** … / **Evidence:** … /
**Suggested action:** … / **Related files:** …`.
Body of a linter entry: lines `**Category:** … / **Issue:** … / **Suggested action:**
… / **Path:** …`.

## Dedup
- Re-import `findings-fixture.json` → **0 new** (all 5 keys present).
- Import `findings-fixture-rerun.json` → **0 new** (keys `declared-folders-vs-actual`
  and `naming:notes/BadName.md` already present, despite the changed `related_files` —
  proves the key excludes `related_files`).
- If `declared-folders-vs-actual` was moved to `triaged/` (status `reject`), re-import
  still adds **0** for it (no resurrection).
