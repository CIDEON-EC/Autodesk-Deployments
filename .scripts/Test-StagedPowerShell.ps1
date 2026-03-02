[CmdletBinding()]
param(
    [string]$Path,
    [switch]$NoBlock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repositoryRoot) {
    throw 'Could not determine git repository root.'
}

$settingsPath = Join-Path -Path $repositoryRoot -ChildPath '.scripts/PSScriptAnalyzerSettings.psd1'
if (-not (Test-Path -LiteralPath $settingsPath)) {
    throw "PSScriptAnalyzer settings file not found: $settingsPath"
}

$pathsToAnalyze = @()
if ($Path) {
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path -Path $repositoryRoot -ChildPath $Path
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Specified file not found: $resolvedPath"
    }

    if ($resolvedPath -notmatch '\.(ps1|psm1|psd1)$') {
        throw "Specified file is not a PowerShell file: $resolvedPath"
    }

    $pathsToAnalyze += $resolvedPath
}
else {
    $stagedFiles = @(git diff --cached --name-only --diff-filter=ACMR)
    $powerShellFiles = @(
        $stagedFiles |
            Where-Object { $_ -match '\.(ps1|psm1|psd1)$' } |
            Sort-Object -Unique
    )

    if (-not $powerShellFiles) {
        Write-Host 'No staged PowerShell files found. Skipping PSScriptAnalyzer check.'
        exit 0
    }

    foreach ($relativePath in $powerShellFiles) {
        $absolutePath = Join-Path -Path $repositoryRoot -ChildPath $relativePath
        if (Test-Path -LiteralPath $absolutePath) {
            $pathsToAnalyze += $absolutePath
        }
    }
}

if (-not $pathsToAnalyze) {
    Write-Host 'No staged PowerShell files exist on disk. Skipping PSScriptAnalyzer check.'
    exit 0
}

$diagnostics = @()
foreach ($pathToAnalyze in $pathsToAnalyze) {
    $fileDiagnostics = Invoke-ScriptAnalyzer -Path $pathToAnalyze -Settings $settingsPath
    if ($fileDiagnostics) {
        $diagnostics += $fileDiagnostics
    }
}

if ($diagnostics) {
    Write-Host 'PSScriptAnalyzer found issues:'
    $diagnostics |
        Sort-Object -Property Severity, ScriptName, Line |
        ForEach-Object {
            $severity = if ($_.Severity -eq 'Error') { 'error' } else { 'warning' }
            $line = if ($_.Line) { $_.Line } else { 1 }
            $column = if ($_.Column) { $_.Column } else { 1 }
            Write-Host ('{0}:{1}:{2}: {3} {4} {5}' -f $_.ScriptName, $line, $column, $severity, $_.RuleName, $_.Message)
        }

    if ($NoBlock) {
        Write-Host 'Report-only mode active: not blocking execution despite diagnostics.'
        exit 0
    }

    throw 'Commit blocked because PSScriptAnalyzer reported issues.'
}

Write-Host 'PSScriptAnalyzer check passed.'