function New-PokerClientState {
    param(
        [Parameter(Mandatory = $false)][string]$Name = 'Player',
        [Parameter(Mandatory = $false)][string]$HostAddress = '127.0.0.1',
        [Parameter(Mandatory = $false)][int]$Port = 7777
    )

    [pscustomobject]@{
        Name = $Name
        HostAddress = $HostAddress
        Port = $Port
        PlayerId = $null
        Seat = $null
        TcpClient = $null
        Reader = $null
        Writer = $null
        LastMessageType = $null
        LastSnapshot = $null
        LastError = $null
    }
}

function New-JoinRequestMessage {
    param(
        [Parameter(Mandatory = $false)][int]$Seq = 1,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )

    return New-ProtocolMessage -Type 'JoinRequest' -Seq $Seq -Payload ([pscustomobject]@{
        Name = $Name
    })
}

function Connect-PokerHost {
    param([Parameter(Mandatory = $true)]$Client)

    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        $tcpClient.Connect([string]$Client.HostAddress, [int]$Client.Port)
        $tcpClient.ReceiveTimeout = 3000
        $stream = $tcpClient.GetStream()
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $reader = New-Object System.IO.StreamReader($stream, $encoding)
        $writer = New-Object System.IO.StreamWriter($stream, $encoding)
        $writer.AutoFlush = $true

        $Client.TcpClient = $tcpClient
        $Client.Reader = $reader
        $Client.Writer = $writer
        return $Client
    } catch {
        throw "Connect to Host failed: $($_.Exception.Message)"
    }
}

function Send-JoinRequest {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $false)][int]$Seq = 1
    )

    if ($null -eq $Client.Writer) {
        throw 'Client is not connected.'
    }

    $message = New-JoinRequestMessage -Seq $Seq -Name $Client.Name
    $Client.Writer.WriteLine((ConvertTo-MessageJson -Message $message))
    return $message
}

function Read-ServerMessage {
    param([Parameter(Mandatory = $true)]$Client)

    if ($null -eq $Client.Reader) {
        throw 'Client is not connected.'
    }

    $line = $Client.Reader.ReadLine()
    if ($null -eq $line) {
        return $null
    }

    return ConvertFrom-MessageJson -Json $line
}

function Show-StateSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $payload = $Snapshot.Payload
    Write-Host "View $($Snapshot.PlayerId) | Hand $($payload.HandId) | $($payload.Street) | Pot $($payload.Pot) | Bet $($payload.CurrentBet)"
    foreach ($player in @($payload.Players | Sort-Object Seat)) {
        $marker = if ($player.IsYou) { 'YOU' } else { '' }
        Write-Host ("{0} {1} {2} Chips:{3} Bet:{4} Status:{5}" -f $player.Seat, $player.Name, $marker, $player.Chips, $player.Bet, $player.Status)
    }
}

function Handle-ServerMessage {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$Message,
        [Parameter(Mandatory = $false)][switch]$Quiet
    )

    if ($null -eq $Message) {
        return
    }

    $Client.LastMessageType = [string]$Message.Type
    switch ([string]$Message.Type) {
        'JoinAccepted' {
            $Client.PlayerId = [string]$Message.Payload.PlayerId
            $Client.Seat = [int]$Message.Payload.Seat
            if (-not [string]::IsNullOrWhiteSpace([string]$Message.Payload.Name)) {
                $Client.Name = [string]$Message.Payload.Name
            }
            if (-not $Quiet) {
                Write-Host "Join accepted: $($Client.PlayerId), seat $($Client.Seat)."
            }
        }
        'StateSnapshot' {
            $Client.LastSnapshot = $Message.Payload
            if (-not $Quiet) {
                Show-StateSnapshot -Snapshot $Message
            }
        }
        'ErrorMessage' {
            $Client.LastError = [string]$Message.Payload.Message
            if (-not $Quiet) {
                Write-Host "Error: $($Client.LastError)"
            }
        }
        default {
            if (-not $Quiet) {
                Write-Host "Received message: $($Message.Type)"
            }
        }
    }
}

function Start-PokerClient {
    param(
        [Parameter(Mandatory = $false)][string]$HostAddress = '127.0.0.1',
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][string]$Name = 'Player',
        [Parameter(Mandatory = $false)][int]$MaxMessages = 2
    )

    $client = New-PokerClientState -Name $Name -HostAddress $HostAddress -Port $Port
    Connect-PokerHost -Client $client | Out-Null
    Send-JoinRequest -Client $client | Out-Null

    for ($i = 0; $i -lt $MaxMessages; $i++) {
        try {
            $message = Read-ServerMessage -Client $client
            if ($null -eq $message) {
                break
            }
            Handle-ServerMessage -Client $client -Message $message
        } catch {
            Write-Host "Read Host message failed: $($_.Exception.Message)"
            break
        }
    }

    return $client
}
