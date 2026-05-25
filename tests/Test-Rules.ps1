. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"

Run-TestCase "Start new hand deals two hole cards and posts blinds" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 3 -Name 'C' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Start-NewHand -Game $game

    Assert-Equal 1 $game.HandId
    Assert-Equal 'PreFlop' $game.Street
    Assert-Equal 1 $game.DealerSeat
    Assert-Equal 1 $game.ActionSeat
    Assert-Equal 2 $game.Players[0].HoleCards.Count
    Assert-Equal 2 $game.Players[1].HoleCards.Count
    Assert-Equal 2 $game.Players[2].HoleCards.Count
    Assert-Equal 990 $game.Players[1].Chips
    Assert-Equal 980 $game.Players[2].Chips
    Assert-Equal 20 $game.CurrentBet
}

Run-TestCase "Advance street deals flop turn and river" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    Start-NewHand -Game $game

    Advance-Street -Game $game
    Assert-Equal 'Flop' $game.Street
    Assert-Equal 3 $game.CommunityCards.Count

    Advance-Street -Game $game
    Assert-Equal 'Turn' $game.Street
    Assert-Equal 4 $game.CommunityCards.Count

    Advance-Street -Game $game
    Assert-Equal 'River' $game.Street
    Assert-Equal 5 $game.CommunityCards.Count

    Advance-Street -Game $game
    Assert-Equal 'Showdown' $game.Street
}
