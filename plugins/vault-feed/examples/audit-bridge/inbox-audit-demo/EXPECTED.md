# Expected triager behaviour on inbox-audit-demo (no triager code change)
- Ledger lists both audit-finding entries with a recommended disposition each
  (Source column shows `vault-audit`).
- Scripted dispositions [adopt, park] write through:
  - audit-declared-folders.md  -> triaged/ status:adopt, decision_reason set
  - audit-naming-badname.md     -> triaged/ status:park, decision_reason set
- After the move, each triaged/ file STILL carries `origin` and `finding_id`
  (the dedup-vs-triaged invariant — spec §6/§9).
