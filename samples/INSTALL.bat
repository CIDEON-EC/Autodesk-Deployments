@ECHO OFF
skript="\\vaultsrv\CIDEON\_DPL\WIM-AppDeploy.ps1"
wim="20XX_PDC_VLT"
wimpath="\\vaultsrv\CIDEON\_DPL"

powershell.exe -ExecutionPolicy Bypass %skript% -WIM %wim% -Mode "Install" -Path %wimpath% -Logging -Purge

REM If another Collection file should be usesd, the following line can be used:
REM powershell.exe -ExecutionPolicy Bypass %skript% -WIM %wim% -Mode "Install" -Path %wimpath% -Files "INV_VLT" -Logging -Purge

REM If multiple Collection files should be installed, the following line can be used:
REM powershell.exe -ExecutionPolicy Bypass %skript% -WIM %wim% -Mode "Install" -Path %wimpath% -Files "INV_ONLY","VAULT" -Logging -Purge


PAUSE