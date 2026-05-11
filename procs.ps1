# Build a process map: PID -> {name, path, parent, cmdline, created}
$procs = Get-CimInstance Win32_Process | ForEach-Object {
  [pscustomobject]@{
    PID = $_.ProcessId
    PPID = $_.ParentProcessId
    Name = $_.Name
    Path = $_.ExecutablePath
    Cmd = $_.CommandLine
    Created = $_.CreationDate
  }
}

# Identify MY pid and its ancestors (Claude Code) so we never recommend killing them
$myPid = $PID
$ancestors = @($myPid)
$cur = $myPid
while ($true) {
  $p = $procs | Where-Object PID -eq $cur | Select-Object -First 1
  if (-not $p -or -not $p.PPID -or $p.PPID -eq 0) { break }
  $ancestors += $p.PPID
  $cur = $p.PPID
  if ($ancestors.Count -gt 20) { break }
}

Write-Host "=== My own process tree (do NOT kill these) ===" -ForegroundColor Yellow
foreach ($a in $ancestors) {
  $p = $procs | Where-Object PID -eq $a | Select-Object -First 1
  if ($p) { "  PID $($p.PID)  $($p.Name)  -- $($p.Path)" }
}

Write-Host "`n=== Process counts grouped by name (>= 2 instances) ===" -ForegroundColor Cyan
$procs | Group-Object Name | Where-Object Count -ge 2 | Sort-Object Count -Descending |
  Format-Table @{n='Count';e={$_.Count}}, Name -AutoSize

Write-Host "`n=== For each duplicated name: path + parent + age ===" -ForegroundColor Cyan
$dupGroups = $procs | Group-Object Name | Where-Object { $_.Count -ge 2 -and $_.Name -ne 'svchost.exe' -and $_.Name -ne 'conhost.exe' -and $_.Name -ne 'RuntimeBroker.exe' -and $_.Name -ne 'dllhost.exe' -and $_.Name -ne 'sihost.exe' -and $_.Name -ne 'taskhostw.exe' }

foreach ($g in $dupGroups) {
  Write-Host "`n--- $($g.Name)  ($($g.Count) instances) ---" -ForegroundColor Green
  $g.Group | ForEach-Object {
    $parent = $procs | Where-Object PID -eq $_.PPID | Select-Object -First 1
    $parentName = if ($parent) { "$($parent.Name) [PID $($parent.PID)]" } else { '(parent gone)' }
    [pscustomobject]@{
      PID = $_.PID
      Parent = $parentName
      Path = $_.Path
      CmdSnippet = if ($_.Cmd) { $_.Cmd.Substring(0, [Math]::Min(80, $_.Cmd.Length)) } else { '' }
    }
  } | Format-Table -AutoSize -Wrap
}

Write-Host "`n=== Memory hogs (top 15 by working set) ===" -ForegroundColor Cyan
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 |
  Select-Object Id, ProcessName, @{n='RAM_MB';e={[Math]::Round($_.WorkingSet64/1MB,0)}}, StartTime |
  Format-Table -AutoSize

Write-Host "`n=== Total claude desktop process count + total RAM used ===" -ForegroundColor Cyan
$cd = Get-Process claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*AnthropicClaude\app-*' }
if ($cd) {
  $totalMB = [Math]::Round(($cd | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
  Write-Host "Claude Desktop processes: $($cd.Count)  Total RAM: $totalMB MB"
}
