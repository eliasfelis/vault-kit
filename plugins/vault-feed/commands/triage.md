---
description: "Surface the feed inbox as a batch ledger, collect batched disposition decisions, and move each entry to triaged with a status and reason."
---

# /vault-feed:triage

Orchestrates the full triage flow: config resolution → preflight inbox check →
triager dispatch (ledger pass) → batched user disposition → triager dispatch
(dispositions pass) → per-status tally.

---

## Config resolution (the command owns this)

Resolve the config file before any other step:

1. Look for `vault-feed.yaml` at the vault/working root.
2. If absent, fall back to `"${CLAUDE_PLUGIN_ROOT}/vault-feed.example.yaml"`.
3. If neither exists, STOP with `Cannot resolve config: neither vault-feed.yaml nor
   the bundled vault-feed.example.yaml exists.` Do not dispatch on a guess.

Parse the resolved config and extract:
- `paths.inbox` — where pending entries live.
- `paths.triaged` — destination after disposition.
- `statuses` — the ordered list of valid dispositions
  (e.g. `["adopt","park","reject","experiment"]`).

Never hardcode paths or status values. Pass the **resolved config object** to the
triager in each dispatch so the triager never needs to re-resolve the config itself.

---

## Step 1 — Preflight

Glob `<paths.inbox>/*.md`.

If the result is empty, print:

```
inbox empty — run /vault-feed:pull first
```

and STOP. Do not dispatch the triager.

---

## Step 2 — Build and surface the ledger

### Ledger order is pinned

Ledger order is the inbox `.md` **filenames sorted lexicographically, by byte order** —
the same sort here and in the triager, on both dispatches.

It is pinned because the user answers positionally ("adopt park experiment") against a
live directory. Unpinned, a file arriving between the two dispatches shifts every index
by one and each decision lands on the wrong entry — silently, because the counts still
match. Positions exist for the human reading the table; the dispositions dispatch
carries explicit `(filename → status)` pairs, so a shift cannot misapply a decision.

### Dispatch — ledger mode

```yaml
subagent_type: vault-feed:triager
prompt: |
  Config (resolved):
  <inline the full resolved config object as YAML>

  Mode: ledger.
  Build and RETURN the batch ledger — the rendered table and recommendation block
  for the user, plus the machine-readable ledger array. Dispose nothing. Do not
  prompt the user.
```

**Triager ledger-mode return:**

```json
{
  "ledger": [
    { "file": "<filename.md>", "title": "<title>", "source": "<source>",
      "value": "<v>", "effort": "<e>", "confidence": "<c>",
      "recommended": "<status>" }
  ],
  "resumed": [ { "file": "<filename.md>" } ],
  "skipped": [ { "file": "<filename.md>", "reason": "<why>" } ],
  "failed":  [ { "file": "<filename.md>", "reason": "<why>" } ]
}
```

`ledger[]` is in the pinned order. `resumed` / `skipped` / `failed` cover inbox files
that are not up for disposition this run (triager Step 2a).

The **command** then:

1. Surfaces the triager's rendered table and recommendation block **verbatim**.
2. Prints one line per entry in `resumed`, `skipped`, and `failed` — always, so a
   shorter table is never unexplained:

```
RESUMED: <file> — already dispositioned; move completed
SKIPPED: <file> — <reason>
FAILED:  <file> — <reason>
```

3. If `ledger[]` is empty, print `Nothing to dispose.` and STOP. Do not dispatch
   again — the lines above already say what happened to every file.
4. Otherwise, follow with the disposition prompt (owned by the command, not the
   triager):

```
Dispositions — reply with one status per item in order, space-separated
(e.g. "adopt park experiment"), or "all <status>" to apply the same to all.
Valid statuses: <comma-separated list from config>.
Type a single item number to get more detail before deciding.
```

Wait for the user's batched disposition answer before proceeding to Step 3.

---

## Step 3 — Write-through (dispositions dispatch)

Parse the user's answer into an ordered list of statuses:

- Space-separated: `"adopt park experiment"` → `["adopt", "park", "experiment"]`.
  After splitting, validate EACH token against the config `statuses` list. If any
  token is invalid, print an error naming the bad value(s) and re-prompt — never pass
  an invalid status into a dispatch. Also confirm the token count matches the number
  of ledger items; if not, print the mismatch and re-prompt.
- `"all <status>"`: validate `<status>` is in the config `statuses` list, then
  expand to a list of that status repeated for every ledger item. If the status is
  not in the config list, print an error and re-prompt (do not proceed with invalid
  input).

Now zip that list against the ledger you already hold — `ledger[i].file` with
`statuses[i]` — into explicit `(filename → status)` pairs. Do NOT re-glob the inbox to
rebuild the order: the pairs must come from the ledger the user actually saw, and the
directory may have changed since.

Dispatch the triager again in **dispositions mode**:

```yaml
subagent_type: vault-feed:triager
prompt: |
  Config (resolved):
  <inline the full resolved config object as YAML>

  Mode: dispositions.
  dispositions:
    - { file: "<filename-1.md>", status: "<status-1>" }
    - { file: "<filename-2.md>", status: "<status-2>" }

  Apply each disposition to the NAMED FILE: set its status and decision_reason, then
  move it from <paths.inbox> to <paths.triaged>. Match by filename only, never by
  position. Return the result JSON.
```

Wait for the triager to return its JSON result before proceeding.

**Triager return shape:**

```json
{
  "triaged": [
    {
      "file": "<filename.md>",
      "title": "<title string>",
      "status": "<disposition applied>",
      "decision_reason": "<reason string>"
    }
  ],
  "resumed": [ { "file": "<filename.md>" } ],
  "failed":  [ { "file": "<filename.md>", "reason": "<why>" } ]
}
```

`resumed[]` is usually empty here — it only fills if an entry became stranded between
the two dispatches. Print those lines too (Step 4).

---

## Step 4 — Report

Print a per-status tally, then list the paths of moved files:

```
Triage complete:
  <status-1>:  N
  <status-2>:  N
  ... (one line per status in config `statuses`)
```

The tally iterates over the config `statuses` list (not a hardcoded list of names) —
print one line per status even if its count is 0.

Then print the `<paths.triaged>/<filename>` path for every successfully moved entry,
taking each `file` from the triager's `triaged[]`:

```
Moved to <paths.triaged>/:
  <filename-1.md>   [adopt]
  <filename-2.md>   [park]
  ...
```

Then one line per entry in the triager's `resumed[]` (an entry stranded between the two
dispatches whose move completed), and one per entry in its `failed[]` — a file that
vanished between the dispatches, or whose write or move failed:

```
RESUMED: <filename.md> — already dispositioned; move completed
FAILED:  <filename.md> — <reason>
```

A failed entry never shifts the others: dispositions are matched by filename, so the
rest apply exactly as the user decided.

If no files moved (all errors), print:

```
No files moved. Check warnings above.
```

---

## Error handling

| Failure                          | Behaviour                                                    |
|----------------------------------|--------------------------------------------------------------|
| Config absent                    | Fall back to `vault-feed.example.yaml`; stop if neither found|
| Inbox empty                      | Print message and stop (Step 1)                              |
| Inbox non-empty but ledger empty | Print the RESUMED/SKIPPED/FAILED lines, then `Nothing to dispose.`; do not dispatch again |
| User provides invalid status     | Reject with clear message; re-prompt before dispatching      |
| File vanished between dispatches | Triager reports it in `failed[]`; print `FAILED:`, apply the rest |
| Triager returns empty triaged[]  | Print "No files moved." report                               |
| Triager dispatch fails           | Surface the error; do not proceed to Step 4                  |
| paths.triaged dir absent         | Triager creates it before moving (triager spec §Step 4)      |

---

## Flags

| Flag      | Meaning                                                    |
|-----------|------------------------------------------------------------|
| (none)    | Full interactive triage run                                |
