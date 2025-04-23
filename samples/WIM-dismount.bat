@ECHO OFF
skript="\\vaultsrv\CIDEON\_DPL\WIM-handler.ps1"
wim="20XX_PDC_VLT"
wimpath="\\vaultsrv\CIDEON\_DPL"

powershell.exe -ExecutionPolicy Bypass %skript% -WIM %wim% -Mode "Dismount" -Path %wimpath%

PAUSE