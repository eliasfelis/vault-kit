---
description: "Surface the feed inbox as a batch ledger, collect batched disposition decisions, and move each entry to triaged with a status and reason."
---

# /vault-feed:triage

Orchestrates the full triage flow: config resolution → preflight inbox check →
triager dispatch (ledger pass) → batched user disposition → triager dispatch
(write-through pass) → per-status tally.

---

## Config resolution (the command owns this)

Resolve the config file before any other step:

1. Look for `vault-feed.yaml` at the vault/working root.
2. If absent, fall back to `${CLAUDE_PLUGIN_ROOT}/vault-feed.example.yaml`.

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

Dispatch the triager in **read-only ledger mode** (no scripted-dispositions, no user
prompting) to scan `<paths.inbox>` and BUILD AND RETURN the batch ledger only:

```yaml
subagent_type: vault-feed:triager  # TODO-VERIFY prefix (confirmed at install in Task 9)
prompt: |
  Config (resolved):
  <inline the full resolved config object as YAML>

  Run in read-only ledger mode (no scripted-dispositions).
  Build and RETURN the batch ledger (summary table + recommendation block).
  Do NOT prompt the user — return the ledger to the command and stop.
```

The triager returns the ledger (summary table + recommendation block) and exits.

The **command** then:
1. Surfaces the triager's ledger output **verbatim** to the user.
2. Immediately follows with the disposition prompt (owned by the command, not the triager):

```
Dispositions — reply with one status per item in order, space-separated
(e.g. "adopt park experiment"), or "all <status>" to apply the same to all.
Valid statuses: <comma-separated list from config>.
Type a single item number to get more detail before deciding.
```

Wait for the user's batched disposition answer before proceeding to Step 3.

---

## Step 3 — Write-through

Parse the user's answer into an ordered list of statuses:

- Space-separated: `"adopt park experiment"` → `["adopt", "park", "experiment"]`.
  After splitting, validate EACH token against the config `statuses` list. If any
  token is invalid, print an error naming the bad value(s) and re-prompt — do NOT
  pass an invalid status into `scripted-dispositions`. Also confirm the token count
  matches the number of ledger items; if not, print the mismatch and re-prompt.
- `"all <status>"`: validate `<status>` is in the config `statuses` list, then
  expand to a list of that status repeated for every ledger item. If the status is
  not in the config list, print an error and re-prompt (do not proceed with invalid
  input).

Build `scripted-dispositions` from the parsed list and dispatch the triager again
in **write-through mode**:

```yaml
subagent_type: vault-feed:triager  # TODO-VERIFY prefix (confirmed at install in Task 9)
prompt: |
  Config (resolved):
  <inline the full resolved config object as YAML>

  scripted-dispositions: [<status1>, <status2>, ...]

  Apply the scripted dispositions in ledger order: set each entry's status and
  decision_reason, then move it from <paths.inbox> to <paths.triaged>.
  Return the result JSON.
```

Wait for the triager to return its JSON result before proceeding.

**Triager return shape:**

```json
{
  "triaged": [
    {
      "title": "<title string>",
      "status": "<disposition applied>",
      "decision_reason": "<reason string>"
    }
  ],
  "ledger_path": null
}
```

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

Then print the `<paths.triaged>/<filename>` path for every successfully moved entry:

```
Moved to <paths.triaged>/:
  <filename-1.md>   [adopt]
  <filename-2.md>   [park]
  ...
```

If no files moved (all errors), print:

```
No files moved. Check warnings above.
```

---

## Error handling

| Failure                          | Behaviour                                                    |
|----------------------------------|--------------------------------------------------------------|
| Config absent                    | Fall back to `vault-feed.example.yaml`; warn if neither found|
| Inbox empty                      | Print message and stop (Step 1)                              |
| User provides invalid status     | Reject with clear message; re-prompt before dispatching      |
| Triager returns empty triaged[]  | Print "No files moved." report                               |
| Triager dispatch fails           | Surface the error; do not proceed to Step 4                  |
| paths.triaged dir absent         | Triager creates it before moving (triager spec §Step 4)      |

---

## Flags

| Flag      | Meaning                                                    |
|-----------|------------------------------------------------------------|
| (none)    | Full interactive triage run                                |
