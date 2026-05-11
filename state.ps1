Write-Host "=== Running claude.exe processes ===" -ForegroundColor Cyan
Get-Process claude -ErrorAction SilentlyContinue |
  Select-Object Id, @{n='Path';e={ try { $_.Path } catch { '(access denied)' } }}, StartTime, Responding |
  Format-Table -AutoSize -Wrap

Write-Host "`n=== AnthropicClaude folder versions ===" -ForegroundColor Cyan
Get-ChildItem 'C:\Users\matth\AppData\Local\AnthropicClaude' -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
  Select-Object Name, CreationTime, LastWriteTime |
  Sort-Object Name | Format-Table -AutoSize

Write-Host "`n=== Top-level AnthropicClaude folder (looking for partial-update markers) ===" -ForegroundColor Cyan
Get-ChildItem 'C:\Users\matth\AppData\Local\AnthropicClaude' -ErrorAction SilentlyContinue |
  Select-Object Mode, LastWriteTime, Length, Name |
  Sort-Object LastWriteTime -Descending | Format-Table -AutoSize

Write-Host "`n=== Squirrel update log tail (last 40 lines) ===" -ForegroundColor Cyan
$log = 'C:\Users\matth\AppData\Local\AnthropicClaude\SquirrelSetup.log'
if (Test-Path $log) {
  Get-Content $log -Tail 40
} else {
  Write-Host "No SquirrelSetup.log at $log"
  Get-ChildItem 'C:\Users\matth\AppData\Local\AnthropicClaude' -Filter '*.log' -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, LastWriteTime, Length | Format-Table -AutoSize
}

Write-Host "`n=== MSIX Claude package version (if still installed) ===" -ForegroundColor Cyan
Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue |
  Select-Object Name, Version, InstallLocation | Format-List

Write-Host "`n=== Registered uninstall entry version ===" -ForegroundColor Cyan
Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -eq 'Claude' } |
  Select-Object DisplayName, DisplayVersion, InstallLocation, InstallDate, UninstallString | Format-List
