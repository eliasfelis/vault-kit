# vault-audit

Audits a Claude-Code Markdown vault against its own declared rules. Two agents, isolated worktrees, your own branch untouched.

- **Linter** — deterministic fixer (broken refs, frontmatter, naming, duplicates, staleness). Autofixes on a throwaway branch; surfaces ambiguous items for decision.
- **Judge** — judgment reviewer (anti-patterns, declaration-vs-reality drift). Returns a standalone report, never edits files.
- **Leak gate** — `/vault-audit:leak-scan`: on-demand pre-publish scan for secrets and instance literals. Read-only.

---

## Quickstart

Run the auditor against the bundled demo vault and watch it catch the planted issues. The demo is a self-contained vault with its own `rules.yaml` at its root — copy it somewhere scratch, make it a repo, and audit it from inside:

```bash
cp -r "${CLAUDE_PLUGIN_ROOT}/examples/demo-vault" /tmp/demo-vault
cd /tmp/demo-vault
git init -b main && git add -A && git commit -m "demo vault"
```

Then, from that directory:

```
/vault-audit:vault-audit --dry-run
```

The run announces which rules pack it loaded. It should name `/tmp/demo-vault/rules.yaml (user)` — the demo's own pack, found because it sits in the vault you are standing in. The git repo is not optional: both agents work in isolated git worktrees, and the run stops early with a clear error if the vault is not a repository.

Expected findings — category by category, with what must NOT be flagged — are in [`examples/EXPECTED-FINDINGS.md`](examples/EXPECTED-FINDINGS.md).

---

## Rules pack

Copy a starting pack into **your vault root** and edit it there:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml" ./rules.yaml   # opinionated, proven
cp "${CLAUDE_PLUGIN_ROOT}/rules.starter.md"   ./rules.md     # the judgment checks
```

(`rules.example.yaml` / `rules.example.md` are the bare-schema versions if you would rather start from nothing.) Each block is optional — omit it to skip that check entirely.

**Where the pack is looked up**, in order — first hit wins:

1. `rules.yaml` / `rules.md` in the directory you run the command from — your vault.
2. `rules.starter.yaml` / `rules.starter.md` shipped with the plugin.
3. `rules.example.yaml` / `rules.example.md` shipped with the plugin.

Your vault comes first, and the plugin directory is deliberately not a place to keep your pack: a plugin reinstall replaces that tree wholesale, taking your edits with it. **Every run prints one line naming the file it actually loaded and which tier it came from** — read it. An audit against the shipped defaults looks exactly like an audit against your conventions, right up to the findings.

**Principles** — the methodology behind the starter rules: [`PRINCIPLES.md`](PRINCIPLES.md).

**Behavior layer** — optional in-session coaching reflexes: [`behavior-layer.example.md`](behavior-layer.example.md). Copy it into your project as `behavior-layer.md` and load it **from your instructions file** — one line, `@behavior-layer.md`, in your `CLAUDE.md` (or paste the layer inline if your tool has no import syntax). It is then loaded verbatim, every session.

**Two shell habits the layer assumes.** Neither is a reflex — there is no moment at which either "fires", and you learn each once — so they live here rather than in the always-on file. **Avoid `cd <path> && <cmd>` in tool calls:** the compound is evaluated as a whole, so a narrow allow-rule scoped to `<cmd>` never matches it, and it re-prompts on every new path you `cd` into; the shell tool persists its working directory between calls, so use absolute paths instead. **Commit with an explicit pathspec whenever the working tree is shared:** if anything else can stage files — a sync daemon, an editor plugin, a parallel session — a bare commit sweeps the whole index and ships someone else's half-finished work under your message, so name the paths you mean and re-read the status right before committing rather than trusting a picture formed several steps ago. The recurring half of that second habit is carried by the `session-close` reflex, which ends every session on an explicit-pathspec commit pass.

> **Do not deliver it through a SessionStart hook that prints the file.** It looks like it works, but hook stdout is capped — we measured truncation at roughly 2 KB — and the cut is silent and mid-file. A behavior layer runs to several KB by nature — the example here is well past the cap — so the hook route quietly drops most of your reflexes with no warning. [`hooks.example.json`](hooks.example.json) carries a different hook pattern — an allowlist guard that **blocks** a tool call — which is what hooks are actually good for.

| Block | What it controls |
|---|---|
| `vault.root` | Path to the vault to audit (default: `.` = cwd). |
| `vault.timezone_offset_hours` | Offset for report timestamps (default: `0` = UTC). |
| `governance_paths` | Paths that are **never modified** and **skipped by all checks** (your constitution, rules, docs). |
| `broken_refs` | Validates relative Markdown links and an optional frontmatter field that holds a file path. |
| `frontmatter` | Checks for required fields, tag count bounds, allowed tag namespaces, optional closed enums per namespace. Supports `exempt_paths`. |
| `naming` | Validates filenames against a regex pattern. Supports `exempt_paths` and `exempt_basenames` (living working files like `STATE.md`, `README.md` — see `PRINCIPLES.md`). Basenames match exactly, so `ROADMAP.md` and `roadmap.md` are different entries. |
| `duplicates` | Flags files with identical basenames across the tree. Supports `exempt_basenames`. |
| `staleness` | Per-glob rules: checks that a frontmatter date field is within `max_age_days`. |
| `memory` | Optional memory-folder hygiene (off by default). Set `enabled: true` and `path` to your Claude-Code memory folder. |
| `leak_scan` | Defaults for `/vault-audit:leak-scan`: private `extra_patterns` file, `tracked_only`, `exclude`. |
| `report.dir` | Directory in your vault where the run writes the Judge's report and the run summary (default: `.vault-audit`). |

The judgment checks (`anti_patterns` and `drift_checks`) live in the `.md` half of the pack (`rules.starter.md` / `rules.example.md`) and resolve by the same order — put your own `rules.md` in your vault root.

---

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Both agents detect issues but write nothing and make no commits. Returns would-have-been summary. |
| `--linter-only` | Skip Judge dispatch. |
| `--judge-only` | Skip Linter dispatch. |

Flags may combine: `--linter-only --dry-run`.

---

## Output

- **Linter** commits autofixes to a `linter/<TS>` branch. Ambiguous items surface in the run summary as a requires-decision list. Review with `git diff <your-branch>...linter/<TS>` before merging.
- **Judge** returns its findings report as text; the command writes it to `<vault>/.vault-audit/report-<TS>.md` (directory configurable via `report.dir`) and prints that path. The report lands in YOUR vault, not in an agent's worktree — a worktree is deleted at cleanup, and a report inside one goes with it.
- **Run summary** — `<vault>/.vault-audit/vault-audit-summary-<TS>.md`, written in every mode.

Whatever branch your vault has checked out is the base branch: `main`, `master`, `trunk` or a working branch, it makes no difference and neither agent touches it.

**Setup, once:** add `.vault-audit/` to your vault's `.gitignore` if you would rather not see audit output in `git status`. The plugin does not edit your `.gitignore` — it never writes outside its own outputs — so nothing is ignored until you add it.

### Bridge to vault-feed

In `vault-only` mode the run also writes `<report.dir>/findings-<TS>.json` — a
machine-readable list of the judge's findings and the linter's requires-decision
items. `vault-feed`'s `/vault-feed:import-audit` reads this file to pull audit
findings into its triage backlog. Nothing else consumes it; if you don't use
vault-feed, ignore it.

---

## Leak gate — /vault-audit:leak-scan

Run the publish gate on demand against any path (default: your vault root from the rules pack):

```
/vault-audit:leak-scan --path . --tracked-only
```

Two pattern layers: the shipped generic set ([`scripts/leak-patterns.txt`](scripts/leak-patterns.txt) — credential shapes, user-profile paths) plus an optional **private** file with your instance literals (names, brands, internal codes, hostnames), passed via `--extra-patterns` or the `leak_scan:` block in the rules pack. Keep the private file outside any published repo — that is the whole point of the two-layer design.

Exit contract (fail-loud): `0` clean (with both counts — `OK: no leaks (N file(s) scanned, 0 unscannable)`) · `1` leak(s) or unreadable file(s) · `2` the gate could not certify (missing/invalid patterns, empty pattern set, invalid or over-broad exclude, zero files, or a file it could not line-scan — never reported as clean) · `64` usage. `--tracked-only` checks every `git ls-files` entry regardless of extension (fail-closed coverage); the default walk enumerates by a wide extension list. Filenames are matched too, not just content.

**A file the gate cannot read is not a file that passed.** Binary and UTF-16 content (PowerShell's `>` writes UTF-16) cannot be line-scanned, so the run lists those files and exits `2` rather than certifying around them — an unscanned file is exactly where a leak would survive a green run. Convert it to UTF-8, or `--exclude` it to put it out of scope deliberately.

Know the limits before trusting a green run: patterns are case-sensitive (`(?i)` your literals), regex metacharacters in a "literal" must be escaped, and every new private pattern file deserves a positive control (plant a literal, expect exit `1`). Full list: the **Limits & discipline** section in [`commands/leak-scan.md`](commands/leak-scan.md).

---

## Platforms

Runs on **Windows (via Git Bash), macOS, and Linux**. The helper scripts are `bash` + `perl` (both bundled with Git for Windows; preinstalled on macOS/Linux). No PowerShell required.
