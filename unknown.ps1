foreach ($pid_ in @(5488, 8600)) {
  Write-Host "=== PID $pid_ ===" -ForegroundColor Cyan
  $p = Get-Process -Id $pid_ -ErrorAction SilentlyContinue
  if (-not $p) { Write-Host "(process gone)"; continue }
  $exe = $p.Path
  Write-Host "Name: $($p.ProcessName)"
  Write-Host "Path: $exe"
  Write-Host "StartTime: $($p.StartTime)"
  if ($exe) {
    $sig = Get-AuthenticodeSignature $exe
    Write-Host "Signature: $($sig.Status)"
    if ($sig.SignerCertificate) {
      Write-Host "Subject:   $($sig.SignerCertificate.Subject)"
      Write-Host "Issuer:    $($sig.SignerCertificate.Issuer)"
    }
    $fi = Get-Item $exe
    Write-Host "Created:   $($fi.CreationTime)   Modified: $($fi.LastWriteTime)   Size: $($fi.Length)"
    $ver = (Get-Item $exe).VersionInfo
    Write-Host "FileDescription: $($ver.FileDescription)"
    Write-Host "ProductName:     $($ver.ProductName)"
    Write-Host "CompanyName:     $($ver.CompanyName)"
    Write-Host "FileVersion:     $($ver.FileVersion)"
  }

  # Parent process - context for what spawned it
  try {
    $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId=$pid_").ParentProcessId
    $parent = Get-Process -Id $parentId -ErrorAction SilentlyContinue
    if ($parent) {
      Write-Host "Parent PID: $parentId  ($($parent.ProcessName))  Path: $($parent.Path)"
    }
  } catch {}
  Write-Host ""
}

Write-Host "=== UDP listeners on this machine (look for unexpected ones) ===" -ForegroundColor Cyan
Get-NetUDPEndpoint | ForEach-Object {
  $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
  [pscustomobject]@{
    Local = "$($_.LocalAddress):$($_.LocalPort)"
    PID = $_.OwningProcess
    Process = if ($p) { $p.ProcessName } else { '?' }
    Path = if ($p) { $p.Path } else { '' }
  }
} | Sort-Object Process | Format-Table -AutoSize -Wrap
