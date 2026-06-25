---
description: "Import vault-audit findings (judge + linter requires-decision) into the feed inbox for triage."
---

# /vault-feed:import-audit

Reads the newest machine-readable audit findings file and writes each finding into
`paths.inbox` as a `type: audit-finding` entry, deduped against what you've already
seen. Then triage them with `/vault-feed:triage` alongside feed items.

## Step 1 — Resolve config

Read `vault-feed.yaml` (fallback `vault-feed.example.yaml`). Extract `paths.inbox`,
`paths.triaged`, `timezone_offset_hours`, and `audit.findings_dir` (default
`.vault-audit`). Never hardcode a path.

## Step 2 — Locate the newest findings file

Glob `<audit.findings_dir>/findings-*.json`. If none → print
`Nothing to import — no findings-*.json under <audit.findings_dir>.` and exit clean
(fail-soft, never an error). Otherwise pick the newest **by mtime** (not by name, so a
`-2` counter suffix never mis-sorts).

Parse it. If `schema` is absent → print `Refusing: findings file has no schema field.`
and exit. If its major tag is not `vault-audit/findings@1` → print
`Refusing: unknown findings schema "<schema>".` and exit. If both
`judge_findings` and `linter_requires_decision` are empty → print `Nothing to import.`
and exit clean.

## Step 3 — Build the dedup key set (scan inbox ∪ triaged)

Glob `<paths.inbox>/*.md` AND `<paths.triaged>/*.md`. For each file, parse frontmatter
and keep ONLY entries with `type: audit-finding` (feed-items carry no `finding_id` —
exclude them so they never collapse into a junk key). From each, read `origin` and
`finding_id`; add `"<origin>|<finding_id>"` to a set `seen`.

## Step 4 — Adapt each finding to an inbox-entry

Compute today's local date `YYYY-MM-DD` = UTC shifted by `timezone_offset_hours`.

For each item in `judge_findings`:

- **Skip** any item whose `id == "memory-cluster"` — these are memory-scope findings
  excluded from the bridge (scope-M exclusion per spec §1.3). Log:
  `Skipping memory-cluster finding (scope-M excluded).`

For each remaining judge item, build:
- `type: audit-finding`, `source: vault-audit`, `origin: judge`
- `title` = the finding's `rule`
- `url: ""`
- `date_captured` = today
- `status: inbox`
- `value` = `high` if `severity=="critical"`, `med` if `"warning"`, `low` if `"suggestion"`
- `effort: med`, `confidence: high`, `decision_reason: ""`
- `finding_id` = the finding's `id`
- `severity` = the finding's `severity`
- `related_files` = the finding's `related_files`
- body:
  ```
  **Severity:** <severity>
  **Rule:** <rule>
  **Evidence:** <evidence>
  **Suggested action:** <suggested_action>
  **Related files:** <related_files joined by ", ">
  ```

For each item in `linter_requires_decision`, build:
- `type: audit-finding`, `source: vault-audit`, `origin: linter`
- `title` = the item's `issue`
- `url: ""`, `date_captured` = today, `status: inbox`
- `value: med`, `effort: med`, `confidence: high`, `decision_reason: ""`
- `finding_id` = `"<category>:<path>"`
- `related_files` = `[<path>]` (no `severity` field for linter items)
- body:
  ```
  **Category:** <category>
  **Issue:** <issue>
  **Suggested action:** <suggested_action>
  **Path:** <path>
  ```

## Step 5 — Dedup, then write survivors

For each adapted entry, compute `"<origin>|<finding_id>"`. If it is in `seen` → skip
(already in inbox or triaged; never resurrect a disposed item). Also skip duplicates
WITHIN this import (two findings sharing a key collapse to one — add the key to `seen`
as you write).

For each survivor, write `<paths.inbox>/<date>-<slug>-<n>.md` exactly as
`/vault-feed:pull` Phase 3b does: `slug` = lowercased `title`, non-alphanumeric → `-`,
max 60 chars; collision counter starting at `-1`; frontmatter from the fields above
(include `origin`, `finding_id`, and `severity`/`related_files` where present); body as
above. Create `<paths.inbox>/` if absent.

File format:

```markdown
---
type: audit-finding
source: vault-audit
origin: <origin>
title: "<title>"
url: ""
date_captured: <date>
status: inbox
value: <value>
effort: med
confidence: high
decision_reason: ""
finding_id: "<finding_id>"
severity: <severity>           # judge findings only; omit for linter
related_files: <related_files> # YAML list
---

<body>
```

## Step 6 — Summary

Print:
```
Import complete — <date>
  Imported: <count written>   to <paths.inbox>/
  Skipped (already seen): <count deduped>
  Filtered (memory-scope): <count of memory-cluster items skipped in Step 4>
  Source: <the findings file path>
```
Never silent: if 0 imported because all were dups, say so explicitly; the
memory-scope filtered count is surfaced here too (fail-soft ≠ silent), and the
`Filtered (memory-scope)` line may be omitted when that count is 0.

## Error handling

| Failure | Behaviour |
|---|---|
| No findings file | "Nothing to import …", exit clean (not an error) |
| Unknown schema major | Refuse with the schema string, exit |
| Both arrays empty | "Nothing to import.", exit clean |
| inbox/ absent | create before first write |
| A malformed finding object | warn (`Skipping malformed finding: <reason>`), continue |
