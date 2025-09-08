@ECHO OFF
set skript=\\SERVER\SHARE\ScriptLocation\WIM-AppDeploy.ps1
set wim=20XX_PDC_VLT
set wimpath=\\SERVER\SHARE\DEPLOYMENT

powershell.exe -ExecutionPolicy Bypass -File %skript% -WIM %wim% -Mode "Install" -Path %wimpath% -Logging -Purge

REM If another Collection file should be usesd, the following line can be used:
REM powershell.exe -ExecutionPolicy Bypass %skript% -WIM %wim% -Mode "Install" -Path %wimpath% -Files "INV_VLT" -Logging -Purge

REM If multiple Collection files should be installed, the following line can be used:
REM powershell.exe -ExecutionPolicy Bypass %skript% -WIM %wim% -Mode "Install" -Path %wimpath% -Files "INV_ONLY","VAULT" -Logging -Purge


PAUSE