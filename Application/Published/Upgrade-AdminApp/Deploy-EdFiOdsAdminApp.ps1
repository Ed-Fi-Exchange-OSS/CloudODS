# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

#Requires -Version 3.0

<#
.SYNOPSIS
    Deploys Admin App appliacation to an existing Azure resource group.
.DESCRIPTION
	Deploys Admin App appliacation to an existing Azure resource group.
.PARAMETER ResourceGroupName
	Existing resource group name.
.PARAMETER AdminAppName
    A friendly name to help identify AdminApp within Azure.  Must be no more than 64 characters long.
.PARAMETER AppInsightLocation
	Existing app insight location, mostly same as resouce group location.
.PARAMETER ProductionApiUrl
	Existing ODS/ API Url that Admin App can connect.
.PARAMETER SQLServerHostname
	SQL Server Hostname (ex: sql.mydomain.com).
.PARAMETER SQLServerUserName
	Username for your SQL Server.
.PARAMETER SQLServerPassword
	Password for your SQL Server.
.PARAMETER EncryptionKey
	Base64-encoded 256 bit key appropriate for use with AES encryption. This is optional parameter. A key will be created if one is not provided.
.PARAMETER TemplateFileDirectory
	Points the script to the directory that holds the Ed-Fi ODS install templates. By default that directory is the same as the one that contains this script.
.PARAMETER AdminAppVersion
	Admin app version to be deployed. Defaults to 2.2.0.
.PARAMETER Edition
	Edition (Test, Release) of the Azure Deploy scripts to deploy.  Defaults to Release.
.EXAMPLE
	.\Deploy-EdFiOds.ps1 -ResourceGroupName "Ed-Fi-Ods-Resourcegroup" -AdminAppName "AdminApp-Latest" -AppInsightLocation "South Central US" -ProductionApiUrl "https://edfiodsapiwebsite-production-yuw8iui32.azurewebsites.net"
    Deploys the provided version of the AdminApp to the South Central US Azure region with the default instance name
#>
Param(

	[string] 
	[Parameter(Mandatory=$true)] 
	$ResourceGroupName,

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
	[Parameter(Mandatory=$true)]
	$SQLServerHostname,

	[string]
	[Parameter(Mandatory=$true)]
	$SQLServerUserName,

	[SecureString]
	[Parameter(Mandatory=$true)]
	$SQLServerPassword,

	[string]
	[Parameter(Mandatory=$false)] 
	$EncryptionKey,

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

function Deploy-AdminApp()
{
	if(-not $EncryptionKey)
	{
		$aes = [System.Security.Cryptography.Aes]::Create()
		$aes.KeySize = 256
		$aes.GenerateKey()
		$EncryptionKey = [System.Convert]::ToBase64String($aes.Key)
	}
	
	$deployParameters = New-Object -TypeName Hashtable
	$deployParameters.Add("version", $AdminAppVersion)
	$deployParameters.Add("edition", $Edition)
	$deployParameters.Add("appInsightsLocation", $AppInsightLocation)
	$deployParameters.Add("odsInstanceName", $ResourceGroupName)
	$deployParameters.Add("sqlServerAdminLogin", $SQLServerUserName)
	$deployParameters.Add("sqlServerAdminPassword", $SQLServerPassword)
	$deployParameters.Add("productionApiUrl", $ProductionApiUrl)	
	$deployParameters.Add("metadataCacheTimeOut", $CacheTimeOut)
	$deployParameters.Add("adminAppNameToDeploy", $AdminAppName)
	$deployParameters.Add("encryptionKey", $EncryptionKey)
	
	$templateFile = $AdminAppTemplateFile
	$templateParametersFile = $AdminAppTemplateParametersFile

	Try
	{
		Write-Host "Deploying ODS Admin App"		
		$deploymentResult = New-AzureRmResourceGroupDeployment -DeploymentDebugLogLevel All -Name ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
									   -ResourceGroupName $ResourceGroupName `
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

function IsDBInstalled($pwd, [string]$database)
{	 
	$arguments = @{
		ServerInstance = $SQLServerHostname
		Username = $SQLServerUserName
		Password = $pwd
		Database = "master"
		Query = "select 1 from sys.databases where name='$database'"
		OutputSqlErrors = $true
	}

	$result = Invoke-Sqlcmd @arguments 
	if (!$result) {				
		Write-Error "Failed to connect to [$database] database on [$Server]" -ErrorAction Stop
	} else {				   
		Write-Success "[$database] Database exists in SQL Server [$Server]"
	}
}

function Run-DbMigrations()
{
	$scriptPackageUri = "https://odsassets.blob.core.windows.net/public/adminapp/$Edition/$AdminAppVersion/Edfi.suite3.ods.adminapp.database.zip"
	$destinationZipFile = "$PSScriptRoot/Database.zip"
	$scriptFilesPath = "$PSScriptRoot/ScriptFiles"
	Invoke-WebRequest -Uri $scriptPackageUri -OutFile $destinationZipFile
	Expand-Archive $destinationZipFile -DestinationPath $scriptFilesPath -Force	
	
	$database = "EdFi_Admin"
	$pwd = (New-Object PSCredential $SQLServerUserName, $SQLServerPassword).GetNetworkCredential().Password	
	 
	IsDBInstalled $pwd $database	 

	$scripts = Get-ChildItem "$scriptFilesPath/MsSql" | Where-Object {$_.Extension -eq ".sql"}
	foreach ($s in $scripts)
	{   
		Write-Host "Running Script : " $s.Name -ForegroundColor Yellow

		$arguments = @{
			ServerInstance = $SQLServerHostname
			Username = $SQLServerUserName
			Password = $pwd
			Database = $database
			InputFile = $s.FullName			
		}

		$tables = Invoke-Sqlcmd @arguments -ErrorAction 'Stop' -querytimeout (65535)
		write-host ($tables | Format-List | Out-String) 
	}
	
}

Login-AzureAccount

Validate-UserIsAzureGlobalAdmin
	
$adminAppDeploymentResult = Deploy-AdminApp 

Warmup-Website $adminAppDeploymentResult.Outputs.adminAppUrl.Value

Write-Success "Deployment Complete"
Write-Success "*** NOTE ***"
Write-Success "All newly deployed resources will now incur costs until they are manually removed from the Azure portal."
Write-Success "***"

$confirmation = Read-Host -Prompt "Please confirm that, all the database tables verification/ deletions are completed. If yes, please enter 'y' or 'Y' to proceed with the db migration"
if (-Not ($confirmation -ieq 'y')) {
	exit 0
}

Run-DbMigrations