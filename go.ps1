# go.ps1 — One-stop workflow runner for the AJ protocol campaign.
#
# Phase 2: capture → Phase 4: parse + diff + crc-solve.
# Phase 1 (Method 1/2 determination) is manual — see sd_setup.ps1 + telnet.
#
# Usage:
#   .\go.ps1 -ComPortRx COM5 -ComPortTx COM7
#
# Skips the API/capture step (just analyzes existing data) with -AnalyzeOnly:
#   .\go.ps1 -SessionDir aj_captures\session_20260508_133045 -AnalyzeOnly

param(
    [string]$ComPortRx,
    [string]$ComPortTx,
    [string]$CameraIP = "10.172.220.15",
    [int]$ApiPort = 8000,
    [string]$ApiUser = "admin",
    [string]$ApiPass = "",
    [string]$SessionDir,
    [switch]$AnalyzeOnly,
    [switch]$WithHandshake
)

$ErrorActionPreference = "Stop"

# Confirm we're in the right directory
if (-not (Test-Path "aj_diff_campaign.ps1")) {
    Write-Host "Run this from C:\Users\matth\investigate\" -ForegroundColor Red
    exit 1
}

if (-not $AnalyzeOnly) {
    if (-not $ComPortRx -or -not $ComPortTx) {
        Write-Host "Capture mode needs -ComPortRx and -ComPortTx." -ForegroundColor Red
        Write-Host "Use -AnalyzeOnly with -SessionDir to skip capture." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " Phase 2: HK32F Bidirectional Diff Campaign " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    $captureArgs = @(
        '-ComPortRx', $ComPortRx,
        '-ComPortTx', $ComPortTx,
        '-CameraIP', $CameraIP,
        '-ApiPort', $ApiPort,
        '-ApiUser', $ApiUser,
        '-ApiPass', $ApiPass
    )
    if ($WithHandshake) { $captureArgs += '-WithHandshake' }

    & .\aj_diff_campaign.ps1 @captureArgs

    # Find the session dir we just created (most recent)
    $SessionDir = Get-ChildItem -Path "aj_captures" -Directory -Filter "session_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName

    if (-not $SessionDir) {
        Write-Host "Capture failed — no session directory created." -ForegroundColor Red
        exit 1
    }
}
else {
    if (-not $SessionDir) {
        Write-Host "AnalyzeOnly needs -SessionDir." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Phase 4a: Parse all captures into CSV      " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$binFiles = Get-ChildItem -Path $SessionDir -Filter "*.bin" | Select-Object -ExpandProperty FullName
if (-not $binFiles) {
    Write-Host "No .bin files found in $SessionDir" -ForegroundColor Red
    exit 1
}

python aj_frame_parser.py @binFiles

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Phase 4b: Diff every action vs idle baseline " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

python aj_diff_visualizer.py "$SessionDir"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Phase 4c: Try CRC algorithms (auto)         " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Run CRC solver against the longest action capture (more frames = more confidence)
$rxCsvs = Get-ChildItem -Path $SessionDir -Filter "*_RX.csv" | Sort-Object Length -Descending
if ($rxCsvs) {
    $largest = $rxCsvs[0].FullName
    Write-Host "Running CRC solver against largest RX capture: $($rxCsvs[0].Name)"
    python aj_crc_solver.py "$largest" --auto
} else {
    Write-Host "No RX CSV files found." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Workflow complete                          " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Outputs in:  $SessionDir"
Write-Host "  *.bin                — raw captures"
Write-Host "  *.csv                — parsed frames"
Write-Host "  *.summary.txt        — per-capture stats"
Write-Host "  diffs\*.txt          — action-vs-baseline byte-position diffs"
Write-Host "  manifest.txt         — campaign metadata"
Write-Host ""
Write-Host "Look at the diff files first — they highlight COMMAND-LIKE bytes."
Write-Host "Then look at the CRC solver output to see if any algorithm matched."
