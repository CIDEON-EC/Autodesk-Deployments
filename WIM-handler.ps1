<#
.SYNOPSIS
    Use and create wim files
.DESCRIPTION
    Options to create a wim file from a folder.
	Or you can just mount/dismount it. It copys the wim file in to a temporary local folder.
.PARAMETER Path
    The path to the WIM file.
	Default is script location.
	So in most cases you don't need to use it.
.PARAMETER WIM
    Name of the WIM file you want to use or create.
.PARAMETER LocalFolder
    Local folder where the wim file should be downloaded and mapped.
	Default is C:\Temp
.PARAMETER Mode
	Mode to use or create wim files
	Available: Mount, Dismount, DismountSave (Save changes), Create (Foldername = Wimname)
	Creation should be made localy on the server, because Admin privileges and shares are
	always a little bit tricky
.EXAMPLE
cd \\SERVER\SHARE\ScriptLocation
.\WIM-Handler.ps1 -WIM "INV_2022" -Mode "Create"

#If not script and Deployments are in the same folder:
.\WIM-handler.ps1 -Path "\\UNCPATH\FOLDER" -WIM "INV_2022" -Mode "Mount"
.NOTES
    Author: Timon Först
    Date:   22.03.2022
#>
[CmdletBinding(SupportsShouldProcess = $true)]Param (
	[Parameter(Mandatory = $false, HelpMessage = 'Serverpath of wim file \\server\CIDEON\_DPL')]
	[ValidateNotNullOrEmpty()]
	#[String]$Path = "\\mx-srv-vault22\CIDEON\_DPL",
	[String]$Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.\'),

	[Parameter(Mandatory = $true, HelpMessage = 'Name of the wim file, wothout .wim')]
	[ValidateNotNullOrEmpty()]
	[String]$WIM = "",

	[Parameter(Mandatory = $false, HelpMessage = 'Local Path C:\Temp')]
	[ValidateNotNullOrEmpty()]
	[String]$LocalFolder = "C:\Temp",

    [Parameter(Mandatory = $true, HelpMessage = 'Mount, Dismount, DismountSave (Save changes), Create (Foldername = Wimname)')]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Mount", "Dismount", "DismountSave", "Create")]
	[string]$Mode

)
if([string]::IsNullOrEmpty($Path)){
   $Path = $PSScriptRoot
}
#
$DebugPreference = 'SilentlyContinue'
$WIMFILE = [System.IO.Path]::Combine($Path, $WIM + ".wim")
$LogFile = [System.IO.Path]::Combine($Path, $WIM + ".log")
$mountPath = [System.IO.Path]::Combine($LocalFolder, "mount_" + $WIM)
$FolderToWIM = [System.IO.Path]::Combine($Path, $WIM)

If(!(test-path $LocalFolder))
{
      New-Item -ItemType Directory -Force -Path $LocalFolder
}
# Write-Host $WIMFILE
# Write-Host $FolderToWIM
# Write-Host $LogFile

switch ($Mode) {
    "Mount" { 
      If(!(test-path $mountPath))
      {
            New-Item -ItemType Directory -Force -Path $mountPath
      }
        mount-windowsimage -Imagepath $WIMFILE -Index 1 -Path $mountPath
     }
     "Dismount"{
        Dismount-WindowsImage -Path $mountPath -Discard
        Remove-Item -Path $mountPath -Force
     }
     "DismountSave"{
        Dismount-WindowsImage -Path $mountPath -save
        Remove-Item -Path $mountPath -Force
     }
     "Create"{
        New-WindowsImage -ImagePath $WIMFILE -CapturePath $FolderToWIM -Name $WIM -LogPath $LogFile -Compress:fast
     }

}
