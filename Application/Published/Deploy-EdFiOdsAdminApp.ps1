# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

#Requires -Version 3.0

<#
.SYNOPSIS
    Deploys a copy of the Ed-Fi ODS to an Azure account
.DESCRIPTION
    Deploys a copy of the Ed-Fi ODS to an Azure account
.PARAMETER Version
    Version of the Ed-Fi ODS you want to deploy.  Valid version numbers are published in Ed-Fi TechDocs.
.PARAMETER ResourceGroupLocation
    The name of the Azure region where all resources will be provisioned (see https://azure.microsoft.com/en-us/regions/).  You should try and use a region near you for optimal performance.
.PARAMETER InstallFriendlyName
    A friendly name to help identify this instance of the Ed-Fi ODS within Azure.  Must be no more than 64 characters long
.PARAMETER UseMyOwnSqlServer
	If provided, the script will not provision databases for you in Azure SQL.  Instead, you'll be required to provide the connection info to your own SQL Server already configured with ODS Databases.
.PARAMETER Edition
	Edition (test, release) of the Azure Deploy scripts to deploy.  Defaults to test.
.PARAMETER TemplateFileDirectory
    Points the script to the directory that holds the Ed-Fi ODS install templates.  By default that directory is the same as the one that contains this script.
.PARAMETER OdsTemplate
    The database template (minimal,populated) to be used for the ODS database. Minimal template contains only the Ed-Fi enumerations. Populated template contains sample dataset with approximately 1000 students. By default minimal template is used. 
.PARAMETER DeploySwaggerUI
    If provided, the script will deploy the swagger documentation for the API
.EXAMPLE
    .\Deploy-EdFiOds.ps1 -ResourceGroupLocation "South Central US"
    Deploys the latest version of the Ed-Fi ODS (including the config tool website) to the South Central US Azure region with the default instance name
.EXAMPLE
    .\Deploy-EdFiOds.ps1 -Version "1.0" -ResourceGroupLocation "South Central US" -InstallFriendlyName "EdFi ODS"
    Deploys v1.0 of the Ed-Fi ODS (including the config tool website) to the South Central US Azure region and names it "EdFi ODS"
.EXAMPLE
    .\Deploy-EdFiOds.ps1 -Version "1.0" -ResourceGroupLocation "South Central US" -UseMyOwnSqlServer
    Deploys v1.0 of the Ed-Fi ODS to the South Central US Azure region and gathers connection info for a SQL Server where you've already deployed Ed-Fi ODS databases.
#>
Param(

	[string] 
	[Parameter(Mandatory=$true)] 
	$ResourceGroupName,

	[ValidateSet("East US", "South Central US")]
	[string] 
	[Parameter(Mandatory=$true)]	
	$ResourceGroupLocation,	

	[string] 
	[Parameter(Mandatory=$true)] 
	$AdminAppNameToDeploy,

	[ValidateSet("East US", "South Central US")]
	[string] 
	[Parameter(Mandatory=$true)]	
	$AppInsightLocation,
	
	[string]
	[Parameter(Mandatory=$true)]
	$ProductionApiUrl,

	[string] 
	[Parameter(Mandatory=$false)] 
	$TemplateFileDirectory = '$PSScriptRoot',

	[string]
	[Parameter(Mandatory=$false)]
	$AdminAppVersion = '2.2.0',
	
	[string]
	[ValidateSet('release','test')]
	$Edition = 'release'	
)

Import-Module $PSScriptRoot\Dependencies.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\AzureActiveDirectoryApplicationHelper.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\EdFiOdsDeploy.psm1 -Force -DisableNameChecking

Use-Module "AzureRM" "4.3.1"
Use-Module "AzureRM.profile" "3.3.1"

# Powershell doesn't support using $PSScriptRoot in parameter defaults,
# so using that value as a marker to update with the real PSScriptRoot value
if ($TemplateFileDirectory -eq '$PSScriptRoot')
{
	$TemplateFileDirectory = $PSScriptRoot;
}

$DoNotInstallAdminApp = $false

$CacheTimeOut = "10"

$AdminAppTemplateFile = "$TemplateFileDirectory\OdsAdminApp.Latest.json"
$AdminAppTemplateParametersFile = "$TemplateFileDirectory\OdsAdminApp.parameters.Latest.json"

function Get-SqlServerInfo()
{	
	$hostName = Read-Host -Prompt "SQL Server Hostname (ex: sql.mydomain.com,1433)"
	$hostName = $hostName.Replace(':', ',')
	$adminCredentialsPrompt = "Please enter a username and password for your SQL Server.  These credentials will be used to create new database users for your Ed-Fi ODS installation."

	$sqlServer = @{
		HostName = $hostName
		AdminCredentials = (Get-CredentialFromConsole $adminCredentialsPrompt)	
	}	
	return $sqlServer
}

function Rollback-Deployment([string]$deploymentExceptionMessage) {
	Write-Host "The following error occured during deployment:" -ForegroundColor Red
	Write-Host $deploymentExceptionMessage -ForegroundColor Red
	Write-Host "Attempting to roll back.  Please wait..."  -ForegroundColor Red
	
	Try {
		# $app = Get-AzureRmWebApp -ResourceGroupName $ResourceGroupName -Name $AdminAppNameToDeploy
		# If($app)
		# {
		# 	Write-Host $app
		# }
		#Delete-AzureCloudOdsAdApplication 
	} Catch {
		$ErrorMessage = $_.Exception.Message
		$ErrorMessage += ([environment]::NewLine)
		$ErrorMessage += "Rollback Error: unable to remove application.  You may remove the application manually in the Azure Portal.";
		Write-Error $ErrorMessage
	}

	$deploymentRollbackMessage = @"
An error occured during deployment, and the changes were rolled back.

NOTE:

There may be a delay while Azure processes all rollback actions.
Please wait a few minutes before retrying or deployment may fail.
"@
	Write-Error $deploymentRollbackMessage
}

function Deploy-AdminApp($odsDeployInfo)
{
	$resourceGroupName = $odsDeployInfo.ResourceGroupName
	$appInsightsLocation = $odsDeployInfo.AppInsightsLocation	
	$sqlServer = $odsDeployInfo.SqlServerInfo
	$productionApiUrl = $odsDeployInfo.ProductionApiUrl	
	
	$deployParameters = New-Object -TypeName Hashtable
	$deployParameters.Add("version", $AdminAppVersion)
	$deployParameters.Add("edition", $Edition)
	$deployParameters.Add("appInsightsLocation", $appInsightsLocation)
	$deployParameters.Add("odsInstanceName", $resourceGroupName)
	$deployParameters.Add("sqlServerAdminLogin", $sqlServer.AdminCredentials.UserName)
	$deployParameters.Add("sqlServerAdminPassword", $sqlServer.AdminCredentials.Password)
	$deployParameters.Add("productionApiUrl", $productionApiUrl)	
	$deployParameters.Add("metadataCacheTimeOut", $CacheTimeOut)
	$deployParameters.Add("adminAppNameToDeploy", $AdminAppNameToDeploy)

	
	$templateFile = $AdminAppTemplateFile
	$templateParametersFile = $AdminAppTemplateParametersFile

	Try
	{
		Write-Host "Deploying ODS Admin App"		
		$deploymentResult = New-AzureRmResourceGroupDeployment -DeploymentDebugLogLevel All -Name ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
									   -ResourceGroupName $resourceGroupName `
									   -TemplateFile $templateFile `
									   -TemplateParameterFile $templateParametersFile `
									   @deployParameters `
									   -Force -Verbose -ErrorAction Stop
	}
	Catch
	{
		Write-Error $_.Exception.Message
		#Rollback-Deployment $resourceGroupName $_.Exception.Message
	}

	Write-Success "Ed-Fi ODS Admin App accessible at $adminAppUrl"
	
	return $deploymentResult
}

Login-AzureAccount

if (-not $DoNotInstallAdminApp)
{
	#Validate-UserIsAzureGlobalAdmin	
}

$sqlServerInfo = Get-SqlServerInfo

if (-not $DoNotInstallAdminApp)
{
	$odsDeployInfo = @{		
		ResourceGroupName = $ResourceGroupName
		ResourceGroupLocation = $ResourceGroupLocation
		AppInsightsLocation = $AppInsightLocation 	
		ProductionApiUrl = $ProductionApiUrl	
		SqlServerInfo = $sqlServerInfo
	};
		
	$adminAppDeploymentResult = Deploy-AdminApp $odsDeployInfo
}

Warmup-Website $odsDeploymentResult.Outputs.productionApiUrl.Value
Warmup-Website $adminAppDeploymentResult.Outputs.adminAppUrl.Value

Write-Success "Deployment Complete"
Write-Success "*** NOTE ***"
Write-Success "All newly deployed resources will now incur costs until they are manually removed from the Azure portal."
Write-Success "***"

