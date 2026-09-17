$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $projectRoot '.local\secrets'
$protectedPath = Join-Path $secretDir 'backup-password.dpapi'
$oneTimePath = Join-Path $projectRoot '.local\ONE-TIME-BACKUP-PASSWORD.txt'

if (Test-Path -LiteralPath $protectedPath) {
  Write-Host 'Password backup DPAPI già presente.'
  exit 0
}

New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$bytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
$password = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$secure = ConvertTo-SecureString $password -AsPlainText -Force
$protected = $secure | ConvertFrom-SecureString
[IO.File]::WriteAllText($protectedPath, $protected, [Text.UTF8Encoding]::new($false))
$notice = "PASSWORD AES-256 BACKUP NOMAD ECHO`r`n`r`n$password`r`n`r`nConservala fuori da questo PC. Elimina questo file dopo averla copiata."
[IO.File]::WriteAllText($oneTimePath, $notice, [Text.UTF8Encoding]::new($false))
Write-Host "Password creata: $oneTimePath"

