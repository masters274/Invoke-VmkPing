$scriptPath = "$PSScriptRoot\Invoke-VmkPing.ps1"

Import-Module -Name VMWare.PowerCLI -Scope currentuser -Force

Publish-Script -Path $scriptPath -NuGetApiKey $Env:APIKEY