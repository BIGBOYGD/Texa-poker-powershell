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
. "$PSScriptRoot\..\src\Bot\TightBot.ps1"
. "$PSScriptRoot\..\src\Bot\LooseBot.ps1"
. "$PSScriptRoot\..\src\Bot\RuleBot.ps1"
. "$PSScriptRoot\..\src\Bot\BotBase.ps1"

function Set-BotTuningBotType {
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

function New-BotTuningGame {
    $seatTypes = @('TightBot', 'LooseBot', 'RuleBot', 'TightBot', 'LooseBot', 'RuleBot')
    $players = @()
    for ($seat = 1; $seat -le 6; $seat++) {
        $type = $seatTypes[$seat - 1]
        $player = New-PlayerState -Seat $seat -Name "$type-$seat" -Type 'Bot' -Chips 50000
        Set-BotTuningBotType -Player $player -BotType $type
        $players += $player
    }

    return New-GameState -Players $players -SmallBlind 10 -BigBlind 20
}

function Get-BotTuningTotalChips {
    param([Parameter(Mandatory = $true)]$Game)

    $total = 0
    foreach ($player in $Game.Players) {
        $total += [int]$player.Chips
    }
    return $total
}

function Test-BotTuningCanStartNextHand {
    param([Parameter(Mandatory = $true)]$Game)

    return @($Game.Players | Where-Object { [int]$_.Chips -gt 0 }).Count -ge 2
}

function Add-BotTuningEvent {
    param(
        [Parameter(Mandatory = $true)]$Events,
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $true)]$Action
    )

    $botType = if ($Player.PSObject.Properties.Name -contains 'BotType' -and -not [string]::IsNullOrWhiteSpace($Player.BotType)) {
        [string]$Player.BotType
    } else {
        'RandomBot'
    }

    $Events.Add([pscustomobject]@{
        HandId = [int]$Game.HandId
        Street = [string]$Game.Street
        BotSeat = [int]$Player.Seat
        BotType = $botType
        SelectedAction = [string]$Action.Command
    }) | Out-Null
}

function Invoke-BotTuningBettingRound {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Events,
        [Parameter(Mandatory = $false)][int]$MaxTurns = 500
    )

    $turns = 0
    while (-not (Is-BettingRoundClosed -Game $Game)) {
        $turns++
        if ($turns -gt $MaxTurns) {
            throw "Bot tuning betting round exceeded $MaxTurns turns."
        }

        if ($null -eq $Game.ActionSeat) {
            $Game.ActionSeat = Get-NextSeat -Game $Game -Seat $Game.DealerSeat -ActionableOnly
        }

        $player = Get-PlayerBySeat -Game $Game -Seat $Game.ActionSeat
        $action = Get-BotAction -Game $Game -Player $player
        Add-BotTuningEvent -Events $Events -Game $Game -Player $player -Action $action
        Apply-PlayerAction -Game $Game -Seat $player.Seat -Command $action.Command -Amount $action.Amount
        Set-NextActionSeat -Game $Game
    }
}

function Invoke-BotTuningHand {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Events,
        [Parameter(Mandatory = $false)][int]$MaxTurns = 500
    )

    Start-NewHand -Game $Game

    while ($Game.Street -ne 'Finished') {
        if ($Game.Street -eq 'Showdown') {
            Resolve-Hand -Game $Game
            break
        }

        Invoke-BotTuningBettingRound -Game $Game -Events $Events -MaxTurns $MaxTurns

        $contenders = @(Get-ContendingPlayers -Game $Game)
        if ($contenders.Count -le 1) {
            Resolve-Hand -Game $Game
            break
        }

        Advance-Street -Game $Game
    }
}

function Get-BotTuningStats {
    param([Parameter(Mandatory = $true)]$Events)

    $stats = [ordered]@{}
    foreach ($type in @('TightBot', 'LooseBot', 'RuleBot')) {
        $eventsForType = @($Events | Where-Object { $_.BotType -eq $type })
        $preflopEvents = @($eventsForType | Where-Object { $_.Street -eq 'PreFlop' })
        $preflopHands = @($preflopEvents | ForEach-Object { "$($_.HandId):$($_.BotSeat)" } | Sort-Object -Unique)
        $vpipHands = @($preflopEvents | Where-Object {
            @('call', 'bet', 'raise', 'allin') -contains $_.SelectedAction
        } | ForEach-Object { "$($_.HandId):$($_.BotSeat)" } | Sort-Object -Unique)

        $eventCount = [Math]::Max(1, $eventsForType.Count)
        $stats[$type] = [pscustomobject]@{
            BotType = $type
            DecisionCount = $eventsForType.Count
            PreflopHandCount = $preflopHands.Count
            Vpip = [Math]::Round(($vpipHands.Count / [Math]::Max(1, $preflopHands.Count)), 3)
            FoldRate = [Math]::Round((@($eventsForType | Where-Object { $_.SelectedAction -eq 'fold' }).Count / $eventCount), 3)
            CallRate = [Math]::Round((@($eventsForType | Where-Object { $_.SelectedAction -eq 'call' }).Count / $eventCount), 3)
            BetRaiseRate = [Math]::Round((@($eventsForType | Where-Object { @('bet', 'raise') -contains $_.SelectedAction }).Count / $eventCount), 3)
            AllInRate = [Math]::Round((@($eventsForType | Where-Object { $_.SelectedAction -eq 'allin' }).Count / $eventCount), 3)
        }
    }

    return $stats
}

function Format-BotTuningStats {
    param([Parameter(Mandatory = $true)]$Stats)

    $parts = @()
    foreach ($type in @('TightBot', 'LooseBot', 'RuleBot')) {
        $item = $Stats[$type]
        $parts += "$type VPIP=$($item.Vpip), Fold=$($item.FoldRate), Call=$($item.CallRate), BetRaise=$($item.BetRaiseRate), AllIn=$($item.AllInRate)"
    }
    return ($parts -join '; ')
}

Run-TestCase "Bot tuning simulation records 200 hands and style metrics stay in target ranges" {
    Get-Random -SetSeed 40406 | Out-Null
    $game = New-BotTuningGame
    $events = New-Object System.Collections.Generic.List[object]
    $initialTotal = Get-BotTuningTotalChips -Game $game

    for ($hand = 1; $hand -le 200; $hand++) {
        Assert-True (Test-BotTuningCanStartNextHand -Game $game) "Not enough players with chips before hand $hand."
        Invoke-BotTuningHand -Game $game -Events $events -MaxTurns 500
        Assert-Equal $hand $game.HandId
        Assert-Equal 'Finished' $game.Street
        Assert-Equal $initialTotal (Get-BotTuningTotalChips -Game $game)
        foreach ($player in $game.Players) {
            Assert-True ([int]$player.Chips -ge 0) "Seat $($player.Seat) has negative chips."
        }
    }

    Assert-True ($events.Count -gt 0) 'Expected bot decision events for tuning statistics.'
    Assert-Equal 200 (($events.ToArray() | Measure-Object -Property HandId -Maximum).Maximum)

    $stats = Get-BotTuningStats -Events $events.ToArray()
    foreach ($type in @('TightBot', 'LooseBot', 'RuleBot')) {
        Assert-True ($stats[$type].DecisionCount -gt 0) "$type should have decisions."
        Assert-True ($stats[$type].PreflopHandCount -gt 0) "$type should have preflop samples."
    }

    $summary = Format-BotTuningStats -Stats $stats
    Write-Host "Bot tuning stats: $summary"
    Assert-True ($stats['TightBot'].Vpip -ge 0.15 -and $stats['TightBot'].Vpip -le 0.25) "TightBot VPIP $($stats['TightBot'].Vpip) outside 0.15-0.25. $summary"
    Assert-True ($stats['LooseBot'].Vpip -ge 0.35 -and $stats['LooseBot'].Vpip -le 0.55) "LooseBot VPIP $($stats['LooseBot'].Vpip) outside 0.35-0.55. $summary"
    Assert-True ($stats['RuleBot'].Vpip -ge 0.25 -and $stats['RuleBot'].Vpip -le 0.40) "RuleBot VPIP $($stats['RuleBot'].Vpip) outside 0.25-0.40. $summary"
    Assert-True ($stats['LooseBot'].BetRaiseRate -gt $stats['TightBot'].BetRaiseRate) "LooseBot bet/raise rate $($stats['LooseBot'].BetRaiseRate) should exceed TightBot $($stats['TightBot'].BetRaiseRate). $summary"

    foreach ($type in @('TightBot', 'LooseBot', 'RuleBot')) {
        Assert-True ($stats[$type].AllInRate -le 0.08) "$type all-in rate $($stats[$type].AllInRate) should stay low. $summary"
    }
}
