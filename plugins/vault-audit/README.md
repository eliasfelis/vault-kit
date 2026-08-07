# vault-audit

Audits a Claude-Code Markdown vault against its own declared rules. Two agents, isolated worktrees, main branch untouched.

- **Linter** — deterministic fixer (broken refs, frontmatter, naming, duplicates, staleness). Autofixes on a throwaway branch; surfaces ambiguous items for decision.
- **Judge** — judgment reviewer (anti-patterns, declaration-vs-reality drift). Writes a standalone report, never edits files.
- **Leak gate** — `/vault-audit:leak-scan`: on-demand pre-publish scan for secrets and instance literals. Read-only.

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

**Behavior layer** — optional in-session coaching reflexes: [`behavior-layer.example.md`](behavior-layer.example.md). Copy it into your project as `behavior-layer.md` and load it **from your instructions file** — one line, `@behavior-layer.md`, in your `CLAUDE.md` (or paste the layer inline if your tool has no import syntax). It is then loaded verbatim, every session.

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

## Leak gate — /vault-audit:leak-scan

Run the publish gate on demand against any path (default: your vault root from the rules pack):

```
/vault-audit:leak-scan --path . --tracked-only
```

Two pattern layers: the shipped generic set ([`scripts/leak-patterns.txt`](scripts/leak-patterns.txt) — credential shapes, user-profile paths) plus an optional **private** file with your instance literals (names, brands, internal codes, hostnames), passed via `--extra-patterns` or the `leak_scan:` block in the rules pack. Keep the private file outside any published repo — that is the whole point of the two-layer design.

Exit contract (fail-loud): `0` clean (with a file count — `OK: no leaks (N file(s) scanned)`) · `1` leak(s) or unreadable file(s) · `2` gate misconfigured or nothing to scan (missing/invalid patterns, empty pattern set, over-broad exclude, zero files — never reported as clean) · `64` usage. `--tracked-only` checks every `git ls-files` entry regardless of extension (fail-closed coverage); the default walk enumerates by a wide extension list. Filenames are matched too, not just content; binary/UTF-16 files are skipped visibly.

Know the limits before trusting a green run: patterns are case-sensitive (`(?i)` your literals), regex metacharacters in a "literal" must be escaped, and every new private pattern file deserves a positive control (plant a literal, expect exit `1`). Full list: the **Limits & discipline** section in [`commands/leak-scan.md`](commands/leak-scan.md).

---

## Platforms

Runs on **Windows (via Git Bash), macOS, and Linux**. The helper scripts are `bash` + `perl` (both bundled with Git for Windows; preinstalled on macOS/Linux). No PowerShell required.
