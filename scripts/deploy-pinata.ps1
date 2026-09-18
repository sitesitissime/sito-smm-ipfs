[CmdletBinding()]
param(
  [switch]$ArchiveOnly,
  [string]$ArchivePath,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$secretDir = Join-Path $projectRoot '.local\secrets'
$backupDir = Join-Path $projectRoot 'backups\encrypted'
$reportPath = Join-Path $projectRoot 'deploy-reports\pinata-latest.json'
$stage = Join-Path $projectRoot ('.local\backup-stage-' + [guid]::NewGuid().ToString('N'))
$sevenZip = @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $sevenZip) { throw '7-Zip non trovato.' }

function Get-DpapiSecret([string]$name) {
  $path = Join-Path $secretDir "$name.dpapi"
  if (-not (Test-Path -LiteralPath $path)) { throw "Segreto locale assente: $name" }
  $secure = (Get-Content -Raw -LiteralPath $path).Trim() | ConvertTo-SecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

$jwt = if ($ArchiveOnly) { $null } else { Get-DpapiSecret 'pinata-jwt' }
$password = Get-DpapiSecret 'backup-password'
$currentCommit = (git rev-parse HEAD).Trim()
if (-not $ArchiveOnly -and -not $ArchivePath -and -not $Force -and (Test-Path -LiteralPath $reportPath)) {
  $previous = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  if ($previous.commit -eq $currentCommit -and $previous.cid) {
    Write-Host "Backup Pinata già aggiornato per $currentCommit."
    return
  }
}
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$archive = if ($ArchivePath) {
  (Resolve-Path -LiteralPath $ArchivePath).Path
} else {
  Join-Path $backupDir "nomad-echo-$timestamp.7z"
}
New-Item -ItemType Directory -Force -Path $backupDir, $stage | Out-Null

try {
  if (-not $ArchivePath) {
    $snapshotZip = Join-Path $stage 'snapshot.zip'
    $snapshotRepo = Join-Path $stage 'snapshot-repo'
    git archive --format=zip --output $snapshotZip HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Creazione snapshot fallita.' }
    Expand-Archive -LiteralPath $snapshotZip -DestinationPath $snapshotRepo
    Remove-Item -LiteralPath $snapshotZip -Force
    git -C $snapshotRepo init --initial-branch=main
    git -C $snapshotRepo config user.name 'Nomad Echo Backup'
    git -C $snapshotRepo config user.email 'backup@local.invalid'
    git -C $snapshotRepo add --all
    git -C $snapshotRepo commit -m "Snapshot cifrato $timestamp"
    if ($LASTEXITCODE -ne 0) { throw 'Creazione commit snapshot fallita.' }
    git -C $snapshotRepo bundle create (Join-Path $stage 'project.bundle') --all
    if ($LASTEXITCODE -ne 0) { throw 'Creazione Git bundle fallita.' }
    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git bundle verify (Join-Path $stage 'project.bundle') *> $null
    $bundleVerifyExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorPreference
    if ($bundleVerifyExitCode -ne 0) { throw 'Verifica Git bundle fallita.' }
    Remove-Item -LiteralPath $snapshotRepo -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $stage 'RECOVERY.txt'), "Nomad Echo`r`nRipristino: git clone project.bundle nomad-echo`r`nEstrazione: 7z x archivio.7z`r`nCronologia completa disponibile su GitHub e GitLab.`r`n", [Text.UTF8Encoding]::new($false))

    & $sevenZip a -t7z -m0=lzma2 -mx=7 -mhe=on "-p$password" $archive (Join-Path $stage '*') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Creazione archivio cifrato fallita.' }
  }
  & $sevenZip t "-p$password" $archive | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Verifica archivio cifrato fallita.' }

  $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
  if ($ArchiveOnly) { Write-Host "Archivio cifrato verificato: $archive"; return }

  $metadata = [ordered]@{
    name = "Nomad Echo encrypted backup $timestamp"
    keyvalues = [ordered]@{ sync_site = 'nomad-echo'; archive_sha = $sha; encrypted = 'aes-256' }
  } | ConvertTo-Json -Compress -Depth 4
  $client = [Net.Http.HttpClient]::new()
  $client.Timeout = [TimeSpan]::FromMinutes(30)
  $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $jwt)
  $multipart = [Net.Http.MultipartFormDataContent]::new()
  $stream = [IO.File]::OpenRead($archive)
  $fileContent = [Net.Http.StreamContent]::new($stream)
  $fileContent.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/x-7z-compressed')
  $multipart.Add($fileContent, 'file', [IO.Path]::GetFileName($archive))
  $multipart.Add([Net.Http.StringContent]::new($metadata), 'pinataMetadata')
  $response = $client.PostAsync('https://api.pinata.cloud/pinning/pinFileToIPFS', $multipart).GetAwaiter().GetResult()
  $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if (-not $response.IsSuccessStatusCode) { throw "Upload Pinata fallito: HTTP $([int]$response.StatusCode)" }
  $result = $body | ConvertFrom-Json
  if (-not $result.IpfsHash) { throw 'CID Pinata assente.' }
  $record = [ordered]@{ publishedAt = (Get-Date).ToUniversalTime().ToString('o'); commit = (git rev-parse HEAD).Trim(); archive = [IO.Path]::GetFileName($archive); sha256 = $sha; size = (Get-Item -LiteralPath $archive).Length; cid = $result.IpfsHash }
  New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'deploy-reports') | Out-Null
  [IO.File]::WriteAllText($reportPath, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  Write-Host "Pinata completato. CID: $($result.IpfsHash)"
} finally {
  if ($fileContent) { $fileContent.Dispose() }
  if ($stream) { $stream.Dispose() }
  if ($multipart) { $multipart.Dispose() }
  if ($client) { $client.Dispose() }
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
