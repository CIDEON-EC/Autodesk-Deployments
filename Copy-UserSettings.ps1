function Copy-CIDEONTools {
    param (
        [Parameter()]
        [string]$Path
    )
    try {
        Write-Debug "INFO: CIDEON Tools will be copied"
        $CLIENTpath = [System.IO.Path]::Combine($Path, "CLIENT")
        #array to put here multiple folder pathes in
        $Sources = @([System.IO.Path]::Combine($CLIENTpath, "Appdata","*"))
        # copy target must be a level obove
        $Targets = @([System.IO.Path]::Combine($env:USERPROFILE,"Appdata","Roaming" ))
        foreach ($Source in $Sources) {
            Copy-Item -Path $Source -Destination $($Targets[$($Sources.IndexOf($Source))]) -Force -Recurse
        }
        
        Write-Debug "INFO: CIDEON Tools copied is done"
        
    }

    catch {
        Write-Debug "ERROR: CIDEON Tools Error for Path: $($Source)"
    

    }
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
        Write-Debug  "INFO: Created $ODISPath"
    }
    else {
        #Get
        $ODIS = Get-Item -Path $ODISPath
    }
    # Check if Property exists
    if ($null -eq $ODIS.GetValue("DisableManualUpdateInstall")) {
        #create 
        $ODISprop = New-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD"
        Write-Debug  "INFO: Created $($ODIS.PSPath)\DisableManualUpdateInstall with $Value"
    }
    else {
        #set
        $ODISprop = Set-ItemProperty -Path $ODIS.PSPath -Name "DisableManualUpdateInstall" -Value $Value -PropertyType "DWORD"
        Write-Debug  "INFO: Set $($ODIS.PSPath)\DisableManualUpdateInstall to $Value"
    }
}



#Set-AutodeskUpdate -ShowOnly
Copy-CIDEONTools -Path "\\vaultsrv\CIDEON\_DPL\2024_PDC_VLT"