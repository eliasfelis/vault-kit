---
type: audit-finding
source: vault-audit
title: "Declared folders in the constitution must exist on disk."
url: ""
date_captured: 2026-01-01
status: inbox
value: med
effort: med
confidence: high
decision_reason: ""
origin: judge
finding_id: declared-folders-vs-actual
severity: warning
related_files: ["CLAUDE.md"]
---
**Severity:** warning
**Rule:** Declared folders in the constitution must exist on disk.
**Evidence:** CLAUDE.md lists `archive/` but no such directory exists.
**Suggested action:** Create archive/ or drop it from the declared folder list.
**Related files:** CLAUDE.md
