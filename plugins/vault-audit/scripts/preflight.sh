#!/usr/bin/env bash
# preflight.sh - list unmerged linter/* and judge/* branches as JSON.
# Usage: preflight.sh [--repo-path DIR]
# Prints ONLY: {"unmerged_count":<int>,"branches":[...]}  (exit 0 always; fail-soft if not a repo)
set -uo pipefail

repo_path="$(pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-path) repo_path="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
  printf '{"unmerged_count":0,"branches":[]}\n'
  exit 0
fi

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

printf '{"unmerged_count":%d,"branches":[%s]}\n' "$count" "$json"
