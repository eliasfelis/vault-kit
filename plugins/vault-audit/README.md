# vault-audit

Audits a Claude-Code Markdown vault against its own declared rules. Two agents, isolated worktrees, main branch untouched.

- **Linter** — deterministic fixer (broken refs, frontmatter, naming, duplicates, staleness). Autofixes on a throwaway branch; surfaces ambiguous items for decision.
- **Judge** — judgment reviewer (anti-patterns, declaration-vs-reality drift). Writes a standalone report, never edits files.

---

## Quickstart

Point the tool at the bundled demo vault to see it catch the planted issues:

```
/vault-audit:vault-audit --dry-run
```

Before that, edit the rules pack so it targets `examples/demo-vault/`:

```yaml
vault:
  root: "examples/demo-vault"
```

Expected findings are listed in `examples/EXPECTED-FINDINGS.md`.

---

## Rules pack

Start from **`rules.starter.yaml`** (opinionated, proven) — or `rules.example.yaml` for a bare schema — copy your choice to `rules.yaml` and adjust. Each block is optional — omit it to skip that check entirely.

**Principles** — the methodology behind the starter rules: [`PRINCIPLES.md`](PRINCIPLES.md).

**Behavior layer** — optional in-session coaching reflexes: [`behavior-layer.example.md`](behavior-layer.example.md) + [`hooks.example.json`](hooks.example.json) (wire as a SessionStart hook).

| Block | What it controls |
|---|---|
| `vault.root` | Path to the vault to audit (default: `.` = cwd). |
| `vault.timezone_offset_hours` | Offset for report timestamps (default: `0` = UTC). |
| `governance_paths` | Paths that are **never modified** and **skipped by all checks** (your constitution, rules, docs). |
| `broken_refs` | Validates relative Markdown links and an optional frontmatter field that holds a file path. |
| `frontmatter` | Checks for required fields, tag count bounds, allowed tag namespaces, optional closed enums per namespace. Supports `exempt_paths`. |
| `naming` | Validates filenames against a regex pattern. Supports `exempt_paths` and `exempt_basenames` (structural files like `STATE.md`, `README.md`). |
| `duplicates` | Flags files with identical basenames across the tree. Supports `exempt_basenames`. |
| `staleness` | Per-glob rules: checks that a frontmatter date field is within `max_age_days`. |
| `memory` | Optional memory-folder hygiene (off by default). Set `enabled: true` and `path` to your Claude-Code memory folder. |
| `report.dir` | Where the Judge writes its standalone report (default: `.vault-audit`). |

The judgment checks (`anti_patterns` and `drift_checks`) live in `rules.example.md`. Copy it to `rules.md` and replace the examples with your own declared rules.

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

- **Linter** commits autofixes to a `linter/<TS>` branch. Ambiguous items surface in the run summary as a requires-decision list. Review with `git diff main...linter/<TS>` before merging.
- **Judge** writes a standalone findings report under `.vault-audit/` (configurable via `report.dir`). The run summary links to it.

Neither agent touches your main branch.

### Bridge to vault-feed

In `vault-only` mode the run also writes `<report.dir>/findings-<TS>.json` — a
machine-readable list of the judge's findings and the linter's requires-decision
items. `vault-feed`'s `/vault-feed:import-audit` reads this file to pull audit
findings into its triage backlog. Nothing else consumes it; if you don't use
vault-feed, ignore it (it lives in the gitignored `.vault-audit/`).

---

## Platforms

Runs on **Windows (via Git Bash), macOS, and Linux**. The helper scripts are `bash` + `perl` (both bundled with Git for Windows; preinstalled on macOS/Linux). No PowerShell required.
