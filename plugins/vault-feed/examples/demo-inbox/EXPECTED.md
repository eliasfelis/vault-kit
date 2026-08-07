# Expected triager behaviour on demo-inbox

## Ledger order

The ledger is the inbox `.md` filenames sorted lexicographically, by byte order — not
whatever sequence the glob returned. For this fixture that is:

1. `item-kb-wiki-pattern.md`
2. `item-managed-agents.md`
3. `item-mcp-linear.md`

The ledger lists every one of them, each with a `File` column and a recommended
disposition.

## Dispositions

Each entry keeps the disposition its value/effort/confidence argue for; only the
positions changed when the sort was pinned. The user's positional reply against the
table above is therefore `experiment adopt park`, which the command zips into pairs:

| # | file | status | why |
|---|---|---|---|
| 1 | `item-kb-wiki-pattern.md` | `experiment` | high value, high effort, med confidence — try before committing |
| 2 | `item-managed-agents.md`  | `adopt`      | high value, med effort, high confidence |
| 3 | `item-mcp-linear.md`      | `park`       | med value, med confidence — no reason to act now |

The `dispositions` dispatch carries those `(file, status)` pairs, and the triager
matches on the filename, so the result does not depend on the positions surviving
between the two dispatches.

## Result

- Each file moves to `triaged/` with its `status` set and `decision_reason` non-empty.
- `inbox/` is emptied of them (moved, not copied).
- `triaged[]` returns one object per moved file, each carrying its `file`.
- `failed[]` is empty; nothing is skipped or resumed.
