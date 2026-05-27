. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Network\Protocol.ps1"

function New-NetworkTestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Add-NetworkTestPlayerId {
    param(
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $true)][string]$PlayerId
    )

    if ($Player.PSObject.Properties.Name -contains 'PlayerId') {
        $Player.PlayerId = $PlayerId
    } else {
        $Player | Add-Member -NotePropertyName PlayerId -NotePropertyValue $PlayerId
    }
}

function New-NetworkProtocolTestGame {
    $alice = New-PlayerState -Seat 1 -Name 'Alice' -Type 'RemoteHuman' -Chips 840
    $bob = New-PlayerState -Seat 2 -Name 'Bob' -Type 'RemoteHuman' -Chips 910
    $bot = New-PlayerState -Seat 3 -Name 'Bot-3' -Type 'Bot' -Chips 1000
    $bot | Add-Member -NotePropertyName BotType -NotePropertyValue 'RandomBot'
    Add-NetworkTestPlayerId -Player $alice -PlayerId 'P1'
    Add-NetworkTestPlayerId -Player $bob -PlayerId 'P2'
    Add-NetworkTestPlayerId -Player $bot -PlayerId 'P3'

    $alice.HoleCards = @((New-Card -Rank 12 -Suit 'H'), (New-Card -Rank 11 -Suit 'D'))
    $bob.HoleCards = @((New-Card -Rank 14 -Suit 'S'), (New-Card -Rank 13 -Suit 'D'))
    $bot.HoleCards = @((New-Card -Rank 2 -Suit 'C'), (New-Card -Rank 3 -Suit 'C'))
    $alice.StreetBet = 80
    $alice.TotalBetThisHand = 80
    $bob.StreetBet = 80
    $bob.TotalBetThisHand = 80
    $bot.StreetBet = 100
    $bot.TotalBetThisHand = 100
    $bob.Status = 'Acting'

    $game = New-GameState -Players @($alice, $bob, $bot) -SmallBlind 10 -BigBlind 20 -Mode 'Host'
    $game.HandId = 12
    $game.Street = 'Flop'
    $game.DealerSeat = 1
    $game.ActionSeat = 2
    $game.CurrentBet = 80
    $game.MinRaise = 80
    $game.CommunityCards = @((New-Card -Rank 14 -Suit 'H'), (New-Card -Rank 7 -Suit 'D'), (New-Card -Rank 7 -Suit 'S'))
    $game.Deck = @((New-Card -Rank 9 -Suit 'C'), (New-Card -Rank 5 -Suit 'H'))

    return $game
}

Run-TestCase "Protocol message can be created and serialized as one-line JSON" {
    $payload = [pscustomobject]@{
        Command = 'raise'
        Amount = 160
        Note = New-NetworkTestText @(0x73a9, 0x5bb6)
    }

    $message = New-ProtocolMessage -Type 'PlayerAction' -Seq 42 -PlayerId 'P2' -HandId 12 -Payload $payload
    $json = ConvertTo-MessageJson -Message $message
    $parsed = ConvertFrom-MessageJson -Json $json

    Assert-Equal 'PlayerAction' $message.Type
    Assert-Equal 42 $message.Seq
    Assert-Equal 'P2' $message.PlayerId
    Assert-Equal 12 $message.HandId
    Assert-True (-not ($json -match "(`r|`n)")) 'Protocol JSON must be one line.'
    Assert-Equal 'PlayerAction' $parsed.Type
    Assert-Equal 'raise' $parsed.Payload.Command
    Assert-Equal 160 ([int]$parsed.Payload.Amount)
    Assert-Equal $payload.Note $parsed.Payload.Note
}

Run-TestCase "Invalid JSON returns a detectable parse failure" {
    $parsed = ConvertFrom-MessageJson -Json '{bad-json'

    Assert-Equal $false $parsed.IsValid
    Assert-True (-not [string]::IsNullOrWhiteSpace($parsed.Error))
}

Run-TestCase "Protocol validator rejects missing or unknown message fields" {
    $missingType = [pscustomobject]@{ Seq = 1; Payload = [pscustomobject]@{} }
    $missingSeq = [pscustomobject]@{ Type = 'JoinRequest'; Payload = [pscustomobject]@{} }
    $missingPayload = [pscustomobject]@{ Type = 'JoinRequest'; Seq = 1 }
    $unknownType = New-ProtocolMessage -Type 'ChatMessage' -Seq 1 -Payload ([pscustomobject]@{})

    Assert-Equal $false (Test-ProtocolMessage -Message $missingType).IsValid
    Assert-Equal $false (Test-ProtocolMessage -Message $missingSeq).IsValid
    Assert-Equal $false (Test-ProtocolMessage -Message $missingPayload).IsValid
    Assert-Equal $false (Test-ProtocolMessage -Message $unknownType).IsValid
}

Run-TestCase "Protocol validator rejects incomplete PlayerAction payloads" {
    $missingCommand = New-ProtocolMessage -Type 'PlayerAction' -Seq 1 -PlayerId 'P2' -HandId 12 -Payload ([pscustomobject]@{})
    $betWithoutAmount = New-ProtocolMessage -Type 'PlayerAction' -Seq 2 -PlayerId 'P2' -HandId 12 -Payload ([pscustomobject]@{ Command = 'bet' })
    $raiseWithoutAmount = New-ProtocolMessage -Type 'PlayerAction' -Seq 3 -PlayerId 'P2' -HandId 12 -Payload ([pscustomobject]@{ Command = 'raise' })
    $validCall = New-ProtocolMessage -Type 'PlayerAction' -Seq 4 -PlayerId 'P2' -HandId 12 -Payload ([pscustomobject]@{ Command = 'call' })

    Assert-Equal $false (Test-ProtocolMessage -Message $missingCommand).IsValid
    Assert-Equal $false (Test-ProtocolMessage -Message $betWithoutAmount).IsValid
    Assert-Equal $false (Test-ProtocolMessage -Message $raiseWithoutAmount).IsValid
    Assert-Equal $true (Test-ProtocolMessage -Message $validCall).IsValid
}

Run-TestCase "StateSnapshot shows only the target player's private hole cards" {
    $game = New-NetworkProtocolTestGame

    $snapshot = New-StateSnapshotForPlayer -Game $game -PlayerId 'P2' -Seq 99
    $payload = $snapshot.Payload
    $playerRows = @($payload.Players)
    $aliceRow = @($playerRows | Where-Object { $_.Seat -eq 1 })[0]
    $bobRow = @($playerRows | Where-Object { $_.Seat -eq 2 })[0]
    $botRow = @($playerRows | Where-Object { $_.Seat -eq 3 })[0]

    Assert-Equal 'StateSnapshot' $snapshot.Type
    Assert-Equal 'P2' $snapshot.PlayerId
    Assert-Equal 12 $snapshot.HandId
    Assert-SequenceEqual @('As', 'Kd') @($payload.YourHoleCards)
    Assert-SequenceEqual @('As', 'Kd') @($bobRow.HoleCards)
    Assert-True ($null -eq $aliceRow.HoleCards)
    Assert-True ($null -eq $botRow.HoleCards)
    Assert-Equal 'RandomBot' $botRow.BotType
    Assert-SequenceEqual @('Ah', '7d', '7s') @($payload.CommunityCards)
    Assert-True (@($payload.LegalActions).Count -gt 0)
}

Run-TestCase "StateSnapshot does not expose deck complete GameState or future hidden cards" {
    $game = New-NetworkProtocolTestGame

    $snapshot = New-StateSnapshotForPlayer -Game $game -PlayerId 'P2' -Seq 100
    $json = ConvertTo-MessageJson -Message $snapshot

    Assert-False ($snapshot.Payload.PSObject.Properties.Name -contains 'Deck') 'Snapshot payload must not include Deck.'
    Assert-False ($snapshot.Payload.PSObject.Properties.Name -contains 'GameState') 'Snapshot payload must not include complete GameState.'
    Assert-False ($json -match '"Deck"') 'Snapshot JSON must not include Deck.'
    Assert-False ($json -match '"GameState"') 'Snapshot JSON must not include complete GameState.'
    Assert-False ($json -match 'Qh') 'Other player hole cards must not leak.'
    Assert-False ($json -match 'Jd') 'Other player hole cards must not leak.'
    Assert-False ($json -match '2c') 'Bot hole cards must not leak.'
    Assert-False ($json -match '3c') 'Bot hole cards must not leak.'
    Assert-False ($json -match '9c') 'Deck cards must not leak.'
    Assert-False ($json -match '5h') 'Deck cards must not leak.'
}
