# AJ Protocol Diff Campaign — Capture Script (DUAL PORT)
#
# Captures HK32F protocol traffic in BOTH directions while triggering specific
# PTZ actions via the camera's Hikvision API.
#
# Adapter assignments (edit defaults below if your COM ports are different):
#   ComPortRx   = USB-serial on R2 RED  (HK32F TX  →  SoC) — lens MCU outgoing
#   ComPortTx   = STLINK V3 VCP on R2 BLACK (SoC TX → HK32F) — SoC outgoing
#                 (or any second USB-serial)
#
# For each capture, two .bin files are saved:
#   <name>_RX.bin  — what the lens MCU sent (telemetry / responses)
#   <name>_TX.bin  — what the SoC sent (commands)
#
# Run with: .\aj_diff_campaign.ps1 -ComPortRx COM5 -ComPortTx COM7

param(
    [Parameter(Mandatory=$true, HelpMessage="COM port for HK32F TX (R2 RED) — lens telemetry")]
    [string]$ComPortRx,

    [Parameter(Mandatory=$true, HelpMessage="COM port for SoC TX (R2 BLACK) — commands. Use STLINK V3 VCP.")]
    [string]$ComPortTx,

    [string]$CameraIP = "10.172.220.15",
    [int]$ApiPort = 8000,
    [string]$ApiUser = "admin",
    [string]$ApiPass = "",

    [string]$OutputDir = "C:\Users\matth\investigate\aj_captures",

    [int]$BaudRate = 115200,

    # Capture timing (seconds)
    [int]$PreTriggerSec = 2,
    [int]$DuringActionSec = 4,
    [int]$PostStopSec = 2,

    # Skip API triggers — capture idle baseline only
    [switch]$IdleOnly,

    # Run only one command from the table (by name)
    [string]$OnlyCommand = $null,

    # HK32F030M's USART1 does NOT support hardware RTS/CTS (datasheet § 3.20).
    # Default is no handshake. Set this flag if for some reason you need RTS/CTS
    # (e.g. you're capturing a different camera that actually uses it).
    [switch]$WithHandshake
)

# -------------------------------------------------------------------
# Command table
# -------------------------------------------------------------------
$commands = @(
    @{ name = "01_idle_baseline";          triggerPath = $null;                                            triggerBody = $null;                                                          stopPath = $null;                                            stopBody = $null;                                                            note = "No action — baseline AJ telemetry stream" }
    @{ name = "02_zoom_in_30";             triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>30</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Zoom in (telephoto) at 30/64 speed" }
    @{ name = "03_zoom_in_60";             triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>60</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Zoom in at 60/64 speed — speed encoding test" }
    @{ name = "04_zoom_out_30";            triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>-30</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Zoom out (wide angle) at 30/64 speed" }
    @{ name = "05_zoom_out_60";            triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>-60</zoom></PTZData>"; stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Zoom out at 60/64 speed" }
    @{ name = "06_focus_far_30";           triggerPath = "/ISAPI/System/Video/inputs/channels/1/focus";    triggerBody = "<FocusData><focus>30</focus></FocusData>";                       stopPath = "/ISAPI/System/Video/inputs/channels/1/focus";    stopBody = "<FocusData><focus>0</focus></FocusData>";                       note = "Focus far (toward infinity)" }
    @{ name = "07_focus_near_30";          triggerPath = "/ISAPI/System/Video/inputs/channels/1/focus";    triggerBody = "<FocusData><focus>-30</focus></FocusData>";                      stopPath = "/ISAPI/System/Video/inputs/channels/1/focus";    stopBody = "<FocusData><focus>0</focus></FocusData>";                       note = "Focus near (close)" }
    @{ name = "08_pan_right_30";           triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>30</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Pan right — see if HK32F gets cross-axis frames" }
    @{ name = "09_pan_left_30";            triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>-30</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Pan left" }
    @{ name = "10_tilt_up_30";             triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>30</tilt><zoom>0</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Tilt up" }
    @{ name = "11_tilt_down_30";           triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>-30</tilt><zoom>0</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Tilt down" }
    @{ name = "12_combined_pan_zoom";      triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>30</pan><tilt>0</tilt><zoom>30</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Pan + zoom together — see if AJ frames combine" }
    @{ name = "13_zoom_in_long";           triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>40</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Long zoom in (8 sec) — captures grinding/stall behavior at mech limit" ; useExtendedDuring = $true }
    @{ name = "14_idle_baseline_again";    triggerPath = $null;                                            triggerBody = $null;                                                          stopPath = $null;                                            stopBody = $null;                                                            note = "Second idle baseline — confirms steady-state stable" }
)

# -------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$sessionDir = Join-Path $OutputDir "session_$timestamp"
New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

$manifestPath = Join-Path $sessionDir "manifest.txt"
"AJ Protocol Diff Campaign — Session $timestamp" | Out-File $manifestPath -Encoding UTF8
"=================================================" | Out-File $manifestPath -Encoding UTF8 -Append
"RX port: $ComPortRx (HK32F TX  -> SoC)  @ $BaudRate 8N1 $(if ($WithHandshake) {'RTS/CTS'} else {'no flow'})" | Out-File $manifestPath -Encoding UTF8 -Append
"TX port: $ComPortTx (SoC TX   -> HK32F) @ $BaudRate 8N1 $(if ($WithHandshake) {'RTS/CTS'} else {'no flow'})" | Out-File $manifestPath -Encoding UTF8 -Append
"Camera:  ${CameraIP}:${ApiPort}" | Out-File $manifestPath -Encoding UTF8 -Append
"Output:  $sessionDir" | Out-File $manifestPath -Encoding UTF8 -Append
"" | Out-File $manifestPath -Encoding UTF8 -Append

Write-Host "=== AJ Protocol Diff Campaign (DUAL PORT) ===" -ForegroundColor Cyan
Write-Host "Session: $timestamp"
Write-Host "RX:      $ComPortRx (HK32F TX)"
Write-Host "TX:      $ComPortTx (SoC TX)"
Write-Host "Output:  $sessionDir"
Write-Host ""

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
function Open-SerialCapture {
    param([string]$Port, [int]$Baud, [switch]$NoFlow)

    $sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    if ($NoFlow) {
        $sp.Handshake = [System.IO.Ports.Handshake]::None
    } else {
        $sp.Handshake = [System.IO.Ports.Handshake]::RequestToSend
    }
    $sp.ReadTimeout = 100
    $sp.ReadBufferSize = 1048576  # 1 MB ring
    $sp.Open()
    $sp.DiscardInBuffer()
    return $sp
}

function Capture-Both {
    param(
        [System.IO.Ports.SerialPort]$RxPort,
        [System.IO.Ports.SerialPort]$TxPort,
        [int]$DurationSec,
        [System.IO.MemoryStream]$RxStream,
        [System.IO.MemoryStream]$TxStream
    )
    $endTime = (Get-Date).AddSeconds($DurationSec)
    $buf = New-Object byte[] 4096

    while ((Get-Date) -lt $endTime) {
        $didWork = $false
        if ($RxPort.BytesToRead -gt 0) {
            $count = [Math]::Min($RxPort.BytesToRead, $buf.Length)
            $read = $RxPort.Read($buf, 0, $count)
            if ($read -gt 0) {
                $RxStream.Write($buf, 0, $read)
                $didWork = $true
            }
        }
        if ($TxPort.BytesToRead -gt 0) {
            $count = [Math]::Min($TxPort.BytesToRead, $buf.Length)
            $read = $TxPort.Read($buf, 0, $count)
            if ($read -gt 0) {
                $TxStream.Write($buf, 0, $read)
                $didWork = $true
            }
        }
        if (-not $didWork) {
            Start-Sleep -Milliseconds 3
        }
    }
}

function Invoke-CameraApi {
    param([string]$Path, [string]$Body)
    if (-not $Path) { return }

    $url = "http://${CameraIP}:${ApiPort}${Path}"
    $cred = $null
    if ($ApiUser) {
        $secpw = ConvertTo-SecureString $ApiPass -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($ApiUser, $secpw)
    }

    # Try PUT first (Hikvision continuous PTZ convention), then POST
    foreach ($method in @("PUT", "POST")) {
        try {
            if ($cred) {
                Invoke-WebRequest -Uri $url -Method $method -Body $Body -Credential $cred -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
            } else {
                Invoke-WebRequest -Uri $url -Method $method -Body $Body -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
            }
            return  # success
        }
        catch {
            # try next method
        }
    }
    Write-Host "    API call failed for $Path (both PUT and POST)" -ForegroundColor Yellow
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
$rx = $null
$tx = $null
try {
    Write-Host "Opening RX port $ComPortRx..." -ForegroundColor Gray
    $rx = Open-SerialCapture -Port $ComPortRx -Baud $BaudRate -NoFlow:(-not $WithHandshake)
    Write-Host "Opening TX port $ComPortTx..." -ForegroundColor Gray
    $tx = Open-SerialCapture -Port $ComPortTx -Baud $BaudRate -NoFlow:(-not $WithHandshake)
    Write-Host "Both ports open." -ForegroundColor Green

    $cmdsToRun = if ($OnlyCommand) {
        $commands | Where-Object { $_.name -eq $OnlyCommand }
    } elseif ($IdleOnly) {
        $commands | Where-Object { $_.triggerPath -eq $null }
    } else {
        $commands
    }

    if (-not $cmdsToRun) {
        Write-Host "No commands selected." -ForegroundColor Red
        return
    }

    foreach ($cmd in $cmdsToRun) {
        $name = $cmd.name
        Write-Host ""
        Write-Host "[$name] $($cmd.note)" -ForegroundColor Green

        $rxFile = Join-Path $sessionDir "${name}_RX.bin"
        $txFile = Join-Path $sessionDir "${name}_TX.bin"
        $rxMs = New-Object System.IO.MemoryStream
        $txMs = New-Object System.IO.MemoryStream

        # Optional extended duration for the long-zoom test
        $duringSec = if ($cmd.useExtendedDuring) { 8 } else { $DuringActionSec }

        # 1. Pre-trigger capture
        Write-Host "    Pre-trigger ($PreTriggerSec sec)..." -ForegroundColor Gray
        $rx.DiscardInBuffer(); $tx.DiscardInBuffer()
        Capture-Both -RxPort $rx -TxPort $tx -DurationSec $PreTriggerSec -RxStream $rxMs -TxStream $txMs
        $preRx = $rxMs.Length; $preTx = $txMs.Length

        # 2. Trigger
        if ($cmd.triggerPath) {
            Write-Host "    Trigger: $($cmd.triggerPath) [$($cmd.triggerBody)]" -ForegroundColor Gray
            Invoke-CameraApi -Path $cmd.triggerPath -Body $cmd.triggerBody
        }

        # 3. During-action capture
        Write-Host "    During-action ($duringSec sec)..." -ForegroundColor Gray
        Capture-Both -RxPort $rx -TxPort $tx -DurationSec $duringSec -RxStream $rxMs -TxStream $txMs
        $duringRx = $rxMs.Length; $duringTx = $txMs.Length

        # 4. Stop
        if ($cmd.stopPath) {
            Write-Host "    Stop: $($cmd.stopPath)" -ForegroundColor Gray
            Invoke-CameraApi -Path $cmd.stopPath -Body $cmd.stopBody
        }

        # 5. Post-stop capture
        Write-Host "    Post-stop ($PostStopSec sec)..." -ForegroundColor Gray
        Capture-Both -RxPort $rx -TxPort $tx -DurationSec $PostStopSec -RxStream $rxMs -TxStream $txMs

        # Save
        [System.IO.File]::WriteAllBytes($rxFile, $rxMs.ToArray())
        [System.IO.File]::WriteAllBytes($txFile, $txMs.ToArray())
        $rxBytes = $rxMs.Length; $txBytes = $txMs.Length

        Write-Host "    RX: $rxBytes bytes  →  $rxFile" -ForegroundColor Cyan
        Write-Host "    TX: $txBytes bytes  →  $txFile" -ForegroundColor Cyan

        # Manifest entry
        "[$name]" | Out-File $manifestPath -Encoding UTF8 -Append
        "  note:    $($cmd.note)" | Out-File $manifestPath -Encoding UTF8 -Append
        "  trigger: $($cmd.triggerPath) | $($cmd.triggerBody)" | Out-File $manifestPath -Encoding UTF8 -Append
        "  stop:    $($cmd.stopPath) | $($cmd.stopBody)" | Out-File $manifestPath -Encoding UTF8 -Append
        "  rx_pre/during/post: $preRx / $($duringRx - $preRx) / $($rxBytes - $duringRx) bytes" | Out-File $manifestPath -Encoding UTF8 -Append
        "  tx_pre/during/post: $preTx / $($duringTx - $preTx) / $($txBytes - $duringTx) bytes" | Out-File $manifestPath -Encoding UTF8 -Append
        "  totals:  rx=$rxBytes tx=$txBytes" | Out-File $manifestPath -Encoding UTF8 -Append
        "" | Out-File $manifestPath -Encoding UTF8 -Append

        $rxMs.Dispose(); $txMs.Dispose()
        Start-Sleep -Seconds 2  # let camera settle
    }

    Write-Host ""
    Write-Host "=== Campaign complete ===" -ForegroundColor Cyan
    Write-Host "Captures: $sessionDir"
    Write-Host ""
    Write-Host "Next: parse and diff." -ForegroundColor Yellow
    Write-Host "  python aj_frame_parser.py $sessionDir\*_RX.bin"
    Write-Host "  python aj_diff_visualizer.py $sessionDir\01_idle_baseline_RX.csv $sessionDir\02_zoom_in_30_RX.csv"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
}
finally {
    if ($rx -and $rx.IsOpen) { $rx.Close(); $rx.Dispose() }
    if ($tx -and $tx.IsOpen) { $tx.Close(); $tx.Dispose() }
}
