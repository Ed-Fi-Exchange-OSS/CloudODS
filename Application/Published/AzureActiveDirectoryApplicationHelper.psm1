<#
MIT License

Copyright (c) 2016 wangzq

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#

Methods below adapted from https://github.com/wangzq/Azure-PowerShell-Extensions

#>

Import-Module $PSScriptRoot\Dependencies.psm1 -Force -DisableNameChecking
Use-Module "AzureRM" "4.3.1"
Use-Module "AzureRM.profile" "3.3.1"

$script:profile = $null
function GetProfile([switch] $Reset) {
    if (!$script:profile -OR $Reset) {
        $script:profile = Get-AzureExProfile -DecodeTokenCache
    }
    $script:profile
}

# ensure the url ends with '/', useful when comparing two urls that one might be misssing the ending slash
filter NormalizeUrl{
    param (
        [Parameter(ValueFromPipeline=$true)]
        [string] $url
    )
    if ($url -and !$url.EndsWith('/')){
        $url + '/'
    } else {
        $url
    }
}

function ConvertFrom-AdalTokenCacheBase64
{
    <#
    .Synopsis
        This cmdlet will deserialize from a base64 encoded ADAL token cache.
    .Example
        PS> ConvertFrom-AdalTokenCacheBase64 $base64
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $TokenCacheBase64Encoded
        )
    process {
        $bytes = [Convert]::FromBase64String($TokenCacheBase64Encoded)
        $tokenCache = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.TokenCache(@(,$bytes))
        $tokenCache.ReadItems()
    }
}

function Get-AzureExAdApplicationOauth2Permission
{
    <#
    .Synopsis
        Returns some well-known RequiredResourceAccess objects.
    .Example
        PS> Get-AzureExAdApplicationOauth2Permission AadSigninAndReadUserProfile
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('AadSigninAndReadUserProfile','ArmAccessAsUser')]
        [string] $Name
        )
    switch ($Name) {
        'AadSigninAndReadUserProfile' {
            New-AzureExAdRequiredResourceAccess -ApplicationId '00000002-0000-0000-c000-000000000000' -PermissionId '311a71cc-e848-46a1-bdf8-97ff7156d8e6'
        }
        'ArmAccessAsUser' {
            New-AzureExAdRequiredResourceAccess -ApplicationId '797f4846-ba00-4fd7-ba43-dac1f8f63013' -PermissionId '41094075-9dad-400e-a0bd-54e686782033'
        }
    }
}

function Get-AzureExGraphAccessToken
{
    <#
    .Synopsis
        This cmdlet will re-use the existing AzureRM powershell cmdlets to get a valid AccessToken to access Graph API for the specified tenant (id).
    .Example
        PS> Get-AzureExGraphAccessToken
    #>
    [CmdletBinding()]
    param (
        # If not specified then uses current azure subscription's default tenant id
        [string] $TenantId
        )

    function GetTokenCacheByTenantResource($tokenCaches, $tenantId, $resource) {
        $resource = $resource.TrimEnd('/')
        foreach($tokenCache in $tokenCaches) {
            $r = $tokenCache.Resource.TrimEnd('/')
            if ($r -eq $resource) {
                $a = $tokenCache.Authority.TrimEnd('/')
                if ($a.EndsWith($tenantId, 'OrdinalIgnoreCase')) {
                    return $tokenCache
                }
            }
        }
    }

    for ($i = 0; $i -lt 2; $i++) {
        $p = GetProfile

        $resource = $p.Contexts.Default.Environment.GraphEndpointResourceId
        if (!$resource) { throw "Unable to get graph api endpoint from AzureRM profile" }
        
        if (!$TenantId) { 
            $TenantId = $p.Contexts.Default.Tenant.Id 
            if (!$TenantId) { throw "Unable to get tenant id from AzureRM profile" }
        }

        [array] $tokenCaches = $p.Contexts.Default.TokenCache.CacheData

        $tokenCache = GetTokenCacheByTenantResource $tokenCaches $TenantId $Resource

        $reason = $null
        if (!$tokenCache) { $reason = "No Graph API access token yet" }
        elseif ($tokenCache.ExpiresOn -le (Get-Date)) { $reason = "Token cache expired" }

        if ($reason) {
            Write-Warning "$reason for tenant $TenantId, will retry after refreshing token"  
            Get-AzureRmAdApplication -IdentifierUri ([Guid]::NewGuid())
            GetProfile -Reset | Out-Null
        } else {
            if (!$tokenCache.AccessToken) {
                throw "Invalid AccessToken for the found token cache entry matching tenant $TenantId and resource $resource" 
            }
            Write-Verbose "Found valid access token which will expire at $($tokenCache.ExpiresOn.ToLocalTime())"
            return $tokenCache.AccessToken
        }
    }

    throw "Unable to get access token for Graph API for Tenant $TenantId"
}


function Get-AzureExProfile
{
    <#
    .Synopsis
        Save-AzureRmContext currently (1.5.0) only persists the profile to a file, this helper script
        will use a temporary file to save it, then return the deserialized json object and delete 
        the temporary file.

        If you specify optional switch `-DecodeTokenCache` then it will also deserialize the base64 encoded token caches.
    .Example
        PS> Get-AzureExProfile 
    #>
    [CmdletBinding()]
    param (
        [switch] $DecodeTokenCache
    )
    
    $tempfile = [IO.Path]::GetTempFileName()
    Remove-Item $tempfile #prevent prompt to overwrite file by deleting the temp file
	
	Save-AzureRmContext -Path $tempfile
    
    $result = ConvertFrom-Json (Get-Content $tempfile -Raw)
    Remove-Item $tempfile

    if ($DecodeTokenCache) {
        $result.Contexts.Default.TokenCache.CacheData = $result.Contexts.Default.TokenCache.CacheData | ConvertFrom-AdalTokenCacheBase64
    }

    $result
}


function Invoke-AzureExGraphAPI
{
    <#
    .Synopsis
        Invokes AAD Graph REST API.
    .Example
        PS> Invoke-AzureExGraphAPI tenantDetails
        PS> Invoke-AzureExGraphAPI me
    .Example
        PS> Invoke-AzureExGraphAPI 'applications?$filter=...'
    .Link
        https://msdn.microsoft.com/en-us/library/azure/ad/graph/api/api-catalog
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $RelativeUrl,

        # If not specified then uses the current azure subscription's default tenant id
        [string] $TenantId,

        [string] $Method,

        $Body,

        [string] $ApiVersion = '1.6'
        )
    $p = GetProfile
    $graphUrl = $p.Contexts.Default.Environment.GraphEndpointResourceId | NormalizeUrl
    if (!$TenantId) { 
        $TenantId = $p.Contexts.Default.Tenant.Id 
        if (!$TenantId) { throw 'Unable to get tenant id from AzureRM profile' }
    }
    
    $accessToken = Get-AzureExGraphAccessToken $TenantId
    if ($RelativeUrl -match '\?') {
        $RelativeUrl = $RelativeUrl.Replace('?', "?api-version=$ApiVersion&")
    } else {
        $RelativeUrl = $RelativeUrl + "?api-version=$ApiVersion"
    }
    $headers = @{
        Authorization = "Bearer $accessToken"
    }
    $p = @{
        Uri = "${graphUrl}$TenantId/$RelativeUrl"
        Headers = $headers
    }
    if ($Method -and $Method -ne 'GET') { 
        $p.Method = $Method 
        $p.ContentType = 'application/json'
        if (!$Body) { throw "Must provide Body if not using GET" }
        if ($Body -isnot 'string') {
            $Body = ConvertTo-Json $Body -Depth 99
        }
        Write-Verbose $Body
        $p.Body = $Body
    }

    Invoke-RestMethod @p
}

function New-AzureCloudOdsAdApplication
{    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $DisplayName,

        [Parameter(Mandatory=$true)]
        [string[]] $ReplyUrls,

        [string] $HomePage,

        [string[]] $IdentifierUris,

        [string[]] $AppSecrets,

        [int] $AppYears = 2,

        [string] $TenantId
        )
    $ErrorActionPreference = 'Stop'

    $app = @{
        displayName = $DisplayName
    }
    if ($HomePage) { $app.homepage = $HomePage }
    if ($IdentifierUris) { $app.identifierUris = $IdentifierUris } 
    else { 
        $app.publicClient = $true 
    }
    if ($ReplyUrls) { $app.replyUrls = $ReplyUrls }
    $app.requiredResourceAccess = @((Get-AzureExAdApplicationOauth2Permission AadSigninAndReadUserProfile), (Get-AzureExAdApplicationOauth2Permission ArmAccessAsUser))
    if ($AppSecrets) {
        [array] $app.passwordCredentials = $AppSecrets | % {
            New-AzureExAdPasswordCredential $_ $AppYears
        }
    }        

    $app = Invoke-AzureExGraphAPI 'applications' -TenantId $TenantId -Method POST -Body $app

    $sp = @{
        appId = $app.appId
        accountEnabled = $true
        tags = @('WindowsAzureActiveDirectoryIntegratedApp')
    }
    $sp = Invoke-AzureExGraphAPI 'servicePrincipals' -TenantId $TenantId -Method POST -Body $sp

    $result = @{
        "Application" = $app;
        "ServicePrincipal" = $sp;
    };

    $result
}

function New-AzureExAdPasswordCredential
{
    <#
    .Synopsis
        Creates a new PasswordCredential object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Password,

        [int] $Years = 2
        )
    @{
        startDate = (Get-Date).ToString('o')
        endDate = (Get-Date).AddYears($Years).ToString('o')
        value = $Password
    }
}

function New-AzureExAdRequiredResourceAccess
{
    <#
    .Synopsis
        Create a new AAD RequiredResourceAccess object.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $ApplicationId,

        [Parameter(Mandatory=$true)]
        [guid] $PermissionId,

        [string] $PermissionType = 'Scope'
        )
    $resourceAccess = @{
        id = $PermissionId
        type = $PermissionType
    }
    $result = @{
        resourceAppId = $ApplicationId
        resourceAccess = @($resourceAccess)
    }
    $result
}

function Get-AzureCloudOdsAdApplication([string]$displayName) {
	return (Get-AzureRmADApplication -DisplayNameStartWith $displayName) | Where-Object {$_.DisplayName -eq $displayName}
}

function Delete-AzureCloudOdsAdApplication([string]$displayName) {
    $app = Get-AzureCloudOdsAdApplication $displayName
    if ($app -ne $null) {
            Write-Host "Removing application: " $displayName
            Remove-AzureRmADApplication -ObjectId $app.ObjectId -Force
	}
}
