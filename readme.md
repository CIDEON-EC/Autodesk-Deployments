# Contents in deployment folder
by default the following example is automatically available "Install INV2022.bat"
```
chcp 65001

rem ========== Install the deployment with basic UI ==========
"\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\Installer.exe" -i deploy --offline_mode --ui_mode basic -o "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\Collection.xml" --installer_version "1.21.0.25"

rem ========== Install the deployment silently ==========
rem "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\Installer.exe" -i deploy --offline_mode -q -o "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\Collection.xml" --installer_version "1.21.0.25"

rem ========== Uninstall the individual product ==========

rem ========== Uninstall Autodesk Inventor Professional 2022 - Deutsch (German)
rem "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\Installer.exe" -i uninstall -q --manifest "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\INVPROSA_2022_de-DE\setup.xml" --extension_manifest "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\INVPROSA_2022_de-DE\setup_ext.xml"

rem "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\Installer.exe" -i uninstall -q --manifest "\\mx-srv-vault22\CIDEON\_DPL\INV_2022\image\ODIS\setup.xml"
```

# Create bat for WIM-AppDeploy.ps1 commands
we need a "Install.cmd" and a "Uninstall.cmd" we can create from the template above

## Install.cmd
```
@ECHO OFF
chcp 65001

ECHO ========== Install the deployment silently ==========
%~dp0image\Installer.exe -i deploy --offline_mode -q -o %~dp0image\Collection.xml --installer_version "1.21.0.25"

```
## Uninstall.cmd
```
@ECHO OFF
chcp 65001

ECHO ========== Uninstall the deployment silently ==========
%~dp0image\Installer.exe -i uninstall -q --manifest %~dp0image\AMECH_PP_2022_de-DE\setup.xml --extension_manifest %~dp0image\AMECH_PP_2022_de-DE\setup_ext.xml

```