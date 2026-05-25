. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Core\Showdown.ps1"

function New-IntegrationCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

function New-IntegrationGame {
    param([Parameter(Mandatory = $true)][int[]]$Chips)

    $players = @()
    for ($i = 0; $i -lt $Chips.Count; $i++) {
        $players += New-PlayerState -Seat ($i + 1) -Name "P$($i + 1)" -Type 'HumanLocal' -Chips $Chips[$i]
    }

    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Flop'
    $game.CurrentBet = 0
    $game.MinRaise = $game.BigBlind
    $game.DealerSeat = 1
    $game.ActionSeat = 1
    return $game
}

function Set-IntegrationHoleCards {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat,
        [Parameter(Mandatory = $true)][string[]]$Cards
    )

    (Get-PlayerBySeat -Game $Game -Seat $Seat).HoleCards = @(New-IntegrationCards -Texts $Cards)
}

function Set-IntegrationBoard {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][string[]]$Cards
    )

    $Game.CommunityCards = @(New-IntegrationCards -Texts $Cards)
}

function Get-IntegrationTotal {
    param([Parameter(Mandatory = $true)]$Game)

    $total = 0
    foreach ($player in $Game.Players) {
        $total += [int]$player.Chips
    }
    return $total
}

function Assert-NoNegativeChips {
    param([Parameter(Mandatory = $true)]$Game)

    foreach ($player in $Game.Players) {
        Assert-True ([int]$player.Chips -ge 0) "Seat $($player.Seat) should not have negative chips."
    }
}

function New-ThreeWaySidePotShowdown {
    $game = New-IntegrationGame -Chips @(100, 300, 300)
    Set-IntegrationBoard -Game $game -Cards @('2c', '3d', '4h', '9s', 'Kc')
    Set-IntegrationHoleCards -Game $game -Seat 1 -Cards @('As', '5s')
    Set-IntegrationHoleCards -Game $game -Seat 2 -Cards @('Kd', 'Qs')
    Set-IntegrationHoleCards -Game $game -Seat 3 -Cards @('9d', '8c')

    Apply-PlayerAction -Game $game -Seat 1 -Command 'allin'
    Apply-PlayerAction -Game $game -Seat 2 -Command 'raise' -Amount 300
    Apply-PlayerAction -Game $game -Seat 3 -Command 'call'
    Resolve-Hand -Game $game
    return $game
}

Run-TestCase "Integration three player betting flow creates main and side pots" {
    $game = New-ThreeWaySidePotShowdown

    Assert-Equal 'Finished' $game.Street
    Assert-Equal 2 $game.Pots.Count
    Assert-Equal 300 $game.Pots[0].Amount
    Assert-Equal 400 $game.Pots[1].Amount
    Assert-SequenceEqual @(1, 2, 3) $game.Pots[0].EligibleSeats
    Assert-SequenceEqual @(2, 3) $game.Pots[1].EligibleSeats
    Assert-False (@($game.Pots[1].EligibleSeats) -contains 1)
    Assert-Equal 700 (Get-IntegrationTotal -Game $game)
    Assert-NoNegativeChips -Game $game
}

Run-TestCase "Integration main pot and side pot are awarded to different players" {
    $game = New-ThreeWaySidePotShowdown

    Assert-Equal 300 $game.Players[0].Chips
    Assert-Equal 400 $game.Players[1].Chips
    Assert-Equal 0 $game.Players[2].Chips
    Assert-Equal 700 (Get-IntegrationTotal -Game $game)
    Assert-NoNegativeChips -Game $game
}

Run-TestCase "Integration folded contribution stays in pot but folded player cannot win" {
    $game = New-IntegrationGame -Chips @(500, 500, 500)
    Set-IntegrationBoard -Game $game -Cards @('As', 'Ks', 'Qs', '2d', '3c')
    Set-IntegrationHoleCards -Game $game -Seat 1 -Cards @('Js', 'Ts')
    Set-IntegrationHoleCards -Game $game -Seat 2 -Cards @('Ah', 'Ad')
    Set-IntegrationHoleCards -Game $game -Seat 3 -Cards @('2h', '2c')

    Apply-PlayerAction -Game $game -Seat 1 -Command 'bet' -Amount 100
    Apply-PlayerAction -Game $game -Seat 2 -Command 'call'
    Apply-PlayerAction -Game $game -Seat 3 -Command 'call'
    Apply-PlayerAction -Game $game -Seat 1 -Command 'fold'
    Resolve-Hand -Game $game

    Assert-Equal 1 $game.Pots.Count
    Assert-Equal 300 $game.Pots[0].Amount
    Assert-SequenceEqual @(2, 3) $game.Pots[0].EligibleSeats
    Assert-False (@($game.Pots[0].EligibleSeats) -contains 1)
    Assert-Equal 400 $game.Players[0].Chips
    Assert-Equal 700 $game.Players[1].Chips
    Assert-Equal 400 $game.Players[2].Chips
    Assert-Equal 1500 (Get-IntegrationTotal -Game $game)
    Assert-NoNegativeChips -Game $game
}

Run-TestCase "Integration short call automatically becomes all-in" {
    $game = New-IntegrationGame -Chips @(60, 1000)

    Apply-PlayerAction -Game $game -Seat 2 -Command 'bet' -Amount 100
    Apply-PlayerAction -Game $game -Seat 1 -Command 'call'

    Assert-Equal 0 $game.Players[0].Chips
    Assert-Equal 'AllIn' $game.Players[0].Status
    Assert-Equal 60 $game.Players[0].StreetBet
    Assert-Equal 60 $game.Players[0].TotalBetThisHand
    Assert-Equal 100 $game.CurrentBet
    Assert-True ([int]$game.Players[0].Chips -ge 0)
}

Run-TestCase "Integration incomplete all-in raise does not reopen acted players and can close" {
    $game = New-IntegrationGame -Chips @(1000, 1000, 150)

    Apply-PlayerAction -Game $game -Seat 1 -Command 'bet' -Amount 100
    Apply-PlayerAction -Game $game -Seat 2 -Command 'call'
    Apply-PlayerAction -Game $game -Seat 3 -Command 'allin'

    Assert-Equal 150 $game.CurrentBet
    Assert-Equal 100 $game.MinRaise
    Assert-True $game.Players[0].HasActedThisRound
    Assert-True $game.Players[1].HasActedThisRound
    Assert-Equal 'AllIn' $game.Players[2].Status

    Apply-PlayerAction -Game $game -Seat 1 -Command 'call'
    Apply-PlayerAction -Game $game -Seat 2 -Command 'call'

    Assert-Equal 850 $game.Players[0].Chips
    Assert-Equal 850 $game.Players[1].Chips
    Assert-Equal 0 $game.Players[2].Chips
    Assert-Equal 150 $game.Players[0].StreetBet
    Assert-Equal 150 $game.Players[1].StreetBet
    Assert-Equal 150 $game.Players[2].StreetBet
    Assert-True (Is-BettingRoundClosed -Game $game)
    Assert-NoNegativeChips -Game $game
}

function Complete-HeadsUpCheckStreet {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][string]$Street
    )

    Assert-Equal $Street $Game.Street
    Assert-Equal 2 $Game.ActionSeat
    Apply-PlayerAction -Game $Game -Seat 2 -Command 'check'
    Set-NextActionSeat -Game $Game
    Assert-Equal 1 $Game.ActionSeat
    Apply-PlayerAction -Game $Game -Seat 1 -Command 'check'
    Set-NextActionSeat -Game $Game
    Assert-True ($null -eq $Game.ActionSeat)
}

Run-TestCase "Integration heads-up full hand uses dealer preflop then big blind postflop" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'DealerSB' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'BigBlind' -Type 'HumanLocal' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Start-NewHand -Game $game
    Assert-Equal 'PreFlop' $game.Street
    Assert-Equal 1 $game.DealerSeat
    Assert-Equal 1 $game.ActionSeat

    Apply-PlayerAction -Game $game -Seat 1 -Command 'call'
    Set-NextActionSeat -Game $game
    Assert-Equal 2 $game.ActionSeat
    Apply-PlayerAction -Game $game -Seat 2 -Command 'check'
    Set-NextActionSeat -Game $game
    Assert-True ($null -eq $game.ActionSeat)

    Advance-Street -Game $game
    Complete-HeadsUpCheckStreet -Game $game -Street 'Flop'

    Advance-Street -Game $game
    Complete-HeadsUpCheckStreet -Game $game -Street 'Turn'

    Advance-Street -Game $game
    Complete-HeadsUpCheckStreet -Game $game -Street 'River'

    Advance-Street -Game $game
    Assert-Equal 'Showdown' $game.Street
    Assert-True ($null -eq $game.ActionSeat)
}
