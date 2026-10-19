@ECHO OFF
set image=20XX_PDC_VLT
set imagepath=\\SERVER\SHARE\DEPLOYMENT
set skript=%imagepath%\Install-ADSK.ps1

powershell.exe -ExecutionPolicy Bypass -File "%skript%" -Image %image% -Mode "Install" -Path %imagepath% -Logging -Purge

REM Optional parameters of Install-ADSK.ps1 (append to the call above):
REM   -Files "INV_VLT"             Other Collection file(s) without extension, default "Collection". Multiple: -Files "INV_ONLY","VAULT"
REM   -LocalFolder "D:\Temp"       Local folder for the image copy and logs, default C:\Temp
REM   -Version 2027                Software version, default: 4 digit number from the image name
REM   -NoDownload                  Mount a .wim from the server instead of copying it (not with .vhdx, not with -Purge)
REM   -ModuleVersionPin 3.0.0      Use a specific GitHub Release of the module instead of the latest
REM   -Quiet                       Suppress output messages
REM   -ForceQuit                   Close blocking Autodesk processes without asking
REM   -WhatIf                      Dry run, no changes are made
REM   -Confirm                     Ask before each action

PAUSE
