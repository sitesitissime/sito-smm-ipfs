[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateRange(2, 1000)]
  [int]$Keep = 30
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
$offset = 0
do {
  $uri = "https://api.pinata.cloud/data/pinList?status=pinned&pageLimit=1000&includeCount=false&pageOffset=$offset"
  $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
  $rows = @($result.rows)
  foreach ($row in $rows) {
    if ($row.metadata.keyvalues.sync_site -eq 'nomad-echo') { $pins.Add($row) }
  }
  $offset += $rows.Count
} while ($rows.Count -eq 1000)

$ordered = @($pins | Sort-Object { [datetime]$_.date_pinned } -Descending)
$protected = @($ordered | Select-Object -First $Keep | ForEach-Object { $_.ipfs_pin_hash })
if (Test-Path -LiteralPath $reportPath) {
  $latestCid = (Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json).cid
  if ($latestCid) { $protected += $latestCid }
}
$obsolete = @($ordered | Where-Object { $_.ipfs_pin_hash -notin $protected })

foreach ($pin in $obsolete) {
  $cid = $pin.ipfs_pin_hash
  if ($PSCmdlet.ShouldProcess($cid, 'Rimuovi vecchio backup cifrato Nomad Echo da Pinata')) {
    Invoke-RestMethod -Method Delete -Uri "https://api.pinata.cloud/pinning/unpin/$cid" -Headers $headers | Out-Null
    Write-Host "Rimosso backup Pinata: $cid"
    Start-Sleep -Milliseconds 300
  }
}

Write-Host "Pulizia Pinata completata: $($ordered.Count) backup trovati, $($obsolete.Count) rimossi, conservazione $Keep."
