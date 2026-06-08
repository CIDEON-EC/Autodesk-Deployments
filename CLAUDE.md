# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

PowerShell tooling for deploying Autodesk products (Inventor, AutoCAD, Vault) via WIM files in enterprise environments. The solution has two layers:

- **`Install-ADSK.ps1`** — the customer-facing installer script. Downloads and validates `CIDEON.AutodeskDeployment.psm1` from a GitHub Release, verifies the Authenticode signature against a pinned thumbprint (`53D03841EC43C1C545F56919F9A6AEF0C7D2E783`), then calls `Invoke-DeploymentWorkflow -ModeHandler { ... }`. Customers customize the `switch ($Mode)` block inside the ModeHandler.
- **`CIDEON.AutodeskDeployment.psm1`** — the signed module containing all helper/orchestration functions. Not present in this repo; it lives in GitHub Releases. Tests mock it.
- **`Copy-Local.ps1`** — thin wrapper using the same signed module loader for post-install file copying.

## Commands

### Run tests
```powershell
# Run all Pester tests (requires Pester v5 — script installs it if missing)
.\.scripts\Invoke-PesterTests.ps1

# Run tests without blocking on failure (report-only)
.\.scripts\Invoke-PesterTests.ps1 -NoBlock

# Run a specific test file directly
Invoke-Pester -Path .\Install-ADSK.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\CIDEON.AutodeskDeployment.Tests.ps1 -Output Detailed
```

### Lint
```powershell
# Analyze all scripts using project settings (Error severity only, excluding PSAvoidUsingWriteHost)
Get-ChildItem -Recurse -Filter *.ps1 |
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings .\.scripts\PSScriptAnalyzerSettings.psd1 }
```

### Enable git hooks (PSScriptAnalyzer + Pester run on pre-commit)
```powershell
.\.scripts\Enable-GitHooks.ps1
```

## Architecture

### Module loading pattern
`Install-ADSK.ps1` and `Copy-Local.ps1` both follow the same loader pattern:
1. Fetch the module + certificate from a GitHub Release asset (latest, or pinned via `-ModuleVersionPin`)
2. Validate the downloaded certificate thumbprint against the allowlist
3. Validate the module's Authenticode signature with that certificate
4. Fall back to a local copy of the module in the script directory if remote loading fails

If the code-signing certificate is rotated, update the pinned thumbprint allowlist in `Install-ADSK.ps1` and `Copy-Local.ps1` before trusting the new release.

### WIM workflow
1. WIM is copied locally (or mounted directly with `-NoDownload`)
2. WIM is mounted to a temp path
3. ModeHandler ScriptBlock runs (Install / Update / Uninstall)
4. WIM is dismounted; a scheduled task is registered as a safety net for dismount on failure

### Test files
- `Install-ADSK.Tests.ps1` — tests the loader security (signature validation, fallback, missing assets) and mode dispatch
- `CIDEON.AutodeskDeployment.Tests.ps1` — tests module functions; see `TEST-MATRIX.md` for coverage status

## PowerShell Conventions

Follow `.github/instructions/powershell.instructions.md`:
- `[CmdletBinding()]` on all functions; `SupportsShouldProcess` for any function that modifies state
- Use `$PSCmdlet.WriteError()` / `$PSCmdlet.ThrowTerminatingError()` with proper `ErrorRecord` objects — not bare `Write-Error` / `throw`
- PascalCase for parameters and public variables; camelCase for private variables
- Full cmdlet names only (no aliases like `gci`, `?`, `%`)
- Comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.OUTPUTS`) for all public functions

Follow `.github/instructions/powershell-pester-5.instructions.md` for tests:
- All code inside Pester blocks (`BeforeAll`, `Describe`, `Context`, `It`)
- Import tested scripts with `BeforeAll { . $PSScriptRoot/Script.ps1 }`
- Use `Should -Invoke` (not `Assert-MockCalled`) for mock verification

## Documentation

When changing public function signatures or script parameters, update:
1. `readme.md` — parameter table and usage examples
2. `CHANGELOG.md` — under the appropriate section (`Added`, `Changed`, `Fixed`); prefix breaking changes with **BREAKING**
3. Comment-based help inside the function itself
