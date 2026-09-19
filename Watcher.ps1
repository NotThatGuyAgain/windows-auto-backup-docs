#requires -version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path $configPath)) { exit 1 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$safeUser = ($env:USERNAME -replace '[\\/:*?"<>|]', '_')
$mutexName = 'Local\DocumentsBackup_' + ($env:USERDOMAIN -replace '\W', '_') + '_' + $safeUser
$createdNew = $false
$mutex = New-Object Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Get-BackupDrive {
    Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.VolumeSerialNumber -eq [string]$config.VolumeSerial } |
        Select-Object -First 1
}

function Get-SourceFiles([string]$root) {
    $files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        $folder = $pending.Pop()
        try {
            foreach ($item in Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop) {
                if ($item.PSIsContainer) {
                    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pending.Push($item.FullName) }
                } else {
                    $files.Add($item)
                }
            }
        } catch { }
    }
    return $files
}

function Start-VisibleBackup($drive) {
    $source = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    if (-not $source -or -not (Test-Path -LiteralPath $source)) { return }

    $safeComputer = ($env:COMPUTERNAME -replace '[\\/:*?"<>|]', '_')
    $destination = Join-Path ($drive.DeviceID + '\') ([string]$config.BackupFolder)
    $destination = Join-Path $destination $safeComputer
    $destination = Join-Path $destination $safeUser
    $destination = Join-Path $destination 'Documents'

    $form = New-Object Windows.Forms.Form
    $form.Text = 'Documents Backup'
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object Drawing.Size(570, 225)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)

    $title = New-Object Windows.Forms.Label
    $title.Location = New-Object Drawing.Point(22, 18)
    $title.Size = New-Object Drawing.Size(525, 28)
    $title.Font = New-Object Drawing.Font('Segoe UI Semibold', 14)
    $title.Text = 'Checking your Documents...'
    $form.Controls.Add($title)

    $current = New-Object Windows.Forms.Label
    $current.Location = New-Object Drawing.Point(22, 58)
    $current.Size = New-Object Drawing.Size(525, 44)
    $current.AutoEllipsis = $true
    $current.Text = 'Building the file list'
    $form.Controls.Add($current)

    $progress = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(22, 108)
    $progress.Size = New-Object Drawing.Size(525, 25)
    $progress.Style = 'Continuous'
    $form.Controls.Add($progress)

    $stats = New-Object Windows.Forms.Label
    $stats.Location = New-Object Drawing.Point(22, 145)
    $stats.Size = New-Object Drawing.Size(390, 30)
    $stats.Text = '0 new  |  0 updated  |  0 already backed up'
    $form.Controls.Add($stats)

    $closeButton = New-Object Windows.Forms.Button
    $closeButton.Location = New-Object Drawing.Point(457, 174)
    $closeButton.Size = New-Object Drawing.Size(90, 34)
    $closeButton.Text = 'Close'
    $closeButton.Enabled = $false
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    $script:busy = $true
    $form.Add_FormClosing({ param($sender, $eventArgs); if ($script:busy) { $eventArgs.Cancel = $true } })
    $form.Show()
    [Windows.Forms.Application]::DoEvents()

    $copied = 0; $updated = 0; $skipped = 0; $failed = 0
    try {
        $files = @(Get-SourceFiles $source)
        $progress.Maximum = [Math]::Max(1, $files.Count)
        $title.Text = 'Backing up your Documents...'

        for ($i = 0; $i -lt $files.Count; $i++) {
            $file = $files[$i]
            $relative = $file.FullName.Substring($source.Length).TrimStart('\')
            $target = Join-Path $destination $relative
            $current.Text = 'Checking: ' + $relative

            try {
                $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                $same = $existing -and $existing.Length -eq $file.Length -and
                    [Math]::Abs(($existing.LastWriteTimeUtc - $file.LastWriteTimeUtc).TotalSeconds) -lt 2
                if ($same) {
                    $skipped++
                } else {
                    $parent = Split-Path -Parent $target
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                    $temporary = $target + '.documents-backup-partial'
                    Copy-Item -LiteralPath $file.FullName -Destination $temporary -Force
                    [IO.File]::SetLastWriteTimeUtc($temporary, $file.LastWriteTimeUtc)
                    Move-Item -LiteralPath $temporary -Destination $target -Force
                    if ($existing) { $updated++ } else { $copied++ }
                    $current.Text = 'Copied: ' + $relative
                }
            } catch {
                $failed++
                Remove-Item -LiteralPath ($target + '.documents-backup-partial') -Force -ErrorAction SilentlyContinue
            }

            $progress.Value = [Math]::Min($i + 1, $progress.Maximum)
            $stats.Text = "$copied new  |  $updated updated  |  $skipped already backed up"
            [Windows.Forms.Application]::DoEvents()
        }

        if ($failed -eq 0) {
            $title.Text = 'Backup complete'
            $current.Text = 'It is now safe to eject the external drive.'
        } else {
            $title.Text = 'Backup completed with problems'
            $current.Text = "$failed file(s) could not be copied. Reconnect the drive to try again."
        }
    } catch {
        $title.Text = 'Backup stopped'
        $current.Text = 'The drive may have been disconnected. Reconnect it to continue later.'
    } finally {
        $script:busy = $false
        $closeButton.Enabled = $true
        $form.AcceptButton = $closeButton
        $form.Activate()
        while ($form.Visible) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        $form.Dispose()
    }
}

try {
    $wasConnected = $false
    while ($true) {
        $drive = Get-BackupDrive
        $isConnected = $null -ne $drive
        if ($isConnected -and -not $wasConnected) { Start-VisibleBackup $drive }
        $wasConnected = $null -ne (Get-BackupDrive)
        Start-Sleep -Seconds ([Math]::Max(2, [int]$config.PollSeconds))
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
