# ================== CONFIGURATION ==================
# Define your servers as an array. Add or remove entries as needed.
 $servers = @(
    @{
        Name     = "server1"     # A friendly name for the logs
        Host     = "192.168.#"
        Port     = 25575         # RCON port for server 1
        Password = "password"
    },
    @{
        Name     = server2"
        Host     = "192.168.#"   # Can be the same IP if using different ports
        Port     = 25576         # RCON port for server 2
        Password = "password"    # Can be the same or different password
    }
)

 $checkInterval  = 60            # In seconds

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
    }
    catch {
        Write-Host "Failed to set power plan: $_" -ForegroundColor Red
    }
}

# ================== MAIN LOOP ==================
Write-Host "Starting Multi-Server Minecraft RCON Power Plan Monitor..." -ForegroundColor Green
Write-Host "Monitoring $($servers.Count) servers every $checkInterval seconds.`n"

while ($true) {
    
    $anyPlayersOnline = $false

    foreach ($srv in $servers) {
        $response = Send-RconCommand -rconHost $srv.Host -rconPort $srv.Port -rconPassword $srv.Password -command "list"

        # CHECK 1: Did it fail to connect entirely?
        if ($null -eq $response) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$($srv.Name)] Server is OFFLINE or unreachable" -ForegroundColor Yellow
        }
        # CHECK 2: Did it connect but get a blank response? (Usually wrong password)
        elseif ([string]::IsNullOrWhiteSpace($response)) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$($srv.Name)] EMPTY RESPONSE: RCON Password is likely wrong." -ForegroundColor Red
        }
        # CHECK 3: Does the response contain a number? (Works with Vanilla, BungeeCord, and most plugins)
        elseif ($response -match "(\d+)") {
            
            # Grabs the FIRST number found in the response. 
            $online = [int]$Matches[1]

            if ($online -gt 0) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$($srv.Name)] Players online: $online" -ForegroundColor Green
                $anyPlayersOnline = $true
            }
            else {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$($srv.Name)] Players online: 0" -ForegroundColor DarkGray
            }
        }
        # CHECK 4: Fallback if it connects, gets text, but no numbers are found
        else {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$($srv.Name)] Unexpected response from server" -ForegroundColor Magenta
            Write-Host "Response text: $response" -ForegroundColor DarkGray
        }
    }

    # AFTER checking all servers, make the power decision
    if ($anyPlayersOnline) {
        Write-Host ">> Action: Players detected on at least one server. Switching to High Performance" -ForegroundColor Cyan
        Set-PowerPlan -guid $highPerf
    }
    else {
        Write-Host ">> Action: No players on ANY server. Switching to Power Saver" -ForegroundColor Gray
        Set-PowerPlan -guid $powerSave
    }

    Write-Host "---------------------------------------------------"
    Start-Sleep -Seconds $checkInterval
}
