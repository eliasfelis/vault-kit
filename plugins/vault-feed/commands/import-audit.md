---
description: "Import vault-audit findings (judge + linter requires-decision) into the feed inbox for triage."
---

# /vault-feed:import-audit

Reads the newest machine-readable audit findings file and writes each finding into
`paths.inbox` as a `type: audit-finding` entry, deduped against what you've already
seen. Then triage them with `/vault-feed:triage` alongside feed items.

## Step 1 — Resolve config

Look for `vault-feed.yaml` at the vault/working root; absent → fall back to
`"${CLAUDE_PLUGIN_ROOT}/vault-feed.example.yaml"`. If neither exists, STOP with
`Cannot resolve config: neither vault-feed.yaml nor the bundled
vault-feed.example.yaml exists.` — an unresolved config means unresolved paths, and
guessing them would scatter entries somewhere nobody triages.

From the resolved config extract `paths.inbox`, `paths.triaged`,
`timezone_offset_hours`, and `audit.findings_dir` (default `.vault-audit`). Never
hardcode a path.

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
exclude them so they never collapse into a junk key). From each, read `origin`,
`finding_id`, and `related_files`; add the key to a set `seen`.

### The dedup key

```
<origin>|<finding_id>|<instance>
```

`<instance>` is the `related_files` list joined in order with `,` and no spaces
(`projects/alpha/STATE.md,projects/beta/STATE.md`). An absent or empty list yields an
empty `<instance>` segment; the key still has its two separators.

The third segment is what makes the key a *violation* key rather than a *rule* key.
`finding_id` for a judge finding is the rule id, so on `<origin>|<finding_id>` alone,
disposing "declared folders must exist" once suppressed every future violation of that
rule forever: the second missing folder was silently swallowed as a duplicate of the
first, and the import cheerfully reported nothing new. `related_files` is the
discriminator already present in the findings JSON, and it is stable — re-detecting the
*same* violation yields the same file list, while a new one changes it.

For linter items `related_files` is `[<path>]`, and the path is already inside
`finding_id`, so the key behaves exactly as it did before for that origin.

The tradeoff is deliberate: a finding whose file list changes for a cosmetic reason
(a rename, a reordering by the auditor) re-imports once as a new entry. A duplicate you
can see and dispose beats a real violation you never learn about.

## Step 4 — Adapt each finding to an inbox-entry

Compute today's local date `YYYY-MM-DD` = UTC shifted by `timezone_offset_hours`.

For each item in `judge_findings`:

- **Skip** any item whose `id == "memory-cluster"` — memory findings are about the
  hygiene of a long-lived memory store, not about anything in the vault tree, so they
  have no file to act on and no place in a file-disposition ledger. They are also off
  by default in vault-audit, so importing them would surface a finding most users never
  asked to generate. Log:
  `Skipping memory-cluster finding (memory scope is not bridged).`

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

For each adapted entry, compute `"<origin>|<finding_id>|<instance>"` per Step 3 —
`<instance>` from the entry's own `related_files`, joined in order with `,`. If the key
is in `seen` → skip (already in inbox or triaged; never resurrect a disposed item).
Also skip duplicates WITHIN this import (two findings sharing a key collapse to one —
add the key to `seen` as you write).

Two live violations of one rule now carry different keys and both land. Their titles
are identical (the title is the rule text), so the collision counter below gives them
distinct filenames — `-1`, `-2` — and the bodies differ by their `Related files` line.

For each survivor, write `<paths.inbox>/<date>-<slug>-<n>.md` exactly as
`/vault-feed:pull` Phase 3b does: `slug` = lowercased `title`, non-alphanumeric → `-`,
max 60 chars; collision counter starting at `-1`; frontmatter from the fields above;
body as above. Create `<paths.inbox>/` if absent.

`origin`, `finding_id`, and `related_files` are always written — Step 3 rebuilds the
dedup key from exactly those three, so an entry missing one comes back as new on the
next import. Write `related_files: []` when the finding carried none. `severity` is
judge-only and omitted for linter items.

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
| Neither config nor bundled fallback | STOP naming both paths (Step 1) |
| No findings file | "Nothing to import …", exit clean (not an error) |
| Unknown schema major | Refuse with the schema string, exit |
| Both arrays empty | "Nothing to import.", exit clean |
| inbox/ absent | create before first write |
| Finding has no `related_files` | Empty `<instance>` segment; write `related_files: []` |
| A malformed finding object | warn (`Skipping malformed finding: <reason>`), continue |
