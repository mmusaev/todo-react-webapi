$ErrorActionPreference = "Continue"
$root = "c:\dev2\todo-app"
$rg = "rg-auth-msentra"
$apiId = "c926a415-afd9-41de-9e06-2c6b335db515"
$spaId = "a3445dba-2ef5-4672-90d4-d75bd8594f12"

# Admin consent for SPA -> API delegated scope
az ad app permission admin-consent --id $spaId 2>$null

# Assign signed-in user the Admin role
$userId = az ad signed-in-user show --query id -o tsv 2>$null
$spId = az ad sp show --id $apiId --query id -o tsv 2>$null
$adminRole = az ad app show --id $apiId --query "appRoles[?value=='Admin'].id | [0]" -o tsv 2>$null
az rest --method POST --uri "https://graph.microsoft.com/v1.0/users/$userId/appRoleAssignments" --headers "Content-Type=application/json" --body (@{ principalId = $userId; resourceId = $spId; appRoleId = $adminRole } | ConvertTo-Json -Compress).Replace('"', '\"') 2>$null

# API
dotnet publish "$root\api" -c Release -o "$root\api\publish" -nologo -v q
Compress-Archive "$root\api\publish\*" "$root\api.zip" -Force
az webapp deploy -g $rg -n todo-api-mm2026 --src-path "$root\api.zip" --type zip 2>$null

# Web
az webapp config set -g $rg -n todo-web-mm2026 --startup-file "pm2 serve /home/site/wwwroot --no-daemon --spa" 2>$null | Out-Null
# Compress-Archive writes backslash paths that break assets on Linux; tar writes forward slashes
Remove-Item "$root\web.zip" -ErrorAction SilentlyContinue
tar -a -cf "$root\web.zip" -C "$root\client\dist" .
az webapp deploy -g $rg -n todo-web-mm2026 --src-path "$root\web.zip" --type zip 2>$null
Remove-Item "$root\api.zip", "$root\web.zip", "$root\api\publish" -Recurse -Force
