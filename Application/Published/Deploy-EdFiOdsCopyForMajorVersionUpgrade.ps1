# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

#Requires -Version 3.0

<#
.SYNOPSIS
	Prepares a new resource group for a major version upgrade using data from an existing Ed-Fi ODS instance
.DESCRIPTION
	Prepares a new resource group for a major version upgrade using data from an existing Ed-Fi ODS instance
.PARAMETER SourceInstallFriendlyName
	Install-friendly name or Resource group name of the old Ed-Fi ODS instance containing data that will be migrated: e.g. 'EdFi ODS'.  This instance must already exist.
.PARAMETER DestinationInstallFriendlyName
	Install-friendly name or Resource group name of the new Ed-Fi ODS instance that will be created: e.g. 'EdFi ODS v3'.
.PARAMETER MigrationToolExePath
	Points the script to the EdFi ODS Migration console utility (.exe).  By default, this utility is assumed to be installed in ..\Tools\Migration\
.PARAMETER DescriptorNamespacePrefix
	Needed for major version upgrade only if there are non-default descriptors present.  Namespace prefix for new descriptors that are not in the Ed-Fi defaults.  Must be in the format: "uri://[organization_name]".
.PARAMETER CredentialNamespacePrefix
	Needed to upgrade to v3.1 if there are records in the table edfi.Credential. Namespace prefix to use for all staff credential records.  Must be in the format: "uri://[organization_name]".
.PARAMETER CalendarConfigFilePath
	Needed to upgrade to v3.1 if the source ODS has a calendar with multiple school years.  See migration utility documentation for details.
.PARAMETER MigrationScriptTimeout
	Timeout (in seconds) to be applied to each transaction during the upgrade process.  Increase this value if you encounter timeout exceptions on larger datasets
.PARAMETER Edition
    Edition of the new Ed-Fi ODS you want to deploy.  The release edition will be chosen by default.
.PARAMETER Version
	Version of the new Ed-Fi ODS you want to deploy.  The latest available version will be chosen by default.
.PARAMETER TemplateFileDirectory
	Points the script to the directory that holds the Ed-Fi ODS install templates.  By default that directory is the same as the one that contains this script.
.PARAMETER ForceDatabaseUpgradeToVersion
	Primarily for development use:  Force database to upgrade to the specified version.  Format: major.minor[.build[.revision]]
#>

Param(
	[ValidatePattern('^[a-zA-z0-9\s-]+$')]
	[ValidateLength(1,64)]
	[string] 
	[Parameter(Mandatory=$true)] 
	$SourceInstallFriendlyName,

 	[ValidatePattern('^[a-zA-z0-9\s-]+$')]
	[ValidateLength(1,64)]
	[string] 
	[Parameter(Mandatory=$true)] 
	$DestinationInstallFriendlyName,

	[string] 
	[Parameter(Mandatory=$false)] 
	$MigrationToolExePath = (Join-Path $PsScriptRoot -ChildPath "\Tools\Migration\EdFi.Ods.Utilities.Migration.exe"),

	[string] 
	$DescriptorNamespacePrefix = "uri://ed-fi.org",

	[string] 
	$CredentialNamespacePrefix = "uri://ed-fi.org",

	[string]
	[Parameter(Mandatory=$false)]
	$CalendarConfigFilePath,

	[int] 
	$MigrationScriptTimeout = 3600,

	[string]
	[ValidateSet('release','test')]
	$Edition = 'release',

	[Version]
	[Parameter(Mandatory=$false)]
	$Version,

	[string] 
	[Parameter(Mandatory=$false)] 
	$TemplateFileDirectory = '.\',

	[string]
	[Parameter(Mandatory=$false)]
	$ForceDatabaseUpgradeToVersion
)

Import-Module $PSScriptRoot\Dependencies.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\KuduApiSupport.psm1 -Force -DisableNameChecking
Import-Module $PSScriptRoot\EdFiOdsDeploy.psm1 -Force -DisableNameChecking
Use-Module "AzureRM" "4.3.1"
Use-Module "AzureRM.profile" "3.3.1"

New-Variable -Name "UpgradeInProgressNamingConventionPrefix" -Value "UPGRADE_IN_PROGRESS" -Option Constant -Scope Script

function Assert-RequestedInstallVersionExists()
{
	if ($ForceDatabaseUpgradeToVersion) {
		try {
			$upgradeVersion = ([Version] $ForceDatabaseUpgradeToVersion)
		} catch {
			$upgradeVersion = $null
		}
		if ((-not $upgradeVersion) -or ([Version] "0.0") -ge $upgradeVersion) {
			Write-Error "Invalid database upgrade version:  $ForceDatabaseUpgradeToVersion.  Must be in format major.minor[.build[.revision]]"
		}
	}
	if (-not $Version)
	{
		$script:Version = Select-CloudOdsVersionToDeploy $Edition
	}

	else
	{
		Validate-VersionAndEdition $Version.ToString() $Edition
	}
}

function Assert-UpgradePathSupported() {
	$sourceVersion = Get-CloudOdsVersion $SourceInstallFriendlyName

	if ($ForceDatabaseUpgradeToVersion) {
		Write-Host "Skipping upgrade version validation:  Forcing upgrade from $sourceVersion to $ForceDatabaseUpgradeToVersion"
		return
	}

	$detailsMessage = "[Details: Source version ($SourceInstallFriendlyName): $sourceVersion.  Destination requested version ($DestinationInstallFriendlyName): $Version]"
	if ($sourceVersion.Major -gt $Version.Major ) {
		Write-Error "Major version downgrades are not supported at this time. $detailsMessage"
	}

	if ($sourceVersion.Major -eq $Version.Major ) {
		Write-Error "This deployment script is designed for major version upgrades only.  For minor version upgrades or reinstallations, please use the included Ed-Fi ODS Upgrade script instead. $detailsMessage"
	}
}

$DestinationStatusOption = New-Object -TypeName PSObject -Prop @{
	'Free' = 'Resource group free: Ready for deployment';
	'UpgradeInProgress' = 'Upgrade in progress';
	'Invalid' = 'Invalid destination: Resource group exists and is an invalid target for migration';
}

function Get-DestinationResourceGroupStatus() {
	$resourceGroupName = Get-ResourceGroupName $DestinationInstallFriendlyName
	$resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
	$resourceGroupIsFree = ($null -eq $resourceGroup)

	if ($resourceGroupIsFree) {
		return $DestinationStatusOption.Free
	}

	$upgradeInProgress = ($resourceGroup.Tags.Keys | Where-Object { $_ -like $UpgradeInProgressNamingConventionPrefix}).Count -ge 1

	if ($upgradeInProgress) {
		return $DestinationStatusOption.UpgradeInProgress
	}

	return $DestinationStatusOption.Invalid
}

function Assert-DestinationDeploymentSucceeded([PSObject] $destinationDeploymentResult) {
	if (!$destinationDeploymentResult.Success) {
		Write-Error "An error occurred while deploying new resource group $DestinationInstallFriendlyName.  If this resource group still exists, you should remove it manually from the Azure portal to avoid incurring additional charges."
	}
}

function Get-EdFiOdsSqlServerName([string] $friendlyName) {
	$resourceGroupName = Get-ResourceGroupName $friendlyName
	Retry-Command -ExponentialBackoff { 
		$serverName = (Get-AzureRmSqlServer -ResourceGroupName $resourceGroupName).ServerName
		if ($null -eq $serverName)
		{
			throw "An error occurred while retrieving sql server information from $friendlyName."
		} else {
			return $serverName
		}
	}
}

function Copy-SourceDatabaseToDestinationServer([string] $sourceDatabasename, [string] $destinationDatabaseName, [hashtable] $destinationTags) {
	$statusMessage = "Copying database '$sourceDatabasename' from source ($SourceInstallFriendlyName) to destination ($DestinationInstallFriendlyName)"
	$sourceResourceGroupName = Get-ResourceGroupName $SourceInstallFriendlyName
	$destinationResourceGroupName = Get-ResourceGroupName $DestinationInstallFriendlyName
	$sourceServerName = Get-EdFiOdsSqlServerName $SourceInstallFriendlyName
	$destinationServerName = Get-EdFiOdsSqlServerName $DestinationInstallFriendlyName

	Retry-Command -StatusMessage $statusMessage -ExponentialBackoff {
		$databaseCopyResult = New-AzureRmSqlDatabaseCopy -DatabaseName $sourceDatabasename -CopyDatabaseName $destinationDatabaseName -ResourceGroupName $sourceResourceGroupName -CopyResourceGroupName $destinationResourceGroupName -ServerName $sourceServerName -CopyServerName $destinationServerName
		if ($null -eq $databaseCopyResult)
		{
			throw "An error occurred while executing the database copy operation."
		}
	}
	#Wait for a few seconds for the newly created resource to appear before querying it
	Start-Sleep -Seconds 30

	$statusMessage = "Adding tags to destination database."
	Retry-Command -StatusMessage $statusMessage -ExponentialBackoff {
		$destinationDatabaseResourceId = (Find-AzureRmResource -ResourceGroupNameEquals $destinationResourceGroupName -Name $destinationDatabaseName -ResourceType "Microsoft.Sql/servers/databases").ResourceId		
		$addTagResult = Set-AzureRmResource -Tag $destinationTags -ResourceId $destinationDatabaseResourceId -Force
		if ($null -eq $addTagResult)
		{
			throw "An error occurred while adding tags to the destination database"
		}
	}

	$statusMessage = "Enabling transparent data encryption on destination database."
	Retry-Command -StatusMessage $statusMessage -ExponentialBackoff {
		$enableEncryptionResult = Set-AzureRMSqlDatabaseTransparentDataEncryption -ResourceGroupName $destinationResourceGroupName -ServerName $destinationServerName -DatabaseName $destinationDatabaseName -State "Enabled"
		if ($null -eq $enableEncryptionResult)
		{
			throw "An error occurred while enabling transparent data encryption on the new database."
		}
	}
}

function Select-FirewallSecurityPreference([string] $external_ip)
{
	$ipAddressDisplayText = $external_ip
	if ($null -eq $external_ip) {
		$ipAddressDisplayText = "the IP address of your choosing"
	}
	$options = @(
		$null,
		@{Value = $true; DisplayText = "Yes: Temporarily add a firewall rule granting access to $ipAddressDisplayText.  I understand the security implications."},
		@{Value = $false; DisplayText = "No: I will manage the firewall rules myself"}
	)

	$choice = 0

	while ($choice -eq 0)
	{
		Write-Host "The migration tool will require direct database access to upgrade the ODS.  Would you like to automatically create a firewall rule?"
		Write-Host
		
		For ($i = 1; $i -lt $options.Length; $i++) {
			Write-Host "[$i] $($options[$i].DisplayText)"
		}
		Write-Host

		$input = Read-Host -Prompt "Enter selection"

		if ([int32]::TryParse($input, [ref]$choice))
		{
			if ($choice -gt 0 -and $choice -lt $options.length)
			{
				$selectionResult = $options[$choice].Value
				return $selectionResult
			}
			else
			{
				$choice = 0;
			}
		}
		else
		{
			$choice = 0;
		}
	}
}

function Add-DestinationFirewallRule([PSObject] $firewallOptions) {
	$firewallRuleCreationResult = $null
	if ($firewallOptions.AddRule -ne $true) {
		return $firewallRuleCreationResult
	}
	$resourceGroupName = Get-ResourceGroupName $DestinationInstallFriendlyName
	$destinationServerName = Get-EdFiOdsSqlServerName $DestinationInstallFriendlyName 
	$statusMessage = "Automatic firewall rule creation is enabled.  Granting server access to IP $($firewallOptions.IP)"
	
	Retry-Command -StatusMessage $statusMessage -ExponentialBackoff {
		$firewallRuleAlreadyExists = Remove-AzureRmSqlServerFirewallRule -FirewallRuleName $firewallOptions.RuleName -ResourceGroupName $resourceGroupName -ServerName $destinationServerName -ErrorAction SilentlyContinue
		if ($firewallRuleAlreadyExists) {
			#Wait for a few seconds for rule deletion to be processed
			Start-Sleep -Seconds 15
		}

		$firewallRuleCreationResult = New-AzureRmSqlServerFirewallRule -ResourceGroupName $resourceGroupName -FirewallRuleName $firewallOptions.RuleName -StartIpAddress $firewallOptions.IP -EndIpAddress $firewallOptions.IP -ServerName $destinationServerName
		if ($null -eq $firewallRuleCreationResult)
		{
			Write-Warning "Automatic firewall rule creation failed.  You will need to perform this action manually in the Azure portal before launching the migration tool."
		}
	}
}


function Remove-DestinationFirewallRule([PSObject] $firewallOptions) {
	$resourceGroupName = Get-ResourceGroupName $DestinationInstallFriendlyName
	$destinationServerName = Get-EdFiOdsSqlServerName $DestinationInstallFriendlyName 

	if ($firewallOptions.AddRule -ne $true) {
		#Just in case: ensure temporary firewall rule is removed if a previous deployment was closed forcefully or the rule was left intact for troubleshooting
		Remove-AzureRmSqlServerFirewallRule -FirewallRuleName $firewallOptions.RuleName -ResourceGroupName $resourceGroupName -ServerName $destinationServerName -ErrorAction SilentlyContinue
		return
	}

	$statusMessage = "Removing temporary firewall rule"
	Retry-Command -StatusMessage $statusMessage -ExponentialBackoff {
		$result = Remove-AzureRmSqlServerFirewallRule -FirewallRuleName $firewallOptions.RuleName -ResourceGroupName $resourceGroupName -ServerName $destinationServerName -ErrorAction SilentlyContinue
		if ($null -eq $result)
		{
			Write-Warning "Warning:  removal of temporary firewall rule failed.  If this item still exists, you should remove it manually from the Azure portal."
		}
	}
}

function Get-FirewallOptions () {
	$firewallOptions = 
	@{
		'AddRule'= $false;
		'IP'= $null;
		'RuleName' = "$UpgradeInProgressNamingConventionPrefix-MigrationTool"
	}

	$firewallOptions.IP = Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip -ErrorAction SilentlyContinue

	if ($null -eq $firewallOptions.IP) 
	{
		Write-Host Your external IP was detected as $firewallOptions.IP 
	} else {
		Write-Host Your external IP could not be automatically detected
	}

	$firewallOptions.AddRule = Select-FirewallSecurityPreference $firewallOptions.IP

	if ($firewallOptions.AddRule -and ($null -eq $firewallOptions.IP)) {
		while (-not ($firewallOptions.IP -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'))
		{
			$firewallOptions.IP = Read-Host -Prompt "Please enter your external IP address, or press enter to skip if you prefer to use the Azure Portal"
			if (!$firewallOptions.IP) {
				$firewallOptions.IP = $null
				break;
			}
		}		
	}

	if ($null -eq $firewallOptions.IP) {
		$firewallOptions.AddRule = $false
	}

	if ($firewallOptions.AddRule) {
		Write-Host "A firewall rule will be automatically created for use by the migration tool."
	} else {
		Write-Host "A firewall rule will NOT be created.  You will need to perform this action manually before launching the data migration tool."
	}
	return $firewallOptions
}

function Get-DatabaseConnectionStringBuilder([string] $friendlyName, [string] $databaseName, [PSCredential] $credentials) {
	$serverName = Get-EdFiOdsSqlServerName $friendlyName

	$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
	$builder["Data Source"] = "$serverName.database.windows.net"
	$builder["Initial Catalog"] = $databaseName
	$builder["User ID"] = (Get-CredentialAsPlainText $credentials).UserName
	$builder["Password"] = (Get-CredentialAsPlainText $credentials).Password
	$builder["Connect Timeout"] = $MigrationScriptTimeout
	$builder["Encrypt"] = $true

	return $builder
}
function Update-CalendarConfiguration {
	$noCalendarFileProvidedMessage = "No calendar configuration file provided:  Using default/single year configuration"

	if (!$script:CalendarConfigFilePath) {
		Write-Host $noCalendarFileProvidedMessage
		return
	}
	while ($script:CalendarConfigFilePath -and !(Test-Path $script:CalendarConfigFilePath)) {

		if ($script:CalendarConfigFilePath) {
			Write-Host "The supplied calendar configuration file was not found."
		}

		$script:CalendarConfigFilePath = Read-Host -Prompt "Please enter calendar configuration file path, or press enter to browse"
		if (!$script:CalendarConfigFilePath) {
			[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
			$openFile = New-Object System.Windows.Forms.OpenFileDialog
			$openFile.Filter = "CSV (*.csv)| *.csv"
			$openFile.MultiSelect = $false
			$openFile.ShowDialog()
			$script:CalendarConfigFilePath = $openFile.FileName
		}
		$script:CalendarConfigFilePath = $script:CalendarConfigFilePath.Replace('"', '')
		if (!$script:CalendarConfigFilePath) {
			Write-Host $noCalendarFileProvidedMessage
			return
		}
	}
}

function Handle-MigrationSqlException([PSObject] $firewallOptions, [string] $targetDatabaseName) {
	$leaveTemporaryFirewallRule = $false
	if ($firewallOptions.AddRule) {
		Write-Host 
		$leaveTemporaryFirewallRule = Get-BooleanFromConsolePrompt "Migration failed (see previous errors).  Would you like to leave the firewall rule active for remote troubleshooting?"
		if ($leaveTemporaryFirewallRule) {
			Write-Host "Firewall rule will not be removed.  Please be sure to re-run this script or remove this item manually when you have finished making changes."
		}
	}

	if (!$leaveTemporaryFirewallRule) {
		Remove-DestinationFirewallRule $firewallOptions
	}

	$serverName = Get-EdFiOdsSqlServerName $DestinationInstallFriendlyName
	Write-Host 
	Write-Host "Connect to the destination database [$targetDatabaseName] at $serverName.database.windows.net to resolve conflicts, and then launch this script again to resume the migration process."
}

function Migrate-EdFiOdsDestination([string] $targetDatabaseName, [PSCredential] $credentials, [PSObject] $configUploadResult) {
	$exitCode = $null
	$ConnectionStringBuilder = Get-DatabaseConnectionStringBuilder "$DestinationInstallFriendlyName" "$targetDatabaseName" $credentials

	$args = @(
	"--Database","$($ConnectionStringBuilder.ConnectionString)",
	"--Timeout", "$MigrationScriptTimeout",
	"--DescriptorNamespace", "$DescriptorNamespacePrefix",
	"--CredentialNamespace","$CredentialNamespacePrefix",
	"--AzureStorageLocation", "$($configUploadResult.AzureStorageLocation)"
	)

	if ($ForceDatabaseUpgradeToVersion) {
		$args += @("--ToVersion", "$ForceDatabaseUpgradeToVersion")
	} else {
		$upgradeVersionAux = Get-CloudOdsVersion "$DestinationInstallFriendlyName"
		$upgradeVersion = "$($upgradeVersionAux.Major).$($upgradeVersionAux.Minor)"
		$args += @("--ToVersion", "$upgradeVersion")
	}

	if ($configUploadResult.CalendarFileName) {
		$args += @("--CalendarConfigPath", "$($configUploadResult.ResourceContainerName)/$($configUploadResult.CalendarFileName)")
	}

	Write-Host "Launching migration utility"
	try 
	{
		& "$MigrationToolExePath" $args | Write-Host
		$exitCode = $LASTEXITCODE
	} finally {
		if ($exitCode -and ($exitCode -gt 1)) {
			Handle-MigrationSqlException $firewallOptions $targetDatabaseName
		} else {
			Remove-DestinationFirewallRule $firewallOptions
		}
	}
	return $exitCode
}

function Upload-ConfigFilesToDestination([string] $migrationResourcesContainerName) {
	$resourceGroupName = Get-ResourceGroupName $DestinationInstallFriendlyName
	$storageAccount = (Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName)
	$containerName = $migrationResourcesContainerName
	$container = Get-AzureStorageContainer -Name $containerName -Context $storageAccount.Context -ErrorAction SilentlyContinue

	if ($null -eq $container) {
		$container = New-AzureStorageContainer -Name $migrationResourcesContainerName -Context $storageAccount.Context -Permission Blob -ConcurrentTaskCount 1
	}

	if ($script:CalendarConfigFilePath) {
		$calendarConfigDestinationName = "calendar-config.csv"

		$statusMessage = "Uploading calendar configuration"
		Retry-Command -StatusMessage $statusMessage -ExponentialBackoff {
			$uploadResult = Set-AzureStorageBlobContent -File "$CalendarConfigFilePath" -Blob $calendarConfigDestinationName -Container $container.Name -Context $storageAccount.Context -ConcurrentTaskCount 1 -Force
			if ($null -eq $uploadResult)
			{
				throw "An error occurred while uploading the calendar configuration file"
			}
		}
	}

	return New-Object -TypeName PSObject -Prop @{
		'AzureStorageLocation' = "https://$($storageAccount.StorageAccountName).blob.core.windows.net";
		'ResourceContainerName' = "$migrationResourcesContainerName";
		'CalendarFileName' = "$calendarConfigDestinationName";
		'DescriptorXMLBlobLocation' = "$DescriptorXMLBlobLocation"
	}
}

function Stop-AllWebApps([string] $friendlyName) {
	$resourceGroupName = Get-ResourceGroupName $friendlyName
	$websites = ((Get-AzureRmWebApp -ResourceGroupName $resourceGroupName) | Where-Object { $_.State -ne 'Stopped' })

	foreach ($website in $websites) 
	{
		Write-Host "Shutting down $($website.Name) for upgrade" 
		Stop-AzureRmWebApp -ResourceGroupName $resourceGroupName -Name $website.Name | Out-Null
	}
}

function Restart-AllWebApps([string] $friendlyName) {
	Stop-AllWebApps $friendlyName
	$resourceGroupName = Get-ResourceGroupName $friendlyName
	$websites = (Get-AzureRmWebApp -ResourceGroupName $resourceGroupName)	
	foreach ($website in $websites) 
	{
		Start-AzureRmWebApp -ResourceGroupName $resourceGroupName -Name $website.Name | Out-Null
		if ($website.DefaultHostName) {
			$url = "https://$($website.DefaultHostName).azurewebsites.net"
			Warmup-Website $url
			Write-Success "Website $($website.Name) is accessible at https://$($website.DefaultHostName)"
		}
	}
}

Login-AzureAccount
Assert-RequestedInstallVersionExists
Assert-UpgradePathSupported
$destinationStatus = Get-DestinationResourceGroupStatus
if ($destinationStatus -eq $DestinationStatusOption.Invalid) {
	Write-Error "Cannot deploy new resource group ${DestinationInstallFriendlyName}: Destination resource group already exists and is an invalid target for migration."
} else {
	Write-Host "Destination resource group status:  $destinationStatus"
}

Update-CalendarConfiguration
$firewallOptions = Get-FirewallOptions

$credentials = $null
if ($destinationStatus -eq $DestinationStatusOption.Free) {
	$destinationDeploymentResult = .\Deploy-EdFiOds.ps1 -Version $Version -InstallFriendlyName $DestinationInstallFriendlyName -TemplateFileDirectory $TemplateFileDirectory -Edition $Edition -DeployAsTargetForDataMigration
	Assert-DestinationDeploymentSucceeded $destinationDeploymentResult
	$credentials = $destinationDeploymentResult.Credentials
	Stop-AllWebApps $DestinationInstallFriendlyName
	Copy-SourceDatabaseToDestinationServer "EdFi_Ods_Production" "EdFi_Ods_Production" @{displayName="EdFi ODS Production Database"}
	Add-ResourceGroupTag "$DestinationInstallFriendlyName" "$UpgradeInProgressNamingConventionPrefix"

	if (!$firewallOptions.AddRule) {
		Write-Host "Destination resource group deployed.  Direct database access is required to continue.  If you would like to use this script for remote data migration, please manually open firewall access and re-run this script to continue."
		Exit
	}
} else {
	Stop-AllWebApps $DestinationInstallFriendlyName
	$credentials = Get-CredentialFromConsole "To resume migration, please re-enter the username and password for the destination SQL Server"
}

$configUploadResult = Upload-ConfigFilesToDestination "ed-fi-ods-migration-resources" 

if ($firewallOptions.AddRule) {
	Add-DestinationFirewallRule $firewallOptions
} else {
	Remove-DestinationFirewallRule $firewallOptions
}

$migrationResultExitCode = Migrate-EdFiOdsDestination "EdFi_Ods_Production" $credentials $configUploadResult
if ($migrationResultExitCode -eq 0) {
	Restart-AllWebApps $DestinationInstallFriendlyName
	Remove-ResourceGroupTag "$DestinationInstallFriendlyName" $UpgradeInProgressNamingConventionPrefix | Out-Null

	Write-Success "Deployment Complete"
	Write-Success "Please visit the new admin app instance directly to perform final setup steps"
	Write-Success "*** NOTE ***"
	Write-Success "All newly deployed resources will incur costs until they are manually removed from the Azure portal."
	Write-Success "***"
} else {
	Write-Host "Destination resource group currently remains in status: ""Upgrade In Progress""."		
	Write-Host "Note that all newly deployed resources will continue to incur charges until manually removed from the Azure portal."
	Write-Host "You may re-run this script with the same resource group arguments to resume the migration process at any time."
}

