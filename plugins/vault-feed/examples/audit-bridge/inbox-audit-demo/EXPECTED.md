# Expected triager behaviour on inbox-audit-demo (no triager code change)

## Ledger order

Filenames sorted lexicographically, by byte order — which here matches the order the
files were created:

1. `audit-declared-folders.md`
2. `audit-naming-badname.md`

Both audit-finding entries are listed with a `File` column and a recommended
disposition; the `Source` column shows `vault-audit`.

## Dispositions

The user's positional reply `adopt park` zips into pairs:

| # | file | status |
|---|---|---|
| 1 | `audit-declared-folders.md` | `adopt` |
| 2 | `audit-naming-badname.md`   | `park`  |

## Result

- Each file moves to `triaged/` with its `status` set and `decision_reason` non-empty.
- After the move, each `triaged/` file STILL carries `origin`, `finding_id`, and
  `related_files`. That is the dedup-vs-triaged invariant: `/vault-feed:import-audit`
  rebuilds its `seen` key set from exactly those fields across inbox ∪ triaged,
  so a disposed finding that lost them on the way out would be re-imported as new on
  the next audit — the resurrection the dedup exists to prevent.
