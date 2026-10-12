# Changelog

All notable changes to **vault-kit** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

vault-kit is a marketplace of independently versioned plugins — each
entry notes which plugin and version it covers. Tags on the repo follow the
per-plugin convention `<plugin>-vX.Y.Z` (the latest per plugin = the newest
entry below), plus the earlier bare-named `v0.3.0` / `v0.3.1` (before the
convention).

---

## Unreleased — vault-audit (documentation corrections)

**Corrections to published statements — documentation only, no behavior change.**

### Fixed
- **Withdrawn: the roughly-2 KB cap on hook output.** Since vault-audit
  0.4.1 the root `README.md`, `plugins/vault-audit/README.md`,
  `hooks.example.json`, `behavior-layer.example.md` and `PRINCIPLES.md` said that
  hook output is silently truncated; the plugin README, `hooks.example.json` and
  the 0.4.1 entry below put the figure at roughly 2 KB, and the 0.4.1 entry added
  that a hook printing the behavior layer delivered only its first third.
  That figure is not supported by the Claude Code documentation and is
  withdrawn. The documentation gives the cap on a hook's output as 10,000
  characters, and the example layer is below it. The 0.4.1 change itself
  stands — the layer is still loaded with a `@behavior-layer.md` import — but
  the cause given for it is withdrawn. What the docs do say, and the shipped
  text now states: output over the cap is replaced by a file path and a preview
  of up to the first 2,000 characters, and Claude Code does not ask the
  assistant to read that file — so a layer that grows past 10,000 characters
  would stop arriving whole.
- **Withdrawn: the claim that `cd <path> && <cmd>` is evaluated as a whole.**
  The plugin README said a compound command is matched as one string, so an
  allow rule for the second command never matches it, and that it prompts again
  for every directory you `cd` into. The Claude Code documentation says each
  part of a compound command is checked separately, and a `cd` inside the
  working directory is itself read-only. A `cd` outside the working directories
  still asks for approval for that path, so that part of the old advice stands.
  The "use absolute paths" habit is kept; the plugin README now gives the
  documented reasons.

## vault-persona 0.1.0 — 2026-08-07

**First release. Reworked before it shipped: the starters were unreachable.**

### Added
- `/vault-persona:persona` — apply a named audience overlay, list what is
  available, or clear it with `off`. A persona is a markdown file, so adding one
  means writing a file rather than editing a command.
- Starters `executive` / `non-technical` / `peer`, resolved from the plugin tree
  via `${CLAUDE_PLUGIN_ROOT}` and activated read-only in place — the plugin works
  on a fresh install with no config file, no personas directory and nothing
  copied. The listing merges your own directory with the starters and marks each
  row `user` or `starter`; a file of yours shadows a starter of the same name.
  Copying is only needed to *edit* a starter, and the listing prints that command.
- Name safety: an argument (and a configured default) must be letters, digits,
  spaces, hyphens or underscores. A dot, a slash or a traversal is rejected before
  resolution — a name indexes the merged view, it is not a path.
- `off` and `default` are reserved words, matched case-insensitively. A file named
  after one can never be activated, so the listing shows it as unreachable rather
  than offering it.
- Case-insensitive resolution against the actual directory listing. Files inside
  one tier differing only by case are an ambiguity error naming all of them —
  never a silent pick, because the wrong voice applied confidently reads as
  deliberate.
- A machine-output carve-out in the command spec: the overlay applies to prose the
  assistant composes and never to relayed machine-shaped output — positionally
  parsed ledgers, status lines carrying counts or fixed prefixes, structured
  payloads, quoted tool output. Where another command's spec says "verbatim", the
  persona yields.
- A closing limits line in every persona file. The documented fix for a drifted
  voice is re-reading the persona, which re-injected only the voice; the reminder
  travels with it. The command remains the canonical statement.

### Changed
- Config is optional and resolves in two real tiers: `vault-persona.yaml` at your
  project root, else the built-ins. Keys: `paths.personas`, `default`.
- Starter worked examples rewritten to obey the plugin's own safety clause. The
  executive sample kept a hedge it had been stripping and lost an invented cause
  and an invented commitment; the non-technical sample stopped answering a
  question its source never answered and keeps the word *failed*; the
  approximation guidance now requires marking an approximation and forbids
  rounding across a threshold.

### Removed
- `vault-persona.example.yaml` — it byte-duplicated the built-in defaults and its
  fallback tier was unreachable. The built-ins live in the command spec alone.
- Frontmatter `name:` (the filename is the name) and `language:` (no consumer; its
  only reachable effect was breaking English-only contracts elsewhere).

## vault-feed 0.3.0 — 2026-08-07

**A quiet source no longer erases its own history.** Audit + hands-on reproduction of
the pull → state → triage path; the two critical findings both silently destroyed data
while reporting success.

### Fixed
- **The watermark survived nothing.** `/vault-feed:pull` told the model to write epoch
  `0` for a source with no fresh items, claiming it "leaves the existing last_seen
  unchanged". It does not: the script overwrites unconditionally, so every quiet source
  had its watermark reset to zero and re-flooded the inbox with its whole history on the
  next pull. Deeper, the scout never returned an epoch at all, so even a busy source got
  no correct watermark. The scout now returns a per-source record (`slug`, `max_epoch`,
  `outcome`) and `feed-state.sh write` takes a `keep` epoch that holds the stored value
  while still recording the outcome.
- **`feed-state.sh write` silently dropped entries.** The write path demanded one exact
  entry shape and discarded anything else — an extra field, a different key order — with
  no error and no trace. It now parses as permissively as the read path, preserves extra
  fields, and passes an entry it cannot parse through verbatim rather than deleting it.
- **Triage applied decisions by position** against an order nothing pinned. A file
  arriving between the ledger pass and the write-through pass shifted every index, and
  the counts still matched, so each disposition landed on the wrong entry with nothing to
  see. Ledger order is now the byte-order filename sort, and the write-through dispatch
  carries explicit `(filename, status)` pairs. A file that vanishes costs one `FAILED:`
  line instead of corrupting the rest of the batch.
- **A failed move stranded an entry forever.** If the move failed after the frontmatter
  edit, the entry sat in the inbox with a non-inbox status, and the "only process
  `status: inbox`" rule stepped over it on every subsequent run. Each run now retries the
  move once and reports `RESUMED:` or `FAILED:`.
- **An unedited config classified live sources.** With no `vault-feed.yaml`, `interests`
  is the shipped comment block, and the scout was told it is the sole basis for bucketing.
  `/vault-feed:pull` now stops with setup instructions instead of filling the inbox with
  confident noise.
- **A second pull on one day overwrote that day's digest.** It now appends a timestamped
  section.
- **The audit bridge suppressed new violations.** The dedup key used the *rule* id, so
  disposing one violation of a rule silently swallowed every future violation of it — the
  rerun fixture cheerfully reported "0 new" while a second missing folder arrived. The key
  now carries the finding's `related_files` as an instance discriminator.
- Unbounded first pull (now a documented newest-few sample per source, not a backfill);
  `feed-state.sh read` without a slug died on `set -u` with an exit code indistinguishable
  from data (now usage, exit 2); unquoted `${CLAUDE_PLUGIN_ROOT}` and `<paths.state>`
  broke on paths with spaces; `import-audit`'s config fallback was unanchored and had no
  error path; two citations pointed at a spec that is not shipped; the plugin README named
  `/vault-audit` instead of `/vault-audit:vault-audit`.

### Changed
- **Scout return contract** (breaking): `failed[]` and `digest_path` are replaced by
  `sources[]`. The state write and the `FAILED:` summary now read one array, so they
  cannot disagree about which source broke. `ledger_path` is likewise gone from the
  triager return.
- **One resolution convention.** `/vault-feed:pull` resolves config, feeds, *and* the
  significance criteria and inlines all three into the dispatch; the scout has no Bash and
  could never reach the fallbacks it was told to try. It reads no config file at all now.
- `feed-state.sh` writes through a temp file, refuses to rewrite a state file that is not
  a JSON object (exit 65), and rejects an epoch or outcome it cannot round-trip (exit 64).

## vault-audit 0.4.2 — 2026-08-07

**A rules-based auditor that quietly audited against someone else's rules, a timestamp
that died west of UTC, and a report the user never received.**

### Fixed
- **The rules pack is now read from YOUR vault first.** Resolution is
  `<cwd>/rules.yaml` → shipped `rules.starter.yaml` → shipped `rules.example.yaml`
  (same for the judgment pack `rules.md`). Previously only the plugin directory was
  consulted, so a pack written in your own vault was never read and the run silently
  audited against the shipped starter conventions — the worst failure available to a
  tool whose premise is "audit against your declared rules", because the output looks
  right. Observed live: a demo vault's own `rules.yaml` ignored, most findings pure
  noise from the starter naming pattern. Every run now prints one line naming the file
  it loaded and which tier it came from. The plugin directory was also the wrong home
  for user data — a reinstall replaces that tree.
- **`{TS}` crashed for every timezone west of UTC.** The perl one-liner took the offset
  as a bare argument, so `-5` was parsed as a perl switch and the command died at its
  first output-producing step. Argument list now terminated with `--`.
- **The leak gate no longer certifies files it could not read.** A binary or UTF-16 file
  was skipped with a note and exit `0`, while an *unreadable* file failed the run —
  the same epistemic state with opposite verdicts, and a leak inside a UTF-16 `.md`
  passed the gate. Unscannable files are now listed and the run exits `2`; to declare
  one out of scope, `--exclude` it, which puts the decision on the record. Every verdict
  line carries both the scanned and the unscannable count.
- **`sk-` no longer matches ordinary words.** The credential pattern had no left
  boundary, so `risk-assessment-checklist-2026.md`, `task-management-…` and `kiosk-…`
  matched in content *and* in filenames — false positives in exactly the place a gate
  must be trustworthy. Windows user-profile paths are now also caught in their
  forward-slash and Git-Bash mount spellings (drive-colon and `/c/`-prefixed forms).
- **The judgment report reaches the user.** The Judge wrote its report inside its own
  worktree, the user was pointed at that path in *their* checkout, and cleanup then
  deleted the worktree. The Judge now returns the report as text (`report_markdown`)
  and the command writes it to `<vault>/<report.dir>/report-<TS>.md`; if the report is
  missing, the summary says `FAILED: judge report missing` instead of naming a file
  that does not exist. The Judge no longer commits anything and no longer holds a
  Write tool.
- **The Linter's branch is created, not assumed.** The isolated worktree opens on a
  harness-generated branch; nothing created `linter/<TS>`, yet the Linter's own guard
  refuses to write unless it is on exactly that branch — so the autofix feature lived
  on agent improvisation. The dispatch now pins the first action: `git switch -C
  <branch_name>` inside the worktree, then verify. Observed live before the fix: one
  agent improvised the switch, the design owed it a sentence.
- **The base branch is whatever your vault has checked out.** "Current branch must be
  `main`" and the uncommitted-changes prompt were unnumbered prose that a literal walk
  of the steps never reached, and the hardcoded name locked out `master` / `trunk` /
  working-branch vaults. Both are now a numbered step that derives the base branch,
  refuses a detached HEAD, and asks before running on a dirty tree; every later
  reference uses it.
- **A vault that is not a git repository now fails before the lock is taken**, not at
  worktree creation with the lock held (which left the next run facing a phantom busy
  lock). `preflight.sh` reports `is_repo`, and the command passes `--repo-path` — it
  had always reported on its own working directory instead of the configured vault.
- **The lock is per-vault and honest about being a timer.** It lived in one
  machine-global directory, so auditing one vault blocked an unrelated audit of
  another; and the PID it recorded belonged to the already-exited lock script, making
  its liveness check always false while looking authoritative (a recycled PID would
  have wedged it forever). The command now derives the lock directory from the vault's
  absolute path, the lockfile records that path, `release` warns on a mismatch, and
  the documented semantics are the max-age timer they always were.
- **Agents are told where the rules pack is.** Both agent prompts said the pack sits
  "one level up from this agent file" — something a dispatched subagent cannot resolve
  — while the orchestrator passed an unexpanded `${CLAUDE_PLUGIN_ROOT}/rules.yaml`
  string. The orchestrator resolves once, to an absolute path, and passes it; the
  agents just read it. Config-relative paths resolve against each agent's own worktree,
  now stated explicitly.
- **Broken-link repair is bounded.** Category A asked for a ≥90% similarity comparison
  of each broken basename against every file in the vault, with no tool to do it.
  Candidates are now the containing directory plus files sharing the first filename
  token, capped per link, and hitting the cap surfaces as requires-decision rather
  than a silent partial pass.
- Invalid `--exclude` regexes are reported as invalid regexes (exit `2`) instead of
  surfacing as "matched all N files"; `--tracked-only` with a single-file `--path` is
  a loud usage error instead of being silently ignored; the `FAIL:` line no longer
  conflates a filename hit and a content hit into an unexplained total.

### Changed
- **Quickstart is actually runnable:** copy `examples/demo-vault` out, `git init`,
  commit, and run from inside it — the demo's own `rules.yaml` is now found.
  `examples/EXPECTED-FINDINGS.md` re-derived category by category against that pack,
  with the per-category cardinality rules stated (one frontmatter finding per file
  listing its missing fields; one duplicate finding per basename).
- The starter `update-protocol-gap` judgment check reads the vault's own history
  (`git -C <vault root>`) instead of whatever repository encloses the working directory.
- `naming.exempt_paths` and `frontmatter.exempt_paths` in both packs no longer re-list
  paths that `governance_paths` already skips globally; what remains carries its reason.
- Behavior layer gains agent-dispatch addenda (an in-flight agent is not a result;
  read a return for what it structurally cannot know; try to break gate code before
  calling it green; vary the model across verify seats) and two reflex rules
  (proxy-vs-goal, and planting a clock where the decision reflex actually looks).
- The dispatch call site is deliberately silent about the agent model: it is declared
  once in each agent's frontmatter, where editing it has an effect.
- Living working files (`STATE.md`, `roadmap.md`, `active-scope.md`, …) documented as
  a named exempt class — exempt by basename rather than folder, with the reason stated
  in both packs and in `PRINCIPLES.md`.
- Wording pass across the shipped surface: the starter pack, the behavior layer and the
  dispatch rationale describe what they do and what they guard against, without
  reference to where they came from.

## vault-audit 0.4.1 — 2026-08-05

**Moves behavior-layer delivery from a SessionStart hook to an instructions-file import.**

*(Stated cause corrected after release: this entry originally attributed the
change to a hook-output cap measured at roughly 2 KB, under which users received
about the first third of the layer. That figure is withdrawn — see Unreleased.)*

### Fixed
- **Behavior-layer delivery.** Every documented route pointed at a SessionStart
  hook that prints the file (`cat behavior-layer.md`). The layer is now loaded
  from the instructions file the assistant reads every session (one
  `@behavior-layer.md` line in `CLAUDE.md`), which loads it into context at
  launch. Corrected in all four places that carried the old
  route — `hooks.example.json`, `plugins/vault-audit/README.md`, the root
  `README.md`, and the header of `behavior-layer.example.md` itself — plus a
  delivery clause in `PRINCIPLES.md`, since delivery is part of the design
  rather than a footnote.
- `hooks.example.json` no longer ships a `SessionStart` block at all. The
  reason it is absent is recorded in the file so it does not get re-added; the
  `PreToolUse` allowlist-guard pattern stays, because gating a tool call is
  what hooks are genuinely good for, unlike injecting a large block of text.

---

## vault-audit 0.4.0 — 2026-08-05

**The publish gate goes user-facing + repo CI.**

### Added
- `/vault-audit:leak-scan` — the leak gate as a command: scan any path (default:
  your vault root) against the shipped generic patterns plus an optional private
  `--extra-patterns` file; `--tracked-only` and `--exclude` pass through. Exit
  codes: `0` clean / `1` leak / `2` misconfigured-or-nothing-scanned, fail-loud.
  Optional `leak_scan:` defaults block in the rules pack, and a documented
  **Limits & discipline** list (case-sensitivity, metachar escaping,
  positive-control ritual) — a gate you over-trust is worse than no gate.
- GitHub Actions CI (`.github/workflows/ci.yml`): script syntax checks, leak-gate
  positive/negative self-test, hardening controls (the fail-open vectors below
  stay closed), repo self-gate (`--tracked-only` over all tracked files),
  feed-state smoke.

### Hardened (leak-audit.sh — adversarial review before this release)
- **Zero files scanned now refuses to certify** (exit `2`): an empty dir, an
  extension-less tree, or `--tracked-only` with nothing tracked used to print
  `OK: no leaks` having checked nothing.
- **Filenames are scanned too** (relative to the scan root): an instance literal
  or credential in a path used to pass a content-only scan.
- **Binary/UTF-16 files are skipped VISIBLY** (`SKIP (binary/UTF-16…)` + a count
  in the verdict): a UTF-16 file — PowerShell's `>` default — used to false-clean
  silently. The clean verdict now always carries the scanned-file count.
- `--tracked-only` reads `git ls-files` with `core.quotePath=false`: a clean
  non-ASCII filename used to fail the run as "unreadable".

### Changed
- Root README: a single **Install** block up top for both plugins (they are two
  separate installs — adding the marketplace alone installs nothing), plus a
  "Not using Claude Code?" portability note for other coding agents; the Roadmap
  names the next planned tool (git-truth staleness check).
- Marketplace manifest gains a top-level `description` (clears the
  `claude plugin validate` warning).

_Tag: `vault-audit-v0.4.0`._

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
- Agents renamed to **`linter` / `judge`** — names that describe the role without
  prior context. *(Earlier internal names redacted for publication, 2026-08-07.)*

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
