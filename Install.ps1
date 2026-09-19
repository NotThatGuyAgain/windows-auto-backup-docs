#requires -version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:ProgramData 'DocumentsBackup'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    try {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait
        exit 0
    } catch {
        Write-Error 'Administrator permission is required.'
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$drives = @(Get-CimInstance Win32_LogicalDisk | Where-Object {
    $_.DriveType -in 2, 3 -and $_.DeviceID -ne $env:SystemDrive -and $_.VolumeSerialNumber
} | Sort-Object DeviceID)

if ($drives.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        'Connect the external backup drive, then run Install.cmd again.',
        'Documents Backup', 'OK', 'Warning') | Out-Null
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Set up Documents Backup'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(480, 205)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$intro = New-Object System.Windows.Forms.Label
$intro.Location = New-Object Drawing.Point(20, 18)
$intro.Size = New-Object Drawing.Size(440, 52)
$intro.Text = 'Choose the external drive that will receive each user''s Documents backup. The drive can use a different letter later.'
$form.Controls.Add($intro)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.Location = New-Object Drawing.Point(20, 78)
$combo.Size = New-Object Drawing.Size(440, 30)
$combo.DropDownStyle = 'DropDownList'
foreach ($drive in $drives) {
    $label = if ($drive.VolumeName) { $drive.VolumeName } else { 'No label' }
    [void]$combo.Items.Add(('{0}  {1}  ({2:N1} GB free)' -f $drive.DeviceID, $label, ($drive.FreeSpace / 1GB)))
}
$combo.SelectedIndex = 0
$form.Controls.Add($combo)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Install'
$installButton.Location = New-Object Drawing.Point(275, 145)
$installButton.Size = New-Object Drawing.Size(85, 35)
$installButton.DialogResult = 'OK'
$form.AcceptButton = $installButton
$form.Controls.Add($installButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Location = New-Object Drawing.Point(375, 145)
$cancelButton.Size = New-Object Drawing.Size(85, 35)
$cancelButton.DialogResult = 'Cancel'
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

if ($form.ShowDialog() -ne 'OK') { exit 1 }
$selected = $drives[$combo.SelectedIndex]

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Watcher.ps1') (Join-Path $installDir 'Watcher.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'Uninstall.ps1') (Join-Path $installDir 'Uninstall.ps1') -Force

$config = [ordered]@{
    VolumeSerial = [string]$selected.VolumeSerialNumber
    VolumeLabel  = [string]$selected.VolumeName
    BackupFolder = 'PC Backup'
    PollSeconds  = 5
}
$config | ConvertTo-Json | Set-Content (Join-Path $installDir 'config.json') -Encoding UTF8

$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$command = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}"' -f (Join-Path $installDir 'Watcher.ps1')
New-ItemProperty -Path $runKey -Name 'DocumentsBackup' -Value $command -PropertyType String -Force | Out-Null

# Start it now for the person doing the installation; other users start at their next sign-in.
Start-Process powershell.exe -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}"' -f (Join-Path $installDir 'Watcher.ps1'))

[System.Windows.Forms.MessageBox]::Show(
    ('Setup is complete. Documents will back up whenever drive {0} is connected.' -f $selected.DeviceID),
    'Documents Backup', 'OK', 'Information') | Out-Null

