[CmdletBinding(SupportsShouldProcess = $true)]Param (
    [Parameter(Mandatory = $true, HelpMessage = 'Path to the folder containing the subfolder "Local"')]
    [string]$Path,

    [Parameter(Mandatory = $true, HelpMessage = 'folders to copy')]
    [string[]]$folder = @("ProgramData", "Users")
)


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

$targetFolder = @()
# fill targetfolder with "C:" for each source folder
foreach ($source in $folder) {
    $targetFolder += "C:\"
}

#Set-AutodeskUpdate -ShowOnly
Copy-Local -Path $path -SourceFolder $folder -TargetFolder $targetFolder