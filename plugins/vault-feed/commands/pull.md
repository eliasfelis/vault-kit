---
description: "Pull curated feeds, filter for relevance, write actionable inbox entries + a news digest, and update run-state."
argument-hint: "[--setup]"
---

# /vault-feed:pull

Orchestrates the full pull flow: config/feeds resolution → onboarding (first run or
`--setup`) → scout dispatch → inbox + digest write → state update → summary.

---

## Config and feeds resolution (the command owns this)

The command resolves every file. The scout has no Bash, does not know the plugin
root, and therefore cannot follow a fallback chain — so it reads no config at all:
everything it needs arrives inlined in its dispatch prompt.

Resolve these in order:

1. **Config:** look for `vault-feed.yaml` at the vault/working root.
   Absent → fall back to `"${CLAUDE_PLUGIN_ROOT}/vault-feed.example.yaml"`.

2. **Feeds:** look for `feeds.yaml` at the vault/working root
   (or the path in `config.feeds_file` if set).
   Absent → fall back to `"${CLAUDE_PLUGIN_ROOT}/feeds.starter.yaml"`.

3. **Significance criteria:** look for `significance.md` at the vault/working root.
   Absent → fall back to `"${CLAUDE_PLUGIN_ROOT}/significance.example.md"`.
   Read the resolved file's **content** — the scout is handed the text, never the path.

If any of the three resolves to nothing (the bundled fallback is missing too), STOP
with `Cannot resolve <config|feeds|significance>: neither the vault copy nor the
bundled fallback exists.` Never dispatch on a guess.

Pass the **resolved config object**, the **resolved feeds list** (already parsed) and
the **significance criteria text** to the scout in its dispatch prompt.

All runtime paths (`paths.inbox`, `paths.digest`, `paths.state`) come from the
resolved config. Never hardcode a path.

### Interests gate — stop before fetching on a placeholder

`interests` is the only yardstick the scout buckets against, and the shipped
`vault-feed.example.yaml` carries a template rather than interests. Running on it
scores every source against comment text, so the inbox fills with confident noise.

After resolving the config, inspect the `interests` string. Treat it as **unset** if
any of these holds:

- it is absent, empty, or whitespace only; or
- every non-blank line begins with `#` (the shipped block is entirely comments); or
- it still contains an angle-bracket placeholder such as `<e.g. …>`.

When it is unset, print this and STOP — no fetch, no inbox entry, no digest, no state
write. The gate applies to every invocation, `--setup` included: sources are worth
choosing only once the yardstick exists.

```
vault-feed is not configured — `interests` is still the shipped placeholder.

  1. Copy "${CLAUDE_PLUGIN_ROOT}/vault-feed.example.yaml" to `vault-feed.yaml`
     at your vault root.
  2. Replace the `interests` block with YOUR stack and topics: delete the `#`
     comment lines and the <angle-bracket> examples, write plain prose.
  3. Re-run /vault-feed:pull.

Nothing was fetched; no inbox entry, digest, or run-state was written.
```

This is the only place the check lives. The scout either receives real interests or
is never dispatched.

---

## Phase 1 — Onboarding

**Trigger:** run if `--setup` was passed, OR if there is no prior run-state
(first-ever pull). Detect first run by executing:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/feed-state.sh" summary "<paths.state>"
```
If the command exits non-zero (e.g. 65 — the state file exists but is not parseable),
STOP and name the file; do NOT treat it as a first run. Only when it exits 0 AND the
output STARTS WITH `ok=0 failed=0` (prefix/substring match — the actual output may have
trailing tokens such as `failed_slugs=`) treat this as a first run and enter onboarding.

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

Dispatch the scout subagent with everything resolved — config, feeds, and the
significance criteria text:

```yaml
subagent_type: vault-feed:scout
prompt: |
  Config (resolved):
  <inline the full resolved config object as YAML>

  Feeds (resolved, enabled sources only):
  <inline the full resolved feeds list as YAML>

  Significance criteria (verbatim content of the resolved significance file):
  <inline the text — not the path>

  State directory: <paths.state from config>

  Run the pull flow per your specification and return the result JSON.
```

The state directory is the one path the scout resolves: it reads
`<paths.state>/state.json` for the per-source watermarks. That path is absolute from
config with no fallback chain, and an absent file simply means "no watermarks yet" —
so it is safe to hand over, unlike the config/feeds/significance chains above.

Wait for the scout to return its result JSON before proceeding.

**Scout return shape:**

```json
{
  "actionable": [ <inbox-entry objects> ],
  "news":       [ "<one-paragraph string>", ... ],
  "rejected_count": <integer>,
  "sources": [
    { "slug": "<slug>", "max_epoch": <integer or null>, "outcome": "ok|failed" }
  ]
}
```

`sources[]` is the per-source run record and the single input to both the Phase 3d
state write and the Phase 4 FAILED lines — there is no separate `failed[]` array, so
the watermark and the report cannot disagree about which source broke.

- One object per **enabled source in the resolved feeds list**, whether or not it
  returned items. A slug the scout omits is a fault, not a pass: treat it as
  `max_epoch: null, outcome: "failed"` and name it in the summary.
- `max_epoch` — the highest `published_epoch` among the **fresh** items this source
  contributed this run, counting all three buckets (a rejected item was still seen,
  so the watermark must move past it). `null` when the source produced no fresh items
  or failed.
- `outcome` — `failed` on fetch error, parse error, or an unrecovered
  significance-filter parse failure affecting that source's items; `ok` otherwise.

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

The digest file is one per local date: `<paths.digest>/<date>.md`.

**First pull of the day** (the file does not exist) — create it and concatenate the
`scout.news` paragraphs (each is a ready-to-use string):

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

**Second and later pull of the same day** (the file already exists) — **append** a
separated section; never overwrite. Re-running a pull must not silently delete the
morning's digest.

```markdown

---

## Later pull — <HH:MM>

<news paragraph 1>

<news paragraph 2>
```

`<HH:MM>` is the run's local time (UTC shifted by `config.timezone_offset_hours`), so
same-day sections are self-ordering and no counter has to be tracked.

If `scout.news` is empty, still write: the header alone on a first pull, or a section
whose only line is `No news-tier items this pull.` on a later one. A digest that
records nothing is a signal; a missing file is ambiguous.

### 3d. Update run-state per source

One write per enabled source in the resolved feeds list — including the quiet ones and
the broken ones, since an unwritten outcome is an outcome nobody can see:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/feed-state.sh" write \
  "<paths.state>" \
  "<slug>" \
  <epoch> \
  <outcome>
```

Read `<epoch>` and `<outcome>` off that slug's entry in `scout.sources`:

| The source this run                                     | `<epoch>`   | `<outcome>` |
|---------------------------------------------------------|-------------|-------------|
| `outcome: ok` and `max_epoch` is an integer (fresh items)| `max_epoch` | `ok`        |
| `outcome: ok` and `max_epoch` is `null` (quiet, healthy) | `keep`      | `ok`        |
| `outcome: failed` (fetch or parse error)                 | `keep`      | `failed`    |
| absent from `scout.sources` entirely                     | `keep`      | `failed`    |

`keep` is a literal the script understands: it preserves the stored `last_seen` (0
when the slug is new) and updates only the outcome.

**Never pass `0` for a quiet source.** `0` is a real epoch and the script writes it,
wiping the watermark — the next pull then treats the source's whole history as fresh
and re-floods the inbox. `keep` is the only correct value when there is nothing new.

A failed source also gets `keep`, never its `max_epoch`: its items were not classified
this run, so the watermark must not move past them.

`<paths.state>` = `config.paths.state`. The script creates the directory if absent.
If a write exits non-zero, carry on with the remaining sources and report it in
Phase 4 as `FAILED: state write <slug> (exit <code>)`.

---

## Phase 4 — Summary

Print a one-line count summary, then one `FAILED:` line per failure (never silent —
fail-soft ≠ silent):

```
Pull complete — <date>
  Actionable: <count of scout.actionable>   written to <paths.inbox>/
  News:       <count of scout.news>          written to <paths.digest>/<date>.md
  Rejected:   <scout.rejected_count>
```

Then, for every source in `scout.sources` whose `outcome` is `failed`, plus every
source the feeds list carried but `scout.sources` omitted (zero or more — these are
the CURRENT run's failures, NOT all-time cumulative state):

```
FAILED: <slug>
```

And one line per state write that exited non-zero in Phase 3d:

```
FAILED: state write <slug> (exit <code>)
```

With no failures, omit the FAILED lines entirely. Do not add an "all sources
succeeded" message — for failures, silence is the success signal.

---

## Error handling

| Failure                          | Behaviour                                                 |
|----------------------------------|-----------------------------------------------------------|
| Config file absent               | Fall back to `vault-feed.example.yaml` (see resolution)  |
| Feeds file absent                | Fall back to `feeds.starter.yaml` (see resolution)       |
| Significance file absent         | Fall back to `significance.example.md` (see resolution)  |
| A bundled fallback also missing  | STOP naming which one; do not dispatch                   |
| `interests` still the placeholder| STOP with the setup message; nothing fetched or written  |
| State file unparseable           | `feed-state.sh` exits 65; STOP and name the file — do NOT onboard as a first run and do NOT write |
| Scout returns empty actionable   | Write digest, update state, print summary (0 actionable)  |
| Scout fails entirely             | Surface the error; do not write partial state             |
| Slug missing from `scout.sources`| Write `keep failed`; list it under Phase 4 FAILED         |
| `feed-state.sh write` non-zero   | Continue other sources; `FAILED: state write <slug>`      |
| Inbox directory absent           | Create it before writing the first entry                  |
| Digest directory absent          | Create it before writing the digest file                  |
| Digest file for today exists     | Append a `## Later pull — <HH:MM>` section; never overwrite|
| State directory absent           | `feed-state.sh write` creates it (`mkdir -p` internally)  |

---

## Flags

| Flag      | Meaning                                               |
|-----------|-------------------------------------------------------|
| (none)    | Full pull run                                         |
| `--setup` | Force onboarding phase (re-show sources, offer search)|
