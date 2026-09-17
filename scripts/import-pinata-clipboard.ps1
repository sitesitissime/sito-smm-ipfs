$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $projectRoot '.local\secrets'
$clipboard = Get-Clipboard -Raw
$match = [regex]::Match($clipboard, 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
$temporaryPath = Join-Path $projectRoot '.local\pinata-copy.tmp'
if (-not $match.Success -and (Test-Path -LiteralPath $temporaryPath)) {
  $temporary = Get-Content -Raw -LiteralPath $temporaryPath
  $match = [regex]::Match($temporary, 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
}
if (-not $match.Success) { throw 'JWT Pinata non trovato.' }
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$secure = ConvertTo-SecureString $match.Value -AsPlainText -Force
$protected = $secure | ConvertFrom-SecureString
[IO.File]::WriteAllText((Join-Path $secretDir 'pinata-jwt.dpapi'), $protected, [Text.UTF8Encoding]::new($false))
if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
$clipboard = $null
$temporary = $null
Write-Host 'JWT Pinata salvato localmente con Windows DPAPI.'
