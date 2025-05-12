[CmdletBinding(SupportsShouldProcess = $true)]Param (
    [Parameter(Mandatory = $true, HelpMessage = 'Path to the folder containing the subfolder "Local"')]
    [string]$Path,

    [Parameter(Mandatory = $true, HelpMessage = 'folders to copy')]
    [string[]]$folder = @("ProgramData", "Users")
)

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
    Param
    (
        [Parameter(Mandatory)]
        [string]$text,
        [Parameter()]
        [switch]$Info,
        [Parameter()]
        [switch]$Fail
    )
    if ($Logging.IsPresent) {
        $category = "INFO"
        if ($Info.IsPresent) {
            $category = "INFO"
        }
        if ($Fail.IsPresent) {
            $category = "ERROR"
        }
        "$(get-date -format "yyyy-MM-dd HH:mm:ss.ms") [$($category)] $($text)" | out-file "$script:LogFile" -Append
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
    
    .EXAMPLE
        Copy-Local
        Copy-Local -Path "C:\Temp\PDC_20XX"
    
    .NOTES
        Autor: Timon Först
        Datum: 16.04.2025

        Formally this was function was called Copy-CIDEONTools, but this was not a good name, because it is not only copying CIDEON Tools, but also the local files.
    #>
    
    param (
        [Parameter()]
        [string]$Path = $Script:mountPath,
        [Parameter()]
        [string[]]$SourceFolder = @("ProgramData", "Users"),
        [Parameter()]
        [string[]]$TargetFolder = @("C:\", "C:\")
    )
    try {
        Write-InstallLog -text "Local Folders will be copied" -Info

        #check if the array sizes from source and target are the same
        if ($SourceFolder.Count -ne $TargetFolder.Count) {
            Write-InstallLog -text "Source and Target quantites must be the same" -Fail
            return
        }
        # copy
        foreach ($Source in $SourceFolder) {
            $localpath = [System.IO.Path]::Combine($Path, "Local", $Source)
            Write-InstallLog -text "Local folder $Source" -Info

            # exception for Users folder, because we have to copy it to the user profile folder
            if ($Source -eq "Users") {
                # get subfolders in Users folder
                $UsersFolder = Get-ChildItem -Path $localpath -Directory

                # for every subfolder in Users
                foreach ($userFolder in $UsersFolder) {

                    # check folder USERNAME, this is the folder for the current user
                    if ($userFolder.Name -eq "USERNAME") {

                        # Find the "normal" (non-elevated) user name
                        try {
                            # Get the explorer process to find the normal user name
                            $explorerProc = Get-Process -Name explorer -ErrorAction Stop | Select-Object -First 1
                            # Get the owner of the explorer process
                            $normalUserName = (Get-WmiObject Win32_Process -Filter "ProcessId = $($explorerProc.Id)").GetOwner().User

                            Write-InstallLog -text "Username $normalUserName seems the normal User" -Info
                        }
                        catch {
                            Write-InstallLog -text "Could not determine normal user name." -Fail
                            continue
                        }
                        # copy the folder to the user profile folder
                        Copy-Item -Path $userFolder.FullName -Destination [System.IO.Path]::Combine($($TargetFolder[$($SourceFolder.IndexOf($Source))]), "Users", $normalUserName) -Force -Recurse
                    }
                    # copy the other folders to the target folder (e.g. "Public")
                    else {
                        Copy-Item -Path $userFolder.FullName -Destination [System.IO.Path]::Combine($($TargetFolder[$($SourceFolder.IndexOf($Source))]), "Users", $userFolder.Name) -Force -Recurse
                    }
                }



            }
            # normal case for ProgramData and other folders
            else {
                Copy-Item -Path $localpath -Destination [System.IO.Path]::Combine($($TargetFolder[$($SourceFolder.IndexOf($Source))])) -Force -Recurse
            }
        }

        
        Write-InstallLog -text "Local Folders is done" -Info
        
    }

    catch {
        Write-InstallLog -text "Local Folders error for path $($Source): $($_.Exception.Message)" -Fail
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
        Write-InstallLog -text "Created $ODISPath" -Info
    }
    else {
        #Get
        $ODIS = Get-Item -Path $ODISPath
    }
    # Check if Property exists
    if ($null -eq (Get-ItemProperty -Path $ODIS.PSPath).DisableManualUpdateInstall) {
        #create 
        New-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD" | Out-Null
        Write-InstallLog -text "Created $($ODIS.PSPath)\DisableManualUpdateInstall with $Value" -Info
    }
    else {
        #set
        Set-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value | Out-Null
        Write-InstallLog -text "Set $($ODIS.PSPath)\DisableManualUpdateInstall to $Value" -Info
    }
}
# need for default Copy-Local path
$mountPath = $Path

## Main Script

$targetFolder = @()
# fill targetfolder with "C:" for each source folder
foreach ($source in $folder) {
    $targetFolder += "C:\"
}

#Set-AutodeskUpdate -ShowOnly
Copy-Local -Path $Path -SourceFolder $folder -TargetFolder $TargetFolder