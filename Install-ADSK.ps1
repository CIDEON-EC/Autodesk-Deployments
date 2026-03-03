<#
.SYNOPSIS
    Automation of using the wim file localy and start the installation/uninstallation

.NOTES
    Author: Timon Först
    Version: 1.0.3

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
.PARAMETER WhatIf
    Shows what would happen if the script runs. No actual changes are made (Dry Run mode).
.PARAMETER Confirm
    Prompts for confirmation before executing each action.
.EXAMPLE
cd \\SERVER\SHARE\ScriptLocation
.\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging

#When using "CMD" instead of powershell (as admin):
cd \\SERVER\SHARE\ScriptLocation
powershell.exe -ExecutionPolicy Bypass .\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging


#>
[CmdletBinding(SupportsShouldProcess = $true)]param (
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
    [string]$Version = [regex]::Matches($WIM, '\d+(\.\d+)?').Value,

    [Parameter(Mandatory = $false, HelpMessage = 'An array of XML filenames without extension, default <<Collection>>')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Files = @('Collection'),

    [Parameter(Mandatory = $false, HelpMessage = 'Enable log file')]
    [switch]$Logging,

    [Parameter(Mandatory = $false, HelpMessage = 'Disable Copying of the WIM file to the local folder')]
    [switch]$NoDownload,

    [Parameter(Mandatory = $false, HelpMessage = 'Deletes the WIM file after finishing the script')]
    [switch]$Purge
)



#region Functions
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
        $category = 'INFO'
        if ($Info.IsPresent) {
            $category = 'INFO'
        }
        if ($Fail.IsPresent) {
            $category = 'ERROR'
        }
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.ms') [$($category)] $($text)"
        if ($PSCmdlet.ShouldProcess("[$($category)] $($text)", 'Log')) {
            if (-not $WhatIfPreference) {
                $logMessage | Out-File "$script:LogFile" -Append
            }
        }
    }

}
function Invoke-WithoutWhatIf {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $previousWhatIfPreference = $WhatIfPreference
    try {
        $WhatIfPreference = $false
        & $ScriptBlock
    }
    finally {
        $WhatIfPreference = $previousWhatIfPreference
    }
}
function Resolve-WhatIfSourceItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter()]
        [object[]]$CachedItems,
        [Parameter()]
        [object[]]$Exclude,
        [Parameter(Mandatory)]
        [string]$MissingPathLogText,
        [Parameter(Mandatory)]
        [string]$CachedPathLogText
    )

    if (Test-Path -Path $Path) {
        if ($Exclude) {
            return @(Get-ChildItem -Path $Path -Exclude $Exclude)
        }
        return @(Get-ChildItem -Path $Path)
    }

    if (-not $WhatIfPreference) {
        if ($Exclude) {
            return @(Get-ChildItem -Path $Path -Exclude $Exclude)
        }
        return @(Get-ChildItem -Path $Path)
    }

    if ($CachedItems -and $CachedItems.Count -gt 0) {
        Write-InstallLog -text $CachedPathLogText -Info
        return @($CachedItems | ForEach-Object {
                [pscustomobject]@{
                    Name      = $_.Name
                    FullName  = [System.IO.Path]::Combine($Path, $_.Name)
                    FromCache = $true
                }
            })
    }

    Write-InstallLog -text $MissingPathLogText -Info
    return @()
}
function Update-WIMInspectionCache {
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
        $Script:CachedUpdateFiles = @(Get-ChildItem -Path $updatesPath -Exclude @('*.txt', '*.xml', 'VBA') -ErrorAction SilentlyContinue)
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
function Get-UpdateInstallSpec {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FileName,
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $Executable = $FilePath
    if ($FileName -like '*msi') {
        $Executable = 'msiexec.exe'
        $Arguments = "/i `"$FilePath`" /qn /norestart /l*v `"$script:LogFile`""
    }
    elseif ($FileName -like '*Licensing*exe') {
        $Arguments = '--unattendedmodeui none --mode unattended'
    }
    elseif ($FileName -like '*AdODIS*exe') {
        $Arguments = '--mode unattended'
    }
    elseif ($FileName -like '*vba*') {
        $Arguments = '/quiet /norestart'
    }
    else {
        $Arguments = '-q /quiet'
    }

    return [pscustomobject]@{
        Executable = $Executable
        Arguments  = $Arguments
    }
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
        [string]$Path = $Script:mountPath
    )
    # install updates
    # get all updates in folder
    Write-InstallLog -text 'Updates will be installed' -Info
    $filepath = [System.IO.Path]::Combine($Path, 'Updates')

    $files = Resolve-WhatIfSourceItem -Path $filepath -CachedItems $Script:CachedUpdateFiles -Exclude @('*.txt', '*.xml', 'VBA') -MissingPathLogText "Would install updates from $filepath (WhatIf mode)" -CachedPathLogText "Would install updates from $filepath (WhatIf mode, using inspected WIM cache)"
    if ($files.Count -eq 0) {
        return
    }

    foreach ($file in $files) {
        $installSpec = Get-UpdateInstallSpec -FileName $file.Name -FilePath $file.FullName
        try {
            Write-InstallLog -text "Start update installation: $($file.Name) with arguments: $($installSpec.Arguments)" -Info
            if ($PSCmdlet.ShouldProcess($file.Name, "Install Update with arguments: $($installSpec.Arguments)")) {
                $process = Start-Process -NoNewWindow -FilePath $installSpec.Executable -ArgumentList $installSpec.Arguments -PassThru -Wait -ErrorAction Stop

                # Check exit code
                if ($process.ExitCode -eq 0) {
                    Write-InstallLog -text "Successfully installed update: $($file.Name)" -Info
                }
                else {
                    Write-InstallLog -text "Update installation failed for $($file.Name) with exit code: $($process.ExitCode). Check log file: $script:LogFile" -Fail
                }
            }
        }
        catch {
            Write-InstallLog -text "Update installation error for $($file.Name): $($_.Exception.Message)" -Fail
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

    .EXAMPLE
        Install-AutodeskDeployment -Path "C:\Temp\PDC_20XX"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        [string]$Path = $Script:mountPath
    )
    Write-InstallLog -text 'Start Autodesk installer' -Info
    # call install autodesk deployment
    # Start-Process -NoNewWindow -FilePath $Path\Install.cmd -Wait
    foreach ($ConfigFullFilename in $ConfigFullFilenames) {
        Write-InstallLog -text "Started Installation of ConfigFile: $ConfigFullFilename" -Info
        $installerPath = [System.IO.Path]::Combine($Path, 'Image', 'Installer.exe')
        $installerArgs = "-i deploy --offline_mode -q -o $ConfigFullFilename"
        if ($PSCmdlet.ShouldProcess((Split-Path $ConfigFullFilename -Leaf), "Install Autodesk Deployment with arguments: $installerArgs")) {
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
        $adskProducts = (Get-ChildItem -Directory -Path $Path) | Where-Object { $_.Name -like "*$($Version)*" }
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

    begin {
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
            Write-InstallLog -text "No Autodesk Products found in $Path" -Fail
            return
        }
        else {
            Write-InstallLog -text "Autodesk Products found: $($adskProducts.Name -join ', ')" -Info
        }
    }

    process {
        foreach ($adskProduct in $adskProducts) {

            # get xml file
            $xmlPath = [System.IO.Path]::Combine($adskProduct.FullName, $xmlFileName)
            [xml]$xml = Get-Content $xmlPath

            Write-InstallLog -text "Change $xmlPath file" -Info

            # set namespace
            [System.Xml.XmlNamespaceManager]$ns = New-Object System.Xml.XmlNamespaceManager $xml.NameTable
            $ns.AddNamespace('ns', $xml.BundleExtension.xmlns)

            # Language Packs
            if ($Language.Length -gt 0) {
                try {

                    # get all language pack nodes
                    $packages = $xml.SelectNodes("//ns:Package[contains(@name,'Language Pack')]", $ns)

                    # delete all language packs that are not in the Language array
                    # go through all packages
                    foreach ($package in $packages) {
                        $delete = $true
                        # go through all languages in the Language array
                        foreach ($lang in $Language) {
                            # check if the package name contains the language
                            if ($package.name -like "*$lang*") {
                                $delete = $false
                            }
                        }
                        if ($delete) {
                            if ($PSCmdlet.ShouldProcess("Remove language package $($package.name) from $xmlPath")) {
                                Write-InstallLog -text "Package $($package.name) will be removed" -Info
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
                try {
                    foreach ($name in $Remove) {
                        $packages = $xml.SelectNodes("//ns:Package[contains(@name,$name)]", $ns)
                        foreach ($package in $packages) {
                            if ($PSCmdlet.ShouldProcess("Remove package $($package.name) from $xmlPath")) {
                                Write-InstallLog -text "Package $($package.name) will be removed" -Info
                                # remove the package from the xml file
                                $package.ParentNode.RemoveChild($package) | Out-Null
                            }
                        }
                    }
                }
                catch {
                    Write-InstallLog -text "The Package $Remove could not be removed"
                }
            }

            # saving changes to xml
            try {
                if ($PSCmdlet.ShouldProcess("Save changes to $xmlPath")) {
                    $xml.Save($xmlPath)
                    Write-InstallLog -text "Saved changes to $xmlPath" -Info
                }
            }
            catch {
                Write-InstallLog -text "Could not save changes to $xmlPath" -Fail
            }

        }
    }

    end {}
}
function Get-CideonInstallArgumentString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FileName,
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

    if ($FileName -like 'CIDEON.VAULT.TOOLBOX*' -and $FileName -notlike '*SERVICEPACK*') {
        $features = @()
        if ($VaultToolboxStandard.IsPresent) {
            $features += 'STANDARD'
        }
        if ($VaultToolboxPro.IsPresent) {
            $features += 'CIDEON_VAULT_TOOLBOX'
        }
        if ($VaultToolboxObserver.IsPresent) {
            $features += 'CIDEON_VAULT_AddOns'
        }
        if ($VaultToolboxClassification.IsPresent) {
            $features += 'CIDEON_INVENTOR_CLASSIFICATION_Addin'
        }
        if ($VaultToolboxUpdate.IsPresent) {
            $features += 'CIDEON_UPDATE_EXTENSION'
        }
        return "ADDLOCAL=$($features -join ',') /qn"
    }

    return '/qn'
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
        [string]$Path = $Script:mountPath,
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
    $filepath = [System.IO.Path]::Combine($Path, 'Cideon')

    $files = Resolve-WhatIfSourceItem -Path $filepath -CachedItems $Script:CachedCideonFiles -Exclude @('*.txt') -MissingPathLogText "Would install CIDEON tools from $filepath (WhatIf mode)" -CachedPathLogText "Would install CIDEON tools from $filepath (WhatIf mode, using inspected WIM cache)"
    if ($files.Count -eq 0) {
        return
    }

    foreach ($file in $files) {
        $Arguments = Get-CideonInstallArgumentString -FileName $file.Name -VaultToolboxStandard:$VaultToolboxStandard.IsPresent -VaultToolboxPro:$VaultToolboxPro.IsPresent -VaultToolboxObserver:$VaultToolboxObserver.IsPresent -VaultToolboxClassification:$VaultToolboxClassification.IsPresent -VaultToolboxUpdate:$VaultToolboxUpdate.IsPresent
        try {
            Write-InstallLog -text "Start Installation: $($file.Name) $Arguments" -Info
            if ($PSCmdlet.ShouldProcess($file.Name, "Install CIDEON Tool with arguments: $Arguments")) {
                Start-Process -FilePath $file.FullName -ArgumentList $Arguments -Wait
                Write-InstallLog -text "Installed: $($file.Name)" -Info
            }
        }
        catch {
            Write-InstallLog -text "CIDEON Install Error for: $($file.Name)" -Fail
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
        [string]$Version = $Script:Version,

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
    $FolderDisable = Get-ChildItem -Path $Folder | Where-Object { $_.Name -like $Filter } | Where-Object { $_.Name -notin $Keep }
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
        Gets the real user name of the current user, if the script is running with admin rights.
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
            Write-InstallLog -text 'You can only set one of the parameters DomainUser or LocalUser' -Fail
            return
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

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string]$Version = $Script:Version,
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
        [string]$Path = $Script:mountPath,
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
            if (Test-Path -Path $localPath) {
                $SourceFolder = Get-ChildItem -Path $localPath -Directory | Select-Object -ExpandProperty Name
            }
            elseif ($WhatIfPreference -and $Script:CachedLocalFolders -and $Script:CachedLocalFolders.Count -gt 0) {
                Write-InstallLog -text "Would copy local files from $localPath (WhatIf mode, using inspected WIM cache)" -Info
                $SourceFolder = @($Script:CachedLocalFolders)
                $usingCachedSource = $true
            }
            elseif ($WhatIfPreference) {
                Write-InstallLog -text "Would copy local files from $localPath (WhatIf mode)" -Info
                return
            }
            else {
                $SourceFolder = Get-ChildItem -Path $localPath -Directory | Select-Object -ExpandProperty Name
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

                $filePath = ($installedProduct.UninstallString -split '/' , 2)[0]
                # gets the string after the first / - these are the arguments
                # we have to add the first / again, and put quiet after the additional arguments

                $arguments = '/' + $(($installedProduct.UninstallString -split '/' , 2)[1]) + ' /quiet /passive'
            }
            else {
                # ODIS Uninstaller with - arguments
                $filePath = ($installedProduct.UninstallString -split '-' , 2)[0]
                $arguments = '-' + $(($installedProduct.UninstallString -split '-' , 2)[1]) + ' -q'
            }

            if ($PSCmdlet.ShouldProcess($installedProduct.DisplayName, "Uninstall with command: $filePath $arguments")) {
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
    $WhereScriptBlock = [scriptblock]::create("`$_.DisplayName $FilterOperator '$DisplayName' -and `$_.Publisher -match '$Publisher'")
    $installedPrograms = Get-ItemProperty -Path $(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction 'SilentlyContinue' | Where-Object $WhereScriptBlock | Select-Object -Property 'Publisher', 'DisplayName', 'DisplayVersion', 'UninstallString', 'ModifyPath' | Sort-Object -Property 'DisplayName' -Unique
    return $installedPrograms
}
function Set-CIDEONLanguageVariable {
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
        [string]$Version = $Script:Version
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

    # if your repair the autodesk software, it will look localy to the wim
    # we change this to the serverpath
    $RegistryPath = 'HKLM:\SOFTWARE\Classes\Installer\Products'
    $Registry = Get-ChildItem $RegistryPath -Recurse
    $SearchQuery = [System.IO.Path]::Combine($mountPath, 'image')
    $NewValue = [System.IO.Path]::Combine($Path, [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name) , 'image')

    Write-InstallLog -text 'Reg Change' -Info

    foreach ($a in $Registry) {
        $a.Property | Where-Object {
            $a.GetValue($_) -like "*$SearchQuery*"
        } | ForEach-Object {
            $CurrentValue = $a.GetValue($_)
            $ReplacedValue = $CurrentValue.Replace($SearchQuery, $NewValue)
            Write-InstallLog -text "$a\$_" -Info
            Write-InstallLog -text "From '$CurrentValue' to '$ReplacedValue'" -Info
            if ($PSCmdlet.ShouldProcess($a, 'Update registry path')) {
                Set-ItemProperty -Path Registry::$a -Name $_ -Value $ReplacedValue
            }
        }
    }
}
function Get-WIM {
    <#
    .SYNOPSIS
        Copies the specified WIM file to the local machine.
    .DESCRIPTION
        Copies the specified WIM file to the local machine. The WIM file is expected to be in the specified path.
        If the NoDownload switch is set, the WIM file will not be copied to the local machine, but mounted from the server.
    .PARAMETER File
        System.IO.FileInfo or String (full path) of the WIM file.
    .PARAMETER Folder
        The folder to copy the WIM file to. Default is the LocalFolder variable.
    .EXAMPLE
        Get-WIM -File "C:\Temp\PDC_20XX.wim"
        Get-WIM -File "C:\Temp\PDC_20XX.wim" -Folder "C:\Temp\LocalWIM"

    .NOTES
        Autor: Timon Först
        Datum: 03.06.2025
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (

        [Parameter()]
        $File = $Script:wimFile,
        [Parameter()]
        [string]$Folder = $Script:LocalFolder
    )

    begin {

        # check if File is a string, then get the file from the path
        if ($File -is [string]) {
            $File = Get-Item -Path $File
        }
        # local wim filepath
        $localwimFile = [System.IO.Path]::Combine($Folder, $File.Name)
    }

    process {

        # copy wim to local path
        if ($Script:NoDownload.IsPresent) {
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
        if ($WhatIfPreference) {
            if ($Script:NoDownload.IsPresent) {
                return $File
            }
            if (Test-Path -Path $localwimFile) {
                return (Get-Item -Path $localwimFile)
            }
            return $File
        }

        return (Get-Item -Path $localwimFile)
    }
}
function Mount-WIM {

    <#
    .SYNOPSIS
        Mounts the specified WIM file to the specified path.

    .DESCRIPTION
        Mounts the specified WIM file to the specified path. The WIM file is expected to be in the specified path.

    .PARAMETER File
        System.IO.FileInfo or String (full path) of the WIM file.
    .PARAMETER Path
        The path to mount the WIM file.

    .EXAMPLE
        Mount-WIM -FullFileName "C:\Temp\PDC_20XX.wim" -Path "C:\Temp\mount"

    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Mount-ADSKwim, but this was not a good name.
   #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter()]
        $File = $Script:wimFile,
        [Parameter()]
        [string]$Path = $Script:mountPath,
        [Parameter()]
        [switch]$Inspect
    )
    begin {
        # check if File is a string, then get the file from the path
        if ($File -is [string]) {
            $File = Get-Item -Path $File
        }
    }
    process {
        if ($Inspect.IsPresent) {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                Write-InstallLog -text 'WhatIf mode: WIM inspection requires elevated rights. Start PowerShell as Administrator to see file details.' -Info
                return
            }

            $tempMount = [System.IO.Path]::Combine($env:TEMP, "WIM_Inspect_$(Get-Random)")
            $mounted = $false
            try {
                Invoke-WithoutWhatIf -ScriptBlock {
                    New-Item -Path $tempMount -ItemType Directory -Force | Out-Null
                }

                Invoke-WithoutWhatIf -ScriptBlock {
                    Mount-WindowsImage -ImagePath $File.FullName -Index 1 -Path $tempMount -ReadOnly -ErrorAction Stop | Out-Null
                }
                $mounted = $true
                Write-InstallLog -text 'WIM mounted read-only for inspection' -Info
                Update-WIMInspectionCache -MountedPath $tempMount

                return [pscustomobject]@{
                    ImagePath = $File.FullName
                    Path      = $tempMount
                }
            }
            catch {
                Write-InstallLog -text "WhatIf mode: WIM inspection skipped - $($_.Exception.Message)" -Info
                if (-not $mounted -and (Test-Path -Path $tempMount)) {
                    Invoke-WithoutWhatIf -ScriptBlock {
                        Remove-Item -Path $tempMount -Force -Recurse -ErrorAction SilentlyContinue
                    }
                }
                return
            }
        }

        # mount local wim
        if ($PSCmdlet.ShouldProcess($File.FullName, "Mount WIM to $Path")) {
            Mount-WindowsImage -ImagePath $File.FullName -Index 1 -Path $Path | Out-Null
            Write-InstallLog -text "WIM $File.FullName mounted to $Path" -Info
        }

        # check if configfile exists (skip in WhatIf mode)
        if (-not $WhatIfPreference) {
            foreach ($ConfigFullFilename in $ConfigFullFilenames) {
                if (-not [System.IO.File]::Exists($ConfigFullFilename)) {
                    Write-InstallLog -text "ConfigFile $ConfigFullFilename does not exist" -Fail
                    throw "ConfigFile $ConfigFullFilename does not exist"
                }
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
        $File = $Script:wimFile,
        [Parameter()]
        [switch]$all,
        [Parameter()]
        [switch]$purge
    )
    begin {
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
                $images = @([pscustomobject]@{ ImagePath = $displayPath; Path = $Script:mountPath })
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
        if ($null -eq (Get-ItemProperty -Path $ODIS.PSPath).DisableManualUpdateInstall) {
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
#endregion

#region Code


##################


# Get Version if empty or not 4 digits
if ([String]::IsNullOrEmpty($Version) -or $Version.Length -ne 4) {
    $Version = Read-Host -Prompt 'Input Software Version (e.g. 2026):'
}

$DebugPreference = 'SilentlyContinue'
# local logfile
$logfile = "Install_Autodesk_$($Version).log"
$script:LogFile = [System.IO.Path]::Combine($LocalFolder, $logfile)

#create local path
if (!(Test-Path $LocalFolder)) {
    New-Item -Path $LocalFolder -ItemType Directory | Out-Null
    Write-InstallLog -text "Created $LocalFolder" -Info
}
##################

$StartTime = Get-Date


# Get wim Files of Path
$wimFiles = Get-ChildItem -Path $Path -Filter *.wim

# Filter wim Files of specified command
$wimFiles = $wimFiles | Where-Object { $_.Name -match ($WIM + '.wim') }


foreach ($wimFile in $wimFiles) {

    Write-InstallLog -text "WIM File: $wimFile" -Info
    # local mount Path
    $mountPath = [System.IO.Path]::Combine($LocalFolder, 'mount_' + [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name))

    # Configfiles
    $ConfigFullFilenames = @()

    # set the configfiles
    foreach ($ConfigFile in $Files) {
        $ConfigFullFilenames += [System.IO.Path]::Combine($mountPath, 'Image', $ConfigFile + '.xml')
    }





    #create local path
    if (!(Test-Path $mountPath)) {
        New-Item -Path $mountPath -ItemType Directory | Out-Null
        Write-InstallLog -text "Created $mountPath" -Info
    }

    $inspectMount = $null


    try {
        # installation mode
        switch ($Mode) {
            'Install' {

                # Download WIM file to local path
                $localwimFile = Get-WIM

                if ($WhatIfPreference) {
                    Write-InstallLog -text 'WhatIf mode: Inspecting WIM content...' -Info
                    $inspectMount = Mount-WIM -File $localwimFile -Inspect
                }

                # mount local wim
                if (-not $WhatIfPreference) {
                    Mount-WIM -File $localwimFile
                }



                # Write-InstallLog -text 'Get Installed Products' -Info
                # $installedApps = (Get-InstalledProgram -Publisher 'Autodesk|CIDEON')
                # foreach ($installedApp in $installedApps) {
                #     Write-InstallLog -text "-- $($installedApp.DisplayName)" -Info
                # }


                # #Uninstall Desktop App, if is installed
                # Uninstall-Program -DisplayName "Autodesk desktop-app"

                # onother uninstall method
                # $installedAutodeskApps = Get-CimInstance -Class Win32_Product | Where-Object { $_.vendor -match "Autodesk|CIDEON"} | Where-Object {$_.Name -match "Desktop Connect|Single Sign On"}
                # foreach ($installedAutodeskApp in $installedAutodeskApps){
                #     Write-InstallLog -text "Uninstall $($installedAutodeskApp.Name)" -Info
                #     $installedAutodeskApp.Uninstall()
                # }

                #Uninstall 2022 products
                #Uninstall-Program -Publisher "Autodesk" -DisplayName "Autodesk Single Sign On Component"

                # Reduce from all provided language packs in Autodesk deplyoment, only the local installed windows language
                #Set-AutodeskDeployment -Language (Get-WinUserLanguageList)[0].EnglishName


                # install autodesk software
                Install-AutodeskDeployment

                # set Autodesk Update
                Set-AutodeskUpdate -ShowOnly

                #updates
                Install-Update

                # correct the registry
                #Rename-RegistryInstallationPath

                # copy CIDEON Tools
                Install-CIDEONTool -VaultToolboxStandard -VaultToolboxPro -VaultToolboxObserver -VaultToolboxClassification
                Disable-VaultExtension
                Copy-Local

                # set custom Inventor Project File, if needed, otherwise the default project file will be used and the user has to change it manually
                # Set-InventorProjectFile -File "C:\path\Vault.ipj"
                Set-InventorProjectFile

                #Set Variables
                #Remove-UserSystemVariable -Name "CDN_LNG"



                # # log the installed software
                # Write-InstallLog -text 'Get Installed Products' -Info
                # $installedApps = (Get-InstalledProgram -Publisher 'Autodesk' -DisplayName "Inventor Professional $Version|AutoCAD $Version|AutoCAD Mechanical $Version|Vault $Version")
                # $installedApps += (Get-InstalledProgram -Publisher 'CIDEON')
                # foreach ($installedApp in $installedApps) {
                #     Write-InstallLog -text "-- $($installedApp.DisplayName) |  $($installedApp.DisplayVersion)" -Info
                # }




            }
            'Update' {

                # mount wim from network
                Mount-WIM

                Install-Update
                Copy-Local
            }


            'Uninstall' {
                # mount wim from network
                # Mount-WIM

                # Uninstall-AutodeskDeployment

                # Uninstall CIDEON Tools with windows Installer
                Uninstall-Program -Publisher 'CIDEON'
                # Uninstall Autodesk Products with windows Installer
                Uninstall-Program -DisplayName 'Autodesk AutoCAD Mechanical 2022 - English' -Publisher 'Autodesk' -FilterOperator '-eq'
                Uninstall-Program -DisplayName 'Autodesk Inventor Professional 2022' -Publisher 'Autodesk' -FilterOperator '-eq'
                Uninstall-Program -DisplayName 'Autodesk Vault Professional 2022 (Client)' -Publisher 'Autodesk' -FilterOperator '-eq'
            }
        }

    }
    catch {

        Write-InstallLog -text "By $Mode" -Fail
        Write-InstallLog -text "$($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)" -Fail
    }
    finally {
        try {
            Get-AppLogError -Start $StartTime

            # dismount and delete local wim, if copied
            Write-InstallLog -text "Dismounting WIM $($wimFile.Name)" -Info
            if ($WhatIfPreference -and $inspectMount) {
                Invoke-WithoutWhatIf -ScriptBlock {
                    Dismount-WIM -File $inspectMount
                }
                Write-InstallLog -text 'WIM inspection complete and dismounted' -Info
            }
            elseif ($NoDownload.IsPresent) {
                Dismount-Wim
            }
            elseif ($purge.IsPresent) {
                Dismount-Wim -purge
            }
            else {
                Dismount-Wim
            }

        }
        catch {
            Write-InstallLog -text "$($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)" -Fail
        }
        finally {

            # copy log to server
            if ($Logging.IsPresent) {
                try {

                    $logFolder = [System.IO.Path]::Combine($Path, '_LOG')
                    if (!(Test-Path $logFolder)) {
                        New-Item -Path $logFolder -ItemType Directory | Out-Null
                    }
                    $LogFilepath = [System.IO.Path]::Combine($logFolder, "$env:computername.log")

                    # Copy and remove log file only if it exists (WhatIf mode doesn't create the file)
                    if (Test-Path $script:LogFile) {
                        Copy-Item $script:LogFile $LogFilepath
                        # delete local logfile
                        if (Test-Path $LogFilepath) {
                            Remove-Item $script:LogFile -Recurse
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


#endregion
