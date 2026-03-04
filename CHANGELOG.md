# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.2] - 2026-03-04
### Changed
- Updated readme
- Logfile from Install-ADSK renamed to Install-ADSK-20xx.log
- `Install-AutodeskDeployment` now enforces `LoggingSettings` in selected deployment XML files before installer start (`-Files` selection): `Logging=true` and `Path=<LocalFolder>\\Install-ADSK-Deplyoment-<WIM>.log`

### Fixed
- Improved `WhatIf` output in `Install-CideonTool` for `CIDEON.VAULT.TOOLBOX*.msi` by adding explicit `ADDLOCAL` feature context in the `ShouldProcess` action text (also for service packs)
- Adjusted MSI update logging in `Install-Update` to write to a dedicated per-file log (`<mainlog>_<msi-name>.log`), keeping the main script log independent

## [1.1.1] - 2026-03-04
### Changed
- Refactored `Install-CideonTool` for a simpler, direct execution flow with inline argument construction and direct `ShouldProcess`-guarded install calls
- Updated `Install-CideonTool` file processing order so installers with `servicepack` in the file name are executed last
- Refactored `Install-Update` to inline installer command resolution and remove unnecessary indirection
- Replaced duplicated WhatIf cache fallback branches with shared `Get-CachedFiles` helper usage in `Install-Update`, `Install-CideonTool`, and `Copy-Local`
- Simplified source resolution logic by removing redundant duplicated path-access branches in update/tool/local copy flows
- Removed temporary WhatIf override helper and switched inspection-only operations to explicit `-WhatIf:$false` where needed

### Fixed
- Improved `WhatIf` output in `Install-CideonTool` for `CIDEON.VAULT.TOOLBOX*.msi` by adding explicit `ADDLOCAL` feature context in the `ShouldProcess` action text (also for service packs)

### Removed
- Removed `Resolve-WhatIfSourceItem`
- Removed `Invoke-WithoutWhatIf`
- Removed `Get-CideonInstallArgumentString`
- Removed `Get-UpdateInstallSpec`

## [1.1.0] - 2026-03-03
### Added
- Full WhatIf/Dry-Run mode support for all functions
- SupportsShouldProcess attribute to all relevant functions
- WhatIf/-Confirm parameter documentation

### Changed
- Improved Write-InstallLog to display only log message in WhatIf mode (without timestamp)
- All path checks in Get-WIM, Mount-WIM, Set-AutodeskDeployment, Install-Update, Install-CideonTool, Copy-Local, Disable-VaultExtension, and Uninstall-AutodeskDeployment now skip in WhatIf mode to avoid errors on non-existent paths
- Dismount-WIM optimized to work in WhatIf mode without requiring elevated privileges
- ShouldProcess calls now show more meaningful output in WhatIf mode
- Install-CideonTool now includes the effective argument string in ShouldProcess action text (WhatIf/Confirm output)
- Simplified INSTALL.bat sample script with dynamic path resolution - now automatically finds Install-ADSK.ps1 from parent directory
- Enhanced MSI installation in Install-Update function: Now uses msiexec.exe with proper forward-slash syntax instead of direct MSI execution, includes comprehensive logging via /l*v parameter, and implements robust exit-code validation
- Refactored WhatIf handling to reduce duplicate code paths: shared helper functions now resolve source items (path vs inspected WIM cache) and compute installer arguments
- Simplified Get-WIM inspection flow with centralized temporary WhatIf override helper and reduced inspection log noise
- Unified Dismount-WIM into a single execution path for WhatIf and non-WhatIf modes

### Fixed
- Fixed WhatIf mode errors caused by attempting to access non-existent mount paths
- Fixed elevated privileges requirement errors in Dismount-WIM during WhatIf mode
- Resolved file system errors when running with -WhatIf parameter
- Fixed MSI installation failures: Corrected invalid argument syntax (-qn -norestart to /i /qn /norestart), replaced unreliable Wait-Process with proper -Wait parameter, and added proper error handling with exit code validation
- Fixed Get-RealUserName to correctly identify normal user in WhatIf mode: Temporarily disables WhatIfPreference during CIM operations to ensure proper user detection for both local and domain admins

## [1.0.1] - 2025-09-09
### Changed
- Removed old powershell scripts

## [1.0.0] - 2025-08-01

### Added
- Initial release of Autodesk Deployment Tools
- Install-ADSK.ps1 - Main installation script with WIM file automation
- Copy-Local.ps1 - Script for copying local configuration files
- Uninstall.ps1 - Uninstallation script
- Sample batch files for common scenarios
- Comprehensive README with documentation
- Support for Autodesk product installation/uninstallation
- Support for Cideon Tools installation
- WIM file mounting and management
- Logging functionality
- Registry configuration
- Environment variable setup

### Features
- Automated WIM file downloading and mounting
- Support for multiple installation modes (Install, Update, Uninstall)
- Cideon Vault Toolbox integration
- Language pack management
- Update installation
- Local file copying with user profile handling
- Comprehensive error handling and logging
- Registry path correction for repair scenarios

### Functions Available
- 22 PowerShell functions for various deployment tasks
- WIM management (Mount, Dismount, Get)
- Software installation/uninstallation
- Registry operations
- User and system configuration
- File operations and copying

[1.0.0]: https://github.com/slydlake/Autodesk-Deployment/releases/tag/v1.0.0
