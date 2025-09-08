@ECHO OFF
set skript=\\SERVER\SHARE\ScriptLocation\WIM-handler.ps1
set wim=20XX_PDC_VLT
set wimpath=\\SERVER\SHARE\DEPLOYMENT

powershell.exe -ExecutionPolicy Bypass -File %skript% -WIM %wim% -Mode "DismountSave" -Path %wimpath%

PAUSE