<#
.SYNOPSIS
Lock-file management for /vault-audit orchestrator.

.DESCRIPTION
Single-lockfile mechanism. A JSON file under -LockDir records the owning PID
and acquire time. Supports acquire (with stale-PID reclaim), release, and
force-release.

.PARAMETER Action
acquire | release | force-release

.PARAMETER LockDir
Directory in which to place the lock file.
Default: "$env:TEMP\vault-audit"  (created if absent).

.PARAMETER MaxAgeMinutes
Minutes after which a lock is considered stale (even if the PID is gone).
A lock is only reclaimable when BOTH conditions hold: owning PID is not
running AND age > MaxAgeMinutes. This prevents a just-written lock from
being overwritten in rapid sequential calls (e.g. orchestrator acquire →
pre-check acquire on the same lockfile).
Default: 60.

.OUTPUTS
acquire   -> short status string to stdout; exit 0 (got it) or exit 1 (busy).
release   -> exit 0 always.
force-release -> exit 0 always.
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('acquire','release','force-release')]
    [string]$Action,

    [string]$LockDir = "$env:TEMP\vault-audit",

    [int]$MaxAgeMinutes = 60
)

$ErrorActionPreference = 'Stop'
$LockPath = Join-Path $LockDir '.running'

# Ensure lock directory exists
if (-not (Test-Path $LockDir)) {
    New-Item -ItemType Directory -Path $LockDir -Force | Out-Null
}

function Get-LockData {
    if (-not (Test-Path $LockPath)) { return $null }
    try {
        $raw = Get-Content $LockPath -Raw -ErrorAction Stop
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Is-PidRunning([int]$TargetPid) {
    # Returns $true if a process with the given PID is currently running.
    try {
        $proc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
        return ($null -ne $proc)
    } catch {
        return $false
    }
}

function Get-AgeMinutes($data) {
    if (-not $data -or -not $data.timestamp) { return [double]::PositiveInfinity }
    try {
        return ((Get-Date) - [DateTime]::Parse($data.timestamp)).TotalMinutes
    } catch {
        return [double]::PositiveInfinity
    }
}

function Remove-Lock {
    if (Test-Path $LockPath) {
        Remove-Item $LockPath -Force
    }
}

$existing = Get-LockData

switch ($Action) {
    'acquire' {
        if ($existing) {
            $ownerPid = [int]$existing.pid
            $ageMin   = [math]::Round((Get-AgeMinutes $existing), 1)
            $isAlive  = Is-PidRunning $ownerPid

            # A lock is busy if: PID is alive, OR the lock is recent (< MaxAgeMinutes).
            # This guards against rapid sequential calls where the writer's process
            # has already exited but the lock is still fresh.
            $isFresh = ($ageMin -le $MaxAgeMinutes)

            if ($isAlive -or $isFresh) {
                # Busy: live process holds it, or lock is too recent to reclaim
                Write-Host "Lock busy: PID $ownerPid, age ${ageMin} min"
                exit 1
            }
            # Stale lock: PID is gone AND older than MaxAgeMinutes — reclaimable
        }

        $data = [PSCustomObject]@{
            pid       = $PID
            timestamp = (Get-Date).ToString('o')
        }
        $data | ConvertTo-Json -Compress | Set-Content -Path $LockPath -Encoding ascii
        Write-Host "Lock acquired by PID $PID"
        exit 0
    }

    'release' {
        Remove-Lock
        exit 0
    }

    'force-release' {
        Remove-Lock
        exit 0
    }
}
