###############################################################################################################################################
#script for CIDEON Vault Prof. Int. to SAP Synchronization Server
#INPUT
## Use Sample Data?
$DebugPreference = 'Continue'
$ErrorActionPreference = "SilentlyContinue"
$DebPrefValue = $true
$LogFile = "C:\temp\INTERN_PrioList.txt"
$ofs = "," #Separator für [string]
################################################



#Region funktionen

[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.Connectivity.WebServices.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.Connectivity.Explorer.Extensibility.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.Connectivity.Explorer.ExtensibilityTools.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.Connectivity.Extensibility.Framework.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.DataManagement.Client.Framework.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.DataManagement.Client.Framework.Forms.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.DataManagement.Client.Framework.Vault.dll")
# [System.Reflection.Assembly]::LoadFrom("C:\ProgramData\Autodesk\Vault 2023\Extensions\VaultSapInterface\VaultSapInterface.dll")
[System.Reflection.Assembly]::LoadFrom("C:\program files\Autodesk\Vault Client 2023\Explorer\Autodesk.DataManagement.Client.Framework.Vault.Forms.dll")
# [System.Reflection.Assembly]::LoadWithPartialName("VaultSapInterface.Vault.ClLinkVaultItemSAPMaterials");

[System.Reflection.Assembly]::LoadFrom("C:\ProgramData\Autodesk\Vault 2023\Extensions\Cideon.Shared\CIDEON_GENERAL_TOOLS.dll")
[System.Reflection.Assembly]::LoadFrom("C:\ProgramData\Autodesk\Vault 2023\Extensions\Cideon.Shared\CIDEON_VAULT_ITEM_TOOLS.dll")
[System.Reflection.Assembly]::LoadFrom("C:\ProgramData\Autodesk\Vault 2023\Extensions\Cideon.Shared\CIDEON_VAULT_DOCUMENT_TOOLS.dll")
[System.Reflection.Assembly]::LoadFrom("C:\ProgramData\Autodesk\Vault 2023\Extensions\Cideon.Shared\CIDEON_VAULT_TOOLS.dll")

function Find-VLT {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]$Arguments,
		[Parameter(Mandatory)][ValidateSet('ITEM', 'FILE', 'FLDR', 'FILEFLDR', 'CO', 'CUSTENT')][string[]]$Class,
		[Parameter()]$Path = "$/"
	)
	DynamicParam {
		# convert string path in array
		if ($Path -is [String]) {
			$Path = @($Path)
		}
	}
	process {
		# Create Search Arguments
		$searchArgs = Get-VLTSearchConditions -Arguments $Arguments -Class $Class
		# Start Search
		$result = Invoke-VLTSearch -Class $Class -Arguments $searchArgs -Path $Path
		# return
		return $result
	}


}

function CS_UpdateItem($Item) {
	$ItemNum = $item.ItemNum
	$files = @();

	$Item = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemObjectByMasterID($Item.MasterId)

	Write-Debug "[CS_UpdateItem]Aktualisieren des Artikels: $ItemNum"

	$ItemHistotic = $serviceManager.ItemService.GetItemHistoryByItemMasterId($Item.MasterId, [Autodesk.Connectivity.WebServices.ItemHistoryTyp]::All)
	$EditItem = $serviceManager.ItemService.GetLatestItemByItemMasterId($Item.MasterId)
	$EditItems = New-Object "System.Collections.Generic.List[Long]"
	try {
		$serviceManager.ItemService.UpdatePromoteComponents(@($EditItem.RevId), [Autodesk.Connectivity.WebServices.ItemAssignAll]::Default, $false)
		$TStamp = New-Object "System.DateTime"
		$PropOrder = $serviceManager.ItemService.GetPromoteComponentOrder([ref]$TStamp)
		if ($PropOrder.PrimaryArray -ne $null) {
			$serviceManager.ItemService.PromoteComponents($TStamp, $PropOrder.PrimaryArray)
			$serviceManager.ItemService.PromoteComponentLinks($PropOrder.PrimaryArray)
		}


		if ($PropOrder.NonPrimaryArray -ne $null) {
			$serviceManager.ItemService.PromoteComponents($TStamp, $PropOrder.NonPrimaryArray)
			$serviceManager.ItemService.PromoteComponentLinks($PropOrder.NonPrimaryArray)
		}

		$ItemAndFiles = $serviceManager.ItemService.GetPromoteComponentsResults($TStamp)

		foreach ($element in $ItemAndFiles.ItemRevArray) {
			$EditItems.Add($element.Id)
			try {
				$serviceManager.ItemService.UpdateAndCommitItems(@($element))
			}
			catch {
				try {
					$serviceManager.ItemService.UndoEditItems(@($element.Id))
				}
				catch {

				}
			}
		}
	}
	catch {
		$serviceManager.ItemService.UndoEditItems($EditItems.ToArray())
	}
}
function Set-VLTInventorMaterial {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$file,
		[Parameter(Mandatory)]
		[string]$Material,
		[Parameter()]
		[switch]$SaveDocument,
		[Parameter()]
		[switch]$QuitOnEnd
	)
	try {
		Write-Debug "Datei wird herunterladen"
		# Abholen der aktuelle FileID
		$file = $CIDEON_VAULT_DOCUMENT_TOOLS.CDN_GetLatestFileObjectByMasterFileID($file.MasterId);

		########### CHECK OUT single DRAWING
		# Download first all depencys
		$fileDepencies = $CIDEON_VAULT_DOCUMENT_TOOLS.DownloadFileAndDependencysToFolder($file, $null, $false, $null, $false, $true)
		# checkout the attachment
		$CheckoutResult = $CIDEON_VAULT_DOCUMENT_TOOLS.DownloadAndCheckoutFileByFileObjectToPath($file)

		#Schreiben des betroffenen Filenames inklusive Pfade in $SourceFileFullName
		$SourceFileFullName = $CheckoutResult.FileResults[0].LocalPath.FullPath

		#Aufruf des Debuglog
		Write-Debug "Datei wurde heruntergeladen $SourceFileFullName"

		Add-Type -Path ("C:\WINDOWS\Microsoft.Net\assembly\GAC_MSIL\Autodesk.Inventor.Interop\v4.0_27.4.0.0__d84147f8b4276564\Autodesk.Inventor.Interop.dll")

		if ($InventorObject) {
			# Inventor Server
			Write-Information "INVENTOR SERVER"
			$inventor = $InventorObject
		}
		else {
			Write-Information "INVENTOR APP"
			try {
				Write-Debug "Inventor Sitzung wird gesucht"
				$inventor = [Runtime.Interopservices.Marshal]::GetActiveObject('Inventor.Application')
				Write-Debug "Inventor Sitzung wurde gefunden"
			}
			catch {
				Write-Debug "Inventor wird neu geöffnet"
				$inventorAppType = [System.Type]::GetTypeFromProgID("Inventor.Application");
				$inventor = [System.Activator]::CreateInstance($inventorAppType)
				Write-Debug "Inventor wurde geöffnet"
			}
			finally {
				# Set Inventor to silent to supress all dialogs
				$inventor.SilentOperation = $true
			}
		}


		Write-Debug "Dokument wird geöffnet"

		$document = $inventor.Documents.Open($SourceFileFullName, $false)
		Write-Debug "Dokument wurde geöffnet"

		if ($document.ismodifiable) {
			$matlib = $inventor.ActiveMaterialLibrary
			Write-Debug "Materialbibliothek $($matlib.DisplayName)"
			$mat = $matlib.MaterialAssets | Where-Object { $_.DisplayName -eq $Material }
			if ($null -ne $mat) {
				Write-Debug "Material $Material setzten"
				$document.ActiveMaterial = $mat
				$activematerial = $document.ComponentDefinition.Material.Name
				Write-Debug "Material $activematerial ist gesetzt"
				if ($activematerial -ne $Material) {
					Write-Error "Material ist nicht wie gewünscht geändert worden"
				}
			}
			else {
				Write-Error "Material $Material nicht gefunden"
			}
		}
		else {
			Write-Error "Bibliotheksdatei: $($document.FullFileName)"
		}





		if ($SaveDocument) {
			Write-Debug "Dokument speichern"
			$document.Save2($false)
		}
		Write-Debug "Dokument schließen"
		$document.Close($true)

		#Write-Debug "Inventor schließen"
		if ($QuitOnEnd.IsPresent) {
			$inventor.Quit()
		}

		# DLL will close the application and/or the IDW-file as configured in option file
		# if ($errorcode -ne 0) {
		# 	throw "iLogic Error $errorcode"
		# }

		# checkin
		$newFile = $CIDEON_VAULT_DOCUMENT_TOOLS.CDN_CheckInFileFromPath($File.MasterId, $SourceFileFullName)
		Write-Debug "Dokument eingecheckt"
		# return
		$newFile
	}
	catch {
		# checkout undo
		Write-Debug "Auschecken Rückgängig"
		$vaultConnection.FileManager.UndoCheckoutFile($CheckoutResult.FileResults[0].NewFileIteration, $SourceFileFullName)

		# Protokollieren des aufgetauchten Fehler in der *.log Datei
		[array] $log = "[$($MyInvocation.MyCommand.Name)]" + $_.Exception.Message
		Write-Error $log

	}
	finally {

		# delete local files
		Write-Debug "Lösche lokale Dateien"
		Remove-Item $fileDepencies.DownloadedFiles -Recurse -Force
	}

}

function Invoke-VLTSearch {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$Class,
		[Parameter(Mandatory)]
		$Arguments,
		[Parameter()]
		$Path
	)
	# Liste der gefundenen Dateien initalisieren
	[System.Collections.Generic.List[Object]] $FoundEntities = New-Object 'System.Collections.Generic.List[Object]'
	# Den Suchfolder Definieren

	$SearchFolder = $serviceManager.DocumentService.FindFoldersByPaths($Path)

	# Variablen für das Loppen durch die SuchPages definieren
	$bookmark = ""
	$status = $null
	#Die Variable für die Anzahl der gefundenen Elemente initialisieren
	$TotalResultCount = 0

	# Suche starten und solange durch die Pages loopen wie notwendig
	while ($null -eq $status -or $TotalResultCount -lt $status.TotalHits) {
		# Jetzt die suche ausführen
		switch ($Class) {
			"FLDR" { $result = $serviceManager.DocumentService.FindFoldersBySearchConditions($Arguments, $null, @($SearchFolder.Id), $true, [ref]$bookmark, [ref]$status) }
			"FILE" { $result = $serviceManager.DocumentService.FindFilesBySearchConditions($Arguments, $null, @($SearchFolder.Id), $true, $true, [ref]$bookmark, [ref]$status) }
			"FILEFLDR" { $result = $serviceManager.DocumentService.FindFileFoldersBySearchConditions($Arguments, $null, @($SearchFolder.Id), $true, $true, [ref]$bookmark, [ref]$status) }
			"ITEM" { $result = $serviceManager.ItemService.FindItemRevisionsBySearchConditions($Arguments, $null, $true, [ref]$bookmark, [ref]$status) }
			"CO" { $result = $serviceManager.ItemService.FindChangeOrdersBySearchConditions($Arguments, $null, $true, [ref]$bookmark, [ref]$status) }
			"CUSTENT" { $result = $serviceManager.ItemService.FindCustomEntitiesBySearchConditions($Arguments, $null, $true, [ref]$bookmark, [ref]$status) }
			Default {}
		}

		# die anzahl der aktuellen Page der gesammtzahl hinzufügen
		$TotalResultCount += $result.Count
		# Jetzt die gefundenen Dateien in die Rückgabeliste aufnehmen
		foreach ($Entity in $result) {
			$FoundEntities.Add($Entity)
		}
	}

	# rückgabe der liste mit allen gefundenen Dateien
	return $FoundEntities

}

function Get-VLTSearchConditions {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		$Arguments,
		[Parameter(Mandatory)]
		$Class
	)

	$srchconds = @()
	#Searchcondition zusammenbauen
	foreach ($SingleCond in $Arguments) {
		#Den Schlüssel Merken
		$PropertyDispName = $SingleCond.Key
		$SearchText = $SingleCond.Value
		$SrchOper = $SingleCond.SrchOper

		# if a search goes for file and folders, we have to change the Class for the PropertyDefenition
		if ($Class -eq "FILEFLDR") {
			$Class = "FILE"
		}

		#Jetzt wird die Suchbedingung zusammengebaut
		$PropDefs = $serviceManager.PropertyService.GetPropertyDefinitionsByEntityClassId($Class);
		$PropDefId = $PropDefs | Where-Object { $_.DispName.trim() -eq $PropertyDispName.trim() } | Select-Object -ExpandProperty "Id"
		$searchCond = New-Object -type Autodesk.Connectivity.WebServices.SrchCond
		$searchCond.PropDefId = $PropDefId
		$searchCond.PropTyp = [Autodesk.Connectivity.WebServices.PropertySearchType]::SingleProperty
		$searchCond.SrchTxt = $SearchText
		$searchCond.SrchOper = $SrchOper
		$searchCond.SrchRule = [Autodesk.Connectivity.WebServices.SearchRuleType]::Must

		#und zurückgegeben
		$srchconds += $searchCond

		#Den Suchoperator auf enthält Übereinstimmung setzen
		# 1 = contains
		# 2 = Does not contain
		# 3 = is exactly  or equals
		# 4 = is empty
		# 5 = is not empty
		# 6 = greater than
		# 7 = greater than or equal to
		# 8 = less then
		# 9 = less then or equal to
		# 10 = not equal to


		# Liste der Suchoperatoren
		# Contains 1 string yes
		# Does not contain 2 string yes
		# Is exactly (or equals) 3 numeric, bool, datetime, string yes
		# Is empty 4 image, string no
		# Is not empty 5 image, string no
		# Greater than 6 numeric, datetime, string yes
		# Greater than or equal to 7 numeric, datetime, string yes
		# Less than 8 numeric, datetime, string yes
		# Less than or equal to 9 numeric, datetime, string yes
		# Not equal to 10 numeric, bool, string


	}

	return $srchconds

}
function GetAllModelZnr($Artikelnummer) {

	$SearchStartFolder = "$"
	#SuchDictionary instanzieren
	$SearchDic = New-Object 'System.Collections.Generic.Dictionary[String,String]'
	#search parameters
	$SearchDic["Provider"] = "Inventor"
	$SearchDic["Zeichnungsnummer"] = $Artikelnummer
	#get files
	$FoundFiles = SearchFilesInPathByPropertyDic $SearchStartFolder $SearchDic
	#only 3d documents
	$FoundFiles = $FoundFiles | Where-Object { $_.Name -match ".ipt|.iam" }
	return $FoundFiles

}
function LoadERPInterface() {
	$AllErpInterfaceDLLs = @("CIDEON.VAULT.ERP.INTERFACE.CORE.dll", "CIDEON.VAULT.ECO_TOOLS.dll")

	$Path = "C:\ProgramData\Autodesk\Vault 2023\Extensions\Cideon.Shared\"

	foreach ($CIDEONDLL in  $AllErpInterfaceDLLs ) {
		$FileFullName = $Path + $CIDEONDLL
		if (![IO.File]::Exists($FileFullName)) { $FileFullName = $CDN_SharedFldr + $CIDEONDLL }
		if ([IO.File]::Exists($FileFullName)) {
			try {
				[System.reflection.Assembly]::LoadFrom($FileFullName)
			}
			catch {
				[array] $log = $CIDEONDLL + "[CDN_LoadERPInterface]" + $_.Exception.Message
				CDN_ErrorLog "" $log
			}
		}
		else {
			[array] $log = $CIDEONDLL + "[CDN_LoadERPInterface] File not Exist"
			CDN_ErrorLog "" $log
		}
	}

	try {
		#Instanzieren des ERP Interfaces
		$global:CIDEON_VAULT_ERP_INTERFACE = New-Object -TypeName CIDEON.VAULT.ERP.INTERFACE.CORE.CIDEON_VAULT_ERP_INTERFACE_CORE($serviceManager)


	}
	catch {
		#Protokollieren des aufgetauchten Fehler in der *.log Datei
		[array] $log = "[CDN_LoadERPInterface]" + $_.Exception.Message
	}
	try {
		#Instanzieren des ERP Interfaces
		$global:CIDEON_VAULT_ECO_TOOLS = New-Object -TypeName CIDEON.VAULT.ECO_TOOLS.CIDEON_VAULT_ECO_TOOLS($serviceManager)
	}
	catch {
		#Protokollieren des aufgetauchten Fehler in der *.log Datei
		[array] $log = "[CDN_LoadERPInterface]" + $_.Exception.Message
	}
}
function ExportItemBOM ($vault, $fileID) {
	# get the latest version of the file in case a sync prop has been executed bevore the job
	$itemMasterId = $CIDEON_VAULT_DOCUMENT_TOOLS.CDN_GetAttachedItem($fileID)
	$item = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemObjectByMasterID($itemMasterId)

	# #Laden des ERP Interfaces
	# CDN_LoadERPInterface
	#Einlesen der Konfiguration. Kann auch aus einer Datei kommen. Dann $CIDEON_VAULT_ERP_INTERFACE.ReadInterfaceConfigFromFile(Pfad zur Datei)
	#$CIDEON_VAULT_ERP_INTERFACE.ReadInterfaceConfigFromOptions()

	#Jetzt das Item Exportieren
	$CIDEON_VAULT_ERP_INTERFACE.ItemExport($item)

	#Jetzt das Item Exportieren
	$CIDEON_VAULT_ERP_INTERFACE.BomOfItemExport($item)

}
function ExportItem ($vault, $fileID) {
	# get the latest version of the file in case a sync prop has been executed bevore the job
	$itemMasterId = $CIDEON_VAULT_DOCUMENT_TOOLS.CDN_GetAttachedItem($fileID)
	$item = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemObjectByMasterID($itemMasterId)

	# #Laden des ERP Interfaces
	# CDN_LoadERPInterface
	#Einlesen der Konfiguration. Kann auch aus einer Datei kommen. Dann $CIDEON_VAULT_ERP_INTERFACE.ReadInterfaceConfigFromFile(Pfad zur Datei)
	#$CIDEON_VAULT_ERP_INTERFACE.ReadInterfaceConfigFromOptions()

	#Jetzt das Item Exportieren
	$CIDEON_VAULT_ERP_INTERFACE.ItemExport($item)

	#Jetzt das Item Exportieren
	#$CIDEON_VAULT_ERP_INTERFACE.BomOfItemExport($item)

}

#Suchfunktion zum Ermitteln der Dateien
function SearchFilesInPathByPropertyDic($FolderPath, $SearchPropVals) {
	#Liste der gefundenen Dateien initalisieren
	[System.Collections.Generic.List[Object]] $FoundFiles = New-Object 'System.Collections.Generic.List[Object]'

	#Array für die SearchCondition festlegen
	$srchconds = @()
	#Searchcondition zusammenbauen
	foreach ($SingleCond in $SearchPropVals.GetEnumerator()) {
		#Den Schlüssel Merken
		$KeyString = $SingleCond.Key
		$ValueString = $SingleCond.Value

		$LogString = "Search  Key=" + $KeyString + " Value=" + $ValueString
		#Write-Debug LogString

		#if ($ValueString.Trim() -ne "") {
		#Die einzelnen Searchcondition zusammenbauen
		$srchconds += CreateSarchCond $KeyString $ValueString "FILE"
		#}

	}

	#Den Suchfolder Definieren
	$SearchFolder = $serviceManager.DocumentService.FindFoldersByPaths( @($FolderPath))[0]
	#Variablen für das Loppen durch die SuchPages definieren
	$bookmark = ""
	$status = $null

	$LogString = "===Start Search==="
	#CDN_DebugLog ""  $LogString

	#Die Variable für die Anzahl der gefundenen Elemente initialisieren
	$TotalResultCount = 0

	#Suche starten und solange durch die Pages loopen wie notwendig
	while ($null -eq $status -or $TotalResultCount -lt $status.TotalHits) {
		#Jetzt die siche ausführen
		$result = $serviceManager.DocumentService.FindFilesBySearchConditions($srchconds, $null, @($SearchFolder.Id), $true, $true, [ref]$bookmark, [ref]$status)
		#die anzahl der aktuellen Page der gesammtzahl hinzufügen
		$TotalResultCount += $result.Count
		#Jetzt die gefundenen Dateien in die Rückgabeliste aufnehmen
		foreach ($SingleFile in $result) {
			$FoundFiles.Add($SingleFile)
		}
	}

	$LogString = "===End Search==="
	#CDN_DebugLog ""  $LogString

	#rückgabe der liste mit allen gefundenen Dateien
	return , $FoundFiles

}
function SearchItemsByPropertyDic($SearchPropVals) {
	#Liste der gefundenen Dateien initalisieren
	[System.Collections.Generic.List[Object]] $FoundItems = New-Object 'System.Collections.Generic.List[Object]'

	#Array für die SearchCondition festlegen
	$srchconds = @()
	#Searchcondition zusammenbauen
	foreach ($SingleCond in $SearchPropVals.GetEnumerator()) {
		#Den Schlüssel Merken
		$KeyString = $SingleCond.Key
		$ValueString = $SingleCond.Value

		$LogString = "Search  Key=" + $KeyString + " Value=" + $ValueString
		#Write-Debug LogString

		#if ($ValueString.Trim() -ne "") {
		#Die einzelnen Searchcondition zusammenbauen
		$srchconds += CreateSarchCond $KeyString $ValueString "ITEM"
		#}

	}


	#Variablen für das Loppen durch die SuchPages definieren
	$bookmark = ""
	$status = $null

	$LogString = "===Start Search==="
	#CDN_DebugLog ""  $LogString

	#Die Variable für die Anzahl der gefundenen Elemente initialisieren
	$TotalResultCount = 0

	#Suche starten und solange durch die Pages loopen wie notwendig
	while ($null -eq $status -or $TotalResultCount -lt $status.TotalHits) {
		#Jetzt die siche ausführen
		$result = $serviceManager.ItemService.FindItemRevisionsBySearchConditions($srchconds, $null, $true, [ref]$bookmark, [ref]$status)
		#die anzahl der aktuellen Page der gesammtzahl hinzufügen
		$TotalResultCount += $result.Count
		#Jetzt die gefundenen Dateien in die Rückgabeliste aufnehmen
		foreach ($SingleItem in $result) {
			$FoundItems.Add($SingleItem)
		}
	}

	$LogString = "===End Search==="
	#CDN_DebugLog ""  $LogString

	#rückgabe der liste mit allen gefundenen Dateien
	return , $FoundItems

}

#Funktion zum Erzeugen der Suchkondition
function CreateSarchCond($PropertyDispName , $SearchText, $ClassId) {
	$LogString = "CreateItemSearchCond  PropertyDisplayName=" + $PropertyDispName + " SearchText=" + $SearchText
	#CDN_DebugLog ""  $LogString

	#Den Suchoperator auf enthält Übereinstimmung setzen
	# 1 = contains
	# 2 = Does not contain
	# 3 = is exactly  or equals
	# 4 = is empty
	# 5 = is not empty
	# 6 = greater than
	# 7 = greater than or equal to
	# 8 = less then
	# 9 = less then or equal to
	# 10 = not equal to
	$Soper = 1

	#Prüfen ob der Suchtext eine Datum ist
	# [DateTime] $SearchDate = New-Object DateTime
	# if ([DateTime]::TryParse($SearchText, [ref] $SearchDate )) {
	# 	#Ja ist es , dann müssen wir den Suchoperator auf neuer oder gleich anpassen
	# 	$Soper = 7
	# 	#und das Datum in das Amerikanische Format umwandeln
	# 	[string]$SearchText = $SearchDate.ToString("MM.dd.yyyy").Replace(".", "/")
	# }
	Elseif ($SearchText.Trim() -eq "") {
		#Der Suchtext sein leer zu sein, also setzen wir den Suchoperator auf 4
		$Soper = 4
	}
	# boolean values are always 3
	if ($SearchText -eq "True" -or $SearchText -eq "False" ) { $Soper = 3 }

	#Jetzt wird die Suchbedingung zusammengebaut
	$filePropDefs = $serviceManager.PropertyService.GetPropertyDefinitionsByEntityClassId($ClassId);
	#$fileNamePropDef = New-Object -type Autodesk.Connectivity.WebServices.PropDef
	$fileNamePropDef = $filePropDefs | Where-Object { $_.DispName.trim() -eq $PropertyDispName.trim() } | Select-Object -ExpandProperty "Id"
	$searchCond = New-Object -type Autodesk.Connectivity.WebServices.SrchCond
	$searchCond.PropDefId = $fileNamePropDef
	$searchCond.PropTyp = [Autodesk.Connectivity.WebServices.PropertySearchType]::SingleProperty
	$searchCond.SrchTxt = $SearchText
	$searchCond.SrchOper = $Soper
	$searchCond.SrchRule = [Autodesk.Connectivity.WebServices.SearchRuleType]::Must

	#und zurückgegeben
	return $searchCond


	# Liste der Suchoperatoren
	# Contains 1 string yes
	# Does not contain 2 string yes
	# Is exactly (or equals) 3 numeric, bool, datetime, string yes
	# Is empty 4 image, string no
	# Is not empty 5 image, string no
	# Greater than 6 numeric, datetime, string yes
	# Greater than or equal to 7 numeric, datetime, string yes
	# Less than 8 numeric, datetime, string yes
	# Less than or equal to 9 numeric, datetime, string yes
	# Not equal to 10 numeric, bool, string

}


function AssignFilesToItem ($item, $file) {
	#Update Item links with set new file associations
	$editItem = $serviceManager.ItemService.EditItems(@($item.RevId)) | Select-Object -first 1
	$serviceManager.ItemService.AssignFileToItem($editItem.revID, $file.Id)
	$serviceManager.ItemService.UpdateAndCommitItems(@($editItem))
}


#Artikel aktualisieren (letzte Version der verknüpften Dokumente holen)
function CS_UpdateItem($Item) {
	$ItemNum = $item.ItemNum
	$files = @();

	$Item = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemObjectByMasterID($Item.MasterId)

	Write-Debug "[CS_UpdateItem]Aktualisieren des Artikels: $ItemNum"

	$ItemHistotic = $serviceManager.ItemService.GetItemHistoryByItemMasterId($Item.MasterId, [Autodesk.Connectivity.WebServices.ItemHistoryTyp]::All)
	$EditItem = $serviceManager.ItemService.GetLatestItemByItemMasterId($Item.MasterId)
	$EditItems = New-Object "System.Collections.Generic.List[Long]"
	try {
		$serviceManager.ItemService.UpdatePromoteComponents(@($EditItem.RevId), [Autodesk.Connectivity.WebServices.ItemAssignAll]::Default, $false)
		$TStamp = New-Object "System.DateTime"
		$PropOrder = $serviceManager.ItemService.GetPromoteComponentOrder([ref]$TStamp)
		if ($PropOrder.PrimaryArray -ne $null) {
			$serviceManager.ItemService.PromoteComponents($TStamp, $PropOrder.PrimaryArray)
			$serviceManager.ItemService.PromoteComponentLinks($PropOrder.PrimaryArray)
		}


		if ($PropOrder.NonPrimaryArray -ne $null) {
			$serviceManager.ItemService.PromoteComponents($TStamp, $PropOrder.NonPrimaryArray)
			$serviceManager.ItemService.PromoteComponentLinks($PropOrder.NonPrimaryArray)
		}

		$ItemAndFiles = $serviceManager.ItemService.GetPromoteComponentsResults($TStamp)

		foreach ($element in $ItemAndFiles.ItemRevArray) {
			$EditItems.Add($element.Id)
			try {
				$serviceManager.ItemService.UpdateAndCommitItems(@($element))
			}
			catch {
				try {
					$serviceManager.ItemService.UndoEditItems(@($element.Id))
				}
				catch {
					Write-Error "Error Update Item: $($item.ItemNum)"
				}
			}
		}
	}
	catch {
		$serviceManager.ItemService.UndoEditItems($EditItems.ToArray())
		Write-Error "Error Update Item: $($item.ItemNum)"
	}
}

function CS_UpdateItemTest($Item) {
	$ItemNum = $item.ItemNum
	$files = @();

	$Item = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemObjectByMasterID($Item.MasterId)

	Write-Debug "[CS_UpdateItem]Aktualisieren des Artikels: $ItemNum"

	$ItemHistotic = $serviceManager.ItemService.GetItemHistoryByItemMasterId($Item.MasterId, [Autodesk.Connectivity.WebServices.ItemHistoryTyp]::All)
	$EditItem = $serviceManager.ItemService.GetLatestItemByItemMasterId($Item.MasterId)
	$EditItems = New-Object "System.Collections.Generic.List[Long]"
	try {
		$serviceManager.ItemService.UpdatePromoteComponents(@($EditItem.RevId), [Autodesk.Connectivity.WebServices.ItemAssignAll]::Yes, $false)
		$TStamp = New-Object "System.DateTime"
		$PropOrder = $serviceManager.ItemService.GetPromoteComponentOrder([ref]$TStamp)
		if ($PropOrder.PrimaryArray -ne $null) {
			$serviceManager.ItemService.PromoteComponents($TStamp, $PropOrder.PrimaryArray)
			$serviceManager.ItemService.PromoteComponentLinks($PropOrder.PrimaryArray)
		}


		if ($PropOrder.NonPrimaryArray -ne $null) {
			$serviceManager.ItemService.PromoteComponents($TStamp, $PropOrder.NonPrimaryArray)
			$serviceManager.ItemService.PromoteComponentLinks($PropOrder.NonPrimaryArray)
		}

		$ItemAndFiles = $serviceManager.ItemService.GetPromoteComponentsResults($TStamp)

		foreach ($element in $ItemAndFiles.ItemRevArray) {
			$EditItems.Add($element.Id)
			try {
				$serviceManager.ItemService.UpdateAndCommitItems(@($element))
			}
			catch {
				try {
					$serviceManager.ItemService.UndoEditItems(@($element.Id))
				}
				catch {
					Write-Error "Error Update Item: $($item.ItemNum)"
				}
			}
		}
	}
	catch {
		$serviceManager.ItemService.UndoEditItems($EditItems.ToArray())
		Write-Error "Error Update Item: $($item.ItemNum)"
	}
}

function CS_UpdateBOM($Item) {
	$ItemNum = $item.ItemNum
	$files = @();

	$Item = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemObjectByMasterID($Item.MasterId)

	# Write-Debug "[CS_UpdateItem]Aktualisieren des Artikels: $ItemNum"

	$ItemHistotic = $serviceManager.ItemService.GetItemHistoryByItemMasterId($Item.MasterId, [Autodesk.Connectivity.WebServices.ItemHistoryTyp]::All)
	$EditItem = $serviceManager.ItemService.GetLatestItemByItemMasterId($Item.MasterId)
	$EditItems = New-Object "System.Collections.Generic.List[Long]"
	try {
		$EditItems = $serviceManager.ItemService.EditItems(@($EditItem.RevId))
		$ItemBOM = $serviceManager.ItemService.GetItemBOMByItemIdAndDate($EditItems[0].Id, [DateTime]::Now, [Autodesk.Connectivity.WebServices.BOMTyp]::Tip, [Autodesk.Connectivity.WebServices.BOMViewEditOptions]::ReturnExcluded)

		$ItemAssocParams = New-Object System.Collections.Generic.List[Autodesk.Connectivity.WebServices.ItemAssocParam]
		foreach ($ItemAssoc in $ItemBOM.ItemAssocArray) {
			$ItemAssocParam = New-Object Autodesk.Connectivity.WebServices.ItemAssocParam
			$ItemAssocParam.EditAct = [Autodesk.Connectivity.WebServices.BOMEditAction]::Delete
			$ItemAssocParam.Id = $ItemAssoc.Id
			$ItemAssocParams += $ItemAssocParam


		}
		try {
			$itmBOM = $serviceManager.ItemService.UpdateItemBOMAssociations($EditItems[0].Id, $ItemAssocParams, [Autodesk.Connectivity.WebServices.BOMViewEditOptions]::ReturnBOMFragmentsOnEdits)
			$serviceManager.ItemService.UpdateAndCommitItems(@($EditItems))
		}
		catch {
			$serviceManager.ItemService.UndoEditItems(@($EditItem.Id))
		}


	}
	catch {
		$serviceManager.ItemService.UndoEditItems($EditItems.ToArray())
		Write-Error "Error Update Item: $($item.ItemNum)"
	}
}
#Anlegen eines Syncronisierungsjobs

function AddSyncJob($serviceManager, $file , $Prio = 100 ) {
	try {
		#Abholen der aktuellsten Datei
		$file = $CIDEON_VAULT_DOCUMENT_TOOLS.CDN_GetLatestFileObjectByMasterFileID($file.MasterId);
		#Notwendige Parameter zusammenstellen
		$param1 = New-Object Autodesk.Connectivity.Webservices.JobParam -Property @{Name = "FileVersionId" ; Val = $file.Id }
		$param2 = New-Object Autodesk.Connectivity.Webservices.JobParam -Property @{Name = "QueueCreateDwfJobsOnCompletion" ; Val = "False" }
		$param3 = New-Object Autodesk.Connectivity.Webservices.JobParam -Property @{Name = "QueueCreatePdfJobsOnCompletion" ; Val = "False" }
		#Parameterarray bilden
		$jobParams = @($param1, $param2, $param3)
		#Beschreibung bilden
		$Description = [string]::Format("{0} : SyncProperties", $file.Name)
		#Job anlegen
		$message = [string]::Format("AddSyncJob : Lege job {0} für {1} an ", "Autodesk.Vault.SyncProperties an", $file.Name);
		#CDN_InfoLog $file $message
		$erg = $serviceManager.JobService.AddJob("Autodesk.Vault.SyncProperties", $Description, $jobParams , $Prio)
	}
	catch {

		#Protokollieren des aufgetauchten Fehler in der *.log Datei
		[array] $log = "[AddSyncJob]" + $_.Exception.Message
		Write-Error $file $log

	}
}
function LogInVault () {
	#for login are Filestore and Database server mandatory, even if the same
	$VaultDB = "angsrv0005"
	$VaultFS = $VaultDB
	$VaultName = "Vault"
	$VaultUser = "cideon-jobserver"
	$VaultPWD = "#Service123!!!"
	#$ReadOnly = $false

	try {
		$ServerIdenties = New-Object Autodesk.Connectivity.WebServices.ServerIdentities -Property @{ DataServer = $VaultDB; FileServer = $VaultFS }
		$licenseAgent = [Autodesk.Connectivity.WebServices.LicensingAgent]::Client

		$login = New-Object  Autodesk.Connectivity.WebServicesTools.UserPasswordCredentials($ServerIdenties, $VaultName, $VaultUser, $VaultPWD, $licenseAgent)

		$global:serviceManager = New-Object Autodesk.Connectivity.WebServicesTools.WebServiceManager($login)

	}
	catch {
		Write-Host "Logon in vault failed - please check the log on data by the function 'LogInVault' "
		exit
	}


}

function CreateUpdateItem ($ItemNumber, $VltSAPCat, $Arguments) {
	#create object for the UDP properties
	$ItemProperties = New-Object Autodesk.Connectivity.WebServices.PropInstParamArray

	#read the property definition for entity class ITEM
	$allPropDefs = $serviceManager.PropertyService.GetPropertyDefinitionsByEntityClassId("ITEM")

	#read the paramter from sync server message (for DEBUG in PS comment $Argument = $sapProps.Arguments)

	foreach ($Argument in $Arguments.Keys) {

		$UDPValue = $Argument
		$ItemUDP = ($allPropDefs | Where-Object { $_.DispName -eq $UDPValue })
		$ItemUDPId = $ItemUDP.Id

		if ($null -ne $ItemUDPId) {
			# Datentyp beachten und konvertieren
			switch ($ItemUDP.Typ) {
		  Bool { $ItemProperties.Items += New-Object Autodesk.Connectivity.WebServices.PropInstParam -Property @{ PropDefId = $ItemUDPId; Val = [System.Convert]::toBoolean($Arguments.$Argument) } }
		  String { $ItemProperties.Items += New-Object Autodesk.Connectivity.WebServices.PropInstParam -Property @{ PropDefId = $ItemUDPId; Val = [System.Convert]::toString($Arguments.$Argument) } }
		  Numeric { $ItemProperties.Items += New-Object Autodesk.Connectivity.WebServices.PropInstParam -Property @{ PropDefId = $ItemUDPId; Val = [System.Convert]::toDecimal($Arguments.$Argument) } }
		  DateTime { $ItemProperties.Items += New-Object Autodesk.Connectivity.WebServices.PropInstParam -Property @{ PropDefId = $ItemUDPId; Val = [System.Convert]::toDateTime($Arguments.$Argument) } }
		  Default { $ItemProperties.Items += New-Object Autodesk.Connectivity.WebServices.PropInstParam -Property @{ PropDefId = $ItemUDPId; Val = $Arguments.$Argument } }
			}
		}
	}

	#EVOQUA do not use the SAP categories, only a fix item category
	#$VltSAPCat = $Kategorie
	<# #define category by MATART
	  switch ($SAPCat)
	  {
		"ZSEM" {$VltSAPCat="General"; Break }
		Default {$VltSAPCat="General"}
	  } #>

	#EVOQUA do not use the SAP state, only the Delete Flag for the vault state Obsolete
	#default is "Work in Progress"
	switch ($VltSAPCat) {
		"Artikel" { $VltSAPState = "Import" }
	}
	# $VltSAPState="In Bearbeitung"
	#check delete flag if the state have to be changed
	# $SAP_Delete_Flag = $SAP_Delete_Flag.ToUpper()
	# $debug = "Delete Flag: $SAP_Delete_Flag "
	# Write-Debug $debug -debug:$DebPrefValue
	# if ($SAP_Delete_Flag -eq "X")
	# {
	#   $VltSAPState = "Obsolete"
	# }


	<# #define state by SAP STATE
	  switch ($SAPState)
	  {
		"10" {$VltSAPState="Work in Progress"; Break }
		"50" {$VltSAPState="Released"; Break }
		"90" {$VltSAPState="Obsolete"; Break }
		Default {$VltSAPState="Work in Progress"}
	  } #>



	#Write log
	Write-Debug "-------------"
	$debug = "Start to create or update item number: $ItemNumber"
	Write-Debug $debug #-debug:$DebPrefValue

	try {

		#get category ID
		$ItemCats = $serviceManager.CategoryService.GetCategoriesByEntityClassId("ITEM", $true)
		$ItemCatID = ($ItemCats | Where-Object { $_.Name -eq $VltSAPCat }).Id
		#$ItemCatID = $ItemCat.Id

		#get DEFAULT Lifecycle ID by item category
		#define the name of behaviors to return.Currently there are only 4 allowed names: "Category", "UserDefinedProperty", "RevisionScheme", or "LifeCycle".
		$Behav2Srch = "LifeCycle"
		$CatBehavsObj = $serviceManager.CategoryService.GetCategoryConfigurationById($ItemCatID, $Behav2Srch)
		$ItemDefaultLCId = (($CatBehavsObj.BhvCfgArray | Where-Object { $_.Name -eq $Behav2Srch }).BhvArray | Where-Object { $_.AssignTyp -eq "Default" }).Id

		#$test = $serviceManager.LifeCycleService.GetLifeCycleDefinitionsByIds($ItemDefaultLCId).StateArray
		#get Lifecycle state ID by Name
		$VltSAPStateID = ($serviceManager.LifeCycleService.GetLifeCycleDefinitionsByIds($ItemDefaultLCId).StateArray | Where-Object { $_.DispName -eq $VltSAPState }).Id

		#get numberschema ID
		$ItemNumberSchemes = $serviceManager.NumberingService.GetNumberingSchemes("ITEM", "Activated")
		foreach ($Scheme in $ItemNumberSchemes) {
			#check item number scheme to get the id
			if ($Scheme.Name -eq $ItemNumScheme) {
		  $ItemNumSchemeID = $Scheme.SchmID
			}

		}

		#try to create a new item, if not, update existing one


		#Search items in vault
		#create search criteria, this are searched by a fall system: from top to bottom.
		#value with | (list) are searched as "may"
		#xingle value as "must"
		#date value are searched with "less than this Date"

		#create dictionary an set the search value(s)
		$SearchPropVals = New-Object 'System.Collections.Generic.Dictionary[String,String]'
		$SearchPropVals["Number"] = $ItemNumber

		#call the search function
		#$Itemresults = SearchItems $SearchPropVals
		try {
			$Itemresults = $CIDEON_VAULT_ITEM_TOOLS.CDN_GetLatestItemByItemNumber($ItemNumber)
		}
		catch {
			Write-Debug "Artikel $($sapProps["itemNumber"]) existiert noch nicht"
		}
		#check if the search find an item, if not, create the item
		if (!$Itemresults) {

			#Write log
			$debug = "Start to create item number: $ItemNumber"
			Write-Debug $debug #-debug:$DebPrefValue

			#try create a new item object
			$Item = $serviceManager.ItemService.AddItemRevision($ItemCatID)
			$ItemRevIDs = @($Item.RevId)

			#create a new custom number to assign it later with edit number
			$ItemMID = $Item.MasterId
			$ItemNumbers = New-Object Autodesk.Connectivity.WebServices.StringArray
			$ItemNumbers.Items = $ItemNumber
			$Restric = New-Object Autodesk.Connectivity.WebServices.ProductRestric
			$ItemNumDef = $serviceManager.ItemService.AddItemNumbers(@($ItemMID), @($ItemNumSchemeID), $ItemNumbers, [ref]$Restric)
			if ($Restric.length -eq 1) {
		  #DeleteUncommittedItems
		  #$AllMyLogins (true/false) Whether to clear out locks and uncommitted item iterations for all logins for this userID or just the current login.
		  $AllMyLogins = $true
		  $serviceManager.ItemService.DeleteUncommittedItems($AllMyLogins)

		  #try again to create a new item
		  $Item = $serviceManager.ItemService.AddItemRevision($ItemCatID)
		  $ItemRevIDs = @($Item.RevId)

		  #create again a new custom number to assign it later with edit number
		  $ItemMID = $Item.MasterId
		  $ItemNumbers = New-Object Autodesk.Connectivity.WebServices.StringArray
		  $ItemNumbers.Items = $ItemNumber
		  $Restric = New-Object Autodesk.Connectivity.WebServices.ProductRestric
		  $ItemNumDef = $serviceManager.ItemService.AddItemNumbers(@($ItemMID), @($ItemNumSchemeID), $ItemNumbers, [ref]$Restric)
			}
			$ItemNumGen = $ItemNumDef[0].ItemNum1
			#edit item object and set the new number
			$EditItems = $serviceManager.ItemService.EditItems($ItemRevIDs)
			$EditItem = $EditItems[0]
			$EditItem.ItemNum = $ItemNumGen
			switch ($sapProps["Kategorie"]) {
		  "Artikel" {
					$EditItem.Title = $sapProps["Benennung_DE"]
					$EditItem.Detail = $sapProps["Benennung_DEzusatz"]
					$UnitsofMeasure = $serviceManager.ItemService.GetAllUnitsOfMeasure()
					$EditItem.UnitId = $UnitsofMeasure | Where-Object { $_.UnitName -eq $sapProps["Units"] } | Select-Object -ExpandProperty "Id"

					#$EditItem.Detail = $sapProps["Beschreibung"]
		  }
		  #"Untermaschinenartikel" { #$EditItem.Title = $sapProps["Titel"]
		  #   $EditItem.Detail = $sapProps["Beschreibung"]
		  # }
		  #"Zubehör" { #$EditItem.Title = $sapProps["Titel"]
		  #   $EditItem.Detail = $sapProps["Beschreibung"]
		  # }
		  #"Halbzeug" {#$EditItem.Title = $sapProps["Titel"]
		  #   $EditItem.Detail = $sapProps["Beschreibung"]
		  # }
		  #   "Halbzeug" {
		  #     #$EditItem.Title = $sapProps["Titel"]
		  #     $EditItem.Detail = $sapProps["Beschreibung"]
		  #   }
			}

			# $EditItem.Title = $SAPTitle
			# $EditItem.Units = $VltSAPUnit
			# $EditItem.UnitId = $VltSAPUnitId


			#comit the change to create the item
			#IMPORTANT: as long the UpdateAndCommitItems is not committed, the generate number stay reserved but is not visible in Vault.
			$serviceManager.ItemService.UpdateAndCommitItems(@($EditItems))

		}
		#Write log
		$debug = "Start update item number: $ItemNumber"
		Write-Debug $debug #-debug:$DebPrefValue

		#item exist, check the category, update the properties and change the state

		#get the last version
		$Item = $serviceManager.ItemService.GetLatestItemByItemNumber($ItemNumber)

		#if item exist update it

		$ItemMID = $Item.MasterID

		#check the category (only by update)
		if ($Item.Cat.CatID -eq $ItemCatID) {
			#Write log
			$debug = "Item number $ItemNumber update - category is correct"
			Write-Debug $debug #-debug:$DebPrefValue
		}
		#category is not correct, change category
		else {
			$serviceManager.ItemService.UpdateItemCategories(@($ItemMID), @($ItemCatID), "Category change by Vault SAP Interface")

			#Write log
			$debug = "Item number $ItemNumber update - category was not correct - category changed"
			Write-Debug $debug #-debug:$DebPrefValue

		}
		#get the last version, in the case the category was change
		$Item = $serviceManager.ItemService.GetLatestItemByItemMasterId($ItemMID)
		$ItemRevIDs = @($Item.RevId)
		#edit item object and set the properties, if not commited
		try {
			$EditItems = $serviceManager.ItemService.EditItems($ItemRevIDs)
		}
		catch {
			#edit item is not possible, because the item is uncomitted
			#get the last user that edit the item
			$ItemLastUser = $Item.LastModUserName
			#get the logged user

			$VaultLogOnUser = $serviceManager.WebServiceCredentials.UserName
			#check if is locked by the user that run this script, undo locked
			if ($ItemLastUser -eq $VaultLogOnUser) {
		  #$AllMyLogins (true/false) Whether to clear out locks and uncommitted item iterations for all logins for this userID or just the current login.
		  $AllMyLogins = $true
		  $serviceManager.ItemService.DeleteUncommittedItems($AllMyLogins)
			}
			else {

		  "$Itemnumber;$ItemLastUser" | Out-File $LockedItemLog -Append
		  $debug = "Item number $ItemNumber cannot be updated because locked by user $ItemLastUser"
		  Write-Debug $debug #-debug:$DebPrefValue
		  break
			}
			#get the last version, in the case the category was change
			$Item = $serviceManager.ItemService.GetLatestItemByItemMasterId($ItemMID)
			#edit item object
			$EditItems = $serviceManager.ItemService.EditItems($ItemRevIDs)
		}
		$EditItem = $EditItems[0]
		switch ($sapProps["Kategorie"]) {
			"Artikel" {
		  $EditItem.Title = $sapProps["Benennung_DE"]
		  $EditItem.Detail = $sapProps["Benennung_DEzusatz"]
		  $UnitsofMeasure = $serviceManager.ItemService.GetAllUnitsOfMeasure()
		  $EditItem.UnitId = $UnitsofMeasure | Where-Object { $_.UnitName -eq $sapProps["Units"] } | Select-Object -ExpandProperty "Id"

		  #$EditItem.Detail = $sapProps["Beschreibung"]
			}
		}
		# $EditItem.Title = $SAPTitle
		# $EditItem.Detail = $SAPDesc
		# $EditItem.Units = $VltSAPUnit
		# $EditItem.UnitId = $VltSAPUnitId

		#Write log
		$debug = "Start Edit item by item update"
		Write-Debug $debug #-debug:$DebPrefValue

		#set the properties
		if ($Arguments.Count -gt 0) {
			$propVals = $serviceManager.ItemService.UpdateItemProperties(@($EditItem.RevID), $ItemProperties)
		}

		#comit the change update the item
		#IMPORTANT: as long the UpdateAndCommitItems is not committed, the item will stay in edit mode.
		$serviceManager.ItemService.UpdateAndCommitItems(@($EditItems))

		#Write log
		$debug = "Item number $ItemNumber updated"
		Write-Debug $debug #-debug:$DebPrefValue
		Write-Debug "-------------"

		#check the item state and update it, if necessary
		#get the last version
		# $Item = $serviceManager.ItemService.GetLatestItemByItemMasterId($ItemMID)

		# #get the item state values
		# $ItemLCStateDefID = $Item.LfCyc.LfCycDefId
		# $ItemLCStateID = $Item.LfCyc.LfCycStateId

		#check if the lifecycle is the default lifecyle for the category
		# if ($ItemLCStateDefID -eq $ItemDefaultLCId)
		# {
		#   #check the actuall state of the item and change it if not correct
		#   if ($ItemLCStateID -ne $VltSAPStateID)
		#   {
		#     $serviceManager.ItemService.UpdateItemLifeCycleStates(@($ItemMID),@($VltSAPStateID),"Update state by Vault SAP Interface")

		#     #Write log
		#     $debug = "Item number $ItemNumber state changed"
		#     Write-Debug $debug -debug:$DebPrefValue
		#   }

		# }
		# else
		# {
		#   #Update the lifecycle definition to the default definition and change the state if necessary
		#   $serviceManager.ItemService.UpdateItemLifeCycleDefinitions(@($ItemMID),@($ItemDefaultLCId),@($VltSAPStateID),"Update lifecycle definition and state by Vault SAP Interface" )

		#   #Write log
		#   $debug = "Item number $ItemNumber life cycle definition and state changed"
		#   Write-Debug $debug -debug:$DebPrefValue

		# }

	}
	catch {

		#Write log
		$debug = "Item number $($sapProps["itemNumber"]) error by create or update."
		Write-Error $debug #-debug:$DebPrefValue
		$errorstring = "Error" + $err.InnerException.Message + ' in line ' + $_.InvocationInfo.ScriptLineNumber
		Write-Error $errorString
		Write-Debug "-------------"
		if ($DebPrefValue) {
			throw ($ErrorMessage)
		}

	}
}

function GetITEMUPDofCat ($Kategorie) {
	try {
		#$propdef = [System.Collections.Generic.Dictionary[String,[Autodesk.Connectivity.WebServices.PropDef]]]::new()
		$propdef = $CIDEON_VAULT_INFORMATION.GetAllPropsOfCategoryByDisplayName($Kategorie)
	}
	catch {
		# Wenn keine Eigenschaften der Kategorie zugewiesen sind, scheitert das ganze
		$propdef = @{}
	}

	$propAsDict = @{}
	# Kategorieeigenschaftsnamen in neues Hashtable schreiben
	$propdef.Keys | ForEach { $propAsDict[$_] = "" }
	return $propAsDict
}
function MergeCatPropsWithImportValues ($CatProps, $SAPProps) {
	# JSON Attribute, die nicht zu einer Kategorie gehören
	$TakeOut = "itemNumber", "Units", "Title(Item,CO)", "Link Vault", "Kategorie"

	foreach ($SAPProp in $SAPProps.Keys) {
		# Skip bei TakeOut Werten
		if ($SAPProp -in $TakeOut) { Continue }
		# Skip wenn JSON Attribut kein Bestandteil der Kategorieeigenschaften ist
		if (-not $CatProps.ContainsKey($SAPProp)) { Write-Debug "Import Attribut ""$($SAPProp)"" ist keine Kategorieeigenschaft"; Continue }

		# Kategorie Eigenschaft, den Import Value zuweisen
		$CatProps[$SAPProp] = $SAPProps.$SAPProp
		# Write-Debug "Kategorieeigenschaft $($SAPProp): $($SAPProps.$SAPProp)"
	}
	return $CatProps
}
function GetCatPropsFilledWithSAPargs ($SAPProps) {
	$CatProps = GetITEMUPDofCat $SAPProps["Kategorie"]
	$MergedProps = MergeCatPropsWithImportValues $CatProps $SAPProps

	return $MergedProps
}

#endregion
#region Import Data

# $csvfile = "C:\Users\timon.foerst\Desktop\Testimport.csv"
# $importdata = Import-Csv -path $csvfile
LogInVault
#endregion

#Region Input Parameter


###get input parameter
$global:CIDEON_GENERAL_TOOLS = New-Object -TypeName  CIDEON.GENERAL.TOOLS.CIDEON_GENERAL_TOOLS
$global:CIDEON_VAULT_DOCUMENT_TOOLS = New-Object -TypeName CIDEON.VAULT.DOCUMENT.TOOLS.CIDEON_VAULT_DOCUMENT_TOOLS($serviceManager)
$global:CIDEON_VAULT_ITEM_TOOLS = New-Object -TypeName CIDEON.VAULT.ITEM.TOOLS.CIDEON_VAULT_ITEM_TOOLS($serviceManager)
$global:CIDEON_VAULT_TOOLS = New-Object -TypeName CIDEON.VAULT.TOOLS.CIDEON_VAULT_TOOLS($serviceManager)
$global:CIDEON_VAULT_INFORMATION = New-Object -TypeName CIDEON.VAULT.TOOLS.CIDEON_VAULT_INFORMATION($serviceManager)

#Laden des ERP Interfaces
LoadERPInterface

$CIDEON_VAULT_ERP_INTERFACE.ReadInterfaceConfigFromOptions()


Start-Transcript -path $LogFile -append
#Stop-Transcript
$date = Get-Date -format "yyyy-MM-dd HH:mm"
Write-Debug $date

Write-Debug "-------------"
#Endregion

$list = Import-Excel -Path "C:\Users\SRV_ANG_Autodesk\Desktop\prioliste.xlsx"
#$list = $list | Where-Object { $_."neue Benennung DE" -ne $null }

$models = @()
$nodeCounter = 0
foreach ($element in $list) {
	$nodeCounter++

	$percent = [math]::Round(($nodeCounter / $list.Count) * 100, 1)
	Write-Progress -Activity "File search" -Status "$([int]$percent)% processed" -PercentComplete $percent

	# Get File
	# Zeichnungsnummer = adccb22d-a119-499c-bd35-26e97010f51e
	#$models = $CIDEON_VAULT_DOCUMENT_TOOLS.CDN_GetFileObjectByPropertyNameValues("/adccb22d-a119-499c-bd35-26e97010f51e=$($element.Artikelcode)")
	## Search
	# search parameters
	# 1 = contains
	# 2 = Does not contain
	# 3 = is exactly  or equals
	# 4 = is empty
	# 5 = is not empty
	# 6 = greater than
	# 7 = greater than or equal to
	# 8 = less then
	# 9 = less then or equal to
	# 10 = not equal to
	$SearchDic = @(
		[PSCustomObject]@{Key = 'Zeichnungsnummer'; Value = "$($element.Artikelnummer)"; SrchOper = '1' }
		[PSCustomObject]@{Key = 'Dateierweiterung'; Value = 'iam'; SrchOper = '3' }
	)
	$results = Find-VLT -Class "FILE" -Path "$" -Arguments $SearchDic
	#get files
	if ($null -ne $results) {
		$models += $results
		continue
	}
	$SearchDic = @(
		[PSCustomObject]@{Key = 'Zeichen-Nr.'; Value = "$($element.Artikelnummer)"; SrchOper = '1' }
		[PSCustomObject]@{Key = 'Dateierweiterung'; Value = 'iam'; SrchOper = '3' }
	)
	$results = Find-VLT -Class "FILE" -Path "$" -Arguments $SearchDic

	#get files
	if ($null -ne $results) {
		$models += $results
		continue
	}

	$SearchDic = @(
		[PSCustomObject]@{Key = 'Zeichnungsnummer alt'; Value = "$($element.Artikelnummer)"; SrchOper = '1' }
		[PSCustomObject]@{Key = 'Dateierweiterung'; Value = 'iam'; SrchOper = '3' }
	)
	$results = Find-VLT -Class "FILE" -Path "$" -Arguments $SearchDic

	#get files
	if ($null -ne $results) {
		$models += $results
		continue
	}


	$SearchDic = @(
		[PSCustomObject]@{Key = 'Teilenummer'; Value = "$($element.Artikelnummer)"; SrchOper = '1' }
		[PSCustomObject]@{Key = 'Dateierweiterung'; Value = 'iam'; SrchOper = '3' }
	)
	$results = Find-VLT -Class "FILE" -Path "$" -Arguments $SearchDic

	#get files
	if ($null -ne $results) {
		$models += $results
		continue
	}

	Write-Debug "Keine Dateien zu $($element.Artikelcode) gefunden"

}
Write-Progress -Activity "File search" -Status "$([int]$percent)% processed" -Completed
# get every Dependency
# child models

$fileAssociations = $serviceManager.DocumentService.GetLatestFileAssociationsByMasterIds($models.MasterId, [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::None, $false, [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::Dependency, $true, $false, $false, $false)
# drawings
$fileAssociations += $serviceManager.DocumentService.GetLatestFileAssociationsByMasterIds($models.MasterId, [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::Dependency, $false, [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::None, $false, $false, $false, $false)
$fileIds = $fileAssociations | ForEach-Object { $_.FileAssocs.CldFile.Id }
# now get properties of all files
$PropDefintions = $serviceManager.PropertyService.GetPropertyDefinitionsByEntityClassId("FILE")
$PropDefs = @()
$PropDefs += $PropDefintions | Where-Object { $_.DispName.trim() -eq "Ordnerpfad" }
$PropDefs += $PropDefintions | Where-Object { $_.DispName.trim() -eq "Name" }
$PropDefs += $PropDefintions | Where-Object { $_.DispName.trim() -eq "Zeichnungsnummer" }
$PropDefs += $PropDefintions | Where-Object { $_.DispName.trim() -eq "Application Version" }


$file = "C:\temp\PrioList_Props.xlsx"
Remove-Item $file | Out-Null
$nodeCounter = 0
$data = [PSCustomObject]@{}

foreach ($PropDef in $PropDefs) {
	$nodeCounter++
	$percent = [math]::Round(($nodeCounter / $PropDefs.Count) * 100, 1)
	Write-Progress -Activity "File property export" -Status "$([int]$percent)% processed" -PercentComplete $percent
	$fileProps = $serviceManager.PropertyService.GetProperties("FILE", $fileIds, $PropDef.Id)
	$data | Add-Member -Name $PropDef.DispName -Type NoteProperty -Value $fileProps.Val
}


Export-Excel -Path $file -InputObject $data -WorksheetName "Properties"

Write-Progress -Activity "File property export" -Status "$([int]$percent)% processed" -Completed


$date = Get-Date -format "yyyy-MM-dd HH:mm"
Write-Debug $date
Stop-Transcript

#endregion

