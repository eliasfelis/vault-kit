# Expected triager behaviour on demo-inbox

- The ledger lists all 3 items with a recommended disposition each.
- Scripted dispositions [adopt, park, experiment] write through:
  - item-managed-agents.md  -> triaged/ status:adopt, decision_reason set
  - item-mcp-linear.md      -> triaged/ status:park, decision_reason set
  - item-kb-wiki-pattern.md -> triaged/ status:experiment, decision_reason set
- inbox/ is emptied of the 3 items (moved, not copied).
