---
description: "Run the leak gate on demand: scan a path for secret / instance-literal patterns (shipped generic set + your private extras). Read-only, fail-loud."
---

# /vault-audit:leak-scan — pre-publish leak gate

One deterministic script run + a readable verdict. Scans, never edits. This is the same engine vault-kit uses to gate its own publishes: a shipped **generic** pattern set (credential shapes, user-profile paths) plus an optional **private** pattern file holding YOUR instance literals, kept outside any published repo.

## Arguments

| Arg | Effect |
|---|---|
| `--path P` | File or directory to scan. Default: resolved from the rules pack (Step 1). |
| `--extra-patterns F` | Private pattern file — one perl/PCRE regex per line, `#` comments. Keep it OUTSIDE the scanned repo. |
| `--tracked-only` | Enumerate `git ls-files` instead of a filesystem walk (requires `P` to be a directory inside a git repo — with a single-file `P` the flag is a usage error, not a no-op). Fail-closed coverage: every tracked file is checked regardless of extension; gitignored scratch never is. |
| `--exclude REGEX` | Path-exclude regex applied to the enumerated file list. **Additive:** `\.git/` is always excluded and your regex is OR-ed onto it, never substituted for it. |

## Behavior

### Step 1 — resolve target + defaults

- `--path` given → use it verbatim.
- Else load the rules pack (same resolution order as `/vault-audit`, **your vault first**: `<cwd>/rules.yaml` → `${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml` → `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml`) and read the optional `leak_scan:` block for defaults (`extra_patterns`, `tracked_only`, `exclude`); the target is `cfg.vault.root`.
- Whenever a pack is loaded, name it in one line before the scan — `Rules pack: <path> (user | starter fallback | example fallback)`. A gate configured from a fallback you did not notice is a gate configured by someone else.
- Explicit flags always override config values.
- Resolve the target to an **absolute path** and echo it before running — a relative `.` silently scanning the wrong cwd is how a gate certifies the wrong tree.
- If the target still does not resolve to an existing path → ask the user for it (one question). Do not guess.

### Step 2 — run the gate

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/leak-audit.sh" --path <P> [--tracked-only] [--extra-patterns <F>] [--exclude <REGEX>]
```

### Step 3 — report by exit code

| Exit | Meaning | What to show |
|---|---|---|
| `0` | clean | Relay the script's own verdict line — `OK: no leaks (N file(s) scanned, 0 unscannable)` including BOTH counts — plus what was covered (resolved path, walk vs tracked-only, pattern layers loaded: shipped + private yes/no). A clean verdict without the counts is not a verdict. |
| `1` | leak(s) or unreadable file(s) | The findings table below, with every matched token MASKED. Close with: **do not publish until clean.** |
| `2` | gate could not certify | Relay the script's stderr and stdout verbatim, and say WHICH cause fired: missing/invalid pattern file, empty pattern set, invalid `--exclude` regex, over-broad `--exclude`, zero files, `--tracked-only` outside a git repo, or **unscannable paths** — binary/UTF-16 files **and directory / submodule-gitlink entries**. In that last case list them from the `UNSCANNABLE` block (each entry is tagged `[binary/UTF-16]` or `[directory/gitlink]`) and name the way out per tag — convert a UTF-16 file to UTF-8; `--exclude` a gitlink to put it out of scope on the record. A gate that could not certify must NEVER be relayed as clean. |
| `64` | usage error | Relay the script's stderr — it names the exact problem (e.g. `path not found: <P>`, `--tracked-only` with a single-file `--path`, `unknown arg`) — then show the usage line from the script header. |

**The script's finding lines do not all carry a line number — a filename match has no line, an unreadable file has neither. Fill the cells with what exists, never with a guess:**

| Script output | file | line | match |
|---|---|---|---|
| `LEAK <file>:<n>: <text>` | `<file>` | `<n>` | masked token from `<text>` |
| `LEAK (filename) <file>` | `<file>` | `—` (the finding is the NAME, not a line in it) | masked offending part of the filename |
| `FAILED: cannot read <file>: <reason>` | `<file>` | `—` | `—` · not a leak: an unread file, reason `<reason>` |

An em dash in those cells is the honest answer. Inventing a line number for a filename match, or listing an unreadable file as if a pattern had matched it, misreports what the gate actually saw.

Masking is mandatory when relaying: the script echoes full matched lines; truncate every matched token in what you show. Never write findings to a file. Note the honest boundary: the raw script output (with unmasked matches) does pass through the terminal and session transcript before masking — when scanning for LIVE credentials (vs instance literals), treat the scan session itself as sensitive.

### Step 4 — suggest the standing setup (only when relevant)

If the run used no private pattern file (none passed, none in config), append one short note: create one OUTSIDE the repo (e.g. a sibling private folder) listing your instance literals — names, brands, internal project codes, hostnames — and wire it via `leak_scan.extra_patterns` in `rules.yaml`. Skip the note if a private file was already in play.

## Config (optional)

```yaml
leak_scan:               # defaults for /vault-audit:leak-scan; flags override
  extra_patterns: ""     # absolute path to your PRIVATE pattern file (outside any published repo)
  tracked_only: true
  exclude: ''         # ADDED to the always-on `\.git/` exclusion, never a replacement for it
```

## Limits & discipline

- **Patterns are case-sensitive.** For instance literals, prefix `(?i)` — `(?i)acmecorp` catches `AcmeCorp`, `ACMECORP`, `acmecorp`.
- **A literal with regex metacharacters must be escaped** (`Acme (UK) Ltd` as a raw line matches nothing — write `Acme \(UK\) Ltd` or wrap in `\Q…\E`). The gate validates that patterns COMPILE, not that they can match.
- **Positive-control every new private pattern file:** plant one of its literals in a scratch file, run the scan, confirm exit `1`. A pattern set that has never failed a planted leak has never been proven to work.
- **Filenames are checked too** (relative to the scan root) — instance literals leak via paths, not just content.
- **A path the gate cannot line-scan fails the run (exit `2`), it does not pass with a note.** Two shapes qualify and both are listed under `UNSCANNABLE`: binary / UTF-16 files (PowerShell's `>` redirect writes UTF-16 — and a NUL anywhere in the file counts, so an ASCII heading in front of a UTF-16 body does not buy a clean verdict), and **directory entries such as a submodule gitlink** enumerated by `--tracked-only`, whose contents this run does not open at all. An unread path and a clean path are not the same thing, and a leak hidden in one is exactly what a gate exists to catch. Convert a UTF-16 file to UTF-8, or `--exclude` the path — the exclusion is then a decision on the record instead of a silent skip. (A submodule is scanned by pointing a separate run at it.)
- **A UTF-8 BOM never silences a pattern.** A BOM'd pattern line compiles clean and then matches nothing; the gate strips a leading BOM from every pattern line in both layers (shipped and `--extra-patterns`) and from the first line of every scanned file. You still get the positive control below — but a Windows editor saving your private pattern file will not quietly disarm it.
- **`--exclude` is an unanchored regex** over the enumerated paths, and it is **added** to the built-in `\.git/` exclusion rather than replacing it. Anchor yours (`^\./docs/generated/`) — a bare substring like `\.git/` also drops `vendor/upstream.git/…`. An `--exclude` that fails to compile is reported as an invalid regex (exit `2`), never as an empty file list.
