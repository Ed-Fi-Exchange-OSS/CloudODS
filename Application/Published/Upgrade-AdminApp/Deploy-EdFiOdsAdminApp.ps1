# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

#Requires -Version 3.0

<#
.SYNOPSIS
    Deploys Admin App appliacation to an existing Azure resource group
.DESCRIPTION
	Deploys Admin App appliacation to an existing Azure resource group
.PARAMETER ResourceGroupName
	Existing resource group name
.PARAMETER ResourceGroupLocation
    Existing resource group location
.PARAMETER AdminAppName
    A friendly name to help identify AdminApp within Azure.  Must be no more than 64 characters long
.PARAMETER AppInsightLocation
	Existing app insight location, mostly same as resouce group location
.PARAMETER ProductionApiUrl
	Existing ODS/ API Url that Admin App can connect
.PARAMETER TemplateFileDirectory
	Points the script to the directory that holds the Ed-Fi ODS install templates.  By default that directory is the same as the one that contains this script.
.PARAMETER AdminAppVersion
	Admin app version to be deployed
.PARAMETER Edition
	Edition (Test, Release) of the Azure Deploy scripts to deploy.  Defaults to Release.
.EXAMPLE
	.\Deploy-EdFiOds.ps1 -ResourceGroupName "Ed-Fi-Ods-Resourcegroup" -ResourceGroupLocation "South Central US" -AdminAppName "AdminApp-Latest" -AppInsightLocation "South Central US" -ProductionApiUrl "https://edfiodsapiwebsite-production-yuw8iui32.azurewebsites.net"
    Deploys the provided version of the AdminApp to the South Central US Azure region with the default instance name
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
	$AdminAppName,

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
	[ValidateSet('Release','Test')]
	$Edition = 'Release'	
)

Import-Module $PSScriptRoot\..\Dependencies.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\..\EdFiOdsDeploy.psm1 -Force -DisableNameChecking

Use-Module "AzureRM" "4.3.1"
Use-Module "AzureRM.profile" "3.3.1"

# Powershell doesn't support using $PSScriptRoot in parameter defaults,
# so using that value as a marker to update with the real PSScriptRoot value
if ($TemplateFileDirectory -eq '$PSScriptRoot')
{
	$TemplateFileDirectory = $PSScriptRoot;
}

$CacheTimeOut = "10"

$AdminAppTemplateFile = "$TemplateFileDirectory\OdsAdminApp.Upgrade.json"
$AdminAppTemplateParametersFile = "$TemplateFileDirectory\OdsAdminApp.parameters.Upgrade.json"

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
	$deployParameters.Add("adminAppNameToDeploy", $AdminAppName)

	
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
	}
	
	$adminAppUrl = $deploymentResult.Outputs.adminAppUrl.Value
	Write-Success "Ed-Fi ODS Admin App accessible at $adminAppUrl"
	
	return $deploymentResult
}

function IsDBInstalled([string]$Server, [string]$database)
{	 
	$t=Invoke-Sqlcmd -ServerInstance $Server -Username  $user -Password  $pwd -Database "master" -Query "select 1 from sys.databases where name='$database'" -OutputSqlErrors $true 
	if (!$t) {				
		Write-Error "Failed to connect to [$database] database on [$Server]" -ErrorAction Stop
	} else {				   
		Write-Success "[$database] Database exists in SQL Server [$Server]"
	}
}

function Run-DbMigrations($sqlServerInfo)
{
	$destinationZipFile = "$PSScriptRoot/Database.zip"
	$scriptFilesPath = "$PSScriptRoot/ScriptFiles"
	Invoke-WebRequest -Uri "https://odsassets.blob.core.windows.net/public/adminapp/Release/2.2.0/edfi.suite3.ods.adminapp.database.2.2.0.zip" -OutFile $destinationZipFile
	Expand-Archive $destinationZipFile -DestinationPath $scriptFilesPath -Force
	
	$Server =  $sqlServerInfo.HostName
	$database = "EdFi_Admin"
	$user = $sqlServerInfo.AdminCredentials.UserName
	$pwd = (New-Object PSCredential $user, $sqlServerInfo.AdminCredentials.Password).GetNetworkCredential().Password	
	 
	IsDBInstalled $Server $database	 

	$scripts = Get-ChildItem "$scriptFilesPath/MsSql" | Where-Object {$_.Extension -eq ".sql"}
	foreach ($s in $scripts)
	{   
		Write-Host "Running Script : " $s.Name -ForegroundColor Yellow
		$tables=Invoke-Sqlcmd -ServerInstance $Server -Username  $user -Password  $pwd -Database  $database -InputFile $s.FullName -ErrorAction 'Stop' -querytimeout (65535)
		write-host ($tables | Format-List | Out-String) 
	}
	
}

Login-AzureAccount

Validate-UserIsAzureGlobalAdmin

$sqlServerInfo = Get-SqlServerInfo

$odsDeployInfo = @{		
	ResourceGroupName = $ResourceGroupName
	ResourceGroupLocation = $ResourceGroupLocation
	AppInsightsLocation = $AppInsightLocation 	
	ProductionApiUrl = $ProductionApiUrl	
	SqlServerInfo = $sqlServerInfo
};
	
$adminAppDeploymentResult = Deploy-AdminApp $odsDeployInfo

Warmup-Website $adminAppDeploymentResult.Outputs.adminAppUrl.Value

Write-Success "Deployment Complete"
Write-Success "*** NOTE ***"
Write-Success "All newly deployed resources will now incur costs until they are manually removed from the Azure portal."
Write-Success "***"

$confirmation = Read-Host -Prompt "Please confirm that, all the database tables verification/ deletions are completed. If yes, please enter 'y' or 'Y' to proceed with the db migration."
if (-Not ($confirmation -ieq 'y')) {
	exit 0
}

Run-DbMigrations($sqlServerInfo)