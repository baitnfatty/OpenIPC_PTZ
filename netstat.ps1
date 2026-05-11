Write-Host "=== TCP CONNECTIONS (established/listen) with owning process ===" -ForegroundColor Cyan
$procs = @{}
Get-Process | ForEach-Object { $procs[$_.Id] = $_ }

$conns = Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.State -in 'Established','Listen' }

$rows = foreach ($c in $conns) {
  $p = $procs[[int]$c.OwningProcess]
  $exe = if ($p) { try { $p.Path } catch { $p.ProcessName } } else { '?' }
  [pscustomobject]@{
    State    = $c.State
    Local    = "$($c.LocalAddress):$($c.LocalPort)"
    Remote   = if ($c.State -eq 'Listen') { '' } else { "$($c.RemoteAddress):$($c.RemotePort)" }
    PID      = $c.OwningProcess
    Process  = if ($p) { $p.ProcessName } else { '?' }
    Path     = $exe
  }
}

Write-Host "`n--- LISTENING PORTS ---"
$rows | Where-Object State -eq 'Listen' | Sort-Object { [int]($_.Local -replace '.*:','') } |
  Format-Table State, Local, PID, Process, Path -AutoSize -Wrap

Write-Host "`n--- ESTABLISHED CONNECTIONS ---"
$rows | Where-Object State -eq 'Established' | Sort-Object Process |
  Format-Table State, Local, Remote, PID, Process, Path -AutoSize -Wrap

Write-Host "`n=== UNIQUE REMOTE IPs (Established) - reverse DNS ===" -ForegroundColor Cyan
$remotes = $rows | Where-Object State -eq 'Established' |
  ForEach-Object { ($_.Remote -split ':')[0] } | Sort-Object -Unique
foreach ($ip in $remotes) {
  if (-not $ip -or $ip -match '^(127\.|::1|0\.0\.0\.0|::$)') { continue }
  try {
    $name = [System.Net.Dns]::GetHostEntry($ip).HostName
  } catch { $name = '(no PTR)' }
  "{0,-40}  {1}" -f $ip, $name
}

Write-Host "`n=== Anything LISTENING on a non-standard port owned by a non-system process ===" -ForegroundColor Cyan
$rows | Where-Object {
  $_.State -eq 'Listen' -and
  $_.Process -notmatch '^(svchost|System|Idle|lsass|services|wininit|smss|csrss)$' -and
  $_.Path -notmatch 'WINDOWS\\System32|WINDOWS\\SystemApps|WINDOWS\\WinSxS'
} | Format-Table State, Local, PID, Process, Path -AutoSize -Wrap
