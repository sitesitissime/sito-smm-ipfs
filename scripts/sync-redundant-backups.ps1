$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot

$branch = (git branch --show-current).Trim()
if (-not $branch) { throw 'Branch Git non rilevato.' }
git push origin $branch
if ($LASTEXITCODE -ne 0) { throw 'Push GitHub fallito.' }

if (-not (git remote get-url gitlab 2>$null)) { throw 'Remote GitLab non configurato.' }
git push gitlab $branch
if ($LASTEXITCODE -ne 0) { throw 'Push GitLab fallito.' }

& (Join-Path $PSScriptRoot 'deploy-pinata.ps1')

