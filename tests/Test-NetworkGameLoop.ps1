. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Core\Showdown.ps1"
. "$PSScriptRoot\..\src\UI\CommandParser.ps1"
. "$PSScriptRoot\..\src\Network\Protocol.ps1"
. "$PSScriptRoot\..\src\Network\Server.ps1"
. "$PSScriptRoot\..\src\Network\Client.ps1"
. "$PSScriptRoot\..\src\Local\GameLoop.ps1"

function New-NetworkGameLoopTestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function New-NetworkGameLoopTestTable {
    $server = New-PokerServerState -MaxSeats 6
    $alice = New-PokerClientConnectionState -ConnectionId 'C1'
    $bob = New-PokerClientConnectionState -ConnectionId 'C2'

    $aliceJoin = Handle-JoinRequest -Server $server -Connection $alice -Message (New-JoinRequestMessage -Seq 1 -Name 'Alice')
    $bobJoin = Handle-JoinRequest -Server $server -Connection $bob -Message (New-JoinRequestMessage -Seq 2 -Name 'Bob')

    Assert-Equal 'JoinAccepted' $aliceJoin.Type
    Assert-Equal 'JoinAccepted' $bobJoin.Type

    Start-NewHand -Game $server.Game

    [pscustomobject]@{
        Server = $server
        Alice = $alice
        Bob = $bob
    }
}

function New-NetworkGameLoopActionMessage {
    param(
        [Parameter(Mandatory = $true)][string]$PlayerId,
        [Parameter(Mandatory = $true)][int]$HandId,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)][Nullable[int]]$Amount = $null,
        [Parameter(Mandatory = $false)][int]$Seq = 10
    )

    $payload = [pscustomobject]@{ Command = $Command }
    if ($null -ne $Amount) {
        $payload | Add-Member -NotePropertyName Amount -NotePropertyValue $Amount
    }

    return New-ProtocolMessage -Type 'PlayerAction' -Seq $Seq -PlayerId $PlayerId -HandId $HandId -Payload $payload
}

Run-TestCase "Host applies only the current remote player's legal action through betting rules" {
    $table = New-NetworkGameLoopTestTable
    $server = $table.Server

    Assert-Equal 1 ([int]$server.Game.ActionSeat)
    $message = New-NetworkGameLoopActionMessage -PlayerId 'P1' -HandId $server.Game.HandId -Command 'call'

    $result = Apply-RemotePlayerAction -Server $server -Connection $table.Alice -Message $message
    $alicePlayer = Get-PlayerBySeat -Game $server.Game -Seat 1

    Assert-True $result.Accepted
    Assert-True ($null -eq $result.Error)
    Assert-Equal 980 ([int]$alicePlayer.Chips)
    Assert-Equal 20 ([int]$alicePlayer.StreetBet)
    Assert-Equal 20 ([int]$alicePlayer.TotalBetThisHand)
    Assert-True $alicePlayer.HasActedThisRound
    Assert-Equal 2 ([int]$server.Game.ActionSeat)
}

Run-TestCase "Host rejects a PlayerAction from a remote player who is not ActionSeat without mutating GameState" {
    $table = New-NetworkGameLoopTestTable
    $server = $table.Server
    $aliceBefore = Get-PlayerBySeat -Game $server.Game -Seat 1
    $bobBefore = Get-PlayerBySeat -Game $server.Game -Seat 2
    $before = [pscustomobject]@{
        ActionSeat = $server.Game.ActionSeat
        CurrentBet = $server.Game.CurrentBet
        AliceChips = $aliceBefore.Chips
        AliceBet = $aliceBefore.StreetBet
        BobChips = $bobBefore.Chips
        BobBet = $bobBefore.StreetBet
    }
    $message = New-NetworkGameLoopActionMessage -PlayerId 'P2' -HandId $server.Game.HandId -Command 'check'

    $result = Apply-RemotePlayerAction -Server $server -Connection $table.Bob -Message $message

    Assert-False $result.Accepted
    Assert-Equal 'ErrorMessage' $result.Error.Type
    Assert-Equal 'NotYourTurn' $result.Error.Payload.Code
    Assert-Equal $before.ActionSeat $server.Game.ActionSeat
    Assert-Equal $before.CurrentBet $server.Game.CurrentBet
    Assert-Equal $before.AliceChips (Get-PlayerBySeat -Game $server.Game -Seat 1).Chips
    Assert-Equal $before.AliceBet (Get-PlayerBySeat -Game $server.Game -Seat 1).StreetBet
    Assert-Equal $before.BobChips (Get-PlayerBySeat -Game $server.Game -Seat 2).Chips
    Assert-Equal $before.BobBet (Get-PlayerBySeat -Game $server.Game -Seat 2).StreetBet
}

Run-TestCase "Host rejects stale HandId and illegal command without advancing action" {
    $table = New-NetworkGameLoopTestTable
    $server = $table.Server
    $stale = New-NetworkGameLoopActionMessage -PlayerId 'P1' -HandId 999 -Command 'call'
    $illegal = New-NetworkGameLoopActionMessage -PlayerId 'P1' -HandId $server.Game.HandId -Command 'check'

    $staleResult = Apply-RemotePlayerAction -Server $server -Connection $table.Alice -Message $stale
    $illegalResult = Apply-RemotePlayerAction -Server $server -Connection $table.Alice -Message $illegal

    Assert-False $staleResult.Accepted
    Assert-Equal 'HandMismatch' $staleResult.Error.Payload.Code
    Assert-False $illegalResult.Accepted
    Assert-Equal 'IllegalAction' $illegalResult.Error.Payload.Code
    Assert-Equal 1 ([int]$server.Game.ActionSeat)
    Assert-Equal 990 ([int](Get-PlayerBySeat -Game $server.Game -Seat 1).Chips)
    Assert-Equal 10 ([int](Get-PlayerBySeat -Game $server.Game -Seat 1).StreetBet)
}

Run-TestCase "ActionRequest exposes only current player legal actions and client converts numbered text into PlayerAction" {
    $table = New-NetworkGameLoopTestTable
    $server = $table.Server
    $client = New-PokerClientState -Name 'Alice'
    $client.PlayerId = 'P1'
    $client.Seat = 1

    $request = New-ActionRequestMessage -Server $server -Connection $table.Alice
    $action = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $request -InputText '2'

    Assert-Equal 'ActionRequest' $request.Type
    Assert-Equal 'P1' $request.PlayerId
    Assert-Equal $server.Game.HandId ([int]$request.HandId)
    Assert-Equal 1 ([int]$request.Payload.ActionSeat)
    Assert-SequenceEqual @('fold', 'call', 'raise', 'allin') @($request.Payload.LegalActions | ForEach-Object { $_.Command })
    Assert-Equal 'PlayerAction' $action.Type
    Assert-Equal 'P1' $action.PlayerId
    Assert-Equal $server.Game.HandId ([int]$action.HandId)
    Assert-Equal 'call' $action.Payload.Command
}

Run-TestCase "Client converts English Chinese and numbered remote commands without creating local GameState" {
    $table = New-NetworkGameLoopTestTable
    $client = New-PokerClientState -Name 'Alice'
    $client.PlayerId = 'P1'
    $client.Seat = 1
    $callRaiseRequest = New-ActionRequestMessage -Server $table.Server -Connection $table.Alice
    $checkBetRequest = New-ProtocolMessage -Type 'ActionRequest' -Seq 77 -PlayerId 'P1' -HandId 3 -Payload ([pscustomobject]@{
        HandId = 3
        Seat = 1
        ActionSeat = 1
        ToCall = 0
        LegalActions = @(
            [pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null },
            [pscustomobject]@{ Command = 'check'; MinAmount = $null; MaxAmount = $null },
            [pscustomobject]@{ Command = 'bet'; MinAmount = 20; MaxAmount = 100 },
            [pscustomobject]@{ Command = 'allin'; MinAmount = $null; MaxAmount = $null }
        )
    })
    $foldText = New-NetworkGameLoopTestText @(0x5f03, 0x724c)
    $checkText = New-NetworkGameLoopTestText @(0x8fc7, 0x724c)
    $callText = New-NetworkGameLoopTestText @(0x8ddf, 0x6ce8)
    $betText = "$(New-NetworkGameLoopTestText @(0x4e0b, 0x6ce8)) 40"
    $raiseText = "$(New-NetworkGameLoopTestText @(0x52a0, 0x6ce8)) 40"
    $allInText = New-NetworkGameLoopTestText @(0x5168, 0x4e0b)

    $foldAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $callRaiseRequest -InputText $foldText
    $callAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $callRaiseRequest -InputText $callText
    $raiseAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $callRaiseRequest -InputText $raiseText
    $checkAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $checkBetRequest -InputText $checkText
    $betAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $checkBetRequest -InputText $betText
    $allInAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $checkBetRequest -InputText $allInText
    $numberedAction = ConvertTo-ClientPlayerAction -Client $client -ActionRequest $checkBetRequest -InputText '2'

    Assert-Equal 'fold' $foldAction.Payload.Command
    Assert-Equal 'call' $callAction.Payload.Command
    Assert-Equal 'raise' $raiseAction.Payload.Command
    Assert-Equal 40 ([int]$raiseAction.Payload.Amount)
    Assert-Equal 'check' $checkAction.Payload.Command
    Assert-Equal 'bet' $betAction.Payload.Command
    Assert-Equal 40 ([int]$betAction.Payload.Amount)
    Assert-Equal 'allin' $allInAction.Payload.Command
    Assert-Equal 'check' $numberedAction.Payload.Command
    Assert-False ($client.PSObject.Properties.Name -contains 'Game')
}

Run-TestCase "GameLoop accepts RemoteHuman actions through a remote action provider" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Alice' -Type 'RemoteHuman' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bob' -Type 'RemoteHuman' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20 -Mode 'Host'
    Start-NewHand -Game $game
    $commands = @('call', 'check')
    $script:networkGameLoopCommandIndex = 0
    $provider = {
        $command = $commands[$script:networkGameLoopCommandIndex]
        $script:networkGameLoopCommandIndex++
        return $command
    }

    Invoke-BettingRound -Game $game -ActionProvider $provider -MaxTurns 5

    Assert-True (Is-BettingRoundClosed -Game $game)
    Assert-True ($null -eq $game.ActionSeat)
    Assert-Equal 20 ([int](Get-PlayerBySeat -Game $game -Seat 1).StreetBet)
    Assert-Equal 20 ([int](Get-PlayerBySeat -Game $game -Seat 2).StreetBet)
}

Run-TestCase "Client marks session finished after HandResult" {
    $client = New-PokerClientState -Name 'Alice'
    $result = New-ProtocolMessage -Type 'HandResult' -Seq 12 -PlayerId 'P1' -HandId 3 -Payload ([pscustomobject]@{
        HandId = 3
        Street = 'Finished'
        Pot = 2000
        CurrentBet = 0
        Players = @()
        LegalActions = @()
    })

    Handle-ServerMessage -Client $client -Message $result -Quiet

    Assert-Equal 'HandResult' $client.LastMessageType
    Assert-True $client.IsFinished
    Assert-Equal 3 ([int]$client.LastSnapshot.HandId)
}
