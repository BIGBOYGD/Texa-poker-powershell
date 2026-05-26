function New-PokerServerState {
    param(
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][ValidateRange(2, 6)][int]$MaxSeats = 6
    )

    $game = [pscustomobject]@{
        HandId = 0
        Street = 'Finished'
        Players = @()
        Deck = @()
        CommunityCards = @()
        DealerSeat = 0
        SmallBlind = 10
        BigBlind = 20
        CurrentBet = 0
        MinRaise = 20
        Pots = @()
        ActionSeat = $null
        Log = @()
        Mode = 'Host'
    }

    [pscustomobject]@{
        Port = $Port
        MaxSeats = $MaxSeats
        NextSeq = 1
        Clients = @()
        Game = $game
        Listener = $null
    }
}

function New-PokerClientConnectionState {
    param(
        [Parameter(Mandatory = $true)][string]$ConnectionId,
        [Parameter(Mandatory = $false)]$TcpClient = $null,
        [Parameter(Mandatory = $false)]$Reader = $null,
        [Parameter(Mandatory = $false)]$Writer = $null
    )

    [pscustomobject]@{
        ConnectionId = $ConnectionId
        TcpClient = $TcpClient
        Reader = $Reader
        Writer = $Writer
        PlayerId = $null
        Seat = $null
        Name = $null
        IsConnected = $true
    }
}

function New-ServerMessage {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $false)][string]$PlayerId = $null,
        [Parameter(Mandatory = $false)][Nullable[int]]$HandId = $null,
        [Parameter(Mandatory = $false)]$Payload = $null
    )

    $message = New-ProtocolMessage -Type $Type -Seq ([int]$Server.NextSeq) -PlayerId $PlayerId -HandId $HandId -Payload $Payload
    $Server.NextSeq = [int]$Server.NextSeq + 1
    return $message
}

function New-ServerErrorMessage {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Code = 'Error'
    )

    return New-ServerMessage -Server $Server -Type 'ErrorMessage' -Payload ([pscustomobject]@{
        Code = $Code
        Message = $Message
    })
}

function Get-NextAvailableSeat {
    param([Parameter(Mandatory = $true)]$Server)

    $occupied = @{}
    foreach ($player in @($Server.Game.Players)) {
        $occupied[[int]$player.Seat] = $true
    }

    for ($seat = 1; $seat -le [int]$Server.MaxSeats; $seat++) {
        if (-not $occupied.ContainsKey($seat)) {
            return $seat
        }
    }

    return $null
}

function Add-ServerClientIfMissing {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection
    )

    $existing = @($Server.Clients | Where-Object { $_.ConnectionId -eq $Connection.ConnectionId })
    if ($existing.Count -eq 0) {
        $Server.Clients = @($Server.Clients) + $Connection
    }
}

function Handle-JoinRequest {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)]$Message
    )

    $validation = Test-ProtocolMessage -Message $Message
    if (-not $validation.IsValid -or [string]$Message.Type -ne 'JoinRequest') {
        return New-ServerErrorMessage -Server $Server -Code 'InvalidJoinRequest' -Message 'Invalid JoinRequest message.'
    }

    if (-not (Test-ProtocolPropertyExists -Object $Message.Payload -Name 'Name') -or [string]::IsNullOrWhiteSpace([string]$Message.Payload.Name)) {
        return New-ServerErrorMessage -Server $Server -Code 'InvalidName' -Message 'Name is required.'
    }

    if ($null -ne $Connection.Seat) {
        return New-ServerErrorMessage -Server $Server -Code 'AlreadyJoined' -Message 'Connection has already joined.'
    }

    $seat = Get-NextAvailableSeat -Server $Server
    if ($null -eq $seat) {
        return New-ServerErrorMessage -Server $Server -Code 'TableFull' -Message 'Table is full.'
    }

    Add-ServerClientIfMissing -Server $Server -Connection $Connection

    $name = ([string]$Message.Payload.Name).Trim()
    $playerId = "P$seat"
    $player = New-PlayerState -Seat $seat -Name $name -Type 'RemoteHuman' -Chips 1000
    $player.ConnectionId = $Connection.ConnectionId
    $player | Add-Member -NotePropertyName PlayerId -NotePropertyValue $playerId
    $Server.Game.Players = @($Server.Game.Players) + $player

    $Connection.PlayerId = $playerId
    $Connection.Seat = $seat
    $Connection.Name = $name

    return New-ServerMessage -Server $Server -Type 'JoinAccepted' -PlayerId $playerId -HandId ([int]$Server.Game.HandId) -Payload ([pscustomobject]@{
        PlayerId = $playerId
        Seat = $seat
        Name = $name
        MaxSeats = [int]$Server.MaxSeats
    })
}

function Send-ProtocolMessage {
    param(
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)]$Message
    )

    if ($null -eq $Connection.Writer) {
        return
    }

    $Connection.Writer.WriteLine((ConvertTo-MessageJson -Message $Message))
}

function Accept-ClientConnection {
    param([Parameter(Mandatory = $true)]$Server)

    $tcpClient = $Server.Listener.AcceptTcpClient()
    $stream = $tcpClient.GetStream()
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $reader = New-Object System.IO.StreamReader($stream, $encoding)
    $writer = New-Object System.IO.StreamWriter($stream, $encoding)
    $writer.AutoFlush = $true

    $connectionId = "C$(@($Server.Clients).Count + 1)"
    $connection = New-PokerClientConnectionState -ConnectionId $connectionId -TcpClient $tcpClient -Reader $reader -Writer $writer
    Add-ServerClientIfMissing -Server $Server -Connection $connection
    return $connection
}

function Send-StateSnapshotToPlayer {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection
    )

    if ([string]::IsNullOrWhiteSpace([string]$Connection.PlayerId)) {
        return
    }

    $snapshot = New-StateSnapshotForPlayer -Game $Server.Game -PlayerId $Connection.PlayerId -Seq ([int]$Server.NextSeq)
    $Server.NextSeq = [int]$Server.NextSeq + 1
    Send-ProtocolMessage -Connection $Connection -Message $snapshot
}

function Broadcast-StateSnapshot {
    param([Parameter(Mandatory = $true)]$Server)

    foreach ($connection in @($Server.Clients | Where-Object { $_.IsConnected -and -not [string]::IsNullOrWhiteSpace([string]$_.PlayerId) })) {
        Send-StateSnapshotToPlayer -Server $Server -Connection $connection
    }
}

function Start-PokerServer {
    param(
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][ValidateRange(2, 6)][int]$MaxSeats = 6
    )

    $server = New-PokerServerState -Port $Port -MaxSeats $MaxSeats
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $server.Listener = $listener
    $listener.Start()

    Write-Host "Host listening on port $Port. Waiting for clients."
    try {
        while ($true) {
            $connection = Accept-ClientConnection -Server $server
            try {
                $line = $connection.Reader.ReadLine()
                $message = ConvertFrom-MessageJson -Json $line
                $response = Handle-JoinRequest -Server $server -Connection $connection -Message $message
                Send-ProtocolMessage -Connection $connection -Message $response
                if ($response.Type -eq 'JoinAccepted') {
                    Write-Host "Player $($connection.Name) joined as $($connection.PlayerId), seat $($connection.Seat)."
                    Send-StateSnapshotToPlayer -Server $server -Connection $connection
                } else {
                    Write-Host "Join failed: $($response.Payload.Message)"
                }
            } catch {
                $errorMessage = New-ServerErrorMessage -Server $server -Code 'JoinFailed' -Message $_.Exception.Message
                Send-ProtocolMessage -Connection $connection -Message $errorMessage
            }
        }
    } finally {
        $listener.Stop()
    }
}
