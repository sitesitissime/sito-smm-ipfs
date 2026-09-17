$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $projectRoot '.local\secrets'
$protectedPath = Join-Path $secretDir 'backup-password.dpapi'

if (Test-Path -LiteralPath $protectedPath) {
  throw 'Password già presente. Eliminala esplicitamente prima di sostituirla.'
}

$first = Read-Host 'Scegli la password AES-256 del backup' -AsSecureString
$second = Read-Host 'Ripeti la password' -AsSecureString
$firstPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
$secondPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
try {
  $firstText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($firstPtr)
  $secondText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secondPtr)
  if ($firstText.Length -lt 16) { throw 'Usa almeno 16 caratteri.' }
  if ($firstText -cne $secondText) { throw 'Le password non coincidono.' }
  New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
  $protected = $first | ConvertFrom-SecureString
  [IO.File]::WriteAllText($protectedPath, $protected, [Text.UTF8Encoding]::new($false))
  Write-Host 'Password salvata localmente con Windows DPAPI.'
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($firstPtr)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secondPtr)
  $firstText = $null
  $secondText = $null
}
