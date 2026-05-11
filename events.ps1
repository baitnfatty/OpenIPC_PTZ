$since = (Get-Date).AddDays(-14)

Write-Host "=== WINDOWS DEFENDER - DETECTED THREATS (Operational, last 14 days) ===" -ForegroundColor Cyan
# Event IDs: 1006/1015 = malware detected, 1116/1117 = malware detected/acted, 1118/1119 = remediation, 5007 = config change, 5001 = realtime disabled
try {
  Get-WinEvent -FilterHashtable @{
    LogName='Microsoft-Windows-Windows Defender/Operational';
    Id=1006,1007,1008,1009,1010,1015,1116,1117,1118,1119,5001,5007;
    StartTime=$since
  } -ErrorAction Stop | Select-Object TimeCreated, Id, LevelDisplayName, Message |
    Format-List
} catch {
  Write-Host "(no matching Defender events in window)"
}

Write-Host "`n=== APPLICATION LOG - ERRORS related to Claude (last 14 days) ===" -ForegroundColor Cyan
try {
  Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$since} -ErrorAction Stop |
    Where-Object { $_.Message -match 'claude|anthropic' -or $_.ProviderName -match 'claude|anthropic' } |
    Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, @{n='Msg';e={ ($_.Message -split "`n")[0] }} |
    Format-Table -AutoSize -Wrap
} catch {
  Write-Host "(none)"
}

Write-Host "`n=== APPLICATION CRASHES (Application Error / WER, last 14 days) ===" -ForegroundColor Cyan
try {
  Get-WinEvent -FilterHashtable @{
    LogName='Application';
    ProviderName='Application Error','Windows Error Reporting','Application Hang';
    StartTime=$since
  } -ErrorAction Stop | Select-Object TimeCreated, ProviderName, Id, @{n='Msg';e={ ($_.Message -split "`n")[0..2] -join ' | ' }} |
    Sort-Object TimeCreated -Descending | Select-Object -First 25 | Format-Table -AutoSize -Wrap
} catch {
  Write-Host "(none)"
}

Write-Host "`n=== SYSTEM LOG - critical/error in last 14 days (top 15) ===" -ForegroundColor Cyan
try {
  Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$since} -ErrorAction Stop |
    Sort-Object TimeCreated -Descending | Select-Object -First 15 |
    Select-Object TimeCreated, ProviderName, Id, @{n='Msg';e={ ($_.Message -split "`n")[0] }} |
    Format-Table -AutoSize -Wrap
} catch {
  Write-Host "(none)"
}

Write-Host "`n=== DEFENDER STATUS ===" -ForegroundColor Cyan
Get-MpComputerStatus | Select-Object AMServiceEnabled, AntispywareEnabled, AntivirusEnabled,
  RealTimeProtectionEnabled, BehaviorMonitorEnabled, NISEnabled, OnAccessProtectionEnabled,
  AntivirusSignatureLastUpdated, QuickScanStartTime, FullScanStartTime |
  Format-List

Write-Host "`n=== DEFENDER THREAT HISTORY ===" -ForegroundColor Cyan
$threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
if ($threats) {
  $threats | Select-Object InitialDetectionTime, ThreatID, Resources, ActionSuccess | Format-List
} else {
  Write-Host "(no threats in current detection history)"
}

$histThreats = Get-MpThreat -ErrorAction SilentlyContinue
if ($histThreats) {
  Write-Host "`n--- Historical Threats (Get-MpThreat) ---"
  $histThreats | Select-Object ThreatName, SeverityID, CategoryID, DidThreatExecute | Format-List
}
