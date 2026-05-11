# sd_setup.ps1 — Prepare SD card for stock-firmware RCE
#
# When this SD card is inserted into the MC800S running stock firmware,
# the camera's mainctrl auto-runs /mnt/mmc0/upt_exec, which:
#   - Enables telnet on port 23 (no auth)
#   - Captures all diagnostic data we need to confirm Method 1 vs 2
#   - Captures UART traffic on /dev/ttyS1 and /dev/ttyS2
#   - Saves everything to /mnt/mmc0/diag.log + side files
#
# Usage:
#   1. Insert FAT32-formatted SD card into your PC
#   2. Run: .\sd_setup.ps1 -Drive E:    (replace E: with your SD card's drive letter)
#   3. Eject card, insert into camera, power-cycle
#   4. After ~2 minutes telnet should be open: telnet 10.172.220.15
#   5. Pull /mnt/mmc0/diag.log via telnet/scp to see findings

param(
    [Parameter(Mandatory=$true, HelpMessage="SD card drive letter, e.g. E:")]
    [string]$Drive,
    [string]$UptExecSource = "C:\Users\matth\investigate\upt_exec"
)

$Drive = $Drive.TrimEnd('\').TrimEnd(':') + ':'

if (-not (Test-Path $Drive)) {
    Write-Host "ERROR: $Drive not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $UptExecSource)) {
    Write-Host "ERROR: upt_exec source missing: $UptExecSource" -ForegroundColor Red
    exit 1
}

Write-Host "Copying upt_exec to SD card root..." -ForegroundColor Cyan
Copy-Item -Path $UptExecSource -Destination "$Drive\upt_exec" -Force

# Verify
$srcSize = (Get-Item $UptExecSource).Length
$dstSize = (Get-Item "$Drive\upt_exec").Length
if ($srcSize -ne $dstSize) {
    Write-Host "ERROR: Size mismatch after copy ($srcSize -> $dstSize)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "SD card prepped." -ForegroundColor Green
Write-Host "  $Drive\upt_exec  ($dstSize bytes)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Eject SD card cleanly"
Write-Host "  2. Insert into MC800S, power on (or power-cycle)"
Write-Host "  3. Wait ~90 seconds for stock boot + upt_exec auto-run"
Write-Host "  4. telnet 10.172.220.15  (no password)"
Write-Host "  5. cat /mnt/mmc0/diag.log  (look for motor_ctrl_use_pwm.flag)"
Write-Host ""
Write-Host "Method check command (key Phase 1 test):"
Write-Host '   ls -la /opt/ch/motor_ctrl_use_pwm.flag' -ForegroundColor Cyan
Write-Host ""
Write-Host "  File EXISTS    -> Method 1 (direct GPIO bit-bang for pan/tilt)"
Write-Host "  File MISSING   -> Method 2 (UART Pelco-D to STC8G for pan/tilt)"
