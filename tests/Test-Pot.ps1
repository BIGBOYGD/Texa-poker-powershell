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

Run-TestCase "Three player all-in creates layered side pots" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Short' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'Middle' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 3 -Name 'Deep' -Type 'HumanLocal' -Chips 0)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Players[0].TotalBetThisHand = 100
    $game.Players[0].Status = 'AllIn'
    $game.Players[1].TotalBetThisHand = 300
    $game.Players[1].Status = 'AllIn'
    $game.Players[2].TotalBetThisHand = 600
    $game.Players[2].Status = 'AllIn'

    $pots = @(Build-Pots -Game $game)

    Assert-Equal 3 $pots.Count
    Assert-Equal 300 $pots[0].Amount
    Assert-Equal 400 $pots[1].Amount
    Assert-Equal 300 $pots[2].Amount
    Assert-SequenceEqual @(1, 2, 3) $pots[0].EligibleSeats
    Assert-SequenceEqual @(2, 3) $pots[1].EligibleSeats
    Assert-SequenceEqual @(3) $pots[2].EligibleSeats
}

Run-TestCase "Folded player contribution stays in pot but cannot win" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Folded' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'Caller' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 3 -Name 'Winner' -Type 'HumanLocal' -Chips 0)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    foreach ($player in $game.Players) {
        $player.TotalBetThisHand = 100
    }
    $game.Players[0].Status = 'Folded'
    $game.Pots = @(Build-Pots -Game $game)
    $results = @{
        1 = [pscustomobject]@{ RankLevel = 9; Kickers = @(14) }
        2 = [pscustomobject]@{ RankLevel = 1; Kickers = @(13, 9, 8, 6, 2) }
        3 = [pscustomobject]@{ RankLevel = 2; Kickers = @(12, 11, 8, 6) }
    }

    Assert-Equal 300 $game.Pots[0].Amount
    Assert-SequenceEqual @(2, 3) $game.Pots[0].EligibleSeats

    Award-Pots -Game $game -HandResults $results

    Assert-Equal 0 $game.Players[0].Chips
    Assert-Equal 0 $game.Players[1].Chips
    Assert-Equal 300 $game.Players[2].Chips
}

Run-TestCase "Two players split the main pot" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'HumanLocal' -Chips 0)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Pots = @([pscustomobject]@{ Amount = 200; EligibleSeats = @(1, 2) })
    $results = @{
        1 = [pscustomobject]@{ RankLevel = 5; Kickers = @(14) }
        2 = [pscustomobject]@{ RankLevel = 5; Kickers = @(14) }
    }

    Award-Pots -Game $game -HandResults $results

    Assert-Equal 100 $game.Players[0].Chips
    Assert-Equal 100 $game.Players[1].Chips
}

Run-TestCase "Main pot and side pot can be won by different players" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Short' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'Middle' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 3 -Name 'Deep' -Type 'HumanLocal' -Chips 0)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Players[0].TotalBetThisHand = 100
    $game.Players[1].TotalBetThisHand = 300
    $game.Players[2].TotalBetThisHand = 300
    $game.Pots = @(Build-Pots -Game $game)
    $results = @{
        1 = [pscustomobject]@{ RankLevel = 7; Kickers = @(14, 2) }
        2 = [pscustomobject]@{ RankLevel = 6; Kickers = @(13, 12, 8, 7, 2) }
        3 = [pscustomobject]@{ RankLevel = 2; Kickers = @(12, 11, 9, 8) }
    }

    Award-Pots -Game $game -HandResults $results

    Assert-Equal 300 $game.Players[0].Chips
    Assert-Equal 400 $game.Players[1].Chips
    Assert-Equal 0 $game.Players[2].Chips
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
