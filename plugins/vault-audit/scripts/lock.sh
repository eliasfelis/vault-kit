#!/usr/bin/env bash
# lock.sh - single-lockfile concurrency guard for /vault-audit.
# Usage: lock.sh <acquire|release|force-release> [--lock-dir DIR] [--max-age-min N] [--vault-path P]
# acquire: exit 0 (acquired) / 1 (busy) / 64 (bad usage or unwritable lock).
# release: exit 0 (released) / 3 (REFUSED - the lock is held for a different --vault-path) /
#          64 (bad usage). A mismatch is not a warning: deleting a lock taken by a run in
#          ANOTHER vault unprotects that live run, and the caller that passed the wrong path
#          is exactly the caller that will not notice a line on stderr. The lockfile is left
#          in place; force-release is the deliberate escape hatch.
# force-release: exit 0 (deletes the lock, mismatch or not - use it when you KNOW the owning
#          run is dead) / 64 (bad usage).
#
# WHAT THIS LOCK ACTUALLY IS: a TIMER, not a liveness check. The PID recorded in the lockfile
# belongs to this script's own shell, which exits milliseconds later - so it is provenance
# ("who took the lock"), never proof that a run is still going. The lock therefore holds for
# --max-age-min and is then reclaimable, which has one honest consequence: a run that lasts
# LONGER than max-age can be entered by a second run. Raise --max-age-min if your runs are
# long, and use force-release when you know a run died. No pretence of process liveness.
#
# The lock dir is a plain directory path: the CALLER makes it per-vault (pass --lock-dir with
# a path derived from the vault's absolute path). A single shared default would let an audit
# of vault A block an unrelated audit of vault B.
set -uo pipefail

action="${1:-}"
[ $# -gt 0 ] && shift

lock_dir="${TMPDIR:-/tmp}/vault-audit"
max_age_min=60
vault_path=""

while [ $# -gt 0 ]; do
  case "$1" in
    --lock-dir)    [ $# -ge 2 ] || { echo "ERROR: --lock-dir needs a value" >&2; exit 64; }; lock_dir="$2"; shift 2 ;;
    --max-age-min) [ $# -ge 2 ] || { echo "ERROR: --max-age-min needs a value" >&2; exit 64; }; max_age_min="$2"; shift 2 ;;
    --vault-path)  [ $# -ge 2 ] || { echo "ERROR: --vault-path needs a value" >&2; exit 64; }; vault_path="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

# Validate max_age_min is a non-negative integer. Otherwise the arithmetic below crashes
# under set -u and the crash rc (1) would be indistinguishable from the 'busy' exit code.
case "$max_age_min" in ''|*[!0-9]*) echo "ERROR: --max-age-min must be a non-negative integer" >&2; exit 64 ;; esac
# ...and bound it. `max_age_min * 60` on a huge value overflows the shell's signed 64-bit
# arithmetic and WRAPS NEGATIVE, at which point `age_sec -le max_age_sec` is false for every
# lock and the guard is silently off - an absurd number disables the lock instead of making
# it eternal. Check the digit LENGTH first: the comparison itself would overflow on a
# 20-digit value and could quietly report "not too big". 525600 min = 1 year, far beyond any
# audit run, and 525600*60 is nowhere near the 64-bit ceiling.
if [ "${#max_age_min}" -gt 7 ] || [ "$max_age_min" -gt 525600 ]; then
  echo "ERROR: --max-age-min out of range: $max_age_min (allowed 0..525600 minutes = 1 year)" >&2
  exit 64
fi
# Canonicalize to base-10 now that it is validated (digits-only, in range). `$(( ))` reads a
# leading zero as OCTAL, so a value like 08 would crash the arithmetic below (rc 1, which reads
# as 'busy') and 0525600 would silently shrink the timer. `10#` forces base-10 once, here.
max_age_min=$(( 10#$max_age_min ))

lock_file="$lock_dir/.running"
mkdir -p "$lock_dir" || { echo "ERROR: cannot create lock dir: $lock_dir" >&2; exit 64; }

case "$action" in
  acquire)
    if [ -f "$lock_file" ]; then
      # Fields: <pid> <epoch> <vault-path>. The path may contain spaces, so it must be the
      # LAST field and read into the last variable, which absorbs the remainder.
      read -r owner_pid lock_epoch owner_vault < "$lock_file" || true
      # Harden against a corrupt/partial lockfile: a non-numeric field must not crash
      # arithmetic under set -u. Bad pid -> "" (unknown); bad epoch -> 0 (ancient) so a
      # corrupt lock is reclaimed, never wedged forever.
      case "${owner_pid:-}" in ''|*[!0-9]*) owner_pid="" ;; esac
      case "${lock_epoch:-}" in ''|*[!0-9]*) lock_epoch=0 ;; esac
      owner_vault="${owner_vault:-}"
      now_epoch="$(date -u +%s)"
      age_sec=$(( now_epoch - lock_epoch ))
      max_age_sec=$(( max_age_min * 60 ))
      # Busy iff the lock is younger than max-age. Deliberately NOT a `kill -0` liveness
      # test: the recorded PID is this script's own shell from the earlier `acquire` call
      # and is always dead by now, so a liveness test reads as false 100% of the time
      # while looking authoritative — and a recycled PID would read as true and wedge the
      # lock forever. The age IS the semantics; see the header.
      if [ "$age_sec" -le "$max_age_sec" ]; then
        disp_age=$(( age_sec / 60 )); [ "$disp_age" -lt 0 ] && disp_age=0
        echo "Lock busy: taken ${disp_age} min ago by PID ${owner_pid:-?}${owner_vault:+ for $owner_vault}; expires after ${max_age_min} min"
        exit 1
      fi
      # else: older than max-age -> reclaim
    fi
    # Fail loud if the lock can't be written — never print 'acquired' on a failed write
    # (that would let two runs both believe they hold the lock). fail-soft != silent.
    if ! printf '%s %s %s\n' "$$" "$(date -u +%s)" "$vault_path" > "$lock_file"; then
      echo "ERROR: cannot write lock file: $lock_file" >&2
      exit 64
    fi
    echo "Lock acquired by PID $$${vault_path:+ for $vault_path}"
    exit 0
    ;;
  release|force-release)
    # Releasing a lock taken for a DIFFERENT vault means the lock dir was not derived
    # per-vault (or the caller passed the wrong one). Either way the lock in front of us
    # belongs to somebody else's run, and deleting it leaves that run unprotected in the real
    # vault. A warning on stderr does not stop that: the caller already demonstrated it is
    # not tracking which vault it is releasing. REFUSE, keep the lockfile, exit non-zero.
    # force-release stays the escape hatch for a run you know is dead.
    if [ -n "$vault_path" ] && [ -f "$lock_file" ]; then
      read -r _pid _epoch owner_vault < "$lock_file" || true
      owner_vault="${owner_vault:-}"
      if [ -n "$owner_vault" ] && [ "$owner_vault" != "$vault_path" ]; then
        if [ "$action" = "release" ]; then
          echo "ERROR: refusing to release a lock held for a different vault: $owner_vault (you passed $vault_path)" >&2
          echo "The lock is left in place. Re-run release with the owning --vault-path, or use force-release if that run is dead." >&2
          exit 3
        fi
        echo "WARNING: force-releasing a lock held for a different vault: $owner_vault (you passed $vault_path)" >&2
      fi
    fi
    rm -f "$lock_file"
    exit 0
    ;;
  *)
    echo "Usage: lock.sh <acquire|release|force-release> [--lock-dir DIR] [--max-age-min N] [--vault-path P]" >&2
    exit 64
    ;;
esac
