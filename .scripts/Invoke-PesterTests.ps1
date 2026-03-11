<#
.SYNOPSIS
    Ensures Pester v5 is available and runs all project Pester tests.

.DESCRIPTION
    Checks whether Pester v5 or later is installed. If not, installs it for the
    current user. Then runs all project test files and blocks execution (exit 1)
    when any test fails.

    Intended to be called from the .githooks/pre-commit hook so test failures are
    caught locally before changes reach CI.

.PARAMETER NoBlock
    Report-only mode: diagnostics are printed but the script exits with 0 even when
    tests fail. Mirrors the same flag used in Test-StagedPowerShell.ps1.
#>
[CmdletBinding()]
param(
    [switch]$NoBlock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Ensure Pester v5+ ────────────────────────────────────────────────────────
$existing = Get-Module -ListAvailable -Name Pester |
Sort-Object -Property Version -Descending |
Select-Object -First 1

if (-not $existing -or $existing.Version -lt [Version]'5.0.0') {
    Write-Host 'Pester v5 not found – installing for current user...'
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module -Name Pester -MinimumVersion 5.0.0 -Force

$loaded = Get-Module -Name Pester
Write-Host "Using Pester version: $($loaded.Version)"

# ── Resolve test files relative to repo root ─────────────────────────────────
$repositoryRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repositoryRoot) {
    throw 'Could not determine git repository root.'
}

$testFiles = @(
    Join-Path -Path $repositoryRoot -ChildPath 'Install-ADSK.Tests.ps1'
    Join-Path -Path $repositoryRoot -ChildPath 'CIDEON.AutodeskDeployment.Tests.ps1'
) | Where-Object { Test-Path -LiteralPath $_ }

if (-not $testFiles) {
    Write-Host 'No Pester test files found. Skipping Pester check.'
    exit 0
}

# ── Run tests ─────────────────────────────────────────────────────────────────
$result = Invoke-Pester -Path $testFiles -Output Minimal -PassThru

if ($result.FailedCount -gt 0) {
    if ($NoBlock) {
        Write-Host "Report-only mode: $($result.FailedCount) test(s) failed but not blocking commit."
        exit 0
    }

    throw "Commit blocked: $($result.FailedCount) Pester test(s) failed."
}

Write-Host "All $($result.PassedCount) Pester test(s) passed."
