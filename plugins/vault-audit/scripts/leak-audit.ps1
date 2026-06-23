# leak-audit.ps1 - Publish gate: fails if any file under -Path matches a forbidden pattern.
# Usage: leak-audit.ps1 -Path <file-or-dir> [-PatternFile <path>] [-ExtraPatterns <path>] [-Exclude <regex>]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$PatternFile = "",
    [string]$ExtraPatterns = "",
    [string]$Exclude = '\\\.git\\'
)

if ($PatternFile -eq "") {
    $PatternFile = Join-Path $PSScriptRoot "leak-patterns.txt"
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Load-Patterns {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) {
        Write-Error "Pattern file not found: $FilePath"
        exit 2
    }
    Get-Content $FilePath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }
}

# Load patterns
$patterns = [System.Collections.Generic.List[string]]::new()
foreach ($p in (Load-Patterns $PatternFile)) { $patterns.Add($p) }

if ($ExtraPatterns -ne "") {
    if (-not (Test-Path $ExtraPatterns)) {
        [Console]::Error.WriteLine("ExtraPatterns file not found: $ExtraPatterns")
        exit 2
    }
    foreach ($p in (Load-Patterns $ExtraPatterns)) { $patterns.Add($p) }
}

if ($patterns.Count -eq 0) {
    Write-Host "OK: no patterns loaded - nothing to check"
    exit 0
}

# Enumerate files
$extensions = @("*.md","*.json","*.yaml","*.yml","*.ps1","*.txt","*.js","*.ts")

if (Test-Path $Path -PathType Leaf) {
    $files = @(Get-Item $Path)
} else {
    $files = $extensions | ForEach-Object { Get-ChildItem -Path $Path -Recurse -Filter $_ -ErrorAction SilentlyContinue } |
             Where-Object { $_.FullName -notmatch $Exclude }
}

# Scan
$hits = [System.Collections.Generic.List[string]]::new()

foreach ($file in $files) {
    if ($file.FullName -match $Exclude) { continue }
    $matches = Select-String -Path $file.FullName -Pattern $patterns -AllMatches -ErrorAction SilentlyContinue
    foreach ($m in $matches) {
        $hits.Add("$($m.Path):$($m.LineNumber): $($m.Line.Trim())")
    }
}

if ($hits.Count -gt 0) {
    foreach ($h in $hits) { Write-Host "LEAK $h" }
    Write-Host "FAIL: $($hits.Count) leak(s)"
    exit 1
} else {
    Write-Host "OK: no leaks"
    exit 0
}
