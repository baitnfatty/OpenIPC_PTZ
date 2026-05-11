Write-Host "=== APPX PACKAGES: Claude + Notepad - publisher / signature / install location ===" -ForegroundColor Cyan
Get-AppxPackage | Where-Object { $_.Name -match 'Claude|Notepad|IntelArc' } |
  Select-Object Name, Publisher, PublisherId, SignatureKind, Version, IsBundle, IsFramework, InstallLocation, Architecture |
  Format-List

Write-Host "`n=== AUTHENTICODE SIGNATURE: AnthropicClaude\claude.exe (Squirrel install) ===" -ForegroundColor Cyan
Get-AuthenticodeSignature 'C:\Users\matth\AppData\Local\AnthropicClaude\app-1.5354.0\claude.exe' |
  Select-Object Status, StatusMessage, SignerCertificate | Format-List
$cert1 = (Get-AuthenticodeSignature 'C:\Users\matth\AppData\Local\AnthropicClaude\app-1.5354.0\claude.exe').SignerCertificate
if ($cert1) { $cert1 | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint | Format-List }

Write-Host "`n=== AUTHENTICODE SIGNATURE: WindowsApps Claude (MSIX) ===" -ForegroundColor Cyan
$msixExe = 'C:\Program Files\WindowsApps\Claude_1.5354.0.0_x64__pzs8sxrjxfjjc\claude.exe'
if (Test-Path $msixExe) {
  $sig = Get-AuthenticodeSignature $msixExe
  $sig | Select-Object Status, StatusMessage | Format-List
  if ($sig.SignerCertificate) {
    $sig.SignerCertificate | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint | Format-List
  }
} else {
  Write-Host "(no claude.exe at the path - listing folder)"
  Get-ChildItem 'C:\Program Files\WindowsApps\Claude_1.5354.0.0_x64__pzs8sxrjxfjjc' -ErrorAction SilentlyContinue |
    Select-Object Name, Length | Format-Table -AutoSize
}

Write-Host "`n=== CONTENTS OF WindowsApps Claude folder ===" -ForegroundColor Cyan
try {
  Get-ChildItem 'C:\Program Files\WindowsApps\Claude_1.5354.0.0_x64__pzs8sxrjxfjjc' -ErrorAction Stop |
    Select-Object Mode, LastWriteTime, Length, Name | Format-Table -AutoSize
} catch {
  Write-Host "ACL blocks listing (this is normal for WindowsApps). Trying via takeown alternative..."
  cmd.exe /c "dir `"C:\Program Files\WindowsApps\Claude_1.5354.0.0_x64__pzs8sxrjxfjjc`""
}

Write-Host "`n=== PUBLISHER ID DECODE - Claude_pzs8sxrjxfjjc ===" -ForegroundColor Cyan
# pzs8sxrjxfjjc is the Family Publisher Hash. Real Anthropic publisher should match consistently.
# Compare against the package that's known to be the real Anthropic one.
Write-Host "Claude package PFN family: Claude_pzs8sxrjxfjjc"
Write-Host "If the Publisher above does not say 'CN=Anthropic, O=Anthropic, ...' then this is suspicious."

Write-Host "`n=== ALL .EXE FILES IN AnthropicClaude folder w/ signature status ===" -ForegroundColor Cyan
Get-ChildItem 'C:\Users\matth\AppData\Local\AnthropicClaude' -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue |
  ForEach-Object {
    $sig = Get-AuthenticodeSignature $_.FullName
    [pscustomobject]@{
      Path = $_.FullName.Replace('C:\Users\matth\AppData\Local\AnthropicClaude\','')
      Status = $sig.Status
      Subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(unsigned)' }
    }
  } | Format-Table -AutoSize -Wrap

Write-Host "`n=== UPDATE HISTORY for Notepad install error - is the package real? ===" -ForegroundColor Cyan
# 9MSMLRH6LZF3 is Microsoft's official Store product ID for Windows Notepad. Verify.
Get-AppxPackage Microsoft.WindowsNotepad -ErrorAction SilentlyContinue |
  Select-Object Name, Publisher, PublisherId, SignatureKind, Version, InstallLocation | Format-List

Write-Host "`n=== ALL non-system MSIX packages installed (look for unfamiliar publishers) ===" -ForegroundColor Cyan
Get-AppxPackage | Where-Object {
  $_.SignatureKind -ne 'System' -and $_.Publisher -notmatch 'Microsoft Corporation|Microsoft Windows'
} | Select-Object Name, Publisher, SignatureKind, Version | Sort-Object Publisher | Format-Table -AutoSize -Wrap
