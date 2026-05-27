function New-PokerHttpServerState {
    param(
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][ValidateRange(2, 6)][int]$MaxSeats = 6,
        [Parameter(Mandatory = $false)][ValidateRange(0, 5)][int]$BotCount = 0,
        [Parameter(Mandatory = $false)][int]$ClientTimeoutSeconds = 8
    )

    $base = New-PokerServerState -Port $Port -MaxSeats $MaxSeats
    $base | Add-Member -NotePropertyName Sessions -NotePropertyValue @()
    $base | Add-Member -NotePropertyName BotCount -NotePropertyValue $BotCount
    $base | Add-Member -NotePropertyName ClientTimeoutSeconds -NotePropertyValue $ClientTimeoutSeconds
    $base | Add-Member -NotePropertyName WaitingActionPlayerId -NotePropertyValue $null
    $base | Add-Member -NotePropertyName PendingActions -NotePropertyValue @{}
    $base | Add-Member -NotePropertyName IsInHand -NotePropertyValue $false
    $base | Add-Member -NotePropertyName IsPaused -NotePropertyValue $false
    $base | Add-Member -NotePropertyName PauseMessage -NotePropertyValue ''
    $base | Add-Member -NotePropertyName LastHandFinishedUtc -NotePropertyValue ([DateTime]::MinValue)
    return $base
}

function New-HttpRenderText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function New-HttpSessionToken {
    return ([guid]::NewGuid().ToString('N'))
}

function Get-HttpSession {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $false)][string]$PlayerId = $null,
        [Parameter(Mandatory = $false)][string]$Token = $null,
        [Parameter(Mandatory = $false)][string]$Name = $null
    )

    $matches = @($Server.Sessions | Where-Object {
        $ok = $true
        if (-not [string]::IsNullOrWhiteSpace($PlayerId)) { $ok = $ok -and [string]$_.PlayerId -eq $PlayerId }
        if (-not [string]::IsNullOrWhiteSpace($Token)) { $ok = $ok -and [string]$_.Token -eq $Token }
        if (-not [string]::IsNullOrWhiteSpace($Name)) { $ok = $ok -and [string]$_.Name -eq $Name }
        $ok
    } | Select-Object -First 1)

    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Test-HttpSessionValid {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][string]$Token
    )

    return $null -ne (Get-HttpSession -Server $Server -PlayerId $PlayerId -Token $Token)
}

function Get-HttpConnectedHumanSessions {
    param([Parameter(Mandatory = $true)]$Server)

    return @($Server.Sessions | Where-Object {
        $_.IsConnected -and -not (Test-HttpSessionTimedOut -Server $Server -Session $_)
    })
}

function Get-HttpRequiredHumanCount {
    param([Parameter(Mandatory = $true)]$Server)

    if ([int]$Server.BotCount -le 0) {
        return 2
    }

    return [Math]::Max(1, [int]$Server.MaxSeats - [int]$Server.BotCount)
}

function Get-HttpSeatedHumanSessions {
    param([Parameter(Mandatory = $true)]$Server)

    $sessions = @()
    foreach ($session in @($Server.Sessions)) {
        $player = Get-ServerPlayerByPlayerId -Server $Server -PlayerId ([string]$session.PlayerId)
        if ($null -eq $player) {
            continue
        }
        if ([string]$player.Type -ne 'RemoteHuman') {
            continue
        }
        if ([int]$player.Chips -le 0) {
            continue
        }

        $sessions += $session
    }

    return $sessions
}

function Get-HttpOfflineHumanSessions {
    param([Parameter(Mandatory = $true)]$Server)

    $offline = @()
    foreach ($session in @(Get-HttpSeatedHumanSessions -Server $Server)) {
        $isCurrentDecisionPlayer = -not [string]::IsNullOrWhiteSpace([string]$Server.WaitingActionPlayerId) -and
            [string]$session.PlayerId -eq [string]$Server.WaitingActionPlayerId

        if ((-not $isCurrentDecisionPlayer) -and (Test-HttpSessionTimedOut -Server $Server -Session $session)) {
            $session.IsConnected = $false
        }
        if (-not [bool]$session.IsConnected) {
            $offline += $session
        }
    }

    return $offline
}

function Get-HttpInsufficientHumanPauseMessage {
    param([Parameter(Mandatory = $false)][int]$ConnectedHumanCount = 0)

    if ([int]$ConnectedHumanCount -le 0) {
        return New-HttpRenderText @(0x771f, 0x4eba, 0x73a9, 0x5bb6, 0x4e0d, 0x8db3, 0xff0c, 0x7b49, 0x5f85, 0x771f, 0x4eba, 0x52a0, 0x5165, 0x6216, 0x91cd, 0x65b0, 0x8fde, 0x63a5, 0x540e, 0x518d, 0x5f00, 0x59cb, 0x4e0b, 0x4e00, 0x5c40)
    }

    return New-HttpRenderText @(0x771f, 0x4eba, 0x73a9, 0x5bb6, 0x4e0d, 0x8db3, 0xff0c, 0x7b49, 0x5f85, 0x771f, 0x4eba, 0x52a0, 0x5165, 0x6216, 0x91cd, 0x65b0, 0x8fde, 0x63a5, 0x540e, 0x518d, 0x5f00, 0x59cb, 0x4e0b, 0x4e00, 0x5c40)
}

function Update-HttpPauseState {
    param([Parameter(Mandatory = $true)]$Server)

    $offline = @(Get-HttpOfflineHumanSessions -Server $Server)
    $connectedHumans = @(Get-HttpConnectedHumanSessions -Server $Server)
    $isBetweenHands = (-not [bool]$Server.IsInHand) -and ([string]$Server.Game.Street -eq 'Finished')
    if ($isBetweenHands -and $connectedHumans.Count -lt (Get-HttpRequiredHumanCount -Server $Server)) {
        $Server.IsPaused = $true
        $Server.PauseMessage = Get-HttpInsufficientHumanPauseMessage -ConnectedHumanCount $connectedHumans.Count
    } elseif ($offline.Count -gt 0) {
        $Server.IsPaused = $true
        $Server.PauseMessage = New-HttpRenderText @(0x724c, 0x5c40, 0x6682, 0x505c, 0xff0c, 0x7b49, 0x5f85, 0x79bb, 0x7ebf, 0x73a9, 0x5bb6, 0x91cd, 0x65b0, 0x8fde, 0x63a5)
    } else {
        $Server.IsPaused = $false
        $Server.PauseMessage = ''
    }

    return [bool]$Server.IsPaused
}

function Reset-HttpTableIfConnectedHumansAreOut {
    param([Parameter(Mandatory = $true)]$Server)

    $connectedHumans = @(Get-HttpConnectedHumanSessions -Server $Server)
    if ($connectedHumans.Count -lt (Get-HttpRequiredHumanCount -Server $Server)) {
        return $false
    }

    $connectedHumanPlayers = @()
    foreach ($session in $connectedHumans) {
        $player = Get-ServerPlayerByPlayerId -Server $Server -PlayerId ([string]$session.PlayerId)
        if ($null -ne $player -and [string]$player.Type -eq 'RemoteHuman') {
            $connectedHumanPlayers += $player
        }
    }

    if ($connectedHumanPlayers.Count -eq 0) {
        return $false
    }
    if (@($connectedHumanPlayers | Where-Object { [int]$_.Chips -gt 0 }).Count -gt 0) {
        return $false
    }

    foreach ($player in @($Server.Game.Players)) {
        $player.Chips = 1000
        $player.HoleCards = @()
        $player.StreetBet = 0
        $player.TotalBetThisHand = 0
        $player.HasActedThisRound = $false
        $player.Status = 'Waiting'
    }
    $Server.Game.CommunityCards = @()
    $Server.Game.Pots = @()
    $Server.Game.CurrentBet = 0
    $Server.Game.MinRaise = [int]$Server.Game.BigBlind
    $Server.Game.ActionSeat = $null
    $Server.PauseMessage = ''
    $Server.IsPaused = $false
    return $true
}

function New-HttpPausedAction {
    return [pscustomobject]@{
        Command = '__paused'
        Amount = $null
        IsPaused = $true
    }
}

function Test-HttpCanStartNextHand {
    param([Parameter(Mandatory = $true)]$Server)

    if (Update-HttpPauseState -Server $Server) {
        return $false
    }

    if ([bool]$Server.IsInHand -or [string]$Server.Game.Street -ne 'Finished') {
        return $false
    }

    Reset-HttpTableIfConnectedHumansAreOut -Server $Server | Out-Null

    $playersWithChips = @($Server.Game.Players | Where-Object { [int]$_.Chips -gt 0 })
    if ($playersWithChips.Count -lt 2) {
        return $false
    }

    $connectedHumans = @(Get-HttpConnectedHumanSessions -Server $Server)
    return $connectedHumans.Count -ge (Get-HttpRequiredHumanCount -Server $Server)
}

function Touch-HttpSession {
    param([Parameter(Mandatory = $true)]$Session)

    $Session.LastSeenUtc = [DateTime]::UtcNow
    $Session.IsConnected = $true
}

function New-HttpErrorMessage {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return New-ServerErrorMessage -Server $Server -Code $Code -Message $Message
}

function Invoke-HttpJoin {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )

    $trimmedName = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedName)) {
        return New-HttpErrorMessage -Server $Server -Code 'InvalidName' -Message 'Name is required.'
    }

    $existingSession = Get-HttpSession -Server $Server -Name $trimmedName
    if ($null -ne $existingSession) {
        $existingSession.Token = New-HttpSessionToken
        Touch-HttpSession -Session $existingSession
        return New-ServerMessage -Server $Server -Type 'JoinAccepted' -PlayerId ([string]$existingSession.PlayerId) -HandId ([int]$Server.Game.HandId) -Payload ([pscustomobject]@{
            PlayerId = [string]$existingSession.PlayerId
            Seat = [int]$existingSession.Seat
            Name = [string]$existingSession.Name
            Token = [string]$existingSession.Token
            Transport = 'HttpPolling'
            MaxSeats = [int]$Server.MaxSeats
        })
    }

    $connection = New-PokerClientConnectionState -ConnectionId "H$(@($Server.Sessions).Count + 1)"
    $joinMessage = New-ProtocolMessage -Type 'JoinRequest' -Seq ([int]$Server.NextSeq) -Payload ([pscustomobject]@{
        Name = $trimmedName
    })
    $response = Handle-JoinRequest -Server $Server -Connection $connection -Message $joinMessage
    if ([string]$response.Type -ne 'JoinAccepted') {
        return $response
    }

    if ([int]$Server.Game.HandId -gt 0 -and [string]$Server.Game.Street -ne 'Finished') {
        $joinedPlayer = Get-ServerPlayerByPlayerId -Server $Server -PlayerId ([string]$response.Payload.PlayerId)
        if ($null -ne $joinedPlayer) {
            $joinedPlayer.Status = 'Out'
            $joinedPlayer.HoleCards = @()
        }
    }

    $token = New-HttpSessionToken
    $session = [pscustomobject]@{
        PlayerId = [string]$response.Payload.PlayerId
        Seat = [int]$response.Payload.Seat
        Name = $trimmedName
        Token = $token
        LastSeenUtc = [DateTime]::UtcNow
        IsConnected = $true
    }
    $Server.Sessions = @($Server.Sessions) + $session

    if ([int]$Server.BotCount -gt 0) {
        Add-ServerBots -Server $Server -BotCount ([int]$Server.BotCount)
    }

    Update-HttpPauseState -Server $Server | Out-Null

    $response.Payload | Add-Member -NotePropertyName Token -NotePropertyValue $token
    $response.Payload | Add-Member -NotePropertyName Transport -NotePropertyValue 'HttpPolling'
    return $response
}

function New-HttpStateSnapshotForPlayer {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][int]$Seq
    )

    Update-HttpPauseState -Server $Server | Out-Null

    $snapshot = New-StateSnapshotForPlayer -Game $Server.Game -PlayerId $PlayerId -Seq $Seq
    $targetPlayer = Get-ServerPlayerByPlayerId -Server $Server -PlayerId $PlayerId
    $waitingPlayer = if ($null -ne $Server.Game.ActionSeat) {
        Get-PlayerBySeat -Game $Server.Game -Seat ([int]$Server.Game.ActionSeat)
    } else {
        $null
    }
    $waitingPlayerId = if ($null -ne $waitingPlayer) { Get-ProtocolPlayerId -Player $waitingPlayer } else { $null }
    $waitingPlayerName = if ($null -ne $waitingPlayer) { [string]$waitingPlayer.Name } else { $null }

    $snapshot.Payload | Add-Member -NotePropertyName IsPaused -NotePropertyValue ([bool]$Server.IsPaused) -Force
    $snapshot.Payload | Add-Member -NotePropertyName PauseMessage -NotePropertyValue ([string]$Server.PauseMessage) -Force
    $snapshot.Payload | Add-Member -NotePropertyName WaitingPlayerId -NotePropertyValue $waitingPlayerId -Force
    $snapshot.Payload | Add-Member -NotePropertyName WaitingPlayerName -NotePropertyValue $waitingPlayerName -Force

    $isTargetTurn = $false
    if ($null -ne $targetPlayer -and $null -ne $Server.Game.ActionSeat) {
        $isTargetTurn = [int]$targetPlayer.Seat -eq [int]$Server.Game.ActionSeat
    }
    if ([bool]$Server.IsPaused -or -not $isTargetTurn) {
        $snapshot.Payload.LegalActions = @()
    }

    return $snapshot
}

function Invoke-HttpState {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $session = Get-HttpSession -Server $Server -PlayerId $PlayerId -Token $Token
    if ($null -eq $session) {
        return New-HttpErrorMessage -Server $Server -Code 'InvalidSession' -Message 'Session was not found.'
    }

    Touch-HttpSession -Session $session
    return New-HttpStateSnapshotForPlayer -Server $Server -PlayerId $PlayerId -Seq ([int]$Server.NextSeq)
}

function Invoke-HttpAction {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)]$Amount = $null
    )

    $session = Get-HttpSession -Server $Server -PlayerId $PlayerId -Token $Token
    if ($null -eq $session) {
        return New-HttpErrorMessage -Server $Server -Code 'InvalidSession' -Message 'Session was not found.'
    }

    Touch-HttpSession -Session $session
    if (Update-HttpPauseState -Server $Server) {
        return New-HttpErrorMessage -Server $Server -Code 'Paused' -Message ([string]$Server.PauseMessage)
    }

    if ([string]$Server.WaitingActionPlayerId -ne [string]$PlayerId) {
        return New-HttpErrorMessage -Server $Server -Code 'NotYourTurn' -Message 'It is not this player turn.'
    }

    $payload = [pscustomobject]@{ Command = ([string]$Command).ToLowerInvariant() }
    if ($null -ne $Amount) {
        $payload | Add-Member -NotePropertyName Amount -NotePropertyValue ([int]$Amount)
    }

    $connection = New-PokerClientConnectionState -ConnectionId "HTTP-$PlayerId"
    $connection.PlayerId = $PlayerId
    $connection.Seat = [int]$session.Seat
    $message = New-ProtocolMessage -Type 'PlayerAction' -Seq ([int]$Server.NextSeq) -PlayerId $PlayerId -HandId ([int]$Server.Game.HandId) -Payload $payload
    $result = Test-RemotePlayerAction -Server $Server -Connection $connection -Message $message
    if (-not $result.Accepted) {
        return $result.Error
    }

    $Server.PendingActions[$PlayerId] = [pscustomobject]@{
        Command = [string]$result.Command
        Amount = $result.Amount
    }

    return New-ServerMessage -Server $Server -Type 'ActionAccepted' -PlayerId $PlayerId -HandId ([int]$Server.Game.HandId) -Payload ([pscustomobject]@{
        Command = [string]$result.Command
        Amount = $result.Amount
    })
}

function Invoke-HttpLeave {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $session = Get-HttpSession -Server $Server -PlayerId $PlayerId -Token $Token
    if ($null -eq $session) {
        return New-HttpErrorMessage -Server $Server -Code 'InvalidSession' -Message 'Session was not found.'
    }

    $session.IsConnected = $false
    $session.LastSeenUtc = [DateTime]::UtcNow.AddYears(-1)
    Update-HttpPauseState -Server $Server | Out-Null
    return New-ServerMessage -Server $Server -Type 'LeaveAccepted' -PlayerId $PlayerId -HandId ([int]$Server.Game.HandId) -Payload ([pscustomobject]@{
        PlayerId = $PlayerId
    })
}

function Test-HttpSessionTimedOut {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Session
    )

    $age = [DateTime]::UtcNow - [DateTime]$Session.LastSeenUtc
    return $age.TotalSeconds -ge [int]$Server.ClientTimeoutSeconds
}

function Wait-HttpPlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $false)][Nullable[int]]$TimeoutMilliseconds = $null
    )

    $playerId = Get-ProtocolPlayerId -Player $Player
    $Server.WaitingActionPlayerId = $playerId
    $hasDeadline = $null -ne $TimeoutMilliseconds
    $deadline = if ($hasDeadline) { [DateTime]::UtcNow.AddMilliseconds([int]$TimeoutMilliseconds) } else { [DateTime]::MaxValue }

    try {
        while ($true) {
            Invoke-HttpHostPump -Server $Server -TimeoutMilliseconds 25 | Out-Null

            if (Update-HttpPauseState -Server $Server) {
                if ($hasDeadline -and [DateTime]::UtcNow -ge $deadline) {
                    return New-HttpPausedAction
                }
                Start-Sleep -Milliseconds 25
                continue
            }

            if ($Server.PendingActions.ContainsKey($playerId)) {
                $action = $Server.PendingActions[$playerId]
                $Server.PendingActions.Remove($playerId)
                return $action
            }

            $session = Get-HttpSession -Server $Server -PlayerId $playerId
            if ($null -eq $session) {
                Update-HttpPauseState -Server $Server | Out-Null
                continue
            }

            if ($hasDeadline -and [DateTime]::UtcNow -ge $deadline) {
                return [pscustomobject]@{ Command = '__timeout'; Amount = $null; IsPaused = $false }
            }

            Start-Sleep -Milliseconds 25
        }
    } finally {
        $Server.WaitingActionPlayerId = $null
    }
}

function Invoke-HttpNetworkHand {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $false)][int]$MaxTurns = 500
    )

    $Server.IsInHand = $true
    try {
        $remoteProvider = {
            param($Game, $Player)
            return Wait-HttpPlayerAction -Server $Server -Player $Player
        }

        Invoke-LocalHand -Game $Server.Game -ActionProvider $remoteProvider -MaxTurns $MaxTurns
    } finally {
        $Server.IsInHand = $false
        $Server.LastHandFinishedUtc = [DateTime]::UtcNow
    }
}

function Read-SimpleHttpRequest {
    param([Parameter(Mandatory = $true)]$TcpClient)

    $stream = $TcpClient.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 1024, $true)
    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $parts = $requestLine.Split(' ')
    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq '') {
            break
        }
        $colon = $line.IndexOf(':')
        if ($colon -gt 0) {
            $headers[$line.Substring(0, $colon).Trim().ToLowerInvariant()] = $line.Substring($colon + 1).Trim()
        }
    }

    $body = ''
    if ($headers.ContainsKey('content-length')) {
        $length = [int]$headers['content-length']
        if ($length -gt 0) {
            $buffer = New-Object char[] $length
            $read = $reader.ReadBlock($buffer, 0, $length)
            $body = -join $buffer[0..($read - 1)]
        }
    }

    return [pscustomobject]@{
        Method = $parts[0]
        Target = $parts[1]
        Headers = $headers
        Body = $body
    }
}

function ConvertFrom-HttpQuery {
    param([Parameter(Mandatory = $true)][string]$Target)

    $query = @{}
    $question = $Target.IndexOf('?')
    if ($question -lt 0) {
        return $query
    }

    foreach ($pair in $Target.Substring($question + 1).Split('&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $parts = $pair.Split('=', 2)
        $key = [System.Uri]::UnescapeDataString($parts[0])
        $value = if ($parts.Count -gt 1) { [System.Uri]::UnescapeDataString($parts[1]) } else { '' }
        $query[$key] = $value
    }

    return $query
}

function Get-SimpleHttpPath {
    param([Parameter(Mandatory = $true)][string]$Target)

    $question = $Target.IndexOf('?')
    if ($question -lt 0) {
        return $Target
    }
    return $Target.Substring(0, $question)
}

function Write-SimpleHttpJsonResponse {
    param(
        [Parameter(Mandatory = $true)]$TcpClient,
        [Parameter(Mandatory = $true)]$Body,
        [Parameter(Mandatory = $false)][int]$StatusCode = 200
    )

    $json = ConvertTo-MessageJson -Message $Body
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $statusText = if ($StatusCode -eq 200) { 'OK' } else { 'Error' }
    $header = "HTTP/1.1 $StatusCode $statusText`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $stream = $TcpClient.GetStream()
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

function Invoke-HttpRoute {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)]$Request
    )

    $path = Get-SimpleHttpPath -Target ([string]$Request.Target)
    $query = ConvertFrom-HttpQuery -Target ([string]$Request.Target)
    $body = if ([string]::IsNullOrWhiteSpace([string]$Request.Body)) { [pscustomobject]@{} } else { ConvertFrom-MessageJson -Json ([string]$Request.Body) }

    switch ($path) {
        '/join' {
            return Invoke-HttpJoin -Server $Server -Name ([string]$body.Name)
        }
        '/state' {
            return Invoke-HttpState -Server $Server -PlayerId ([string]$query['playerId']) -Token ([string]$query['token'])
        }
        '/action' {
            $amount = if (Test-ProtocolPropertyExists -Object $body -Name 'Amount') { $body.Amount } else { $null }
            return Invoke-HttpAction -Server $Server -PlayerId ([string]$body.PlayerId) -Token ([string]$body.Token) -Command ([string]$body.Command) -Amount $amount
        }
        '/leave' {
            return Invoke-HttpLeave -Server $Server -PlayerId ([string]$body.PlayerId) -Token ([string]$body.Token)
        }
        default {
            return New-HttpErrorMessage -Server $Server -Code 'NotFound' -Message "Unknown route '$path'."
        }
    }
}

function Invoke-HttpHostPump {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $false)][int]$TimeoutMilliseconds = 50
    )

    if ($null -eq $Server.Listener) {
        Start-Sleep -Milliseconds $TimeoutMilliseconds
        return $false
    }

    if (-not $Server.Listener.Pending()) {
        Start-Sleep -Milliseconds $TimeoutMilliseconds
        return $false
    }

    $tcpClient = $Server.Listener.AcceptTcpClient()
    try {
        $request = Read-SimpleHttpRequest -TcpClient $tcpClient
        if ($null -eq $request) {
            return $true
        }
        $response = Invoke-HttpRoute -Server $Server -Request $request
        Write-SimpleHttpJsonResponse -TcpClient $tcpClient -Body $response
    } catch {
        $errorMessage = New-HttpErrorMessage -Server $Server -Code 'HttpFailed' -Message $_.Exception.Message
        Write-SimpleHttpJsonResponse -TcpClient $tcpClient -Body $errorMessage -StatusCode 500
    } finally {
        $tcpClient.Close()
    }

    return $true
}

function Start-PokerHttpServer {
    param(
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][ValidateRange(2, 6)][int]$MaxSeats = 6,
        [Parameter(Mandatory = $false)][ValidateRange(0, 5)][int]$BotCount = 0
    )

    $server = New-PokerHttpServerState -Port $Port -MaxSeats $MaxSeats -BotCount $BotCount
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    $server.Listener = $listener
    $listener.Start()

    Write-Host "HTTP Host listening on port $Port. Waiting for clients."
    try {
        while ($true) {
            Invoke-HttpHostPump -Server $server -TimeoutMilliseconds 50 | Out-Null
            $recentlyFinished = (([DateTime]::UtcNow - [DateTime]$server.LastHandFinishedUtc).TotalSeconds -lt 3)
            if (-not $recentlyFinished -and (Test-HttpCanStartNextHand -Server $server)) {
                Invoke-HttpNetworkHand -Server $server
            }
        }
    } finally {
        $listener.Stop()
    }
}
