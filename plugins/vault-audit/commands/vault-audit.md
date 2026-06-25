---
description: "Audit your vault against its rules pack: linter fixes deterministic issues, judge reports judgment-call drift."
---

# /vault-audit — audit a vault against its rules pack

Dispatches two subagents sequentially in the foreground: the **Linter** (deterministic fixer) runs first, then the **Judge** (judgment reviewer). Both run in isolated git worktrees. Branches surface findings; main branch is untouched.

## Flags

| Flag | Effect |
|---|---|
| (none) | Vault-only mode: both agents. Linter runs categories A–E (+H if enabled). Judge runs all judgment checks. |
| `--dry-run` | Both agents detect but write/commit nothing. Returns would-have-been summary. |
| `--linter-only` | Skip Judge dispatch. |
| `--judge-only` | Skip Linter dispatch. |

`--linter-only` and `--judge-only` are mutually exclusive (error if both passed). Flags may combine: `--linter-only --dry-run`, etc.

## Behavior

### Step 1: Parse flags

Extract flag set from user invocation. Validate:
- If both `--linter-only` and `--judge-only` → emit error "Cannot pass both --linter-only and --judge-only" and exit.

### Step 2: Compute `{TS}`

Load and parse the rules pack — locate `rules.yaml` beside the plugin (`${CLAUDE_PLUGIN_ROOT}/rules.yaml`), falling back to `${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml` (the opinionated, proven starter conventions) if absent, then falling back to `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml` (the bare schema reference) as the final resort — and store the parsed object as `cfg` **once here**; all later `cfg.*` references (timezone, `cfg.report.dir`, `cfg.vault.root`, etc.) read from this object.

Read current UTC time, apply `cfg.vault.timezone_offset_hours` (default `0` = UTC), format as `YYYY-MM-DD-HHMM`. Example: `2026-05-18-1430`.

Compute the timestamp (with offset from the rules pack — replace `<OFFSET>` with the integer value). `perl` is bundled with Git on every platform:

```bash
perl -e 'use POSIX; print strftime("%Y-%m-%d-%H%M", gmtime(time + ($ARGV[0]*3600)))' <OFFSET>
```

If the rules pack is not yet loaded at this point, default to UTC (offset 0):

```bash
date -u +%Y-%m-%d-%H%M
```

Store as `{TS}`.

### Step 3: Preflight

Run the preflight helper:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh"
```

The script prints JSON `{ "unmerged_count": <int>, "branches": [<string>...] }` listing unmerged `linter/*` and `judge/*` branches.

If `unmerged_count > 0`:
- Display the list of unmerged branches.
- Ask user via AskUserQuestion: "Continue dispatch despite unmerged audit branches above? / Abort?" If Abort → exit.

### Step 4: Acquire lock

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh" acquire
```

Check exit code:
- `0` (acquired) → proceed.
- `1` (busy) → display lock status (PID + age), ask user via AskUserQuestion: "Wait (re-run /vault-audit later) / Force release and proceed / Abort."
  - Wait → emit "Lock busy. Re-run /vault-audit when the current run completes." and exit.
  - Force release → run `lock.sh force-release`, then re-acquire (`lock.sh acquire`).
  - Abort → exit.

### Step 5: Dispatch announce

Emit this **before** the Step 6 dispatch:

```
/vault-audit running (sequential foreground)
- Linter → linter/{TS}  (mode: {linter_mode})
- Judge → judge/{TS}  (mode: {judge_mode})

Agents run in isolated worktrees, one at a time (Linter → Judge). Main branch is untouched.
Session is busy for the duration of the run (~10–20 min) — this is foreground, not background.
```

If `--linter-only` or `--judge-only`, list only the dispatched agent.

### Step 6: Sequential foreground dispatch

**Sequential foreground is required** — Linter first, then Judge, each run in the foreground one at a time. NOT parallel, NOT `run_in_background`. Rationale: parallel background dispatch has caused worktree isolation failures and main-branch drift. Foreground-sequential keeps the orchestrator holding the session so a PWD-guard can catch any agent that strays onto the main branch. Parallel/background dispatch requires an explicit separate decision and an edit to this step.

Decide which agents to dispatch based on flags:
- Default / `--dry-run`: dispatch both.
- `--linter-only`: dispatch Linter only.
- `--judge-only`: dispatch Judge only.

Derive `linter_mode`:
- `--dry-run` → `dry-run`
- else → `vault-only`

Derive `judge_mode`:
- `--dry-run` → `dry-run`
- else → `vault-only`

Locate the rules pack files:
- `rules_path` = path to `rules.yaml` beside the plugin (one level up from this file, e.g. `${CLAUDE_PLUGIN_ROOT}/rules.yaml`). If not customized, fall back to `${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml`; if that is also absent, fall back to `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml`.
- `rules_md_path` = path to the judgment-checks markdown file, e.g. `${CLAUDE_PLUGIN_ROOT}/rules.md` (fall back to `${CLAUDE_PLUGIN_ROOT}/rules.starter.md`; if absent, fall back to `${CLAUDE_PLUGIN_ROOT}/rules.example.md`).

Construct prompts:

**Linter prompt:**

```
You are linter. Run the vault audit per your prompt.

Parameters:
- TS: {TS}
- mode: {linter_mode}
- branch_name: linter/{TS}
- rules_path: {rules_path}

Operate at the vault root resolved from the rules pack (cfg.vault.root). Return structured JSON per your spec.

PWD-GUARD (mandatory): you run in an isolated git worktree. Before ANY git write (add/commit/branch), run `git rev-parse --show-toplevel` and confirm it is your worktree path, NOT the main vault root. If you are on the main vault root, ABORT immediately, make no commits, and report `"errors": ["pwd-guard: landed on main, aborted"]`. Never `git checkout main`, never commit to main.
```

**Judge prompt:**

```
You are judge. Run the vault audit per your prompt.

Parameters:
- TS: {TS}
- mode: {judge_mode}
- branch_name: judge/{TS}
- rules_md_path: {rules_md_path}
- rules_path: {rules_path}

Operate at the vault root resolved from the rules pack (cfg.vault.root). Return structured JSON per your spec.

PWD-GUARD (mandatory): you run in an isolated git worktree. Before ANY git write (add/commit/branch), run `git rev-parse --show-toplevel` and confirm it is your worktree path, NOT the main vault root. If you are on the main vault root, ABORT immediately, make no commits, and report `"errors": ["pwd-guard: landed on main, aborted"]`. Never `git checkout main`, never commit to main.
```

Dispatch via the Agent tool **sequentially, in the foreground** — one Agent call per message, await each result before dispatching the next.

**Step 6a — dispatch Linter** (skip if `--judge-only`), await its structured JSON:

```
Agent(
  description: "Linter vault audit",
  subagent_type: "vault-audit:linter",
  isolation: "worktree",
  model: "sonnet",
  prompt: <linter prompt above>
)
```

**Step 6b — after Linter returns, dispatch Judge** (skip if `--linter-only`), await its structured JSON:

```
Agent(
  description: "Judge vault audit",
  subagent_type: "vault-audit:judge",
  isolation: "worktree",
  model: "sonnet",
  prompt: <judge prompt above>
)
```

Foreground dispatch means each Agent call blocks until the agent finishes and returns its JSON inline — there is no background notification to wait for.

### Step 7: Collect results (inline)

Foreground dispatch means each Agent call returns its structured JSON inline the moment that agent finishes — there is no background run, no harness notification, no polling. Collect Linter's JSON when its call returns, then (after dispatching Judge in Step 6b) collect Judge's JSON the same way. Proceed to Step 8 once all dispatched agents have returned.

### Step 8: Parse results

For each returned agent JSON, extract:
- `branch` (may be null if no findings and worktree was auto-cleaned).
- Linter: `autofixed` per-category counts + commit hashes, `requires_decision` list, `skipped_rate_limit` counts, `errors`.
- Judge: `findings` list, `report_path`, `skipped` list, `errors`.

Edge cases:
- If JSON parse fails → log `"errors": ["agent returned non-JSON output"]` for that agent, continue.
- If agent returned `errors: ["worktree creation failed"]` or similar → surface in the run summary; do not abort the other agent's processing.

### Step 9: Write run summary

Read `cfg.report.dir` from the rules pack (default `.vault-audit`). Write the summary to:

```
<cfg.report.dir>/vault-audit-summary-{TS}.md
```

Use this template (substitute all placeholders):

```markdown
---
tags:
  - type/audit-summary
  - status/inbox
date: {YYYY-MM-DD from TS}
---

# Vault audit summary — {TS}

## TLDR

- **Linter:** {N_total_autofix} autofixes, {M_requires_decision} requires-decision
- **Judge:** {K_findings} findings ({S_skipped} skipped by rate limit), report: `{judge_report_path}`
- **Mode:** {mode_label}  (vault-only / dry-run / linter-only / judge-only)
- **Branches:**
  - `linter/{TS}` ({linter_commit_count} commits; or "no findings — worktree auto-cleaned")
  - `judge/{TS}` ({judge_commit_count} commits; or "no findings — worktree auto-cleaned")

## Linter findings

### Autofixed

| Category | Count | Commit |
|---|---|---|
| Broken refs | {linter.autofixed.broken_refs.count} | `{linter.autofixed.broken_refs.commit}` |
| Frontmatter | {linter.autofixed.frontmatter.count} | `{linter.autofixed.frontmatter.commit}` |
| Naming | {linter.autofixed.naming.count} | `{linter.autofixed.naming.commit}` |

### Requires decision

(for each item in `linter.requires_decision`:)

1. **{path}** — {issue}
   - Suggested action: {suggested_action}

### Skipped (rate limit)

(for each non-zero entry in `linter.skipped_rate_limit`:)
- {category}: {count} more found, deferred to next run.

### Memory hygiene autofixes (H1/H2/H3)

(Render this section only if `linter.memory_hygiene` is non-null and has any non-empty array or non-zero `skipped_rate_limit` entry.)

**H1: Orphan files added to index** ({len})
(list files + index lines added)

**H2: Wikilinks rewritten** ({len})
(list file, before, after)

**H3: Dead index entries removed** ({len})
(list lines removed)

**Skipped (rate limit):**
(per subcategory h1/h2/h3 counts > 0)

## Judge findings

(for each finding in `judge.findings`, grouped by severity critical → warning → suggestion:)

### {severity}

| ID | Rule | Evidence | Suggested action |
|---|---|---|---|
| {id} | {rule} | {evidence} | {suggested_action} |

### Skipped (rate limit)

(for each item in `judge.skipped`:)
- `{id}` — {reason}

## Errors / warnings

(Combined from linter.errors + judge.errors. Omit this section if both are empty.)

## Next steps

1. Review `git log linter/{TS}` and `git diff main...linter/{TS}`. Merge the Linter branch if OK.
2. Review Judge report at `{judge_report_path}` and decide on findings.
3. Resolve requires-decision items listed above.
4. After approving merges, run Step 11 cleanup (delete branches + worktrees).
```

Note on git-mv: if the summary file (or any audit file) is later relocated with `git mv` after editing, edits to the moved-from path stay unstaged (status `RM`). Always `git add` the NEW path after a `git mv`-then-edit sequence.

### Step 9b: Emit the machine-readable findings file (bridge contract)

Additionally write `<cfg.report.dir>/findings-{TS}.json` for downstream consumers
(e.g. `/vault-feed:import-audit`). This is a serialization of data already in hand
from Step 8 — no new detection.

**Three invariants (do NOT copy the Step 9 summary-write pattern blindly — it differs):**

1. **Dry-run guard — explicit.** Write this file ONLY when `mode == vault-only`. If
   `--dry-run`, skip it entirely (the summary above is written in every mode, but the
   findings file must NOT be, or a preview leaks a real-looking contract file).
2. **Before lock-release.** This write is part of Step 9, so it completes while the
   lock (Step 4) is still held — Step 10 releases it. A consumer takes no audit lock,
   so a half-written file must never be visible as "newest".
3. **No-overwrite.** If `<cfg.report.dir>/findings-{TS}.json` already exists, write
   `findings-{TS}-2.json` (then `-3`, …) instead of overwriting. (Two runs sharing a
   minute-granular `{TS}` is rare — the lock serializes runs that each far exceed a
   minute — but never silently overwrite a contract file.)

Content (substitute placeholders; `judge_findings` and `linter_requires_decision` are
the Step 8 arrays verbatim — empty `[]` for any agent that did not run):

```json
{
  "schema": "vault-audit/findings@1",
  "ts": "2026-05-18-1430",
  "vault_root": ".",
  "mode": "vault-only",
  "judge_findings": [],
  "linter_requires_decision": []
}
```

Field descriptions:
- `schema`: always the literal string `"vault-audit/findings@1"` — version sentinel for consumers.
- `ts`: the `{TS}` value computed in Step 2 (e.g. `"2026-05-18-1430"`).
- `vault_root`: `cfg.vault.root` from the rules pack — informational only; no consumer trusts it as a resolved path.
- `mode`: the agent run mode — `"vault-only"` (this file is only ever written in vault-only mode, per invariant 1).
- `judge_findings`: the Step 8 `judge.findings` array verbatim; each item has keys `{id, severity, rule, evidence, suggested_action, related_files}`. Use `[]` if Judge did not run or returned no findings.
- `linter_requires_decision`: the Step 8 `linter.requires_decision` array verbatim; each item has keys `{category, path, issue, suggested_action}`. Use `[]` if Linter did not run or returned no requires-decision items.

Notes: `vault_root` is informational (may be the literal `"."`); no consumer trusts it
as a resolved path. Stage only this file with an explicit pathspec if anything is
committed; it normally stays an untracked artefact in `.vault-audit/` (gitignored).

### Step 10: Release lock + final user message

Release the lock:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh" release
```

Emit the final user message (adapt counts for zero-findings cases):

```
Vault audit complete.

Linter: {N} autofixes on `linter/{TS}` + {M} requires-decision.
Judge: {K} findings on `judge/{TS}` ({S} skipped). Report: `{judge_report_path}`.

Run summary: `<cfg.report.dir>/vault-audit-summary-{TS}.md`
Review: `git log linter/{TS}` / `git diff main...linter/{TS}`
```

If any agent had errors, list them explicitly in the message. If an agent had zero findings (e.g. "Linter: clean — 0 autofixes, 0 requires-decision"), say so.

### Step 11: Post-merge cleanup

The orchestrator's job does not end at the summary (Step 9) and lock release (Step 10). After the user reviews and **approves the merge** of an agent branch into main, clean up the branch and its worktree to prevent stale isolated worktrees from accumulating.

This step is **interactive and gated on the user's merge approval** — never auto-merge, never auto-delete a branch with unmerged findings.

1. **After an approved merge** of `linter/{TS}` or `judge/{TS}` into main:
   - Delete the branch: `git branch -d <role>/{TS}` (use `-d`, not `-D` — `-d` refuses to delete unmerged branches, a safety net).
   - Remove the agent's worktree: find it via `git worktree list`, then `git worktree remove <worktree-path>`. If the worktree was already auto-cleaned (no findings), skip.
   - Run `git worktree prune` to clear any stale administrative entries.

2. **Stale-branch sweep (preflight-driven).** Step 3 preflight already reports unmerged `linter/*` and `judge/*` branches (`unmerged_count` + `branches`). When that list is non-empty at the START of a run, for each branch older than ~7 days: check whether its findings are already disposed (e.g. already merged or otherwise resolved); if so, propose `git branch -D` + `git worktree remove` to the user via AskUserQuestion. Never delete unmerged work whose findings are not yet resolved.

Surface every deletion (and every skip/failure) in the run summary — fail-soft is not silent: a skipped or failed cleanup must appear as an explicit line, never silently omitted.

## Inputs

- Current branch must be `main` (else error and exit).
- `${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh` + `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh` must be available.
- Plugin agents `vault-audit:linter` and `vault-audit:judge` must be registered (the `<plugin>:<agent>` form is the Claude Code plugin-namespacing convention; check `/agents` only if a dispatch ever fails to resolve).
- A rules pack `rules.yaml` (or `rules.example.yaml` fallback) must be readable.

## Failure handling

- `git status` shows uncommitted changes on main → ask user via AskUserQuestion: "Continue anyway? (Agent worktrees are isolated; your main work is safe.) / Stash and continue. / Abort."
- Lock already held by a recent run → user-decision branch in Step 4 (Wait / Force / Abort).
- Preflight reports unmerged branches → user-decision in Step 3 (Continue / Abort).
- Agent dispatch errors (e.g. worktree creation fails) → release lock, emit error, exit. No partial state left behind.

## Co-author convention

All commits made by dispatched agents use:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```
