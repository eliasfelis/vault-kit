# Significance filter (read by the `scout` agent)

For each fetched item, decide ONE bucket by comparing it to the user's `interests`:

- **actionable** — changes a capability the user depends on, OR is directly
  applicable to a tracked topic. Write a full inbox entry. First-pass estimate:
  value/effort/confidence ∈ {low, med, high}.
- **news-tier** — real signal, no action (industry direction, a tracked tool's
  non-actionable release). One paragraph in the digest; no inbox entry.
- **reject** — benchmark posturing, funding rounds, wrong-tool features,
  out-of-domain topics. Dropped (logged, not written).

This is a GENERIC EXAMPLE keyed to a sample `interests`. The user's real
`interests` (config) is the actual yardstick. Calibrate against
`examples/significance-eval/eval-set.md` (≥80% match required).
