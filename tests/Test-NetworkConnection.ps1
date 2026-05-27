. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\HandAdvisor.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\UI\CommandParser.ps1"
. "$PSScriptRoot\..\src\Network\Protocol.ps1"
. "$PSScriptRoot\..\src\Network\Server.ps1"
. "$PSScriptRoot\..\src\Network\Client.ps1"

function New-NetworkConnectionTestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

Run-TestCase "JoinRequest can be constructed by client" {
    $join = New-JoinRequestMessage -Seq 7 -Name 'Alice'

    Assert-Equal 'JoinRequest' $join.Type
    Assert-Equal 7 $join.Seq
    Assert-Equal 'Alice' $join.Payload.Name
    Assert-Equal $true (Test-ProtocolMessage -Message $join).IsValid
}

Run-TestCase "JoinRequest with empty name is rejected" {
    $server = New-PokerServerState -MaxSeats 6
    $connection = New-PokerClientConnectionState -ConnectionId 'C1'
    $join = New-JoinRequestMessage -Seq 1 -Name ''

    $response = Handle-JoinRequest -Server $server -Connection $connection -Message $join

    Assert-Equal 'ErrorMessage' $response.Type
    Assert-True ($response.Payload.Message -match 'Name')
    Assert-Equal 0 @($server.Game.Players).Count
}

Run-TestCase "JoinAccepted assigns PlayerId and first available Seat" {
    $server = New-PokerServerState -MaxSeats 6
    $connection = New-PokerClientConnectionState -ConnectionId 'C1'
    $join = New-JoinRequestMessage -Seq 1 -Name 'Alice'

    $response = Handle-JoinRequest -Server $server -Connection $connection -Message $join

    Assert-Equal 'JoinAccepted' $response.Type
    Assert-Equal 'P1' $response.Payload.PlayerId
    Assert-Equal 1 ([int]$response.Payload.Seat)
    Assert-Equal 'Alice' $response.Payload.Name
    Assert-Equal 'P1' $connection.PlayerId
    Assert-Equal 1 ([int]$connection.Seat)
    Assert-Equal 1 @($server.Game.Players).Count
    Assert-Equal 'RemoteHuman' $server.Game.Players[0].Type
}

Run-TestCase "Server ignores client requested Seat and prevents duplicate seats" {
    $server = New-PokerServerState -MaxSeats 6
    $first = New-PokerClientConnectionState -ConnectionId 'C1'
    $second = New-PokerClientConnectionState -ConnectionId 'C2'

    $joinOne = New-ProtocolMessage -Type 'JoinRequest' -Seq 1 -Payload ([pscustomobject]@{ Name = 'Alice'; Seat = 6 })
    $joinTwo = New-ProtocolMessage -Type 'JoinRequest' -Seq 2 -Payload ([pscustomobject]@{ Name = 'Bob'; Seat = 1 })

    $firstResponse = Handle-JoinRequest -Server $server -Connection $first -Message $joinOne
    $secondResponse = Handle-JoinRequest -Server $server -Connection $second -Message $joinTwo

    Assert-Equal 'JoinAccepted' $firstResponse.Type
    Assert-Equal 1 ([int]$firstResponse.Payload.Seat)
    Assert-Equal 'JoinAccepted' $secondResponse.Type
    Assert-Equal 2 ([int]$secondResponse.Payload.Seat)
    Assert-SequenceEqual @(1, 2) @($server.Game.Players | Sort-Object Seat | ForEach-Object { [int]$_.Seat })
}

Run-TestCase "Full table returns ErrorMessage" {
    $server = New-PokerServerState -MaxSeats 2

    $response1 = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C1') -Message (New-JoinRequestMessage -Seq 1 -Name 'Alice')
    $response2 = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C2') -Message (New-JoinRequestMessage -Seq 2 -Name 'Bob')
    $response3 = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C3') -Message (New-JoinRequestMessage -Seq 3 -Name 'Carol')

    Assert-Equal 'JoinAccepted' $response1.Type
    Assert-Equal 'JoinAccepted' $response2.Type
    Assert-Equal 'ErrorMessage' $response3.Type
    Assert-True ($response3.Payload.Message -match 'full')
    Assert-Equal 2 @($server.Game.Players).Count
}

Run-TestCase "Disconnected RemoteHuman frees seat before next JoinRequest" {
    $server = New-PokerServerState -MaxSeats 2
    $alice = New-PokerClientConnectionState -ConnectionId 'C1'
    $bob = New-PokerClientConnectionState -ConnectionId 'C2'
    $carol = New-PokerClientConnectionState -ConnectionId 'C3'

    $response1 = Handle-JoinRequest -Server $server -Connection $alice -Message (New-JoinRequestMessage -Seq 1 -Name 'Alice')
    $response2 = Handle-JoinRequest -Server $server -Connection $bob -Message (New-JoinRequestMessage -Seq 2 -Name 'Bob')
    $fullResponse = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C4') -Message (New-JoinRequestMessage -Seq 3 -Name 'Dave')
    $alice.IsConnected = $false

    $response3 = Handle-JoinRequest -Server $server -Connection $carol -Message (New-JoinRequestMessage -Seq 4 -Name 'Carol')

    Assert-Equal 'JoinAccepted' $response1.Type
    Assert-Equal 'JoinAccepted' $response2.Type
    Assert-Equal 'ErrorMessage' $fullResponse.Type
    Assert-Equal 'JoinAccepted' $response3.Type
    Assert-Equal 1 ([int]$response3.Payload.Seat)
    Assert-Equal 'P1' $response3.Payload.PlayerId
    Assert-Equal 2 @($server.Game.Players).Count
    Assert-SequenceEqual @('Carol', 'Bob') @($server.Game.Players | Sort-Object Seat | ForEach-Object { $_.Name })
    Assert-SequenceEqual @(1, 2) @($server.Game.Players | Sort-Object Seat | ForEach-Object { [int]$_.Seat })
    Assert-False (@($server.Game.Players | Where-Object { $_.Name -eq 'Alice' }).Count -gt 0)
}

Run-TestCase "Client can parse JoinAccepted and store session identity" {
    $client = New-PokerClientState -Name 'Alice'
    $message = New-ProtocolMessage -Type 'JoinAccepted' -Seq 1 -PlayerId 'P1' -Payload ([pscustomobject]@{
        PlayerId = 'P1'
        Seat = 1
        Name = 'Alice'
    })

    Handle-ServerMessage -Client $client -Message $message -Quiet

    Assert-Equal 'P1' $client.PlayerId
    Assert-Equal 1 ([int]$client.Seat)
    Assert-Equal 'Alice' $client.Name
}

Run-TestCase "Client can parse StateSnapshot without creating GameState" {
    $client = New-PokerClientState -Name 'Alice'
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 2 -PlayerId 'P1' -HandId 0 -Payload ([pscustomobject]@{
        HandId = 0
        Street = 'Finished'
        Pot = 0
        CurrentBet = 0
        ActionSeat = $null
        CommunityCards = @()
        YourHoleCards = @()
        Players = @()
        LegalActions = @()
    })

    Handle-ServerMessage -Client $client -Message $snapshot -Quiet

    Assert-Equal 'StateSnapshot' $client.LastMessageType
    Assert-Equal 0 ([int]$client.LastSnapshot.HandId)
    Assert-False ($client.PSObject.Properties.Name -contains 'Game')
}

Run-TestCase "Client close releases TCP connection so host can detect disconnect" {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        $client = New-PokerClientState -Name 'Alice'
        $client.TcpClient = [System.Net.Sockets.TcpClient]::new()
        $client.TcpClient.Connect('127.0.0.1', $listener.LocalEndpoint.Port)
        $serverTcp = $listener.AcceptTcpClient()
        $serverConnection = New-PokerClientConnectionState -ConnectionId 'C1' -TcpClient $serverTcp

        Assert-True (Test-ServerConnectionAlive -Connection $serverConnection)
        Close-PokerClient -Client $client
        Start-Sleep -Milliseconds 100

        Assert-False (Test-ServerConnectionAlive -Connection $serverConnection)
    } finally {
        if ($null -ne $serverTcp) {
            $serverTcp.Close()
        }
        $listener.Stop()
    }
}

Run-TestCase "Client cancel shutdown releases active TCP connection" {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        $client = New-PokerClientState -Name 'Alice'
        $client.TcpClient = [System.Net.Sockets.TcpClient]::new()
        $client.TcpClient.Connect('127.0.0.1', $listener.LocalEndpoint.Port)
        $serverTcp = $listener.AcceptTcpClient()
        $serverConnection = New-PokerClientConnectionState -ConnectionId 'C1' -TcpClient $serverTcp

        Register-PokerClientShutdownHandler -Client $client
        Assert-True (Test-ServerConnectionAlive -Connection $serverConnection)

        Close-ActivePokerClientForShutdown
        Start-Sleep -Milliseconds 100

        Assert-False (Test-ServerConnectionAlive -Connection $serverConnection)
    } finally {
        Unregister-PokerClientShutdownHandler
        if ($null -ne $serverTcp) {
            $serverTcp.Close()
        }
        $listener.Stop()
    }
}

Run-TestCase "Client formats pre-hand StateSnapshot as one-line room status" {
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 3 -PlayerId 'P1' -HandId 0 -Payload ([pscustomobject]@{
        HandId = 0
        Street = 'Finished'
        Pot = 0
        CurrentBet = 0
        ActionSeat = $null
        DealerSeat = 0
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @()
        YourHoleCards = @()
        Players = @(
            [pscustomobject]@{ Seat = 1; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 1000; Bet = 0; Status = 'Waiting'; IsYou = $true; HoleCards = @() },
            [pscustomobject]@{ Seat = 2; Name = 'Bot-2'; Type = 'Bot'; BotType = 'RandomBot'; Chips = 1000; Bet = 0; Status = 'Waiting'; IsYou = $false; HoleCards = $null }
        )
        LegalActions = @()
    })

    $lines = @(Format-StateSnapshotLines -Snapshot $snapshot)
    $text = $lines -join "`n"
    $roomLabel = New-NetworkConnectionTestText @(0x623f, 0x95f4)
    $joinedLabel = New-NetworkConnectionTestText @(0x5df2, 0x52a0, 0x5165)
    $waitingLabel = New-NetworkConnectionTestText @(0x7b49, 0x5f85, 0x5f00, 0x5c40)
    $tableHeader = "$(New-NetworkConnectionTestText @(0x5ea7))  $(New-NetworkConnectionTestText @(0x73a9, 0x5bb6))      $(New-NetworkConnectionTestText @(0x578b))"
    $boardLabel = New-NetworkConnectionTestText @(0x516c, 0x5171)
    $handLabel = New-NetworkConnectionTestText @(0x624b, 0x724c)
    $finishedLine = New-NetworkConnectionTestText @(0x672c, 0x624b, 0x724c, 0x5df2, 0x7ed3, 0x675f)

    Assert-Equal 1 $lines.Count
    Assert-Equal "$roomLabel`: Alice, Bot-2 $joinedLabel, $waitingLabel" $lines[0]
    Assert-True ($text -match 'Alice')
    Assert-True ($text -match 'Bot-2')
    Assert-False ($text -match [regex]::Escape($tableHeader))
    Assert-False ($text -match [regex]::Escape($boardLabel))
    Assert-False ($text -match [regex]::Escape($handLabel))
    Assert-False ($text -match [regex]::Escape($finishedLine))
}

Run-TestCase "Client formats pre-hand pause reason when not enough real players are online" {
    $pauseMessage = New-NetworkConnectionTestText @(0x771f, 0x4eba, 0x73a9, 0x5bb6, 0x4e0d, 0x8db3, 0xff0c, 0x7b49, 0x5f85, 0x771f, 0x4eba, 0x52a0, 0x5165, 0x6216, 0x91cd, 0x65b0, 0x8fde, 0x63a5, 0x540e, 0x518d, 0x5f00, 0x59cb, 0x4e0b, 0x4e00, 0x5c40)
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 4 -PlayerId 'P1' -HandId 0 -Payload ([pscustomobject]@{
        HandId = 0
        Street = 'Finished'
        Pot = 0
        CurrentBet = 0
        ActionSeat = $null
        DealerSeat = 0
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @()
        YourHoleCards = @()
        Players = @(
            [pscustomobject]@{ Seat = 1; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 1000; Bet = 0; Status = 'Waiting'; IsYou = $true; HoleCards = @() }
        )
        LegalActions = @()
        IsPaused = $true
        PauseMessage = $pauseMessage
    })

    $lines = @(Format-StateSnapshotLines -Snapshot $snapshot)
    $text = $lines -join "`n"

    Assert-True ($lines.Count -ge 2)
    Assert-True ($text -match [regex]::Escape($pauseMessage))
}

Run-TestCase "Client formats finished-hand pause reason before next hand" {
    $pauseMessage = New-NetworkConnectionTestText @(0x771f, 0x4eba, 0x73a9, 0x5bb6, 0x4e0d, 0x8db3, 0xff0c, 0x7b49, 0x5f85, 0x771f, 0x4eba, 0x52a0, 0x5165, 0x6216, 0x91cd, 0x65b0, 0x8fde, 0x63a5, 0x540e, 0x518d, 0x5f00, 0x59cb, 0x4e0b, 0x4e00, 0x5c40)
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 5 -PlayerId 'P1' -HandId 2 -Payload ([pscustomobject]@{
        HandId = 2
        Street = 'Finished'
        Pot = 0
        CurrentBet = 0
        ActionSeat = $null
        DealerSeat = 1
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @('Ah', 'Kc', '4d', '2s', '3c')
        YourHoleCards = @('As', 'Kd')
        Players = @(
            [pscustomobject]@{ Seat = 1; PlayerId = 'P1'; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 1000; Bet = 0; Status = 'Waiting'; IsYou = $true; HoleCards = @('As', 'Kd') },
            [pscustomobject]@{ Seat = 2; PlayerId = 'P2'; Name = 'Bot-2'; Type = 'Bot'; BotType = 'LooseBot'; Chips = 1000; Bet = 0; Status = 'Waiting'; IsYou = $false; HoleCards = @('Qs', 'Jd') }
        )
        LegalActions = @()
        IsPaused = $true
        PauseMessage = $pauseMessage
    })

    $text = (@(Format-StateSnapshotLines -Snapshot $snapshot) -join "`n")

    Assert-True ($text -match [regex]::Escape($pauseMessage))
}

Run-TestCase "Client formats StateSnapshot as compact Chinese table without private leaks" {
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 3 -PlayerId 'P1' -HandId 1 -Payload ([pscustomobject]@{
        HandId = 1
        Street = 'Flop'
        Pot = 120
        CurrentBet = 0
        ActionSeat = 1
        DealerSeat = 1
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @('Th', '4s', '7d')
        YourHoleCards = @('4c', '8s')
        Players = @(
            [pscustomobject]@{ Seat = 1; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 980; Bet = 0; Status = 'Waiting'; IsYou = $true; HoleCards = @('4c', '8s') },
            [pscustomobject]@{ Seat = 2; Name = 'Bot-2'; Type = 'Bot'; BotType = 'RandomBot'; Chips = 980; Bet = 0; Status = 'Waiting'; IsYou = $false; HoleCards = $null },
            [pscustomobject]@{ Seat = 3; Name = 'Bob'; Type = 'RemoteHuman'; Chips = 980; Bet = 0; Status = 'Waiting'; IsYou = $false; HoleCards = $null }
        )
        LegalActions = @(
            [pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null },
            [pscustomobject]@{ Command = 'check'; MinAmount = $null; MaxAmount = $null },
            [pscustomobject]@{ Command = 'bet'; MinAmount = 20; MaxAmount = 980 },
            [pscustomobject]@{ Command = 'allin'; MinAmount = $null; MaxAmount = $null }
        )
    })

    $lines = @(Format-StateSnapshotLines -Snapshot $snapshot)
    $text = $lines -join "`n"
    $you = New-NetworkConnectionTestText @(0x4f60)
    $random = New-NetworkConnectionTestText @(0x968f, 0x673a)
    $remote = New-NetworkConnectionTestText @(0x8054, 0x673a)
    $flop = New-NetworkConnectionTestText @(0x7ffb, 0x724c)
    $headerLine = "$(New-NetworkConnectionTestText @(0x7b2c))1$(New-NetworkConnectionTestText @(0x624b)) | $(New-NetworkConnectionTestText @(0x5e84))1 | $flop | $(New-NetworkConnectionTestText @(0x76f2))10/20 | $(New-NetworkConnectionTestText @(0x6c60))120 | $(New-NetworkConnectionTestText @(0x6ce8))0"
    $tableHeader = "$(New-NetworkConnectionTestText @(0x5ea7))  $(New-NetworkConnectionTestText @(0x73a9, 0x5bb6))      $(New-NetworkConnectionTestText @(0x578b))    $(New-NetworkConnectionTestText @(0x7b79, 0x7801))  $(New-NetworkConnectionTestText @(0x6ce8))  $(New-NetworkConnectionTestText @(0x72b6, 0x6001))"
    $boardLine = "$(New-NetworkConnectionTestText @(0x516c, 0x5171)): [$(New-NetworkConnectionTestText @(0x7ea2, 0x6843))10] [$(New-NetworkConnectionTestText @(0x9ed1, 0x6843))4] [$(New-NetworkConnectionTestText @(0x65b9, 0x5757))7] [??] [??]"
    $holeLine = "$(New-NetworkConnectionTestText @(0x624b, 0x724c)): [$(New-NetworkConnectionTestText @(0x6885, 0x82b1))4] [$(New-NetworkConnectionTestText @(0x9ed1, 0x6843))8]"
    $toCallLine = "$(New-NetworkConnectionTestText @(0x9700, 0x8ddf)): 0"
    $commandLine = "$(New-NetworkConnectionTestText @(0x547d, 0x4ee4)): 1.$(New-NetworkConnectionTestText @(0x5f03, 0x724c))  2.$(New-NetworkConnectionTestText @(0x8fc7, 0x724c))  3.$(New-NetworkConnectionTestText @(0x4e0b, 0x6ce8))20-980  4.$(New-NetworkConnectionTestText @(0x5168, 0x4e0b))"

    Assert-True ($text -match [regex]::Escape($headerLine))
    Assert-True ($text -match [regex]::Escape($tableHeader))
    Assert-True ($text -match "Alice")
    Assert-True ($text -match [regex]::Escape($you))
    Assert-True ($text -match "Bot-2")
    Assert-True ($text -match [regex]::Escape($random))
    Assert-True ($text -match "Bob")
    Assert-True ($text -match [regex]::Escape($remote))
    Assert-True ($text -match [regex]::Escape($boardLine))
    Assert-True ($text -match [regex]::Escape($holeLine))
    Assert-True ($text -match [regex]::Escape($toCallLine))
    Assert-True ($text -match [regex]::Escape($commandLine))
    Assert-False ($text -match 'Ah')
    Assert-False ($text -match 'Deck')
    Assert-False ($text -match 'GameState')
}

Run-TestCase "Client formats non-turn StateSnapshot as wait message without commands" {
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 4 -PlayerId 'P1' -HandId 1 -Payload ([pscustomobject]@{
        HandId = 1
        Street = 'PreFlop'
        Pot = 30
        CurrentBet = 20
        ActionSeat = 2
        WaitingPlayerId = 'P2'
        WaitingPlayerName = 'Bob'
        DealerSeat = 1
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @()
        YourHoleCards = @('As', 'Kd')
        Players = @(
            [pscustomobject]@{ Seat = 1; PlayerId = 'P1'; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 990; Bet = 10; Status = 'Waiting'; IsYou = $true; HoleCards = @('As', 'Kd') },
            [pscustomobject]@{ Seat = 2; PlayerId = 'P2'; Name = 'Bob'; Type = 'RemoteHuman'; Chips = 980; Bet = 20; Status = 'Acting'; IsYou = $false; HoleCards = $null }
        )
        LegalActions = @()
        IsPaused = $false
    })

    $text = (@(Format-StateSnapshotLines -Snapshot $snapshot) -join "`n")
    $waitLine = New-NetworkConnectionTestText @(0x8bf7, 0x7b49, 0x5f85, 0x5176, 0x4ed6, 0x73a9, 0x5bb6, 0x51b3, 0x7b56)
    $commandLabel = New-NetworkConnectionTestText @(0x547d, 0x4ee4)

    Assert-True ($text -match [regex]::Escape($waitLine))
    Assert-True ($text -match 'Bob')
    Assert-False ($text -match [regex]::Escape("$commandLabel`:"))
}

Run-TestCase "Client formats paused StateSnapshot as pause message without commands" {
    $pauseMessage = New-NetworkConnectionTestText @(0x724c, 0x5c40, 0x6682, 0x505c, 0xff0c, 0x7b49, 0x5f85, 0x79bb, 0x7ebf, 0x73a9, 0x5bb6, 0x91cd, 0x65b0, 0x8fde, 0x63a5)
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 5 -PlayerId 'P1' -HandId 1 -Payload ([pscustomobject]@{
        HandId = 1
        Street = 'Flop'
        Pot = 120
        CurrentBet = 0
        ActionSeat = 2
        WaitingPlayerId = 'P2'
        WaitingPlayerName = 'Bob'
        DealerSeat = 1
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @('Th', '4s', '7d')
        YourHoleCards = @('As', 'Kd')
        Players = @(
            [pscustomobject]@{ Seat = 1; PlayerId = 'P1'; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 980; Bet = 0; Status = 'Waiting'; IsYou = $true; HoleCards = @('As', 'Kd') },
            [pscustomobject]@{ Seat = 2; PlayerId = 'P2'; Name = 'Bob'; Type = 'RemoteHuman'; Chips = 980; Bet = 0; Status = 'Waiting'; IsYou = $false; HoleCards = $null }
        )
        LegalActions = @()
        IsPaused = $true
        PauseMessage = $pauseMessage
    })

    $text = (@(Format-StateSnapshotLines -Snapshot $snapshot) -join "`n")
    $commandLabel = New-NetworkConnectionTestText @(0x547d, 0x4ee4)

    Assert-True ($text -match [regex]::Escape($pauseMessage))
    Assert-False ($text -match [regex]::Escape("$commandLabel`:"))
}

Run-TestCase "Client revealed hands include each player's best hand summary" {
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 6 -PlayerId 'P1' -HandId 3 -Payload ([pscustomobject]@{
        HandId = 3
        Street = 'Finished'
        Pot = 600
        CurrentBet = 0
        ActionSeat = $null
        DealerSeat = 1
        SmallBlind = 10
        BigBlind = 20
        CommunityCards = @('Ah', 'Kc', '4d', '2s', '3c')
        YourHoleCards = @('As', 'Kd')
        Players = @(
            [pscustomobject]@{ Seat = 1; PlayerId = 'P1'; Name = 'Alice'; Type = 'RemoteHuman'; Chips = 1300; Bet = 0; Status = 'Waiting'; IsYou = $true; HoleCards = @('As', 'Kd') },
            [pscustomobject]@{ Seat = 2; PlayerId = 'P2'; Name = 'Bob'; Type = 'RemoteHuman'; Chips = 700; Bet = 0; Status = 'Waiting'; IsYou = $false; HoleCards = @('Qs', 'Jd') }
        )
        LegalActions = @()
    })

    $text = (@(Format-StateSnapshotLines -Snapshot $snapshot) -join "`n")
    $bestLabel = New-NetworkConnectionTestText @(0x6700, 0x5927, 0x724c, 0x578b)
    $twoPair = New-NetworkConnectionTestText @(0x4e24, 0x5bf9)
    $highCard = New-NetworkConnectionTestText @(0x9ad8, 0x724c)

    Assert-True ($text -match "Alice: .*$bestLabel`: $twoPair A")
    Assert-True ($text -match "Bob: .*$bestLabel`: $highCard A")
}

Run-TestCase "Client action validation errors are Chinese" {
    $client = New-PokerClientState -Name 'Alice'
    $client.PlayerId = 'P1'
    $request = New-ProtocolMessage -Type 'ActionRequest' -Seq 7 -PlayerId 'P1' -HandId 1 -Payload ([pscustomobject]@{
        HandId = 1
        Seat = 1
        ActionSeat = 1
        LegalActions = @(
            [pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null },
            [pscustomobject]@{ Command = 'call'; MinAmount = $null; MaxAmount = $null },
            [pscustomobject]@{ Command = 'raise'; MinAmount = 40; MaxAmount = 980 },
            [pscustomobject]@{ Command = 'allin'; MinAmount = $null; MaxAmount = $null }
        )
    })

    try {
        ConvertTo-ClientPlayerAction -Client $client -ActionRequest $request -InputText '3 1000' | Out-Null
        throw 'Expected client to reject illegal action.'
    } catch {
        $currentState = New-NetworkConnectionTestText @(0x5f53, 0x524d, 0x72b6, 0x6001)
        $illegal = New-NetworkConnectionTestText @(0x4e0d, 0x5408, 0x6cd5)
        Assert-True ($_.Exception.Message -match [regex]::Escape($currentState)) "Expected Chinese illegal-action error."
        Assert-True ($_.Exception.Message -match [regex]::Escape($illegal)) "Expected Chinese illegal-action wording."
    }
}
