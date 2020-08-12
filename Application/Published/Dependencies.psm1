# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

function Use-Module
{
	[CmdletBinding()]
	param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string] $ModuleName,
		
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [version] $ModuleVersion
	)
	process {
		Write-Debug "Trying to import module $ModuleName v$ModuleVersion"
	
		$loadedModule = Get-Module -Name $ModuleName
		if ($loadedModule)
		{
			Write-Debug "Found module $ModuleName already loaded"
			Write-Debug ($loadedModule | Format-Table | Out-String)
			
			if ($loadedModule -is [system.array])
			{
				$msg = @"
	Multiple versions of Module $ModuleName are already loaded, but this script requires v$ModuleVersion.

	If you have further trouble with this script, try restarting your PowerShell session and running this script again.

"@
				
				Write-Warning $msg
				Remove-Module $ModuleName
			}
			
			elseif ($loadedModule.Version -ne $ModuleVersion)
			{
				$msg = @"
	Module $ModuleName v$($loadedModule.Version) is already loaded, but this script requires $ModuleVersion.

	If you have further trouble with this script, try restarting your PowerShell session and running this script again.

"@
				Write-Warning $msg
				Remove-Module $ModuleName
			}
			
			else
			{
				Write-Debug "Correct version already loaded"
				return; #module with correct version is already loaded
			}			
		}
		
		Write-Debug "Module $ModuleName not yet loaded"
		
		$allModuleVersions = Get-Module -Name $ModuleName -Refresh -ListAvailable
		$moduleWithDifferentMinorVersion = $allModuleVersions | where { $_.Version.Major -eq $ModuleVersion.Major -and $_.Version.Minor -ne $ModuleVersion.Minor }

		$module =  $allModuleVersions | where { $_.Version -eq $ModuleVersion }
		if (-not $module)
		{
			$allowClobber = if ($moduleWithDifferentMinorVersion) {"-AllowClobber`r`n`r`nNote: Running the above command will replace your existing $ModuleName v$($moduleWithDifferentMinorVersion.Version)"} else {""}

			$msg = @"
	Module $ModuleName v$ModuleVersion is not installed on this system.
	You may be able to install by running the following command:

	Install-Module -Name $ModuleName -RequiredVersion "$ModuleVersion" $allowClobber

"@
			Write-Host $msg -ForegroundColor Red
			break
		}
		
		Write-Debug "Loading module $ModuleName v$ModuleVersion"
		Import-Module -Name $ModuleName -RequiredVersion $ModuleVersion	
	}	
}
