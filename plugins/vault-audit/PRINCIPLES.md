# Principles

The methodology the starter rules pack encodes and the auditor enforces. These are field-tested conventions for running a Claude-Code Markdown knowledge vault as a single knowledge-worker; adopt them whole or pick the ones that fit your setup.

---

## CORE — Capture → Organize → Review → Engage

Every artifact lives in one of four phases, and work moves forward through them in order.

- **Capture** — a single quick-capture inbox for raw notes, transcripts, voice-to-text. No structure required; speed is the point.
- **Organize** — durable homes: projects, reference resources, meeting notes, briefs. Captured material is sorted here, not left in the inbox.
- **Review** — daily focus, periodic reviews, and gate/checkpoint reviews. This is where you read what you have and decide what matters.
- **Engage** — action goes out: tickets, messages, briefings — and the decisions behind them are recorded.

Don't skip stages. A note jumps from Capture to Engage without ever being Organized or Reviewed, and you act on stale or half-understood context. The inbox is for capture only; clear it on a fixed cadence so nothing long-lived rots there.

---

## Discipline rules

The gold. Seven rules that keep a single-operator system from drifting into noise. Each is a principle plus the failure it prevents.

### subtraction-not-mechanism

Default to subtraction, not new machinery. When something goes wrong once, fix the instance — do not stand up new infrastructure, a new process, or a governance layer to prevent it. Build mechanism only when the *same* drift recurs or causes real operational damage. The reason: every mechanism you add is permanent overhead that future-you must maintain, route around, and remember. A one-off mistake costs you once; a process built to prevent it taxes every session forever. Make the system earn its complexity by letting the problem prove it is recurring first.

### fail-soft ≠ silent

A pipeline step you allow to fail without aborting its parent must still announce that it failed. Surface an explicit `FAILED: <step>` line in the run's user-facing summary, and record the outcome in run-state by *status* (done / failed), never by a proxy like attempt count or last-modified time. The reason: "fail-soft" is supposed to mean the run survives a non-critical error, but if the failure is swallowed, a broken leg of your pipeline can sit dead for weeks while the run keeps reporting success. Silent tolerance is indistinguishable from working. Fail soft on the control flow, loud on the report.

### defer-to-a-concrete-channel

When you defer an item, route it to a channel that has a clock — a dated task, a decision with a due date, a scheduled review — never to an abstract "later" or a catch-all "I'll handle it at the weekly review." The reason: a name without a clock is a black hole. Items parked under a vague label are never disposed, only accumulated; the pile grows until it is noise nobody triages. Capture without an explicit disposal step is just deferred drift. Every deferral needs a where and a when, or it isn't a deferral — it's a loss.

### one-source-of-truth

Every fact lives in exactly one place. If two places disagree, that is a conflict to resolve, not a copy to keep — mark it contested and escalate, then reconcile to a single home. The reason: duplicated facts drift apart silently, and once they do you can no longer trust either copy or tell which is current. The cost of a single canonical location is a little indirection; the cost of two is a slow-motion data-integrity failure you discover at the worst moment. One fact, one home.

### verify-live-state-before-acting

Before you act, check the live state — read the file, run the script, inspect the actual repo — rather than trusting docs, specs, or memory. Each of those can be stale, and recalled memory most of all. For anything deployed, verify the *deployed* revision too, not just your local source, before you debug it. The reason: documentation and memory describe the system as it was believed to be, not as it is; acting on a stale picture means diagnosing problems against code the machine isn't actually running and "fixing" things that already changed. Ground every consequential action in current reality, not in a remembered model of it.

### atomic-commits-by-workstream

Commit by workstream with explicit pathspecs; never reach for a blanket `git add -A`. Before any interactive commit or push, show the status, a staged-diff summary, and the proposed message, then proceed. The reason: blanket staging sweeps unrelated and unreviewed changes — half-finished edits, sensitive drops, generated junk — into one opaque commit, which destroys reviewability and makes a clean revert impossible. Atomic, scoped commits keep history legible and each change independently reversible. The few seconds to name your pathspecs buys you a history you can actually read and trust.

### outbound-send-gate

Put a human gate in front of anything that leaves your system. Send- and publish-class actions (sending mail, posting to a channel, uploading, creating an external event) default to *ask*, never silent-allow; drafting is fine to automate, because a draft is not a send. The reason: an automated read or an internal edit is recoverable, but an outbound message is irreversible the instant it lands in someone else's inbox or channel. The asymmetry between "draft for me to approve" and "sent on my behalf" is the whole game. Let automation prepare freely; keep a hand on the trigger for anything that crosses the boundary out.

---

## Naming

Name files on one predictable scheme: `<project> <type> <description> - <date>.md`. A consistent shape means a filename is itself metadata — you can scan, sort, and locate without opening anything, and tooling can validate names mechanically. Pick a delimiter and a date format and hold them everywhere.

Allow a small set of **exempt folders** that opt out by design: entity registries (one file per person / place / method, named by the entity, where a date-stamped scheme would be noise), templates, and the archive. These follow their own internal convention or keep their original document names. Declare the exemptions explicitly so the auditor skips them instead of flagging them — and keep the exempt set small, or "exempt" quietly becomes "unconventional everywhere."

---

## Session summaries

Once per working day, write a dense, fielded session summary. Keep it terse and machine-readable — four fields are enough: **scope** (what you worked on), **changed** (what moved), **decisions** (what you decided and why), **open** (what is still unresolved). Prose is the wrong format here; you and your tools should be able to parse it at a glance. The summary is the durable record of a day's thinking, not a diary.

Then close the loop: sweep the still-open follow-ups from the summary into your task manager so nothing actionable lives only in a log. Mark agent-created tasks with a provenance marker — a consistent prefix in the title — so a task the system queued is always distinguishable from one you typed yourself. That marker lets cross-session sweeps deduplicate cleanly and lets you see at a glance what the assistant added versus what you own.

---

## Changelog

Record architectural and behavioral changes in a changelog — new commands, new rules, structural moves, anything that changes how the system works. Write the changelog entry *before* the session summary. The reason for the ordering: the changelog is the durable, project-level record, while a session summary is a snapshot of one day; leading with the durable record ensures the lasting account is captured first and the daily note references it, not the other way around. The changelog answers "how did the system get this way?" long after any single session is forgotten.

---

## Memory hygiene

If you keep a long-lived memory store, hold it to three rules. **One fact per file** — each memory note is a single self-contained topic, not a junk drawer. **One index line per fact** — a short pointer in a single index, so the index stays a navigable table of contents and never balloons into a second copy of the content. **A cold archive for the expired** — when a fact is finished or superseded, move it to an archive that the index does not load, so it costs nothing yet stays recoverable. Then clean the index periodically: prune dead pointers and tighten the rest so it remains scannable. Memory that is never gardened stops being a resource and becomes overhead — every stale line is context you pay for and noise you read past.

---

## How the pieces fit

Three layers, one set of conventions:

- **The starter rules pack ENCODES them.** `rules.starter.yaml` and `rules.starter.md` ship these conventions as the auditor's out-of-box defaults — the opinionated, proven set rather than a blank schema.
- **The auditor ENFORCES them.** The two agents — `linter` (the deterministic fixer: broken refs, frontmatter, naming, duplicates, staleness) and `judge` (the judgment reviewer: anti-patterns and declaration-vs-reality drift) — check the live vault against the rules pack and surface what has drifted.
- **The behavior-layer COACHES them.** `behavior-layer.example.md` carries the same principles into the session as in-the-moment reflexes, so the conventions are reinforced while you work — not only caught after the fact by an audit.

Encode the method, enforce it mechanically, coach it in the moment — so the approach outlives any single vault.
