# vault-kit

A small collection of operational tools for running a Claude-Code Markdown knowledge vault — `vault-audit`, `vault-feed` and `vault-persona`, with more to come.

## Install

Every plugin comes from the one marketplace, and each is its own **separate install** (adding the marketplace alone installs nothing):

```
/plugin marketplace add eliasfelis/vault-kit
/plugin install vault-audit@vault-kit
/plugin install vault-feed@vault-kit
/plugin install vault-persona@vault-kit
```

---

## vault-audit

`vault-audit` audits a vault against its **own declared rules** — a rules pack you fill in once. Two agents, each in an isolated git worktree:

- **Linter** — the deterministic fixer. Scans for broken links, frontmatter rot, naming violations, duplicates, and staleness. Autofixes safe issues on a throwaway branch you review before merge; surfaces ambiguous ones for your decision.
- **Judge** — the judgment reviewer. Checks your declared anti-patterns and declaration-vs-reality drift (e.g. folders named in your config that don't exist). Writes a standalone findings report. Never edits files.
- **Leak gate** — `/vault-audit:leak-scan`: an on-demand pre-publish scan for secrets and instance literals (shipped generic patterns + your private extras kept outside the repo).

Nothing touches your working branch without review.

### How it stays safe

`vault-audit` autofixes only on a throwaway git branch you review before merge. The judgment agent never edits files — it only writes a report.

### Setup

After install (see **Install** above): copy the starter pack into **your vault root** and edit it there — `cp "${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml" ./rules.yaml` (or start from `rules.example.yaml` for a bare schema; add `rules.starter.md` → `./rules.md` for the judgment checks) — then run `/vault-audit:vault-audit --dry-run`. The plugin looks in your vault first and falls back to the shipped starter, announcing which pack it loaded on every run. Keep your pack out of the plugin directory — a reinstall replaces that tree wholesale.

> **Note:** The exact invocation command and subagent names are confirmed at install via `/plugin validate` and `/agents`.

### Principles & opinionated starter

Out of the box the auditor ships with an **opinionated starter rulebook** ([`plugins/vault-audit/rules.starter.yaml`](plugins/vault-audit/rules.starter.yaml) / [`rules.starter.md`](plugins/vault-audit/rules.starter.md)) — proven conventions, not a blank schema. The methodology behind them is in [**`plugins/vault-audit/PRINCIPLES.md`**](plugins/vault-audit/PRINCIPLES.md). And [**`plugins/vault-audit/behavior-layer.example.md`**](plugins/vault-audit/behavior-layer.example.md) is a coaching layer so your assistant reinforces the same principles in-session — load it by adding one line, `@behavior-layer.md`, to your `CLAUDE.md`, not through a SessionStart hook (hook stdout is capped and silently truncates a file this size; see the plugin README).

### Requirements

Runs on **Windows (via Git Bash), macOS, and Linux**. Needs `bash`, `git`, and `perl` — all bundled with Git for Windows, preinstalled on macOS/Linux. No PowerShell required.

---

## vault-feed

`vault-feed` fetches curated feeds, filters each item for relevance to your declared `interests`, and triage keepers into a dispositioned backlog. Set your interests once; a scout agent pulls and classifies, a triager agent runs the batch disposition flow.

See [`plugins/vault-feed/README.md`](plugins/vault-feed/README.md) for the full quickstart, feeds schema, config reference, and the three-bucket model.

**Bridge:** vault-audit findings flow into vault-feed's triage backlog via `/vault-feed:import-audit` — so audit issues and feed items share one disposition ledger.

---

## vault-persona

`vault-persona` switches your assistant's voice for a target audience. Same work, different reader: the answer that helps a fellow engineer is the wrong answer for someone deciding a budget, and both are wrong for a reader who does not know the vocabulary.

One command — `/vault-persona:persona <name>` — resolves a markdown file, merging your own personas directory with the starters shipped inside the plugin, so adding a persona means writing a file rather than editing a command. Starters ship (`executive`, `non-technical`, `peer`) as worked samples to rewrite rather than defaults to obey, and they work out of the box — a file of yours shadows a starter of the same name.

The overlay governs how the assistant writes, never what is true: it may change vocabulary, length and what comes first, but not drop a caveat that matters or inflate confidence. See [`plugins/vault-persona/README.md`](plugins/vault-persona/README.md).

---

## Not using Claude Code?

The plugins are Claude-Code-native (slash commands + subagents), but the material is portable: the rules packs (`rules.starter.yaml` / `rules.starter.md`) and `PRINCIPLES.md` read as plain guidance docs for any coding agent (Codex, Copilot, …), and the helper scripts (`leak-audit.sh`, `feed-state.sh`, `lock.sh`, `preflight.sh`) are plain bash + perl — they run anywhere Git Bash runs. To port a flow, hand your agent the corresponding `plugins/*/commands/*.md` file as a prompt.

---

## Use it freely

MIT-licensed and provided as-is. Fork it, adapt it, ship it. I built this for my own vault and opened it up — I may not get to every issue or PR, but you don't need my permission to make it yours.

---

## Roadmap

A growing collection. `vault-audit` covers rules-based audit, `vault-feed` delivers the feed-pull + triage flow, and `vault-persona` handles audience overlays. Next planned: a git-truth staleness check for vault-audit — frontmatter dates against the file's actual last-commit date, which catches both the note that claims to be fresh and the one that looks abandoned but is not. More vault tools after that.

---

## License

[MIT](LICENSE)
