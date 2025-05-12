# Install Autodesk Deplyoments with WIM

We have two powershell files that manage everything.
- WIM-handler.ps1 (creates from a folder a WIM file)
- WIM-AppDeploy.ps1 (installation script)

## Workflow
1. Create a Autodesk Deployment and download it locally
    - Copy the Collection.xml and modify it (e.g. you want a Version without AutoCAD)
2. Add folders to provide additionally updates, Cideon Tools and local configuration files (optional)
    - The folders Update, Cideon, Local are hardcoded foldernames you have to use
3. Create a WIM from this folder
    - For simplicity copy the WIM-handler.ps1 parallel to the deployment folder
4. Change the WIM-Appdeploy.ps1 for your needs
5. Install

## Sample folder structure
The folder structure is based on the default Autodesk deployments. This could be look like this:
```plaintext
├──  PDC_20XX                   (name of the Autodesk deployment)
│   ├── image                   (default from Autodesk deployment)
│   │   ├── AMECH_PP_20XX_de-DE
│   │   |    ├── ...
│   │   |    ├── setup.xml      (contains product to install)
│   │   |    └── setup_ext.xml  (contains updates and language packs)
│   │   ├── INVPROSA_20XX_de-DE
│   │   ├── ...
│   │   ├── Collection.xml
│   │   ├── Inventor_only.xml   (modified version of Collection.xml)
│   │   └── ...
│   ├── Updates                 (additionally updates to install)
│   │   ├── Update_Inventor_20XX.X.exe
│   │   └── Update_AutoCAD_20XX.X.exe
│   ├── Cideon                  (Cideon Tools)
│   │   ├── CIDEON.VAULT.TOOLBOX.SETUP_XXXX.X.X.XXXXX.msi
│   │   ├── CIDEON.Inventor.Toolbox_x64_XXXX.X.X.XXXXX.msi
│   │   └── CDN_DataStandards_Setup_XXXX.X.X.XXXXX.msi
│   └── Local                   (local configuration files)
│       ├── ProgramData
│       └── Users
│           ├── Public          (Public user folder)
│           │   └── Documents
│           │       └── CIDEON
│           │           └── LicenseFiles
│           │               └── 20XX
│           └── USERNAME        (local user folder, will be renamed to the actual username)
│               └── AppData
│                    └── Roaming
│                        └── Autodesk
└── WIM-handler.ps1
```
## Create a WIM
We use for thet the WIM-handler.ps1. We can create, mount, dismount and dismountSave (modify) a wim file.
Either you can call the powershell directly or with a batch file (like in the sample folder).


You could simply go to the folder, where the deployment is stored and call the powershell:
```powershell
# Go to the main folder, where the deployment is stored and where the WIM-handler.ps1 is
cd C:\temp
# Create the wim file. The name of the Autodesk deplyoment must be named with "-WIM"
.\WIM-handler.ps1 -WIM PDC_20XX -Mode "Create"
```
All arguments are documented in the WIM-handler.ps1

## Change the WIM-Appdeploy.ps1 for your needs
You can find the ps1 in two sections
1. Functions
    - In the Functions area you can find all pre defined commands.
2. Code
    - You can find the "Install", "Uninstall" and "Update" section. Here you can modify your own needs.
All Functions are documented in the ps1 file itself.


## FAQ
### What if I need to change the Autodesk deployment or change/add files?
The fastest way is just to create a new WIM file from the deplyoment folder
<br><br><br>

### How to call the powershells and with wich parameters?
You can find batch files in the subfolder "samples" for all the basic scenarios.
<br><br><br>

### How can I copy file to the ProgramData folder or to the Users folder after installation?
Ha, I got you!
For this you can find the Copy-Local.ps1. A sample call you can also find in the samples folder.

This allows you to copy (by default the ProgramData and Users Folder) from the central stored deployment folders.

<h5 a><strong><code>Copy-Local.bat</code></strong></h5>

```cmd
@ECHO OFF
skript="\\vaultsrv\CIDEON\_DPL\Copy-Local.ps1"

powershell.exe -ExecutionPolicy Bypass %skript% -Path "\\vaultsrv\CIDEON\_DPL" -Folder "Users"

REM Default folders are "Users" and "ProgramData"
REM powershell.exe -ExecutionPolicy Bypass %skript% -Path "\\vaultsrv\CIDEON\_DPL"
```
<br><br><br>

### What are the parameters for the WIM-AppDeploy.ps1?
You can find this in the file itself, but here is a overview.
- WIM
   -  Mandatory. Name of the WIM file you want to use.
- Mode
    - Mandatory. Available is: Install, Uninstall, Update
	- Mode that you want to execute. Start the batchfile  inside the wim file.
- Path
    - Optional. The path to the WIM file. Default is script location.
	- You don't need to set it, when the WIM file is in the same folder as the script.
- LocalFolder
    - Optional. Local folder where the wim file should be downloaded and mapped.
	- Default is C:\Temp
    - You have to set this, if you have localy only in specified folder install rights.
- Files
    - Optional. Array of XML filenames WIHOUT extension, default "Collection"
    - Files that should be used for the installation.
- Version
    - Optional. The Software Version for installing cideon tools and logging.
    - It will be extracted from the WIM name, if a 4 digit number is found.    
- Logging
    - Optional. Enable log file. The log file will be created in the local folder.
- NoDownload
    - Optional. Disable Copying of the WIM file to the local folder. The WIM file will be mounted from the server.
- Purge
    - Optional. Deletes the WIM file after finishing the script. NOT COMBINED with NoDownload!
<br><br><br>

### How can I call the WIM-AppDeploy?
```powershell
# Go to the script location
cd \\SERVER\SHARE\ScriptLocation
# Call Installation
## Path is needed because the deplyoment is stored on another location
## Logging enabled
## Purge enabled (deletes WIM localy)
.\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Path "\\SERVER\SHARE\DEPLOYMENT" -Logging -Purge
```
```powershell
# Call Installation
## Path is not needed, because WIM-AppDeploy.ps1 is parallel to the deplyoment folder
## Logging enabled
## The wim will not downloaded, it will be mounted from the server directly (slower installation)
## Instead of default Collection.xml, the Inventor_only.xml is used
.\WIM-AppDeploy.ps1 -WIM "PDC_20XX" -Mode "Install" -Logging -NoDownload -Files "Inventor_only"
```