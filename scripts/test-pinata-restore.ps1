[CmdletBinding()]
param(
  [switch]$DownloadFromPinata,
  [string]$GatewayBase = 'https://aqua-rational-penguin-314.mypinata.cloud/ipfs'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$reportPath = Join-Path $projectRoot 'deploy-reports\pinata-latest.json'
$secretPath = Join-Path $projectRoot '.local\secrets\backup-password.dpapi'
$testRoot = Join-Path $projectRoot ('.local\restore-test-' + [guid]::NewGuid().ToString('N'))
$sevenZip = @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $sevenZip) { throw '7-Zip non trovato.' }
if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Rapporto Pinata assente.' }
if (-not (Test-Path -LiteralPath $secretPath)) { throw 'Password backup locale assente.' }

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$secure = (Get-Content -Raw -LiteralPath $secretPath).Trim() | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
  $archive = Join-Path $projectRoot "backups\encrypted\$($report.archive)"
  if ($DownloadFromPinata) {
    $archive = Join-Path $testRoot $report.archive
    Invoke-WebRequest -Uri "$($GatewayBase.TrimEnd('/'))/$($report.cid)" -OutFile $archive
  }
  if (-not (Test-Path -LiteralPath $archive)) { throw "Archivio non trovato: $archive" }
  $actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
  if ($actualSha -ne $report.sha256) { throw 'SHA-256 archivio non corrispondente.' }

  $extractPath = Join-Path $testRoot 'extracted'
  New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
  & $sevenZip x -y "-p$password" "-o$extractPath" $archive | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Decrittazione archivio fallita.' }
  $bundle = Join-Path $extractPath 'project.bundle'
  $previousErrorPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  git bundle verify $bundle *> $null
  $bundleVerifyExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorPreference
  if ($bundleVerifyExitCode -ne 0) { throw 'Verifica Git bundle fallita.' }

  $restoredRepo = Join-Path $testRoot 'restored'
  git clone --quiet $bundle $restoredRepo
  if ($LASTEXITCODE -ne 0) { throw 'Clone del bundle ripristinato fallito.' }

  $originalLines = @(git ls-tree -r $report.commit)
  if ($LASTEXITCODE -ne 0) { throw 'Commit originale non disponibile per il confronto.' }
  $restoredLines = @(git -C $restoredRepo ls-tree -r HEAD)
  if ($LASTEXITCODE -ne 0) { throw 'Lettura albero ripristinato fallita.' }
  $originalManifest = @($originalLines | ForEach-Object { $parts = $_ -split "`t", 2; "$(($parts[0] -split '\s+')[2])`t$($parts[1])" } | Sort-Object)
  $restoredManifest = @($restoredLines | ForEach-Object { $parts = $_ -split "`t", 2; "$(($parts[0] -split '\s+')[2])`t$($parts[1])" } | Sort-Object)
  if (($originalManifest -join "`n") -ne ($restoredManifest -join "`n")) { throw 'I contenuti ripristinati non corrispondono al commit originale.' }

  $record = [ordered]@{
    testedAt = (Get-Date).ToUniversalTime().ToString('o')
    source = if ($DownloadFromPinata) { 'pinata-gateway' } else { 'local-archive' }
    cid = $report.cid
    commit = $report.commit
    sha256 = $actualSha
    files = $restoredManifest.Count
    result = 'ok'
  }
  $reportName = if ($DownloadFromPinata) { 'restore-pinata-latest.json' } else { 'restore-local-latest.json' }
  [IO.File]::WriteAllText((Join-Path $projectRoot "deploy-reports\$reportName"), ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  Write-Host "Ripristino verificato: $($restoredManifest.Count) file, commit sorgente $($report.commit)."
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
