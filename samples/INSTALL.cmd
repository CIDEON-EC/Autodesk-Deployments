@ECHO OFF
set skript=%~dp0\Install-ADSK.ps1
set image=20XX_PDC_VLT
set imagepath=\\SERVER\SHARE\DEPLOYMENT

powershell.exe -ExecutionPolicy Bypass -File %skript% -Image %image% -Mode "Install" -Path %imagepath% -Logging -Purge

REM If another Collection file should be usesd, the following line can be used:
REM powershell.exe -ExecutionPolicy Bypass -File %skript% -Image %image% -Mode "Install" -Path %imagepath% -Files "INV_VLT" -Logging -Purge

REM If multiple Collection files should be installed, the following line can be used:
REM powershell.exe -ExecutionPolicy Bypass -File %skript% -Image %image% -Mode "Install" -Path %imagepath% -Files "INV_ONLY","VAULT" -Logging -Purge


PAUSE