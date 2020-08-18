# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

<#
.SYNOPSIS
	Updates Ed-Fi ODS resources with a newer version published by Ed-Fi
.DESCRIPTION
	Updates Ed-Fi ODS resources with a newer version published by Ed-Fi
.PARAMETER Version
	Version number to update the given Ed-Fi ODS; if not provided, the latest available version will be used
.PARAMETER InstallFriendlyName
	Install-friendly name or Resource group name of the Ed-Fi ODS instance that will be scaled
.EXAMPLE
	.\Update-EdFiODS -InstallFriendlyName "EdFi ODS" 
#>
Param(
	[Version]
	$Version,

	[ValidatePattern('^[a-zA-z0-9\s-]+$')]
	[ValidateLength(1,64)]
	[string] 
	[Parameter(Mandatory=$false)] 
	$InstallFriendlyName = 'EdFi ODS',

	[string] 
	[Parameter(Mandatory=$false)] 
	$TemplateFileDirectory = '.\',
	
	[string] 
	[Parameter(Mandatory=$false)] 
	$Edition = 'release',

	[switch]
	$Force
)

Import-Module $PSScriptRoot\Dependencies.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\KuduApiSupport.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\EdFiOdsDeploy.psm1 -Force -DisableNameChecking
Use-Module "AzureRM" "4.3.1"

$OdsTemplateFile = "$TemplateFileDirectory\OdsUpdate.json"
$OdsTemplateParametersFile = "$TemplateFileDirectory\OdsUpdate.parameters.json"

function Validate-RequestedInstallVersionExists()
{
	if (-not $Version)
	{
		$script:Version = Select-CloudOdsVersionToDeploy $Edition
	}

	else
	{
		Validate-VersionAndEdition $Version.ToString() $Edition
	}
}

function Validate-UpdateIsPossible()
{
	$currentVersion = Get-CloudOdsVersion $InstallFriendlyName
	if ($currentVersion -gt $Version -and -not $Force)
	{
		Write-Error "Ed-Fi ODS '$InstallFriendlyName' currently has version $currentVersion installed, but you are trying to install version $Version.  If you intend to downgrade your installed version, please pass the -Force flag to this script."
	}

	if ($currentVersion -eq $Version -and -not $Force)
	{
		Write-Error "Ed-Fi ODS '$InstallFriendlyName' is already at version $currentVersion.  If you intend to re-install, please pass the -Force flag to this script."
	}

	if ($Version.Major -gt $currentVersion.Major)
	{
		Write-Error "Ed-Fi ODS '$InstallFriendlyName' currently has version $currentVersion installed, but you are trying to install version $Version.  Major version upgrades are not currently supported."
	}
	
	if ($currentVersion.Major -eq 2 -and $currentVersion.Minor -le 4 -and $Version.Major -eq 2 -and $Version.Minor -ge 5)
	{
		Write-Error "Ed-Fi ODS '$InstallFriendlyName' currently has version $currentVersion installed, and you are trying to install version $Version. Due to breaking changes in the database schema for Ed-Fi ODS 2.5, versions prior 2.4.x cannot currently be upgraded to 2.5.x and beyond."
	}
}

function Update-OdsVersion($resourceGroupName)
{
	$tags = (Get-AzureRmResourceGroup -Name $resourceGroupName).Tags
	$tags["Cloud-Ods-Version"] = $Version;
	$tags["Cloud-Ods-Edition"] = $Edition;
	
	Set-AzureRmResourceGroup -Name $resourceGroupName -Tags $tags
}

function Get-AzureRmWebSiteName($resourceGroupName, $baseName)
{
    $webSite = (Get-AzureRmResource | Where {$_.ResourceGroupName -eq $resourceGroupName -and $_.ResourceType -eq 'Microsoft.Web/sites' -and $_.Name -like "*$baseName*"})
    return $webSite.Name;
}

function Update-Ods()
{
	Write-Host "Updating EdFi ODS to version $Version"
	$resourceGroupName = Get-ResourceGroupName $InstallFriendlyName

	$existingAppPlans = Get-AzureRmAppServicePlan -ResourceGroupName $resourceGroupName
	$adminAppWebsiteServiceObjective = ($existingAppPlans | Where {$_.Name -like '*Admin*'}).Sku.Name
	$productionWebsiteServiceObjective = ($existingAppPlans | Where {$_.Name -like '*Production*'}).Sku.Name
		
	$deployParameters = New-Object -TypeName Hashtable
	$deployParameters.Add("version", $Version.ToString())
	$deployParameters.Add("edition", $Edition)

	$deployParameters.Add("adminAppWebsiteServiceObjective", $adminAppWebsiteServiceObjective)
	$deployParameters.Add("productionWebsiteServiceObjective", $productionWebsiteServiceObjective)
	
	$templateFile = $OdsTemplateFile
	$templateParametersFile = $OdsTemplateParametersFile
		
    $deploymentResult = New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                   -ResourceGroupName $resourceGroupName `
                                   -TemplateFile $templateFile `
                                   -TemplateParameterFile $templateParametersFile `
                                   @deployParameters `
                                   -Force -Verbose -ErrorAction Stop
	
	Update-OdsVersion $resourceGroupName

	return $deploymentResult
}

Validate-RequestedInstallVersionExists
Login-AzureAccount
Validate-UpdateIsPossible
$deploymentResult = Update-Ods

Warmup-Website $deploymentResult.Outputs.productionApiUrl.Value
Warmup-Website $deploymentResult.Outputs.swaggerUrl.Value
Warmup-Website $deploymentResult.Outputs.adminAppUrl.Value

$adminAppUrl = $deploymentResult.Outputs.adminAppUrl.Value

Write-Success "Deployment Complete"
Write-Success "Login to the AdminApp ($adminAppUrl) to complete the Update process."

Start-Process $adminAppUrl