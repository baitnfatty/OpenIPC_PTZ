# Installed programs matching Claude/Anthropic
Write-Host "=== INSTALLED PROGRAMS (Claude/Anthropic) ===" -ForegroundColor Cyan
$paths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $paths -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -match 'Claude|Anthropic' } |
  Select-Object DisplayName, DisplayVersion, InstallLocation, Publisher, InstallDate |
  Format-List

Write-Host "`n=== STARTUP / AUTORUN ENTRIES (Run keys) ===" -ForegroundColor Cyan
$runKeys = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
foreach ($k in $runKeys) {
  if (Test-Path $k) {
    Write-Host "--- $k ---"
    Get-Item $k | Select-Object -ExpandProperty Property | ForEach-Object {
      $v = (Get-ItemProperty $k).$_
      "  $_  =  $v"
    }
  }
}

Write-Host "`n=== STARTUP FOLDER SHORTCUTS ===" -ForegroundColor Cyan
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
              "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue |
  Select-Object FullName, LastWriteTime | Format-Table -AutoSize

Write-Host "`n=== SCHEDULED TASKS modified in last 30 days (non-Microsoft) ===" -ForegroundColor Cyan
Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
  $info = $_ | Get-ScheduledTaskInfo
  [pscustomobject]@{
    Name = $_.TaskName
    Path = $_.TaskPath
    State = $_.State
    LastRun = $info.LastRunTime
    NextRun = $info.NextRunTime
    Author = $_.Author
    Action = ($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join '; '
  }
} | Sort-Object LastRun -Descending | Format-Table -AutoSize -Wrap
