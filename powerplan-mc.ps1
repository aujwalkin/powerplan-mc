# ================== CONFIGURATION ==================
$rconHost       = "192.168.#"           # Your server IP or hostname
$rconPort       = 25575                 # RCON port from server.properties
$rconPassword   = "password"            # Your RCON password
$checkInterval  = 60                    # Seconds between checks

$highPerf       = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$powerSave      = "a1841308-3541-4fab-bc81-f71556f20b4a"
# ===================================================

function Send-RconCommand {
    param (
        [string]$rconHost,
        [int]$rconPort,
        [string]$rconPassword,
        [string]$command
    )

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($rconHost, $rconPort)
        $stream = $tcp.GetStream()

        function Write-RconPacket($id, $type, $body) {
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $length = 10 + $bodyBytes.Length
            $packet = New-Object byte[] (4 + $length)

            [BitConverter]::GetBytes([int32]$length).CopyTo($packet, 0)
            [BitConverter]::GetBytes([int32]$id).CopyTo($packet, 4)
            [BitConverter]::GetBytes([int32]$type).CopyTo($packet, 8)
            $bodyBytes.CopyTo($packet, 12)

            $packet[$packet.Length - 2] = 0
            $packet[$packet.Length - 1] = 0

            $stream.Write($packet, 0, $packet.Length)
        }

        # Authenticate
        Write-RconPacket 1 3 $rconPassword
        $buf = New-Object byte[] 4096
        $stream.Read($buf, 0, $buf.Length) | Out-Null

        # Send command
        Write-RconPacket 2 2 $command
        $bytesRead = $stream.Read($buf, 0, $buf.Length)

        $tcp.Close()

        if ($bytesRead -gt 12) {
            return [System.Text.Encoding]::UTF8.GetString($buf, 12, $bytesRead - 14).Trim()
        }

        return $null
    }
    catch {
        return $null
    }
}

function Set-PowerPlan {
    param (
        [string]$guid
    )

    try {
        powercfg /setactive $guid | Out-Null
        Write-Host "Power plan switched to: $guid" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Failed to set power plan: $_" -ForegroundColor Red
    }
}

# ================== MAIN LOOP ==================
Write-Host "Starting Minecraft RCON Power Plan Monitor..." -ForegroundColor Green
Write-Host "Checking every $checkInterval seconds.`n"

while ($true) {

    $response = Send-RconCommand -rconHost $rconHost -rconPort $rconPort -rconPassword $rconPassword -command "list"

    if ($null -eq $response) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Server is OFFLINE or unreachable" -ForegroundColor Yellow
        Write-Host "Switching to Power Saver plan" -ForegroundColor Gray
        Set-PowerPlan -guid $powerSave
    }
    elseif ($response -match "There are (\d+) of a max") {
        $online = [int]$Matches[1]
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Players online: $online" -ForegroundColor Green

        if ($online -gt 0) {
            Write-Host "Switching to High Performance" -ForegroundColor Cyan
            Set-PowerPlan -guid $highPerf
        }
        else {
            Write-Host "No players online → Switching to Power Saver" -ForegroundColor Gray
            Set-PowerPlan -guid $powerSave
        }
    }
    else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Unexpected response from server" -ForegroundColor Magenta
        Write-Host "Response: $response" -ForegroundColor DarkGray
        Set-PowerPlan -guid $powerSave
    }

    Start-Sleep -Seconds $checkInterval
}
