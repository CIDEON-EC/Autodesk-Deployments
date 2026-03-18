<#
.SYNOPSIS
    CIDEON Autodesk Deployment helper functions.
.NOTES
    Author: Timon Först
    ModuleVersion: 1.2.0
#>

Set-StrictMode -Version 3.0

function Set-InstallContext {
    <#
    .SYNOPSIS
        Stores deployment context values as global variables.

    .DESCRIPTION
        Accepts a hashtable of key-value pairs and publishes each entry as a global variable
        so that all downstream module functions can access shared state such as Version,
        LogFile, wimFile, mountPath and ConfigFullFilenames.

    .PARAMETER Context
        A hashtable whose keys become global variable names and whose values become their values.

    .EXAMPLE
        Set-InstallContext -Context @{
            Version  = '2026'
            LogFile  = 'C:\Temp\Install-ADSK-2026.log'
        }

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    foreach ($entry in $Context.GetEnumerator()) {
        Set-Variable -Name $entry.Key -Value $entry.Value -Scope Global
    }
}

function Invoke-DeploymentWorkflow {
    <#
    .SYNOPSIS
        Orchestrates the full WIM deployment lifecycle and invokes a caller-supplied mode handler.

    .DESCRIPTION
        Validates the software version, sets up logging, discovers the WIM file, prepares mount
        paths and configuration file names, then executes the supplied ScriptBlock inside a
        try/catch/finally that handles error logging, WIM dismount and log-file archival.

        The caller passes the mode-specific logic (Install / Update / Uninstall) as a ScriptBlock
        so that customer-specific adjustments stay in Install-ADSK.ps1 while all infrastructure
        code lives in the module.

    .PARAMETER ModeHandler
        A ScriptBlock that contains the mode-specific deployment logic (typically a switch on $Mode).
        It is invoked after the WIM is prepared and the install context is set.

    .EXAMPLE
        Invoke-DeploymentWorkflow -ModeHandler {
            switch ($Mode) {
                'Install'   { Install-AutodeskDeployment }
                'Update'    { Mount-WIM; Install-Update; Copy-Local }
                'Uninstall' { Uninstall-Program -Publisher 'CIDEON' }
            }
        }

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory)]
        [scriptblock]$ModeHandler
    )

    begin {
        # Validate Version — must be a 4-digit year string (e.g. '2026')
        if ([string]::IsNullOrEmpty($Version) -or $Version.Length -ne 4) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    "Version must be a 4-digit year string (e.g. '2026'). Received: '$Version'. " +
                    'Supply -Version explicitly or ensure the WIM name contains a 4-digit number.'
                ),
                'InvalidVersionFormat',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $Version
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Set-InstallContext -Context @{ Version = $Version }

        $DebugPreference = 'SilentlyContinue'

        # Local log file
        $logFileName = "Install-ADSK-$($Version).log"
        $script:LogFile = [System.IO.Path]::Combine($LocalFolder, $logFileName)
        $Global:LogFile = $script:LogFile

        Set-InstallContext -Context @{ LogFile = $Global:LogFile }

        # Create local folder
        if (-not (Test-Path $LocalFolder)) {
            New-Item -Path $LocalFolder -ItemType Directory | Out-Null
            Write-InstallLog -text "Created $LocalFolder" -Info
        }
    }

    process {
        $startTime = Get-Date

        # Discover WIM file
        $wimFile = Get-ChildItem -Path $Path -Filter "$WIM.wim" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1

        if (-not $wimFile) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new("No WIM file matching '$WIM.wim' found in '$Path'."),
                'WimFileNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Path
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-InstallLog -text "WIM File: $wimFile" -Info

        # Mount path
        $mountPath = [System.IO.Path]::Combine(
            $LocalFolder,
            'mount_' + [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name)
        )

        # Build config file paths
        $ConfigFullFilenames = @()
        foreach ($configFile in $Files) {
            $ConfigFullFilenames += [System.IO.Path]::Combine($mountPath, 'Image', "$configFile.xml")
        }

        Set-InstallContext -Context @{
            wimFile             = $wimFile
            mountPath           = $mountPath
            ConfigFullFilenames = $ConfigFullFilenames
        }

        # Create mount directory
        if (-not (Test-Path $mountPath)) {
            New-Item -Path $mountPath -ItemType Directory | Out-Null
            Write-InstallLog -text "Created $mountPath" -Info
        }

        $inspectMount = $null
        $script:InspectMount = $null

        try {
            # Execute the caller-supplied mode handler (Install / Update / Uninstall logic)
            & $ModeHandler
        }
        catch {
            Write-InstallLog -text "By $Mode" -Fail
            Write-InstallLog -text "$($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)" -Fail
        }
        finally {
            try {
                Get-AppLogError -Start $startTime

                # Dismount and optionally delete WIM
                Write-InstallLog -text "Dismounting WIM $($wimFile.Name)" -Info
                if ($WhatIfPreference -and $script:InspectMount) {
                    Dismount-WIM -File $script:InspectMount -WhatIf:$false
                    Write-InstallLog -text 'WIM inspection complete and dismounted' -Info
                }
                elseif ($NoDownload.IsPresent) {
                    Dismount-WIM
                }
                elseif ($Purge.IsPresent) {
                    Dismount-WIM -Purge
                }
                else {
                    Dismount-WIM
                }
            }
            catch {
                Write-InstallLog -text "$($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)" -Fail
            }
            finally {
                # Copy log to server
                if ($Logging.IsPresent) {
                    try {
                        $logFolder = [System.IO.Path]::Combine($Path, '_LOG')
                        if (-not (Test-Path $logFolder)) {
                            New-Item -Path $logFolder -ItemType Directory | Out-Null
                        }
                        $logFilePath = [System.IO.Path]::Combine($logFolder, "$env:COMPUTERNAME.log")

                        # Copy and remove log file only if it exists (WhatIf mode may not create it)
                        if (Test-Path $script:LogFile) {
                            Copy-Item -Path $script:LogFile -Destination $logFilePath
                            if (Test-Path $logFilePath) {
                                Remove-Item -Path $script:LogFile -Recurse
                            }
                        }
                    }
                    catch {
                        Write-InstallLog -text "Copy Logfile to $logFolder failed" -Info
                    }
                }
            }
        }
    }

    end {
    }
}

function Write-InstallLog {
    <#
    .SYNOPSIS
        Writes a log entry to the log file, if $Logging is set.

    .DESCRIPTION
        Adds a log entry to the specified log file with a timestamp.

    .PARAMETER text
        The text to log.

    .PARAMETER Info
        If set, the log entry will be marked as an info message.
    .PARAMETER Fail
        If set, the log entry will be marked as a failure message.

    .EXAMPLE
        Write-InstallLog -text "This is a log entry." -Info
        Write-InstallLog -text "This is a failure message." -Fail

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory)]
        [string]$text,
        [Parameter()]
        [switch]$Info,
        [Parameter()]
        [switch]$Fail
    )
    if ($Logging.IsPresent) {
        # choose category based on failure switch only; INFO is default
        $category = if ($Fail.IsPresent) { 'ERROR' } else { 'INFO' }
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [$($category)] $($text)"
        if ($PSCmdlet.ShouldProcess("[$($category)] $($text)", 'Log')) {
            if (-not $WhatIfPreference) {
                $targetLogFile = $script:LogFile
                if ([string]::IsNullOrWhiteSpace($targetLogFile) -and -not [string]::IsNullOrWhiteSpace($Global:LogFile)) {
                    $targetLogFile = $Global:LogFile
                }
                if (-not [string]::IsNullOrWhiteSpace($targetLogFile)) {
                    $logMessage | Out-File $targetLogFile -Append
                }
            }
        }
    }

}

function Write-InstallProgress {
    <#
    .SYNOPSIS
        Writes a compact progress status to the PowerShell host.

    .DESCRIPTION
        Shows user-facing progress messages for important steps (for example before
        installer executions). Output is suppressed when Quiet mode is enabled.

    .PARAMETER Text
        The status text to display.

    .PARAMETER Fail
        Marks the status as an error message.

    .NOTES
        Autor: Timon Forst
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [Parameter()]
        [switch]$Fail
    )

    $quietValue = $false
    $quietVariable = Get-Variable -Name Quiet -ErrorAction SilentlyContinue
    if ($quietVariable) {
        $quietValue = [bool]$quietVariable.Value
    }

    if ($quietValue) {
        return
    }

    $tag = if ($Fail.IsPresent) { 'ERROR' } else { 'INFO' }
    $foregroundColor = if ($Fail.IsPresent) { 'Red' } else { 'Gray' }
    Write-Host "[$tag] $Text" -ForegroundColor $foregroundColor
}

function Update-WIMInspectionCache {
    <#
    .SYNOPSIS
        Updates cached file and folder information from a mounted WIM path.

    .DESCRIPTION
        Reads available content from the folders "Updates", "Cideon" and "Local" in a mounted image
        and stores the results in script-level cache variables for later WhatIf simulation.

    .PARAMETER MountedPath
        The mounted root path of the deployment image.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$MountedPath
    )

    # reset cached lists for this run
    $Script:CachedUpdateFiles = $null
    $Script:CachedCideonFiles = $null
    $Script:CachedLocalFolders = $null

    # Cache Updates
    $updatesPath = Join-Path $MountedPath 'Updates'
    if (Test-Path $updatesPath) {
        $Script:CachedUpdateFiles = @(Get-ChildItem -Path $updatesPath -Exclude @('*.txt', '*.xml', 'VBA') -File -ErrorAction SilentlyContinue)
    }
    else {
        Write-InstallLog -text "Updates folder not found at: $updatesPath" -Info
    }

    # Cache Cideon tools
    $cideonPath = Join-Path $MountedPath 'Cideon'
    if (Test-Path $cideonPath) {
        $Script:CachedCideonFiles = @(Get-ChildItem -Path $cideonPath -Exclude *.txt -ErrorAction SilentlyContinue)
    }
    else {
        Write-InstallLog -text "Cideon folder not found at: $cideonPath" -Info
    }

    # Cache Local folders
    $localPath = Join-Path $MountedPath 'Local'
    if (Test-Path $localPath) {
        $Script:CachedLocalFolders = @(Get-ChildItem -Path $localPath -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    else {
        Write-InstallLog -text "Local folder not found at: $localPath" -Info
    }
}
function Get-CachedFiles {
    <#
    .SYNOPSIS
        Returns file-like objects from cached inspection data for WhatIf mode.

    .DESCRIPTION
        Converts cached entries into objects with Name and FullName and logs the simulated operation.
        If no cache is available, an empty collection is returned.

    .PARAMETER Path
        The target path used to build FullName values.
    .PARAMETER OperationText
        The text used for logging the simulated operation.
    .PARAMETER CachedFiles
        Optional cached entries to convert and return.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$OperationText,
        [Parameter()]
        [object[]]$CachedFiles
    )

    if ($CachedFiles -and $CachedFiles.Count -gt 0) {
        Write-InstallLog -text "$OperationText $Path (WhatIf mode, using inspected WIM cache)" -Info
        return @($CachedFiles | ForEach-Object {
                $itemName = if ($_ -is [string]) {
                    $_
                }
                elseif ($_.PSObject.Properties['Name']) {
                    $_.Name
                }
                else {
                    [string]$_
                }

                [pscustomobject]@{
                    Name      = $itemName
                    FullName  = [System.IO.Path]::Combine($Path, $itemName)
                    FromCache = $true
                }
            })
    }

    Write-InstallLog -text "$OperationText $Path (WhatIf mode)" -Info
    return @()
}
function Install-Update {
    <#
    .SYNOPSIS
        Installs updates from the specified path.

    .DESCRIPTION
        Installs updates from the specified path. The updates are expected to be in the subfolder "Updates".

    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Updates".

    .EXAMPLE
        Install-Update -Path "C:\Temp\PDC_20XX"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Path = $Global:mountPath
    )
    # install updates
    # get all updates in folder
    Write-InstallLog -text 'Updates will be installed' -Info
    $filepath = [System.IO.Path]::Combine($Path, 'Updates')
    $excludePatterns = @('*.txt', '*.xml', 'VBA')

    if (-not $WhatIfPreference -or (Test-Path -Path $filepath)) {
        $files = @(Get-ChildItem -Path $filepath -Exclude $excludePatterns -File)
    }
    else {
        $files = Get-CachedFiles -Path $filepath -OperationText 'Would install updates from' -CachedFiles $Script:CachedUpdateFiles
    }

    # ensure we always have an array; cached helper may return $null
    $files = @($files)

    if ($files.Count -eq 0) {
        return
    }

    foreach ($file in $files) {
        $executable = $file.FullName
        $updateLogFile = $script:LogFile
        if ($file.Name -like '*msi') {
            $updateLogFile = [System.IO.Path]::Combine($LocalFolder, "Install_Autodesk_$Version`_$([System.IO.Path]::GetFileNameWithoutExtension($file.Name)).log")
            $arguments = "/i ""$($file.FullName)"" /qn /norestart /l*v ""$updateLogFile"""
            $executable = 'msiexec.exe'
        }
        elseif ($file.Name -like '*Licensing*exe') {
            $arguments = '--unattendedmodeui none --mode unattended'
        }
        elseif ($file.Name -like '*AdODIS*exe') {
            $arguments = '--mode unattended'
        }
        elseif ($file.Name -like '*vba*') {
            $arguments = '/quiet /norestart'
        }
        else {
            $arguments = '-q /quiet'
        }
        try {
            Write-InstallLog -text "Start update installation: $($file.Name) with arguments: $arguments" -Info
            if ($PSCmdlet.ShouldProcess($file.Name, "Install Update with arguments: $arguments")) {
                Write-InstallProgress -Text "Installing update: $($file.Name)"
                $process = Start-Process -NoNewWindow -FilePath $executable -ArgumentList $arguments -PassThru -Wait -ErrorAction Stop

                # Check exit code
                if ($process.ExitCode -eq 0) {
                    Write-InstallLog -text "Successfully installed update: $($file.Name)" -Info
                }
                else {
                    Write-InstallLog -text "Update installation failed for $($file.Name) with exit code: $($process.ExitCode). Check log file: $updateLogFile" -Fail
                }
            }
        }
        catch {
            Write-InstallLog -text "Update installation error for $($file.Name): $($_.Exception.Message)" -Fail
            Write-InstallProgress -Text "Update failed: $($file.Name)" -Fail
        }

    }
}

function Install-AutodeskDeployment {

    <#
    .SYNOPSIS
        Installs the Autodesk Deployment from the specified path.

    .DESCRIPTION
        Installs the Autodesk Deployment from the specified path. The deployment is expected to be in the subfolder "Image".

    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Image".

    .PARAMETER ConfigFile
        Optional explicit deployment config XML paths. If omitted, the function uses the
        current deployment context and falls back to Image\Collection.xml.

    .PARAMETER LogFolder
        Optional override for the folder where the deployment installer log should be written.

    .PARAMETER DeploymentName
        Optional override for the deployment name used in the installer log file name.

    .EXAMPLE
        Install-AutodeskDeployment -Path "C:\Temp\PDC_20XX"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Path,
        [Parameter()]
        [string[]]$ConfigFile,
        [Parameter()]
        [string]$LogFolder,
        [Parameter()]
        [string]$DeploymentName
    )
    Write-InstallLog -text 'Start Autodesk installer' -Info
    if (-not $PSBoundParameters.ContainsKey('Path')) {
        $mountPathVariable = Get-Variable -Name mountPath -Scope Global -ErrorAction SilentlyContinue
        if ($mountPathVariable) {
            $Path = $mountPathVariable.Value
        }
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new(
                'Install-AutodeskDeployment requires -Path or an initialized script mountPath context.'
            ),
            'MissingDeploymentPath',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $Path
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if (-not $PSBoundParameters.ContainsKey('ConfigFile')) {
        $configFileVariable = Get-Variable -Name ConfigFullFilenames -Scope Global -ErrorAction SilentlyContinue
        if ($configFileVariable) {
            $ConfigFile = $configFileVariable.Value
        }
    }

    if (-not $PSBoundParameters.ContainsKey('LogFolder')) {
        $logFolderVariable = Get-Variable -Name LocalFolder -Scope Global -ErrorAction SilentlyContinue
        if ($logFolderVariable) {
            $LogFolder = $logFolderVariable.Value
        }
    }

    if (-not $PSBoundParameters.ContainsKey('DeploymentName')) {
        $deploymentNameVariable = Get-Variable -Name WIM -Scope Global -ErrorAction SilentlyContinue
        if ($deploymentNameVariable) {
            $DeploymentName = $deploymentNameVariable.Value
        }
    }

    $configFiles = @($ConfigFile)
    if ($configFiles.Count -eq 0) {
        $defaultConfigPath = [System.IO.Path]::Combine($Path, 'Image', 'Collection.xml')
        if (Test-Path -Path $defaultConfigPath -PathType Leaf) {
            $configFiles = @($defaultConfigPath)
        }
    }

    # call install autodesk deployment
    foreach ($ConfigFullFilename in $configFiles) {
        Write-InstallLog -text "Started Installation of ConfigFile: $ConfigFullFilename" -Info
        $configName = Split-Path $ConfigFullFilename -Leaf
        $deploymentLogPath = [System.IO.Path]::Combine($LogFolder, "Install-ADSK-Deplyoment-$DeploymentName.log")

        if (-not (Test-Path -Path $ConfigFullFilename -PathType Leaf)) {
            Write-InstallLog -text "Config file not found: $ConfigFullFilename" -Fail
            continue
        }

        # enfore logging settings for deployment installere
        try {
            # Load selected deployment XML
            [xml]$configXml = Get-Content -Path $ConfigFullFilename -ErrorAction Stop
            if (-not $configXml.Collection) {
                throw "Missing root node 'Collection' in config file: $ConfigFullFilename"
            }

            # Ensure required LoggingSettings structure exists without relying on dynamic XML properties.
            $loggingSettingsNode = $configXml.Collection.SelectSingleNode('LoggingSettings')
            if (-not $loggingSettingsNode) {
                $loggingSettingsNode = $configXml.CreateElement('LoggingSettings')
                [void]$configXml.Collection.AppendChild($loggingSettingsNode)
            }

            $loggingNode = $loggingSettingsNode.SelectSingleNode('Logging')
            if (-not $loggingNode) {
                $loggingNode = $configXml.CreateElement('Logging')
                [void]$loggingSettingsNode.AppendChild($loggingNode)
            }

            $pathNode = $loggingSettingsNode.SelectSingleNode('Path')
            if (-not $pathNode) {
                $pathNode = $configXml.CreateElement('Path')
                [void]$loggingSettingsNode.AppendChild($pathNode)
            }

            # Enforce logging defaults for deployment installer
            $loggingNode.InnerText = 'true'
            $pathNode.InnerText = $deploymentLogPath

            if ($PSCmdlet.ShouldProcess($configName, 'Update LoggingSettings in deployment config')) {
                # Persist XML changes before running Installer.exe
                $configXml.Save($ConfigFullFilename)
                Write-InstallLog -text "Updated LoggingSettings in config file: $ConfigFullFilename" -Info
            }
        }
        catch {
            Write-InstallLog -text "Failed to update LoggingSettings for config file $ConfigFullFilename. Error: $($_.Exception.Message)" -Fail
            continue
        }

        $installerPath = [System.IO.Path]::Combine($Path, 'Image', 'Installer.exe')
        $installerArgs = "-i deploy --offline_mode -q -o $ConfigFullFilename"
        if ($PSCmdlet.ShouldProcess($configName, "Install Autodesk Deployment with arguments: $installerArgs")) {
            Write-InstallProgress -Text "Starting Autodesk deployment: $configName"
            Start-Process -FilePath $installerPath -ArgumentList $installerArgs -PassThru | Out-Null
            # Waiting
            Wait-Process -Name 'Installer'
        }
    }

    Write-InstallLog -text 'Autodesk Products installed' -Info
}
function Uninstall-AutodeskDeployment {

    <#
    .SYNOPSIS
        Uninstalls the Autodesk Deployment from the specified path.

    .DESCRIPTION
        Uninstalls the Autodesk Deployment from the specified path. The deployment is expected to be in the subfolder "Image".

    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Image".

    .EXAMPLE
        Uninstall-AutodeskDeployment -Path "C:\Temp\PDC_20XX"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false, HelpMessage = 'Path to the Autodesk Deployment')]
        [string]$Path = [System.IO.Path]::Combine($mountPath, 'image'),
        [Parameter(Mandatory = $false, HelpMessage = 'Optional: Products to uninstall')]
        [string[]]$Product
    )
    begin {
        # Skip in WhatIf mode if path doesn't exist
        if ($WhatIfPreference -and -not (Test-Path -Path $Path)) {
            Write-InstallLog -text "Would uninstall Autodesk products from $Path (WhatIf mode)" -Info
            return
        }

        # Get the Autodesk Products from the path
        $adskProducts = @((Get-ChildItem -Directory -Path $Path) | Where-Object { $_.Name -like "*$($Version)*" })
        if ($adskProducts.Count -eq 0) {
            Write-InstallLog -text "No Autodesk Products found in $Path" -Fail
            return
        }
        # else {
        #     Write-InstallLog -text "Autodesk Products found: $($adskProducts.Name -join ", ")" -Info
        # }
    }
    process {
        foreach ($adskProduct in $adskProducts) {

            try {
                # get xml file
                $setupxml = [System.IO.Path]::Combine($adskProduct.FullName, 'setup.xml')
                $setupextxml = [System.IO.Path]::Combine($adskProduct.FullName, 'setup_ext.xml')

                [xml]$xml = Get-Content $setupxml
                $productname = $xml.Bundle.Identity.DisplayName

                # if $Product is filled
                # AND the productname does NOT match, continue with the next product
                if ($null -ne $Product -and (-not ($Product | Where-Object { $productname -like "*$_*" }))) {
                    Write-InstallLog -text "Product $productname is not in the specified products to uninstall" -Info
                    continue
                }

                # start uninstall
                Write-InstallLog -text "Uninstallation of $productname" -Info
                $uninstallExecutable = [System.IO.Path]::Combine($Path, 'image', 'Installer.exe')
                $uninstallArguments = "-i uninstall -q --manifest $setupxml --extension_manifest $setupextxml"
                if ($PSCmdlet.ShouldProcess($productname, "Uninstall Autodesk Product with arguments: $uninstallArguments")) {
                    Write-InstallProgress -Text "Starting uninstall: $productname"
                    Start-Process -FilePath $uninstallExecutable -ArgumentList $uninstallArguments -Wait

                    Write-InstallLog -text 'Uninstallation: complete' -Info
                }
            }
            catch {
                Write-InstallLog -text 'Uninstallation: not successful' -Fail
            }
        }
    }

    end {
    }

}

function Set-AutodeskDeployment {
    <#
    .SYNOPSIS
        Modifies Autodesk deployment XML files before installation.

    .DESCRIPTION
        Processes deployment product XML files and optionally removes language packs or specific packages.

    .PARAMETER Path
        Path to the Autodesk deployment image folder.
    .PARAMETER xmlFileName
        XML file name to modify, default is "setup_ext.xml".
    .PARAMETER Language
        One or more language pack names to keep.
    .PARAMETER Remove
        One or more package name patterns to remove.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false, HelpMessage = 'Path to the Autodesk Deployment')]
        [string]$Path = [System.IO.Path]::Combine($mountPath, 'image'),
        [Parameter(Mandatory = $false, HelpMessage = 'XML file to change. Default is "setup_ext.xml"')]
        [string]$xmlFileName = 'setup_ext.xml',
        [Parameter(Mandatory = $false, HelpMessage = 'One or More Language Packs to keep. Name must be in English (e.g. German, Polish). It has to be available in the deployment. Default is "German"')]
        [string[]]$Language,
        [Parameter(Mandatory = $false, HelpMessage = 'Remove a specified update')]
        [string[]]$Remove
    )

    # Ensure scalar string inputs are treated as single-element arrays so foreach loops work as expected

    $Language = @(@($Language) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $Remove = @(@($Remove) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $adskProducts = @()

    if (-not (Test-Path -Path $Path)) {
        if ($WhatIfPreference) {
            Write-InstallLog -text "Would process Autodesk Deployment files in $Path (WhatIf mode)" -Info
            return
        }

        Write-InstallLog -text "Path not found: $Path" -Fail
        return
    }

    # Get the Autodesk Products from the path
    $adskProducts = @((Get-ChildItem -Directory -Path $Path) | Where-Object { $_.Name -like "*$($Version)*" })
    if ($adskProducts.Count -eq 0) {
        # If the deployment folder does not contain a versioned product subfolder,
        # treat the provided path itself as the deployment root.
        Write-InstallLog -text "No Autodesk Products found in $Path (falling back to path itself)" -Info
        $adskProducts = @([pscustomobject]@{ FullName = $Path })
    }
    else {
        Write-InstallLog -text "Autodesk Products found: $($adskProducts.Name -join ', ')" -Info
    }

    foreach ($adskProduct in $adskProducts) {

        # get xml file
        $xmlPath = [System.IO.Path]::Combine($adskProduct.FullName, $xmlFileName)
        [xml]$xml = Get-Content $xmlPath

        Write-InstallLog -text "Change $xmlPath file" -Info

        # set namespace
        [System.Xml.XmlNamespaceManager]$ns = New-Object System.Xml.XmlNamespaceManager $xml.NameTable
        # Use the document's default namespace (often defined on the root node)
        $ns.AddNamespace('x', $xml.DocumentElement.NamespaceURI)
        # Language Packs
        if ($Language.Length -gt 0) {
            try {

                # get all language pack nodes
                $packages = $xml.SelectNodes("//x:Package[contains(@name,'Language Pack')]", $ns)

                # delete all language packs that are not in the Language array
                # go through all packages
                foreach ($package in $packages) {
                    $packageName = $package.GetAttribute('name')
                    $delete = $true
                    # go through all languages in the Language array
                    foreach ($lang in $Language) {
                        # check if the package name contains the language
                        if ($packageName -like "*$lang*") {
                            $delete = $false
                        }
                    }
                    if ($delete) {
                        if ($PSCmdlet.ShouldProcess("Remove language package $packageName from $xmlPath")) {
                            Write-InstallLog -text "Package $packageName will be removed" -Info
                            # remove the package from the xml file
                            $package.ParentNode.RemoveChild($package) | Out-Null
                        }
                    }
                }
            }
            catch {
                Write-InstallLog -text "The language $Language could not be removed"
            }
        }
        # Remove
        if ($Remove.Length -gt 0) {
            foreach ($name in $Remove) {
                # avoid XPath injection by not interpolating user input into XPath
                # and instead filter the nodes in PowerShell.
                $packages = @($xml.SelectNodes('//x:Package', $ns)) | Where-Object {
                    $packageName = $_.GetAttribute('name')
                    $packageName -like "*$name*"
                }
                foreach ($package in $packages) {
                    $packageName = $package.GetAttribute('name')
                    if ($PSCmdlet.ShouldProcess("Remove package $packageName from $xmlPath")) {
                        Write-InstallLog -text "Package $packageName will be removed" -Info
                    }
                    # remove the package from the xml file (always, even if ShouldProcess is disabled)
                    $package.ParentNode.RemoveChild($package) | Out-Null
                }
            }
        }

        # saving changes to xml
        try {
            $xml.Save($xmlPath)
            Write-InstallLog -text "Saved changes to $xmlPath" -Info
        }
        catch {
            Write-InstallLog -text "Could not save changes to $xmlPath" -Fail
        }

    }

    # no begin/process/end blocks needed
}
function Install-CideonTool {

    <#
    .SYNOPSIS
        Installs cideon tools from the specified path.

    .DESCRIPTION
        The tools are expected to be in the subfolder "Cideon".
        The Cideon Vault Toolbox can be installed with selected features (see Parameters). All other tools will be installed with default settings.

    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Cideon". Default is the mountPath of the script.
    .PARAMETER VaultToolboxStandard
        If set, the Cideon Vault Toolbox Standard will be installed.
    .PARAMETER VaultToolboxPro
        If set, the Cideon Vault Toolbox Pro will be installed.
    .PARAMETER VaultToolboxObserver
        If set, the Cideon Vault Toolbox Observer will be installed.
    .PARAMETER VaultToolboxClassification
        If set, the Cideon Vault Toolbox Classification will be installed.
    .PARAMETER VaultToolboxUpdate
        If set, the Cideon Vault Toolbox Update will be installed.


    .EXAMPLE
        Install-CIDEONTool -VaultToolboxPro -VaultToolboxObserver -VaultToolboxClassification
        Install-CIDEONTool -VaultToolboxPro -VaultToolboxObserver -VaultToolboxClassification -Path "C:\Temp\PDC_20XX"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Path = $Global:mountPath,
        [Parameter()]
        [switch]$VaultToolboxStandard,
        [Parameter()]
        [switch]$VaultToolboxPro,
        [Parameter()]
        [switch]$VaultToolboxObserver,
        [Parameter()]
        [switch]$VaultToolboxClassification,
        [Parameter()]
        [switch]$VaultToolboxUpdate

    )
    # install updates
    # get all updates in folder

    Write-InstallLog -text 'Cideon Tools will be installed' -Info

    $filePath = [System.IO.Path]::Combine($Path, 'Cideon')
    if (-not $WhatIfPreference -or (Test-Path -Path $filePath)) {
        $files = @(Get-ChildItem -Path $filePath -Exclude @('*.txt') -File)
    }
    else {
        $files = Get-CachedFiles -Path $filePath -OperationText 'Would install CIDEON tools from' -CachedFiles $Script:CachedCideonFiles
    }

    # reorder files so that service packs will be installed at the end, otherwise there could be problems with prerequisites of the service pack installations
    $nonServicePackFiles = @($files | Where-Object { $_.Name -notlike '*servicepack*' })
    $servicePackFiles = @($files | Where-Object { $_.Name -like '*servicepack*' })
    $files = @($nonServicePackFiles + $servicePackFiles)

    if ($files.Count -eq 0) {
        return
    }

    foreach ($file in $files) {
        $arguments = '/qn'
        $featureInfo = $null
        if ($file.Name -like 'CIDEON.VAULT.TOOLBOX*') {
            $features = @()
            if ($VaultToolboxStandard) {
                $features += 'STANDARD'
            }
            if ($VaultToolboxPro) {
                $features += 'CIDEON_VAULT_TOOLBOX'
            }
            if ($VaultToolboxObserver) {
                $features += 'CIDEON_VAULT_AddOns'
            }
            if ($VaultToolboxClassification) {
                $features += 'CIDEON_INVENTOR_CLASSIFICATION_Addin'
            }
            if ($VaultToolboxUpdate) {
                $features += 'CIDEON_UPDATE_EXTENSION'
            }
            $arguments = "ADDLOCAL=$($features -join ',') /qn"

            $selectedFeatures = if ($features.Count -gt 0) {
                $features -join ','
            }
            else {
                '<none>'
            }

            $featureInfo = "Features (ADDLOCAL): $selectedFeatures"
            if ($file.Name -like '*servicepack*') {
                $featureInfo = "$featureInfo | Pakettyp: Servicepack"
            }
        }
        try {
            $actionText = "Install CIDEON Tool with arguments: $arguments"
            if ($featureInfo) {
                $actionText = "$actionText | $featureInfo"
            }

            Write-InstallLog -text "Start Installation: $($file.Name) with action: $actionText" -Info
            if ($PSCmdlet.ShouldProcess($file.Name, $actionText)) {
                Write-InstallProgress -Text "Installing CIDEON tool: $($file.Name)"
                Start-Process -FilePath $file.FullName -ArgumentList $arguments -Wait -ErrorAction Stop
                Write-InstallLog -text "Installed: $($file.Name)" -Info
            }
        }
        catch {
            Write-InstallLog -text "CIDEON Install Error for: $($file.Name): $($_.Exception.Message)" -Fail
        }


    }
}
function Disable-VaultExtension {

    <#
    .SYNOPSIS
        Deactivate Vault Extensions

    .DESCRIPTION
        Moves folder from the Extensions folder to one folder above.
    .PARAMETER Filter
        The filter for the folders to move. Default is "CIDEON.Vault*"
    .PARAMETER Version
        The version of the Autodesk Vault. Default is Version of the script.
    .PARAMETER Keep
        The name of the folder to keep. Default is @("CIDEON.Vault.Toolbox","Cideon.Vault.JobHandler","CIDEON.Vault.Explorer.PartsList")

    .EXAMPLE
        Disable-VaultExtension
        Disable-VaultExtension -Filter "CIDEON.Vault.Event*"
        Disable-VaultExtension -Keep "CIDEON.Vault.Toolbox"


    .NOTES
        Autor: Timon Först
        Datum: 07.05.2025

        Formally this was function was called Move-CIDEONToolboxUnused, but this was not a good name
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Version = $Global:Version,

        [Parameter()]
        [string]$Filter = 'CIDEON.Vault*',

        [Parameter()]
        [string[]]$Keep = @('CIDEON.Vault.Toolbox', 'Cideon.Vault.JobHandler', 'CIDEON.Vault.Explorer.PartsList')
    )
    #Get Extension folder
    $extensionPath = "C:\ProgramData\Autodesk\Vault $Version\Extensions"

    # Skip in WhatIf mode if path doesn't exist
    if ($WhatIfPreference -and -not (Test-Path -Path $extensionPath)) {
        Write-InstallLog -text "Would disable Vault extensions from $extensionPath (WhatIf mode)" -Info
        return
    }

    $Folder = Get-Item -Path $extensionPath
    # Get all folders from Standard Toolbox, filter out the folders to keep
    $FolderDisable = Get-ChildItem -Path $Folder -Directory | Where-Object { $_.Name -like $Filter } | Where-Object { $_.Name -notin $Keep }
    # Move Folders one folder obove
    foreach ($item in $FolderDisable) {
        $destination = "C:\ProgramData\Autodesk\Vault $Version"
        $destPath = [System.IO.Path]::Combine($destination, $item.Name)
        if (Test-Path -Path $destPath) {
            if ($PSCmdlet.ShouldProcess($destPath, 'Remove existing folder')) {
                Remove-Item -Path $destPath -Recurse -Force
            }
        }

        if ($PSCmdlet.ShouldProcess($item.Name, 'Disable Vault Extension')) {
            Move-Item -Path $item.FullName -Destination $destination -Force
        }
    }

}
function Get-RealUserName {
    <#
    .SYNOPSIS
        Gets the real user name of the current user, even when the script runs elevated.

    .DESCRIPTION
        When the current PowerShell session runs as Administrator (or as a different user),
        the environment variable $env:USERNAME may return the admin account instead of the
        interactively logged-on user.  This function inspects the owner of the explorer.exe
        process to determine the actual desktop user name.

        If no elevated session is detected or no explorer.exe owner can be resolved, the
        function falls back to $env:USERNAME.

    .EXAMPLE
        $user = Get-RealUserName
        # Returns e.g. 'john.doe' even when running as local admin.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param ()

    begin {}

    process {
        try {
            $normalUserName = $null

            if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                # Temporarily disable WhatIf for CIM operations
                $originalWhatIf = $WhatIfPreference
                $WhatIfPreference = $false

                try {
                    $explorerUsers = @()
                    Get-Process -Name explorer -ErrorAction SilentlyContinue | ForEach-Object {
                        $procCim = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue
                        if ($procCim) {
                            $ownerInfo = Invoke-CimMethod -InputObject $procCim -MethodName GetOwner -ErrorAction SilentlyContinue
                            if ($ownerInfo -and $ownerInfo.User) {
                                $fullUserName = "$($ownerInfo.Domain)\$($ownerInfo.User)"
                                if ($fullUserName -ne "$env:USERDOMAIN\$env:USERNAME" -and $fullUserName -notlike '*SYSTEM*' -and $fullUserName -notlike '*NT AUTHORITY*') {
                                    if ($fullUserName -notin $explorerUsers) {
                                        $explorerUsers += $fullUserName
                                    }
                                }
                            }
                        }
                    }

                    if ($explorerUsers.Count -gt 0) {
                        $normalUserName = $explorerUsers[0].Split('\')[-1]
                    }
                }
                finally {
                    # Restore original WhatIf preference
                    $WhatIfPreference = $originalWhatIf
                }

                if ([String]::IsNullOrEmpty($normalUserName)) {
                    $normalUserName = $env:USERNAME
                }
            }
            else {
                $normalUserName = $env:USERNAME
            }
        }
        catch {
            Write-InstallLog -text "Could not determine normal user name: $($_.Exception.Message)" -Fail
            return $env:USERNAME
        }
    }

    end {
        Write-InstallLog -text "Normal User Name is $normalUserName" -Info
        return $normalUserName
    }
}

function Get-UserSID {
    <#
    .SYNOPSIS
        Gets the SID of the specified user.
    .DESCRIPTION
        Gets the SID of the specified user. If the user is a domain user, the SID will be returned in the format DOMAIN\UserName.
        If the user is a local user, the SID will be returned in the format S-1-5-21-...-UserName.
    .PARAMETER UserName
        The name of the user to get the SID for. If not specified, the current user will be used.
    .PARAMETER DomainUser
        If set, the user is a domain user. The SID will be returned in the format DOMAIN\UserName.
    .PARAMETER LocalUser
        If set, the user is a local user. The SID will be returned in the format S-1-5-21-...-UserName.
    .EXAMPLE
        Get-UserSID -UserName "JohnDoe" -DomainUser
        Get-UserSID -UserName "JohnDoe" -LocalUser
        Get-UserSID -UserName "JohnDoe"
        Get-UserSID

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param (
        [string]$UserName,
        [switch]$DomainUser,
        [switch]$LocalUser
    )

    begin {
        # validate that $DomainUser or $LocalUser is set, but not both
        if ($DomainUser.IsPresent -and $LocalUser.IsPresent) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new('You can only set one of the parameters DomainUser or LocalUser'),
                'InvalidUserTypeCombination',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $null
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        # validate that $DomainUser or $LocalUser is set, if not, set $DomainUser to true
        if (-not $DomainUser.IsPresent -and -not $LocalUser.IsPresent) {
            $DomainUser = $true
        }

        if (-not $UserName) {
            $UserName = Get-RealUserName
        }
        if ($DomainUser.IsPresent) {
            $UserDomain = [System.IO.Path]::Combine($env:USERDOMAIN, $UserName)
        }
    }

    process {

        if ($LocalUser.IsPresent) {
            $sid = (Get-LocalUser $UserName).SID.Value
        }
        else {
            $sid = (New-Object System.Security.Principal.NTAccount($UserDomain)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        }
    }

    end {
        return $sid
    }
}
function Set-InventorProjectFile {
    <#
    .SYNOPSIS
        Sets the Inventor Project File Path in the registry for the current user.
    .DESCRIPTION
        Sets the Inventor Project File Path in the registry for the current user.
        The registry key is created if it does not exist. If the key already exists, the value is updated.
    .PARAMETER Version
        The version of Autodesk Inventor. Default is the Version of the script.
    .PARAMETER File
        The path to the Inventor Project File. Default is "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj".
    .EXAMPLE
        Set-InventorProjectFile -Version "2024" -File "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj"
        Set-InventorProjectFile -File "C:\Vault_Work\CDN_Vault\CDN_Vault.ipj"
        Set-InventorProjectFile

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string]$Version = $Global:Version,
        [string]$File = 'C:\Vault_Work\CDN_Vault\CDN_Vault.ipj'
    )

    begin {
        # The ProductVersion is e.g. 2024, the registry key is 28.0
        # We take the last two digits of the Version
        [int]$RegistryVersion = $Version.Substring($Version.Length - 2)
        #After that we add the 2.0 to it, so we get 28.0 for 2024.
        $RegistryVersion += 4

        # Get the SID of the current user
        $sid = Get-UserSID -DomainUser

        $regPath = "Registry::HKEY_USERS\$sid\Software\Autodesk\Inventor\RegistryVersion$($RegistryVersion).0\System\Preferences\ExternalReferences"

    }

    process {
        if ($PSCmdlet.ShouldProcess("$regPath", "Set Inventor Project File Path to $File")) {
            # Check if the registry key exists, if not, create it
            if (-not (Test-Path -Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            # Set the Registry PathFile value to the specified regPath. check before if PathFile it exists, then we set it, instead of creating it
            if (-not (Get-ItemProperty -Path $regPath -Name 'PathFile' -ErrorAction SilentlyContinue)) {
                New-ItemProperty -Path $regPath -Name 'PathFile' -Value $File -PropertyType String -Force | Out-Null
            }
            else {
                Set-ItemProperty -Path $regPath -Name 'PathFile' -Value $File | Out-Null
            }
        }
    }

    end {

    }
}
function Remove-UserSystemVariable {
    <#
    .SYNOPSIS
        Removes user environment variables from the current user's registry hive.

    .DESCRIPTION
        Resolves the current user SID and removes the specified variables from
        `HKEY_USERS\<SID>\Environment` when they exist.

    .PARAMETER Name
        One or more user environment variable names to remove.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string[]]$Name
    )

    begin {
        # Get the SID of the current user
        $sid = Get-UserSID -DomainUser

        $regPath = "Registry::HKEY_USERS\$sid\Environment"
    }

    process {
        foreach ($var in $Name) {
            # Check if the variable exists, if so, remove it
            if ((Get-ItemProperty -Path $regPath).$var) {
                if ($PSCmdlet.ShouldProcess("Remove user system variable $var from $regPath")) {
                    Write-InstallLog -text "Removing User System Variable: $var" -Info
                    Remove-ItemProperty -Path $regPath -Name $var -Force | Out-Null
                }
            }
            else {
                Write-InstallLog -text "User System Variable: $var does not exist" -Info
            }
        }
    }

    end {

    }
}
function Copy-Local {
    <#
    .SYNOPSIS
        Copies local files from the specified path to the local machine.

    .DESCRIPTION
        Copies local files from the specified path to the local machine. The files are expected to be in the subfolder "Local".
        Subfolders "ProgramData" and "Users" will be copied to the root of C:\.
        The folder "Users\USERNAME" will be renamed to the actual username. There is a special handling for the USERNAME folder.
        If the script is running with admin rights, the script checks the "explorer.exe" process to find out what the normal user name is.
        !IMPORTANT! The normal User must be logged in and the script must be started with admin rights (optionally runs as another user).

    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Local". Default is the mountPath of the script.
    .PARAMETER SourceFolder
        Optional. The name of the subfolder to copy from the Local folder. Default is all subfolders.
    .PARAMETER TargetFolder
        Optional. The target folder where the files should be copied to. Default is C:\ for each SourceFolder.
    .EXAMPLE
        Copy-Local -SourceFolder "ProgramData" -TargetFolder "C:\"
        Copy-Local -Path "C:\Temp\PDC_20XX" -SourceFolder @("ProgramData", "Users") -TargetFolder @("C:\", "C:\")

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Copy-CIDEONTools, but this was not a good name, because it is not only copying CIDEON Tools, but also the local files.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Path = $Global:mountPath,
        [Parameter()]
        [string[]]$SourceFolder,
        [Parameter()]
        [string[]]$TargetFolder
    )
    begin {
        $usingCachedSource = $false

        # if sourcefolder is empty, use all folders in the Local folder
        if (-not $SourceFolder) {
            $localPath = [System.IO.Path]::Combine($Path, 'Local')
            if (-not $WhatIfPreference -or (Test-Path -Path $localPath)) {
                $SourceFolder = Get-ChildItem -Path $localPath -Directory | Select-Object -ExpandProperty Name
            }
            else {
                $cachedSource = Get-CachedFiles -Path $localPath -OperationText 'Would copy local files from' -CachedFiles $Script:CachedLocalFolders
                $SourceFolder = @($cachedSource | Select-Object -ExpandProperty Name)
                $usingCachedSource = $SourceFolder.Count -gt 0
                if ($SourceFolder.Count -eq 0) {
                    return
                }
            }
        }
        # if targetfolder is empty, use for each sourcefolder C:\ as target
        if (-not $TargetFolder) {
            $TargetFolder = @('C:\') * $SourceFolder.Count
        }
        # if targetfolder count is not equal to sourcefolder count, throw an error
        if ($SourceFolder.Count -ne $TargetFolder.Count) {
            Write-InstallLog -text 'Source and Target quantities must be the same' -Fail
            return
        }

    }
    process {
        try {
            Write-InstallLog -text 'Local Folders will be copied' -Info

            #check if the array sizes from source and target are the same

            # copy
            foreach ($Source in $SourceFolder) {
                $localpath = [System.IO.Path]::Combine($Path, 'Local', $Source)
                Write-InstallLog -text "Local folder $Source" -Info

                # exception for Users folder, because we have to copy it to the user profile folder
                if ($Source -eq 'Users') {
                    if ($usingCachedSource -and $WhatIfPreference) {
                        if ($PSCmdlet.ShouldProcess($localpath, 'Copy user folder to: C:\Users')) {
                            # Simulation only in WhatIf mode
                        }
                        continue
                    }

                    # get subfolders in Users folder
                    $UsersFolder = Get-ChildItem -Path $localpath -Directory

                    # for every subfolder in Users
                    foreach ($userFolder in $UsersFolder) {

                        # check folder USERNAME, this is the folder for the current user
                        if ($userFolder.Name -eq 'USERNAME') {
                            $subFolder = Get-RealUserName
                        }
                        # if the userFolder is not USERNAME, we use the folder name as subfolder
                        else {
                            $subFolder = $userFolder.Name
                        }
                        # copy the user folder to the target folder
                        $copyDestination = [System.IO.Path]::Combine($($TargetFolder[$($SourceFolder.IndexOf($Source))]), 'Users', $subFolder)
                        if ($PSCmdlet.ShouldProcess($userFolder.FullName, "Copy user folder to: $copyDestination")) {
                            Copy-Item -Path ([System.IO.Path]::Combine($userFolder.FullName, '*')) -Destination $copyDestination -Force -Recurse
                        }
                    }



                }
                # normal case for ProgramData and other folders
                else {
                    $targetPath = $TargetFolder[$($SourceFolder.IndexOf($Source))]
                    if ($PSCmdlet.ShouldProcess($localpath, "Copy folder to: $targetPath")) {
                        Copy-Item -Path $localpath -Destination $targetPath -Force -Recurse
                    }
                }
            }


            Write-InstallLog -text 'Local Folders is done' -Info

        }

        catch {
            Write-InstallLog -text "Local Folders error for path $($Source): $($_.Exception.Message)" -Fail
        }
    }
    end {
        # nothing to do here
    }





}
function Uninstall-Program {
    <#
    .SYNOPSIS
        Uninstalls the specified software from the local machine.

    .DESCRIPTION
        Uninstalls the specified software from the local machine.
        The software is expected to be installed with the specified publisher and display name.

    .PARAMETER DisplayName
        The display name of the software to uninstall.
    .PARAMETER Publisher
        The publisher of the software to uninstall.
    .PARAMETER FilterOperator
        The filter operator for the display name. Default is -match.

    .EXAMPLE
        Uninstall-Program -DisplayName "Inventor" -Publisher "Autodesk"
        Uninstall-Program -Publisher "CIDEON"
        Uninstall-Program -DisplayName "Autodesk Inventor Professional 2022" -Publisher "Autodesk" -FilterOperator "-eq"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$DisplayName,
        [Parameter()]
        [string]$Publisher,
        [Parameter(Mandatory = $false, HelpMessage = 'Filter Operator for DisplayName. Default is -match')]
        [ValidateSet('-match', '-notmatch', '-eq', '-like', '-notlike', '-gt', '-lt', '-ge', '-le')]
        [string]$FilterOperator = '-match'
    )
    if ($Publisher -eq '' -and $DisplayName -eq '') {
        Write-InstallLog -text 'No Software or Publisher specified to uninstall' -Fail
        return
    }
    $installedProducts = Get-InstalledProgram -Publisher $Publisher -DisplayName $DisplayName -FilterOperator $FilterOperator
    foreach ($installedProduct in $installedProducts) {
        try {

            # Write-InstallLog -text "$($installedProduct) will be uninstalled" -Info
            # gets the string before the first / - this is the exe filepath
            $uninstaller = $installedProduct.UninstallString
            # msiexec with / arguments
            if ($uninstaller -match '/') {
                $filePath = ($installedProduct.UninstallString -split '/' , 2)[0].Trim()
                # gets the string after the first / - these are the arguments
                # we have to add the first / again, and put quiet after the additional arguments
                $arguments = '/' + $(($installedProduct.UninstallString -split '/' , 2)[1].Trim()) + ' /quiet /passive'
            }
            else {
                # ODIS Uninstaller with - arguments
                $filePath = ($installedProduct.UninstallString -split '-' , 2)[0].Trim()
                $arguments = '-' + $(($installedProduct.UninstallString -split '-' , 2)[1].Trim()) + ' -q'
            }

            if ($PSCmdlet.ShouldProcess($installedProduct.DisplayName, "Uninstall with command: $filePath $arguments") -and
                -not [string]::IsNullOrWhiteSpace($filePath)) {
                Write-InstallProgress -Text "Uninstalling program: $($installedProduct.DisplayName)"
                Start-Process -NoNewWindow -FilePath $filePath -ArgumentList $arguments -Wait
            }
        }
        catch {
            Write-InstallLog -text "$($installedProduct.DisplayName) could not be uninstalled" -Fail
        }
    }
}
function Get-InstalledProgram {
    <#
    .SYNOPSIS
        Retrieves the installed software from the local machine.

    .DESCRIPTION
        Retrieves the installed software from the local machine.
        The software is expected to be installed with the specified publisher and display name.


    .PARAMETER DisplayName
        The display name of the software
    .PARAMETER Publisher
        The publisher of the software
    .PARAMETER FilterOperator
        The filter operator for the display name. Default is -match.

    .EXAMPLE
        Get-InstalledProgram -DisplayName "Inventor" -Publisher "Autodesk"
        Get-InstalledProgram -Publisher "CIDEON"
        Get-InstalledProgram -DisplayName "Autodesk Inventor Professional 2022" -Publisher "Autodesk" -FilterOperator "-eq"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>

    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$DisplayName,
        [Parameter()]
        [string]$Publisher,
        [Parameter(Mandatory = $false, HelpMessage = 'Filter Operator for DisplayName. Default is -match')]
        [ValidateSet('-match', '-notmatch', '-eq', '-like', '-notlike', '-gt', '-lt', '-ge', '-le')]
        [string]$FilterOperator = '-match'
    )

    Set-StrictMode -Off | Out-Null
    switch ($FilterOperator) {
        '-match' { $WhereScriptBlock = { $_.DisplayName -match $DisplayName -and $_.Publisher -match $Publisher } }
        '-notmatch' { $WhereScriptBlock = { $_.DisplayName -notmatch $DisplayName -and $_.Publisher -match $Publisher } }
        '-eq' { $WhereScriptBlock = { $_.DisplayName -eq $DisplayName -and $_.Publisher -match $Publisher } }
        '-like' { $WhereScriptBlock = { $_.DisplayName -like $DisplayName -and $_.Publisher -match $Publisher } }
        '-notlike' { $WhereScriptBlock = { $_.DisplayName -notlike $DisplayName -and $_.Publisher -match $Publisher } }
        '-gt' { $WhereScriptBlock = { $_.DisplayName -gt $DisplayName -and $_.Publisher -match $Publisher } }
        '-lt' { $WhereScriptBlock = { $_.DisplayName -lt $DisplayName -and $_.Publisher -match $Publisher } }
        '-ge' { $WhereScriptBlock = { $_.DisplayName -ge $DisplayName -and $_.Publisher -match $Publisher } }
        '-le' { $WhereScriptBlock = { $_.DisplayName -le $DisplayName -and $_.Publisher -match $Publisher } }
    }
    $installedPrograms = Get-ItemProperty -Path $(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction 'SilentlyContinue' | Where-Object $WhereScriptBlock | Select-Object -Property 'Publisher', 'DisplayName', 'DisplayVersion', 'UninstallString', 'ModifyPath' | Sort-Object -Property 'DisplayName' -Unique
    return $installedPrograms
}
function Set-CIDEONLanguageVariable {
    <#
    .SYNOPSIS
        Sets CIDEON language-related machine environment variables based on system locale.

    .DESCRIPTION
        Detects the Windows system locale and sets `CDN_LNG` and `CDN_ITEM_LNG`
        to predefined values.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ()
    #TODO: This is not properly working, because the basic language of windows is always en-US, but the user language is different.
    #Set PC Variables from Language
    #(Get-UICulture).Name
    #(Get-Culture).Name
    $lngenv = Get-WinSystemLocale | Select-Object -ExpandProperty Name
    Write-InstallLog -text "Set language Variables for $lngenv" -Info
    switch ($lngenv) {
        'de-DE' {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for de-DE')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'de-DE', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'AT', 'Machine')
            }
        }
        'de-AT' {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for de-AT')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'de-DE', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'AT', 'Machine')
            }
        }
        'cz-CZ' {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for cz-CZ')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'CZ', 'Machine')
            }
        }
        'en-GB' {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for en-GB')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'UK', 'Machine')
            }
        }
        'pl-PL' {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for pl-PL')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'PL', 'Machine')
            }
        }
        'nl-NL' {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for nl-NL')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'NL', 'Machine')
            }
        }
        default {
            if ($PSCmdlet.ShouldProcess('Set CDN_LNG and CDN_ITEM_LNG for Default')) {
                [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
                [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'UK', 'Machine')
            }
        }
    }
}
function Set-CIDEONVariable {
    <#
    .SYNOPSIS
        Sets the CIDEON environment variables for the specified version.

    .DESCRIPTION
        Set the CDN_PROGRAMDATA, CDN_PROGRAM_DIR, and CDN_VAULT_EXTENSIONS environment variables for the specified version.

    .PARAMETER Version
        The version of the Autodesk Vault

    .EXAMPLE
        Set-CIDEONVariable -Version "2024"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Version = $Global:Version
    )
    Write-InstallLog -text 'Set CIDEON Variables' -Info

    $CDN_VAULT_EXTENSIONS = "C:\ProgramData\Autodesk\Vault $($Version)\Extensions\"

    if ($PSCmdlet.ShouldProcess('Environment', 'Set CDN_PROGRAMDATA, CDN_PROGRAM_DIR, CDN_VAULT_EXTENSIONS')) {
        [System.Environment]::SetEnvironmentVariable('CDN_PROGRAMDATA', 'C:\ProgramData\CIDEON\', 'Machine')
        [System.Environment]::SetEnvironmentVariable('CDN_PROGRAM_DIR', 'C:\Program Files\CIDEON\', 'Machine')
        [System.Environment]::SetEnvironmentVariable('CDN_VAULT_EXTENSIONS', $CDN_VAULT_EXTENSIONS, 'Machine')
    }
}
function Rename-RegistryInstallationPath {

    <#
    .SYNOPSIS
        Changes the installation path in the registry for the Autodesk software.

    .DESCRIPTION
        Because of the installation locally from wim, the installation path in the registry is not correct, if the clients wants to repair a installation.
        This function changes the installation path in the registry to the server path.

    .EXAMPLE
        Rename-RegistryInstallationPath

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ()

    # if your repair the autodesk software, it will look localy to the wim
    # we change this to the serverpath
    $RegistryPath = 'HKLM:\SOFTWARE\Classes\Installer\Products'
    $Registry = Get-ChildItem $RegistryPath -Recurse
    $SearchQuery = [System.IO.Path]::Combine($mountPath, 'image')
    $NewValue = [System.IO.Path]::Combine($Path, [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name) , 'image')

    Write-InstallLog -text 'Reg Change' -Info

    foreach ($registryItem in $Registry) {
        foreach ($propertyName in $registryItem.Property) {
            $currentValue = $registryItem.GetValue($propertyName)
            if ($currentValue -notlike "*$SearchQuery*") {
                continue
            }

            $replacedValue = $currentValue.Replace($SearchQuery, $NewValue)
            Write-InstallLog -text "$registryItem\$propertyName" -Info
            Write-InstallLog -text "From '$currentValue' to '$replacedValue'" -Info

            if ($PSCmdlet.ShouldProcess($registryItem.PSPath, 'Update registry path')) {
                Set-ItemProperty -Path $registryItem.PSPath -Name $propertyName -Value $replacedValue
            }
        }
    }
}
function Copy-WIM {
    <#
    .SYNOPSIS
        Copies the WIM file from the network share to the local machine.

    .DESCRIPTION
        Copies the specified WIM file from the network share to the local folder so that
        it can be mounted locally for faster installation.  When the NoDownload switch is
        active the copy is skipped and the original server path is returned instead.

    .PARAMETER File
        System.IO.FileInfo or String (full path) of the WIM file.

    .PARAMETER Folder
        The folder to copy the WIM file to.  Default is the LocalFolder variable.

    .EXAMPLE
        Copy-WIM
        Copy-WIM -File '\\server\share\PDC_2026.wim' -Folder 'C:\Temp'

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (

        [Parameter()]
        $File,
        [Parameter()]
        [string]$Folder
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('File') -or $null -eq $File) {
            $wimFileVar = Get-Variable -Name 'wimFile' -Scope Global -ErrorAction SilentlyContinue
            if ($wimFileVar) { $File = $wimFileVar.Value }
        }
        if (-not $PSBoundParameters.ContainsKey('Folder') -or [string]::IsNullOrWhiteSpace($Folder)) {
            $localFolderVar = Get-Variable -Name 'LocalFolder' -Scope Global -ErrorAction SilentlyContinue
            if ($localFolderVar) { $Folder = $localFolderVar.Value }
        }
        # Resolve NoDownload from global context
        $noDownloadVar = Get-Variable -Name 'NoDownload' -Scope Global -ErrorAction SilentlyContinue
        $noDownload = if ($noDownloadVar) { $noDownloadVar.Value } else { [System.Management.Automation.SwitchParameter]$false }

        # check if File is a string, then get the file from the path
        if ($File -is [string]) {
            $File = Get-Item -Path $File
        }
        # local wim filepath
        $localwimFile = [System.IO.Path]::Combine($Folder, $File.Name)
    }

    process {

        # copy wim to local path
        if ($noDownload.IsPresent) {
            Write-InstallLog -text 'No Download of WIM file to local folder. Mounting from server.' -Info
            # mount wim from network
            $localwimFile = $File.FullName
        }
        else {
            # check if wim file exists
            if ([System.IO.File]::Exists($localwimFile)) {
                Write-InstallLog -text 'WIM file already exists, no download needed' -Info
            }
            else {
                if ($PSCmdlet.ShouldProcess($File.FullName, "Copy WIM to $Folder")) {
                    Write-InstallLog -text "Copy $($File.FullName) to $Folder" -Info
                    Copy-Item $File.FullName $Folder -Force
                    Write-InstallLog -text 'WIM file copied' -Info
                }
            }
        }
    }

    end {
        # Update global wimFile context so Mount-WIM picks up the local copy
        $resolvedFile = if ($WhatIfPreference) {
            if ($noDownload.IsPresent) {
                $File
            }
            elseif (Test-Path -Path $localwimFile) {
                Get-Item -Path $localwimFile
            }
            else {
                $File
            }
        }
        else {
            Get-Item -Path $localwimFile
        }

        Set-InstallContext -Context @{ wimFile = $resolvedFile }
    }
}
function Mount-WIM {

    <#
    .SYNOPSIS
        Mounts the specified WIM file to the specified path.

    .DESCRIPTION
        Mounts the specified WIM file to the local mount path.  In WhatIf mode the WIM is
        mounted read-only to a temporary directory for inspection purposes, the inspection
        cache is populated and the mount reference is stored in $script:InspectMount so that
        Invoke-DeploymentWorkflow can dismount it in its finally block.

    .PARAMETER File
        System.IO.FileInfo or String (full path) of the WIM file.

    .PARAMETER Path
        The path to mount the WIM file to.

    .EXAMPLE
        Mount-WIM
        Mount-WIM -File 'C:\Temp\PDC_2026.wim' -Path 'C:\Temp\mount_PDC_2026'

    .NOTES
        Autor: Timon Först
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        $File,
        [Parameter()]
        [string]$Path
    )
    begin {
        if (-not $PSBoundParameters.ContainsKey('File') -or $null -eq $File) {
            $wimFileVar = Get-Variable -Name 'wimFile' -Scope Global -ErrorAction SilentlyContinue
            if ($wimFileVar) { $File = $wimFileVar.Value }
        }
        if (-not $PSBoundParameters.ContainsKey('Path') -or [string]::IsNullOrWhiteSpace($Path)) {
            $mountPathVar = Get-Variable -Name 'mountPath' -Scope Global -ErrorAction SilentlyContinue
            if ($mountPathVar) { $Path = $mountPathVar.Value }
        }
        # check if File is a string, then get the file from the path
        if ($File -is [string]) {
            $File = Get-Item -Path $File
        }
    }
    process {
        # WhatIf mode: mount read-only for inspection and cache content
        if ($WhatIfPreference) {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                Write-InstallLog -text 'WhatIf mode: WIM inspection requires elevated rights. Start PowerShell as Administrator to see file details.' -Info
                return
            }

            $tempMount = [System.IO.Path]::Combine($env:TEMP, "WIM_Inspect_$(Get-Random)")
            $mounted = $false
            try {
                New-Item -Path $tempMount -ItemType Directory -Force -WhatIf:$false | Out-Null
                Mount-WindowsImage -ImagePath $File.FullName -Index 1 -Path $tempMount -ReadOnly -ErrorAction Stop | Out-Null
                $mounted = $true
                Write-InstallLog -text 'WIM mounted read-only for inspection' -Info
                Update-WIMInspectionCache -MountedPath $tempMount

                $script:InspectMount = [pscustomobject]@{
                    ImagePath = $File.FullName
                    Path      = $tempMount
                }
            }
            catch {
                Write-InstallLog -text "WhatIf mode: WIM inspection skipped - $($_.Exception.Message)" -Info
                if (-not $mounted -and (Test-Path -Path $tempMount)) {
                    Remove-Item -Path $tempMount -Force -Recurse -ErrorAction SilentlyContinue -WhatIf:$false
                }
            }
            return
        }

        # Normal mode: mount WIM
        if ($PSCmdlet.ShouldProcess($File.FullName, "Mount WIM to $Path")) {
            Mount-WindowsImage -ImagePath $File.FullName -Index 1 -Path $Path | Out-Null
            Write-InstallLog -text "WIM $File.FullName mounted to $Path" -Info
        }

        # check if configfile exists
        foreach ($ConfigFullFilename in $ConfigFullFilenames) {
            if (-not [System.IO.File]::Exists($ConfigFullFilename)) {
                Write-InstallLog -text "ConfigFile $ConfigFullFilename does not exist" -Fail
                throw "ConfigFile $ConfigFullFilename does not exist"
            }
        }
    }

    end {
        # nothing to do here
    }
}
function Dismount-WIM {
    <#
    .SYNOPSIS
        Dismounts the specified WIM file to the specified path.

    .DESCRIPTION
        Dismounts the specified WIM file to the specified path. The WIM file is expected to be in the specified path.

    .PARAMETER Name
        The name of the WIM file to dismount, WIHOUT extension.
    .PARAMETER purge
        If set, the local WIM file will be deleted after dismounting.
    .PARAMETER all
        If set, all WIM files will be dismounted, instead of NAME Parameter.

    .EXAMPLE
        Dismount-WIM -Name "PDC_20XX" -purge
        Dismount-WIM -all

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Dismount-ADSKwim, but this was not a good name.
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        $File,
        [Parameter()]
        [switch]$all,
        [Parameter()]
        [switch]$purge
    )
    begin {
        if (-not $PSBoundParameters.ContainsKey('File') -or $null -eq $File) {
            $wimFileVar = Get-Variable -Name 'wimFile' -Scope Global -ErrorAction SilentlyContinue
            if ($wimFileVar) { $File = $wimFileVar.Value }
        }
        if ($File -is [string]) {
            $File = Get-Item -Path $File
        }
    }
    process {

        if (-not $File -and -not $all.IsPresent ) {
            Write-InstallLog -text 'No WIM specified to dismount' -Fail
            return
        }

        $images = @()
        if ($File -and $File.PSObject.Properties['ImagePath'] -and $File.PSObject.Properties['Path']) {
            $images = @([pscustomobject]@{ ImagePath = $File.ImagePath; Path = $File.Path })
        }
        elseif ($WhatIfPreference) {
            if ($all.IsPresent) {
                $images = @([pscustomobject]@{ ImagePath = 'ALL_MOUNTED_WIMS'; Path = '<all-mounted-paths>' })
            }
            else {
                $displayPath = if ($File.PSObject.Properties['FullName']) { $File.FullName } else { "$File" }
                $mountPathVar = Get-Variable -Name 'mountPath' -Scope Global -ErrorAction SilentlyContinue
                $resolvedMountPath = if ($mountPathVar) { $mountPathVar.Value } else { $null }
                $images = @([pscustomobject]@{ ImagePath = $displayPath; Path = $resolvedMountPath })
            }
        }
        else {
            if ($all.IsPresent) {
                $images = @(Get-WindowsImage -Mounted | Where-Object { $_.MountStatus -eq 'Ok' })
            }
            else {
                $images = @(Get-WindowsImage -Mounted | Where-Object { $_.ImagePath -like "*$File*" })
            }
        }

        if ($images.Count -eq 0) {
            Write-InstallLog -text 'No mounted WIM images found to dismount' -Info
            return
        }

        foreach ($image in $images) {
            Write-InstallLog -text "Dismounting WIM $($image.ImagePath)" -Info
            try {
                if ($PSCmdlet.ShouldProcess($image.ImagePath, 'Dismount WIM')) {
                    if ($WhatIfPreference) {
                        continue
                    }

                    $dismountErrors = @()
                    Dismount-WindowsImage -Path $image.Path -Discard -ErrorAction SilentlyContinue -ErrorVariable dismountErrors | Out-Null

                    $hasIncompleteUnmountWarning = $false
                    if ($dismountErrors.Count -gt 0) {
                        $dismountErrorMessages = @($dismountErrors | ForEach-Object { $_.ToString() })
                        $hasIncompleteUnmountWarning = @($dismountErrorMessages | Where-Object { $_ -match 'could not be completely unmounted' }).Count -gt 0

                        if (-not $hasIncompleteUnmountWarning) {
                            throw ($dismountErrors[0])
                        }

                        Write-InstallLog -text "WIM $($image.ImagePath) could not be completely unmounted and will be ignored; cleanup will run after reboot if needed" -Info
                        Register-WIMDismountTask
                    }

                    if ($hasIncompleteUnmountWarning) {
                        continue
                    }

                    Write-InstallLog -text "WIM $($image.ImagePath) dismounted" -Info

                    if ($purge.IsPresent) {
                        # delete local wim file
                        if ($PSCmdlet.ShouldProcess($image.ImagePath, 'Delete WIM file')) {
                            Remove-Item -Path $image.ImagePath -Force
                            Write-InstallLog -text "WIM $($image.ImagePath) locally deleted" -Info
                        }
                    }
                    if ($PSCmdlet.ShouldProcess($image.Path, 'Delete mount directory')) {
                        Remove-Item -Path $image.Path -Force -Recurse
                    }
                }
            }
            catch {
                Register-WIMDismountTask
            }

        }
    }
    end {

    }


}
function Register-WIMDismountTask {
    <#
    .SYNOPSIS
        Registers a scheduled task to dismount the WIM file after a reboot.

    .DESCRIPTION
        Registers a scheduled task to dismount the WIM file after a reboot. This is used if the WIM file could not be dismounted cleanly.

    .EXAMPLE
        Register-WIMDismountTask

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Register-ADSKwimDismountTask, but this was not a good name.
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ()

    ## failed to cleanly dismount, so set a task to cleanup after reboot
    Write-InstallLog -text "WIM $WIM failed to dismounted" -Fail

    $STAction = New-ScheduledTaskAction `
        -Execute 'Powershell.exe' `
        -Argument '-NoProfile -WindowStyle Hidden -command "& {Get-WindowsImage -Mounted | Where-Object {$_.MountStatus -eq ''Invalid''} | ForEach-Object {$_ | Dismount-WindowsImage -Discard -ErrorVariable wimerr; if ([bool]$wimerr) {$errflag = $true}}; If (-not $errflag) {Clear-WindowsCorruptMountPoint; Unregister-ScheduledTask -TaskName ''CleanupWIM'' -Confirm:$false}}"'

    $STTrigger = New-ScheduledTaskTrigger -AtStartup

    if ($PSCmdlet.ShouldProcess('CleanupWIM', 'Register scheduled task for WIM cleanup')) {
        Register-ScheduledTask `
            -Action $STAction `
            -Trigger $STTrigger `
            -TaskName 'CleanupWIM' `
            -Description 'Clean up WIM Mount points that failed to dismount properly' `
            -User 'NT AUTHORITY\SYSTEM' `
            -RunLevel Highest `
            -Force
    }
}
function Set-AutodeskUpdate {
    <#
    .SYNOPSIS
        Sets the Autodesk update settings in the registry.
    .DESCRIPTION
        Sets the Autodesk update settings in the registry. This is used to enable or disable or shows only the updates.
    .PARAMETER Enable
        Enables the installation of updates.
    .PARAMETER ShowOnly
        Shows the updates, but the user cannot install them.
    .PARAMETER Disable
        Disables the installation of updates.
    .EXAMPLE
        Set-AutodeskUpdate -Enable
        Set-AutodeskUpdate -ShowOnly
        Set-AutodeskUpdate -Disable
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # Enables Installation for user
        [Parameter()]
        [Switch]
        $Enable,

        # Shows Updates, but user cannot install
        [Parameter()]
        [Switch]
        $ShowOnly,
        # User cannot see or install updates
        [Parameter()]
        [Switch]
        $Disable
    )
    # Set Values Switch
    if ($Enable) {
        $Value = 0
    }
    if ($ShowOnly) {
        $Value = 2
    }
    if ($Disable) {
        $Value = 1
    }
    # Path to Registry
    $ODISPath = 'HKCU:\SOFTWARE\Autodesk\ODIS'

    if ($PSCmdlet.ShouldProcess("$ODISPath", "Set DisableManualUpdateInstall to $Value")) {
        # Check if ODIS Key exists
        if (!(Test-Path $ODISPath)) {
            #create
            $ODIS = New-Item -Path $ODISPath
            Write-InstallLog -text "Created $ODISPath" -Info
        }
        else {
            #Get
            $ODIS = Get-Item -Path $ODISPath
        }
        # Check if Property exists
        if ($null -eq (Get-ItemProperty -Path $ODIS.PSPath -Name 'DisableManualUpdateInstall' -ErrorAction SilentlyContinue)) {
            #create
            New-ItemProperty -Path $ODIS.PSPath -Name 'DisableManualUpdateInstall' -Value $Value -PropertyType 'DWORD' | Out-Null
            Write-InstallLog -text "Created $($ODIS.PSPath)\DisableManualUpdateInstall with $Value" -Info
        }
        else {
            #set
            Set-ItemProperty -Path $ODIS.PSPath -Name 'DisableManualUpdateInstall' -Value $Value | Out-Null
            Write-InstallLog -text "Set $($ODIS.PSPath)\DisableManualUpdateInstall to $Value" -Info
        }
    }
}


function Get-AppLogError {
    <#
    .SYNOPSIS
        Retrieves recent MSI-related errors from the Windows Application event log.

    .DESCRIPTION
        Filters Application log entries since the given start time for provider `MsiInstaller`
        and writes matching errors into the installation log.

    .PARAMETER Start
        Start time used to search for recent errors.

    .NOTES
        Autor: Timon Först
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = 'Starttime where to search for errors')]
        [datetime]$Start = (Get-Date).AddHours(-1)
    )

    begin {

        # Check Windows Application logs for errors
        $logErrors = Get-WinEvent -LogName Application -ErrorAction SilentlyContinue | Where-Object { $_.LevelDisplayName -eq 'Error' -and $_.TimeCreated -gt $Start }
        # filter for MsiInstaller errors
        $logErrors = $logErrors | Where-Object { $_.ProviderName -like 'MsiInstaller' }
    }

    process {

        if ($logErrors) {
            Write-InstallLog -text 'Windows AppLog error messages - START' -Info
            foreach ($logError in $logErrors) {
                Write-InstallLog -text "AppLog: $($logError.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss.ff')) $($logError.ProviderName): $($logError.Message)" -Fail
            }
            Write-InstallLog -text 'Windows AppLog error messages - END' -Info
        }
    }

    end {

    }
}
Export-ModuleMember -Function *
