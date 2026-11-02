$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot
$rg = "rg-auth-msentra"
$plan = "asp-auth-msentra"
$apiApp = "todo-api-v2-mm2026"
$webApp = "todo-web-v2-mm2026"
$web = "https://$webApp.azurewebsites.net"
$api = "https://$apiApp.azurewebsites.net"
$tenant = az account show --query tenantId -o tsv

function Invoke-Graph($method, $uri, $obj) {
  $f = New-TemporaryFile
  $obj | ConvertTo-Json -Depth 8 -Compress | Set-Content $f -Encoding ascii
  az rest --method $method --uri $uri --headers "Content-Type=application/json" --body "@$f" | Out-Null
  Remove-Item $f
}

# App registrations
$apiId = az ad app list --display-name todo-api-v2 --query "[0].appId" -o tsv
if (-not $apiId) { $apiId = az ad app create --display-name todo-api-v2 --sign-in-audience AzureADMyOrg --query appId -o tsv }
$apiObj = az ad app show --id $apiId --query id -o tsv
$ids = az ad app show --id $apiId -o json 2>$null | ConvertFrom-Json
$scopeId = $ids.api.oauth2PermissionScopes[0].id
$adminRole = ($ids.appRoles | Where-Object value -eq "Admin").id
$userRole = ($ids.appRoles | Where-Object value -eq "User").id
if (-not $scopeId) { $scopeId = [guid]::NewGuid().ToString() }
if (-not $adminRole) { $adminRole = [guid]::NewGuid().ToString() }
if (-not $userRole) { $userRole = [guid]::NewGuid().ToString() }
Invoke-Graph PATCH "https://graph.microsoft.com/v1.0/applications/$apiObj" @{
  identifierUris = @("api://$apiId")
  api = @{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = @(@{ id = $scopeId; value = "access_as_user"; type = "User"; isEnabled = $true; adminConsentDisplayName = "Access Todo API"; adminConsentDescription = "Access Todo API as the signed-in user"; userConsentDisplayName = "Access Todo API"; userConsentDescription = "Access Todo API on your behalf" }) }
  appRoles = @(
    @{ id = $adminRole; value = "Admin"; displayName = "Admin"; description = "Read and write todos"; allowedMemberTypes = @("User"); isEnabled = $true },
    @{ id = $userRole; value = "User"; displayName = "User"; description = "Read todos"; allowedMemberTypes = @("User"); isEnabled = $true })
}
az ad sp create --id $apiId 2>$null | Out-Null

$spaId = az ad app list --display-name todo-spa-v2 --query "[0].appId" -o tsv
if (-not $spaId) { $spaId = az ad app create --display-name todo-spa-v2 --sign-in-audience AzureADMyOrg --query appId -o tsv }
$spaObj = az ad app show --id $spaId --query id -o tsv
Invoke-Graph PATCH "https://graph.microsoft.com/v1.0/applications/$spaObj" @{
  spa = @{ redirectUris = @("http://localhost:5173", $web) }
  requiredResourceAccess = @(@{ resourceAppId = $apiId; resourceAccess = @(@{ id = $scopeId; type = "Scope" }) })
}
az ad sp create --id $spaId 2>$null | Out-Null
az ad app permission admin-consent --id $spaId 2>$null

# Assign signed-in user the Admin role
$userId = az ad signed-in-user show --query id -o tsv
$spId = az ad sp show --id $apiId --query id -o tsv
Invoke-Graph POST "https://graph.microsoft.com/v1.0/users/$userId/appRoleAssignments" @{ principalId = $userId; resourceId = $spId; appRoleId = $adminRole }

# App Services on the existing plan
az webapp create -g $rg -p $plan -n $apiApp --runtime "DOTNETCORE:10.0" | Out-Null
az webapp create -g $rg -p $plan -n $webApp --runtime "NODE:22-lts" | Out-Null
az webapp config appsettings set -g $rg -n $apiApp --settings `
  "AzureAd__TenantId=$tenant" "AzureAd__ClientId=$apiId" `
  "Cors__AllowedOrigins__0=$web" "Cors__AllowedOrigins__1=http://localhost:5173" | Out-Null
az webapp config set -g $rg -n $webApp --startup-file "pm2 serve /home/site/wwwroot --no-daemon --spa" | Out-Null

# Client env for `vite build --mode v2`
@"
VITE_TENANT_ID=$tenant
VITE_CLIENT_ID=$spaId
VITE_API_CLIENT_ID=$apiId
VITE_API_URL=$api
"@ | Set-Content "$root\client\.env.v2" -Encoding ascii

# Deploy (tar writes forward-slash zip paths, required on Linux)
dotnet publish "$root\api" -c Release -o "$root\api\publish" -nologo -v q
tar -a -cf "$root\api.zip" -C "$root\api\publish" .
az webapp deploy -g $rg -n $apiApp --src-path "$root\api.zip" --type zip | Out-Null

Push-Location "$root\client"; npx vite build --mode v2; Pop-Location
tar -a -cf "$root\web.zip" -C "$root\client\dist" .
az webapp deploy -g $rg -n $webApp --src-path "$root\web.zip" --type zip | Out-Null
Remove-Item "$root\api.zip", "$root\web.zip", "$root\api\publish" -Recurse -Force

"web=$web"
"api=$api"
"apiId=$apiId"
"spaId=$spaId"
