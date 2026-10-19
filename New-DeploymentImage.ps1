<#
.SYNOPSIS
    Creates a .vhdx deployment image from a deployment folder (replaces the 7-Zip "add to .wim" step).

.DESCRIPTION
    Install-ADSK.ps1 mounts the image on the client and installs from there. The Autodesk installer
    (ODIS 2.24+) refuses files inside a mounted .wim (exit code 453), so the deployment folder is packed
    into a .vhdx instead: an expandable VHDX is created with diskpart (no Hyper-V module needed),
    formatted with NTFS and the folder content is copied into it. The folder content ends up in the
    root of the image, exactly like in a .wim (Image\, Updates\, Cideon\, Local\ ...).

    The name of the image is the name Install-ADSK.ps1 gets as -Image, so name the folder like the
    deployment, e.g. PDC_2027 or 2027_PDC_VLT.

    Needs administrator rights and starts itself elevated if necessary.
    Easiest usage: drag the deployment folder onto New-DeploymentImage.cmd.

.PARAMETER Source
    The deployment folder (the one that contains the subfolder Image).

.PARAMETER VhdxPath
    Target file. Default: <Source>.vhdx next to the folder. Must be on a local drive and needs about
    as much free space as the folder.

.PARAMETER Force
    Overwrite an existing VHDX.

.PARAMETER Pause
    Wait for Enter at the end (used by New-DeploymentImage.cmd, so the window stays open).

.EXAMPLE
    .\New-DeploymentImage.ps1 -Source D:\Deployments\PDC_2027

.EXAMPLE
    .\New-DeploymentImage.ps1 -Source D:\Deployments\PDC_2027 -VhdxPath E:\Share\PDC_2027.vhdx -Force
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Source,
    [string]$VhdxPath,
    [switch]$Force,
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source folder not found: $Source"
}
$Source = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
if (-not $VhdxPath) { $VhdxPath = "$Source.vhdx" }
$VhdxPath = [System.IO.Path]::GetFullPath($VhdxPath)
if ($VhdxPath.StartsWith('\\')) { throw "VhdxPath must be on a local drive (not a network share): $VhdxPath" }
if (-not (Test-Path -LiteralPath (Join-Path -Path $Source -ChildPath 'Image') -PathType Container)) {
    Write-Warning "The folder '$Source' has no subfolder 'Image'. Install-ADSK.ps1 expects the Autodesk deployment in Image\."
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    'Administrator rights are required, restarting elevated ...'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Source', "`"$Source`"", '-VhdxPath', "`"$VhdxPath`"", '-Pause')
    if ($Force) { $arguments += '-Force' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
    return
}

try {
    if (Test-Path -LiteralPath $VhdxPath) {
        if (-not $Force) { throw "$VhdxPath already exists. Use -Force to overwrite." }
        Dismount-DiskImage -ImagePath $VhdxPath -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -LiteralPath $VhdxPath -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Path $VhdxPath -Parent) -Force | Out-Null

    $total = [System.Diagnostics.Stopwatch]::StartNew()
    $sourceBytes = (Get-ChildItem -LiteralPath $Source -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum
    $freeBytes = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($VhdxPath)).AvailableFreeSpace
    if ($freeBytes -lt $sourceBytes * 1.05) {
        throw ('Not enough free space on {0}: {1:N1} GB free, about {2:N1} GB needed.' -f [System.IO.Path]::GetPathRoot($VhdxPath), ($freeBytes / 1GB), ($sourceBytes * 1.05 / 1GB))
    }
    # 10 % + 4 GB headroom for NTFS metadata; the VHDX is expandable, so unused space costs nothing
    $maxGB = [int][math]::Ceiling($sourceBytes * 1.1 / 1GB) + 4
    'Source: {0:N1} GB -> {1} (expandable, max {2} GB)' -f ($sourceBytes / 1GB), $VhdxPath, $maxGB

    $diskpartScript = New-TemporaryFile
    "create vdisk file=`"$VhdxPath`" maximum=$($maxGB * 1024) type=expandable" | Set-Content -LiteralPath $diskpartScript
    $null = diskpart.exe /s $diskpartScript
    $diskpartExit = $LASTEXITCODE
    Remove-Item -LiteralPath $diskpartScript -Force
    if ($diskpartExit -ne 0) { throw "diskpart failed with exit code $diskpartExit" }

    try {
        Mount-DiskImage -ImagePath $VhdxPath | Out-Null
        $disk = Get-DiskImage -ImagePath $VhdxPath | Get-Disk
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel 'ADSKDEPLOY' -Confirm:$false | Out-Null
        $root = "$($partition.DriveLetter):\"

        'Copying ... (this takes a few minutes)'
        robocopy.exe $Source $root /E /COPY:DAT /R:1 /W:1 /MT:16 /NFL /NDL /NP /NJH | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    }
    finally {
        Dismount-DiskImage -ImagePath $VhdxPath | Out-Null
    }

    'Done in {0:N0} s: {1} ({2:N1} GB)' -f $total.Elapsed.TotalSeconds, $VhdxPath, ((Get-Item -LiteralPath $VhdxPath).Length / 1GB)
    "Use it with: Install-ADSK.ps1 -Image $([System.IO.Path]::GetFileNameWithoutExtension($VhdxPath)) -Path $(Split-Path -Path $VhdxPath -Parent) -Mode Install"
}
catch {
    if (-not $Pause) { throw }
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($Pause) { Read-Host 'Press Enter to close' }
}
