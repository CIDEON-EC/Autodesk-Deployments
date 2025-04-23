@ECHO OFF
skript="\\vaultsrv\CIDEON\_DPL\Copy-Local.ps1"

powershell.exe -ExecutionPolicy Bypass %skript% -Path "\\vaultsrv\CIDEON\_DPL" -Folder "User"

REM Default folders are "User" and "ProgramData"
REM powershell.exe -ExecutionPolicy Bypass %skript% -Path "\\vaultsrv\CIDEON\_DPL"