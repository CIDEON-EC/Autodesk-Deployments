#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Git Release Tag Management Script
.DESCRIPTION
    Manages Git release tags (create patch/minor/major tags, show latest, push to remote)
.PARAMETER Action
    The action to perform: Patch, Minor, Major, ShowLatest, Push
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Patch', 'Minor', 'Major', 'ShowLatest', 'Push')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

function Get-CurrentVersion {
    $tag = (git describe --tags --abbrev=0 2>$null)
    if ($tag) {
        return $tag.TrimStart('v')
    }
    return '0.0.0'
}

[CmdletBinding(SupportsShouldProcess)]
function New-PatchTag {
    $current = Get-CurrentVersion
    $parts = $current -split '\.'
    $patch = [int]$parts[2] + 1
    $newVersion = "$($parts[0]).$($parts[1]).$patch"
    $tagName = "v$newVersion"

    if (-not $PSCmdlet.ShouldProcess($tagName, 'Create git tag')) {
        return
    }

    Write-Output "Creating tag: $tagName"
    git tag -a "$tagName" -m "Release version $newVersion"

    if ($LASTEXITCODE -eq 0) {
        Write-Output "Tag created successfully: $tagName"
    }
    else {
        Write-Error 'Failed to create tag'
        exit 1
    }
}

[CmdletBinding(SupportsShouldProcess)]
function New-MinorTag {
    $current = Get-CurrentVersion
    $parts = $current -split '\.'
    $minor = [int]$parts[1] + 1
    $newVersion = "$($parts[0]).$minor.0"
    $tagName = "v$newVersion"

    if (-not $PSCmdlet.ShouldProcess($tagName, 'Create git tag')) {
        return
    }

    Write-Output "Creating tag: $tagName"
    git tag -a "$tagName" -m "Release version $newVersion"

    if ($LASTEXITCODE -eq 0) {
        Write-Output "Tag created successfully: $tagName"
    }
    else {
        Write-Error 'Failed to create tag'
        exit 1
    }
}

[CmdletBinding(SupportsShouldProcess)]
function New-MajorTag {
    $current = Get-CurrentVersion
    $parts = $current -split '\.'
    $major = [int]$parts[0] + 1
    $newVersion = "$major.0.0"
    $tagName = "v$newVersion"

    if (-not $PSCmdlet.ShouldProcess($tagName, 'Create git tag')) {
        return
    }

    Write-Output "Creating tag: $tagName"
    git tag -a "$tagName" -m "Release version $newVersion"

    if ($LASTEXITCODE -eq 0) {
        Write-Output "Tag created successfully: $tagName"
    }
    else {
        Write-Error 'Failed to create tag'
        exit 1
    }
}

function Show-LatestTag {
    $tag = git describe --tags --abbrev=0 2>$null
    if ($tag) {
        Write-Output "Latest tag: $tag"
    }
    else {
        Write-Output 'No tags found'
    }
}

[CmdletBinding(SupportsShouldProcess)]
function Push-Tag {
    if (-not $PSCmdlet.ShouldProcess('origin', 'Push git tags')) {
        return
    }

    Write-Output 'Pushing tags to remote...'
    git push origin --tags

    if ($LASTEXITCODE -eq 0) {
        Write-Output 'Tags pushed successfully!'
    }
    else {
        Write-Error 'Failed to push tags'
        exit 1
    }
}

# Execute the requested action
switch ($Action) {
    'Patch' { New-PatchTag }
    'Minor' { New-MinorTag }
    'Major' { New-MajorTag }
    'ShowLatest' { Show-LatestTag }
    'Push' { Push-Tag }
}
