#!/usr/bin/env bash
# lock.sh - single-lockfile concurrency guard for /vault-audit.
# Usage: lock.sh <acquire|release|force-release> [--lock-dir DIR] [--max-age-min N]
# acquire: exit 0 (acquired) / 1 (busy, with stale reclaim) / 64 (bad usage or unwritable lock).
# release / force-release: exit 0.
set -uo pipefail

action="${1:-}"
[ $# -gt 0 ] && shift

lock_dir="${TMPDIR:-/tmp}/vault-audit"
max_age_min=60

while [ $# -gt 0 ]; do
  case "$1" in
    --lock-dir)    [ $# -ge 2 ] || { echo "ERROR: --lock-dir needs a value" >&2; exit 64; }; lock_dir="$2"; shift 2 ;;
    --max-age-min) [ $# -ge 2 ] || { echo "ERROR: --max-age-min needs a value" >&2; exit 64; }; max_age_min="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

# Validate max_age_min is a non-negative integer. Otherwise the arithmetic below crashes
# under set -u and the crash rc (1) would be indistinguishable from the 'busy' exit code.
case "$max_age_min" in ''|*[!0-9]*) echo "ERROR: --max-age-min must be a non-negative integer" >&2; exit 64 ;; esac

lock_file="$lock_dir/.running"
mkdir -p "$lock_dir"

case "$action" in
  acquire)
    if [ -f "$lock_file" ]; then
      read -r owner_pid lock_epoch < "$lock_file" || true
      # Harden against a corrupt/partial lockfile: a non-numeric field must not crash
      # arithmetic under set -u. Bad pid -> "" (dead); bad epoch -> 0 (ancient) so a
      # corrupt lock is reclaimed, never wedged forever.
      case "${owner_pid:-}" in ''|*[!0-9]*) owner_pid="" ;; esac
      case "${lock_epoch:-}" in ''|*[!0-9]*) lock_epoch=0 ;; esac
      now_epoch="$(date -u +%s)"
      age_sec=$(( now_epoch - lock_epoch ))
      max_age_sec=$(( max_age_min * 60 ))
      alive=false
      # PID 0 is never a real owner: `kill -0 0` signals the caller's process group and
      # always succeeds, which would wedge the lock forever — treat 0 (and only >0 passes) as dead.
      if [ -n "$owner_pid" ] && [ "$owner_pid" -gt 0 ] 2>/dev/null && kill -0 "$owner_pid" 2>/dev/null; then
        alive=true
      fi
      # Busy iff owning PID alive OR lock younger than max-age (guards rapid sequential calls).
      if [ "$alive" = true ] || [ "$age_sec" -le "$max_age_sec" ]; then
        disp_age=$(( age_sec / 60 )); [ "$disp_age" -lt 0 ] && disp_age=0
        echo "Lock busy: PID ${owner_pid:-?}, age ${disp_age} min"
        exit 1
      fi
      # else: stale (PID gone/garbage/0 AND older than max-age) -> reclaim
    fi
    # Fail loud if the lock can't be written — never print 'acquired' on a failed write
    # (that would let two runs both believe they hold the lock). fail-soft != silent.
    if ! printf '%s %s\n' "$$" "$(date -u +%s)" > "$lock_file"; then
      echo "ERROR: cannot write lock file: $lock_file" >&2
      exit 64
    fi
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
