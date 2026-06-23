# vault-kit

A small collection of operational tools for running a Claude-Code Markdown knowledge vault. First tool: `vault-audit`.

---

## vault-audit

`vault-audit` audits a vault against its **own declared rules** — a rules pack you fill in once. Two agents, each in an isolated git worktree:

- **Junker** — the deterministic fixer. Scans for broken links, frontmatter rot, naming violations, duplicates, and staleness. Autofixes safe issues on a throwaway branch you review before merge; surfaces ambiguous ones for your decision.
- **Builder** — the judgment reviewer. Checks your declared anti-patterns and declaration-vs-reality drift (e.g. folders named in your config that don't exist). Writes a standalone findings report. Never edits files.

Nothing touches your main branch without review.

### How it stays safe

`vault-audit` autofixes only on a throwaway git branch you review before merge. The judgment agent never edits files — it only writes a report.

### Install

```
/plugin marketplace add eliasfelis/vault-kit
/plugin install vault-audit@vault-kit
```

Then: copy `plugins/vault-audit/rules.example.yaml` → `rules.yaml`, edit it to match your vault, and run `/vault-audit:vault-audit --dry-run`.

> **Note:** The exact invocation command and subagent names are confirmed at install via `/plugin validate` and `/agents`.

### Requirements

Windows + PowerShell 5.1 (v0.1 — the lock/preflight/leak-audit helpers are PowerShell). A cross-platform port is a future item.

---

## Take it and use it

MIT-licensed. This is shared as-is: issues and PRs may go unanswered. No support desk.

---

## Roadmap

A started collection — more vault tools (an innovation feeder, a triage flow) are planned. `vault-audit` is the first.

---

## License

[MIT](LICENSE)
