[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateRange(1, 1000)]
  [int]$Keep = 30,
  [ValidateRange(0, [long]::MaxValue)]
  [long]$RequiredFreeBytes = 0,
  [ValidateRange(1, [long]::MaxValue)]
  [long]$StorageLimitBytes = 1000000000,
  [bool]$ProtectLatestReport = $true
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$secretPath = Join-Path $projectRoot '.local\secrets\pinata-jwt.dpapi'
$reportPath = Join-Path $projectRoot 'deploy-reports\pinata-latest.json'

if (-not (Test-Path -LiteralPath $secretPath)) { throw 'JWT Pinata locale assente.' }
$secure = (Get-Content -Raw -LiteralPath $secretPath).Trim() | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $jwt = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }

$headers = @{ Authorization = "Bearer $jwt" }
$pins = [System.Collections.Generic.List[object]]::new()
$allPins = [System.Collections.Generic.List[object]]::new()
$offset = 0
do {
  $uri = "https://api.pinata.cloud/data/pinList?status=pinned&pageLimit=1000&includeCount=false&pageOffset=$offset"
  $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
  $rows = @($result.rows)
  foreach ($row in $rows) {
    $allPins.Add($row)
    $isNomadBackup = $row.metadata.keyvalues.sync_site -eq 'nomad-echo'
    $isLegacyNomadBackup = $row.metadata.name -eq 'Sito SMM - Nomad Echo'
    if ($isNomadBackup -or $isLegacyNomadBackup) { $pins.Add($row) }
  }
  $offset += $rows.Count
} while ($rows.Count -eq 1000)

$ordered = @($pins | Sort-Object { [datetime]$_.date_pinned } -Descending)
$protected = @($ordered | Select-Object -First $Keep | ForEach-Object { $_.ipfs_pin_hash })
$latestCid = $null
if ($ProtectLatestReport -and (Test-Path -LiteralPath $reportPath)) {
  $latestCid = (Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json).cid
  if ($latestCid) { $protected += $latestCid }
}
$obsolete = [System.Collections.Generic.List[object]]::new()
foreach ($pin in @($ordered | Where-Object { $_.ipfs_pin_hash -notin $protected })) { $obsolete.Add($pin) }

if ($RequiredFreeBytes -gt 0) {
  $usedBytes = [long](($allPins | Measure-Object -Property size -Sum).Sum)
  $afterRetention = $usedBytes - [long](($obsolete | Measure-Object -Property size -Sum).Sum)
  foreach ($candidate in @($ordered | Sort-Object { [datetime]$_.date_pinned })) {
    if (($afterRetention + $RequiredFreeBytes) -le $StorageLimitBytes) { break }
    if ($candidate.ipfs_pin_hash -eq $latestCid) { continue }
    if ($candidate.ipfs_pin_hash -notin @($obsolete.ipfs_pin_hash)) {
      $obsolete.Add($candidate)
      $afterRetention -= [long]$candidate.size
    }
  }
  if (($afterRetention + $RequiredFreeBytes) -gt $StorageLimitBytes) {
    throw 'Spazio Pinata insufficiente senza rimuovere backup estranei a Nomad Echo.'
  }
}

foreach ($pin in $obsolete) {
  $cid = $pin.ipfs_pin_hash
  if ($PSCmdlet.ShouldProcess($cid, 'Rimuovi vecchio backup cifrato Nomad Echo da Pinata')) {
    Invoke-RestMethod -Method Delete -Uri "https://api.pinata.cloud/pinning/unpin/$cid" -Headers $headers | Out-Null
    Write-Host "Rimosso backup Pinata: $cid"
    Start-Sleep -Milliseconds 300
  }
}

Write-Host "Pulizia Pinata completata: $($ordered.Count) backup Nomad Echo trovati (inclusi legacy), $($obsolete.Count) rimossi, conservazione massima $Keep."
