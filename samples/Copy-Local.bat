@ECHO OFF
set skript=\\vaultsrv\CIDEON\_DPL\Copy-Local.ps1

REM powershell.exe -ExecutionPolicy Bypass %skript% -Path "\\vaultsrv\CIDEON\_DPL" -Folder "Users"

REM Default folders are "Users" and "ProgramData"
powershell.exe -ExecutionPolicy Bypass -File %skript% -Path "\\vaultsrv\CIDEON\_DPL"