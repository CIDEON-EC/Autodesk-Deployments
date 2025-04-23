# Mount wim file
```
.\WIM-handler.ps1 -WIM "ACADM_2022" -Mode "Mount"
.\WIM-handler.ps1 -Path "\\mx-srv-vault22\CIDEON\_DPL" -WIM "ACADM_2022" -Mode "Mount"
```
# Dismount
```
.\WIM-handler.ps1 -WIM "ACADM_2022" -Mode "Dismount"
```
# Dismount and Save changes
```
.\WIM-handler.ps1 -WIM "ACADM_2022" -Mode "DismountSave"
```
# create new wim
WIM Name = foldername of deployment
```
.\WIM-handler.ps1 -WIM "ACADM_2022" -Mode "Create"
```
