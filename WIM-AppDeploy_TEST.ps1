<#
.SYNOPSIS
    Automation of using the wim file localy and start the installation/uninstallation
.DESCRIPTION
    Automation of downloading a wim file to a temporary local folder. After
	that the wim file will mount in the local folder. You can choose if you
	want to install or uninstall a product. At the end, the wim file will 
	dismount and the wim file will be deleted.
.PARAMETER Path
    The path to the WIM file.
	Default is script location.
	So in most cases you don't need to use it.
.PARAMETER WIM
    Name of the WIM file you want to use.
.PARAMETER LocalFolder
    Local folder where the wim file should be downloaded and mapped.
	Default is C:\Temp
.PARAMETER Mode
    Available: Install, Uninstall
	Mode that you want to execute. Start the batchfile  inside the wim file.
.PARAMETER Language
    Available: enu, deu, plk, csy
    Additional Language pack, that should installed to english version.
.PARAMETER ConfigFiles
    Array of XML filenames without extension, default <<Collection>>
    Configfiles that should be used for the installation.
.EXAMPLE
cd \\SERVER\SHARE\ScriptLocation
.\WIM-AppDeploy.ps1 -WIM "INV_2022" -Mode "Install" -Language "deu" -Path "\\sukwas187\CIDEON\_DPL"

#When using "CMD" instead of powershell (as admin):
cd \\SERVER\SHARE\ScriptLocation
powershell.exe -ExecutionPolicy Bypass .\WIM-AppDeploy.ps1 -WIM "INV_2022" -Mode "Install" -Language "deu" -Path "\\sukwas187\CIDEON\_DPL"


.NOTES
    Author: Timon Först
    Date:   22.03.2022
#>
[CmdletBinding(SupportsShouldProcess = $true)]Param (
    [Parameter(Mandatory = $true, HelpMessage = 'specified location of the wim file.')]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[\\]')]
    [String]$Path,

    [Parameter(Mandatory = $true, HelpMessage = 'specified the and filename of the wim file without extension.')]
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
    [string[]]$ConfigFiles = @("Collection")

    # [Parameter(Mandatory = $true, HelpMessage = 'Specified the additional language pack: enu, deu, plk or csy')]
    # [ValidateNotNullOrEmpty()]
    # [ValidateSet("enu", "deu", "plk", "csy")]
    # [string]$Language
)



#region Functions
function Write-Log {
    Param
    (
        $text
    )

    "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $($text)" | out-file "$global:LogFile" -Append
}
function Install-Updates {
    param (
        [Parameter()]
        [string]$Path
    )
    # install updates
    # get all updates in folder
    Write-Log -text "INFO: Updates will be installed"
    $filepath = [System.IO.Path]::Combine($Path, "SP")
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
            Write-Log -text "INFO: Start Installation: $($file.Name) $Arguments"
            Start-Process -NoNewWindow -FilePath $file.FullName -ArgumentList $Arguments -Wait              
            # waiting to get sure that installation is done
            Wait-Process -EA SilentlyContinue -Name $file | Select-Object -ExpandProperty BaseName
            Write-Log -text "INFO: Installed: $($file.Name)"
        }
        catch {
            Write-Log -text "ERROR: Install update $($file)"
        }
        
    }
}
function Install-LanguagePacks {
    param (
        [Parameter()]
        [string]$Path
    )
    # install language packs
    # get specified Language pack
    $LPpath = [System.IO.Path]::Combine($Path, "LP")
    if (Test-Path -Path $LPpath) {
        $LPfiles = Get-ChildItem -Path $LPpath | Where-Object { $_.Name -like "*$Language*.exe" }
        foreach ($LPfile in $LPfiles) {
            Start-Process -NoNewWindow -FilePath $LPfile.FullName -ArgumentList '-q' -Wait
            # waiting to get sure that installation is done
            Wait-Process -EA SilentlyContinue -Name $LPfile | Select-Object -ExpandProperty BaseName
            Write-Log -text "INFO: Installed: $LPfile"
        }
    }
}
function Install-AutodeskDeployment {
    param (
        [Parameter()]
        [string]$Path
    )
    Write-Log -text "INFO: Start Autodesk installer"
    # call install autodesk deployment
    # Start-Process -NoNewWindow -FilePath $Path\Install.cmd -Wait
    foreach ($ConfigFullFilename in $ConfigFullFilenames) {
        Write-Log -text "INFO: Started Installation of ConfigFile: $ConfigFullFilename"
        Start-Process -FilePath $([System.IO.Path]::Combine($Path, "Image", "Installer.exe")) -ArgumentList "-i deploy --offline_mode -q -o $ConfigFullFilename" -Wait
    }
    
    Write-Log -text "INFO: Autodesk Products installed"
}
function Uninstall-AutodeskDeployment {
    param (
        [Parameter()]
        [string]$Path
    )
    
    Write-Log -text "INFO: Start Autodesk Uninstaller"
    Start-Process -NoNewWindow -FilePath $Path\Uninstall.cmd -Wait
    Write-Log -text "INFO: Uninstalled Autodesk Products"
}
function Install-CIDEONTools {
    param (
        [Parameter()]
        [string]$Path
    )
    # install updates
    # get all updates in folder	
	
    Write-Log -text "INFO: Updates will be installed"
    $filepath = [System.IO.Path]::Combine($Path, "CDN")
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
            Write-Log -text "INFO: Installed: $($file.Name)"
        }
        catch {
            Write-Log -text "ERROR: CIDEON Install Error for: $($file.Name)"
        }
              
        
    }
}
function Move-CIDEONToolboxUnused {

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
function Copy-CIDEONTools {
    param (
        [Parameter()]
        [string]$Path
    )
    try {
        Write-Log -text "INFO: CIDEON Tools will be copied"
        $CLIENTpath = [System.IO.Path]::Combine($Path, "CLIENT")
        #array to put here multiple folder pathes in
        $Sources = @([System.IO.Path]::Combine($CLIENTpath, "ProgramData"), [System.IO.Path]::Combine($CLIENTpath, "Users"))
        # copy target must be a level obove
        $Targets = @([System.IO.Path]::Combine("C:\"), [System.IO.Path]::Combine("C:\"))
        foreach ($Source in $Sources) {
            Copy-Item -Path $Source -Destination $($Targets[$($Sources.IndexOf($Source))]) -Force -Recurse
        }
        
        Write-Log -text "INFO: CIDEON Tools copied is done"
        
    }

    catch {
        Write-Log -text "ERROR: CIDEON Tools Error for Path: $($Source)"
    }

    
}
function Uninstall-Programs {
    param (
        [Parameter()]
        [string]
        $DisplayName = '',
        [Parameter()]
        [string]
        $Publisher = ''
    )
    if ($Publisher -eq '' -and $DisplayName -eq '') {
        Write-Log -text "ERROR: No Software or Publisher specified to uninstall"
        return
    }
    $installedProducts = Get-InstalledPrograms -Publisher $Publisher -DisplayName $DisplayName
    foreach ($installedProduct in $installedProducts) {
        try {
            write-host $installedProduct.UninstallString
            #Write-Log -text "INFO: $($installedProduct) will be uninstalled"
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
            # Write-Log -text "INFO: $($installedProduct.DisplayName) is now uninstalled"
        }
        catch {
            # Write-Log -text "ERROR: $($installedProduct.DisplayName) could not be uninstalled"
        }
    }
}
function Get-InstalledPrograms {

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
    #Set PC Variables from Language
    $lngenv = Get-WinSystemLocale | Select-Object -ExpandProperty Name
    Write-Log -text "INFO: Set language Variables for $lngenv"
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
    param (
        [Parameter()]
        [string]$Version
    )
    #Set PC Variables
    Write-Log -text "INFO: Set CIDEON Variables"
    
    $CDN_VAULT_EXTENSIONS = "C:\ProgramData\Autodesk\Vault $($Version)\Extensions\"
    [System.Environment]::SetEnvironmentVariable('CDN_PROGRAMDATA', 'C:\ProgramData\CIDEON\', 'Machine')
    [System.Environment]::SetEnvironmentVariable('CDN_PROGRAM_DIR', 'C:\Program Files\CIDEON\', 'Machine')
    [System.Environment]::SetEnvironmentVariable('CDN_VAULT_EXTENSIONS', $CDN_VAULT_EXTENSIONS, 'Machine')
}
function Rename-RegistryInstallationPath {
    # if your repair the autodesk software, it will look localy to the wim
    # we change this to the serverpath
    $RegistryPath = "HKLM:\SOFTWARE\Classes\Installer\Products"
    $Registry = Get-ChildItem $RegistryPath -Recurse
    $SearchQuery = [System.IO.Path]::Combine($mountPath, "image")
    $NewValue = [System.IO.Path]::Combine($Path, [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name) , "image")

    Write-Log -text "INFO: Reg Change"

    foreach ($a in $Registry) {
        $a.Property | Where-Object {
            $a.GetValue($_) -Like "*$SearchQuery*"
        } | ForEach-Object {
            $CurrentValue = $a.GetValue($_)
            $ReplacedValue = $CurrentValue.Replace($SearchQuery, $NewValue)
            Write-Log -text "INFO: $a\$_"
            Write-Log -text "INFO: From '$CurrentValue' to '$ReplacedValue'"
            Set-ItemProperty -Path Registry::$a -Name $_ -Value $ReplacedValue
        }
    }
}
function Mount-ADSKwim {
    param (
        [Parameter()]
        [string]$wimFile,
        [Parameter()]
        [string]$Path
    )
    # mount local wim
    Mount-WindowsImage -ImagePath $wimFile -Index 1 -Path $Path | Out-Null
    Write-Log -text "INFO: WIM $wimFile mounted to $Path"
}
function Dismount-ADSKwim {
    param (
        [Parameter()]
        [string]$deleteWIM,
        [Parameter()]
        [string]$Path
    )
    # dismount the wim file and remove mount folder
    Dismount-WindowsImage -Path $Path -Discard | Out-Null
    Write-Log -text "INFO: WIM dismounted"
    if ($null -ne $deleteWIM) {
        # delete local wim file
        Remove-Item -Path $deleteWIM -Force
        Write-Log -text "INFO: WIM $deleteWIM localy deleted"
    }
    # delete local mount folder
    Remove-Item -Path $Path -Force
}
function Register-ADSKwimDismountTask {
    ## failed to cleanly dismount, so set a task to cleanup after reboot
    Write-Log -text "ERROR: WIM $WIM failed to dismounted"

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
        Write-Log -text "INFO: Created $ODISPath"
    }
    else {
        #Get
        $ODIS = Get-Item -Path $ODISPath
    }
    # Check if Property exists
    if ($null -eq $ODIS.DisableManualUpdateInstall) {
        #create 
        $ODISprop = New-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD"
        Write-Log -text "INFO: Created $($ODIS.PSPath)\DisableManualUpdateInstall with $Value"
    }
    else {
        #set
        $ODISprop = Set-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD"
        Write-Log -text "INFO: Set $($ODIS.PSPath)\DisableManualUpdateInstall to $Value"
    }
}
Function Get-SIDfromAcctName() {
    Param(
        [Parameter(mandatory = $true)]$userName
    )
    $myacct = Get-WmiObject Win32_UserAccount -filter "Name='$userName'" 
    return $myacct.sid
}
Function Set-RegistryForUser {
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
    Write-Log -text "INFO: Created $LocalFolder"
}
##################




# Get wim Files of Path
$wimFiles = Get-ChildItem -Path $Path -Filter *.wim

# Filter wim Files of specified command
$wimFiles = $wimFiles | Where-Object { $_.Name -match ($WIM + ".wim") }


foreach ($wimFile in $wimFiles) {

    Write-Log -text "INFO: WIM File: $wimFile"
    # local mount Path
    $mountPath = [System.IO.Path]::Combine($LocalFolder, "mount_" + [System.IO.Path]::GetFileNameWithoutExtension($wimFile.Name))
   
    # Configfiles
    $ConfigFullFilenames = @()
    
    # set the configfiles
    foreach ($ConfigFile in $ConfigFiles) {
        $ConfigFullFilenames += [System.IO.Path]::Combine($mountPath, "Image", $ConfigFile, ".xml")
    }


    


    #create local path
    If (!(test-path $mountPath)) {
        New-Item -Path $mountPath -ItemType Directory | Out-Null
        Write-Log -text "INFO: Created $mountPath"
    }
    

    try {
        # installation mode
        switch ($Mode) {
            "Install" { 

                # local wim filepath
                $localwimFile = [System.IO.Path]::Combine($LocalFolder, $wimFile.Name)
                Write-Log -text "INFO: Copy WIM to $LocalFolder"

                # copy wim to local path
                Copy-Item $wimFile.FullName $LocalFolder
                Write-Log -text "INFO: WIM file copied"

                # mount local wim
                Mount-ADSKwim -wimfile $localwimFile -Path $mountPath

                # check if configfile exists
                foreach ($ConfigFullFilename in $ConfigFullFilenames) {
                    if (-not [System.IO.File]::Exists($ConfigFullFilename)) {
                        throw "ConfigFile $ConfigFullFilename does not exist"
                    }
                }
    
                Write-Log -text "INFO: Get Installed Products"
                $installedApps = (Get-InstalledPrograms -Publisher "Autodesk|CIDEON")
                foreach ($installedApp in $installedApps) {
                    Write-Log -text "INFO: Installed Product: $($installedApp.DisplayName)"
                }
                # #Uninstall Desktop App, if is installed
                # Uninstall-Programs -DisplayName "Autodesk desktop-app"
                
                # onother uninstall method
                # $installedAutodeskApps = Get-CimInstance -Class Win32_Product | Where-Object { $_.vendor -match "Autodesk|CIDEON"} | Where-Object {$_.Name -match "Desktop Connect|Single Sign On"}
                # foreach ($installedAutodeskApp in $installedAutodeskApps){
                #     Write-Log -text "INFO: Uninstall $($installedAutodeskApp.Name)"
                #     $installedAutodeskApp.Uninstall()
                # }

                #Uninstall 2022 products
                Uninstall-Programs -Publisher "Autodesk" -DisplayName "Autodesk Single Sign On Component"

                
                # install autodesk software
                Install-AutodeskDeployment -Path $mountPath

                # set Autodesk Update 
                Set-AutodeskUpdate -Enable

                #updates
                #Install-Updates -Path $mountPath

                # correct the registry
                Rename-RegistryInstallationPath
				
                # copy CIDEON Tools
                Install-CIDEONTools -Path $mountPath
                Move-CIDEONToolboxUnused -Version $Version
                #Copy-CIDEONTools -Path $mountPath

                #Set Variables
                # Set-LanguageVariables
                #Set-CIDEONVariables -Version $Version

            }
            "Update" {

                # mount wim from network
                Mount-ADSKwim -wimfile $wimFile -Path $mountPath

                Install-Updates -Path $mountPath
                Copy-CIDEONTools -Path $mountPath
            }
            

            "Uninstall" {
                Uninstall-AutodeskDeployment -Path $mountPath
                Uninstall-Programs -Publisher "CIDEON"
            }
        }
        
    }
    catch {
        
        Write-Log -text "ERROR: By $Mode"
        Write-Log -text "ERROR: $($_.Exception.Message) in line $($_.InvocationInfo.ScriptLineNumber)"
    }
    finally {
        try {
            # log the installed software
            Write-Log -text "INFO: Get Installed Products"
            $installedApps = (Get-InstalledPrograms -Publisher "Autodesk" -DisplayName "Inventor Professional $Version|AutoCAD $Version|AutoCAD Mechanical $Version|Vault $Version") 
            $installedApps += (Get-InstalledPrograms -Publisher "CIDEON") 
            foreach ($installedApp in $installedApps) {
                Write-Log -text "INFO: Installed Product: $($installedApp.DisplayName) |  $($installedApp.DisplayVersion)"
            }

            # dismount and delete local wim, if copied
            Dismount-ADSKwim -Path $mountPath -deleteWIM $localwimFile

        }
        catch {
            Register-ADSKwimDismountTask
        }
        finally {
            
            # copy log to server
            Copy-Item $global:LogFile $([System.IO.Path]::Combine($Path, "_LOG", "$env:computername.log"))
            # delete local logfile
            Remove-Item $global:LogFile -Recurse
        }
    }
}


#endregion
