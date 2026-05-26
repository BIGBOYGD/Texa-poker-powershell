. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Bot\BotProfiles.ps1"
. "$PSScriptRoot\..\src\Bot\BotEvaluator.ps1"
. "$PSScriptRoot\..\src\Bot\BotDecision.ps1"

function New-BotDecisionTestCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

function New-BotDecisionTestGame {
    param(
        [Parameter(Mandatory = $false)][string[]]$HoleCards = @('As', 'Ah'),
        [Parameter(Mandatory = $false)][string]$Street = 'PreFlop',
        [Parameter(Mandatory = $false)][int]$CurrentBet = 100,
        [Parameter(Mandatory = $false)][int]$BotStreetBet = 0,
        [Parameter(Mandatory = $false)][int]$BotChips = 1000,
        [Parameter(Mandatory = $false)][object[]]$CommunityCards = @()
    )

    $players = @(
        (New-PlayerState -Seat 1 -Name 'Bot-A' -Type 'Bot' -Chips $BotChips),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 3 -Name 'Bot-C' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.HandId = 12
    $game.Street = $Street
    $game.DealerSeat = 3
    $game.ActionSeat = 1
    $game.CurrentBet = $CurrentBet
    $game.MinRaise = 100
    $game.CommunityCards = @($CommunityCards)

    $players[0].HoleCards = @(New-BotDecisionTestCards $HoleCards)
    $players[0].StreetBet = $BotStreetBet
    $players[0].TotalBetThisHand = $BotStreetBet
    $players[1].StreetBet = $CurrentBet
    $players[1].TotalBetThisHand = $CurrentBet
    $players[2].StreetBet = $CurrentBet
    $players[2].TotalBetThisHand = $CurrentBet

    return [pscustomobject]@{
        Game = $game
        Player = $players[0]
    }
}

function Copy-BotDecisionState {
    param([Parameter(Mandatory = $true)]$Game)

    [pscustomobject]@{
        CurrentBet = $Game.CurrentBet
        MinRaise = $Game.MinRaise
        ActionSeat = $Game.ActionSeat
        PotCount = @($Game.Pots).Count
        PlayerRows = @($Game.Players | Sort-Object Seat | ForEach-Object {
            "$($_.Seat):$($_.Chips):$($_.StreetBet):$($_.TotalBetThisHand):$($_.Status):$($_.HasActedThisRound)"
        })
    }
}

Run-TestCase "Bot decision context exposes scores and public betting state" {
    $setup = New-BotDecisionTestGame -HoleCards @('As', 'Ks') -CurrentBet 100 -BotStreetBet 20
    $profile = Get-DefaultBotProfile -Name 'RuleBot'
    $legalActions = @(Get-LegalActions -Game $setup.Game -Seat $setup.Player.Seat)

    $ctx = New-BotDecisionContext -Game $setup.Game -Player $setup.Player -Profile $profile -LegalActions $legalActions

    Assert-Equal 12 $ctx.HandId
    Assert-Equal 'PreFlop' $ctx.Street
    Assert-Equal 1 $ctx.BotSeat
    Assert-Equal 80 $ctx.ToCall
    Assert-Equal 220 $ctx.PotSize
    Assert-True ($ctx.PreflopScore -gt 0)
    Assert-True ($ctx.PotOdds -gt 0)
    Assert-SequenceEqual @('fold', 'call', 'raise', 'allin') @($ctx.LegalActions | ForEach-Object { $_.Command })
}

Run-TestCase "Bot decision returns legal action object without changing game state" {
    $setup = New-BotDecisionTestGame -HoleCards @('As', 'Ah') -CurrentBet 100
    $profile = Get-DefaultBotProfile -Name 'RuleBot'
    $profile.randomness = 0
    $before = Copy-BotDecisionState -Game $setup.Game
    $legalActions = @(Get-LegalActions -Game $setup.Game -Seat $setup.Player.Seat)
    $ctx = New-BotDecisionContext -Game $setup.Game -Player $setup.Player -Profile $profile -LegalActions $legalActions

    $decision = Get-BotDecision -Context $ctx -LegalActions $legalActions
    $after = Copy-BotDecisionState -Game $setup.Game

    Assert-True ($null -ne $decision)
    Assert-True ($decision.PSObject.Properties.Name -contains 'Command')
    Assert-True ($decision.PSObject.Properties.Name -contains 'Amount')
    Assert-True ($decision.PSObject.Properties.Name -contains 'Reason')
    Assert-True ($decision.PSObject.Properties.Name -contains 'FinalScore')
    Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $decision.Command -Amount $decision.Amount)
    Assert-Equal $before.CurrentBet $after.CurrentBet
    Assert-Equal $before.MinRaise $after.MinRaise
    Assert-SequenceEqual $before.PlayerRows $after.PlayerRows
}

Run-TestCase "Select legal bot action degrades unavailable raise to call" {
    $legalActions = @(
        [pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null },
        [pscustomobject]@{ Command = 'call'; MinAmount = $null; MaxAmount = $null },
        [pscustomobject]@{ Command = 'allin'; MinAmount = $null; MaxAmount = $null }
    )
    $ctx = [pscustomobject]@{
        ToCall = 80
        FinalScore = 85
        PotSize = 240
        CurrentBet = 100
        MinRaise = 100
        Chips = 1000
    }

    $decision = Select-LegalBotAction -Context $ctx -LegalActions $legalActions -PreferredCommand 'raise' -PreferredAmount 200 -Reason 'strong hand'

    Assert-Equal 'call' $decision.Command
    Assert-True ($null -eq $decision.Amount)
    Assert-Equal 85 $decision.FinalScore
}

Run-TestCase "Bot bet amount is clamped to legal range" {
    $ctx = [pscustomobject]@{
        PotSize = 1000
        CurrentBet = 100
        MinRaise = 100
        Chips = 500
        StreetBet = 0
    }
    $action = [pscustomobject]@{ Command = 'raise'; MinAmount = 200; MaxAmount = 500 }

    $amount = Get-BotBetAmount -Context $ctx -Action $action -DecisionType 'value'

    Assert-True ($amount -ge 200)
    Assert-True ($amount -le 500)
}

Run-TestCase "Weak hand facing large call folds more often than loose profile" {
    $setup = New-BotDecisionTestGame -HoleCards @('7s', '2d') -CurrentBet 700 -BotStreetBet 0
    $legalActions = @(Get-LegalActions -Game $setup.Game -Seat $setup.Player.Seat)
    $tight = Get-DefaultBotProfile -Name 'TightBot'
    $loose = Get-DefaultBotProfile -Name 'LooseBot'
    $tight.randomness = 0
    $loose.randomness = 0

    $tightCtx = New-BotDecisionContext -Game $setup.Game -Player $setup.Player -Profile $tight -LegalActions $legalActions
    $looseCtx = New-BotDecisionContext -Game $setup.Game -Player $setup.Player -Profile $loose -LegalActions $legalActions
    $tightDecision = Get-BotDecision -Context $tightCtx -LegalActions $legalActions
    $looseDecision = Get-BotDecision -Context $looseCtx -LegalActions $legalActions

    Assert-Equal 'fold' $tightDecision.Command
    Assert-True ($looseDecision.FinalScore -gt $tightDecision.FinalScore)
}

Run-TestCase "Strong hand prefers continuing over folding" {
    $setup = New-BotDecisionTestGame -HoleCards @('As', 'Ah') -CurrentBet 100 -BotStreetBet 0
    $profile = Get-DefaultBotProfile -Name 'RuleBot'
    $profile.randomness = 0
    $legalActions = @(Get-LegalActions -Game $setup.Game -Seat $setup.Player.Seat)
    $ctx = New-BotDecisionContext -Game $setup.Game -Player $setup.Player -Profile $profile -LegalActions $legalActions

    $decision = Get-BotDecision -Context $ctx -LegalActions $legalActions

    Assert-True (@('call', 'raise', 'allin') -contains $decision.Command)
    Assert-True ($decision.FinalScore -ge 80)
}

Run-TestCase "Bot decision produces only legal actions for 1000 contexts" {
    $profiles = @(
        (Get-DefaultBotProfile -Name 'TightBot'),
        (Get-DefaultBotProfile -Name 'LooseBot'),
        (Get-DefaultBotProfile -Name 'RuleBot')
    )
    $holeCardSets = @(
        @('As', 'Ah'),
        @('As', 'Ks'),
        @('8s', '8h'),
        @('7s', '6s'),
        @('7s', '2d')
    )

    for ($i = 0; $i -lt 1000; $i++) {
        $hole = $holeCardSets[$i % $holeCardSets.Count]
        $currentBet = @(0, 40, 100, 300, 700)[$i % 5]
        $streetBet = if ($currentBet -eq 0) { 0 } else { @(0, 20, 100)[$i % 3] }
        if ($streetBet -gt $currentBet) { $streetBet = $currentBet }
        $setup = New-BotDecisionTestGame -HoleCards $hole -CurrentBet $currentBet -BotStreetBet $streetBet
        $profile = $profiles[$i % $profiles.Count]
        $legalActions = @(Get-LegalActions -Game $setup.Game -Seat $setup.Player.Seat)

        $ctx = New-BotDecisionContext -Game $setup.Game -Player $setup.Player -Profile $profile -LegalActions $legalActions
        $decision = Get-BotDecision -Context $ctx -LegalActions $legalActions

        Assert-True (Test-PlayerActionLegal -Game $setup.Game -Seat $setup.Player.Seat -Command $decision.Command -Amount $decision.Amount) "Illegal decision at iteration ${i}: $($decision.Command) $($decision.Amount)"
    }
}
