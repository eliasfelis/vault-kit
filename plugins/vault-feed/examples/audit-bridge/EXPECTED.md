# Expected `/vault-feed:import-audit` output

## Dedup key

```
<origin>|<finding_id>|<instance>
```

`<instance>` = the finding's `related_files`, joined in order with `,` and no spaces.

## On `findings-fixture.json` (first import)

Every finding in the file is written to `paths.inbox`, all `type: audit-finding`,
`source: vault-audit`, `status: inbox`, `effort: med`, `confidence: high`,
`decision_reason: ""`.

| origin | finding_id | instance | title (= rule/issue) | value | severity |
|---|---|---|---|---|---|
| judge | declared-folders-vs-actual | `CLAUDE.md` | Declared folders in the constitution must exist on disk. | med (warning) | warning |
| judge | stale-pinned-doc | `reference/pinned-map.md` | Pinned reference docs should be refreshed within the declared window. | low (suggestion) | suggestion |
| judge | one-source-of-truth-contested | `projects/alpha/STATE.md,projects/beta/STATE.md` | Each fact has exactly one source of truth. | high (critical) | critical |
| linter | naming:notes/BadName.md | `notes/BadName.md` | Filename does not match the declared naming pattern. | med | (none) |
| linter | duplicates:projects/alpha/STATE.md | `projects/alpha/STATE.md` | Basename STATE.md appears in two or more directories. | med | (none) |

Summary line: `Imported: 5`, `Skipped (already seen): 0`.

Body of a judge entry: lines `**Severity:** … / **Rule:** … / **Evidence:** … /
**Suggested action:** … / **Related files:** …`.
Body of a linter entry: lines `**Category:** … / **Issue:** … / **Suggested action:**
… / **Path:** …`.

## Dedup

**Re-import `findings-fixture.json`** → `Imported: 0`, `Skipped (already seen): 5`.
Every key is unchanged, because re-detecting the same violation reports the same
`related_files`.

**Import `findings-fixture-rerun.json`** → `Imported: 1`, `Skipped (already seen): 1`.

| key | verdict |
|---|---|
| `judge\|declared-folders-vs-actual\|CLAUDE.md,scratch` | **new** — not in `seen` |
| `linter\|naming:notes/BadName.md\|notes/BadName.md` | skipped — identical key |

The judge finding is the point of the fixture. It is the same rule as the first import
and the same `finding_id`, but `CLAUDE.md` now declares `scratch/` as well and neither
folder exists — a second, genuinely new violation. On a key of
`<origin>|<finding_id>` alone it was swallowed as a duplicate and the run reported
nothing new, which is how a live problem stays invisible behind a disposed one. Under
the instance-discriminated key it imports, and the title collides with the already-
present entry, so the new file takes the `-2` counter suffix.

The linter item is the control: same path, same rule, unchanged `related_files`, so it
still dedups. Adding the third segment must not make re-runs noisy.

**Disposal does not resurrect.** If `judge|declared-folders-vs-actual|CLAUDE.md` was
moved to `triaged/` with status `reject`, re-importing `findings-fixture.json` still
imports 0 for it — Step 3 scans inbox ∪ triaged, so a disposed key stays disposed. The
rerun's `…|CLAUDE.md,scratch` is a different violation and is unaffected by that
disposal, which is exactly the intent.
