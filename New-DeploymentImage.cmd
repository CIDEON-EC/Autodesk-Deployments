@ECHO OFF
REM Drag a deployment folder onto this file to create a .vhdx image next to it.
REM Tip: put a shortcut to this file into shell:sendto, then right-click the folder > Send to > New-DeploymentImage.
IF "%~1"=="" (
    ECHO Drag a deployment folder onto this file.
    PAUSE
    EXIT /B 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DeploymentImage.ps1" -Source "%~1" -Pause
IF ERRORLEVEL 1 PAUSE
