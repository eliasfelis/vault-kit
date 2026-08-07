#!/usr/bin/env bash
# preflight.sh - report the audit-relevant state of a vault as JSON.
# Usage: preflight.sh [--repo-path DIR]      (default: current directory)
# Prints ONLY: {"is_repo":<bool>,"unmerged_count":<int>,"branches":[...]}  (exit 0 always)
#
# is_repo is the field the caller MUST read first. A vault that is not a git repo cannot
# host the isolated worktrees the audit runs in, and the run has to stop before it takes
# the lock - otherwise it dies later at worktree creation with the lock still held. Without
# this field a non-repo is indistinguishable from a clean repo: both report zero branches.
#
# is_repo means "<repo_path> is ITSELF the root of a git working tree" - NOT "somewhere under
# git control". A plain directory nested inside an unrelated repo answers yes to
# `rev-parse --git-dir`, and on that answer the caller reads the ENCLOSING repo's branches and
# then creates branches, worktrees and commits in a repository the user never pointed at.
# So: resolve `rev-parse --show-toplevel` and compare its realpath to the realpath of
# <repo_path>. Different (nested) or no answer at all (not a repo, or a bare repo with no
# working tree) -> false.
set -uo pipefail

repo_path="$(pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-path) [ $# -ge 2 ] || { echo "ERROR: --repo-path needs a value" >&2; exit 64; }; repo_path="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

not_a_repo() { printf '{"is_repo":false,"unmerged_count":0,"branches":[]}\n'; exit 0; }

[ -d "$repo_path" ] || not_a_repo
toplevel="$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null)" || not_a_repo
[ -n "$toplevel" ] || not_a_repo
# `cd … && pwd -P` IS the realpath here: it resolves symlinks and, on Windows, normalises the
# two spellings git and the shell use for one path (C:/x vs /c/x). Comparing the raw strings
# would report a false mismatch at the real repo root.
real_path="$(cd "$repo_path" 2>/dev/null && pwd -P)" || not_a_repo
real_top="$(cd "$toplevel" 2>/dev/null && pwd -P)"   || not_a_repo
[ -n "$real_path" ] && [ -n "$real_top" ]            || not_a_repo
[ "$real_path" = "$real_top" ]                       || not_a_repo

# Newline-delimited list of branches not merged into HEAD (strip leading * + markers/space).
unmerged="$(git -C "$repo_path" branch --no-merged HEAD 2>/dev/null | sed 's/^[*+ ]*//;s/[[:space:]]*$//')"

count=0
json=""
while IFS= read -r b; do
  [ -z "$b" ] && continue
  case "$b" in
    linter/*|judge/*) ;;     # keep
    *) continue ;;
  esac
  if printf '%s\n' "$unmerged" | grep -qxF "$b"; then
    count=$(( count + 1 ))
    if [ -z "$json" ]; then json="\"$b\""; else json="$json,\"$b\""; fi
  fi
done < <(git -C "$repo_path" branch --list 'linter/*' 'judge/*' 2>/dev/null | sed 's/^[*+ ]*//;s/[[:space:]]*$//')

printf '{"is_repo":true,"unmerged_count":%d,"branches":[%s]}\n' "$count" "$json"
