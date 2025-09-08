# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-08

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
