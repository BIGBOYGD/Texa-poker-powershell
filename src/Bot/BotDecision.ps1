function Get-BotObjectValue {
    param(
        [Parameter(Mandatory = $false)][AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function New-BotDecisionContext {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $false)]$LegalActions
    )

    $actions = if ($PSBoundParameters.ContainsKey('LegalActions')) {
        @($LegalActions)
    } else {
        @(Get-LegalActions -Game $Game -Seat $Player.Seat)
    }

    $potSize = 0
    foreach ($tablePlayer in $Game.Players) {
        $potSize += [int]$tablePlayer.TotalBetThisHand
    }

    $toCall = [Math]::Max(0, [int]$Game.CurrentBet - [int]$Player.StreetBet)
    $activeOpponentCount = @($Game.Players | Where-Object {
        [int]$_.Seat -ne [int]$Player.Seat -and @('Folded', 'Out') -notcontains $_.Status
    }).Count

    $holeCards = @($Player.HoleCards)
    $communityCards = @($Game.CommunityCards)
    $preflopScore = if ($holeCards.Count -eq 2) { Get-PreflopHandScore -HoleCards $holeCards } else { 0 }
    $postflopScore = if ($Game.Street -eq 'PreFlop' -or $holeCards.Count -ne 2) {
        0
    } else {
        Get-PostflopHandScore -HoleCards $holeCards -CommunityCards $communityCards
    }
    $drawScore = if ($Game.Street -eq 'PreFlop' -or $holeCards.Count -ne 2) {
        0
    } else {
        Get-DrawPotentialScore -HoleCards $holeCards -CommunityCards $communityCards
    }

    [pscustomobject]@{
        HandId = $Game.HandId
        Street = $Game.Street
        BotSeat = $Player.Seat
        BotName = $Player.Name
        BotType = Get-BotObjectValue -Object $Player -Name 'BotType' -Default 'RandomBot'
        HoleCards = $holeCards
        CommunityCards = $communityCards
        Chips = [int]$Player.Chips
        StreetBet = [int]$Player.StreetBet
        TotalBetThisHand = [int]$Player.TotalBetThisHand
        PotSize = [int]$potSize
        CurrentBet = [int]$Game.CurrentBet
        MinRaise = [int]$Game.MinRaise
        ToCall = [int]$toCall
        LegalActions = $actions
        ActiveOpponentCount = [int]$activeOpponentCount
        PositionScore = [int](Get-PositionScore -Game $Game -Player $Player)
        Profile = $Profile
        PreflopScore = [int]$preflopScore
        PostflopScore = [int]$postflopScore
        DrawScore = [int]$drawScore
        PotOdds = [double](Get-PotOdds -ToCall $toCall -PotSize $potSize)
    }
}

function Get-BotDecisionScore {
    param([Parameter(Mandatory = $true)]$Context)

    $profile = $Context.Profile
    $aggression = [double](Get-BotObjectValue -Object $profile -Name 'aggression' -Default 0.30)
    $raiseBias = [double](Get-BotObjectValue -Object $profile -Name 'raiseBias' -Default 0.25)
    $riskTolerance = [double](Get-BotObjectValue -Object $profile -Name 'riskTolerance' -Default 0.35)
    $randomness = [double](Get-BotObjectValue -Object $profile -Name 'randomness' -Default 0.0)

    $baseScore = if ($Context.Street -eq 'PreFlop') {
        [double]$Context.PreflopScore
    } else {
        [double]$Context.PostflopScore + [double]$Context.DrawScore
    }

    $stackExposure = [double]$Context.ToCall / [Math]::Max(1, ([double]$Context.Chips + [double]$Context.StreetBet))
    $potPressurePenalty = $stackExposure * 50.0 * (1.0 - $riskTolerance)
    $opponentPenalty = [Math]::Max(0, [int]$Context.ActiveOpponentCount - 1) * 1.5
    $noise = 0.0
    if ($randomness -gt 0) {
        $noise = ((Get-Random -Minimum -1000 -Maximum 1001) / 1000.0) * $randomness * 50.0
    }

    $score = $baseScore +
        [double]$Context.PositionScore +
        ($aggression * 10.0) +
        ($raiseBias * 5.0) -
        $potPressurePenalty -
        $opponentPenalty +
        $noise

    return Limit-BotScore -Score $score
}

function Get-BotBetAmount {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $false)][ValidateSet('value', 'semiBluff', 'bluff', 'probe', 'strongValue')][string]$DecisionType = 'value'
    )

    if ($null -eq $Action.MinAmount) {
        return $null
    }

    $ratio = switch ($DecisionType) {
        'probe' { 0.35 }
        'bluff' { 0.35 }
        'semiBluff' { 0.50 }
        'strongValue' { 0.85 }
        default { 0.65 }
    }

    $desired = if ($Action.Command -eq 'raise') {
        [int]$Context.CurrentBet + [int][Math]::Round([Math]::Max([int]$Context.MinRaise, [double]$Context.PotSize * $ratio))
    } else {
        [int][Math]::Round([Math]::Max([int]$Context.MinRaise, [double]$Context.PotSize * $ratio))
    }

    $amount = [Math]::Max([int]$Action.MinAmount, $desired)
    $amount = [Math]::Min([int]$Action.MaxAmount, $amount)
    return [int]$amount
}

function New-BotDecisionResult {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)][Nullable[int]]$Amount,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][int]$FinalScore
    )

    [pscustomobject]@{
        Command = $Command
        Amount = $Amount
        Reason = $Reason
        FinalScore = $FinalScore
    }
}

function Select-LegalBotAction {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$LegalActions,
        [Parameter(Mandatory = $true)][string]$PreferredCommand,
        [Parameter(Mandatory = $false)][Nullable[int]]$PreferredAmount,
        [Parameter(Mandatory = $false)][string]$Reason = 'selected by bot decision'
    )

    $actions = @($LegalActions)
    if ($actions.Count -eq 0) {
        throw 'Bot has no legal action.'
    }

    $finalScore = if ($Context.PSObject.Properties.Name -contains 'FinalScore') {
        [int]$Context.FinalScore
    } else {
        Get-BotDecisionScore -Context $Context
    }

    $fallbacks = switch ($PreferredCommand) {
        'raise' { @('raise', 'call', 'check', 'bet', 'fold', 'allin') }
        'bet' { @('bet', 'check', 'call', 'fold', 'allin') }
        'call' { @('call', 'check', 'fold', 'allin') }
        'check' { @('check', 'call', 'fold', 'allin') }
        'allin' { @('allin', 'raise', 'bet', 'call', 'check', 'fold') }
        default { @($PreferredCommand, 'check', 'call', 'fold', 'allin') }
    }

    foreach ($command in $fallbacks) {
        $action = @($actions | Where-Object { $_.Command -eq $command } | Select-Object -First 1)
        if ($action.Count -eq 0) {
            continue
        }

        $selected = $action[0]
        $amount = $null
        if ($null -ne $selected.MinAmount) {
            if ($null -ne $PreferredAmount -and $command -eq $PreferredCommand) {
                $amount = [Math]::Max([int]$selected.MinAmount, [int]$PreferredAmount)
                $amount = [Math]::Min([int]$selected.MaxAmount, [int]$amount)
            } else {
                $amount = Get-BotBetAmount -Context $Context -Action $selected -DecisionType 'value'
            }
        }

        return New-BotDecisionResult -Command $selected.Command -Amount $amount -Reason $Reason -FinalScore $finalScore
    }

    throw 'No fallback legal bot action could be selected.'
}

function Test-BotCanCallProfitably {
    param([Parameter(Mandatory = $true)]$Context)

    $profile = $Context.Profile
    $callTolerance = [double](Get-BotObjectValue -Object $profile -Name 'callTolerance' -Default 0.35)
    $estimatedEquity = ([double]$Context.FinalScore / 100.0) + ($callTolerance * 0.15)
    return $estimatedEquity -ge [double]$Context.PotOdds
}

function Get-BotDecision {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$LegalActions
    )

    $finalScore = Get-BotDecisionScore -Context $Context
    $ctx = $Context | Select-Object *
    $ctx | Add-Member -NotePropertyName FinalScore -NotePropertyValue $finalScore -Force
    $profile = $ctx.Profile
    $aggression = [double](Get-BotObjectValue -Object $profile -Name 'aggression' -Default 0.30)
    $raiseBias = [double](Get-BotObjectValue -Object $profile -Name 'raiseBias' -Default 0.25)
    $bluffRate = [double](Get-BotObjectValue -Object $profile -Name 'bluffRate' -Default 0.05)
    $callTolerance = [double](Get-BotObjectValue -Object $profile -Name 'callTolerance' -Default 0.35)
    $riskTolerance = [double](Get-BotObjectValue -Object $profile -Name 'riskTolerance' -Default 0.35)
    $vpip = [double](Get-BotObjectValue -Object $profile -Name 'vpip' -Default 0.30)

    $commands = @($LegalActions | ForEach-Object { $_.Command })
    $preferredCommand = 'fold'
    $reason = 'weak hand facing pressure'
    $preferredAmount = $null

    if ([int]$ctx.ToCall -eq 0) {
        $bluffSignal = $bluffRate + ($aggression * 0.08) + ($raiseBias * 0.04)
        if ([int]$ctx.ActiveOpponentCount -le 1) {
            $bluffSignal += 0.05
        } else {
            $bluffSignal -= ([int]$ctx.ActiveOpponentCount - 1) * 0.04
        }

        if ($finalScore -ge 75) {
            $preferredCommand = if ($commands -contains 'bet') { 'bet' } elseif ($commands -contains 'raise') { 'raise' } else { 'check' }
            $reason = 'strong score with no call required'
        } elseif ($finalScore -ge 55) {
            $attackThreshold = $aggression + $raiseBias
            $preferredCommand = if ($attackThreshold -ge 0.85 -and ($commands -contains 'bet')) { 'bet' } else { 'check' }
            $reason = 'medium score controls pot'
        } elseif ($finalScore -ge 35) {
            $preferredCommand = if ($bluffSignal -ge 0.13 -and ($commands -contains 'bet')) { 'bet' } else { 'check' }
            $reason = 'marginal score checks or probes'
        } else {
            $preferredCommand = if ($bluffSignal -ge 0.22 -and ($commands -contains 'bet')) { 'bet' } else { 'check' }
            $reason = 'weak score checks'
        }
    } else {
        $callPressure = [double]$ctx.ToCall / [Math]::Max(1, ([double]$ctx.Chips + [double]$ctx.StreetBet))
        $shortStackThreshold = [Math]::Max(1, ([double]$ctx.PotSize * 0.25))
        $preflopEntryScore = 70.0 - ($vpip * 30.0)
        if ($ctx.Street -eq 'PreFlop' -and $finalScore -lt $preflopEntryScore) {
            $preferredCommand = 'fold'
            $reason = 'preflop score below profile entry range'
        } elseif ($finalScore -ge 88 -and $riskTolerance -ge 0.35 -and ($commands -contains 'allin') -and ([int]$ctx.Chips -le $shortStackThreshold)) {
            $preferredCommand = 'allin'
            $reason = 'premium score with short stack'
        } elseif ($finalScore -ge 82) {
            $preferredCommand = if ($commands -contains 'raise' -and ($aggression + $raiseBias) -ge 0.75) { 'raise' } else { 'call' }
            $reason = 'strong score continues'
        } elseif ($finalScore -ge 60) {
            $preferredCommand = if (Test-BotCanCallProfitably -Context $ctx) { 'call' } else { 'fold' }
            $reason = 'medium score uses pot odds'
        } elseif ($finalScore -ge 40) {
            $preferredCommand = if ($callPressure -le ($riskTolerance * 0.35)) { 'call' } else { 'fold' }
            $reason = 'marginal score calls only small pressure'
        } else {
            $looseCallPressureLimit = $riskTolerance * $callTolerance
            $loosePotLimit = [double]$ctx.ToCall -le ([double]$ctx.PotSize * 0.60)
            $looseSmallCall = ($riskTolerance -ge 0.55 -and $callPressure -le $looseCallPressureLimit -and $loosePotLimit)
            $preferredCommand = if ($looseSmallCall) { 'call' } else { 'fold' }
            $reason = 'low score folds to pressure'
        }
    }

    if ($preferredCommand -in @('bet', 'raise')) {
        $action = @($LegalActions | Where-Object { $_.Command -eq $preferredCommand } | Select-Object -First 1)
        if ($action.Count -gt 0) {
            $decisionType = if ($finalScore -ge 85) { 'strongValue' } elseif ($finalScore -ge 65) { 'value' } else { 'probe' }
            $preferredAmount = Get-BotBetAmount -Context $ctx -Action $action[0] -DecisionType $decisionType
        }
    }

    return Select-LegalBotAction -Context $ctx -LegalActions $LegalActions -PreferredCommand $preferredCommand -PreferredAmount $preferredAmount -Reason $reason
}
