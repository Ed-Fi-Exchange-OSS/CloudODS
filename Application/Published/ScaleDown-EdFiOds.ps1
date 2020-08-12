# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

<#
.SYNOPSIS
	Scales down Ed-Fi ODS resources to minimize costs during testing and development
.DESCRIPTION
	Scales down Ed-Fi ODS resources to minimize costs during testing and development
.PARAMETER InstallFriendlyName
	Install-friendly name or Resource group name of the Ed-Fi ODS instance that will be scaled
.EXAMPLE
	.\ScaleDown-EdFiOds -InstallFriendlyName "EdFi ODS" 
#>
Param(
	[string]
	[ValidatePattern('^[a-zA-z0-9\s-_]+$')]
	[Parameter(Mandatory=$true)]
	$InstallFriendlyName
)

Import-Module $PSScriptRoot\EdFiOdsDeploy.psm1 -Force -DisableNameChecking
$ResourceGroupName = Get-ResourceGroupName $InstallFriendlyName


function Set-DatabaseScale([string]$dbServiceObjectiveName) {
	$sqlServer =   Get-AzureRmSqlServer -ResourceGroupName $ResourceGroupName

	if ($sqlServer -eq $null) {
		Write-Error "Error locating sql server in resource group $ResourceGroupName"
	}

	if ($sqlServer.Count -gt 1) {
		Write-Error "$ResourceGroupName Sql Server Error: Expected to find 1 sql server, but instead found $sqlServer.Count"
	}

	foreach ($database in Get-AzureRmSqlDatabase -ServerName $sqlServer.ServerName -ResourceGroupName $ResourceGroupName |where {$_.DatabaseName -ne "master" -and $_.CurrentServiceObjectiveName -ne $dbServiceObjectiveName }) {
		Write-Host  "$($database.DatabaseName): Setting service level to $dbServiceObjectiveName"
		Set-AzureRmSqlDatabase -DatabaseName $database.DatabaseName -ServerName $sqlServer.ServerName -ResourceGroupName $ResourceGroupName -RequestedServiceObjectiveName $dbServiceObjectiveName -Edition $dbServiceObjectiveName | Out-Null
	}
}

function Disable-WebsitesAlwaysOn() {
	foreach ($website in (Get-AzureRmWebApp -ResourceGroupName $ResourceGroupName)) {
		$websiteName = $website.Name;
		Write-Host  "Disabling AlwaysOn for $websiteName"
		Set-AzureRmResource -PropertyObject @{"siteConfig" = @{"AlwaysOn" = $false}} -ResourceName $websiteName -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Web/sites" -Force | Out-Null
	}	
}

function Set-WebAppServicePlan($tier, $numberOfWorkers, $workerSize) {
	foreach ($plan in Get-AzureRmAppServicePlan -ResourceGroupName $ResourceGroupName) {
		Write-Host  "$($plan.Name): setting tier to $tier"
		Set-AzureRmAppServicePlan -Name $plan.Name -ResourceGroupName $ResourceGroupName  -Tier $tier -NumberofWorkers $numberOfWorkers -WorkerSize $workerSize | Out-Null
	}
}

Login-AzureAccount

$resourceGroupExists = Assert-ResourceGroupExists $ResourceGroupName
if ($resourceGroupExists -eq $false) {
	Write-Error "Unable to retrieve resource group $resourceGroupName. Downscale operation cancelled"
}

Set-DatabaseScale "Basic"
Disable-WebsitesAlwaysOn
Set-WebAppServicePlan "Free" 1 "Small"
Write-Success "Operation complete.  IMPORTANT: You should verify that all pricing levels have been successfully configured from the Azure Portal in order to avoid incurring any unexpected charges"