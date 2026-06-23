<#
.SYNOPSIS
Pre-flight check for /vault-audit orchestrator.

.DESCRIPTION
Lists local branches matching linter/* or judge/* that are not yet merged
into the current branch. Used by the orchestrator to warn about leftover audit
branches before dispatching a new run.

.PARAMETER RepoPath
Path to the git repository to inspect.
Default: current working directory.

.OUTPUTS
Prints ONLY a single JSON object to stdout:
  { "unmerged_count": <int>, "branches": [ "<name>", ... ] }

If the path is not a git repo, prints { "unmerged_count": 0, "branches": [] }
and exits 0 (fail-soft).
#>

param(
    [string]$RepoPath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# Validate that the path is a git repository; fail-soft if not.
$gitCheck = & git -C $RepoPath rev-parse --git-dir 2>&1
if ($LASTEXITCODE -ne 0) {
    [PSCustomObject]@{
        unmerged_count = 0
        branches       = @()
    } | ConvertTo-Json -Compress
    exit 0
}

# Collect all local linter/* and judge/* branches.
$linterRaw  = & git -C $RepoPath branch --list 'linter/*'  2>$null
$judgeRaw = & git -C $RepoPath branch --list 'judge/*' 2>$null

$allBranches = @()
foreach ($line in (@($linterRaw) + @($judgeRaw))) {
    if ($line) {
        $name = ($line -replace '^\*?\s+', '').Trim()
        if ($name) { $allBranches += $name }
    }
}

if ($allBranches.Count -eq 0) {
    [PSCustomObject]@{
        unmerged_count = 0
        branches       = @()
    } | ConvertTo-Json -Compress
    exit 0
}

# Get branches not yet merged into the current branch.
$unmergedRaw = & git -C $RepoPath branch --no-merged HEAD 2>$null
$unmergedSet = @{}
foreach ($line in $unmergedRaw) {
    if ($line) {
        $name = ($line -replace '^\*?\s+', '').Trim()
        if ($name) { $unmergedSet[$name] = $true }
    }
}

$unmerged = @($allBranches | Where-Object { $unmergedSet.ContainsKey($_) })

[PSCustomObject]@{
    unmerged_count = $unmerged.Count
    branches       = @($unmerged)
} | ConvertTo-Json -Compress
