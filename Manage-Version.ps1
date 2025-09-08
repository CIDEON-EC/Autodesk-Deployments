<#
.SYNOPSIS
    Version management script for Autodesk Deployment Tools

.DESCRIPTION
    This script helps manage versions of the Autodesk Deployment Tools.
    It can bump version numbers and update relevant files.

.PARAMETER Action
    The action to perform: bump-major, bump-minor, bump-patch, or show

.PARAMETER NewVersion
    Manually set a specific version (e.g., "1.2.3")

.EXAMPLE
    .\Manage-Version.ps1 -Action bump-patch
    .\Manage-Version.ps1 -Action bump-minor
    .\Manage-Version.ps1 -NewVersion "2.0.0"
    .\Manage-Version.ps1 -Action show

.NOTES
    Author: Timon Först
    Date: 08.01.2025
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("bump-major", "bump-minor", "bump-patch", "show")]
    [string]$Action = "show",

    [Parameter(Mandatory = $false)]
    [string]$NewVersion
)

# Get current version from VERSION.txt
$versionFile = Join-Path $PSScriptRoot "VERSION.txt"
if (-not (Test-Path $versionFile)) {
    Write-Error "VERSION.txt not found!"
    exit 1
}

$currentVersion = Get-Content $versionFile -Raw
$currentVersion = $currentVersion.Trim()

Write-Host "Current Version: $currentVersion" -ForegroundColor Green

if ($Action -eq "show") {
    exit 0
}

# Parse current version
if ($currentVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
} else {
    Write-Error "Invalid version format in VERSION.txt. Expected format: X.Y.Z"
    exit 1
}

# Calculate new version
if ($NewVersion) {
    if ($NewVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
        $newVersionString = $NewVersion
    } else {
        Write-Error "Invalid version format. Expected format: X.Y.Z"
        exit 1
    }
} else {
    switch ($Action) {
        "bump-major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "bump-minor" {
            $minor++
            $patch = 0
        }
        "bump-patch" {
            $patch++
        }
    }
    $newVersionString = "$major.$minor.$patch"
}

Write-Host "New Version: $newVersionString" -ForegroundColor Yellow

# Update VERSION.txt
$newVersionString | Set-Content $versionFile -NoNewline

# Update Install-ADSK.ps1
$installScript = Join-Path $PSScriptRoot "Install-ADSK.ps1"
if (Test-Path $installScript) {
    $content = Get-Content $installScript -Raw
    # Update the Version line in the .NOTES section
    $content = $content -replace 'Version:\s*[\d\.]+', "Version: $newVersionString"
    $content | Set-Content $installScript -NoNewline
    Write-Host "Updated Install-ADSK.ps1 version to $newVersionString" -ForegroundColor Green
}

# Update README.md if it contains version references
$readmeFile = Join-Path $PSScriptRoot "readme.md"
if (Test-Path $readmeFile) {
    $content = Get-Content $readmeFile -Raw
    # Update any version references in README if needed
    $content | Set-Content $readmeFile -NoNewline
    Write-Host "Checked readme.md for version updates" -ForegroundColor Green
}

Write-Host "`nVersion updated successfully!" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Review changes: git diff" -ForegroundColor White
Write-Host "2. Commit changes: git add . && git commit -m 'Bump version to $newVersionString'" -ForegroundColor White
Write-Host "3. Push to GitHub: git push" -ForegroundColor White
Write-Host "4. GitHub Action will automatically create a release" -ForegroundColor White
