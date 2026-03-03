# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
