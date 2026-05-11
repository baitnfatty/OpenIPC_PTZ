$sig = Get-AuthenticodeSignature 'C:\Program Files\ASUS\AsusDriverHub\ADU.exe'
Write-Host "Status: $($sig.Status)"
Write-Host "Subject: $($sig.SignerCertificate.Subject)"
Write-Host "Issuer:  $($sig.SignerCertificate.Issuer)"
Write-Host "Thumbprint: $($sig.SignerCertificate.Thumbprint)"
$ver = (Get-Item 'C:\Program Files\ASUS\AsusDriverHub\ADU.exe').VersionInfo
Write-Host "FileDescription: $($ver.FileDescription)"
Write-Host "ProductName:     $($ver.ProductName)"
Write-Host "CompanyName:     $($ver.CompanyName)"
