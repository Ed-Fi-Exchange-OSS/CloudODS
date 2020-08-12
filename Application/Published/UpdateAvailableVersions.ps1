# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

# Deployment process script for updating AvailableVersions
# Used by Octopus as part of deploy process

# Comment out this $version and uncomment the next several lines to test locally
$version = $OctopusParameters["Octopus.Action[Extract package to local directory].Package.NuGetPackageVersion"]
#$AvailableVersionsUrl = "https://odsassets.blob.core.windows.net/public/CloudOds/deploy/test/AzureDeploy1.2.0/AvailableVersions.txt"
#$AvailableVersionsLocalFilePath = "C:\Cloud\TestOutput\AvailableVersions.txt"
#$version = "3.1.1.344"
$outputFileContents = $version
if ($OverwriteAvailableVersions.ToLowerInvariant() -ne 'true')
{
	Write-Host "AvailableVersions.txt will be merged with current version $version, not replaced"
	try
	{
		# This is intentionally using .Net to do the request instead of Invoke-WebRequest due to encoding issues
		$client = New-Object System.Net.WebClient;
		Write-Host "Attempting download of existing available versions from $AvailableVersionsUrl"
		$textVersions = $client.DownloadString($AvailableVersionsUrl)
		Write-Host "Received:"
		Write-Host $textVersions
		$availableVersions = [Version[]]$textVersions.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
	}
	catch
	{
		Write-Host "Exception while downloading existing AvailableVersions file from $AvailableVersionsUrl"
		Write-Host $_.Exception
	}
	if ($availableVersions -and $availableVersions.length -gt 0)
	{
		if (-not $availableVersions.Contains([Version]$version))
		{
			# Force the single version into an array and add the other versions to ensure the new one is at the top of the file
			Write-Host "Adding version $version to existing available versions"
			$availableVersions = @([Version]$version) + $availableVersions
		}
		else
		{
			Write-Host "Version $version already exists in available versions, no change will be made"
		}
		$outputFileContents = [String]::Join([Environment]::NewLine, $availableVersions)
	}
	else
	{
		Write-Host "No versions found from request to available versions url"
	}
}
Write-Host "Writing temporary available versions file to $AvailableVersionsLocalFilePath"
Write-Host "Contents:"
Write-Host $outputFileContents
[System.IO.File]::WriteAllLines($AvailableVersionsLocalFilePath, $outputFileContents)