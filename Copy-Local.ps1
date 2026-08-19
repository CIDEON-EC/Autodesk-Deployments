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
    Author: Timon Först
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
    [ValidatePattern('^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$')]
    [string]$ModuleVersionPin,

    [Parameter(Mandatory = $false, HelpMessage = 'Expected SHA-256 hash for the deployment module. When provided, the downloaded module will be verified against this hash.')]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedModuleHash
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
$TrustedCertificateThumbprints = @(
    '53D03841EC43C1C545F56919F9A6AEF0C7D2E783'
)

function Get-NormalizedThumbprint {
    <#
    .SYNOPSIS
        Normalizes a certificate thumbprint for allowlist comparisons.
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
        throw "Downloaded certificate thumbprint '$normalizedThumbprint' is not trusted. Update the script allowlist before trusting a new signing certificate."
    }

    return $certificate
}

function Assert-TrustedModuleSignature {
    <#
    .SYNOPSIS
        Verifies a module Authenticode signature against the pinned signer allowlist.

    .DESCRIPTION
        Accepts NotTrusted in addition to Valid: the certificate is deliberately no
        longer installed into LocalMachine\Root, so a correctly signed module reports
        NotTrusted (chain not trusted) while its file hash is still verified. The
        pinned signer thumbprint below is the actual trust decision.

        UnknownError is NOT accepted. It is a catch-all status that carries no
        guarantee the file hash was verified, so it cannot stand in for a hash check.
        NotSigned, HashMismatch and all other statuses are rejected as well.
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

# LOW Issue #1: Warn when module download is not pinned to a specific version
if (-not $SelectedModuleVersionPin) {
    Write-Warning 'ModuleVersionPin is not specified. The module and certificate will be downloaded from the latest GitHub Release. For production deployments, pin to a specific version: -ModuleVersionPin "x.y.z"'
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
        Adds the signing certificate to the LocalMachine TrustedPublisher store when missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CertificatePath
    )

    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
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
    #>
    [CmdletBinding()]
    param()

    $moduleRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $ModuleFileName -ReleaseVersion $ModuleVersionPin
    $certificateRemoteUri = Get-ReleaseAssetDownloadUri -AssetName $CertificateFileName -ReleaseVersion $ModuleVersionPin

    Save-RemoteFile -Uri $certificateRemoteUri -DestinationPath $CertificateLocalPath
    Assert-TrustedCertificateThumbprint -CertificatePath $CertificateLocalPath -TrustedThumbprint $TrustedCertificateThumbprints | Out-Null
    Add-CertificateToStoreIfMissing -CertificatePath $CertificateLocalPath

    Save-RemoteFile -Uri $moduleRemoteUri -DestinationPath $ModuleLocalPath

    # LOW Issue #2: SHA-256 hash verification for downloaded assets (MITM protection)
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
        Assert-TrustedModuleSignature -Signature $fallbackSignature -TrustedThumbprint $TrustedCertificateThumbprints
    }
    catch {
        throw "Remote module loading failed: $remoteError - fallback module at '$fallbackLocalModule' is also unusable ($($_.Exception.Message))."
    }

    Import-Module -Name $fallbackLocalModule -Force -ErrorAction Stop
}
#endregion

#region Context
$logFilePath = $null
if ($Logging.IsPresent) {
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
