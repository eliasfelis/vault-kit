#!/usr/bin/env bash
# lock.sh - single-lockfile concurrency guard for /vault-audit.
# Usage: lock.sh <acquire|release|force-release> [--lock-dir DIR] [--max-age-min N]
# acquire: exit 0 (acquired) / 1 (busy, with stale-PID reclaim). release/force-release: exit 0.
set -uo pipefail

action="${1:-}"
[ $# -gt 0 ] && shift

lock_dir="${TMPDIR:-/tmp}/vault-audit"
max_age_min=60

while [ $# -gt 0 ]; do
  case "$1" in
    --lock-dir)    lock_dir="$2"; shift 2 ;;
    --max-age-min) max_age_min="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

lock_file="$lock_dir/.running"
mkdir -p "$lock_dir"

case "$action" in
  acquire)
    if [ -f "$lock_file" ]; then
      read -r owner_pid lock_epoch < "$lock_file" || true
      now_epoch="$(date -u +%s)"
      age_sec=$(( now_epoch - ${lock_epoch:-0} ))
      max_age_sec=$(( max_age_min * 60 ))
      alive=false
      if [ -n "${owner_pid:-}" ] && kill -0 "$owner_pid" 2>/dev/null; then
        alive=true
      fi
      # Busy iff owning PID alive OR lock younger than max-age (guards rapid sequential calls).
      if [ "$alive" = true ] || [ "$age_sec" -le "$max_age_sec" ]; then
        echo "Lock busy: PID ${owner_pid:-?}, age $(( age_sec / 60 )) min"
        exit 1
      fi
      # else: stale (PID gone AND older than max-age) -> reclaim
    fi
    printf '%s %s\n' "$$" "$(date -u +%s)" > "$lock_file"
    echo "Lock acquired by PID $$"
    exit 0
    ;;
  release|force-release)
    rm -f "$lock_file"
    exit 0
    ;;
  *)
    echo "Usage: lock.sh <acquire|release|force-release> [--lock-dir DIR] [--max-age-min N]" >&2
    exit 64
    ;;
esac
