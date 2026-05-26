. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Bot\BotProfiles.ps1"
. "$PSScriptRoot\..\src\Bot\BotEvaluator.ps1"
. "$PSScriptRoot\..\src\Bot\BotDecision.ps1"
. "$PSScriptRoot\..\src\Bot\RandomBot.ps1"
. "$PSScriptRoot\..\src\Bot\TightBot.ps1"
. "$PSScriptRoot\..\src\Bot\LooseBot.ps1"
. "$PSScriptRoot\..\src\Bot\RuleBot.ps1"
. "$PSScriptRoot\..\src\Bot\BotBase.ps1"

function New-BotStrategyTestCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

function Set-TestBotType {
    param(
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $true)][string]$BotType
    )

    if ($Player.PSObject.Properties.Name -contains 'BotType') {
        $Player.BotType = $BotType
    } else {
        $Player | Add-Member -NotePropertyName BotType -NotePropertyValue $BotType
    }
}

function New-BotStrategyTestGame {
    param(
        [Parameter(Mandatory = $true)][string]$BotType,
        [Parameter(Mandatory = $false)][string[]]$HoleCards = @('7s', '2d'),
        [Parameter(Mandatory = $false)][int]$CurrentBet = 100,
        [Parameter(Mandatory = $false)][int]$BotStreetBet = 0,
        [Parameter(Mandatory = $false)][string]$Street = 'PreFlop',
        [Parameter(Mandatory = $false)][string[]]$CommunityCards = @(),
        [Parameter(Mandatory = $false)][ValidateRange(1, 2)][int]$ActiveOpponentCount = 2
    )

    $players = @(
        (New-PlayerState -Seat 1 -Name 'StrategyBot' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Caller' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 3 -Name 'Raiser' -Type 'Bot' -Chips 1000)
    )
    Set-TestBotType -Player $players[0] -BotType $BotType

    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.HandId = 40
    $game.Street = $Street
    $game.CommunityCards = if (@($CommunityCards).Count -gt 0) { @(New-BotStrategyTestCards $CommunityCards) } else { @() }
    $game.DealerSeat = 3
    $game.ActionSeat = 1
    $game.CurrentBet = $CurrentBet
    $game.MinRaise = 100

    $players[0].HoleCards = @(New-BotStrategyTestCards $HoleCards)
    $players[0].StreetBet = $BotStreetBet
    $players[0].TotalBetThisHand = $BotStreetBet
    $players[1].StreetBet = $CurrentBet
    $players[1].TotalBetThisHand = $CurrentBet
    $players[2].StreetBet = $CurrentBet
    $players[2].TotalBetThisHand = $CurrentBet
    if ($ActiveOpponentCount -eq 1) {
        $players[2].Status = 'Folded'
        $players[2].StreetBet = 0
        $players[2].TotalBetThisHand = 0
    }

    return [pscustomobject]@{
        Game = $game
        Player = $players[0]
    }
}

function Copy-BotStrategyState {
    param([Parameter(Mandatory = $true)]$Game)

    @($Game.Players | Sort-Object Seat | ForEach-Object {
        "$($_.Seat):$($_.Chips):$($_.StreetBet):$($_.TotalBetThisHand):$($_.Status):$($_.HasActedThisRound)"
    })
}

Run-TestCase "BotBase dispatches TightBot by BotType" {
    $setup = New-BotStrategyTestGame -BotType 'TightBot' -HoleCards @('7s', '2d') -CurrentBet 700
    $before = Copy-BotStrategyState -Game $setup.Game

    $action = Get-BotAction -Game $setup.Game -Player $setup.Player
    $after = Copy-BotStrategyState -Game $setup.Game

    Assert-Equal 'fold' $action.Command
    Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $action.Command -Amount $action.Amount)
    Assert-SequenceEqual $before $after
}

Run-TestCase "BotBase dispatches LooseBot by BotType" {
    $setup = New-BotStrategyTestGame -BotType 'LooseBot' -HoleCards @('7s', '6s') -CurrentBet 0

    $action = Get-BotAction -Game $setup.Game -Player $setup.Player

    Assert-True (@('bet', 'check') -contains $action.Command)
    Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $action.Command -Amount $action.Amount)
    Assert-True ($action.PSObject.Properties.Name -contains 'Reason')
    Assert-True ($action.PSObject.Properties.Name -contains 'FinalScore')
}

Run-TestCase "TightBot folds marginal hands against pressure more than LooseBot" {
    Get-Random -SetSeed 40404 | Out-Null
    $tightFolds = 0
    $looseFolds = 0

    for ($i = 0; $i -lt 200; $i++) {
        $tightSetup = New-BotStrategyTestGame -BotType 'TightBot' -HoleCards @('As', '2d') -CurrentBet 100
        $looseSetup = New-BotStrategyTestGame -BotType 'LooseBot' -HoleCards @('As', '2d') -CurrentBet 100

        if ((Get-TightBotAction -Game $tightSetup.Game -Player $tightSetup.Player).Command -eq 'fold') {
            $tightFolds++
        }
        if ((Get-LooseBotAction -Game $looseSetup.Game -Player $looseSetup.Player).Command -eq 'fold') {
            $looseFolds++
        }
    }

    Assert-True ($tightFolds -gt $looseFolds) "TightBot fold count $tightFolds should be greater than LooseBot fold count $looseFolds."
}

Run-TestCase "LooseBot bets medium playable hands more than TightBot when checking is free" {
    $tightBets = 0
    $looseBets = 0

    for ($i = 0; $i -lt 200; $i++) {
        $tightSetup = New-BotStrategyTestGame -BotType 'TightBot' -HoleCards @('7s', '6s') -CurrentBet 0
        $looseSetup = New-BotStrategyTestGame -BotType 'LooseBot' -HoleCards @('7s', '6s') -CurrentBet 0

        if ((Get-TightBotAction -Game $tightSetup.Game -Player $tightSetup.Player).Command -eq 'bet') {
            $tightBets++
        }
        if ((Get-LooseBotAction -Game $looseSetup.Game -Player $looseSetup.Player).Command -eq 'bet') {
            $looseBets++
        }
    }

    Assert-True ($looseBets -gt $tightBets) "LooseBot bet count $looseBets should be greater than TightBot bet count $tightBets."
}

Run-TestCase "BotBase dispatches RuleBot by BotType" {
    $setup = New-BotStrategyTestGame -BotType 'RuleBot' -HoleCards @('As', 'Ah') -CurrentBet 100
    $before = Copy-BotStrategyState -Game $setup.Game

    $action = Get-BotAction -Game $setup.Game -Player $setup.Player
    $after = Copy-BotStrategyState -Game $setup.Game

    Assert-True (@('call', 'raise', 'allin') -contains $action.Command) "RuleBot should continue with pocket aces, got $($action.Command)."
    Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $action.Command -Amount $action.Amount)
    Assert-True ($action.PSObject.Properties.Name -contains 'Reason')
    Assert-True ($action.PSObject.Properties.Name -contains 'FinalScore')
    Assert-SequenceEqual $before $after
}

Run-TestCase "RuleBot rarely folds premium hands against normal pressure" {
    $folds = 0

    for ($i = 0; $i -lt 200; $i++) {
        $setup = New-BotStrategyTestGame -BotType 'RuleBot' -HoleCards @('As', 'Ah') -CurrentBet 100
        $action = Get-RuleBotAction -Game $setup.Game -Player $setup.Player
        if ($action.Command -eq 'fold') {
            $folds++
        }
    }

    Assert-True ($folds -le 5) "RuleBot folded premium hands $folds times."
}

Run-TestCase "RuleBot folds weak hands against large pressure often" {
    $folds = 0

    for ($i = 0; $i -lt 200; $i++) {
        $setup = New-BotStrategyTestGame -BotType 'RuleBot' -HoleCards @('7s', '2d') -CurrentBet 700
        $action = Get-RuleBotAction -Game $setup.Game -Player $setup.Player
        if ($action.Command -eq 'fold') {
            $folds++
        }
    }

    Assert-True ($folds -ge 160) "RuleBot should fold weak hands to large pressure often; folded $folds times."
}

Run-TestCase "RuleBot calls strong draws when pot odds are acceptable" {
    $calls = 0

    for ($i = 0; $i -lt 200; $i++) {
        $setup = New-BotStrategyTestGame `
            -BotType 'RuleBot' `
            -HoleCards @('As', '2s') `
            -Street 'Flop' `
            -CommunityCards @('Ks', '9s', '4d') `
            -CurrentBet 80

        $action = Get-RuleBotAction -Game $setup.Game -Player $setup.Player
        if (@('call', 'raise', 'allin') -contains $action.Command) {
            $calls++
        }
    }

    Assert-True ($calls -ge 140) "RuleBot should continue strong draws with acceptable pot odds; continued $calls times."
}

Run-TestCase "RuleBot bluffs less in multiway pots than heads-up pots" {
    $headsUpBets = 0
    $multiwayBets = 0

    for ($i = 0; $i -lt 200; $i++) {
        $headsUpSetup = New-BotStrategyTestGame -BotType 'RuleBot' -HoleCards @('7s', '6d') -CurrentBet 0 -ActiveOpponentCount 1
        $multiwaySetup = New-BotStrategyTestGame -BotType 'RuleBot' -HoleCards @('7s', '6d') -CurrentBet 0 -ActiveOpponentCount 2

        if ((Get-RuleBotAction -Game $headsUpSetup.Game -Player $headsUpSetup.Player).Command -eq 'bet') {
            $headsUpBets++
        }
        if ((Get-RuleBotAction -Game $multiwaySetup.Game -Player $multiwaySetup.Player).Command -eq 'bet') {
            $multiwayBets++
        }
    }

    Assert-True ($headsUpBets -gt $multiwayBets) "RuleBot heads-up bluff bets $headsUpBets should be greater than multiway bluff bets $multiwayBets."
}

Run-TestCase "RuleBot chooses only legal actions for 1000 decisions" {
    $holeCardSets = @(
        @('As', 'Ah'),
        @('As', 'Ks'),
        @('8s', '8h'),
        @('As', '2s'),
        @('7s', '6d'),
        @('7s', '2d')
    )

    for ($i = 0; $i -lt 1000; $i++) {
        $hole = $holeCardSets[$i % $holeCardSets.Count]
        $currentBet = @(0, 40, 80, 100, 300, 700)[$i % 6]
        $streetBet = if ($currentBet -eq 0) { 0 } else { @(0, 20, 80)[$i % 3] }
        if ($streetBet -gt $currentBet) { $streetBet = $currentBet }

        $street = if (($i % 4) -eq 0) { 'Flop' } else { 'PreFlop' }
        $board = if ($street -eq 'Flop') { @('Ks', '9s', '4d') } else { @() }
        $setup = New-BotStrategyTestGame -BotType 'RuleBot' -HoleCards $hole -CurrentBet $currentBet -BotStreetBet $streetBet -Street $street -CommunityCards $board
        $before = Copy-BotStrategyState -Game $setup.Game
        $action = Get-BotAction -Game $setup.Game -Player $setup.Player
        $after = Copy-BotStrategyState -Game $setup.Game

        Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $action.Command -Amount $action.Amount) "Illegal RuleBot decision at iteration ${i}: $($action.Command) $($action.Amount)"
        Assert-SequenceEqual $before $after
    }
}

Run-TestCase "TightBot and LooseBot choose only legal actions for 1000 decisions" {
    $botTypes = @('TightBot', 'LooseBot')
    $holeCardSets = @(
        @('As', 'Ah'),
        @('As', 'Ks'),
        @('8s', '8h'),
        @('7s', '6s'),
        @('7s', '2d')
    )

    for ($i = 0; $i -lt 1000; $i++) {
        $botType = $botTypes[$i % $botTypes.Count]
        $hole = $holeCardSets[$i % $holeCardSets.Count]
        $currentBet = @(0, 40, 100, 300, 700)[$i % 5]
        $streetBet = if ($currentBet -eq 0) { 0 } else { @(0, 20, 100)[$i % 3] }
        if ($streetBet -gt $currentBet) { $streetBet = $currentBet }

        $setup = New-BotStrategyTestGame -BotType $botType -HoleCards $hole -CurrentBet $currentBet -BotStreetBet $streetBet
        $action = Get-BotAction -Game $setup.Game -Player $setup.Player

        Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $action.Command -Amount $action.Amount) "Illegal $botType decision at iteration ${i}: $($action.Command) $($action.Amount)"
    }
}
