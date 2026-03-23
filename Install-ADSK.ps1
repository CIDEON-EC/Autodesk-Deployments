<#
.SYNOPSIS
    Automation of using the wim file localy and start the installation/uninstallation

.NOTES
    Author: Timon Först
    Version: 1.1.1

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
    Array of XML filenames WIHOUT extension, default "Collection"
    Files that should be used for the installation.
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
.PARAMETER SkipSignatureCheck
    Skips Authenticode signature validation for the local fallback module.
    For development/testing use only - do NOT use in production environments.
.EXAMPLE
cd \\SERVER\SHARE\ScriptLocation
.\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging

#When using "CMD" instead of powershell (as admin):
cd \\SERVER\SHARE\ScriptLocation
powershell.exe -ExecutionPolicy Bypass .\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging

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

    [Parameter(Mandatory = $false, HelpMessage = 'Skips Authenticode signature validation for the local fallback module. For development use only.')]
    [switch]$SkipSignatureCheck
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


$ModuleName = 'CIDEON.AutodeskDeployment'
$ModuleFileName = "$ModuleName.psm1"
$CertificateFileName = 'CIDEON-CodeSigning.cer'
$RepositoryOwner = 'CIDEON-EC'
$RepositoryName = 'Autodesk-Deployments'
$RepositoryApiBaseUrl = "https://api.github.com/repos/$RepositoryOwner/$RepositoryName"
$ModuleCacheFolder = Join-Path -Path $env:ProgramData -ChildPath 'CIDEON/Autodesk-Deployments'
$ModuleLocalPath = Join-Path -Path $ModuleCacheFolder -ChildPath $ModuleFileName
$CertificateLocalPath = Join-Path -Path $ModuleCacheFolder -ChildPath $CertificateFileName

# Example for pinned remote module release:
# .\Install-ADSK.ps1 -WIM "PDC_2026" -Mode "Install" -ModuleVersionPin "1.2.0"

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

    if (-not (Test-Path -Path (Split-Path -Path $DestinationPath -Parent))) {
        New-Item -Path (Split-Path -Path $DestinationPath -Parent) -ItemType Directory -Force -WhatIf:$false | Out-Null
    }

    Invoke-WebRequest -Uri $Uri -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
}

function Add-CertificateToStoreIfMissing {
    <#
    .SYNOPSIS
        Adds a code-signing certificate to the LocalMachine TrustedPublisher and Root stores if not already present.

    .DESCRIPTION
        Loads an X.509 certificate from the specified file and adds it to both
        the LocalMachine\TrustedPublisher store (so PowerShell accepts scripts
        from this publisher) and the LocalMachine\Root store (so Authenticode
        chain validation succeeds).

        After installing the new certificate, stale certificates with the same
        subject but a different thumbprint are removed from both stores, preventing
        accumulation of outdated trust anchors.

        TrustedPublisher: uses Import-Certificate (PKI module) and Remove-Item.
        Root: uses certutil.exe -addstore/-delstore, which are the only methods
        that add/remove root CA certificates silently without an interactive dialog.

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

    # Root: certutil.exe -addstore/-delstore is the only silent option when elevated
    $rootPath = 'Cert:\LocalMachine\Root'
    $alreadyInRoot = Get-ChildItem -Path $rootPath | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if (-not $alreadyInRoot) {
        Invoke-Certutil -AddStore 'Root' -FilePath $CertificatePath
    }
    # Remove stale Root certificates with the same subject
    Get-ChildItem -Path $rootPath |
        Where-Object { $_.Subject -eq $certificate.Subject -and $_.Thumbprint -ne $certificate.Thumbprint } |
        ForEach-Object { Invoke-CertutilDelete -StoreName 'Root' -Thumbprint $_.Thumbprint }
}

function Invoke-Certutil {
    <#
    .SYNOPSIS
        Thin wrapper around certutil.exe -addstore for testability.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AddStore,
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $result = & certutil.exe -addstore -f $AddStore $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "certutil failed to add certificate to '$AddStore' store (exit $LASTEXITCODE): $result"
    }
}

function Invoke-CertutilDelete {
    <#
    .SYNOPSIS
        Thin wrapper around certutil.exe -delstore for testability.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StoreName,
        [Parameter(Mandatory)]
        [string]$Thumbprint
    )

    $result = & certutil.exe -delstore $StoreName $Thumbprint 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "certutil failed to remove certificate '$Thumbprint' from '$StoreName' store (exit $LASTEXITCODE): $result"
    }
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

        Throws a terminating error if the signature is invalid.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param()

    $moduleRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $ModuleFileName -ReleaseVersion $ModuleVersionPin
    $certificateRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $CertificateFileName -ReleaseVersion $ModuleVersionPin

    Save-RemoteFile -Uri $certificateRemoteUri -DestinationPath $CertificateLocalPath
    Add-CertificateToStoreIfMissing -CertificatePath $CertificateLocalPath

    Save-RemoteFile -Uri $moduleRemoteUri -DestinationPath $ModuleLocalPath

    $signature = Get-AuthenticodeSignature -FilePath $ModuleLocalPath
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Module signature is invalid. Status: $($signature.Status) - $($signature.StatusMessage)"
    }

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
    if ($fallbackSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Remote module loading failed: $remoteError - fallback module at '$fallbackLocalModule' is also unusable (Signature: $($fallbackSignature.Status) - $($fallbackSignature.StatusMessage))."
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
        Write-InstallLog -Text 'Installation will continue without the last step' -Info
        continue
    }



    #################################
    ###### Main Workflow Logic ######
    ##################################
    switch ($Mode) {
        'Install' {
            # Copy WIM file to local path
            Copy-WIM

            # Mount WIM (in WhatIf mode: read-only inspection mount)
            Mount-WIM

            # install autodesk software
            Install-AutodeskDeployment -ConfigFile INVVLT

            # set Autodesk Update mode
            Set-AutodeskUpdate -Disable

            #updates
            Install-Update

            # install CIDEON Tools
            Install-CIDEONTool -VaultToolboxStandard -VaultToolboxPro -VaultToolboxObserver -VaultToolboxUpdate
            # disable standard vault toolbox jobs and events
            Disable-VaultExtension
            # copy local configuration files (e.g. license files)
            Copy-Local

            # set custom Inventor Project File
            Set-InventorProjectFile
            # alternative: Set-InventorProjectFile -File "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj"
            # Set-InventorProjectFile -File "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj"
        }
        'Update' {
            # mount wim from network
            Mount-WIM

            # install updates from wim
            Install-Update
            # copy local configuration files (e.g. license files)
            Copy-Local
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
