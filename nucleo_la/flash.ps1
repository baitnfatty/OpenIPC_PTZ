# flash.ps1 — Flash LogicAlNucleo SUMP firmware to a Nucleo F411RE
#
# Uses STM32CubeProgrammer CLI to write the .bin via the Nucleo's onboard
# ST-Link/V2-1. Plug the Nucleo into the PC via its mini-USB connector
# before running.
#
# Usage:
#   .\flash.ps1
#   .\flash.ps1 -BinFile path\to\custom.bin
#   .\flash.ps1 -SerialNumber 0670FF...   # if multiple ST-Links connected

param(
    [string]$BinFile = "$PSScriptRoot\LogicAlNucleo.bin",
    [string]$SerialNumber = $null,
    [string]$ProgrammerCli = $null  # let auto-detect
)

# Auto-detect STM32CubeProgrammer CLI if path not given
if (-not $ProgrammerCli) {
    $candidates = @(
        "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "C:\Program Files (x86)\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe",
        "$env:LOCALAPPDATA\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ProgrammerCli = $c; break }
    }
}

if (-not $ProgrammerCli -or -not (Test-Path $ProgrammerCli)) {
    Write-Host "ERROR: STM32_Programmer_CLI.exe not found. Install STM32CubeProgrammer or pass -ProgrammerCli." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BinFile)) {
    Write-Host "ERROR: Binary not found: $BinFile" -ForegroundColor Red
    exit 1
}

$binSize = (Get-Item $BinFile).Length
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Flashing LogicAlNucleo SUMP firmware       " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Binary:        $BinFile  ($binSize bytes)"
Write-Host "Programmer:    $ProgrammerCli"
Write-Host ""

$args = @(
    "-c", "port=SWD"
)
if ($SerialNumber) { $args += @("sn=$SerialNumber") }
$args += @(
    "freq=1800",
    "mode=UR",
    "-w", $BinFile, "0x08000000",
    "-v",
    "-rst"
)

& $ProgrammerCli @args
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host " DONE — flash + verify + reset succeeded     " -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Disconnect and reconnect the Nucleo's USB cable"
    Write-Host "  2. Open Device Manager — note the new STMicro VCP COM port"
    Write-Host "  3. Wire 8 channels to PB0-PB7 per pinout.md"
    Write-Host "  4. Open PulseView — see pulseview_setup.md"
    Write-Host ""
    Write-Host "Quick sanity check: open the COM port at any baud and you should"
    Write-Host "see SUMP protocol responses to ID queries (binary garbage)."
} else {
    Write-Host ""
    Write-Host "FLASH FAILED (exit $exitCode)" -ForegroundColor Red
    Write-Host "Common issues:"
    Write-Host "  - Nucleo not plugged in or USB cable is charge-only"
    Write-Host "  - Multiple ST-Links connected — pass -SerialNumber"
    Write-Host "  - Onboard ST-Link firmware out of date"
    exit $exitCode
}
