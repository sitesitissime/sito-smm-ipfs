$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $projectRoot '.local\secrets'
$clipboard = Get-Clipboard -Raw
$match = [regex]::Match($clipboard, 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
if (-not $match.Success) { throw 'JWT Pinata non trovato negli appunti.' }
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$secure = ConvertTo-SecureString $match.Value -AsPlainText -Force
$protected = $secure | ConvertFrom-SecureString
[IO.File]::WriteAllText((Join-Path $secretDir 'pinata-jwt.dpapi'), $protected, [Text.UTF8Encoding]::new($false))
$clipboard = $null
Write-Host 'JWT Pinata salvato localmente con Windows DPAPI.'

