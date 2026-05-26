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
. "$PSScriptRoot\..\src\Persistence\DebugLogger.ps1"
. "$PSScriptRoot\..\src\Local\GameLoop.ps1"

function Reset-DebugLoggerTestRoot {
    $root = Join-Path $PSScriptRoot 'tmp_debug_logger'
    Clear-DebugLoggerTestRoot -Root $root
    return $root
}

function Clear-DebugLoggerTestRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
}

function Get-DebugLoggerTestFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $logDir = Join-Path $Root 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $logDir -Filter '*_debug.jsonl' -File)
}

function Set-DebugLoggerTestBotType {
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

function New-DebugLoggerTestGame {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'RuleBot-A' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'TightBot-B' -Type 'Bot' -Chips 1000)
    )
    Set-DebugLoggerTestBotType -Player $players[0] -BotType 'RuleBot'
    Set-DebugLoggerTestBotType -Player $players[1] -BotType 'TightBot'

    return New-GameState -Players $players -SmallBlind 10 -BigBlind 20
}

function Copy-DebugLoggerGameState {
    param([Parameter(Mandatory = $true)]$Game)

    @($Game.Players | Sort-Object Seat | ForEach-Object {
        "$($_.Seat):$($_.Chips):$($_.StreetBet):$($_.TotalBetThisHand):$($_.Status):$($_.HasActedThisRound)"
    })
}

function Get-DebugLoggerTotalChips {
    param([Parameter(Mandatory = $true)]$Game)

    $total = 0
    foreach ($player in $Game.Players) {
        $total += [int]$player.Chips + [int]$player.TotalBetThisHand
    }
    return $total
}

Run-TestCase "Debug logger disabled mode does not create debug log files" {
    $root = Reset-DebugLoggerTestRoot
    $null = Initialize-DebugLogger -Enabled:$false -RootPath $root

    $game = New-DebugLoggerTestGame
    Invoke-LocalHand -Game $game -MaxTurns 100

    Assert-Equal 0 @(Get-DebugLoggerTestFiles -Root $root).Count
    Disable-DebugLogger
    Clear-DebugLoggerTestRoot -Root $root
}

Run-TestCase "Debug logger enabled mode writes bot decision jsonl event" {
    $root = Reset-DebugLoggerTestRoot
    $logPath = Initialize-DebugLogger -Enabled:$true -RootPath $root

    $game = New-DebugLoggerTestGame
    Invoke-LocalHand -Game $game -MaxTurns 100

    Assert-True (Test-Path -LiteralPath $logPath)
    $lines = @(Get-Content -LiteralPath $logPath -Encoding UTF8)
    Assert-True ($lines.Count -gt 0) 'Expected at least one debug log line.'
    $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
    $event = @($events | Where-Object { $_.EventType -eq 'BotDecision' } | Select-Object -First 1)[0]
    Assert-True ($null -ne $event) 'Expected a BotDecision debug event.'

    foreach ($field in @(
        'Timestamp',
        'EventType',
        'HandId',
        'Street',
        'BotSeat',
        'BotName',
        'BotType',
        'ToCall',
        'PotSize',
        'CurrentBet',
        'MinRaise',
        'PreflopScore',
        'PostflopScore',
        'DrawScore',
        'PositionScore',
        'PotOdds',
        'FinalScore',
        'LegalActions',
        'SelectedAction',
        'SelectedAmount',
        'Reason',
        'ConnectionId',
        'PlayerId',
        'MessageType',
        'Seq',
        'Direction',
        'ErrorMessage'
    )) {
        Assert-True ($event.PSObject.Properties.Name -contains $field) "Debug event missing field $field."
    }

    Assert-Equal 'BotDecision' $event.EventType
    Assert-True (@('RandomBot', 'TightBot', 'LooseBot', 'RuleBot') -contains $event.BotType)
    Assert-True (@('fold', 'check', 'call', 'bet', 'raise', 'allin') -contains $event.SelectedAction)
    Assert-True (@($event.LegalActions).Count -gt 0)
    Assert-True ([int]$event.Seq -ge 1)
    Disable-DebugLogger
    Clear-DebugLoggerTestRoot -Root $root
}

Run-TestCase "Debug logger does not mutate game state or chip totals" {
    $root = Reset-DebugLoggerTestRoot
    $null = Initialize-DebugLogger -Enabled:$true -RootPath $root

    $game = New-DebugLoggerTestGame
    Start-NewHand -Game $game
    $player = Get-PlayerBySeat -Game $game -Seat $game.ActionSeat
    $action = Get-BotAction -Game $game -Player $player
    $beforeState = Copy-DebugLoggerGameState -Game $game
    $beforeTotal = Get-DebugLoggerTotalChips -Game $game

    Write-BotDecisionDebugLog -Game $game -Player $player -Action $action

    $afterState = Copy-DebugLoggerGameState -Game $game
    $afterTotal = Get-DebugLoggerTotalChips -Game $game
    Assert-SequenceEqual $beforeState $afterState
    Assert-Equal $beforeTotal $afterTotal
    Disable-DebugLogger
    Clear-DebugLoggerTestRoot -Root $root
}
