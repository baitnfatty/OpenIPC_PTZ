# Compare capture files to find cleanest parity setting
$files = @(
    "C:\Users\matth\investigate\hk32115200_rednone",
    "C:\Users\matth\investigate\hk32115200_redeven",
    "C:\Users\matth\investigate\hk32115200_redodd",
    "C:\Users\matth\investigate\hk32115200_red"
)

foreach ($f in $files) {
    if (-not (Test-Path $f)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $hex = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''

    # Count frame header occurrences
    $sync1 = ([regex]::Matches($hex, '0666006080')).Count
    $sync2 = ([regex]::Matches($hex, '06001e0000')).Count

    # Calculate byte distribution entropy (more uniform = more "garbage", peaked = real protocol)
    $hist = @{}
    foreach ($b in $bytes) {
        if ($hist.ContainsKey($b)) { $hist[$b]++ } else { $hist[$b] = 1 }
    }
    $uniqueBytes = $hist.Keys.Count

    # Find top-3 most common bytes
    $top = $hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5

    # Frame density (sync per kilobyte)
    $densitySync = if ($bytes.Length -gt 0) { [math]::Round($sync1 * 1024 / $bytes.Length, 2) } else { 0 }

    $name = (Split-Path $f -Leaf)
    Write-Output "=== $name ==="
    Write-Output "  Size: $($bytes.Length) bytes"
    Write-Output "  Frame header '06 66 00 60 80' count: $sync1 (density: $densitySync per KB)"
    Write-Output "  Frame footer '06 00 1E 00 00' count: $sync2"
    Write-Output "  Unique byte values: $uniqueBytes / 256"
    Write-Output "  Top 5 most frequent bytes:"
    foreach ($t in $top) {
        $pct = [math]::Round($t.Value * 100.0 / $bytes.Length, 1)
        Write-Output "    0x$($t.Key.ToString('x2')) = $($t.Value) ($pct%)"
    }
    Write-Output ""
}
