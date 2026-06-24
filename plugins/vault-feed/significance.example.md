# Significance filter (read by the `scout` agent)

For each fetched item, decide ONE bucket by comparing it to the user's `interests`:

- **actionable** — TWO independent paths, either one is sufficient:
  (a) changes a capability the user depends on (a tool they run has a new/changed
  behaviour that affects their workflow), OR
  (b) is directly applicable to a tracked topic (a new API, pattern, or technique
  usable within a topic the user tracks counts as actionable even if no tool they
  already run has changed).
  Write a full inbox entry. First-pass estimate:
  value/effort/confidence ∈ {low, med, high}.
- **news-tier** — item is in-domain (the tool or topic IS tracked by the user)
  but has no actionable surface: only ambient signal, direction-of-travel, or a
  minor/cosmetic release of a tracked tool with nothing concrete to apply. One
  paragraph in the digest; no inbox entry.
- **reject** — item is out-of-domain (tool or topic the user does NOT track) OR
  is a feature in a wrong-tool that does not generalise to their stack. Also:
  benchmark posturing, funding rounds, hype with no technical content. Dropped
  (logged, not written).

**Boundary cues**

| Pair | Turning condition |
|---|---|
| actionable vs news-tier | Is there a capability change or something directly applicable to a tracked topic? → actionable. Only ambient signal with nothing concrete to apply? → news-tier. |
| news-tier vs reject | Is the tool or topic tracked by the user? → news-tier (even if minor). Not tracked and does not generalise? → reject. |
| actionable path (a) vs (b) | Path (a) = a tool you already run changed. Path (b) = a technique/API/pattern usable in a topic you track (tool need not exist yet in your stack). Either path alone is sufficient. |

This is a GENERIC EXAMPLE keyed to a sample `interests`. The user's real
`interests` (config) is the actual yardstick. Calibrate against
`examples/significance-eval/eval-set.md` (≥80% match required).
