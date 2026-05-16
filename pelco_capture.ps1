# pelco_capture.ps1 — Capture HK32F→STC8G traffic on the white wire (NOT Pelco-D!)
#
# Filename "pelco_capture" is historical — protocol turned out NOT to be standard
# Pelco-D after measurement. Real protocol:
#   - 66,666 baud 8N1 (NOT 2400)
#   - 6-byte custom frames (NOT 7-byte Pelco-D)
#   - Baseline recurring frame: 51 01 04 78 01 0D
#   - Direction: HK32F lens MCU TX → diode D3 → STC8G P3.0 RxD (NOT SoC → STC8G)
#
# Triggers PTZ pan/tilt actions via the camera's Hikvision API while capturing
# what the HK32F is forwarding to the STC8G.  Because the HK32F is acting as
# the central relay, pan/tilt activity should appear here even though the SoC
# never directly speaks to the STC8G.
#
# Wiring:
#   White wire (tap on distro board NET connector, or HK32F 3p-top "IR" pin) ─→ USB-serial RX
#   Camera GND ─→ USB-serial GND
#   USB-serial chip MUST support 66666 baud divisor (CH340G, FT232 w/ custom divisor, PL2303HX OK)
#
# Decode with:
#   python hk32_stc8g_decoder.py <output-dir>\*.bin
#
# Usage:
#   .\pelco_capture.ps1 -ComPort COM5

param(
    [Parameter(Mandatory=$true, HelpMessage="COM port for USB-serial on the white wire")]
    [string]$ComPort,

    [string]$CameraIP = "10.172.220.15",
    [int]$ApiPort = 8000,
    [string]$ApiUser = "admin",
    [string]$ApiPass = "",

    [string]$OutputDir = "C:\Users\matth\investigate\whitewire_captures",

    # CORRECTED 2026-05-16: actual protocol is 9600 baud ASCII (HK32F debug console).
    # The earlier 66666 baud hypothesis was a misinterpretation of the same signal at
    # the wrong rate.  The console prints a boot banner identifying firmware version,
    # build date, module type (AJ), and lens model (LH3X) — then accepts operational
    # commands.
    [int]$BaudRate = 9600,

    [int]$PreTriggerSec = 2,
    [int]$DuringActionSec = 4,
    [int]$PostStopSec = 2,

    [switch]$IdleOnly,
    [string]$OnlyCommand = $null
)

# Pan/tilt commands only — zoom/focus are on the AF UART (use aj_diff_campaign.ps1 for those)
$commands = @(
    @{ name = "01_idle_baseline";       triggerPath = $null;                                            triggerBody = $null;                                                          stopPath = $null;                                            stopBody = $null;                                                            note = "Idle baseline — no PTZ activity" }
    @{ name = "02_pan_right_30";        triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>30</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Pan right at speed 30/64" }
    @{ name = "03_pan_right_60";        triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>60</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Pan right at speed 60/64" }
    @{ name = "04_pan_left_30";         triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>-30</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Pan left at speed 30" }
    @{ name = "05_tilt_up_30";          triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>30</tilt><zoom>0</zoom></PTZData>";   stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Tilt up at speed 30" }
    @{ name = "06_tilt_down_30";        triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>0</pan><tilt>-30</tilt><zoom>0</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Tilt down at speed 30" }
    @{ name = "07_combined_pan_tilt";   triggerPath = "/ISAPI/PTZCtrl/channels/1/continuous";           triggerBody = "<PTZData><pan>30</pan><tilt>30</tilt><zoom>0</zoom></PTZData>";  stopPath = "/ISAPI/PTZCtrl/channels/1/continuous";           stopBody = "<PTZData><pan>0</pan><tilt>0</tilt><zoom>0</zoom></PTZData>";   note = "Diagonal: pan + tilt simultaneously" }
    @{ name = "08_idle_baseline_again"; triggerPath = $null;                                            triggerBody = $null;                                                          stopPath = $null;                                            stopBody = $null;                                                            note = "Confirms steady-state stable" }
)

if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$sessionDir = Join-Path $OutputDir "session_$timestamp"
New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null
$manifestPath = Join-Path $sessionDir "manifest.txt"

"HK32F->STC8G white-wire capture — Session $timestamp" | Out-File $manifestPath -Encoding UTF8
"Port: $ComPort @ $BaudRate 8N1 no flow  (custom protocol, NOT Pelco-D)" | Out-File $manifestPath -Encoding UTF8 -Append
"Camera: ${CameraIP}:${ApiPort}" | Out-File $manifestPath -Encoding UTF8 -Append
"Output: $sessionDir" | Out-File $manifestPath -Encoding UTF8 -Append
"" | Out-File $manifestPath -Encoding UTF8 -Append

Write-Host "=== HK32F->STC8G White Wire Capture (66666 baud, custom protocol) ===" -ForegroundColor Cyan
Write-Host "Port:    $ComPort @ $BaudRate"
Write-Host "Output:  $sessionDir"
Write-Host ""

function Open-Port {
    param([string]$Port, [int]$Baud)
    $sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $sp.Handshake = [System.IO.Ports.Handshake]::None
    $sp.ReadTimeout = 100
    $sp.ReadBufferSize = 524288
    $sp.Open()
    $sp.DiscardInBuffer()
    return $sp
}

function Capture-Bytes {
    param([System.IO.Ports.SerialPort]$Port, [int]$DurationSec, [System.IO.MemoryStream]$Stream)
    $endTime = (Get-Date).AddSeconds($DurationSec)
    $buf = New-Object byte[] 1024
    while ((Get-Date) -lt $endTime) {
        if ($Port.BytesToRead -gt 0) {
            $count = [Math]::Min($Port.BytesToRead, $buf.Length)
            $read = $Port.Read($buf, 0, $count)
            if ($read -gt 0) { $Stream.Write($buf, 0, $read) }
        } else {
            Start-Sleep -Milliseconds 5
        }
    }
}

function Invoke-Api {
    param([string]$Path, [string]$Body)
    if (-not $Path) { return }
    $url = "http://${CameraIP}:${ApiPort}${Path}"
    $secpw = ConvertTo-SecureString $ApiPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($ApiUser, $secpw)
    foreach ($method in @("PUT", "POST")) {
        try {
            Invoke-WebRequest -Uri $url -Method $method -Body $Body -Credential $cred -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
            return
        } catch { }
    }
    Write-Host "    API call failed: $Path" -ForegroundColor Yellow
}

$sp = $null
try {
    $sp = Open-Port -Port $ComPort -Baud $BaudRate

    $cmdsToRun = if ($OnlyCommand) { $commands | Where-Object { $_.name -eq $OnlyCommand } } elseif ($IdleOnly) { $commands | Where-Object { $_.triggerPath -eq $null } } else { $commands }

    foreach ($cmd in $cmdsToRun) {
        Write-Host "[$($cmd.name)] $($cmd.note)" -ForegroundColor Green
        $file = Join-Path $sessionDir "$($cmd.name).bin"
        $ms = New-Object System.IO.MemoryStream

        $sp.DiscardInBuffer()
        Capture-Bytes -Port $sp -DurationSec $PreTriggerSec -Stream $ms
        $preBytes = $ms.Length

        Invoke-Api -Path $cmd.triggerPath -Body $cmd.triggerBody
        Capture-Bytes -Port $sp -DurationSec $DuringActionSec -Stream $ms
        $duringBytes = $ms.Length - $preBytes

        Invoke-Api -Path $cmd.stopPath -Body $cmd.stopBody
        Capture-Bytes -Port $sp -DurationSec $PostStopSec -Stream $ms
        $postBytes = $ms.Length - $preBytes - $duringBytes

        [System.IO.File]::WriteAllBytes($file, $ms.ToArray())
        Write-Host "  -> $file (pre=$preBytes during=$duringBytes post=$postBytes total=$($ms.Length) bytes)" -ForegroundColor Cyan

        "[$($cmd.name)] $($cmd.note)" | Out-File $manifestPath -Encoding UTF8 -Append
        "  trigger: $($cmd.triggerPath) | $($cmd.triggerBody)" | Out-File $manifestPath -Encoding UTF8 -Append
        "  bytes: pre=$preBytes during=$duringBytes post=$postBytes total=$($ms.Length)" | Out-File $manifestPath -Encoding UTF8 -Append
        "" | Out-File $manifestPath -Encoding UTF8 -Append

        $ms.Dispose()
        Start-Sleep -Seconds 2
    }

    Write-Host ""
    Write-Host "=== Done ===" -ForegroundColor Green
    Write-Host "Decode with: python hk32_stc8g_decoder.py $sessionDir\*.bin"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($sp -and $sp.IsOpen) { $sp.Close(); $sp.Dispose() }
}
