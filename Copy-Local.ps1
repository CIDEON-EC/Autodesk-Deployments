<#
.SYNOPSIS
    Wrapper script for copying local deployment files via the shared module.

.DESCRIPTION
    Loads the signed CIDEON.AutodeskDeployment module using the same bootstrap pattern
    as Install-ADSK.ps1 and then calls the module function Copy-Local.

    The source path must contain a subfolder named Local. Selected subfolders from
    that location are copied to the target folders on the local machine.

.PARAMETER Path
    Path to the folder containing the subfolder Local.

.PARAMETER Folder
    Optional list of Local subfolders to copy. Default is Users.

.PARAMETER TargetFolder
    Optional list of target folders. When omitted, the module defaults each entry to C:\.

.PARAMETER Logging
    Enables log file creation in Path\_LOG.

.PARAMETER ModuleVersionPin
    Optional semantic version without leading v. When set, the module and certificate
    are downloaded from that GitHub Release instead of latest.

.EXAMPLE
    .\Copy-Local.ps1 -Path '\\server\share\PDC_2026' -Folder 'Users'

.EXAMPLE
    .\Copy-Local.ps1 -Path '\\server\share\PDC_2026' -Folder @('ProgramData', 'Users') -TargetFolder @('C:\', 'C:\') -Logging

.NOTES
    Autor: Timon Forst
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, HelpMessage = 'Path to the folder containing the subfolder Local')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
            if (Test-Path $_ -PathType Container) {
                $true
            }
            else {
                throw "Path '$_' is not existing."
            }
        })]
    [string]$Path,

    [Parameter(Mandatory = $false, HelpMessage = 'Folders to copy from the Local subfolder')]
    [string[]]$Folder = @('Users'),

    [Parameter(Mandatory = $false, HelpMessage = 'Target folders for the copy operation. Default is C:\ for all folders')]
    [string[]]$TargetFolder,

    [Parameter(Mandatory = $false, HelpMessage = 'Enable logging')]
    [switch]$Logging,

    [Parameter(Mandatory = $false, HelpMessage = 'Optional: Pin remote module download to a specific release version (e.g. 1.2.0). Default is latest release.')]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$ModuleVersionPin
)

#region Module Loader
$ModuleName = 'CIDEON.AutodeskDeployment'
$ModuleFileName = "$ModuleName.psm1"
$CertificateFileName = 'CIDEON-CodeSigning.cer'
$RepositoryOwner = 'CIDEON-EC'
$RepositoryName = 'Autodesk-Deployments'
$RepositoryApiBaseUrl = "https://api.github.com/repos/$RepositoryOwner/$RepositoryName"
$ModuleCacheFolder = Join-Path -Path $env:ProgramData -ChildPath 'CIDEON/Autodesk-Deployments'
$ModuleLocalPath = Join-Path -Path $ModuleCacheFolder -ChildPath $ModuleFileName
$CertificateLocalPath = Join-Path -Path $ModuleCacheFolder -ChildPath $CertificateFileName
$SelectedModuleVersionPin = $ModuleVersionPin
# Keep in sync with the allowlist in Install-ADSK.ps1
$TrustedCertificateThumbprints = @(
    '53D03841EC43C1C545F56919F9A6AEF0C7D2E783'
)

function Get-NormalizedThumbprint {
    <#
    .SYNOPSIS
        Normalizes a certificate thumbprint for allowlist comparisons.

    .PARAMETER Thumbprint
        The thumbprint to normalize.
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

    .PARAMETER CertificatePath
        Full path to the certificate file that should be validated.

    .PARAMETER TrustedThumbprint
        One or more allowed certificate thumbprints.
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
        throw "Downloaded certificate thumbprint '$normalizedThumbprint' is not trusted. Update the allowlist in Install-ADSK.ps1 and Copy-Local.ps1 before trusting a new signing certificate."
    }

    return $certificate
}

function Assert-TrustedModuleSignature {
    <#
    .SYNOPSIS
        Verifies a module Authenticode signature against the pinned signer allowlist.

    .PARAMETER Signature
        Result object from Get-AuthenticodeSignature.

    .PARAMETER TrustedThumbprint
        One or more allowed signer thumbprints.

    .PARAMETER AllowUntrustedChain
        Also accepts the status NotTrusted or UnknownError (intact signature, certificate chain without a
        trusted root). Used when the certificate store is not writable; the thumbprint
        pin is still enforced.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Signature,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TrustedThumbprint,
        [switch]$AllowUntrustedChain
    )

    $acceptedStatus = @([System.Management.Automation.SignatureStatus]::Valid)
    if ($AllowUntrustedChain) {
        # NotTrusted/UnknownError = file hash is intact but the (self-signed) chain has no trusted root; the thumbprint pin below still applies
        $acceptedStatus += [System.Management.Automation.SignatureStatus]::NotTrusted
        $acceptedStatus += [System.Management.Automation.SignatureStatus]::UnknownError
    }

    if ($Signature.Status -notin $acceptedStatus) {
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
        'User-Agent' = 'Copy-Local'
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
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    Invoke-WebRequest -Uri $Uri -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
}

function Add-CertificateToStoreIfMissing {
    <#
    .SYNOPSIS
        Adds the signing certificate to TrustedPublisher when missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CertificatePath
    )

    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
    $trustedPublisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'CurrentUser')
    $trustedPublisherStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        $existing = $trustedPublisherStore.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
        if (-not $existing) {
            $trustedPublisherStore.Add($certificate)
        }
    }
    finally {
        $trustedPublisherStore.Close()
    }
}

function Import-RemoteSignedDeploymentModule {
    <#
    .SYNOPSIS
        Downloads the signed deployment module and imports it.
    #>
    [CmdletBinding()]
    param()

    $moduleRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $ModuleFileName -ReleaseVersion $SelectedModuleVersionPin
    $certificateRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $CertificateFileName -ReleaseVersion $SelectedModuleVersionPin

    Save-RemoteFile -Uri $certificateRemoteUri -DestinationPath $CertificateLocalPath
    Assert-TrustedCertificateThumbprint -CertificatePath $CertificateLocalPath -TrustedThumbprint $TrustedCertificateThumbprints | Out-Null
    try {
        Add-CertificateToStoreIfMissing -CertificatePath $CertificateLocalPath
    }
    catch {
        # Store locked by policy/EDR: rely on the pinned thumbprint instead of chain trust
        Write-Warning ("The CIDEON code-signing certificate could not be added to the CurrentUser TrustedPublisher store ($($_.Exception.Message)). " +
            'The module is still verified by its signature and the pinned certificate thumbprint. ' +
            'To avoid this warning, deploy CIDEON-CodeSigning.cer to the Trusted Publishers/Root stores.')
        $script:AllowUntrustedChain = $true
    }

    Save-RemoteFile -Uri $moduleRemoteUri -DestinationPath $ModuleLocalPath

    $signature = Get-AuthenticodeSignature -FilePath $ModuleLocalPath
    Assert-TrustedModuleSignature -Signature $signature -TrustedThumbprint $TrustedCertificateThumbprints -AllowUntrustedChain:$script:AllowUntrustedChain

    Import-Module -Name $ModuleLocalPath -Force -ErrorAction Stop
}

$script:AllowUntrustedChain = $false

try {
    Import-RemoteSignedDeploymentModule
}
catch {
    $remoteError = $_.Exception.Message

    $fallbackLocalModule = Join-Path -Path $PSScriptRoot -ChildPath $ModuleFileName
    if (-not (Test-Path -Path $fallbackLocalModule)) {
        throw "Remote module loading failed: $remoteError - no local fallback found at '$fallbackLocalModule'."
    }

    $fallbackSignature = Get-AuthenticodeSignature -FilePath $fallbackLocalModule
    try {
        Assert-TrustedModuleSignature -Signature $fallbackSignature -TrustedThumbprint $TrustedCertificateThumbprints -AllowUntrustedChain:$script:AllowUntrustedChain
    }
    catch {
        throw "Remote module loading failed: $remoteError - fallback module at '$fallbackLocalModule' is also unusable ($($_.Exception.Message))."
    }

    Import-Module -Name $fallbackLocalModule -Force -ErrorAction Stop
}
#endregion

#region Context
$logFilePath = $null
$loggingEnabled = $Logging.IsPresent
if ($loggingEnabled) {
    $logFolder = Join-Path -Path $Path -ChildPath '_LOG'
    if (-not $WhatIfPreference -and -not (Test-Path -Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }
    $logFilePath = Join-Path -Path $logFolder -ChildPath ("Copy-Local-{0}.log" -f $env:COMPUTERNAME)
}

Set-InstallContext -Context @{
    Path      = $Path
    mountPath = $Path
    Logging   = $Logging
    LogFile   = $logFilePath
}
#endregion

#region Code
Copy-Local -Path $Path -SourceFolder $Folder -TargetFolder $TargetFolder
#endregion
