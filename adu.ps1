# Try Win32_Process to get the executable path even for SYSTEM-owned processes
$proc = Get-CimInstance Win32_Process -Filter "ProcessId=8600"
if ($proc) {
  Write-Host "=== Win32_Process for PID 8600 ===" -ForegroundColor Cyan
  $proc | Select-Object ProcessId, Name, ExecutablePath, CommandLine, ParentProcessId, CreationDate | Format-List
} else {
  Write-Host "PID 8600 no longer exists. Looking up any 'ADU' process currently running..."
  Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^adu' } |
    Select-Object ProcessId, Name, ExecutablePath, CommandLine | Format-List
}

Write-Host "`n=== Searching for any service hosted in svchost PID 3680 ===" -ForegroundColor Cyan
Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -eq 3680 } |
  Select-Object Name, DisplayName, PathName | Format-List

Write-Host "`n=== Searching all 'ADU*' anything on disk ===" -ForegroundColor Cyan
Get-ChildItem 'C:\Program Files','C:\Program Files (x86)','C:\Windows','C:\Users\matth\AppData' -Recurse -Filter 'ADU*' -ErrorAction SilentlyContinue |
  Select-Object -First 20 FullName, Length, LastWriteTime | Format-Table -AutoSize -Wrap

Write-Host "`n=== Also: any service with 'ADU' or 'Adobe' or 'Asus' in name and its hosting PID ===" -ForegroundColor Cyan
Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'ADU|Adobe|Asus|Audio' } |
  Select-Object Name, ProcessId, State, PathName | Format-List
