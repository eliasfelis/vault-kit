# Expected findings — running vault-audit on `demo-vault/`

Acceptance ground-truth for the Quickstart in the plugin README. Lives OUTSIDE `demo-vault/`
so it is not itself audited.

**What the run resolves.** `demo-vault/rules.yaml` sits at the demo's root, so once you run the
command from a copy of that folder it is found as the **user** pack — the run should announce
`Rules pack: <your copy>/rules.yaml (user)`. If it announces `rules.starter.yaml (starter
fallback)` instead, you are not standing where you think you are, and every count below is off:
the starter pattern expects ` - YYYY-MM-DD.md` (with a hyphen separator) where the demo pack
expects ` YYYY-MM-DD.md`, so most of the demo would flag as naming violations. There is no
`rules.md` in the demo, so the judgment pack legitimately resolves to `rules.starter.md`
(starter fallback) — that is expected, and the checks below are the starter ones.

## Linter (deterministic)

Each row is the complete expectation for that category — one finding each, and nothing else
in that category.

| Category | Finding | Cardinality rule | Disposition |
|---|---|---|---|
| `broken_refs` | `notes/broken-link 2026-06-01.md:11` — `[missing target](./nope.md)`, no such file | one per broken link | `requires_decision` — no candidate in the same directory is a ≥90% match for `nope.md`, so there is no unambiguous rename to apply |
| `frontmatter` | `notes/no-frontmatter 2026-06-01.md` — no frontmatter block, so both required fields (`tags`, `date`) are missing | **one per FILE**, listing every missing field — not one per field | mixed: `tags` is always `requires_decision` (the tool will not invent your taxonomy); `date` is autofixable when `git log` says the file was created within 7 days, which in a freshly `git init`-ed demo copy it was |
| `naming` | `notes/BadName.md` — basename does not match `^.+ \d{4}-\d{2}-\d{2}\.md$` | one per violating file | `requires_decision` — adding a date is information the tool does not have |
| `duplicates` | `report 2026-06-01.md` in both `projects/alpha/` and `projects/beta/` | **one per BASENAME**, listing every path that shares it — not one per file | `requires_decision` — which one to rename or merge is a human call |
| `staleness` | `inbox/stale 2020-01-01.md` — frontmatter `date: 2020-01-01`, past the 7-day `inbox/*.md` rule | one per stale file | `requires_decision` — staleness is a signal, never silently "fixed" |

In `--dry-run` (what the Quickstart runs) every one of these is reported and nothing is
written: autofix counts are 0 and all commits are `null`, including the `date` field above.

## Judge (judgment, via the starter judgment pack)

| Check | Outcome |
|---|---|
| `declared-folders-vs-actual` | **Finding (warning).** `CLAUDE.md` routing declares `widgets/`, which does not exist. The other three declared folders (`notes/`, `projects/`, `inbox/`) exist, and no undeclared top-level folder is present. |
| `no-raw-chat-imports` | No finding — the demo has no research-like folder, so the check no-ops on an absent target. |
| `user-manual-commands-exist` | No finding — neither a commands folder nor a user manual exists; explicit no-op. |
| `update-protocol-gap` | No finding — read against the demo's OWN history (`git -C <vault root> log`), which holds only the Quickstart's initial commit, whose subject matches no `add(command\|skill\|hook\|rule)` pattern. |
| `session-summary-present` | No finding — no logs/summaries folder; no-op on an absent target. |
| `one-source-of-truth-contested` | No finding — nothing is tagged `status/contested`. |
| memory drift (scope M) | Not run — `memory.enabled: false`. |

The Judge writes no file: it returns the report, and the orchestrator writes it to
`<vault>/.vault-audit/report-<TS>.md`. In `--dry-run` nothing is written at all.

## Must NOT be flagged

- `CLAUDE.md` — governance path, skipped by every Linter check (it is still READ by the Judge as evidence for the folder-routing drift check; that is the point of a drift check).
- `rules.yaml` — not a markdown file.
- `projects/alpha/STATE.md`, `projects/beta/STATE.md` — exempt basename for both naming and duplicates, and their frontmatter is valid (3 tags, allowed namespaces, `project/` values inside the declared enum).
- `notes/good-note 2026-06-01.md` — fully compliant.
- `inbox/stale 2020-01-01.md` under naming — the filename is conformant; only its content date is stale.
