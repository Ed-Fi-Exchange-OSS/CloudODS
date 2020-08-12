# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

function Get-AzureRmWebAppPublishingCredentials($resourceGroupName, $webAppName, $slotName = $null)
{
	if ([string]::IsNullOrWhiteSpace($slotName))
    {
		$resourceType = "Microsoft.Web/sites/config"
		$resourceName = "$webAppName/publishingcredentials"
	}
    else
    {
		$resourceType = "Microsoft.Web/sites/slots/config"
		$resourceName = "$webAppName/$slotName/publishingcredentials"
	}
	$publishingCredentials = Invoke-AzureRmResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName -Action list -ApiVersion 2015-08-01 -Force
    return $publishingCredentials
}

function Get-KuduApiAuthorisationHeaderValue($resourceGroupName, $webAppName, $slotName = $null)
{
    $publishingCredentials = Get-AzureRmWebAppPublishingCredentials $resourceGroupName $webAppName $slotName
    return ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $publishingCredentials.Properties.PublishingUserName, $publishingCredentials.Properties.PublishingPassword))))
}

function Download-FileFromWebApp($resourceGroupName, $webAppName, $slotName = "", $kuduPath, $localPath)
{
    $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $webAppName $slotName
    if ($slotName -eq "")
    {
        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    else
    {
        $kuduApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")
    Write-Host "Downloading File from WebApp. Source: '$virtualPath'. Target: '$localPath'..." -ForegroundColor DarkGray

    Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method GET `
                        -OutFile $localPath `
                        -ContentType "multipart/form-data"
}

function Get-DirectoryFromWebApp($resourceGroupName, $webAppName, $slotName = "", $kuduPath = "")
{
    $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $webAppName $slotName
    if ($slotName -eq "")
    {
        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    else
    {
        $kuduApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")
    Write-Host "Retrieving directory content from WebApp. Source: '$virtualPath'..." -ForegroundColor DarkGray

    $filesList = Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method GET `
                        -ContentType "application/json"

    return $filesList;
}

function Upload-FileToWebApp($resourceGroupName, $webAppName, $slotName = "", $localPath, $kuduPath)
{
    $kuduApiAuthorisationToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $webAppName $slotName
    if ($slotName -eq "")
    {
        $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    else
    {
        $kuduApiUrl = "https://$webAppName`-$slotName.scm.azurewebsites.net/api/vfs/site/wwwroot/$kuduPath"
    }
    $virtualPath = $kuduApiUrl.Replace(".scm.azurewebsites.", ".azurewebsites.").Replace("/api/vfs/site/wwwroot", "")
    Write-Host "Uploading File to WebApp. Source: '$localPath'. Target: '$virtualPath'..." -ForegroundColor DarkGray

    Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method PUT `
                        -InFile $localPath `
                        -ContentType "multipart/form-data"
}
