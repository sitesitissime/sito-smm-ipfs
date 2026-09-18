$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $projectRoot '.local\logs'
$logPath = Join-Path $logDir 'pinata-backup.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

try {
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  "[$timestamp] Avvio backup Pinata" | Add-Content -LiteralPath $logPath
  & (Join-Path $PSScriptRoot 'deploy-pinata.ps1') 2>&1 |
    ForEach-Object { $_ | Out-File -LiteralPath $logPath -Append -Encoding utf8 }
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
  & (Join-Path $PSScriptRoot 'cleanup-pinata-backups.ps1') -Keep 30 2>&1 |
    ForEach-Object { $_ | Out-File -LiteralPath $logPath -Append -Encoding utf8 }
  "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Backup completato" | Add-Content -LiteralPath $logPath
} catch {
  "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] ERRORE: $($_.Exception.Message)" | Add-Content -LiteralPath $logPath
  throw
}
