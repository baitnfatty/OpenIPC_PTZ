Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -in 5488,8600 } |
  Select-Object ProcessId, Name, DisplayName, PathName, StartName, StartMode, State |
  Format-List

Write-Host "`n--- Service binary signatures ---"
$paths = Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -in 5488,8600 } | ForEach-Object {
  # PathName may have quoted exe path with args
  if ($_.PathName -match '^"([^"]+)"') { $matches[1] }
  elseif ($_.PathName -match '^([^\s]+)') { $matches[1] }
}
foreach ($p in $paths) {
  if (-not (Test-Path $p)) { Write-Host "Missing: $p"; continue }
  Write-Host "`n$p"
  $sig = Get-AuthenticodeSignature $p
  Write-Host "  Status:  $($sig.Status)"
  if ($sig.SignerCertificate) {
    Write-Host "  Subject: $($sig.SignerCertificate.Subject)"
    Write-Host "  Issuer:  $($sig.SignerCertificate.Issuer)"
  }
  $ver = (Get-Item $p).VersionInfo
  Write-Host "  Description: $($ver.FileDescription)"
  Write-Host "  Product:     $($ver.ProductName)"
  Write-Host "  Company:     $($ver.CompanyName)"
}
