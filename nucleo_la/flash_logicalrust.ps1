# flash_logicalrust.ps1 - Flash LogicalRust SUMP firmware (Rust, native F411)
#
# This is the F411-specific Rust port (https://github.com/westrup/logicalrust)
# built locally on 2026-05-09 with rustc 1.95.0 GNU toolchain.
#
# Built-in: 8 channels on PB0-PB7, SUMP-compatible, native F411 timing,
# uses USART2 -- onboard ST-Link VCP.
#
# Usage:
#   .\flash_logicalrust.ps1
#   .\flash_logicalrust.ps1 -SerialNumber 0670FF...

param(
    [string]$BinFile = "$PSScriptRoot\logicalrust.bin",
    [string]$SerialNumber = $null,
    [string]$ProgrammerCli = $null
)

if (-not $ProgrammerCli) {
    $candidates = @(
        "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "C:\Program Files (x86)\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ProgrammerCli = $c; break }
    }
}

if (-not $ProgrammerCli -or -not (Test-Path $ProgrammerCli)) {
    Write-Host "ERROR: STM32_Programmer_CLI.exe not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BinFile)) {
    Write-Host "ERROR: Binary not found: $BinFile" -ForegroundColor Red
    Write-Host "Rebuild with: cd logicalrust ; cargo build --release --bin logicalrust" -ForegroundColor Yellow
    exit 1
}

$binSize = (Get-Item $BinFile).Length
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Flashing LogicalRust (Rust SUMP firmware)  " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Binary:        $BinFile  ($binSize bytes)"
Write-Host ""

$progArgs = @(
    "-c", "port=SWD"
)
if ($SerialNumber) { $progArgs += @("sn=$SerialNumber") }
$progArgs += @(
    "freq=1800",
    "mode=UR",
    "-w", $BinFile, "0x08000000",
    "-v",
    "-rst"
)

& $ProgrammerCli @progArgs
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host " DONE - flash + verify + reset succeeded     " -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Disconnect and reconnect the Nucleo USB cable"
    Write-Host "  2. Open Device Manager - note the STMicro VCP COM port (likely COM5 same as before)"
    Write-Host "  3. Open PulseView (NOT Analyzer2Go - this is SUMP firmware)"
    Write-Host "  4. Connect to Device, choose 'Openbench Logic Sniffer SUMP-compatibles (ols)'"
    Write-Host "  5. Serial port = COM5, Baud = 115200"
    Write-Host "  6. Sample rate 1 MHz, samples 4096, no trigger, single channel D0"
    Write-Host "  7. Wire D0 (PB0 to A3 on Arduino header) to 3V3 for HIGH test"
    Write-Host ""
    Write-Host "Channel pinout (PulseView D0-D7 to Nucleo header):"
    Write-Host "  D0 = PB0 = A3 (CN8 pin 4)"
    Write-Host "  D1 = PB1 = CN10 pin 7 (Morpho only)"
    Write-Host "  D2 = PB2 = AVOID (BOOT1 strap)"
    Write-Host "  D3 = PB3 = D3 (CN9 pin 4)"
    Write-Host "  D4 = PB4 = D5 (CN9 pin 5)"
    Write-Host "  D5 = PB5 = D4 (CN9 pin 6)"
    Write-Host "  D6 = PB6 = D10 (CN5 pin 3)"
    Write-Host "  D7 = PB7 = CN7 pin 21 (Morpho only)"
} else {
    Write-Host ""
    Write-Host "FLASH FAILED (exit $exitCode)" -ForegroundColor Red
    exit $exitCode
}
