. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"

function New-PotTestGame {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 3 -Name 'C' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 4 -Name 'D' -Type 'HumanLocal' -Chips 0)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Players[0].TotalBetThisHand = 100
    $game.Players[0].Status = 'AllIn'
    $game.Players[1].TotalBetThisHand = 300
    $game.Players[2].TotalBetThisHand = 300
    $game.Players[2].Status = 'Folded'
    $game.Players[3].TotalBetThisHand = 600
    return $game
}

Run-TestCase "Side pots are built by contribution layer" {
    $game = New-PotTestGame
    $pots = @(Build-Pots -Game $game)

    Assert-Equal 3 $pots.Count
    Assert-Equal 400 $pots[0].Amount
    Assert-Equal 600 $pots[1].Amount
    Assert-Equal 300 $pots[2].Amount
    Assert-SequenceEqual @(1, 2, 4) $pots[0].EligibleSeats
    Assert-SequenceEqual @(2, 4) $pots[1].EligibleSeats
    Assert-SequenceEqual @(4) $pots[2].EligibleSeats
}

Run-TestCase "Award pots pays only eligible winners" {
    $game = New-PotTestGame
    $game.Pots = @(Build-Pots -Game $game)
    $results = @{
        1 = [pscustomobject]@{ RankLevel = 7; Kickers = @(14, 2) }
        2 = [pscustomobject]@{ RankLevel = 4; Kickers = @(13, 9, 8) }
        4 = [pscustomobject]@{ RankLevel = 6; Kickers = @(12, 10, 8, 7, 2) }
    }

    Award-Pots -Game $game -HandResults $results

    Assert-Equal 400 $game.Players[0].Chips
    Assert-Equal 0 $game.Players[1].Chips
    Assert-Equal 0 $game.Players[2].Chips
    Assert-Equal 900 $game.Players[3].Chips
}

Run-TestCase "Award pots splits ties and gives remainder by seat order" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 0)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Pots = @([pscustomobject]@{ Amount = 101; EligibleSeats = @(1, 2) })
    $results = @{
        1 = [pscustomobject]@{ RankLevel = 1; Kickers = @(14, 13, 9, 8, 2) }
        2 = [pscustomobject]@{ RankLevel = 1; Kickers = @(14, 13, 9, 8, 2) }
    }

    Award-Pots -Game $game -HandResults $results

    Assert-Equal 51 $game.Players[0].Chips
    Assert-Equal 50 $game.Players[1].Chips
}
