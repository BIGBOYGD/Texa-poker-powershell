. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Core\Showdown.ps1"
. "$PSScriptRoot\..\src\UI\CommandParser.ps1"
. "$PSScriptRoot\..\src\UI\Render.ps1"
. "$PSScriptRoot\..\src\Bot\BotProfiles.ps1"
. "$PSScriptRoot\..\src\Bot\BotEvaluator.ps1"
. "$PSScriptRoot\..\src\Bot\BotDecision.ps1"
. "$PSScriptRoot\..\src\Bot\RandomBot.ps1"
. "$PSScriptRoot\..\src\Bot\RuleBot.ps1"
. "$PSScriptRoot\..\src\Bot\BotBase.ps1"
. "$PSScriptRoot\..\src\Local\GameLoop.ps1"

Run-TestCase "Local hand loop finishes a two bot hand and conserves chips" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Bot-A' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Invoke-LocalHand -Game $game -MaxTurns 100

    $totalChips = 0
    foreach ($player in $game.Players) {
        $totalChips += [int]$player.Chips
    }

    Assert-Equal 1 $game.HandId
    Assert-Equal 'Finished' $game.Street
    Assert-True ($game.CommunityCards.Count -ge 0 -and $game.CommunityCards.Count -le 5)
    Assert-Equal 2000 $totalChips
    foreach ($player in $game.Players) {
        Assert-True ([int]$player.Chips -ge 0)
    }
}

Run-TestCase "Betting round advances through legal bot actions" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Bot-A' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    Start-NewHand -Game $game

    Invoke-BettingRound -Game $game -MaxTurns 10

    Assert-True (Is-BettingRoundClosed -Game $game)
    Assert-True ($null -eq $game.ActionSeat)
    Assert-True ([int]$game.CurrentBet -ge 20)

    $totalChipsAndBets = 0
    foreach ($player in $game.Players) {
        Assert-True ([int]$player.Chips -ge 0)
        $totalChipsAndBets += [int]$player.Chips + [int]$player.TotalBetThisHand
    }
    Assert-Equal 2000 $totalChipsAndBets
}

Run-TestCase "Heads-up short small blind all-in is skipped before action" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'BigBlind' -Type 'Bot' -Chips 100),
        (New-PlayerState -Seat 2 -Name 'ShortSmallBlind' -Type 'Bot' -Chips 8)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.DealerSeat = 1

    Start-NewHand -Game $game

    Assert-Equal 2 $game.DealerSeat
    Assert-Equal 'AllIn' (Get-PlayerBySeat -Game $game -Seat 2).Status
    Assert-Equal 1 $game.ActionSeat
    Assert-True (@(Get-LegalActions -Game $game -Seat $game.ActionSeat).Count -gt 0)
}

Run-TestCase "Invalid human command is ignored until a legal command is provided" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Human' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    Start-NewHand -Game $game
    $player = Get-PlayerBySeat -Game $game -Seat $game.ActionSeat
    $commands = @('w', 'call')
    $index = 0
    $provider = {
        $command = $commands[$script:index]
        $script:index++
        return $command
    }
    $script:index = 0

    $action = Get-LocalActionForPlayer -Game $game -Player $player -ActionProvider $provider

    Assert-Equal 'call' $action.Command
}

Run-TestCase "Numbered human command selects current legal action" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Human' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    Start-NewHand -Game $game
    $player = Get-PlayerBySeat -Game $game -Seat $game.ActionSeat
    $provider = { return '2' }

    $action = Get-LocalActionForPlayer -Game $game -Player $player -ActionProvider $provider

    Assert-Equal 'call' $action.Command
    Assert-True ($null -eq $action.Amount)
}

Run-TestCase "Game loop can detect whether another hand can start" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Human' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 2000),
        (New-PlayerState -Seat 3 -Name 'Bot-C' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Assert-True (Test-CanStartNextHand -Game $game)
    Assert-False (Test-PlayerCanContinue -Game $game -Seat 1)
}

Run-TestCase "Game loop refuses next hand when fewer than two players have chips" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Human' -Type 'HumanLocal' -Chips 0),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 2000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    Assert-False (Test-CanStartNextHand -Game $game)
}
