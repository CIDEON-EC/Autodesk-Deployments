# Install
```
.\WIM-AppDeploy.ps1 -WIM "VAULT_PRO_2022" -Mode "Install"
.\WIM-AppDeploy.ps1 -WIM "VAULT_PRO_2022" -Mode "Install" -Path "\\mx-srv-dfs01\bara-DIP\dip\Apl\Autodesk2022\Autodesk-Install"
```
# Uninstall
```
.\WIM-AppDeploy.ps1 -WIM "VAULT_PRO_2022" -Mode "Uninstall"
```

# Call from external (Software Deployment)
```batch
powershell.exe -ExecutionPolicy Bypass .\WIM-AppDeploy.ps1 -WIM "INV_2022" -Mode "Install"
```
# Call from external when script and wim are not in the same folder (Software Deployment)
```batch
powershell.exe -ExecutionPolicy Bypass .\WIM-AppDeploy.ps1 -Path "\\mx-srv-dfs01\bara-DIP\dip\Apl\Autodesk2022\Autodesk-Install" -WIM "INV_2022" -Mode "Install"
```