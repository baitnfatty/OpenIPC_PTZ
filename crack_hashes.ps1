# Try common passwords against the unsalted MD5 admin hash
$targetAdmin = "3a3b338d87b8837da90860c06da14377"
$targetTopsee = "9082a082425f0feba92925fd8d9f56d9"
$targetBlank = "69721a299df9f9733a1e745ab1678158"
$targetDdns = "7fe2bcf40f6ca474fed7801194f9dbe1"
$targetAdsl = "bb798ad555ccadf3de85c5a74697c589"

$candidates = @(
    "admin", "12345", "123456", "1234", "1111111", "11111111",
    "88888888", "888888", "8888", "999999", "9999",
    "password", "Password", "default", "system", "root", "123",
    "topsee", "TopSee", "TOPSEE", "Topsee123", "topsee123",
    "anjvision", "Anjvision", "ANJVISION", "AnjVision",
    "mc800s", "MC800S", "ipcam", "IPCAM", "Ipcam",
    "qwerty", "qweasd", "user", "User", "USER",
    "test", "Test", "TEST", "test123",
    "abc123", "letmein", "welcome",
    "0000", "00000000", "00000",
    "blank", "(blank)", "",
    "xmhdipc", "xmtech", "tlJwpbo6",
    "hi3516", "hisilicon",
    "sigmastar", "ssc338q",
    "mvxsystem", "mvx", "MVX",
    "factory", "Factory", "FACTORY",
    "service", "support", "manager", "operator",
    "admin1234", "admin123", "Admin123", "Admin@123",
    "a1234567", "888888888", "1234567", "1234567890",
    "icamra", "Icamra",
    "ac18pro", "Ac18Pro", "AC18Pro",
    "jidetech", "JideTech", "JIDETECH"
)

$md5 = [System.Security.Cryptography.MD5]::Create()

function GetMd5([string]$s) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($s)
    $hash = $md5.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-','').ToLower()
}

Write-Output "=== Cracking unsalted MD5 hashes ==="
Write-Output "Target admin:  $targetAdmin"
Write-Output "Target topsee: $targetTopsee"
Write-Output "Target blank:  $targetBlank"
Write-Output "Target ddns:   $targetDdns"
Write-Output "Target adsl:   $targetAdsl"
Write-Output ""

foreach ($c in $candidates) {
    $h = GetMd5 $c
    if ($h -eq $targetAdmin)  { Write-Output "*** ADMIN  PWD = '$c' (MD5 $h)" }
    if ($h -eq $targetTopsee) { Write-Output "*** TOPSEE PWD = '$c' (MD5 $h)" }
    if ($h -eq $targetBlank)  { Write-Output "*** BLANK  PWD = '$c' (MD5 $h)" }
    if ($h -eq $targetDdns)   { Write-Output "*** DDNS   PWD = '$c' (MD5 $h)" }
    if ($h -eq $targetAdsl)   { Write-Output "*** ADSL   PWD = '$c' (MD5 $h)" }
}

Write-Output ""
Write-Output "Done. If no matches, password not in common list."
