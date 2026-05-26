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

function New-RemoteActionResult {
    param(
        [Parameter(Mandatory = $true)][bool]$Accepted,
        [Parameter(Mandatory = $false)]$Error = $null,
        [Parameter(Mandatory = $false)]$Player = $null,
        [Parameter(Mandatory = $false)][string]$Command = $null,
        [Parameter(Mandatory = $false)]$Amount = $null
    )

    [pscustomobject]@{
        Accepted = $Accepted
        Error = $Error
        Player = $Player
        Command = $Command
        Amount = $Amount
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

function Get-ServerConnectionByPlayerId {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId
    )

    $matches = @($Server.Clients | Where-Object { $_.PlayerId -eq $PlayerId } | Select-Object -First 1)
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Get-ServerPlayerByPlayerId {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId
    )

    $matches = @($Server.Game.Players | Where-Object { (Get-ProtocolPlayerId -Player $_) -eq $PlayerId } | Select-Object -First 1)
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function New-ActionRequestMessage {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection
    )

    if ([string]::IsNullOrWhiteSpace([string]$Connection.PlayerId)) {
        return New-ServerErrorMessage -Server $Server -Code 'NoPlayer' -Message 'Connection has no joined player.'
    }

    $player = Get-ServerPlayerByPlayerId -Server $Server -PlayerId ([string]$Connection.PlayerId)
    if ($null -eq $player) {
        return New-ServerErrorMessage -Server $Server -Code 'PlayerNotFound' -Message 'Player was not found.'
    }

    $legalActions = @(ConvertTo-NetworkLegalActions -Game $Server.Game -Seat ([int]$player.Seat))
    $toCall = [Math]::Max(0, [int]$Server.Game.CurrentBet - [int]$player.StreetBet)
    return New-ServerMessage -Server $Server -Type 'ActionRequest' -PlayerId ([string]$Connection.PlayerId) -HandId ([int]$Server.Game.HandId) -Payload ([pscustomobject]@{
        HandId = [int]$Server.Game.HandId
        Seat = [int]$player.Seat
        ActionSeat = $Server.Game.ActionSeat
        ToCall = $toCall
        LegalActions = @($legalActions)
    })
}

function Test-RemotePlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)]$Message
    )

    $validation = Test-ProtocolMessage -Message $Message
    if (-not $validation.IsValid -or [string]$Message.Type -ne 'PlayerAction') {
        $error = New-ServerErrorMessage -Server $Server -Code 'InvalidPlayerAction' -Message 'Invalid PlayerAction message.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    if ([string]::IsNullOrWhiteSpace([string]$Connection.PlayerId)) {
        $error = New-ServerErrorMessage -Server $Server -Code 'NoPlayer' -Message 'Connection has no joined player.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    if ([string]$Message.PlayerId -ne [string]$Connection.PlayerId) {
        $error = New-ServerErrorMessage -Server $Server -Code 'PlayerMismatch' -Message 'PlayerAction does not match this connection.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    $player = Get-ServerPlayerByPlayerId -Server $Server -PlayerId ([string]$Connection.PlayerId)
    if ($null -eq $player -or [int]$player.Seat -ne [int]$Connection.Seat) {
        $error = New-ServerErrorMessage -Server $Server -Code 'PlayerNotFound' -Message 'Player was not found for this connection.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    if ($null -eq $Message.HandId -or [int]$Message.HandId -ne [int]$Server.Game.HandId) {
        $error = New-ServerErrorMessage -Server $Server -Code 'HandMismatch' -Message 'PlayerAction belongs to a stale or unknown hand.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    if ($null -eq $Server.Game.ActionSeat -or [int]$Server.Game.ActionSeat -ne [int]$player.Seat) {
        $error = New-ServerErrorMessage -Server $Server -Code 'NotYourTurn' -Message 'It is not this player turn.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    $command = ([string]$Message.Payload.Command).ToLowerInvariant()
    $amount = $null
    if ((Test-ProtocolPropertyExists -Object $Message.Payload -Name 'Amount') -and $null -ne $Message.Payload.Amount) {
        $amount = [int]$Message.Payload.Amount
    }

    if (-not (Test-PlayerActionLegal -Game $Server.Game -Seat ([int]$player.Seat) -Command $command -Amount $amount)) {
        $error = New-ServerErrorMessage -Server $Server -Code 'IllegalAction' -Message 'Action is not legal in current state.'
        return New-RemoteActionResult -Accepted $false -Error $error
    }

    return New-RemoteActionResult -Accepted $true -Player $player -Command $command -Amount $amount
}

function Apply-RemotePlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)]$Message
    )

    $result = Test-RemotePlayerAction -Server $Server -Connection $Connection -Message $Message
    if (-not $result.Accepted) {
        return $result
    }

    Apply-PlayerAction -Game $Server.Game -Seat ([int]$result.Player.Seat) -Command ([string]$result.Command) -Amount $result.Amount
    Set-NextActionSeat -Game $Server.Game
    Broadcast-StateSnapshot -Server $Server

    return $result
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

function Send-ActionRequest {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection
    )

    $message = New-ActionRequestMessage -Server $Server -Connection $Connection
    Send-ProtocolMessage -Connection $Connection -Message $message
    return $message
}

function Broadcast-StateSnapshot {
    param([Parameter(Mandatory = $true)]$Server)

    foreach ($connection in @($Server.Clients | Where-Object { $_.IsConnected -and -not [string]::IsNullOrWhiteSpace([string]$_.PlayerId) })) {
        Send-StateSnapshotToPlayer -Server $Server -Connection $connection
    }
}

function New-HandResultMessage {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection
    )

    $seq = [int]$Server.NextSeq
    $snapshot = New-StateSnapshotForPlayer -Game $Server.Game -PlayerId $Connection.PlayerId -Seq $seq
    $message = New-ProtocolMessage -Type 'HandResult' -Seq $seq -PlayerId $Connection.PlayerId -HandId ([int]$Server.Game.HandId) -Payload $snapshot.Payload
    $Server.NextSeq = [int]$Server.NextSeq + 1
    return $message
}

function Broadcast-HandResult {
    param([Parameter(Mandatory = $true)]$Server)

    foreach ($connection in @($Server.Clients | Where-Object { $_.IsConnected -and -not [string]::IsNullOrWhiteSpace([string]$_.PlayerId) })) {
        $message = New-HandResultMessage -Server $Server -Connection $connection
        Send-ProtocolMessage -Connection $connection -Message $message
    }
}

function Wait-RemotePlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Connection
    )

    while ($true) {
        $line = $Connection.Reader.ReadLine()
        if ($null -eq $line) {
            throw 'Client disconnected while waiting for PlayerAction.'
        }

        $message = ConvertFrom-MessageJson -Json $line
        $result = Test-RemotePlayerAction -Server $Server -Connection $Connection -Message $message
        if ($result.Accepted) {
            return [pscustomobject]@{
                Command = $result.Command
                Amount = $result.Amount
            }
        }

        Send-ProtocolMessage -Connection $Connection -Message $result.Error
    }
}

function Invoke-NetworkHand {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $false)][int]$MaxTurns = 500
    )

    $remoteProvider = {
        param($Game, $Player)

        $playerId = Get-ProtocolPlayerId -Player $Player
        $connection = Get-ServerConnectionByPlayerId -Server $Server -PlayerId $playerId
        if ($null -eq $connection) {
            throw "Remote connection for $playerId was not found."
        }

        Send-ActionRequest -Server $Server -Connection $connection | Out-Null
        return Wait-RemotePlayerAction -Server $Server -Connection $connection
    }

    Invoke-LocalHand -Game $Server.Game -ActionProvider $remoteProvider -MaxTurns $MaxTurns
    Broadcast-HandResult -Server $Server
}

function Start-PokerServer {
    param(
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][ValidateRange(2, 6)][int]$MaxSeats = 6,
        [Parameter(Mandatory = $false)][ValidateRange(0, 5)][int]$BotCount = 0
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
                    if ($BotCount -gt 0) {
                        Add-ServerBots -Server $server -BotCount $BotCount
                    }
                    if (@($server.Game.Players | Where-Object { [int]$_.Chips -gt 0 }).Count -ge 2) {
                        Broadcast-StateSnapshot -Server $server
                        Invoke-NetworkHand -Server $server
                    }
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

function Add-ServerBots {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $false)][ValidateRange(0, 5)][int]$BotCount = 0
    )

    $existingBots = @($Server.Game.Players | Where-Object { $_.Type -eq 'Bot' }).Count
    $toAdd = [Math]::Max(0, $BotCount - $existingBots)
    for ($i = 0; $i -lt $toAdd; $i++) {
        $seat = Get-NextAvailableSeat -Server $Server
        if ($null -eq $seat) {
            return
        }

        $bot = New-PlayerState -Seat $seat -Name "Bot-$seat" -Type 'Bot' -Chips 1000
        $bot | Add-Member -NotePropertyName PlayerId -NotePropertyValue "P$seat"
        $Server.Game.Players = @($Server.Game.Players) + $bot
    }
}
