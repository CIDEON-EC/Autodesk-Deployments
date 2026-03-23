# Test Matrix

## Scope

This matrix tracks implementation status for tests around:

- Install-ADSK.ps1 as orchestration and security shell
- CIDEON.AutodeskDeployment.psm1 as the primary test surface

Legend:

- [ ] not implemented
- [x] implemented
- [~] partially implemented

## Install-ADSK.ps1

| Area | Scenario | Status |
| --- | --- | --- |
| Loader | Remote module download succeeds | [x] |
| Loader | Remote loader fails without local fallback | [x] |
| Loader | Remote loader falls back to local signed module | [x] |
| Loader | Invalid remote signature aborts import | [x] |
| Loader | Missing release asset aborts import | [x] |
| Dispatch | Install mode triggers expected functions | [x] |
| Dispatch | Update mode triggers expected functions | [x] |
| Dispatch | Uninstall mode triggers expected functions | [x] |
| Input | .wim suffix is normalized | [x] |

## CIDEON.AutodeskDeployment.psm1

| Function | Happy Path | Error Path | WhatIf / ShouldProcess | Status |
| --- | --- | --- | --- | --- |
| Set-InstallContext | [x] | [ ] | n/a | [~] |
| Invoke-DeploymentWorkflow | [~] | [x] | [ ] | [~] |
| Write-InstallLog | [x] | [x] | [x] | [x] |
| Write-InstallProgress | [x] | [~] | n/a | [~] |
| Update-WIMInspectionCache | [x] | [x] | n/a | [x] |
| Get-CachedFiles | [x] | [x] | n/a | [x] |
| Install-Update | [~] | [ ] | [~] | [~] |
| Install-AutodeskDeployment | [~] | [x] | [ ] | [~] |
| Uninstall-AutodeskDeployment | [x] | [x] | [ ] | [~] |
| Set-AutodeskDeployment | [ ] | [ ] | [ ] | [ ] |
| Install-CideonTool | [x] | [~] | [x] | [~] |
| Disable-VaultExtension | [x] | [ ] | [x] | [~] |
| Get-RealUserName | [x] | [ ] | n/a | [~] |
| Get-UserSID | [ ] | [ ] | n/a | [ ] |
| Set-InventorProjectFile | [ ] | [ ] | [ ] | [ ] |
| Remove-UserSystemVariable | [ ] | [ ] | [ ] | [ ] |
| Copy-Local | [x] | [x] | [ ] | [~] |
| Uninstall-Program | [x] | [x] | [ ] | [~] |
| Get-InstalledProgram | [x] | [x] | n/a | [x] |
| Set-CIDEONLanguageVariable | [x] | [ ] | [x] | [~] |
| Set-CIDEONVariable | [x] | [ ] | [x] | [~] |
| Rename-RegistryInstallationPath | [ ] | [ ] | [ ] | [ ] |
| Copy-WIM | [x] | [ ] | [ ] | [~] |
| Mount-WIM | [x] | [x] | [x] | [x] |
| Dismount-WIM | [x] | [x] | [x] | [x] |
| Register-WIMDismountTask | [x] | [ ] | [x] | [~] |
| Set-AutodeskUpdate | [x] | [x] | [x] | [x] |
| Get-AppLogError | [x] | [x] | n/a | [x] |

## Current implementation order

1. P0 functions
2. Install-ADSK loader negative-path hardening
3. P1 function groups
4. CI gate expansion