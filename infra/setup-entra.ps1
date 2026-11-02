$ErrorActionPreference = "Stop"
$web = "https://todo-web-mm2026.azurewebsites.net"
$ErrorActionPreference = "Continue"
$apiId = az ad app list --display-name todo-api --query "[0].appId" -o tsv 2>$null
if (-not $apiId) { $apiId = az ad app create --display-name todo-api --sign-in-audience AzureADMyOrg --query appId -o tsv 2>$null }
$apiObj = az ad app show --id $apiId --query id -o tsv 2>$null
$scopeId = [guid]::NewGuid().ToString(); $adminRole = [guid]::NewGuid().ToString(); $userRole = [guid]::NewGuid().ToString()
$body = @{
  identifierUris = @("api://$apiId")
  api = @{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = @(@{ id = $scopeId; value = "access_as_user"; type = "User"; isEnabled = $true; adminConsentDisplayName = "Access Todo API"; adminConsentDescription = "Access Todo API as the signed-in user"; userConsentDisplayName = "Access Todo API"; userConsentDescription = "Access Todo API on your behalf" }) }
  appRoles = @(
    @{ id = $adminRole; value = "Admin"; displayName = "Admin"; description = "Full CRUD on todos"; allowedMemberTypes = @("User"); isEnabled = $true },
    @{ id = $userRole; value = "User"; displayName = "User"; description = "Read todos"; allowedMemberTypes = @("User"); isEnabled = $true })
} | ConvertTo-Json -Depth 6 -Compress
$f = Join-Path $env:TEMP "api.json"; $body | Set-Content $f -Encoding ascii
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$apiObj" --headers "Content-Type=application/json" --body "@$f" 2>$null
az ad sp create --id $apiId 2>$null | Out-Null

$spaId = az ad app list --display-name todo-spa --query "[0].appId" -o tsv 2>$null
if (-not $spaId) { $spaId = az ad app create --display-name todo-spa --sign-in-audience AzureADMyOrg --query appId -o tsv 2>$null }
$spaObj = az ad app show --id $spaId --query id -o tsv 2>$null
$spa = @{ spa = @{ redirectUris = @("http://localhost:5173", $web) }; requiredResourceAccess = @(@{ resourceAppId = $apiId; resourceAccess = @(@{ id = $scopeId; type = "Scope" }) }) } | ConvertTo-Json -Depth 6 -Compress
$g = Join-Path $env:TEMP "spa.json"; $spa | Set-Content $g -Encoding ascii
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$spaObj" --headers "Content-Type=application/json" --body "@$g" 2>$null
az ad sp create --id $spaId 2>$null | Out-Null
Remove-Item $f, $g
"apiId=$apiId"
"spaId=$spaId"
