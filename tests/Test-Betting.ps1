. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"

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

Run-TestCase "All-in does not make player chips negative" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 35),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Flop'
    $game.CurrentBet = 0
    $game.MinRaise = 20

    Apply-PlayerAction -Game $game -Seat 1 -Command 'allin'

    Assert-Equal 0 $game.Players[0].Chips
    Assert-Equal 35 $game.Players[0].StreetBet
    Assert-Equal 35 $game.Players[0].TotalBetThisHand
    Assert-Equal 'AllIn' $game.Players[0].Status
    Assert-True ([int]$game.Players[0].Chips -ge 0)
    Assert-True $game.Players[0].HasActedThisRound
}

Run-TestCase "Call with insufficient chips automatically becomes all-in" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Short' -Type 'HumanLocal' -Chips 30),
        (New-PlayerState -Seat 2 -Name 'Big' -Type 'HumanLocal' -Chips 900)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Flop'
    $game.CurrentBet = 100
    $game.MinRaise = 50
    $game.ActionSeat = 1
    $game.Players[1].StreetBet = 100
    $game.Players[1].TotalBetThisHand = 100

    Apply-PlayerAction -Game $game -Seat 1 -Command 'call'

    Assert-Equal 0 $game.Players[0].Chips
    Assert-Equal 30 $game.Players[0].StreetBet
    Assert-Equal 30 $game.Players[0].TotalBetThisHand
    Assert-Equal 'AllIn' $game.Players[0].Status
    Assert-True ([int]$game.Players[0].Chips -ge 0)
    Assert-True $game.Players[0].HasActedThisRound
    Assert-Equal 100 $game.CurrentBet
}

Run-TestCase "Short all-in raise does not reset already acted players" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 900),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 900),
        (New-PlayerState -Seat 3 -Name 'Short' -Type 'HumanLocal' -Chips 130)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Flop'
    $game.CurrentBet = 100
    $game.MinRaise = 50
    $game.ActionSeat = 3
    $game.Players[0].StreetBet = 100
    $game.Players[0].TotalBetThisHand = 100
    $game.Players[0].HasActedThisRound = $true
    $game.Players[1].StreetBet = 100
    $game.Players[1].TotalBetThisHand = 100
    $game.Players[1].HasActedThisRound = $true

    Apply-PlayerAction -Game $game -Seat 3 -Command 'allin'

    Assert-Equal 130 $game.CurrentBet
    Assert-Equal 50 $game.MinRaise
    Assert-True $game.Players[0].HasActedThisRound "Seat 1 should not be reset by an incomplete all-in raise."
    Assert-True $game.Players[1].HasActedThisRound "Seat 2 should not be reset by an incomplete all-in raise."
    Assert-Equal 100 $game.Players[0].StreetBet
    Assert-Equal 100 $game.Players[1].StreetBet
    Assert-Equal 130 $game.Players[2].StreetBet
    Assert-Equal 130 $game.Players[2].TotalBetThisHand
    Assert-Equal 'AllIn' $game.Players[2].Status
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

Run-TestCase "Raise below minimum is rejected" {
    $game = New-BettingTestGame
    $threw = $false

    Assert-False (Test-PlayerActionLegal -Game $game -Seat 1 -Command 'raise' -Amount 30)

    try {
        Apply-PlayerAction -Game $game -Seat 1 -Command 'raise' -Amount 30
    } catch {
        $threw = $true
    }

    Assert-True $threw "Raise to 30 should be rejected when current bet is 20 and min raise is 20."
    Assert-Equal 20 $game.CurrentBet
    Assert-Equal 1000 $game.Players[0].Chips
    Assert-Equal 0 $game.Players[0].StreetBet
    Assert-Equal 0 $game.Players[0].TotalBetThisHand
    Assert-False $game.Players[0].HasActedThisRound
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

Run-TestCase "Heads-up preflop action starts with dealer small blind" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'DealerSB' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'BigBlind' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Start-NewHand -Game $game

    Assert-Equal 1 $game.DealerSeat
    Assert-Equal 10 $game.Players[0].StreetBet
    Assert-Equal 20 $game.Players[1].StreetBet
    Assert-Equal 1 $game.ActionSeat
    Assert-Equal 20 $game.CurrentBet
    Assert-Equal 20 $game.MinRaise
}

Run-TestCase "Heads-up postflop streets start with big blind" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'DealerSB' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'BigBlind' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Start-NewHand -Game $game
    Advance-Street -Game $game
    Assert-Equal 'Flop' $game.Street
    Assert-Equal 2 $game.ActionSeat
    Assert-Equal 0 $game.CurrentBet
    Assert-Equal 0 $game.Players[0].StreetBet
    Assert-Equal 0 $game.Players[1].StreetBet

    Advance-Street -Game $game
    Assert-Equal 'Turn' $game.Street
    Assert-Equal 2 $game.ActionSeat
    Assert-Equal 0 $game.CurrentBet

    Advance-Street -Game $game
    Assert-Equal 'River' $game.Street
    Assert-Equal 2 $game.ActionSeat
    Assert-Equal 0 $game.CurrentBet
}
