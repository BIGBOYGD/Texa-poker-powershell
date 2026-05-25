. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"

function New-BettingTestGame {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 980),
        (New-PlayerState -Seat 3 -Name 'C' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'PreFlop'
    $game.CurrentBet = 20
    $game.MinRaise = 20
    $game.ActionSeat = 1
    $game.Players[1].StreetBet = 20
    $game.Players[1].TotalBetThisHand = 20
    return $game
}

Run-TestCase "Legal actions require call when facing a bet" {
    $game = New-BettingTestGame
    $actions = @(Get-LegalActions -Game $game -Seat 1)
    $names = @($actions | ForEach-Object { $_.Command })

    Assert-True ($names -contains 'fold')
    Assert-True ($names -contains 'call')
    Assert-True ($names -contains 'raise')
    Assert-True ($names -contains 'allin')
    Assert-False ($names -contains 'check')
}

Run-TestCase "Call moves chips into the current street bet" {
    $game = New-BettingTestGame

    Apply-PlayerAction -Game $game -Seat 1 -Command 'call'

    Assert-Equal 980 $game.Players[0].Chips
    Assert-Equal 20 $game.Players[0].StreetBet
    Assert-Equal 20 $game.Players[0].TotalBetThisHand
    Assert-True $game.Players[0].HasActedThisRound
}

Run-TestCase "Raise updates current bet and resets other active players" {
    $game = New-BettingTestGame
    $game.Players[1].HasActedThisRound = $true
    $game.Players[2].HasActedThisRound = $true

    Apply-PlayerAction -Game $game -Seat 1 -Command 'raise' -Amount 60

    Assert-Equal 60 $game.CurrentBet
    Assert-Equal 40 $game.MinRaise
    Assert-True $game.Players[0].HasActedThisRound
    Assert-False $game.Players[1].HasActedThisRound
    Assert-False $game.Players[2].HasActedThisRound
}

Run-TestCase "Betting round closes after all active players match current bet" {
    $game = New-BettingTestGame
    Apply-PlayerAction -Game $game -Seat 1 -Command 'call'
    $game.Players[1].HasActedThisRound = $true
    $game.Players[2].Status = 'Folded'
    $game.Players[2].HasActedThisRound = $true

    Assert-True (Is-BettingRoundClosed -Game $game)
}

Run-TestCase "Betting round closes when only one player remains" {
    $game = New-BettingTestGame
    $game.Players[1].Status = 'Folded'
    $game.Players[2].Status = 'Folded'

    Assert-True (Is-BettingRoundClosed -Game $game)
}
