---
description: "Pull curated feeds, filter for relevance, write actionable inbox entries + a news digest, and update run-state."
argument-hint: "[--setup]"
---

# /vault-feed:pull

Orchestrates the full pull flow: config/feeds resolution → onboarding (first run or
`--setup`) → scout dispatch → inbox + digest write → state update → summary.

---

## Config and feeds resolution (the command owns this)

Before dispatching, resolve three files in order:

1. **Config:** look for `vault-feed.yaml` at the vault/working root.
   Absent → fall back to `${CLAUDE_PLUGIN_ROOT}/vault-feed.example.yaml`.

2. **Feeds:** look for `feeds.yaml` at the vault/working root
   (or the path in `config.feeds_file` if set).
   Absent → fall back to `${CLAUDE_PLUGIN_ROOT}/feeds.starter.yaml`.

3. **Significance:** the scout resolves `significance.md` → fallback
   `${CLAUDE_PLUGIN_ROOT}/significance.example.md` itself; no command action needed.

Pass the **resolved config object** and **resolved feeds list** (already parsed) to
the scout via its dispatch prompt. Do not pass raw file paths — parse and inline the
content so the scout never re-reads ambiguously.

All runtime paths (`paths.inbox`, `paths.digest`, `paths.state`) come from the
resolved config. Never hardcode a path.

---

## Phase 1 — Onboarding

**Trigger:** run if `--setup` was passed, OR if there is no prior run-state
(first-ever pull). Detect first run by executing:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/feed-state.sh summary <paths.state>
```
If the output is `ok=0 failed=0` (empty state), treat this as a first run and
enter onboarding.

### 1a. Show default sources

Display the resolved feeds list grouped by tier. For each source show:
`<tier> | <slug> | <name> | <page_url>`.

Example heading per tier:
```
Tier 1 — Platforms (5 sources)
  anthropic-news      Anthropic news           https://www.anthropic.com/news
  claude-code-releases  Claude Code releases   https://github.com/anthropics/claude-code/releases
  ...
```

### 1b. Offer personalisation

Ask the user in one message:
> "These are the default sources. Would you like to: (a) add your own feeds, or
> (b) search for RSS/Atom sources matching your interests? Both optional — the
> defaults are a complete starting set."

### 1c. Optional: WebSearch for additional sources

**Only if the user opts in to search (option b).** Run a **one-shot** WebSearch
(never per-pull — onboarding only) for RSS/Atom feeds matching the `interests`
string from the resolved config. Propose candidate sources with their URLs. For
each one the user accepts, append a new entry to `feeds.yaml` at the
vault/working root. **If no `feeds.yaml` exists there yet:** first copy
`${CLAUDE_PLUGIN_ROOT}/feeds.starter.yaml` to `<vault_root>/feeds.yaml`, then
append to `<vault_root>/feeds.yaml`. **NEVER append to or modify
`${CLAUDE_PLUGIN_ROOT}/feeds.starter.yaml`** — it is a shipped, read-only plugin
file (regenerated on reinstall; user feed URLs must never land in the plugin tree).
Entry shape:

```yaml
- slug: <url-slug>
  name: <human-readable name>
  tier: custom
  page_url: <page_url>
  feed_url: <feed_url or null>
  type: rss | atom | scrape
```

If WebSearch is unavailable or the user declines → skip silently. The defaults
suffice for a first run.

### 1d. Personalisation option (a): manual add

If the user chose option (a) — add feeds manually — accept one or more feed URLs
directly. For each, ask for a name and slug, then append to `feeds.yaml` (same
logic as 1c). Skip if the user declines.

After onboarding (or if it was skipped) → proceed to Phase 2.

---

## Phase 2 — Pull (scout dispatch)

Dispatch the scout subagent with the fully resolved config and feeds:

```yaml
subagent_type: vault-feed:scout  # TODO-VERIFY prefix (confirmed at install in Task 9)
prompt: |
  Config (resolved):
  <inline the full resolved config object as YAML>

  Feeds (resolved, enabled sources only):
  <inline the full resolved feeds list as YAML>

  State directory: <paths.state from config>

  Run the pull flow per your specification and return the result JSON.
```

Wait for the scout to return its result JSON before proceeding.

**Scout return shape:**

Note: the `failed` key name is part of the scout agent's return contract (confirmed
in the scout spec). Do not rename it — the Phase 3d state-write and the Phase 4
FAILED summary both key off `scout.failed` by exact name.

```json
{
  "actionable": [ <inbox-entry objects> ],
  "news":       [ "<one-paragraph string>", ... ],
  "rejected_count": <integer>,
  "failed":     [ "<slug>", ... ],
  "digest_path": null
}
```

`digest_path` from the scout is always `null` — the command sets the actual path.

---

## Phase 3 — Write

### 3a. Compute the local date

Compute today's date string `YYYY-MM-DD` by applying `config.timezone_offset_hours`
to UTC (e.g. offset `+5` means UTC+5). All file names and frontmatter `date_captured`
fields use this local date.

### 3b. Write actionable inbox entries

For each entry in `scout.actionable`:

1. Compute a slug: lowercased `title`, non-alphanumeric → `-`, max 60 chars.
2. Check for collisions in `<paths.inbox>/`. If `<date>-<slug>-1.md` exists,
   increment the counter: `-2`, `-3`, etc. Start at `-1` (always include the counter
   — ensures consistent naming).
3. Write `<paths.inbox>/<date>-<slug>-<n>.md`:

```markdown
---
type: <entry.type>
source: <entry.source>
title: "<entry.title>"
url: <entry.url>
date_captured: <entry.date_captured>
status: inbox
value: <entry.value>
effort: <entry.effort>
confidence: <entry.confidence>
decision_reason: "<entry.decision_reason>"
---

<entry.summary>
```

Field mapping: frontmatter fields come directly from the inbox-entry object;
the file body is `entry.summary` verbatim.

### 3c. Write the news digest

Concatenate `scout.news` paragraphs (each is a ready-to-use string) into a single
digest file:

`<paths.digest>/<date>.md`

```markdown
---
date: <date>
source: vault-feed
tags: [digest, vault-feed]
---

# Feed digest — <date>

<news paragraph 1>

<news paragraph 2>

...
```

If `scout.news` is empty, write the file anyway with only the header (so the state
records a successful digest write).

### 3d. Update run-state per source

For each source slug in the resolved feeds list:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/feed-state.sh write \
  <paths.state> \
  <slug> \
  <newest_published_epoch_for_this_slug> \
  <outcome>
```

- `outcome` = `ok` if the slug is **not** in `scout.failed`; `failed` if it is.
- `newest_published_epoch` = the highest `published_epoch` among the actionable +
  news entries for this source (use 0 if the source had no fresh items this run —
  this leaves the existing `last_seen` unchanged on the next read, which is correct).
- `<paths.state>` = `config.paths.state`.

Run this for every enabled source in the feeds list (not only sources that returned
items — sources that failed also need their outcome recorded as `failed`).

---

## Phase 4 — Summary

Print a one-line count summary followed by one `FAILED:` line per entry in
`scout.failed` (never silent — fail-soft ≠ silent):

```
Pull complete — <date>
  Actionable: <count of scout.actionable>   written to <paths.inbox>/
  News:       <count of scout.news>          written to <paths.digest>/<date>.md
  Rejected:   <scout.rejected_count>
```

Then, for every slug in `scout.failed` (zero or more — these are the CURRENT run's
failures, NOT all-time cumulative state):

```
FAILED: <slug>
```

If `scout.failed` is empty, omit the FAILED lines entirely. Do not add an "all
sources succeeded" message — silence is the success signal for failures.

---

## Error handling

| Failure                         | Behaviour                                                |
|---------------------------------|----------------------------------------------------------|
| Config file absent              | Fall back to `vault-feed.example.yaml` (see resolution) |
| Feeds file absent               | Fall back to `feeds.starter.yaml` (see resolution)      |
| Scout returns empty actionable  | Write digest, update state, print summary (0 actionable) |
| Scout fails entirely            | Surface the error; do not write partial state            |
| Inbox directory absent          | Create it before writing the first entry                 |
| Digest directory absent         | Create it before writing the digest file                 |
| State directory absent          | `feed-state.sh write` creates it (`mkdir -p` internally) |

---

## Flags

| Flag      | Meaning                                               |
|-----------|-------------------------------------------------------|
| (none)    | Full pull run                                         |
| `--setup` | Force onboarding phase (re-show sources, offer search)|
