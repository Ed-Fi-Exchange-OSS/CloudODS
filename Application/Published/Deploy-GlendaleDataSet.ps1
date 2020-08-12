# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

<#
.SYNOPSIS
	Deploys the Glendale database to an Azure resource group
.DESCRIPTION
	Deploys the Glendale database to an Azure resource group
.PARAMETER InstallFriendlyName
	Install-friendly name or Resource group name of the Ed-Fi ODS instance that will be scaled
.PARAMETER GlendaleDatasetUrl
	URL to Glendale Dataset bacpac file
.EXAMPLE
	.\Deploy-GlendaleDataset -InstallFriendlyName "EdFi ODS" -GlendaleDatasetUrl "https://odsassets.blob.core.windows.net/public/Glendale/EdFi_Glendale_v32-20190610-Azure.bacpac"
#>
Param(
	[ValidatePattern('^[a-zA-z0-9\s-]+$')]
	[ValidateLength(1,64)]
	[string]
	[Parameter(Mandatory=$false)]
	$InstallFriendlyName = 'EdFi ODS',

    [ValidateLength(1,150)]
	[string]
	[Parameter(Mandatory=$true)]
	$GlendaleDatasetUrl
)

Import-Module $PSScriptRoot\Dependencies.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\EdFiOdsDeploy.psm1 -Force -DisableNameChecking
Use-Module "AzureRM" "4.3.1"
Use-Module "AzureRM.Sql" "3.3.1"

Login-AzureAccount
$ResourceGroupName = Get-ResourceGroupName $InstallFriendlyName
$sqlServer = Get-AzureRmSqlServer -ResourceGroupName $ResourceGroupName

$sqlCredentials = Get-CredentialFromConsole "Please provide the administrative credentials for your Azure SQL instance"


Write-Host "Starting import. NOTE: This process can take an hour or more."

try
{
	$importRequest = New-AzureRmSqlDatabaseImport -ResourceGroupName $ResourceGroupName `
   -ServerName $sqlServer.ServerName `
   -DatabaseName "EdFi_Ods_Glendale" `
   -DatabaseMaxSizeBytes "268435456000" `
   -StorageKeyType "SharedAccessKey" `
   -StorageKey "?" `
   -StorageUri $GlendaleDatasetUrl `
   -Edition "Standard" `
   -ServiceObjectiveName "S2" `
   -AdministratorLogin $sqlCredentials.UserName `
   -AdministratorLoginPassword $sqlCredentials.Password
   

	Write-Host "Waiting on import to complete" -NoNewline
	$importStatus = Get-AzureRmSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink
	while ($importStatus.Status -eq "InProgress")
	{
		$importStatus = Get-AzureRmSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink
		Write-Host "." -NoNewline
		Start-Sleep -s 60
	}

	Write-Host
	Write-Success "Import Complete"
	Write-Success "***NOTE***"
	Write-Success "More steps are necessary to bring the Glendale dataset online.  Please refer back to the TechDocs instructions for next steps."
	Write-Success "**********"
}

catch
{
	Write-Error "Error during import process: "
	Write-Error $_.Exception.Message
}

