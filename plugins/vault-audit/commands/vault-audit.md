---
description: "Audit your vault against its rules pack: linter fixes deterministic issues, judge reports judgment-call drift."
---

# /vault-audit — audit a vault against its rules pack

Dispatches two subagents sequentially in the foreground: the **Linter** (deterministic fixer) runs first, then the **Judge** (judgment reviewer). Both run in isolated git worktrees. Branches surface findings; the branch your vault has checked out is untouched.

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

### Step 2: Resolve and load the rules pack, then compute `{TS}`

**Resolution order — YOUR vault first.** Take the first file that exists:

1. `<cwd>/rules.yaml` — your own pack, in the vault you invoked the command from.
2. `${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml` — the opinionated starter conventions.
3. `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml` — the bare schema reference.

The judgment pack resolves the same way: `<cwd>/rules.md` → `${CLAUDE_PLUGIN_ROOT}/rules.starter.md` → `${CLAUDE_PLUGIN_ROOT}/rules.example.md`.

Your vault comes first because the plugin tree is replaced wholesale on reinstall, so it is not a place to keep user data — and because a tool whose premise is "audit against YOUR declared rules" auditing against the shipped defaults instead is the worst failure available to it: the run looks right and answers a question nobody asked.

Resolve both to **absolute** paths. The agents run in worktrees whose working directory is not your vault, so a relative path handed to them resolves somewhere else:

```bash
for c in "$PWD/rules.yaml" "$CLAUDE_PLUGIN_ROOT/rules.starter.yaml" "$CLAUDE_PLUGIN_ROOT/rules.example.yaml"; do [ -f "$c" ] && { ( cd "$(dirname "$c")" && printf '%s/%s\n' "$(pwd)" "$(basename "$c")" ); break; }; done
for c in "$PWD/rules.md"   "$CLAUDE_PLUGIN_ROOT/rules.starter.md"   "$CLAUDE_PLUGIN_ROOT/rules.example.md";   do [ -f "$c" ] && { ( cd "$(dirname "$c")" && printf '%s/%s\n' "$(pwd)" "$(basename "$c")" ); break; }; done
```

Store the two results as `{rules_path}` and `{rules_md_path}`. Which tier answered is readable from the basename: `rules.yaml` / `rules.md` = user, `rules.starter.*` = starter fallback, `rules.example.*` = example fallback.

**Then say so, out loud, in every run** — one line, before any other output:

```
Rules pack: {rules_path} (user | starter fallback | example fallback)  ·  judgment pack: {rules_md_path} (user | starter fallback | example fallback)
```

Silence here was the original defect: a fallback that announces nothing is indistinguishable from a hit. If neither pack resolves, error and exit — never audit against no rules.

Parse the YAML and store the parsed object as `cfg` **once here**; all later `cfg.*` references (timezone, `cfg.report.dir`, `cfg.vault.root`, etc.) read from this object.

Read current UTC time, apply `cfg.vault.timezone_offset_hours` (default `0` = UTC), format as `YYYY-MM-DD-HHMM`. Example: `2026-05-18-1430`.

Compute the timestamp (with offset from the rules pack — replace `<OFFSET>` with the integer value). `perl` is bundled with Git on every platform:

```bash
perl -e 'use POSIX; print strftime("%Y-%m-%d-%H%M", gmtime(time + ($ARGV[0]*3600)))' -- <OFFSET>
```

The `--` is load-bearing: without it a negative offset (`-5`, every timezone west of UTC) is eaten as a perl switch and the command dies before its first output.

If the pack declares no offset, that is offset `0` and this is the same thing more cheaply:

```bash
date -u +%Y-%m-%d-%H%M
```

Store as `{TS}`.

### Step 2a: Resolve the vault root to an absolute path

`cfg.vault.root` (default `"."`) is relative to your vault checkout. Resolve it to an absolute path once, here, and call it `{VAULT_ABS}`:

```bash
( cd "<cfg.vault.root>" && pwd )
```

Echo it. Every later step that names a path — preflight, the lock, the report, the summary — uses `{VAULT_ABS}`, because the agents' worktrees have a different working directory and `"."` means something different in each of them.

### Step 3: Preflight

Run the preflight helper against the resolved vault root — not against your own working directory, which is not necessarily the same tree:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh" --repo-path "{VAULT_ABS}"
```

The script prints JSON `{ "is_repo": <bool>, "unmerged_count": <int>, "branches": [<string>...] }`.

Read `is_repo` FIRST:
- `false` → the vault is not a git repository. Emit `ERROR: {VAULT_ABS} is not a git repository — /vault-audit needs one, because both agents run in isolated git worktrees. Run \`git init\` there (and make at least one commit) or point cfg.vault.root at your vault.` and exit. This check sits **before** the lock deliberately: a run that discovers this at worktree-creation time dies holding the lock, and the next run then reports a phantom busy lock for an hour.
- `true` → continue.

If `unmerged_count > 0`:
- Display the list of unmerged branches.
- Ask user via AskUserQuestion: "Continue dispatch despite unmerged audit branches above? / Abort?" If Abort → exit.

### Step 3a: Base branch and clean tree

```bash
git -C "{VAULT_ABS}" branch --show-current
git -C "{VAULT_ABS}" status --porcelain
```

- `{BASE_BRANCH}` := the branch the vault currently has checked out. This is the fork point the audit branches are reviewed against, and the merge target in Steps 9–11. There is no required branch name: `main`, `master`, `trunk` and a personal working branch are all equally valid, and hardcoding one would simply lock those vaults out.
- Empty output from `branch --show-current` = detached HEAD. Emit `ERROR: {VAULT_ABS} is on a detached HEAD — check out a branch first.` and exit.
- Non-empty `status --porcelain` = uncommitted changes. Ask via AskUserQuestion: "Uncommitted changes in {VAULT_ABS}. Continue anyway (agent worktrees are isolated; your working tree is not touched) / Stash and continue / Abort." Abort → exit.

Both gates are numbered steps because an unnumbered rule in a prose section is a rule that never runs: a literal walk of the steps skips it.

### Step 4: Acquire lock

Derive a **per-vault** lock directory, so that auditing one vault never blocks an unrelated audit of another:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh" acquire --lock-dir "${TMPDIR:-/tmp}/vault-audit-$(printf '%s' "{VAULT_ABS}" | cksum | cut -d' ' -f1)" --vault-path "{VAULT_ABS}"
```

Use that same `--lock-dir` and `--vault-path` pair in every later `lock.sh` call in this run (Step 4 force-release, Step 10 release) — a release against the default directory leaves the real lock in place until it ages out.

Check exit code:
- `0` (acquired) → proceed.
- `1` (busy) → display the script's status line, ask user via AskUserQuestion: "Wait (re-run /vault-audit later) / Force release and proceed / Abort."
  - Wait → emit "Lock busy. Re-run /vault-audit when the current run completes." and exit.
  - Force release → run `lock.sh force-release` (same `--lock-dir`), then re-acquire.
  - Abort → exit.

**What the lock actually guarantees.** It is a timer, not a liveness check: the PID it records is the lock script's own shell, already exited, so the busy window is `--max-age-min` (default 60) from acquisition. A run that lasts longer than that can be entered by a second run — raise `--max-age-min` for a long audit, and use Force release when you know a previous run died. Better an honest timer than a liveness check that always reports false.

### Step 5: Dispatch announce

Compute `{REPORT_PATH}` = `{VAULT_ABS}/<cfg.report.dir>/report-{TS}.md` — the user-side path the judgment report will land at in Step 8a (every input exists by Step 3a). Then emit this **before** the Step 6 dispatch:

```
/vault-audit running (sequential foreground)
- Linter → linter/{TS}  (mode: {linter_mode})
- Judge → report as text → {REPORT_PATH}  (mode: {judge_mode})

Agents run in isolated worktrees, one at a time (Linter → Judge). {BASE_BRANCH} is untouched.
Session is busy for the duration of the run (~10–20 min) — this is foreground, not background.
```

If `--linter-only` or `--judge-only`, list only the dispatched agent.

### Step 6: Sequential foreground dispatch

**Sequential foreground is required** — Linter first, then Judge, each run in the foreground one at a time. NOT parallel, NOT `run_in_background`. The risk this guards against: parallel background dispatch is where worktree isolation fails quietly and an agent's writes land on your base branch instead of its own. Foreground-sequential keeps the orchestrator holding the session, so a PWD-guard can catch an agent that strays out of its worktree while there is still someone watching. Parallel/background dispatch requires an explicit separate decision and an edit to this step.

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

The rules pack files were resolved once in Step 2 — do not re-resolve them here. Pass `{rules_path}` and `{rules_md_path}` as the **absolute** paths Step 2 produced. An agent cannot find them on its own: it does not know where the plugin is installed, and its worktree cwd is not your vault, so any relative or "beside the plugin" instruction resolves to nothing in its context.

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

FIRST ACTION, before reading the vault or writing anything: `git switch -C {branch_name}` — the worktree opens on a harness-generated branch, and every downstream step (the review diff, the merge, Step 11 cleanup) addresses your work as {branch_name}. Then confirm `git branch --show-current` prints exactly {branch_name}; if it does not, make no writes and return with an errors entry.

PWD-GUARD (mandatory): you run in an isolated git worktree. Before ANY git write (add/commit/branch), run `git rev-parse --show-toplevel` and confirm it is your worktree path, NOT the vault's primary checkout. If you are on the primary checkout, ABORT immediately, make no commits, and report `"errors": ["pwd-guard: landed on the primary checkout, aborted"]`. Never switch to or commit on {BASE_BRANCH} — the vault's own branch.
```

**Judge prompt:**

```
You are judge. Run the vault audit per your prompt.

Parameters:
- TS: {TS}
- mode: {judge_mode}
- rules_md_path: {rules_md_path}
- rules_path: {rules_path}

Operate at the vault root resolved from the rules pack (cfg.vault.root). Return structured JSON per your spec.

Write NO report file and commit nothing. Return the complete report markdown inside your JSON, in the `report_markdown` field. The orchestrator writes it into the user's own vault after you return — a file written inside your worktree would be destroyed with the worktree and never reaches the user.

NO-WRITE GUARD (mandatory): you make no writes at all — no file writes, no git add, no commit, no branch operations, in the worktree or anywhere else. Your worktree is read-only isolation. If any step appears to require a write, refuse it and report `"errors": ["write required, refused by contract"]`.
```

Dispatch via the Agent tool **sequentially, in the foreground** — one Agent call per message, await each result before dispatching the next.

**Step 6a — dispatch Linter** (skip if `--judge-only`), await its structured JSON:

```
Agent(
  description: "Linter vault audit",
  subagent_type: "vault-audit:linter",
  isolation: "worktree",
  prompt: <linter prompt above>
)
```

**Step 6b — after Linter returns, dispatch Judge** (skip if `--linter-only`), await its structured JSON:

```
Agent(
  description: "Judge vault audit",
  subagent_type: "vault-audit:judge",
  isolation: "worktree",
  prompt: <judge prompt above>
)
```

Foreground dispatch means each Agent call blocks until the agent finishes and returns its JSON inline — there is no background notification to wait for.

**Neither dispatch passes a `model`.** Each agent declares its own in its frontmatter, and a
per-invocation argument silently overrides that declaration — so repeating the model here
would mean editing an agent's frontmatter had no effect and gave no warning. Change the model
in `agents/linter.md` or `agents/judge.md`; the call site deliberately stays silent about it.

### Step 7: Collect results (inline)

Foreground dispatch means each Agent call returns its structured JSON inline the moment that agent finishes — there is no background run, no harness notification, no polling. Collect Linter's JSON when its call returns, then (after dispatching Judge in Step 6b) collect Judge's JSON the same way. Proceed to Step 8 once all dispatched agents have returned.

### Step 8: Parse results

For each returned agent JSON, extract:
- `branch` (may be null if no findings and worktree was auto-cleaned).
- Linter: `autofixed` per-category counts + commit hashes, `requires_decision` list, `skipped_rate_limit` counts, `errors`.
- Judge: `findings` list, `report_markdown` (the report body — the Judge returns text, it writes no file), `skipped` list, `errors`.

Edge cases:
- If JSON parse fails → log `"errors": ["agent returned non-JSON output"]` for that agent, continue.
- If agent returned `errors: ["worktree creation failed"]` or similar → surface in the run summary; do not abort the other agent's processing.

### Step 8a: Write the Judge report into the user's vault

The Judge returns its report as text; **you** write the file — before the summary, so the summary can state truthfully whether the report exists. Skip this step in `--dry-run` (a preview writes nothing) and when the Judge did not run.

- Write `judge.report_markdown` verbatim to `{REPORT_PATH}` = `{VAULT_ABS}/<cfg.report.dir>/report-{TS}.md`, creating the directory if needed.
- The path must be inside the USER's vault, and absolute. The Judge's worktree is deleted in Step 11, so a report left there is a report that never existed as far as the user is concerned — and a relative path printed at the end resolves, in their checkout, to a file that is not there.
- If `judge.report_markdown` is missing or empty → do NOT invent a path. Carry `FAILED: judge report missing — findings are in this summary only` into the Step 9 TLDR line and the Step 10 final message, and let the summary's findings table stand as the record.

### Step 9: Write run summary

Read `cfg.report.dir` from the rules pack (default `.vault-audit`). Write the summary to:

```
{VAULT_ABS}/<cfg.report.dir>/vault-audit-summary-{TS}.md
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
- **Judge:** {K_findings} findings ({S_skipped} skipped by rate limit), report: `{REPORT_PATH}` (or `FAILED: judge report missing` — see Step 8a)
- **Mode:** {mode_label}  (vault-only / dry-run / linter-only / judge-only)
- **Base branch:** `{BASE_BRANCH}` (untouched by this run)
- **Branches:**
  - `linter/{TS}` ({linter_commit_count} commits; or "no findings — worktree auto-cleaned")

(The Judge creates no branch: it returns its report as text and never writes inside its worktree.)

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

1. Review `git log linter/{TS}` and `git diff {BASE_BRANCH}...linter/{TS}`. Merge the Linter branch if OK.
2. Review the Judge report at `{REPORT_PATH}` and decide on findings.
3. Resolve requires-decision items listed above.
4. After approving merges, run Step 11 cleanup (delete branches + worktrees).
```

Note on git-mv: if the summary file (or any audit file) is later relocated with `git mv` after editing, edits to the moved-from path stay unstaged (status `RM`). Always `git add` the NEW path after a `git mv`-then-edit sequence.

### Step 9b: Emit the machine-readable findings file (bridge contract)

Additionally write `{VAULT_ABS}/<cfg.report.dir>/findings-{TS}.json` for downstream consumers
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
- `mode`: the agent run mode at time of write — always `"vault-only"` here because the dry-run guard prevents writes in any other mode (invariant 1).
- `judge_findings`: the Step 8 `judge.findings` array verbatim; each item has keys `{id, severity, rule, evidence, suggested_action, related_files}`. Use `[]` if Judge did not run or returned no findings.
- `linter_requires_decision`: the Step 8 `linter.requires_decision` array verbatim; each item has keys `{category, path, issue, suggested_action}`. Use `[]` if Linter did not run or returned no requires-decision items.

Notes: Stage only this file with an explicit pathspec if anything is committed; it is
normally left untracked in `<cfg.report.dir>/`. Add that directory to your vault's
`.gitignore` if you would rather not see audit output in `git status` — the plugin does
not edit your `.gitignore`, so nothing is ignored unless you say so.

### Step 10: Release lock + final user message

Release the lock — with the same `--lock-dir` and `--vault-path` used to acquire it in Step 4:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh" release --lock-dir "${TMPDIR:-/tmp}/vault-audit-$(printf '%s' "{VAULT_ABS}" | cksum | cut -d' ' -f1)" --vault-path "{VAULT_ABS}"
```

Emit the final user message (adapt counts for zero-findings cases):

```
Vault audit complete.

Rules pack: {rules_path} ({tier})
Linter: {N} autofixes on `linter/{TS}` + {M} requires-decision.
Judge: {K} findings ({S} skipped). Report: `{REPORT_PATH}`.

Run summary: `{VAULT_ABS}/<cfg.report.dir>/vault-audit-summary-{TS}.md`
Review: `git log linter/{TS}` / `git diff {BASE_BRANCH}...linter/{TS}`
```

If any agent had errors, list them explicitly in the message. If an agent had zero findings (e.g. "Linter: clean — 0 autofixes, 0 requires-decision"), say so.

### Step 11: Post-merge cleanup

The orchestrator's job does not end at the summary (Step 9) and lock release (Step 10). After the user reviews and **approves the merge** of an agent branch into `{BASE_BRANCH}`, clean up the branch and its worktree to prevent stale isolated worktrees from accumulating.

This step is **interactive and gated on the user's merge approval** — never auto-merge, never auto-delete a branch with unmerged findings.

1. **After an approved merge** of `linter/{TS}` into `{BASE_BRANCH}`:
   - Delete the branch: `git branch -d <role>/{TS}` (use `-d`, not `-D` — `-d` refuses to delete unmerged branches, a safety net).
   - Remove the agent's worktree: find it via `git worktree list`, then `git worktree remove <worktree-path>`. If the worktree was already auto-cleaned (no findings), skip.
   - If `git branch` still shows the harness-generated branch that worktree originally opened on (an auto-generated worktree-agent name), delete it too (`git branch -D <name>`) — it carries no commits of its own.
   - Run `git worktree prune` to clear any stale administrative entries.

   (The Judge creates no `judge/{TS}` branch — it writes nothing. Its worktree needs only the same worktree removal plus the leftover harness-branch deletion above.)

2. **Stale-branch sweep (preflight-driven).** Step 3 preflight already reports unmerged `linter/*` and `judge/*` branches (`unmerged_count` + `branches`). When that list is non-empty at the START of a run, for each branch older than ~7 days: check whether its findings are already disposed (e.g. already merged or otherwise resolved); if so, propose `git branch -D` + `git worktree remove` to the user via AskUserQuestion. Never delete unmerged work whose findings are not yet resolved.

Surface every deletion (and every skip/failure) in the run summary — fail-soft is not silent: a skipped or failed cleanup must appear as an explicit line, never silently omitted.

## Inputs

- The vault (`cfg.vault.root`) must be a git repository with a branch checked out. Any branch name works — it becomes `{BASE_BRANCH}` (Step 3a).
- `${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh` + `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh` must be available.
- Plugin agents `vault-audit:linter` and `vault-audit:judge` must be registered (the `<plugin>:<agent>` form is the Claude Code plugin-namespacing convention; check `/agents` only if a dispatch ever fails to resolve).
- A rules pack must resolve per Step 2 (your `rules.yaml`, else the shipped starter, else the example).

## Failure handling

| Condition | Where it is handled |
|---|---|
| Neither rules pack resolves | Step 2 — error and exit; never audit against no rules. |
| Vault is not a git repository (`is_repo: false`) | Step 3 — error and exit, **before** the lock is taken. |
| Detached HEAD in the vault | Step 3a — error and exit. |
| Uncommitted changes in the vault | Step 3a — AskUserQuestion (Continue / Stash and continue / Abort). Agent worktrees are isolated, so your working tree is not at risk; the prompt exists so a surprising diff is your choice, not an accident. |
| Lock already held by a recent run | Step 4 — AskUserQuestion (Wait / Force release / Abort). |
| Preflight reports unmerged branches | Step 3 — AskUserQuestion (Continue / Abort). |
| Judge returned no `report_markdown` | Step 8a — `FAILED: judge report missing` in the summary and the final message; findings stay in the summary. Never print a path to a file that was not written. |
| Agent dispatch errors (e.g. worktree creation fails) | Release the lock (Step 10 command, same `--lock-dir`), emit the error, exit. No partial state left behind. |

## Co-author convention

Commits made by a dispatched agent — in practice the Linter, since the Judge commits nothing — use:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```
