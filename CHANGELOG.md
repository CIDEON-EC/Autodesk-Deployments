# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [3.1.0] - 2026-10-20
### Added
- `Set-AutodeskDeployment -Remove` also removes `<Application>` entries of `setup.xml` (name pattern, namespace independent), so a product can be installed without Vault Data Standard: `Set-AutodeskDeployment -Remove 'Vault Data Standard'` (example in `Install-ADSK.ps1`). It logs a note when a pattern matches nothing.
### Changed
- `Set-AutodeskDeployment -xmlFileName` is now a list and defaults to `setup_ext.xml` and `setup.xml`; a file missing in a product folder is skipped (previously a missing file caused an error).
- `Install-AutodeskDeployment` logs a failure instead of `Autodesk Products installed` when no config file was found.
- `Mount-DeploymentImage` no longer requires the config files (`Collection.xml`) and does not stop the workflow when they are missing, so images without an Autodesk deployment can be installed. The config files are only checked by `Install-AutodeskDeployment` (logs the missing file and skips it).

## [3.0.0] - 2026-10-20
### Security
- `Copy-Local.ps1` now pins the release certificate and the module signer to the same thumbprint allowlist as `Install-ADSK.ps1` (previously it only checked for `Status -eq Valid`, so any certificate from the release could be added to `CurrentUser\TrustedPublisher` and any validly signed module was imported). The downloaded certificate is checked before it is added to the store; the local fallback module is checked the same way. If the certificate cannot be added to the store, a `NotTrusted`/`UnknownError` chain is accepted only when the signer thumbprint is pinned; `HashMismatch` is always rejected.
### Added
- `New-DeploymentImage.ps1` / `New-DeploymentImage.cmd`: creates a `.vhdx` deployment image from a deployment folder (drag the folder onto the `.cmd`; replaces the 7-Zip WIM step). Uses `diskpart`, no Hyper-V module needed, starts itself elevated. Included in the release package and as release assets.
- Images can be `.vhdx` or `.wim`; the extension is detected (`<Image>.vhdx` is preferred over `<Image>.wim`). A VHDX is attached with `Mount-DiskImage` and uses its drive letter instead of a mount folder (`mountPath` and the config file paths are set to the drive root after mounting), so all other functions keep working.
- Pester tests for the `Copy-Local.ps1` module loader (`Copy-Local.Tests.ps1`), included in `.scripts/Invoke-PesterTests.ps1`
### Changed
- **BREAKING (compatible via aliases)**: parameter `-WIM` of `Install-ADSK.ps1` is now `-Image` (`-WIM` still works as alias, also with an extension); `Copy-WIM`, `Mount-WIM`, `Dismount-WIM` are now `Copy-DeploymentImage`, `Mount-DeploymentImage`, `Dismount-DeploymentImage` (old names are exported aliases); the install context variables `$WIM` and `$wimFile` are now `$Image` and `$imageFile`. `Register-WIMDismountTask` and `Update-WIMInspectionCache` keep their names.
- `-NoDownload` is not supported for `.vhdx` images (a VHDX cannot be attached from a network share); `Copy-DeploymentImage` throws a clear error.
- A VHDX is mounted read-write, so changes the installer makes in the image (e.g. the rewritten `Collection.xml`) persist in the local copy.
- A VHDX that is still attached from an aborted run is dismounted before it is mounted again (no scheduled cleanup task is needed for a VHDX; an attachment does not survive a reboot).
- Release process: a release is now triggered by changing the `VERSION` file on `main` instead of pushing a `v*` tag; the workflow creates the tag. Pre-release versions can also be released from `release/**` branches without merging to `main`. Removed the tag tasks from `.vscode/tasks.json` (see `.github/workflows/README.md`).
- Pester tests moved to `tests/`; `.scripts/Invoke-PesterTests.ps1` runs every `tests/*.Tests.ps1`.
- `Install-AutodeskDeployment`: waits for the started `Installer.exe` process and logs its exit code and duration; a non-zero exit code is logged as an error instead of always reporting success.
- `Install-AutodeskDeployment`: shows the path of the Autodesk installer log in a second line below "Starting Autodesk deployment", so a long-running installation can be followed in the log.
- The note that the certificate could not be added to the certificate stores (`Install-ADSK.ps1`, `Copy-Local.ps1`) is now a short English `Write-Host` note instead of a warning with the localized OS error text.
- `samples/INSTALL.cmd`: builds the script path from the image path and lists the optional parameters as comments.
- `Copy-Local.ps1` is now stored as UTF-8 with BOM instead of UTF-16 LE so Git can diff it
- `Set-AutodeskUpdate` writes the ODIS setting to the logged-on user's hive (`HKEY_USERS\<SID>`) like `Set-InventorProjectFile`, instead of `HKCU` of the elevated or SYSTEM account. Falls back to `HKCU` if the SID cannot be resolved or the hive is not loaded.
- `Get-AppLogError` lets the event log service filter for `MsiInstaller` errors (`-FilterHashtable`) instead of loading the whole Application log
- CI: new `test` job (PSScriptAnalyzer and Pester on `windows-latest`) for every push and pull request; the release job only runs when it passes
- `.gitignore`: ignore `*.pem`, `.env*`, credential JSON files, `_LOG/`, `.claude/settings.local.json` and `*.code-workspace`
### Fixed
- `Install-ADSK.ps1` with Autodesk ODIS 2.24+ (Autodesk 2027): `Installer.exe` refused every file inside a mounted WIM (`file missing or not a regular file`, exit code 453 after < 1 s, no deployment log), because files in a mounted WIM are reparse points (tag `0x80000008`). For these versions use a `.vhdx` image (see `New-DeploymentImage.ps1`): its files are regular files. `.wim` images remain supported for older versions.
- `Dismount-WIM`: `-Purge` of `Install-ADSK.ps1` is now honoured when the ModeHandler calls a plain `Dismount-WIM` (the WIM was dismounted there, so the final purge in `Invoke-DeploymentWorkflow` found nothing mounted and never deleted the local WIM). Network paths and `-NoDownload` are still never purged.
- `Install-AutodeskDeployment`: the deployment log is now named `Install-ADSK-Deployment-<WIM>.log` (typo `Deplyoment` fixed, as documented in the readme).
- `Copy-WIM`/`Mount-WIM`: a failed WIM copy, a failed mount or a missing config file now stops the workflow (`HardAbort`). Previously the ModeHandler `trap` continued and ran installation, tools, updates and `Copy-Local` against an empty mount folder. Works for existing customised `Install-ADSK.ps1` scripts without changes.
- `Copy-WIM` copies the WIM again when the existing local file differs from the source in size or modification time (previously any local file with the same name was reused)
- `Uninstall-Program` uninstalls MSI products with `msiexec /x {ProductCode}`. Previously an `UninstallString` with `/I` was run as is, which starts a silent repair instead of an uninstall.
- `Get-RealUserName` returns a single value when the user cannot be determined (previously it could return two values, which broke `Get-UserSID`)
- `Set-AutodeskDeployment` honours `-WhatIf`/`-Confirm` for `-Remove` and saves the XML only when something was removed (previously packages were removed and saved even when the removal was declined)
- `Install-AutodeskDeployment` quotes the deployment config path (paths with spaces failed)
- `Set-AutodeskUpdate` throws a terminating error when none of `-Enable`/`-ShowOnly`/`-Disable` is given
## [2.1.1] - 2026-10-13
### Fixed
- `Install-ADSK.ps1`: the untrusted-chain fallback now also accepts the signature status `UnknownError`, which Windows reports for the self-signed code-signing certificate when the root is not trusted (previously only `NotTrusted`, so module loading still failed). The thumbprint pin is still enforced; `HashMismatch` and `NotSigned` are still rejected.
## [2.1.0] - 2026-10-13
### Added
- Release workflow now publishes `Install-ADSK.ps1` as a separate release asset for direct download
### Fixed
- Release workflow version replacement no longer swallows the line break after the version line; `Install-ADSK.ps1` now carries a `ModuleVersion:` header that is set from the release tag
### Changed
- `Install-ADSK.ps1`: if the code-signing certificate cannot be added to the certificate stores (access denied, e.g. locked by GPO or EDR), the installer now continues with a warning and accepts a module signature with status `NotTrusted`, as long as the signer thumbprint matches the pinned allowlist. A tampered module (`HashMismatch`) is still rejected.
## [2.0.2] - 2026-09-08
### Fixed
- Fixed `Update-WIMInspectionCache` and `Install-CIDEONTool` never returning any files: `Get-ChildItem -Exclude ... -File` always returns an empty result when `-Path` has no trailing wildcard, because `-Exclude` only filters the contents of a container when the path expands to it (e.g. `Path\*`) — both calls now pass `Path\*` so files are correctly enumerated and excluded
## [2.0.1] - 2026-09-08
### Fixed
- Fixed `Copy-Local` throwing `PropertyNotFoundException` ("Count" property not found) during `Install` mode when the `Local` folder is missing or contains no subfolders — `Get-ChildItem` result is now wrapped in `@()` so `$SourceFolder` is always a real array instead of `$null` under `Set-StrictMode -Version 3.0`
### Security
- Added network path protection in `Dismount-WIM`: when `-Purge` is used, the function now detects network paths (e.g. `\\server\share\file.wim`) and throws a terminating error instead of deleting — this prevents accidental loss of the source WIM on a central deployment share
- Added warning log in `Copy-WIM` when `-NoDownload` is active, alerting the user that the WIM will be mounted from the server path
## [2.0.0] - 2026-06-08
### Added
- Complete new introduction of using a PowerShell module, instead of one script [#5](https://github.com/CIDEON-EC/Autodesk-Depyloments/issues/5)
- New Pester unit tests covering key functions: `Mount-WIM`, `Dismount-WIM`, `Install-Update`, `Install-AutodeskDeployment`, `Get-CachedFiles` and `Set-AutodeskUpdate` (risk‑based P0/P1 matrix)
- CI workflow extended to execute PSScriptAnalyzer and the unit‑test suite on pull requests and pushes to `main` in addition to tag‑based releases
- Added optional `-ModuleVersionPin` parameter to `Install-ADSK.ps1` to pin online module download to a specific release version — now supports pre-release versions (e.g. `2.0.0-beta.1`) in addition to stable semver
- Added CI code-signing step for `CIDEON.AutodeskDeployment.psm1` in tag-based release workflow
- Added trap to avoid terminating the script for strange errors [#10](https://github.com/CIDEON-EC/Autodesk-Depyloments/issues/10)
- Added compact console progress output [#11](https://github.com/CIDEON-EC/Autodesk-Depyloments/issues/11)
- Progress output will suppressed when `-Quiet` is used in `Install-ADSK.ps1`.
- Added Pester regression tests for rejecting unpinned release certificates and modules signed by an unexpected signer certificate in `Install-ADSK.ps1`
- Unblock file in Install-Updates if necessary #15
- CIDEON.AutodeskDeployment.psm1: New Functions added Get-AutodeskProcesses, Test-AutodeskProcessesRunning, Stop-AutodeskProcess #18
- Install-ADSK.ps1: Added pre check for running Autodesk applications (Inventor, AutoCAD, Vault) before start. If application is running, the installation will aborted #18
- Install-ADSK.ps1: Added new parameter -ForceQuit to force quit running Autodesk applications (Inventor, AutoCAD, Vault) #18


### Changed
- Renamed `Get-WIM` to `Copy-WIM` — clearer intent, the function copies the WIM from the network share to the local machine
- Replaced interactive `Read-Host` version prompt with a terminating `ErrorRecord` (`InvalidVersionFormat`) — scripts are now fully non-interactive per PowerShell best practices
- Removed `foreach` loop over multiple WIM files; the module now discovers exactly one WIM matching the `-WIM` parameter and throws `WimFileNotFound` if zero or more than one match
- Install-AutodeskDeployment accepts optional explicit config, log-folder and deployment-name parameters so deployment execution is less dependent on ambient module state.
- Refactored `Copy-Local.ps1` into a thin wrapper that loads `CIDEON.AutodeskDeployment.psm1` with the same signed module bootstrap and optional `-ModuleVersionPin` behavior as `Install-ADSK.ps1`.

### Fixed
- Fixed `-WIM` parameter to accept value with an `.wim` suffix [#8](https://github.com/CIDEON-EC/Autodesk-Depyloments/issues/8)
- `Install-Update` now guards against `$null` file lists by coercing results to an array; prevents runtime errors during WhatIf/empty-cache scenarios (covered by new unit test)
- Fixed calling folders as installation [#9](https://github.com/CIDEON-EC/Autodesk-Depyloments/issues/9)
- Install-AutodeskDeployment now creates missing LoggingSettings XML nodes correctly under module strict mode before saving the deployment config, and falls back to Image/Collection.xml if no explicit config list is present.
- Install-Update: Exclude pattern fixed, always exclude folders. Removed unnecessary VBA folder #16
- Install-ADSK.ps1: Using Logging only inside of Invoke-DeploymentWorkflow
- Install-ADSK.ps1: Check of running Autodesk programms hard end inside trap
- Install-ADSK.ps1: Throw inside Invoke-DeploymentWorkflow not hanging anymore

### Documentation
- Added or completed comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`) for all module functions: `Set-InstallContext`, `Get-RealUserName`, `Get-UserSID`, `Set-InventorProjectFile`

### Security
- `Add-CertificateToStoreIfMissing` now removes stale certificates with the same subject from `LocalMachine\TrustedPublisher` and `LocalMachine\Root` after installing a new certificate, preventing accumulation of outdated trust anchors
- `Install-ADSK.ps1` now validates the downloaded release certificate against a pinned thumbprint allowlist before importing it into the machine certificate stores and also pins the module signer thumbprint during remote and local fallback module validation


## [1.1.2] - 2026-03-04
### Changed
- Updated readme
- Logfile from Install-ADSK renamed to Install-ADSK-20xx.log
- `Install-AutodeskDeployment` now enforces `LoggingSettings` in selected deployment XML files before installer start (`-Files` selection): `Logging=true` and `Path=<LocalFolder>\\Install-ADSK-Deployment-<WIM>.log`

### Fixed
- Improved `WhatIf` output in `Install-CideonTool` for `CIDEON.VAULT.TOOLBOX*.msi` by adding explicit `ADDLOCAL` feature context in the `ShouldProcess` action text (also for service packs)
- Adjusted MSI update logging in `Install-Update` to write to a dedicated per-file log (`<mainlog>_<msi-name>.log`), keeping the main script log independent
- Install-Update, Install-CideonTool and other functions now get correct items (only files or only directories)

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
