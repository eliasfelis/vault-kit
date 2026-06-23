---
description: "Audit your vault against its rules pack: junker fixes deterministic issues, builder reports judgment-call drift."
---

# /vault-audit — audit a vault against its rules pack

Dispatches two subagents sequentially in the foreground: the **Junker** (deterministic fixer) runs first, then the **Builder** (judgment reviewer). Both run in isolated git worktrees. Branches surface findings; main branch is untouched.

## Flags

| Flag | Effect |
|---|---|
| (none) | Vault-only mode: both agents. Junker runs categories A–E (+H if enabled). Builder runs all judgment checks. |
| `--dry-run` | Both agents detect but write/commit nothing. Returns would-have-been summary. |
| `--junker-only` | Skip Builder dispatch. |
| `--builder-only` | Skip Junker dispatch. |

`--junker-only` and `--builder-only` are mutually exclusive (error if both passed). Flags may combine: `--junker-only --dry-run`, etc.

## Behavior

### Step 1: Parse flags

Extract flag set from user invocation. Validate:
- If both `--junker-only` and `--builder-only` → emit error "Cannot pass both --junker-only and --builder-only" and exit.

### Step 2: Compute `{TS}`

Load and parse the rules pack — locate `rules.yaml` beside the plugin (`${CLAUDE_PLUGIN_ROOT}/rules.yaml`), falling back to `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml` if absent — and store the parsed object as `cfg` **once here**; all later `cfg.*` references (timezone, `cfg.report.dir`, `cfg.vault.root`, etc.) read from this object.

Read current UTC time, apply `cfg.vault.timezone_offset_hours` (default `0` = UTC), format as `YYYY-MM-DD-HHMM`. Example: `2026-05-18-1430`.

PowerShell to compute (with offset from the rules pack — replace `<OFFSET>` with the integer value):

```powershell
powershell -NoProfile -Command "[DateTime]::UtcNow.AddHours(<OFFSET>).ToString('yyyy-MM-dd-HHmm')"
```

If the rules pack is not yet loaded at this point, default to UTC (offset 0):

```powershell
powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('yyyy-MM-dd-HHmm')"
```

Store as `{TS}`.

### Step 3: Preflight

Run the preflight helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.ps1"
```

The script prints JSON `{ "unmerged_count": <int>, "branches": [<string>...] }` listing unmerged `junker/*` and `builder/*` branches.

If `unmerged_count > 0`:
- Display the list of unmerged branches.
- Ask user via AskUserQuestion: "Continue dispatch despite unmerged audit branches above? / Abort?" If Abort → exit.

### Step 4: Acquire lock

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/lock.ps1" -Action acquire
```

Check exit code:
- `0` (acquired) → proceed.
- `1` (busy) → display lock status (PID + age), ask user via AskUserQuestion: "Wait (re-run /vault-audit later) / Force release and proceed / Abort."
  - Wait → emit "Lock busy. Re-run /vault-audit when the current run completes." and exit.
  - Force release → run `lock.ps1 -Action force-release`, then re-acquire (`lock.ps1 -Action acquire`).
  - Abort → exit.

### Step 5: Dispatch announce

Emit this **before** the Step 6 dispatch:

```
/vault-audit running (sequential foreground)
- Junker → junker/{TS}  (mode: {junker_mode})
- Builder → builder/{TS}  (mode: {builder_mode})

Agents run in isolated worktrees, one at a time (Junker → Builder). Main branch is untouched.
Session is busy for the duration of the run (~10–20 min) — this is foreground, not background.
```

If `--junker-only` or `--builder-only`, list only the dispatched agent.

### Step 6: Sequential foreground dispatch

**Sequential foreground is required** — Junker first, then Builder, each run in the foreground one at a time. NOT parallel, NOT `run_in_background`. Rationale: parallel background dispatch has caused worktree isolation failures and main-branch drift. Foreground-sequential keeps the orchestrator holding the session so a PWD-guard can catch any agent that strays onto the main branch. Parallel/background dispatch requires an explicit separate decision and an edit to this step.

Decide which agents to dispatch based on flags:
- Default / `--dry-run`: dispatch both.
- `--junker-only`: dispatch Junker only.
- `--builder-only`: dispatch Builder only.

Derive `junker_mode`:
- `--dry-run` → `dry-run`
- else → `vault-only`

Derive `builder_mode`:
- `--dry-run` → `dry-run`
- else → `vault-only`

Locate the rules pack files:
- `rules_path` = path to `rules.yaml` beside the plugin (one level up from this file, e.g. `${CLAUDE_PLUGIN_ROOT}/rules.yaml`). If not customized, fall back to `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml`.
- `rules_md_path` = path to the judgment-checks markdown file, e.g. `${CLAUDE_PLUGIN_ROOT}/rules.md` (fall back to `${CLAUDE_PLUGIN_ROOT}/rules.example.md`).

Construct prompts:

**Junker prompt:**

```
You are junker. Run the vault audit per your prompt.

Parameters:
- TS: {TS}
- mode: {junker_mode}
- branch_name: junker/{TS}
- rules_path: {rules_path}

Operate at the vault root resolved from the rules pack (cfg.vault.root). Return structured JSON per your spec.

PWD-GUARD (mandatory): you run in an isolated git worktree. Before ANY git write (add/commit/branch), run `git rev-parse --show-toplevel` and confirm it is your worktree path, NOT the main vault root. If you are on the main vault root, ABORT immediately, make no commits, and report `"errors": ["pwd-guard: landed on main, aborted"]`. Never `git checkout main`, never commit to main.
```

**Builder prompt:**

```
You are builder. Run the vault audit per your prompt.

Parameters:
- TS: {TS}
- mode: {builder_mode}
- branch_name: builder/{TS}
- rules_md_path: {rules_md_path}
- rules_path: {rules_path}

Operate at the vault root resolved from the rules pack (cfg.vault.root). Return structured JSON per your spec.

PWD-GUARD (mandatory): you run in an isolated git worktree. Before ANY git write (add/commit/branch), run `git rev-parse --show-toplevel` and confirm it is your worktree path, NOT the main vault root. If you are on the main vault root, ABORT immediately, make no commits, and report `"errors": ["pwd-guard: landed on main, aborted"]`. Never `git checkout main`, never commit to main.
```

Dispatch via the Agent tool **sequentially, in the foreground** — one Agent call per message, await each result before dispatching the next.

**Step 6a — dispatch Junker** (skip if `--builder-only`), await its structured JSON:

```
Agent(
  description: "Junker vault audit",
  subagent_type: "vault-audit:junker",
  isolation: "worktree",
  model: "sonnet",
  prompt: <junker prompt above>
)
```

**Step 6b — after Junker returns, dispatch Builder** (skip if `--junker-only`), await its structured JSON:

```
Agent(
  description: "Builder vault audit",
  subagent_type: "vault-audit:builder",
  isolation: "worktree",
  model: "sonnet",
  prompt: <builder prompt above>
)
```

Foreground dispatch means each Agent call blocks until the agent finishes and returns its JSON inline — there is no background notification to wait for.

### Step 7: Collect results (inline)

Foreground dispatch means each Agent call returns its structured JSON inline the moment that agent finishes — there is no background run, no harness notification, no polling. Collect Junker's JSON when its call returns, then (after dispatching Builder in Step 6b) collect Builder's JSON the same way. Proceed to Step 8 once all dispatched agents have returned.

### Step 8: Parse results

For each returned agent JSON, extract:
- `branch` (may be null if no findings and worktree was auto-cleaned).
- Junker: `autofixed` per-category counts + commit hashes, `requires_decision` list, `skipped_rate_limit` counts, `errors`.
- Builder: `findings` list, `report_path`, `skipped` list, `errors`.

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

- **Junker:** {N_total_autofix} autofixes, {M_requires_decision} requires-decision
- **Builder:** {K_findings} findings ({S_skipped} skipped by rate limit), report: `{builder_report_path}`
- **Mode:** {mode_label}  (vault-only / dry-run / junker-only / builder-only)
- **Branches:**
  - `junker/{TS}` ({junker_commit_count} commits; or "no findings — worktree auto-cleaned")
  - `builder/{TS}` ({builder_commit_count} commits; or "no findings — worktree auto-cleaned")

## Junker findings

### Autofixed

| Category | Count | Commit |
|---|---|---|
| Broken refs | {junker.autofixed.broken_refs.count} | `{junker.autofixed.broken_refs.commit}` |
| Frontmatter | {junker.autofixed.frontmatter.count} | `{junker.autofixed.frontmatter.commit}` |
| Naming | {junker.autofixed.naming.count} | `{junker.autofixed.naming.commit}` |

### Requires decision

(for each item in `junker.requires_decision`:)

1. **{path}** — {issue}
   - Suggested action: {suggested_action}

### Skipped (rate limit)

(for each non-zero entry in `junker.skipped_rate_limit`:)
- {category}: {count} more found, deferred to next run.

### Memory hygiene autofixes (H1/H2/H3)

(Render this section only if `junker.memory_hygiene` is non-null and has any non-empty array or non-zero `skipped_rate_limit` entry.)

**H1: Orphan files added to index** ({len})
(list files + index lines added)

**H2: Wikilinks rewritten** ({len})
(list file, before, after)

**H3: Dead index entries removed** ({len})
(list lines removed)

**Skipped (rate limit):**
(per subcategory h1/h2/h3 counts > 0)

## Builder findings

(for each finding in `builder.findings`, grouped by severity critical → warning → suggestion:)

### {severity}

| ID | Rule | Evidence | Suggested action |
|---|---|---|---|
| {id} | {rule} | {evidence} | {suggested_action} |

### Skipped (rate limit)

(for each item in `builder.skipped`:)
- `{id}` — {reason}

## Errors / warnings

(Combined from junker.errors + builder.errors. Omit this section if both are empty.)

## Next steps

1. Review `git log junker/{TS}` and `git diff main...junker/{TS}`. Merge the Junker branch if OK.
2. Review Builder report at `{builder_report_path}` and decide on findings.
3. Resolve requires-decision items listed above.
4. After approving merges, run Step 11 cleanup (delete branches + worktrees).
```

Note on git-mv: if the summary file (or any audit file) is later relocated with `git mv` after editing, edits to the moved-from path stay unstaged (status `RM`). Always `git add` the NEW path after a `git mv`-then-edit sequence.

### Step 10: Release lock + final user message

Release the lock:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/lock.ps1" -Action release
```

Emit the final user message (adapt counts for zero-findings cases):

```
Vault audit complete.

Junker: {N} autofixes on `junker/{TS}` + {M} requires-decision.
Builder: {K} findings on `builder/{TS}` ({S} skipped). Report: `{builder_report_path}`.

Run summary: `<cfg.report.dir>/vault-audit-summary-{TS}.md`
Review: `git log junker/{TS}` / `git diff main...junker/{TS}`
```

If any agent had errors, list them explicitly in the message. If an agent had zero findings (e.g. "Junker: clean — 0 autofixes, 0 requires-decision"), say so.

### Step 11: Post-merge cleanup

The orchestrator's job does not end at the summary (Step 9) and lock release (Step 10). After the user reviews and **approves the merge** of an agent branch into main, clean up the branch and its worktree to prevent stale isolated worktrees from accumulating.

This step is **interactive and gated on the user's merge approval** — never auto-merge, never auto-delete a branch with unmerged findings.

1. **After an approved merge** of `junker/{TS}` or `builder/{TS}` into main:
   - Delete the branch: `git branch -d <role>/{TS}` (use `-d`, not `-D` — `-d` refuses to delete unmerged branches, a safety net).
   - Remove the agent's worktree: find it via `git worktree list`, then `git worktree remove <worktree-path>`. If the worktree was already auto-cleaned (no findings), skip.
   - Run `git worktree prune` to clear any stale administrative entries.

2. **Stale-branch sweep (preflight-driven).** Step 3 preflight already reports unmerged `junker/*` and `builder/*` branches (`unmerged_count` + `branches`). When that list is non-empty at the START of a run, for each branch older than ~7 days: check whether its findings are already disposed (e.g. already merged or otherwise resolved); if so, propose `git branch -D` + `git worktree remove` to the user via AskUserQuestion. Never delete unmerged work whose findings are not yet resolved.

Surface every deletion (and every skip/failure) in the run summary — fail-soft is not silent: a skipped or failed cleanup must appear as an explicit line, never silently omitted.

## Inputs

- Current branch must be `main` (else error and exit).
- `${CLAUDE_PLUGIN_ROOT}/scripts/lock.ps1` + `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.ps1` must be available.
- Plugin agents `vault-audit:junker` and `vault-audit:builder` must be registered (the `<plugin>:<agent>` form is the Claude Code plugin-namespacing convention; check `/agents` only if a dispatch ever fails to resolve).
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
