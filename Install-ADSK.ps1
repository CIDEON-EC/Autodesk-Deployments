<#
.SYNOPSIS
    Automation of using the wim file localy and start the installation/uninstallation

.NOTES
    Author: Timon Först
    Version: 2.0.0

.DESCRIPTION
    Automation of downloading a wim file to a temporary local folder. After
	that the wim file will mount in the local folder. You can choose if you
    want to install or uninstall a product. At the end, the wim file will
	dismount and the wim file will be deleted.

    Folder structure inside of the wim file:
    ├──  PDC_20XX                   (name of the Autodesk deployment)
    │   ├── image                   (default from Autodesk deployment)
    │   │   ├── AMECH_PP_20XX_de-DE
    │   │   |    ├── ...
    │   │   |    ├── setup.xml      (contains product to install)
    │   │   |    └── setup_ext.xml  (contains updates and language packs)
    │   │   ├── INVPROSA_20XX_de-DE
    │   │   ├── ...
    │   │   ├── Collection.xml
    │   │   ├── Inventor_only.xml   (modified version of Collection.xml)
    │   │   └── ...
    │   ├── Updates                 (additionally updates to install)
    │   │   ├── Update_Inventor_20XX.X.exe
    │   │   └── Update_AutoCAD_20XX.X.exe
    │   ├── Cideon                  (Cideon Tools)
    │   │   ├── CIDEON.VAULT.TOOLBOX.SETUP_XXXX.X.X.XXXXX.msi
    │   │   ├── CIDEON.Inventor.Toolbox_x64_XXXX.X.X.XXXXX.msi
    │   │   └── CDN_DataStandards_Setup_XXXX.X.X.XXXXX.msi
    │   └── Local                   (local configuration files)
    │       ├── ProgramData
    │       └── Users
    │           ├── Public          (Public user folder)
    │           │   └── Documents
    │           │       └── CIDEON
    │           │           └── LicenseFiles
    │           │               └── 20XX
    │           └── USERNAME        (local user folder, will be renamed to the actual username)
    │               └── AppData
    │                    └── Roaming
    │                        └── Autodesk
    └── WIM-handler.ps1


.PARAMETER Path
    The path to the WIM file. Default is script location.
	You don't need to set it, when the WIM file is in the same folder as the script.
.PARAMETER WIM
    Name of the WIM file you want to use.
.PARAMETER LocalFolder
    Local folder where the wim file should be downloaded and mapped.
	Default is C:\Temp
    You have to set this, if you have localy only in specified folder install rights.
.PARAMETER Mode
    Available: Install, Uninstall, Update
	Mode that you want to execute. Start the batchfile  inside the wim file.
.PARAMETER Files
    Array of XML filenames WITHOUT extension, default "Collection"
    Files that should be used for the installation. Missing config files are skipped
    (logged but do not stop the install). If no config files exist, the installation
    proceeds without Autodesk Deployment.
.PARAMETER Version
    Optional. The Software Version for installing cideon tools and logging.
    It will be extracted from the WIM name, if a 4 digit number is found.
.PARAMETER Logging
    Enable log file. The log file will be created in the local folder.
.PARAMETER NoDownload
    Disable Copying of the WIM file to the local folder. The WIM file will be mounted from the server.
.PARAMETER Purge
    Deletes the WIM file after finishing the script. NOT COMBINED with NoDownload!
.PARAMETER ModuleVersionPin
    Optional. Pins the online module download to a specific GitHub Release version (e.g. 1.2.0).
    If omitted, the module and certificate are downloaded from the latest GitHub Release.
.PARAMETER WhatIf
    Shows what would happen if the script runs. No actual changes are made (Dry Run mode).
.PARAMETER Confirm
    Prompts for confirmation before executing each action.
.PARAMETER Quiet
    Suppresses output messages.
.PARAMETER ForceQuit
    Kill processes that block installation silently without confirmation prompts. Use with caution. (e.g. Inventor, AutoCAD or Vault)
.PARAMETER SkipSignatureCheck
    Skips Authenticode signature validation for the local fallback module.
    For development/testing use only - do NOT use in production environments.
.EXAMPLE
cd \\SERVER\SHARE\ScriptLocation
.\Install-ADSK.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging

#When using "CMD" instead of powershell (as admin):
cd \\SERVER\SHARE\ScriptLocation
powershell.exe -ExecutionPolicy Bypass .\Install-ADSK.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging

# Pin remote module to release version 1.2.0 (default is latest release):
.\Install-ADSK.ps1 -WIM "PDC_20XX" -Mode "Install" -ModuleVersionPin "1.2.0"


#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $false, HelpMessage = 'specified location of the wim file.')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
            if (Test-Path $_ -PathType Container) {
                $true
            }
            else {
                throw "Path '$_' is not existing."
            }
        })]
    [String]$Path = $PSScriptRoot,

    [Parameter(Mandatory = $true, HelpMessage = 'specified the wim filename without extension.')]
    [ValidateNotNullOrEmpty()]
    [String]$WIM,

    [Parameter(Mandatory = $false, HelpMessage = 'Changes the default location from of the local temp folder.')]
    [ValidateNotNullOrEmpty()]
    [String]$LocalFolder = 'C:\Temp',

    [Parameter(Mandatory = $true, HelpMessage = 'Specified the installation mode: Install, Update or Uninstall')]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Install', 'Update', 'Uninstall')]
    [string]$Mode,

    [Parameter(Mandatory = $false, HelpMessage = 'The Software Version, if none is specified, it will be extracted from the WIM name.')]
    [ValidateNotNullOrEmpty()]
    [string]$Version = [regex]::Match($WIM, '\d{4}').Value,

    [Parameter(Mandatory = $false, HelpMessage = 'An array of XML filenames without extension, default <<Collection>>')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Files = @('Collection'),

    [Parameter(Mandatory = $false, HelpMessage = 'Enable log file')]
    [switch]$Logging,

    [Parameter(Mandatory = $false, HelpMessage = 'Disable Copying of the WIM file to the local folder')]
    [switch]$NoDownload,

    [Parameter(Mandatory = $false, HelpMessage = 'Deletes the WIM file after finishing the script')]
    [switch]$Purge,

    [Parameter(Mandatory = $false, HelpMessage = 'Optional: Pin remote module download to a specific release version (e.g. 1.2.0 or 2.0.0-beta.1). Default is latest release.')]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$')]
    [string]$ModuleVersionPin,

    [Parameter(Mandatory = $false, HelpMessage = 'Suppresses output messages')]
    [switch]$Quiet,

    [Parameter(Mandatory = $false, HelpMessage = 'Kill processes that block installation silently without confirmation prompts. Use with caution. (e.g. Inventor, AutoCAD or Vault)')]
    [switch]$ForceQuit,

    [Parameter(Mandatory = $false, HelpMessage = 'Skips Authenticode signature validation for the local fallback module. For development use only.')]
    [switch]$SkipSignatureCheck,

    [Parameter(Mandatory = $false, HelpMessage = 'Expected SHA-256 hash for the deployment module. When provided, the downloaded module will be verified against this hash.')]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedModuleHash,

    [Parameter(Mandatory = $false, HelpMessage = 'Expected SHA-256 hash for the code-signing certificate. When provided, the downloaded certificate will be verified against this hash.')]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedCertificateHash
)


#region Module Loader
function Test-IsElevated {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsElevated)) {
    throw 'This script must be run as administrator.'
}

if ($WIM.EndsWith('.wim', [System.StringComparison]::OrdinalIgnoreCase)) {
    $WIM = $WIM.Substring(0, $WIM.Length - 4)
}

# LOW Issue #1: Warn when module download is not pinned to a specific version
if (-not $ModuleVersionPin) {
    Write-Warning 'ModuleVersionPin is not specified. The module and certificate will be downloaded from the latest GitHub Release. For production deployments, pin to a specific version: -ModuleVersionPin "x.y.z"'
}


$ModuleName = 'CIDEON.AutodeskDeployment'
$ModuleFileName = "$ModuleName.psm1"
$CertificateFileName = 'CIDEON-CodeSigning.cer'
$RepositoryOwner = 'CIDEON-EC'
$RepositoryName = 'Autodesk-Deployments'
$RepositoryApiBaseUrl = "https://api.github.com/repos/$RepositoryOwner/$RepositoryName"
$ModuleCacheFolder = Join-Path -Path $env:ProgramData -ChildPath 'CIDEON/Autodesk-Deployments'
$ModuleLocalPath = Join-Path -Path $ModuleCacheFolder -ChildPath $ModuleFileName
$CertificateLocalPath = Join-Path -Path $ModuleCacheFolder -ChildPath $CertificateFileName
$TrustedCertificateThumbprints = @(
    '53D03841EC43C1C545F56919F9A6AEF0C7D2E783'
)

function Get-NormalizedThumbprint {
    <#
    .SYNOPSIS
        Normalizes a certificate thumbprint for allowlist comparisons.

    .PARAMETER Thumbprint
        The thumbprint to normalize.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Thumbprint
    )

    $thumbprintText = [string]$Thumbprint
    if ([string]::IsNullOrWhiteSpace($thumbprintText)) {
        throw 'Thumbprint must not be empty.'
    }

    return ($thumbprintText -replace '\s', '').ToUpperInvariant()
}

function Assert-TrustedCertificateThumbprint {
    <#
    .SYNOPSIS
        Verifies that a certificate file matches the pinned release certificate allowlist.

    .DESCRIPTION
        Loads the certificate from disk and compares its thumbprint against the
        allowlisted thumbprints embedded in the installer.

    .PARAMETER CertificatePath
        Full path to the certificate file that should be validated.

    .PARAMETER TrustedThumbprint
        One or more allowed certificate thumbprints.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CertificatePath,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TrustedThumbprint
    )

    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
    $normalizedThumbprint = Get-NormalizedThumbprint -Thumbprint $certificate.Thumbprint
    $allowedThumbprints = @($TrustedThumbprint | ForEach-Object {
            Get-NormalizedThumbprint -Thumbprint $_
        })

    if ($normalizedThumbprint -notin $allowedThumbprints) {
        throw "Downloaded certificate thumbprint '$normalizedThumbprint' is not trusted. Update the installer allowlist before trusting a new signing certificate."
    }

    return $certificate
}

function Assert-TrustedModuleSignature {
    <#
    .SYNOPSIS
        Verifies a module Authenticode signature against the pinned signer allowlist.

    .DESCRIPTION
        Ensures the signature hash is intact and that the signer certificate thumbprint
        matches the installer allowlist.

        Accepts NotTrusted in addition to Valid: the certificate is deliberately no
        longer installed into LocalMachine\Root, so a correctly signed module reports
        NotTrusted (chain not trusted) while its file hash is still verified. The
        pinned signer thumbprint check below is the actual trust decision.

        UnknownError is NOT accepted. It is a catch-all status that carries no
        guarantee the file hash was verified, so it cannot stand in for a hash check.
        NotSigned, HashMismatch and all other statuses are rejected as well.

    .PARAMETER Signature
        Result object from Get-AuthenticodeSignature.

    .PARAMETER TrustedThumbprint
        One or more allowed signer thumbprints.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Signature,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TrustedThumbprint
    )

    $acceptableStatus = @(
        [System.Management.Automation.SignatureStatus]::Valid
        [System.Management.Automation.SignatureStatus]::NotTrusted
    )
    if ($Signature.Status -notin $acceptableStatus) {
        throw "Module signature is invalid. Status: $($Signature.Status) - $($Signature.StatusMessage)"
    }

    if (-not $Signature.SignerCertificate -or [string]::IsNullOrWhiteSpace($Signature.SignerCertificate.Thumbprint)) {
        throw 'Module signature does not expose a signer certificate thumbprint.'
    }

    $normalizedThumbprint = Get-NormalizedThumbprint -Thumbprint $Signature.SignerCertificate.Thumbprint
    $allowedThumbprints = @($TrustedThumbprint | ForEach-Object {
            Get-NormalizedThumbprint -Thumbprint $_
        })

    if ($normalizedThumbprint -notin $allowedThumbprints) {
        throw "Module signer thumbprint '$normalizedThumbprint' is not trusted."
    }
}

function Get-ReleaseAssetDownloadUri {
    <#
    .SYNOPSIS
        Resolves a GitHub Release asset download URL for a specific or latest release.

    .DESCRIPTION
        Calls the GitHub Releases API and returns the browser_download_url for the requested
        asset file name. If -ReleaseVersion is omitted, the latest release is used.

    .PARAMETER AssetName
        File name of the release asset (e.g. CIDEON.AutodeskDeployment.psm1).

    .PARAMETER ReleaseVersion
        Optional semantic version without leading v (e.g. 1.2.0).

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AssetName,
        [Parameter()]
        [string]$ReleaseVersion
    )

    $releaseEndpoint = if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) {
        "$RepositoryApiBaseUrl/releases/latest"
    }
    else {
        "$RepositoryApiBaseUrl/releases/tags/v$ReleaseVersion"
    }

    $headers = @{
        Accept       = 'application/vnd.github+json'
        'User-Agent' = 'Install-ADSK'
    }

    $release = Invoke-RestMethod -Uri $releaseEndpoint -Headers $headers -Method Get -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1

    if (-not $asset) {
        $errorTarget = if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) { 'latest' } else { "v$ReleaseVersion" }
        throw "Release asset '$AssetName' not found in release '$errorTarget'."
    }

    return $asset.browser_download_url
}

function Save-RemoteFile {
    <#
    .SYNOPSIS
        Downloads a file from a remote URI to a local destination path.

    .DESCRIPTION
        Uses Invoke-WebRequest to download a file. Creates the parent directory
        if it does not already exist.

    .PARAMETER Uri
        The remote URI to download from.

    .PARAMETER DestinationPath
        The local file path where the downloaded content is saved.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $parentPath = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -Path $parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force -WhatIf:$false | Out-Null
    }

    # Harden on every run, not only on creation: a folder left over from an earlier
    # run - or pre-created by a non-admin - would otherwise keep its inherited ACL
    # and defeat the TOCTOU protection entirely.
    Protect-ModuleCacheFolder -FolderPath $parentPath

    Invoke-WebRequest -Uri $Uri -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
}

function Protect-ModuleCacheFolder {
    <#
    .SYNOPSIS
        Restricts the module cache folder ACL to SYSTEM and Administrators.

    .DESCRIPTION
        Disables ACL inheritance and grants full control only to SYSTEM and
        BUILTIN\Administrators so that non-admin users cannot swap the cached
        module between signature validation and import (TOCTOU mitigation).

    .PARAMETER FolderPath
        The folder whose ACL should be hardened.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    try {
        $acl = Get-Acl -Path $FolderPath
        $acl.SetAccessRuleProtection($true, $false)

        $systemSid = [System.Security.Principal.SecurityIdentifier]::new(
            [System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $adminsSid = [System.Security.Principal.SecurityIdentifier]::new(
            [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

        foreach ($sid in @($systemSid, $adminsSid)) {
            $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $sid,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($rule)
        }

        Set-Acl -Path $FolderPath -AclObject $acl
    }
    catch {
        Write-Warning "Could not harden ACL on '$FolderPath': $($_.Exception.Message)"
    }
}

function Add-CertificateToStoreIfMissing {
    <#
    .SYNOPSIS
        Adds a code-signing certificate to the LocalMachine TrustedPublisher store if not already present.

    .DESCRIPTION
        Loads an X.509 certificate from the specified file and adds it to the
        LocalMachine\TrustedPublisher store so PowerShell accepts scripts from this publisher.

        After installing the new certificate, stale certificates with the same
        subject but a different thumbprint are removed from the store, preventing
        accumulation of outdated trust anchors.

        Note: The certificate is NOT added to LocalMachine\Root. Thumbprint pinning
        in the loader provides authenticity verification without fleet-wide root
        trust installation.

        Requires the script to run as administrator.

    .PARAMETER CertificatePath
        The full path to the .cer certificate file.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CertificatePath
    )

    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)

    # TrustedPublisher: Import-Certificate works without any dialog
    $tpPath = 'Cert:\LocalMachine\TrustedPublisher'
    $alreadyInTP = Get-ChildItem -Path $tpPath | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if (-not $alreadyInTP) {
        Import-Certificate -FilePath $CertificatePath -CertStoreLocation $tpPath -WhatIf:$false | Out-Null
    }
    # Remove stale TrustedPublisher certificates with the same subject
    Get-ChildItem -Path $tpPath |
    Where-Object { $_.Subject -eq $certificate.Subject -and $_.Thumbprint -ne $certificate.Thumbprint } |
    ForEach-Object { Remove-Item -Path "$tpPath\$($_.Thumbprint)" -Force }
}

function Import-RemoteSignedDeploymentModule {
    <#
    .SYNOPSIS
        Downloads the deployment module and certificate from GitHub, validates the Authenticode signature and imports the module.

    .DESCRIPTION
        Fetches the CIDEON code-signing certificate and the CIDEON.AutodeskDeployment
        module from the configured GitHub raw URL, adds the certificate to the
        TrustedPublisher store, verifies the module's Authenticode signature and
        imports the module into the current session.

        The module cache folder ACL is restricted to SYSTEM and Administrators when
        created (see Protect-ModuleCacheFolder) so that non-admin users cannot swap
        the cached module between signature validation and import.

        Throws a terminating error if the signature is invalid.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param()

    $moduleRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $ModuleFileName -ReleaseVersion $ModuleVersionPin
    $certificateRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $CertificateFileName -ReleaseVersion $ModuleVersionPin

    Save-RemoteFile -Uri $certificateRemoteUri -DestinationPath $CertificateLocalPath

    # SHA-256 hash verification for downloaded assets (MITM protection).
    # The certificate hash MUST be verified before the certificate is imported into
    # the machine store - otherwise a tampered certificate would already be trusted
    # by the time the mismatch is detected.
    if ($ExpectedCertificateHash) {
        $actualCertHash = (Get-FileHash -Path $CertificateLocalPath -Algorithm SHA256).Hash
        if ($actualCertHash -ne $ExpectedCertificateHash) {
            throw "Certificate hash mismatch. Expected: $ExpectedCertificateHash, Actual: $actualCertHash"
        }
    }

    Assert-TrustedCertificateThumbprint -CertificatePath $CertificateLocalPath -TrustedThumbprint $TrustedCertificateThumbprints | Out-Null
    Add-CertificateToStoreIfMissing -CertificatePath $CertificateLocalPath

    Save-RemoteFile -Uri $moduleRemoteUri -DestinationPath $ModuleLocalPath

    if ($ExpectedModuleHash) {
        $actualModuleHash = (Get-FileHash -Path $ModuleLocalPath -Algorithm SHA256).Hash
        if ($actualModuleHash -ne $ExpectedModuleHash) {
            throw "Module hash mismatch. Expected: $ExpectedModuleHash, Actual: $actualModuleHash"
        }
    }

    $signature = Get-AuthenticodeSignature -FilePath $ModuleLocalPath
    Assert-TrustedModuleSignature -Signature $signature -TrustedThumbprint $TrustedCertificateThumbprints

    Import-Module -Name $ModuleLocalPath -Force -ErrorAction Stop
}

try {
    if ($SkipSignatureCheck) {
        $fallbackLocalModule = Join-Path -Path $PSScriptRoot -ChildPath $ModuleFileName
        if (-not (Test-Path -Path $fallbackLocalModule)) {
            throw "Local fallback module not found at '$fallbackLocalModule'."
        }
        Write-Warning '-SkipSignatureCheck is set: loading unsigned local module. Do not use in production.'
        Import-Module -Name $fallbackLocalModule -Force -ErrorAction Stop
    }
    else {
        Import-RemoteSignedDeploymentModule
    }
}
catch {
    if ($SkipSignatureCheck) { throw }

    $remoteError = $_.Exception.Message

    $fallbackLocalModule = Join-Path -Path $PSScriptRoot -ChildPath $ModuleFileName
    if (-not (Test-Path -Path $fallbackLocalModule)) {
        throw "Remote module loading failed: $remoteError - no local fallback found at '$fallbackLocalModule'."
    }

    $fallbackSignature = Get-AuthenticodeSignature -FilePath $fallbackLocalModule
    try {
        Assert-TrustedModuleSignature -Signature $fallbackSignature -TrustedThumbprint $TrustedCertificateThumbprints
    }
    catch {
        throw "Remote module loading failed: $remoteError - fallback module at '$fallbackLocalModule' is also unusable ($($_.Exception.Message))."
    }

    Import-Module -Name $fallbackLocalModule -Force -ErrorAction Stop
}

Set-InstallContext -Context @{
    Path        = $Path
    WIM         = $WIM
    LocalFolder = $LocalFolder
    Mode        = $Mode
    Version     = $Version
    Files       = $Files
    Logging     = $Logging
    NoDownload  = $NoDownload
    Purge       = $Purge
}



#endregion

#region Code

Invoke-DeploymentWorkflow -ModeHandler {
    # Global error handling for each mode. If an error occurs, it will be logged and the script will continue with the next step.
    trap {
        Write-InstallLog -Text "Error in '$Mode' Mode: $($_.Exception.Message)" -Fail
        if ($_.Exception.Data['HardAbort']) {
            throw $_
        }
        Write-InstallLog -Text 'Installation will continue without the last step' -Info
        continue
    }

    # Check for running Autodesk processes before starting installation. If ForceQuit is enabled, attempt to stop them silently.
    if ($ForceQuit) {
        Write-InstallLog -Text 'ForceQuit is enabled, so the script will attempt to terminate any running Autodesk processes without confirmation.' -Info
        $success = Stop-AutodeskProcess -Force
        if (-not $success) {
            Write-InstallLog -Text 'Failed to stop all Autodesk processes. Installation may be blocked.' -Fail
            $hardError = [System.Exception]::new('Failed to stop all Autodesk processes. Installation may be blocked.')
            $hardError.Data['HardAbort'] = $true
            throw $hardError
        }
    }
    # if processes are still running, log and throw an error
    elseif (Test-AutodeskProcessesRunning) {
        Write-InstallLog -Text 'Autodesk processes are running. Please close all Autodesk applications before running the script or start the script with -ForceQuit to terminate them.' -Fail
        $hardError = [System.Exception]::new('Autodesk processes are running. Please close all Autodesk applications before running the script or start the script with -ForceQuit to terminate them.')
        $hardError.Data['HardAbort'] = $true
        throw $hardError
    }



    #################################
    ###### Main Workflow Logic ######
    ##################################
    switch ($Mode) {
        'Install' {
            # WIM copy and mount are prerequisites for every following step -
            # their failure must hard-abort instead of continuing via the trap.
            try {
                # Copy WIM file to local path
                Copy-WIM

                # Mount WIM (in WhatIf mode: read-only inspection mount)
                Mount-WIM
            }
            catch {
                $_.Exception.Data['HardAbort'] = $true
                throw $_
            }

            # install autodesk software
            Install-AutodeskDeployment

            # set Autodesk Update mode
            Set-AutodeskUpdate -Disable

            #updates
            Install-Update

            # install CIDEON Tools
            Install-CIDEONTool -VaultToolboxStandard -VaultToolboxPro -VaultToolboxObserver
            # disable standard vault toolbox jobs and events
            Disable-VaultExtension
            # copy local configuration files (e.g. license files)
            Copy-Local

            # set custom Inventor Project File
            Set-InventorProjectFile
            # alternative: Set-InventorProjectFile -File "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj"
            # Set-InventorProjectFile -File "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj"

            # Dismount wim and delete local wim file
            # Dismount-WIM -purge
            Dismount-WIM
        }
        'Update' {
            # mount wim from network - prerequisite, hard-abort on failure
            try {
                Mount-WIM
            }
            catch {
                $_.Exception.Data['HardAbort'] = $true
                throw $_
            }

            # install updates from wim
            Install-Update
            # copy local configuration files (e.g. license files)
            Copy-Local

            # Dismount wim from network
            Dismount-WIM
        }
        'Uninstall' {
            # Uninstall all CIDEON Tools with windows Installer
            Uninstall-Program -Publisher 'CIDEON'
            # Uninstall Autodesk Products with windows Installer
            Uninstall-Program -DisplayName 'Autodesk AutoCAD Mechanical 2022 - English' -Publisher 'Autodesk' -FilterOperator '-eq'
            Uninstall-Program -DisplayName 'Autodesk Inventor Professional 2022' -Publisher 'Autodesk' -FilterOperator '-eq'
            Uninstall-Program -DisplayName 'Autodesk Vault Professional 2022 (Client)' -Publisher 'Autodesk' -FilterOperator '-eq'
        }
    }
}

#endregion
