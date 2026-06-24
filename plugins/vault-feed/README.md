# vault-feed

Fetches curated feeds, filters each item for relevance to YOUR declared interests, and triage keepers into a dispositioned backlog. Two agents: a **scout** (pull + classify) and a **triager** (batch disposition). You set the relevance yardstick once — the rest runs on its own.

---

## Install

```
/plugin marketplace add eliasfelis/vault-kit
/plugin install vault-feed@vault-kit
```

---

## Quickstart

**Interests first** — that is the one thing to set before anything else.

1. Copy the starter files to your vault root:
   - `feeds.starter.yaml` → `feeds.yaml` (your live feed list)
   - `vault-feed.example.yaml` → `vault-feed.yaml` (your config)

2. Open `vault-feed.yaml` and edit the `interests` field. This is the relevance yardstick the scout uses to decide what is actionable vs. news-tier vs. reject. Everything else has working defaults.

3. Run the setup wizard (shows sources, offers to search for more):
   ```
   /vault-feed:pull --setup
   ```

4. Run your first pull:
   ```
   /vault-feed:pull
   ```

5. Triage what landed in your inbox:
   ```
   /vault-feed:triage
   ```

> **Note:** The exact invocation commands and subagent names are confirmed at install via `/plugin validate` and `/agents`.

---

## Feeds schema

Each entry in `feeds.yaml` has these fields:

| Field | Required | Description |
|---|---|---|
| `slug` | yes | Short unique identifier (URL-safe, no spaces). |
| `name` | yes | Human-readable source name. |
| `tier` | yes | Grouping label for display (`1`–`4`, `gh`, or `custom`). Organisational only — no filtering logic. |
| `page_url` | yes | The source's canonical page (shown at onboarding). |
| `feed_url` | no | RSS/Atom URL. Null if the source is scraped. |
| `type` | yes | `rss`, `atom`, or `scrape`. |
| `notes` | no | Free-text notes (not used in processing). |

The bundled `feeds.starter.yaml` covers AI / developer tooling sources. Copy it to your vault root as `feeds.yaml` and add or remove entries freely — it is your live list and is never overwritten by the plugin.

---

## Config fields (`vault-feed.yaml`)

| Field | Default | Description |
|---|---|---|
| `feeds_file` | `feeds.yaml` | Path to your feed list (relative to vault root). |
| `interests` | _(example)_ | **The relevance yardstick.** Free-text description of what matters to you. The scout scores every item against this before bucketing. |
| `paths.inbox` | `feed/inbox` | Directory for actionable inbox entries. |
| `paths.triaged` | `feed/triaged` | Directory for dispositioned entries. |
| `paths.digest` | `feed/digest` | Directory for news-tier digest files. |
| `paths.state` | `.vault-feed/runs` | Directory for per-source run-state (last-seen epoch, outcome). |
| `statuses` | `[adopt, park, reject, experiment]` | Ordered list of valid triage dispositions. |
| `timezone_offset_hours` | `0` | UTC offset for local date in file names and frontmatter. |

Copy `vault-feed.example.yaml` to `vault-feed.yaml` and edit. The plugin falls back to the example config if no `vault-feed.yaml` is present.

---

## The three buckets

Every item the scout retrieves lands in exactly one bucket, judged against your `interests`:

| Bucket | Output | Description |
|---|---|---|
| **actionable** | Full inbox entry (`.md` file in `paths.inbox`) | Relevant enough to act on. Carries value / effort / confidence scores and a summary. Feeds `/vault-feed:triage`. |
| **news-tier** | One paragraph in the per-run digest (`paths.digest`) | Worth knowing, not worth a task. |
| **reject** | Dropped | Off-topic or noise. Counted in the summary, not written. |

The bucketing threshold is calibrated against the bundled offline eval-set (see below). Expect roughly the same recall/precision profile the eval set demonstrates.

---

## Output directories

All paths come from your config (defaults shown — see `vault-feed.example.yaml`):

| Path | What lands here |
|---|---|
| `feed/inbox/` | Actionable entries: `<date>-<slug>-<n>.md`. Frontmatter carries `type`, `source`, `title`, `url`, `date_captured`, `status: inbox`, `value`, `effort`, `confidence`, `decision_reason`. |
| `feed/triaged/` | Entries after `/vault-feed:triage` disposition. Frontmatter `status` field updated in-place. |
| `feed/digest/` | Per-run digest files (one file per date): `<date>.md`. One paragraph per news-tier item. A second same-day pull overwrites that date's digest. |
| `.vault-feed/runs/` | Per-source run-state (last-seen epoch + outcome). Used to avoid re-surfacing seen items. |

---

## Offline eval-set

`examples/significance-eval/eval-set.md` contains the labelled acceptance set used to calibrate the scout's significance filter. The acceptance bar is **≥ 80% accuracy (≥ 9 of 11 items correctly bucketed)** before the scout spec is considered stable. Review it if you find the bucketing off for your interests — the eval items show the intended boundary between actionable and news-tier.

`examples/demo-inbox/` contains a triage fixture: three pre-built inbox entries you can run `/vault-feed:triage` against without a live pull. Expected dispositions are in `examples/demo-inbox/EXPECTED.md`.

---

## Requirements

Runs on **Windows (via Git Bash), macOS, and Linux**. Needs `bash`, `git`, and `perl` — all bundled with Git for Windows, preinstalled on macOS/Linux. No PowerShell required.

Native **WebFetch** is used for feed retrieval on every pull. **WebSearch** is optional and used only during the onboarding wizard (`/vault-feed:pull --setup`) to suggest additional sources.

MIT-licensed.
