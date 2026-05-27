. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Core\Showdown.ps1"
. "$PSScriptRoot\..\src\UI\CommandParser.ps1"
. "$PSScriptRoot\..\src\Bot\BotProfiles.ps1"
. "$PSScriptRoot\..\src\Bot\BotEvaluator.ps1"
. "$PSScriptRoot\..\src\Bot\BotDecision.ps1"
. "$PSScriptRoot\..\src\Bot\RandomBot.ps1"
. "$PSScriptRoot\..\src\Bot\TightBot.ps1"
. "$PSScriptRoot\..\src\Bot\LooseBot.ps1"
. "$PSScriptRoot\..\src\Bot\RuleBot.ps1"
. "$PSScriptRoot\..\src\Bot\BotBase.ps1"
. "$PSScriptRoot\..\src\Network\Protocol.ps1"
. "$PSScriptRoot\..\src\Network\Server.ps1"
. "$PSScriptRoot\..\src\Network\Client.ps1"
. "$PSScriptRoot\..\src\Network\HttpServer.ps1"
. "$PSScriptRoot\..\src\Network\HttpClient.ps1"
. "$PSScriptRoot\..\src\Local\GameLoop.ps1"

function New-HttpNetworkTestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

Run-TestCase "HTTP join reconnects same name without filling the table" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 5

    $first = Invoke-HttpJoin -Server $server -Name 'Alice'
    $second = Invoke-HttpJoin -Server $server -Name 'Alice'

    Assert-Equal 'JoinAccepted' $first.Type
    Assert-Equal 'JoinAccepted' $second.Type
    Assert-Equal 'P1' $first.Payload.PlayerId
    Assert-Equal 'P1' $second.Payload.PlayerId
    Assert-Equal 1 ([int]$second.Payload.Seat)
    Assert-Equal 6 @($server.Game.Players).Count
    Assert-Equal 1 @($server.Game.Players | Where-Object { $_.Type -eq 'RemoteHuman' }).Count
    Assert-Equal 1 @($server.Sessions).Count
}

Run-TestCase "HTTP host creates all automatic bots as LooseBot" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 5

    Invoke-HttpJoin -Server $server -Name 'Alice' | Out-Null

    $botTypes = @(
        $server.Game.Players |
            Where-Object { $_.Type -eq 'Bot' } |
            Sort-Object Seat |
            ForEach-Object { [string]$_.BotType }
    )
    Assert-SequenceEqual @('LooseBot', 'LooseBot', 'LooseBot', 'LooseBot', 'LooseBot') $botTypes
}

Run-TestCase "HTTP state request returns private snapshot for the session player" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 1
    $join = Invoke-HttpJoin -Server $server -Name 'Alice'
    Start-NewHand -Game $server.Game

    $snapshot = Invoke-HttpState -Server $server -PlayerId $join.Payload.PlayerId -Token $join.Payload.Token

    Assert-Equal 'StateSnapshot' $snapshot.Type
    Assert-Equal 'P1' $snapshot.PlayerId
    Assert-Equal 1 ([int]$snapshot.Payload.HandId)
    Assert-Equal 2 @($snapshot.Payload.YourHoleCards).Count
    Assert-Equal 2 @((@($snapshot.Payload.Players) | Where-Object { $_.PlayerId -eq 'P1' })[0].HoleCards).Count
    Assert-True ($null -eq (@($snapshot.Payload.Players) | Where-Object { $_.PlayerId -eq 'P2' })[0].HoleCards)
}

Run-TestCase "HTTP state for non-acting player asks client to wait without legal commands" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 4
    $alice = Invoke-HttpJoin -Server $server -Name 'Alice'
    Invoke-HttpJoin -Server $server -Name 'Bob' | Out-Null
    Start-NewHand -Game $server.Game
    $server.Game.ActionSeat = 2

    $snapshot = Invoke-HttpState -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token

    Assert-Equal 'StateSnapshot' $snapshot.Type
    Assert-Equal 2 ([int]$snapshot.Payload.ActionSeat)
    Assert-Equal 'P2' $snapshot.Payload.WaitingPlayerId
    Assert-Equal 0 @($snapshot.Payload.LegalActions).Count
}

Run-TestCase "HTTP action stores only legal action for current waiting player" {
    $server = New-PokerHttpServerState -MaxSeats 2 -BotCount 0
    $alice = Invoke-HttpJoin -Server $server -Name 'Alice'
    $bob = Invoke-HttpJoin -Server $server -Name 'Bob'
    Start-NewHand -Game $server.Game
    $server.WaitingActionPlayerId = 'P1'

    $wrongPlayer = Invoke-HttpAction -Server $server -PlayerId $bob.Payload.PlayerId -Token $bob.Payload.Token -Command 'call'
    $accepted = Invoke-HttpAction -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token -Command 'call'

    Assert-Equal 'ErrorMessage' $wrongPlayer.Type
    Assert-Equal 'NotYourTurn' $wrongPlayer.Payload.Code
    Assert-Equal 'ActionAccepted' $accepted.Type
    Assert-Equal 'call' $server.PendingActions['P1'].Command
}

Run-TestCase "HTTP wait returns queued action and clears wait state" {
    $server = New-PokerHttpServerState -MaxSeats 2 -BotCount 0
    Invoke-HttpJoin -Server $server -Name 'Alice' | Out-Null
    Invoke-HttpJoin -Server $server -Name 'Bob' | Out-Null
    Start-NewHand -Game $server.Game
    $server.PendingActions['P1'] = [pscustomobject]@{ Command = 'call'; Amount = $null }
    $player = Get-PlayerBySeat -Game $server.Game -Seat 1

    $action = Wait-HttpPlayerAction -Server $server -Player $player -TimeoutMilliseconds 100

    Assert-Equal 'call' $action.Command
    Assert-True ($null -eq $action.Amount)
    Assert-True ($null -eq $server.WaitingActionPlayerId)
    Assert-False $server.PendingActions.ContainsKey('P1')
}

Run-TestCase "HTTP current decision timeout does not pause while player is thinking" {
    $server = New-PokerHttpServerState -MaxSeats 2 -BotCount 0
    Invoke-HttpJoin -Server $server -Name 'Alice' | Out-Null
    Invoke-HttpJoin -Server $server -Name 'Bob' | Out-Null
    Start-NewHand -Game $server.Game
    $session = Get-HttpSession -Server $server -PlayerId 'P1'
    $session.LastSeenUtc = [DateTime]::UtcNow.AddSeconds(-30)
    $player = Get-PlayerBySeat -Game $server.Game -Seat 1

    $action = Wait-HttpPlayerAction -Server $server -Player $player -TimeoutMilliseconds 50

    Assert-Equal '__timeout' $action.Command
    Assert-False $action.IsPaused
    Assert-True $session.IsConnected
    Assert-False $server.IsPaused
}

Run-TestCase "HTTP non-acting player timeout pauses active game" {
    $server = New-PokerHttpServerState -MaxSeats 2 -BotCount 0
    $alice = Invoke-HttpJoin -Server $server -Name 'Alice'
    Invoke-HttpJoin -Server $server -Name 'Bob' | Out-Null
    Start-NewHand -Game $server.Game
    $server.WaitingActionPlayerId = 'P1'
    $bobSession = Get-HttpSession -Server $server -PlayerId 'P2'
    $bobSession.LastSeenUtc = [DateTime]::UtcNow.AddSeconds(-30)

    $snapshot = Invoke-HttpState -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token

    Assert-True $snapshot.Payload.IsPaused
    Assert-False $bobSession.IsConnected
}

Run-TestCase "HTTP leave pauses active game until same player reconnects" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 4
    $alice = Invoke-HttpJoin -Server $server -Name 'Alice'
    $bob = Invoke-HttpJoin -Server $server -Name 'Bob'
    Start-NewHand -Game $server.Game

    Invoke-HttpLeave -Server $server -PlayerId $bob.Payload.PlayerId -Token $bob.Payload.Token | Out-Null
    $paused = Invoke-HttpState -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token
    $rejoined = Invoke-HttpJoin -Server $server -Name 'Bob'
    $resumed = Invoke-HttpState -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token

    Assert-Equal 'StateSnapshot' $paused.Type
    Assert-True $paused.Payload.IsPaused
    $pauseWord = New-HttpNetworkTestText @(0x6682, 0x505c)
    Assert-True ([string]$paused.Payload.PauseMessage -match [regex]::Escape($pauseWord))
    Assert-Equal 'JoinAccepted' $rejoined.Type
    Assert-Equal $bob.Payload.PlayerId $rejoined.Payload.PlayerId
    Assert-False $resumed.Payload.IsPaused
}

Run-TestCase "HTTP host pauses next hand when no real player is online" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 5
    Invoke-HttpJoin -Server $server -Name 'Alice' | Out-Null
    $session = Get-HttpSession -Server $server -PlayerId 'P1'
    $session.LastSeenUtc = [DateTime]::UtcNow.AddSeconds(-30)
    $session.IsConnected = $false
    $server.Game.Street = 'Finished'

    $canStart = Test-HttpCanStartNextHand -Server $server

    Assert-False $canStart
    Assert-True $server.IsPaused
}

Run-TestCase "HTTP host pauses between hands when connected humans are below required count" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 4
    $alice = Invoke-HttpJoin -Server $server -Name 'Alice'
    $bob = Invoke-HttpJoin -Server $server -Name 'Bob'
    $bobSession = Get-HttpSession -Server $server -PlayerId $bob.Payload.PlayerId
    $bobSession.IsConnected = $false
    $server.Game.HandId = 3
    $server.Game.Street = 'Finished'

    $canStart = Test-HttpCanStartNextHand -Server $server
    $snapshot = Invoke-HttpState -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token

    Assert-False $canStart
    Assert-True $snapshot.Payload.IsPaused
    Assert-Equal 0 @($snapshot.Payload.LegalActions).Count
    $insufficientHumans = New-HttpNetworkTestText @(0x771f, 0x4eba, 0x73a9, 0x5bb6, 0x4e0d, 0x8db3)
    Assert-True ([string]$snapshot.Payload.PauseMessage -match [regex]::Escape($insufficientHumans))
}

Run-TestCase "HTTP host resets table instead of letting bots play alone when real players are eliminated" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 4
    $alice = Invoke-HttpJoin -Server $server -Name 'Alice'
    Invoke-HttpJoin -Server $server -Name 'Bob' | Out-Null
    foreach ($player in @($server.Game.Players | Where-Object { $_.Type -eq 'RemoteHuman' })) {
        $player.Chips = 0
        $player.Status = 'Out'
    }
    foreach ($player in @($server.Game.Players | Where-Object { $_.Type -eq 'Bot' })) {
        $player.Chips = 6000
    }
    $server.Game.HandId = 4
    $server.Game.Street = 'Finished'

    $canStart = Test-HttpCanStartNextHand -Server $server
    $snapshot = Invoke-HttpState -Server $server -PlayerId $alice.Payload.PlayerId -Token $alice.Payload.Token

    Assert-True $canStart
    Assert-False $snapshot.Payload.IsPaused
    foreach ($player in @($server.Game.Players)) {
        Assert-Equal 1000 ([int]$player.Chips)
        Assert-Equal 'Waiting' ([string]$player.Status)
    }
}

Run-TestCase "HTTP host resumes next hand after same real player reconnects" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 5
    $first = Invoke-HttpJoin -Server $server -Name 'Alice'
    $session = Get-HttpSession -Server $server -PlayerId $first.Payload.PlayerId
    $session.LastSeenUtc = [DateTime]::UtcNow.AddSeconds(-30)
    $session.IsConnected = $false

    $beforeReconnect = Test-HttpCanStartNextHand -Server $server
    $second = Invoke-HttpJoin -Server $server -Name 'Alice'
    $afterReconnect = Test-HttpCanStartNextHand -Server $server

    Assert-False $beforeReconnect
    Assert-Equal 'JoinAccepted' $second.Type
    Assert-Equal 'P1' $second.Payload.PlayerId
    Assert-True $afterReconnect
}

Run-TestCase "HTTP host with four bots waits for second real player before starting" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 4
    Invoke-HttpJoin -Server $server -Name 'Alice' | Out-Null

    $afterOneHuman = Test-HttpCanStartNextHand -Server $server
    $bob = Invoke-HttpJoin -Server $server -Name 'Bob'
    $afterTwoHumans = Test-HttpCanStartNextHand -Server $server

    Assert-False $afterOneHuman
    Assert-Equal 'JoinAccepted' $bob.Type
    Assert-Equal 6 ([int]$bob.Payload.Seat)
    Assert-True $afterTwoHumans
}

Run-TestCase "HTTP join during active hand seats new player out until next hand" {
    $server = New-PokerHttpServerState -MaxSeats 6 -BotCount 4
    Invoke-HttpJoin -Server $server -Name 'Alice' | Out-Null
    Start-NewHand -Game $server.Game

    $bob = Invoke-HttpJoin -Server $server -Name 'Bob'
    $bobPlayer = Get-PlayerBySeat -Game $server.Game -Seat ([int]$bob.Payload.Seat)

    Assert-Equal 'JoinAccepted' $bob.Type
    Assert-Equal 'Out' $bobPlayer.Status
    Assert-Equal 0 @($bobPlayer.HoleCards).Count
}

Run-TestCase "HTTP client numbered action conversion keeps sequence state" {
    $client = New-PokerHttpClientState -Name 'Alice'
    $client.PlayerId = 'P1'
    $client.Seat = 1
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

    $action = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $request -InputText '2'

    Assert-Equal 'PlayerAction' $action.Type
    Assert-Equal 'call' $action.Payload.Command
    Assert-Equal 1 ([int]$action.Seq)
    Assert-Equal 2 ([int]$client.NextSeq)
}

Run-TestCase "HTTP client does not prompt for input while its seat is paused" {
    $client = New-PokerHttpClientState -Name 'Alice'
    $client.PlayerId = 'P1'
    $client.Seat = 6
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 8 -PlayerId 'P1' -HandId 2 -Payload ([pscustomobject]@{
        HandId = 2
        Street = 'PreFlop'
        ActionSeat = 6
        IsPaused = $true
        LegalActions = @()
    })

    $isTurn = Test-PokerHttpClientTurn -Client $client -Snapshot $snapshot

    Assert-False $isTurn
}

Run-TestCase "HTTP client does not prompt when current snapshot has no legal actions" {
    $client = New-PokerHttpClientState -Name 'Alice'
    $client.PlayerId = 'P1'
    $client.Seat = 6
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 9 -PlayerId 'P1' -HandId 2 -Payload ([pscustomobject]@{
        HandId = 2
        Street = 'PreFlop'
        ActionSeat = 6
        IsPaused = $false
        LegalActions = @()
    })

    $isTurn = Test-PokerHttpClientTurn -Client $client -Snapshot $snapshot

    Assert-False $isTurn
}
