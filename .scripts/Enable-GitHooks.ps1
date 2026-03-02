[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repositoryRoot) {
    throw 'Could not determine git repository root.'
}

Push-Location -Path $repositoryRoot
try {
    git config core.hooksPath .githooks
    Write-Host 'Configured git hooks path to .githooks for this repository.'
    Write-Host 'You can verify it with: git config --get core.hooksPath'
}
finally {
    Pop-Location
}