# vault-kit

A small collection of operational tools for running a Claude-Code Markdown knowledge vault. Two tools so far — `vault-audit` and `vault-feed` — with more to come.

---

## vault-audit

`vault-audit` audits a vault against its **own declared rules** — a rules pack you fill in once. Two agents, each in an isolated git worktree:

- **Linter** — the deterministic fixer. Scans for broken links, frontmatter rot, naming violations, duplicates, and staleness. Autofixes safe issues on a throwaway branch you review before merge; surfaces ambiguous ones for your decision.
- **Judge** — the judgment reviewer. Checks your declared anti-patterns and declaration-vs-reality drift (e.g. folders named in your config that don't exist). Writes a standalone findings report. Never edits files.

Nothing touches your main branch without review.

### How it stays safe

`vault-audit` autofixes only on a throwaway git branch you review before merge. The judgment agent never edits files — it only writes a report.

### Install

```
/plugin marketplace add eliasfelis/vault-kit
/plugin install vault-audit@vault-kit
```

Then: copy `plugins/vault-audit/rules.starter.yaml` (opinionated, proven) — or `plugins/vault-audit/rules.example.yaml` for a bare schema — to `rules.yaml`, edit it to match your vault, and run `/vault-audit:vault-audit --dry-run`.

> **Note:** The exact invocation command and subagent names are confirmed at install via `/plugin validate` and `/agents`.

### Principles & opinionated starter

Out of the box the auditor ships with an **opinionated, de-identified starter rulebook** ([`plugins/vault-audit/rules.starter.yaml`](plugins/vault-audit/rules.starter.yaml) / [`rules.starter.md`](plugins/vault-audit/rules.starter.md)) — proven conventions, not a blank schema. The methodology behind them is in [**`plugins/vault-audit/PRINCIPLES.md`**](plugins/vault-audit/PRINCIPLES.md). And [**`plugins/vault-audit/behavior-layer.example.md`**](plugins/vault-audit/behavior-layer.example.md) (+ [**`hooks.example.json`**](plugins/vault-audit/hooks.example.json)) is a coaching layer you can wire as a SessionStart hook so your assistant reinforces the same principles in-session.

### Requirements

Runs on **Windows (via Git Bash), macOS, and Linux**. Needs `bash`, `git`, and `perl` — all bundled with Git for Windows, preinstalled on macOS/Linux. No PowerShell required.

---

## vault-feed

`vault-feed` fetches curated feeds, filters each item for relevance to your declared `interests`, and triage keepers into a dispositioned backlog. Set your interests once; a scout agent pulls and classifies, a triager agent runs the batch disposition flow.

See [`plugins/vault-feed/README.md`](plugins/vault-feed/README.md) for the full quickstart, feeds schema, config reference, and the three-bucket model.

### Install

```
/plugin marketplace add eliasfelis/vault-kit
/plugin install vault-feed@vault-kit
```

---

## Use it freely

MIT-licensed and provided as-is. Fork it, adapt it, ship it. I built this for my own vault and opened it up — I may not get to every issue or PR, but you don't need my permission to make it yours.

---

## Roadmap

A growing collection. `vault-audit` covers rules-based audit; `vault-feed` delivers the feed-pull + triage flow. More vault tools are planned.

---

## License

[MIT](LICENSE)
