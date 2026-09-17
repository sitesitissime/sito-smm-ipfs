$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path $PSScriptRoot -Parent
$secretDir = Join-Path $projectRoot '.local\secrets'
$protectedPath = Join-Path $secretDir 'backup-password.dpapi'

$form = [Windows.Forms.Form]::new()
$form.Text = 'Password backup Nomad Echo'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = [Drawing.Size]::new(460, 210)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true

$label1 = [Windows.Forms.Label]::new()
$label1.Text = 'Scegli la password AES-256 (almeno 16 caratteri)'
$label1.Location = [Drawing.Point]::new(24, 20)
$label1.AutoSize = $true
$form.Controls.Add($label1)

$password1 = [Windows.Forms.TextBox]::new()
$password1.Location = [Drawing.Point]::new(24, 48)
$password1.Size = [Drawing.Size]::new(410, 27)
$password1.UseSystemPasswordChar = $true
$form.Controls.Add($password1)

$label2 = [Windows.Forms.Label]::new()
$label2.Text = 'Ripeti la password'
$label2.Location = [Drawing.Point]::new(24, 88)
$label2.AutoSize = $true
$form.Controls.Add($label2)

$password2 = [Windows.Forms.TextBox]::new()
$password2.Location = [Drawing.Point]::new(24, 114)
$password2.Size = [Drawing.Size]::new(410, 27)
$password2.UseSystemPasswordChar = $true
$form.Controls.Add($password2)

$save = [Windows.Forms.Button]::new()
$save.Text = 'Salva password'
$save.Location = [Drawing.Point]::new(304, 160)
$save.Size = [Drawing.Size]::new(130, 32)
$save.Add_Click({
  if ($password1.Text.Length -lt 16) {
    [Windows.Forms.MessageBox]::Show('Usa almeno 16 caratteri.', 'Password non valida') | Out-Null
    return
  }
  if ($password1.Text -cne $password2.Text) {
    [Windows.Forms.MessageBox]::Show('Le password non coincidono.', 'Password non valida') | Out-Null
    return
  }
  New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
  $secure = ConvertTo-SecureString $password1.Text -AsPlainText -Force
  $protected = $secure | ConvertFrom-SecureString
  [IO.File]::WriteAllText($protectedPath, $protected, [Text.UTF8Encoding]::new($false))
  $password1.Clear()
  $password2.Clear()
  $form.DialogResult = [Windows.Forms.DialogResult]::OK
  $form.Close()
})
$form.Controls.Add($save)
$form.AcceptButton = $save

$cancel = [Windows.Forms.Button]::new()
$cancel.Text = 'Annulla'
$cancel.Location = [Drawing.Point]::new(200, 160)
$cancel.Size = [Drawing.Size]::new(90, 32)
$cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancel)
$form.CancelButton = $cancel

$form.Add_Shown({ $password1.Focus() })
$result = $form.ShowDialog()
if ($result -ne [Windows.Forms.DialogResult]::OK) { exit 1 }
Write-Host 'Password salvata localmente con Windows DPAPI.'
