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
| `--tracked-only` | Enumerate `git ls-files` instead of a filesystem walk (requires `P` inside a git repo). Fail-closed coverage: every tracked file is checked regardless of extension (NUL-containing binary/UTF-16 files are skipped VISIBLY, never silently); gitignored scratch never is. |
| `--exclude REGEX` | Path-exclude regex applied to the enumerated file list (default: `\.git/`). |

## Behavior

### Step 1 — resolve target + defaults

- `--path` given → use it verbatim.
- Else load the rules pack (same fallback chain as `/vault-audit`: `${CLAUDE_PLUGIN_ROOT}/rules.yaml` → `${CLAUDE_PLUGIN_ROOT}/rules.starter.yaml` → `${CLAUDE_PLUGIN_ROOT}/rules.example.yaml`) and read the optional `leak_scan:` block for defaults (`extra_patterns`, `tracked_only`, `exclude`); the target is `cfg.vault.root`.
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
| `0` | clean | Relay the script's own verdict line — `OK: no leaks (N file(s) scanned…)` including the file COUNT and any binary-skip note — plus what was covered (resolved path, walk vs tracked-only, pattern layers loaded: shipped + private yes/no). A clean verdict without the count is not a verdict. |
| `1` | leak(s) or unreadable file(s) | A table: file · line · match — with every matched token MASKED (first 4 chars + `…<length>`). Close with: **do not publish until clean.** |
| `2` | gate misconfigured | Relay the script's stderr verbatim (missing/invalid pattern file, empty pattern set, over-broad `--exclude`, `--tracked-only` outside a git repo). A misconfigured gate must NEVER be reported as clean. |
| `64` | usage error | Relay the script's stderr — it names the exact problem (e.g. `path not found: <P>`, `unknown arg`) — then show the usage line from the script header. |

Masking is mandatory when relaying: the script echoes full matched lines; truncate every matched token in what you show. Never write findings to a file. Note the honest boundary: the raw script output (with unmasked matches) does pass through the terminal and session transcript before masking — when scanning for LIVE credentials (vs instance literals), treat the scan session itself as sensitive.

### Step 4 — suggest the standing setup (only when relevant)

If the run used no private pattern file (none passed, none in config), append one short note: create one OUTSIDE the repo (e.g. a sibling private folder) listing your instance literals — names, brands, internal project codes, hostnames — and wire it via `leak_scan.extra_patterns` in `rules.yaml`. Skip the note if a private file was already in play.

## Config (optional)

```yaml
leak_scan:               # defaults for /vault-audit:leak-scan; flags override
  extra_patterns: ""     # absolute path to your PRIVATE pattern file (outside any published repo)
  tracked_only: true
  exclude: '\.git/'
```

## Limits & discipline

- **Patterns are case-sensitive.** For instance literals, prefix `(?i)` — `(?i)acmecorp` catches `AcmeCorp`, `ACMECORP`, `acmecorp`.
- **A literal with regex metacharacters must be escaped** (`Acme (UK) Ltd` as a raw line matches nothing — write `Acme \(UK\) Ltd` or wrap in `\Q…\E`). The gate validates that patterns COMPILE, not that they can match.
- **Positive-control every new private pattern file:** plant one of its literals in a scratch file, run the scan, confirm exit `1`. A pattern set that has never failed a planted leak has never been proven to work.
- **Filenames are checked too** (relative to the scan root) — instance literals leak via paths, not just content.
- **Binary/UTF-16 files are skipped, visibly.** PowerShell's `>` redirect writes UTF-16 — convert such files to UTF-8 if they must be scanned.
- **`--exclude` is an unanchored regex** over the enumerated paths. Anchor it (`^\./docs/generated/`) — a bare substring like `\.git/` also drops `vendor/upstream.git/…`.
