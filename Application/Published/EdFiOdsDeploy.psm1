# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

Import-Module $PSScriptRoot\Dependencies.psm1 -Force -DisableNameChecking
Use-Module "AzureRM" "4.3.1"
Use-Module "AzureRM.profile" "3.3.1"

$OdsAssetsStorageBaseUrl = "https://odsassets.blob.core.windows.net/public/CloudOds/deploy"
$OdsAssetsStorageAccountName = "odsassets";
$AzureDeployScriptsCurrentVersion = "3.0.0"

function Add-ResourceGroupTag([string] $friendlyName, [string] $newTagName) {
	$newTag = @{$newTagName = $newTagName}
	$resourceGroupName = Get-ResourceGroupName $friendlyName
	$tags = (Get-AzureRmResourceGroup -Name $resourceGroupName).Tags
	$tags += $newTag
	$result = Set-AzureRmResourceGroup -Tag $tags -Name $resourceGroupName
	return $result
}

function Assert-ResourceGroupExists([string]$resourceGroupName) 
{
	try
	{
		Retry-Command -StatusMessage "Retrieving resource group '$resourceGroupName'" -ExponentialBackoff { $group = Get-AzureRmResourceGroup -Name $resourceGroupName; if ($group -eq $null) { throw "Error locating '$resourceGroupName'" }}
		return $true;
	}

	catch
	{
		return $false;
	}
}

function Create-Password([int]$length = 16)
{
	$ascii = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+<>,./?\|";	
	return Get-RandomString $ascii $length
}

function Create-ResourceGroup([string]$friendlyName, [string]$resourceGroupLocation, [string]$version, [string]$edition)
{
	$resourceGroupName = Get-ResourceGroupName $friendlyName

	$group = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
	if ($group -eq $null)
	{
		Write-Host "Creating new Resource Group: $resourceGroupName... "
		$tags = @{"Cloud-Ods-Version" = $version; "Cloud-Ods-Edition" = $edition; "Cloud-Ods-FriendlyName" = $friendlyName}
		New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation -Tag $tags -Verbose -Force -ErrorAction Stop | Out-Null
		Write-Success "Resource Group Created Successfully."
	}

	else
	{
		Write-Error "Ed-Fi ODS instance with name '$friendlyName' already exists.  If you wish to re-install, you must remove the old installation of the Ed-Fi ODS manually in the Azure portal by deleting the '$resourceGroupName' Resource Group."
	}

	return $resourceGroupName
}

function Delete-ResourceGroup([string]$resourceGroupName) 
{
	$resourceGroupExists = Assert-ResourceGroupExists $resourceGroupName -ErrorAction Stop

	if ($resourceGroupExists -eq $false) {
		throw "Unable to locate resource group for deletion"
	}

	Retry-Command -ExponentialBackoff -StatusMessage "Removing resource group '$resourceGroupName'" { Remove-AzureRmResourceGroup -Name $resourceGroupName -Force }
}

function Get-AzureSqlPasswordErrorMessage([PSCredential] $credentials)
{
	<#
	.DESCRIPTION

	Checks that the entered credentials meet Microsoft's SQL Server Strong Password Requirements
	See: https://support.microsoft.com/en-us/kb/965823

	If a password does not meet complexity requirements, an error message is returned indicating what exactly is missing
	#>

	$plaintextPassword = [string] (SecureString-ToPlainText $credentials.Password)
	$messages = @()

	if ($plaintextPassword.Length -lt 8) { $messages += "Your password must be at least 8 characters long" }
	if ($plaintextPassword.ToLower() -match $credentials.Username.ToLower()) { $messages += "Your password may not contain your username" }
	if ($plaintextPassword -match "`"")
	{
		$messages += "Your password may not contain double quotes (`")"
	}

	if ((Get-PasswordCharacterCategoryCount $credentials.Password) -lt 3)
	{
		$messages += "Your password must contain characters from at least three of the following categories:"
		$messages += "    -English uppercase characters (A through Z)"
		$messages += "    -English lowercase characters (a through z)"
		$messages += "    -Base 10 digits (0 through 9)"
		$messages += "    -All Nonalphabetic characters except double quotes (for example: !, $, #, % but not `")"
	}

	return $messages
}

function Get-BooleanFromConsolePrompt([string]$message)
{
	$input = 0
	$yesRegex = '^[Yy][Ee]?[Ss]?$'
	$noRegex = '^[Nn][Oo]?$'
	while (-not (($input -match $yesRegex) -or ($input -match $noRegex))) {
		$input = Read-Host -Prompt "$message [Y/n]"
		if (!$input) 
		{
			break;
		}
	}	
	if ($input -match $yesRegex) {
		return $true
	}
	return $false
}

function Get-CloudOdsResourceGroup($friendlyName)
{
	$resourceGroupName = Get-ResourceGroupName $friendlyName
	$group = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction Silently

	if ($group -eq $null)
	{
		Write-Error "Can't find existing Ed-Fi ODS named '$friendlyName' in your account"
	}

	return $group
}

function Get-CloudOdsVersion($friendlyName)
{
	$resourceGroup = Get-CloudOdsResourceGroup $friendlyName

	if ($resourceGroup.Tags -eq $null -or -not $resourceGroup.Tags.ContainsKey("Cloud-Ods-Version"))
	{
		Write-Error "Can't find current version for Ed-Fi ODS named '$friendlyName'"
	}

	$textVersion = $resourceGroup.Tags["Cloud-Ods-Version"]
	return [Version]$textVersion
}

function Get-CredentialAsPlainText([PSCredential] $credentials)
{
	return @{
		UserName = $credentials.UserName
		Password = (SecureString-ToPlainText $credentials.Password)
	}
}

function Get-CredentialFromConsole($prompt, $defaultUserName)
{
	if ($prompt) {
		Write-Host
		Write-Host $prompt
		Write-Host
	}	

	if ($defaultUserName) {
		$username = Read-Host -Prompt "Username [$defaultUserName]"
		if (!$username) {
			$username = $defaultUserName
		}
	} else {
		do {
			$username = Read-Host -Prompt "Username"
		} while (!$username)		
	}

	$passwordMatch = $false
	do {
		$password = Read-Host -Prompt "Password" -AsSecureString
		$confirmPassword = Read-Host -Prompt "Confirm Password" -AsSecureString

		if (SecureString-Equals $password $confirmPassword) {
			$passwordMatch = $true
		} else {			
			Write-Host "Passwords don't match"
		}
	} while (-not $passwordMatch)
	

	$credential = New-Object System.Management.Automation.PSCredential($username, $password)	
	return $credential
}

function Get-CloudOdsAvailableVersions($edition)
{
	$availableVersions = @()
	$availableVersionsUrl = "$OdsAssetsStorageBaseUrl/$edition/AzureDeploy$AzureDeployScriptsCurrentVersion/AvailableVersions.txt"
	try
	{
		# This is intentionally using .Net to do the request instead of Invoke-WebRequest due to encoding issues
		$client = New-Object System.Net.WebClient;
		Write-Verbose "Attempting download of existing available versions from $availableVersionsUrl"
		$textVersions = $client.DownloadString($availableVersionsUrl)
		Write-Verbose "Received:"
		Write-Verbose $textVersions
		$availableVersions = [Version[]]$textVersions.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
	}
	catch
	{
		Write-Verbose "Exception while downloading existing AvailableVersions file from $availableVersionsUrl"
		Write-Verbose $_.Exception
	}
	return $availableVersions
}

function Select-CloudOdsVersionToDeploy($edition)
{
	$availableVersions = Get-CloudOdsAvailableVersions $edition

	if (-not $availableVersions -or $availableVersions.length -lt 1)
	{
		Write-Error "Error retrieving available versions information for '$edition' edition - please check that this is a valid Cloud ODS edition"
		return;
	}

	$choice = -1

	while ($choice -eq -1)
	{
		Write-Host "Please choose which Cloud Ods Version to deploy."

		$count = 1;
		# Sort available versions descending so the latest is at the top
		$availableVersions = $availableVersions | Sort-Object -Descending
		foreach ($availableVersion in $availableVersions)
		{
			$versionLabel = $availableVersion
			# Assuming the first one is the latest based on our prior sort
			if ($count -eq 1)
			{
				$versionLabel = "$versionLabel (Latest)"
			}
			Write-Host "[$count]: $versionLabel"
			$count++;
		}

		$input = Read-Host -Prompt "Cloud Ods Version"

		if ([int32]::TryParse($input, [ref]$choice) -and $choice -gt 0 -and $choice -le $availableVersions.length)
		{
			$selectedVersion = $availableVersions[$choice-1]
			Write-Host "Using Cloud Ods Version ($selectedVersion)"
			return $selectedVersion
		}
		else
		{
			$choice = -1;
		}
	}
}

function Get-PasswordCharacterCategoryCount([securestring] $securePassword)
{
	$plaintextPassword = (SecureString-ToPlainText $securePassword)
	$typesOfCharactersFound = 0

	#Contains at least one english lowercase character (a through z)
	if ($plaintextPassword -cmatch "[a-z]") { $typesOfCharactersFound++ }

	#Contains at least one english uppercase character (A through Z)
	if ($plaintextPassword -cmatch "[A-Z]") { $typesOfCharactersFound++ }

	#Contains at least one digit (0 through 9)
	if ($plaintextPassword -match "[0-9]") { $typesOfCharactersFound++ }

	#Contains at least one Nonalphabetic character
	if ($plaintextPassword -match "_|[^\w]") { $typesOfCharactersFound++ }

	return $typesOfCharactersFound
}

function Get-RandomId([int]$length = 13)
{
	$ascii = "abcdefghijklmnopqrstuvwxyz0123456789";	
	return Get-RandomString $ascii $length
}

function Get-RandomString([string] $alphabet, [int]$length)
{
	$charArray = $alphabet.ToCharArray();
	
	$result = ""
	for ($i = 1; $i -le $length; $i++)
	{
		$result += ($charArray | Get-Random)
	}

	return $result
}

function Get-ResourceGroupName([string]$friendlyName)
{
	$friendlyName = $friendlyName -replace '\s', '_'	
	return $friendlyName.ToLowerInvariant()
}

function Get-ResourceGroupLocationsInTheUS()
{
	return (Get-AzureRmLocation | Where { $_.DisplayName -clike "*US*" }).DisplayName
}

function Get-NearestAppInsightsLocation([string]$selectedLocation)
{
	$supportedLocations = "East US", "South Central US"
	if ($supportedLocations -contains $selectedLocation) {
		return $selectedLocation
	} else {
		return "South Central US"
	}    
}

function Get-SqlUsernameErrorMessage([PSCredential] $credentials)
{
	$username = $credentials.UserName
	$messages = @()
	if ($username -match "[`"|:*?\\/#&;,%=]") { $messages += "Your username may not contain the following characters: `"|:*?\\/#&;,%=" }
	if ($username -match "\s") { $messages += "Your username may not contain spaces, tabs, or any other whitespace characters" }
	if ($username -match "^[0123456789@$+]") { $messages += "Your username may not begin with a digit (0-9), @, $, or +" }

	$invalidUsernamesFile = (Join-Path $PSScriptRoot 'invalid_usernames.txt')
	if (Test-Path $invalidUsernamesFile)
	{
		$usernameIsReserved = (Select-String $invalidUsernamesFile -pattern ("^" + $username.ToLower() + "$"))
		if ($usernameIsReserved)
		{
			$messages += "Your username may not be a reserved system name (eg: admin, administrator, root, dbo, public, etc)"
		}
	}

	return $messages
}

function Get-ValidatedCredentials($title, $messageBody, $usernameValidatorFunctionName, $passwordValidatorFunctionName)
{
	if ($usernameValidatorFunctionName -ne $null) {
		$validateUsername = (Get-Item -LiteralPath "function:$usernameValidatorFunctionName").ScriptBlock
	}
	if ($passwordValidatorFunctionName -ne $null) {
		$validatePassword = (Get-Item -LiteralPath "function:$passwordValidatorFunctionName").ScriptBlock
	}

	Do {	
		$credentials = Get-CredentialFromConsole $messageBody
		$errorMessages = @()
		
		if ($usernameValidatorFunctionName -ne $null) {
			$errorMessages += $validateUsername.Invoke($credentials)
		}
		if ($passwordValidatorFunctionName -ne $null) {
			$errorMessages += $validatePassword.Invoke($credentials)
		}
		$messageBody = [string]::Join(([environment]::NewLine), $errorMessages)
	} While ($errorMessages.Length -gt 0)

	return $credentials
}

function Login-AzureAccount()
{
	$loggedIn = $true;
	
	try
	{
		$context = Get-AzureRmContext -ErrorAction SilentlyContinue
		$subscription = Get-AzureRmSubscription -ErrorAction SilentlyContinue
		$loggedIn = (($context -ne $null) -and ($subscription -ne $null));
	}

	catch
	{
		$loggedIn = $false
	}	

	if (-not $loggedIn)
	{
		Login-AzureRmAccount -ErrorAction Stop
	}

	Select-Subscription		
}
function Remove-ResourceGroupTag([string] $friendlyName, [string] $oldTagNameToRemove) {
	$resourceGroupName = Get-ResourceGroupName $friendlyName
	$tags = (Get-AzureRmResourceGroup -Name $resourceGroupName).Tags

	if (($tags) -and ($tags.ContainsKey($oldTagNameToRemove))) {
		$tags.Remove($oldTagNameToRemove) 
	}
	
	$result = Set-AzureRmResourceGroup -Tag $tags -Name $resourceGroupName
	return $result
}
function Retry-Command
{
	[CmdletBinding()]
	param 
	(
		[Parameter(ValueFromPipeline,Mandatory)] $Command,
		[Parameter(Mandatory=$false)][string] $StatusMessage,
		[Parameter(Mandatory=$false)][int]$Retries = 5, 
		[Parameter(Mandatory=$false)][int]$SecondsDelay = 2,
		[Parameter(Mandatory=$false)][switch]$ExponentialBackoff
	)
		
	$retryCount = 0
	$success = $false

	while (-not $success) 
	{
		try 
		{
			if ($StatusMessage) 
			{
				if ($retryCount -gt 0) 
				{
					Write-Host "$StatusMessage (Retry $retryCount)"
				}

				else 
				{
					Write-Host $StatusMessage
				}				
			}

			$result = & $Command -ErrorAction SilentlyContinue -ErrorVariable ProcessError 2>$null
			if ($ProcessError)
			{
				throw $ProcessError
			}

			return $result
		} 
		catch 
		{
			if ($retryCount -ge $Retries) 
			{
				throw
			} 
			else 
			{
				$exceptionMessage = $_.Exception.Message
				Write-Verbose "Failed.  Will retry automatically in $SecondsDelay seconds. Details: $exceptionMessage"
				Start-Sleep $SecondsDelay
				$retryCount++

				if ($ExponentialBackoff)
				{
					$secondsDelay *= 2;
				}
			}
		}
	}
}

function SecureString-ToPlainText([securestring] $value)
{
	$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
	$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

	return $PlainPassword
}

function SecureString-Equals([securestring] $value1, [securestring] $value2)
{
	return ((SecureString-ToPlainText $value1) -eq (SecureString-ToPlainText $value2))
}

function Select-ResourceGroupLocation()
{
	$locations = Get-ResourceGroupLocationsInTheUS
	$choice = -1

	if ($locations.length -gt 1)
	{
		while ($choice -eq -1)
		{
			Write-Host "Please choose which Azure datacenter to which you'd like to deploy.  You should try and use a region near you for optimal performance."

			$count = 1;
			foreach ($location in $locations)
			{
				Write-Host "[$count]: $location"
				$count++;
			}

			$input = Read-Host -Prompt "Resource Group Location"

			if ([int32]::TryParse($input, [ref]$choice))
			{
				if ($choice -gt 0 -and $choice -le $locations.length)
				{
					$selectedLocation = $locations[$choice-1]
					Write-Host "Using Resource Group Location ($selectedLocation)"
					return $selectedLocation
				}

				else
				{
					$choice = -1;
				}
			}

			else
			{
				$choice = -1;
			}
		}
	}
}

function Select-Subscription()
{
	$subscriptions = Get-AzureRmSubscription
	$choice = -1

	if ($subscriptions.length -gt 1)
	{
		while ($choice -eq -1)
		{
			Write-Host "Please choose which subscription to which you'd like to deploy:"

			$count = 1;
			foreach ($subscription in $subscriptions)
			{
				Write-Host "[$count]: $($subscription.Name) - $($subscription.Id)"
				$count++;
			}

			$input = Read-Host -Prompt "Subscription"

			if ([int32]::TryParse($input, [ref]$choice))
			{
				if ($choice -gt 0 -and $choice -le $subscriptions.length)
				{
					$choice -= 1;
				}

				else
				{
					$choice = -1;
				}
			}

			else
			{
				$choice = -1;
			}
		}	
	}

	Write-Host "Using Subscription $($subscriptions[$choice].Name) - $($subscriptions[$choice].Id)"
	Select-AzureRmSubscription -SubscriptionId $subscriptions[$choice].Id
}

function Warmup-Website([string]$url)
{
	if (-not $url) { return; }
	Start-Job { Invoke-WebRequest $using:url } | Out-Null
}

function Validate-UserIsAzureGlobalAdmin()
{
	$loginId = (Get-AzureRMContext).Account.Id
	$adminUserRoles = Get-AzureRMRoleAssignment -RoleDefinitionName "ServiceAdministrator" -IncludeClassicAdministrators | where { $_.SignInName -eq $loginId -and $_.RoleDefinitionName.Contains("ServiceAdministrator") }

	if ($adminUserRoles -eq $null)
	{
		Write-Error "This account is not the Global Admin of the Azure Subscription specified.  This script must be run as the Global Admin."
	}
}

function Validate-VersionAndEdition([string] $versionNumber, [string] $edition)
{
	# Verify the version is supported by this version of the deployment scripts
	$availableVersions = Get-CloudOdsAvailableVersions $edition
	if ( -not $availableVersions -contains ([Version]$versionNumber))
	{
		Write-Error "Ed-Fi ODS $edition/$versionNumber is not supported on this version of the Azure deployment scripts."
		Write-Error "Supported Version:"
		Write-Error $availableVersions
		return
	}

	try
	{
		$context = New-AzureStorageContext -StorageAccountName $OdsAssetsStorageAccountName -Anonymous
		$blobs = Get-AzureStorageBlob -Context $context -Container "public" -Prefix "CloudOds/deploy/$edition/$versionNumber/"
	}

	catch
	{
	}
	
	if ($blobs -eq $null)
	{
		Write-Error "Could not find installation artifacts for Ed-Fi ODS $edition/$versionNumber -- please verify your version number is correct.";
	}
}

function Write-Warning($message)
{
	Write-Host $message -ForegroundColor Yellow
}

function Write-Success($message = "Success")
{
	Write-Host $message -ForegroundColor Green
}

function Write-Error($message, $quitScript = $true)
{
	Write-Host "*** Error ***" -ForegroundColor Red
	Write-Host $message -ForegroundColor Red
	Write-Host "*************" -ForegroundColor Red

	if ($quitScript)
	{
		exit
	}
}

function Get-ExternalIPAddress
{
    return Invoke-RestMethod http://ipinfo.io/json | Select -exp ip
}
