# Changelog

All notable changes to **vault-kit** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

vault-kit is a marketplace of two plugins that version **independently** — each
entry notes which plugin and version it covers. Tags on the repo:
`vault-audit-v0.3.2`, `vault-feed-v0.2.0`, plus the earlier `v0.3.0` / `v0.3.1`
(bare-named, before the per-plugin tag convention).

---

## vault-audit 0.3.2 · vault-feed 0.2.0 — 2026-06-25

**Audit → feed bridge.** The two plugins now connect: findings from an audit can
flow into the feed's triage backlog, so audit findings and feed items are
disposed in one ledger.

### Added
- **vault-audit** emits a machine-readable `.vault-audit/findings-<TS>.json` after
  a run (judge findings + linter "requires-decision" items). Additive and guarded:
  written only in vault-only mode, before lock release, never overwriting an
  existing file.
- **vault-feed** gains `/vault-feed:import-audit` — adapts each audit finding into
  a `type: audit-finding` inbox entry, then `/vault-feed:triage` disposes audit
  findings and feed items together.
- Dedup keys on `(origin, finding_id)` — stable across re-runs, so an
  already-disposed finding never resurrects. Memory-scope findings are excluded.

_Tags: `vault-audit-v0.3.2`, `vault-feed-v0.2.0`._

## vault-feed 0.1.0 — 2026-06-24

**Second plugin: vault-feed** — a curated-feed reader with relevance filtering and
interactive triage.

### Added
- `scout` agent — fetches each configured feed, scores every item against a
  user-authored `interests` block, and buckets into actionable / news-tier / reject.
- `triager` agent — batch-ledger disposition: presents a summary table with a
  recommended disposition per item, then moves each to `triaged/` with a status
  and reason.
- Commands `/vault-feed:pull` (onboarding + fetch + inbox/digest write, fail-soft
  with an explicit `FAILED:` summary) and `/vault-feed:triage`.
- Opinionated 21-source starter feed set + a config-driven significance filter
  keyed off the user's `interests` (not a hardcoded roadmap).

_Tag: `vault-feed-v0.1.0`._

## vault-audit 0.3.1 — 2026-06-24

### Changed
- `leak-audit` gains an opt-in `--tracked-only` mode that enumerates `git ls-files`
  instead of walking the filesystem. Closes two gate defects: the fragile
  `--exclude` regex for ignored scratch files, and an extension-allowlist that
  could fail open — coverage is now fail-closed (a secret in a tracked file with an
  unknown extension is caught). Default behaviour unchanged.

_Tag: `v0.3.1`._

## vault-audit 0.3.0 — 2026-06-23

### Changed
- **Cross-platform.** The three helper scripts (`lock` / `preflight` / `leak-audit`)
  moved from PowerShell to a single bash rail — now runs on Windows (Git Bash),
  macOS, and Linux. The engine (`linter` / `judge` agents) was already OS-agnostic.
- The leak scanner uses a perl regex superset of the prior patterns; exit contract
  unchanged (0 clean / 1 leak / 2 missing-pattern-file, fail-loud).

### Removed
- The `.ps1` helper scripts (superseded by the bash rail).

_Tag: `v0.3.0` (first formal release tag + GitHub Release)._

## vault-audit 0.2.0 — 2026-06-23

**The method** — pairs the engine with the conventions and discipline it audits for.

### Added
- `rules.starter.*` — opinionated, proven default rules; now the agents' out-of-box
  fallback (`rules.yaml` → `rules.starter.*` → `rules.example.*`).
- `PRINCIPLES.md` — the CORE workflow + seven discipline rules
  (subtraction-not-mechanism, fail-soft ≠ silent, defer-to-a-concrete-channel,
  one-source-of-truth, verify-live-state, atomic-commits-by-workstream,
  outbound-send-gate) + naming / session-summary / changelog / memory-hygiene.
- `behavior-layer.example.md` + `hooks.example.json` — a coaching-layer pattern and
  a SessionStart-hook wiring example.

### Changed
- Agents renamed `junker` / `builder` → **`linter` / `judge`** — generic names that
  read without internal lore.

## vault-audit 0.1.0 — 2026-06-22

**Initial public release** — audit a Claude-Code markdown knowledge vault against
its own declared rules.

### Added
- `vault-audit` plugin with two agents: `linter` (deterministic fixer — broken
  refs, frontmatter rot, naming violations, duplicates, stale files; low-risk
  autofixes on an isolated branch) and `judge` (judgment reviewer — declaration-vs-
  reality drift → a standalone report).
- A rule-engine design: detection logic is generic; the **rules** are user-owned
  (`rules.example.*`), so the auditor runs against *your* declared conventions.
- A two-layer leak gate so the published repo carries generic patterns only, with
  any instance-specific literals supplied from outside the repo.
- A bundled `demo-vault` with seeded findings for a dry run.
