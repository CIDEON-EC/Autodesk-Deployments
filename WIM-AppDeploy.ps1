<#
.SYNOPSIS
    Automation of using the wim file localy and start the installation/uninstallation
.DESCRIPTION
    Automation of downloading a wim file to a temporary local folder. After
	that the wim file will mount in the local folder. You can choose if you
	want to install or uninstall a product. At the end, the wim file will 
	dismount and the wim file will be deleted.

    Folder structure inside of the wim file:
    |-- image (default from Autodesk deployment)
    |-- Updates (updates to install)
    |-- Cideon (Cideon Tools)
    |-- Local (local configuration files to copy to the local machine)
        |-- ProgramData
        |-- Users
        |-- Public


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
.EXAMPLE
cd \\SERVER\SHARE\ScriptLocation
.\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging

#When using "CMD" instead of powershell (as admin):
cd \\SERVER\SHARE\ScriptLocation
powershell.exe -ExecutionPolicy Bypass .\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging


.NOTES
    Author: Timon Först
    Date:   16.04.2025
#>
[CmdletBinding(SupportsShouldProcess = $true)]Param (
    [Parameter(Mandatory = $true, HelpMessage = 'specified location of the wim file.')]
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
    [String]$LocalFolder = "C:\Temp",

    [Parameter(Mandatory = $true, HelpMessage = 'Specified the installation mode: Install, Update or Uninstall')]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Install", "Update", "Uninstall")]
    [string]$Mode,

    [Parameter(Mandatory = $false, HelpMessage = 'The Software Version, if none is specified, it will be extracted from the WIM name.')]
    [ValidateNotNullOrEmpty()]
    [string]$Version = [regex]::Matches($WIM, "\d+(\.\d+)?").Value,

    [Parameter(Mandatory = $false, HelpMessage = 'An array of XML filenames without extension, default <<Collection>>')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Files = @("Collection"),

    [Parameter(Mandatory = $false, HelpMessage = 'Enable log file')]
    [switch]$Logging,

    [Parameter(Mandatory = $false, HelpMessage = 'Disable Copying of the WIM file to the local folder')]
    [switch]$NoDownload,

    [Parameter(Mandatory = $false, HelpMessage = 'Deletes the WIM file after finishing the script')]
    [switch]$Purge
)



#region Functions
function Write-Log {
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
        Write-Log -text "This is a log entry." -Info
        Write-Log -text "This is a failure message." -Fail
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    Param
    (
        [Parameter(Mandatory)]
        [string]$text,
        [Parameter]
        [switch]$Info,
        [Parameter]
        [switch]$Fail
    )
    if ($Logging.IsPresent) {
        $category = "INFO:"
        if ($Info.IsPresent) {
            $category = "INFO:"
        }
        if ($Fail.IsPresent) {
            $category = "ERROR:"
        }
        "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $($category) $($text)" | out-file "$global:LogFile" -Append
    }
    
}
function Install-Updates {
    <#
    .SYNOPSIS
        Installs updates from the specified path.
    
    .DESCRIPTION
        Installs updates from the specified path. The updates are expected to be in the subfolder "Updates".
    
    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Updates".
    
    .EXAMPLE
        Install-Updates -Path "C:\Temp\PDC_20XX"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    param (
        [Parameter()]
        [string]$Path
    )
    # install updates
    # get all updates in folder
    Write-Log -text "Updates will be installed" -Info
    $filepath = [System.IO.Path]::Combine($Path, "Updates")
    $files = Get-ChildItem -Path $filepath -exclude @("*.txt", "*.xml", "VBA")
    foreach ($file in $files) {
        
        if ($file.Name -like "*AdSSO*msi") {
            #Adsso update
            $Arguments = '-qn -norestart'
        }
        elseif ($file.Name -like "*Licensing*exe") {
            #Licensing exe update
            $Arguments = '--unattendedmodeui none --mode unattended'
        }
        elseif ($file.Name -like "*Identity*exe") {
            #Identity exe update
            $Arguments = '--unattendedmodeui none --mode unattended'
        }
        elseif ($file.Name -like "*AdODIS*exe") {
            #Identity exe update
            $Arguments = '--mode unattended'
        }
        elseif ($file.Name -like "*vba*") {
            #Identity exe update
            $Arguments = '/quiet /norestart'
        }
        else {
            #normale Updates
            $Arguments = '-q'
        }
        try {
            Write-Log -text "Start Installation: $($file.Name) $Arguments" -Info
            Start-Process -NoNewWindow -FilePath $file.FullName -ArgumentList $Arguments -Wait              
            # waiting to get sure that installation is done
            Wait-Process -EA SilentlyContinue -Name $file | Select-Object -ExpandProperty BaseName
            Write-Log -text "Installed: $($file.Name)" -Info
        }
        catch {
            Write-Log -text "Install update $($file)" -Fail
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
    param (
        [Parameter()]
        [string]$Path
    )
    Write-Log -text "Start Autodesk installer" -Info
    # call install autodesk deployment
    # Start-Process -NoNewWindow -FilePath $Path\Install.cmd -Wait
    foreach ($ConfigFullFilename in $ConfigFullFilenames) {
        Write-Log -text "Started Installation of ConfigFile: $ConfigFullFilename" -Info
        Start-Process -FilePath $([System.IO.Path]::Combine($Path, "Image", "Installer.exe")) -ArgumentList "-i deploy --offline_mode -q -o $ConfigFullFilename" -Wait
    }
    
    Write-Log -text "Autodesk Products installed" -Info
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
    param (
        [Parameter()]
        [string]$Path
    )
    
    Write-Log -text "Start Autodesk Uninstaller" -Info
    Start-Process -NoNewWindow -FilePath $Path\Uninstall.cmd -Wait
    Write-Log -text "Uninstalled Autodesk Products" -Info
}
function Install-CideonTools {
    
    <#
    .SYNOPSIS
        Installs cideon tools from the specified path.
    
    .DESCRIPTION
        Installs cideon tools from the specified path. The tools are expected to be in the subfolder "Cideon".
    
    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Cideon".
    
    .EXAMPLE
        Install-CIDEONTools -Path "C:\Temp\PDC_20XX"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    param (
        [Parameter()]
        [string]$Path
    )
    # install updates
    # get all updates in folder	
	
    Write-Log -text " Updates will be installed" -Info
    $filepath = [System.IO.Path]::Combine($Path, "Cideon")
    $files = Get-ChildItem -Path $filepath -exclude *.txt
    foreach ($file in $files) {
        if ($file.Name -like "CIDEON.VAULT.TOOLBOX*") {
            #Toolbox
            $Arguments = 'ADDLOCAL=STANDARD,CIDEON_VAULT_TOOLBOX,CIDEON_VAULT_AddOns /quiet /passive'
        }
        else {
            #andere CIDEON Tools wie UpdateTools, oder DataStandard
            $Arguments = '/qn'
        }
        try {
            Start-Process -FilePath $file.FullName -ArgumentList $Arguments -Wait     
            Write-Log -text "Installed: $($file.Name)" -Info
        }
        catch {
            Write-Log -text "CIDEON Install Error for: $($file.Name)" -Fail
        }
              
        
    }
}
function Move-CIDEONToolboxUnused {

    <#
    .SYNOPSIS
        Deactiveate the additional Standard Cideon Toolbox Tools, with exception of the CIDEON.Vault.Toolbox
    
    .DESCRIPTION
        Move tools from the Standard Cideon Toolbox to one folder above, except the CIDEON.Vault.Toolbox
    
    .PARAMETER Version
        The version of the Autodesk Vault.
    .PARAMETER Keep
        The name of the folder to keep. Default is "CIDEON.Vault.Toolbox"
    
    .EXAMPLE
        Move-CIDEONToolboxUnused -Version "2024"
        Move-CIDEONToolboxUnused -Version "2024" -Keep "CIDEON.Vault.Toolbox"

    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
    #>
    param (
        [Parameter()]
        [string]$Version,
    
        [Parameter()]
        [string]$Keep = "CIDEON.Vault.Toolbox"
    )
    #Get Extension folder
    $ExtFldr = Get-Item -Path "C:\ProgramData\Autodesk\Vault $Version\Extensions"
    # Get all folders from Standard Toolbox, filter out the folders to keep
    $CDNstdFldrs = Get-ChildItem -Path $ExtFldr | Where-Object { $_.Name -like "CIDEON.Vault*" } | Where-Object { $_.Name -notmatch $keep }
    # Move Folders one folder obove
    $CDNstdFldrs  | ForEach-Object { Move-Item -path $_.FullName -Destination "C:\ProgramData\Autodesk\Vault $Version\" }

}
function Copy-Local {
    <#
    .SYNOPSIS
        Copies local files from the specified path to the local machine.
    
    .DESCRIPTION
        Copies local files from the specified path to the local machine. The files are expected to be in the subfolder "Local".
        Subfolders "ProgramData" and "Users" will be copied to the root of C:\.
    
    .PARAMETER Path
        The path to a folder, that is containing the subfolder "Local".
    
    .EXAMPLE
        Copy-Local -Path "C:\Temp\PDC_20XX"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Copy-CIDEONTools, but this was not a good name, because it is not only copying CIDEON Tools, but also the local files.
    #>
    
    param (
        [Parameter()]
        [string]$Path,
        [Parameter()]
        [string[]]$SourceFolder = @("ProgramData", "Users"),
        [Parameter()]
        [string[]]$TargetFolder = @("C:\", "C:\")
    )
    try {
        Write-Log -text "CIDEON Tools will be copied" -Info
        $localpath = [System.IO.Path]::Combine($Path, "Local")

        #check if the array sizes from source and target are the same
        if ($SourceFolder.Count -ne $TargetFolder.Count) {
            Write-Log -text "Source and Target inputs have not the same folder counts" -Fail
            return
        }
        # copy
        foreach($Source in $SourceFolder) {
            Copy-Item -Path $Source -Destination [System.IO.Path]::Combine($($TargetFolder[$($Sources.IndexOf($Source))])) -Force -Recurse
        }

        
        Write-Log -text "CIDEON Tools copied is done" -Info
        
    }

    catch {
        Write-Log -text "CIDEON Tools Error for Path: $($Source)" -Fail
    }

    
}
function Uninstall-Programs {
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
    
    .EXAMPLE
        Uninstall-Programs -DisplayName "Inventor" -Publisher "Autodesk"
        Uninstall-Programs -Publisher "CIDEON"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>
    param (
        [Parameter()]
        [string]$DisplayName,
        [Parameter()]
        [string]$Publisher
    )
    if ($Publisher -eq '' -and $DisplayName -eq '') {
        Write-Log -text "No Software or Publisher specified to uninstall" -Fail
        return
    }
    $installedProducts = Get-InstalledPrograms -Publisher $Publisher -DisplayName $DisplayName
    foreach ($installedProduct in $installedProducts) {
        try {
            write-host $installedProduct.UninstallString
            #Write-Log -text "$($installedProduct) will be uninstalled" -Info
            #gets the string before the first / - this is the exe filepath
            $uninstaller = $installedProduct.UninstallString
            # msiexec with / arguments
            if ($uninstaller -match "/") {
            
                $filePath = ($installedProduct.UninstallString -split "/" , 2)[0]
                write-host $filePath
                #gets the string after the first / - these are the arguments
                #we have to add the first / again, and put quiet after the additional arguments
                
                $arguments = "/" + $(($installedProduct.UninstallString -split '/' , 2)[1]) + " /quiet /passive"
                write-host $arguments
            }
            else {
                # ODIS Uninstaller with - arguments
                $filePath = ($installedProduct.UninstallString -split "-" , 2)[0]
                $arguments = "-" + $(($installedProduct.UninstallString -split '-' , 2)[1]) + " -q"
            }
            
          
            Start-Process -NoNewWindow -FilePath $filePath -ArgumentList $arguments -Wait
            # Start-Process -NoNewWindow -FilePath $installedProduct.UninstallString -Wait
            # Write-Log -text "$($installedProduct.DisplayName) is now uninstalled" -Info
        }
        catch {
            # Write-Log -text "$($installedProduct.DisplayName) could not be uninstalled" -Fail
        }
    }
}
function Get-InstalledPrograms {
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
    
    .EXAMPLE
        Get-InstalledPrograms -DisplayName "Inventor" -Publisher "Autodesk"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>

    param (
        [Parameter()]
        [string]$DisplayName,
        [Parameter()]
        [string]$Publisher
    )

    Set-StrictMode -Off | Out-Null
    $installedPrograms = Get-ItemProperty -Path $(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*';
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*';
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*';
        'HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*';
    ) -ErrorAction 'SilentlyContinue' | Where-Object { $_.DisplayName -match $DisplayName -and $_.Publisher -match $Publisher } | Select-Object -Property 'Publisher', 'DisplayName', 'DisplayVersion', 'UninstallString', 'ModifyPath' | Sort-Object -Property 'DisplayName' -Unique
    return $installedPrograms
}
function Set-CIDEONLanguageVariables {
    #TODO: This is not properly working, because the basic language of windows is always en-US, but the user language is different.
    #Set PC Variables from Language
    #(Get-UICulture).Name
    #(Get-Culture).Name
    $lngenv = Get-WinSystemLocale | Select-Object -ExpandProperty Name
    Write-Log -text "Set language Variables for $lngenv" -Info
    switch ($lngenv) {
        "de-DE" {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'de-DE', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'AT', 'Machine')
        }
        "de-AT" {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'de-DE', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'AT', 'Machine')
        }
        "cz-CZ" {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'CZ', 'Machine')
        }
        "en-GB" {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'UK', 'Machine')
        }
        "pl-PL" {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'PL', 'Machine')
        }
        "nl-NL" {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'NL', 'Machine')
        }
        Default {
            [System.Environment]::SetEnvironmentVariable('CDN_LNG', 'en-US', 'Machine')
            [System.Environment]::SetEnvironmentVariable('CDN_ITEM_LNG', 'UK', 'Machine')
        }
    }
}
function Set-CIDEONVariables {
    
    <#
    .SYNOPSIS
        Sets the CIDEON environment variables for the specified version.
    
    .DESCRIPTION
        Set the CDN_PROGRAMDATA, CDN_PROGRAM_DIR, and CDN_VAULT_EXTENSIONS environment variables for the specified version.
    
    .PARAMETER Version
        The version of the Autodesk Vault
    
    .EXAMPLE
        Set-CIDEONVariables -Version "2024"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025
   #>
    param (
        [Parameter()]
        [string]$Version
    )
    #Set PC Variables
    Write-Log -text "Set CIDEON Variables" -Info
    
    $CDN_VAULT_EXTENSIONS = "C:\ProgramData\Autodesk\Vault $($Version)\Extensions\"
    [System.Environment]::SetEnvironmentVariable('CDN_PROGRAMDATA', 'C:\ProgramData\CIDEON\', 'Machine')
    [System.Environment]::SetEnvironmentVariable('CDN_PROGRAM_DIR', 'C:\Program Files\CIDEON\', 'Machine')
    [System.Environment]::SetEnvironmentVariable('CDN_VAULT_EXTENSIONS', $CDN_VAULT_EXTENSIONS, 'Machine')
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

    # if your repair the autodesk software, it will look localy to the wim
    # we change this to the serverpath
    $RegistryPath = "HKLM:\SOFTWARE\Classes\Installer\Products"
    $Registry = Get-ChildItem $RegistryPath -Recurse
    $SearchQuery = [System.IO.Path]::Combine($mountPath, "image")
    $NewValue = [System.IO.Path]::Combine($Path, [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name) , "image")

    Write-Log -text "Reg Change" -Info

    foreach ($a in $Registry) {
        $a.Property | Where-Object {
            $a.GetValue($_) -Like "*$SearchQuery*"
        } | ForEach-Object {
            $CurrentValue = $a.GetValue($_)
            $ReplacedValue = $CurrentValue.Replace($SearchQuery, $NewValue)
            Write-Log -text "$a\$_" -Info
            Write-Log -text "From '$CurrentValue' to '$ReplacedValue'" -Info
            Set-ItemProperty -Path Registry::$a -Name $_ -Value $ReplacedValue
        }
    }
}
function Mount-WIM {
    
    <#
    .SYNOPSIS
        Mounts the specified WIM file to the specified path.
    
    .DESCRIPTION
        Mounts the specified WIM file to the specified path. The WIM file is expected to be in the specified path.
    
    .PARAMETER FullFileName
        The full path to the WIM file.
    .PARAMETER Path
        The path to mount the WIM file.
    
    .EXAMPLE
        Mount-WIM -FullFileName "C:\Temp\PDC_20XX.wim" -Path "C:\Temp\mount"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Mount-ADSKwim, but this was not a good name.
   #>
    param (
        [Parameter()]
        [string]$FullFileName,
        [Parameter()]
        [string]$Path
    )
    # mount local wim
    Mount-WindowsImage -ImagePath $FullFileName -Index 1 -Path $Path | Out-Null
    Write-Log -text "WIM $FullFileName mounted to $Path" -Info
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
    param (
        [Parameter()]
        [string]$Name,
        [Parameter()]
        [switch]$all,
        [Parameter()]
        [switch]$purge
    )

    if (-not $Name -and -not $all.IsPresent ) {
        Write-Log -text "No WIM specified to dismount" -Fail
        return
    }
    # dismount the wim file and remove mount folder
    # Get wim file
    if ($all.IsPresent) {
        $images = Get-WindowsImage -Mounted | Where-Object { $_.MountStatus -eq "Ok" }
    }
    else {
        $images = Get-WindowsImage -Mounted | Where-Object { $_.ImagePath -like "*$Name*" }
    }
    
    foreach ($image in $images) {
        Write-Log -text "Dismounting WIM $($image.ImagePath)" -Info
        try {
            Dismount-WindowsImage -Path $image.Path -Discard | Out-Null
            Write-Log -text "WIM $($image.ImagePath) dismounted" -Info
            
            if ($purge.IsPresent) {
                
                # delete local wim file
                Remove-Item -Path $image.ImagePath -Force
                Write-Log -text "WIM $deleteWIM localy deleted" -Info
            }
            Remove-Item -Path $image.Path -Force -Recurse
        }
        catch {
            Register-WIMDismountTask
        }

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
    ## failed to cleanly dismount, so set a task to cleanup after reboot
    Write-Log -text "WIM $WIM failed to dismounted" -Fail

    $STAction = New-ScheduledTaskAction `
        -Execute 'Powershell.exe' `
        -Argument '-NoProfile -WindowStyle Hidden -command "& {Get-WindowsImage -Mounted | Where-Object {$_.MountStatus -eq ''Invalid''} | ForEach-Object {$_ | Dismount-WindowsImage -Discard -ErrorVariable wimerr; if ([bool]$wimerr) {$errflag = $true}}; If (-not $errflag) {Clear-WindowsCorruptMountPoint; Unregister-ScheduledTask -TaskName ''CleanupWIM'' -Confirm:$false}}"'

    $STTrigger = New-ScheduledTaskTrigger -AtStartup

    Register-ScheduledTask `
        -Action $STAction `
        -Trigger $STTrigger `
        -TaskName "CleanupWIM" `
        -Description "Clean up WIM Mount points that failed to dismount properly" `
        -User "NT AUTHORITY\SYSTEM" `
        -RunLevel Highest `
        -Force
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
    $ODISPath = "HKCU:\SOFTWARE\Autodesk\ODIS"

    # Check if ODIS Key exists
    If (!(Test-Path $ODISPath)) {
        #create
        $ODIS = New-Item -Path $ODISPath
        Write-Log -text "Created $ODISPath" -Info
    }
    else {
        #Get
        $ODIS = Get-Item -Path $ODISPath
    }
    # Check if Property exists
    if ($null -eq $ODIS.DisableManualUpdateInstall) {
        #create 
        $ODISprop = New-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD"
        Write-Log -text "Created $($ODIS.PSPath)\DisableManualUpdateInstall with $Value" -Info
    }
    else {
        #set
        $ODISprop = Set-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD"
        Write-Log -text "Set $($ODIS.PSPath)\DisableManualUpdateInstall to $Value" -Info
    }
}
Function Get-SIDfromAcctName() {
    #TODO: Check if nessary
    Param(
        [Parameter(mandatory = $true)]$userName
    )
    $myacct = Get-WmiObject Win32_UserAccount -filter "Name='$userName'" 
    return $myacct.sid
}
Function Set-RegistryForUser {
    #TODO: Check if nessary
    $user = 'someuser'
    $sid = GetSIDfromAcctName -userName $user
    $path = Resolve-Path "$env:USERPROFILE\..\$user\NTUSER.DAT"
    
    try {
        reg load "HKU\$sid" $path 
        #New-PSDrive -Name HKUser -PSProvider Registry -Root "HKEY_USERS\$sid"
        #Get-ChildItem HKUser:\
        Get-ChildItem Registry::\HKEY_USERS\$sid
    
    }
    finally {
    
        #Remove-PSDrive -Name HKUser
    
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    
        $retryCount = 0
        $retryLimit = 20
        $retryTime = 1 #seconds
    
        reg unload "HKU\$sid" #> $null
    
        while ($LASTEXITCODE -ne 0 -and $retryCount -lt $retryLimit) {
            Write-Verbose "Error unloading 'HKU\$sid', waiting and trying again." -Verbose
            Start-Sleep -Seconds $retryTime
            $retryCount++
            reg unload "HKU\$sid" 
        }
    }
}

#endregion

#region Code


##################


# Get Version if empty or not 4 digits
if ([String]::IsNullOrEmpty($Version) -or $Version.Length -ne 4) {
    $Version = Read-Host -Prompt 'Input Software Version (e.g. 2024):'
}

$DebugPreference = 'SilentlyContinue'
# local logfile
$logfile = "Install_Autodesk_$($Version).log"
$global:LogFile = [System.IO.Path]::Combine($LocalFolder, $logfile)

#create local path
If (!(test-path $LocalFolder)) {
    New-Item -Path $LocalFolder -ItemType Directory | Out-Null
    Write-Log -text "Created $LocalFolder" -Info
}
##################




# Get wim Files of Path
$wimFiles = Get-ChildItem -Path $Path -Filter *.wim

# Filter wim Files of specified command
$wimFiles = $wimFiles | Where-Object { $_.Name -match ($WIM + ".wim") }


foreach ($wimFile in $wimFiles) {

    Write-Log -text "WIM File: $wimFile" -Info
    # local mount Path
    $mountPath = [System.IO.Path]::Combine($LocalFolder, "mount_" + [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name))
   
    # Configfiles
    $ConfigFullFilenames = @()
    
    # set the configfiles
    foreach ($ConfigFile in $Files) {
        $ConfigFullFilenames += [System.IO.Path]::Combine($mountPath, "Image", $ConfigFile, ".xml")
    }


    


    #create local path
    If (!(test-path $mountPath)) {
        New-Item -Path $mountPath -ItemType Directory | Out-Null
        Write-Log -text "Created $mountPath" -Info
    }
    

    try {
        # installation mode
        switch ($Mode) {
            "Install" { 

                # local wim filepath
                $localwimFile = [System.IO.Path]::Combine($LocalFolder, $wimFile.Name)

                # copy wim to local path
                if ($NoDownload.IsPresent) {
                    Write-Log -text "No Download of WIM file to local folder. Mounting from server." -Info
                    # mount wim from network
                    $localwimFile = $wimFile.FullName
                }
                else {
                    # check if wim file exists
                    if ([System.IO.File]::Exists($localwimFile)) {
                        Write-Log -text "WIM file already exists, no download needed" -Info
                    }
                    else {
                        Write-Log -text "Copy WIM to $LocalFolder" -Info
                        Copy-Item $wimFile.FullName $LocalFolder
                        Write-Log -text "WIM file copied" -Info
                    }
                }
                

                # mount local wim
                Mount-WIM -FullFileName $localwimFile -Path $mountPath

                # check if configfile exists
                foreach ($ConfigFullFilename in $ConfigFullFilenames) {
                    if (-not [System.IO.File]::Exists($ConfigFullFilename)) {
                        throw "ConfigFile $ConfigFullFilename does not exist"
                    }
                }
    
                Write-Log -text "Get Installed Products" -Info
                $installedApps = (Get-InstalledPrograms -Publisher "Autodesk|CIDEON")
                foreach ($installedApp in $installedApps) {
                    Write-Log -text "Installed Product: $($installedApp.DisplayName)" -Info
                }
                # #Uninstall Desktop App, if is installed
                # Uninstall-Programs -DisplayName "Autodesk desktop-app"
                
                # onother uninstall method
                # $installedAutodeskApps = Get-CimInstance -Class Win32_Product | Where-Object { $_.vendor -match "Autodesk|CIDEON"} | Where-Object {$_.Name -match "Desktop Connect|Single Sign On"}
                # foreach ($installedAutodeskApp in $installedAutodeskApps){
                #     Write-Log -text "Uninstall $($installedAutodeskApp.Name)" -Info
                #     $installedAutodeskApp.Uninstall()
                # }

                #Uninstall 2022 products
                #Uninstall-Programs -Publisher "Autodesk" -DisplayName "Autodesk Single Sign On Component"

                
                # install autodesk software
                Install-AutodeskDeployment -Path $mountPath

                # set Autodesk Update 
                Set-AutodeskUpdate -ShowOnly

                #updates
                Install-Updates -Path $mountPath

                # correct the registry
                #Rename-RegistryInstallationPath
				
                # copy CIDEON Tools
                Install-CIDEONTools -Path $mountPath
                Move-CIDEONToolboxUnused -Version $Version
                Copy-Local -Path $mountPath

                #Set Variables
                # Set-LanguageVariables
                Set-CIDEONVariables -Version $Version

            }
            "Update" {

                # mount wim from network
                Mount-WIM -FullFileName $wimFile -Path $mountPath

                Install-Updates -Path $mountPath
                Copy-Local -Path $mountPath
            }
            

            "Uninstall" {
                Uninstall-AutodeskDeployment -Path $mountPath
                Uninstall-Programs -Publisher "CIDEON"
            }
        }
        
    }
    catch {
        
        Write-Log -text "By $Mode" -Fail
        Write-Log -text "$($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)" -Fail
    }
    finally {
        try {
            # log the installed software
            Write-Log -text "Get Installed Products" -Info
            $installedApps = (Get-InstalledPrograms -Publisher "Autodesk" -DisplayName "Inventor Professional $Version|AutoCAD $Version|AutoCAD Mechanical $Version|Vault $Version") 
            $installedApps += (Get-InstalledPrograms -Publisher "CIDEON") 
            foreach ($installedApp in $installedApps) {
                Write-Log -text "Installed Product: $($installedApp.DisplayName) |  $($installedApp.DisplayVersion)" -Info
            }

            # dismount and delete local wim, if copied
            Write-Log -text "Dismounting WIM $($wimFile.Name)" -Info
            if ($NoDownload.IsPresent -and -not $purge.IsPresent) {
                Dismount-Wim -Name $wimFile.Name
            }
            else {
                Dismount-Wim -Name $wimFile.Name -purge
            }

        }
        catch {
            Write-Log -text "$($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)" -Fail
        }
        finally {
            
            # copy log to server
            if ($Logging.IsPresent) {
                Copy-Item $global:LogFile $([System.IO.Path]::Combine($Path, "_LOG", "$env:computername.log"))
                # delete local logfile
                Remove-Item $global:LogFile -Recurse
            }
        }
    }
}


#endregion
