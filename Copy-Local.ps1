[CmdletBinding(SupportsShouldProcess = $true)]Param (
    [Parameter(Mandatory = $true, HelpMessage = 'Path to the folder containing the subfolder "Local"')]
    [string]$Path,

    [Parameter(Mandatory = $true, HelpMessage = 'folders to copy')]
    [string[]]$Folder = @("ProgramData", "Users"),

    [Parameter(Mandatory = $false, HelpMessage = 'target folders for the copy operation. Default is C:\ for all folders')]
    [string[]]$TargetFolder = @(foreach ($source in $Folder) { "C:\" })
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
        "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss.ms") [$($category)] $($text)" | Out-File "$script:LogFile" -Append
    }
    
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
        #Write-Log -text "CIDEON Tools will be copied" -Info
        $localpath = [System.IO.Path]::Combine($Path, "Local")

        #check if the array sizes from source and target are the same
        if ($SourceFolder.Count -ne $TargetFolder.Count) {
            #Write-Log -text "Source and Target inputs have not the same folder counts" -Fail
            return
        }
        # copy
        foreach ($Source in $SourceFolder) {

            if ($Source -eq "Users") {
                # get subfolders in Users folder
                $UsersFolder = Get-ChildItem -Path ([System.IO.Path]::Combine($localpath, $Source)) -Directory

                # for every subfolder in Users
                foreach ($userFolder in $UsersFolder) {
                    # check folder USERNAME, this is the folder for the current user
                    if ($userFolder.Name -eq "USERNAME") { $subfolder = $env:Username }
                    # if not USERNAME, use the folder name, e.g. "Public"
                    else { $subfolder = $userFolder.Name }

                    # copy the content of the user folder to the target folder
                    $from = ([System.IO.Path]::Combine($userFolder.FullName, "*"))
                    $to = ([System.IO.Path]::Combine($($TargetFolder[$($SourceFolder.IndexOf($Source))]), "Users", $subfolder))
                    Copy-Item -Path $from -Destination $to -Force -Recurse
                    Write-InstallLog -text "Copy-Local copied from $($from) to $($to)" -Info
                }
            }
            # normal case for ProgramData and other folders
            else {
                $localpath = [System.IO.Path]::Combine($Path, "Local", $Source)
                $from = $localpath
                $to = ([System.IO.Path]::Combine($($TargetFolder[$($SourceFolder.IndexOf($Source))])))
                Copy-Item -Path $from -Destination $to -Force -Recurse
                Write-InstallLog -text "Copy-Local copied from $($from) to $($to)" -Info
            }
        }
        

    }
  

    catch {
        Write-InstallLog -text "Copy-Local Error for Path: $($Source)" -Fail
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

## Main Script

#Set-AutodeskUpdate -ShowOnly
Copy-Local -Path $Path -SourceFolder $Folder -TargetFolder $TargetFolder