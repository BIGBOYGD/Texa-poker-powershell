function Build-Pots {
    param([Parameter(Mandatory = $true)]$Game)

    $contributors = @($Game.Players | Where-Object { [int]$_.TotalBetThisHand -gt 0 } | Sort-Object TotalBetThisHand)
    if ($contributors.Count -eq 0) {
        return @()
    }

    $levels = @($contributors | ForEach-Object { [int]$_.TotalBetThisHand } | Sort-Object -Unique)
    $previous = 0
    $pots = @()

    foreach ($level in $levels) {
        $layer = $level - $previous
        if ($layer -le 0) {
            continue
        }

        $layerContributors = @($contributors | Where-Object { [int]$_.TotalBetThisHand -ge $level })
        $eligibleSeats = @($layerContributors | Where-Object { $_.Status -ne 'Folded' } | Sort-Object Seat | ForEach-Object { [int]$_.Seat })
        $amount = $layer * $layerContributors.Count

        if ($amount -gt 0 -and $eligibleSeats.Count -gt 0) {
            $pots += [pscustomobject]@{
                Amount = $amount
                EligibleSeats = @($eligibleSeats)
            }
        }

        $previous = $level
    }

    return $pots
}

function Compare-PotHandResult {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )

    if (Get-Command Compare-HandResult -ErrorAction SilentlyContinue) {
        return Compare-HandResult -Left $Left -Right $Right
    }

    if ($Left.RankLevel -gt $Right.RankLevel) { return 1 }
    if ($Left.RankLevel -lt $Right.RankLevel) { return -1 }

    $leftKickers = @($Left.Kickers)
    $rightKickers = @($Right.Kickers)
    $length = [Math]::Max($leftKickers.Count, $rightKickers.Count)
    for ($i = 0; $i -lt $length; $i++) {
        $leftValue = if ($i -lt $leftKickers.Count) { [int]$leftKickers[$i] } else { 0 }
        $rightValue = if ($i -lt $rightKickers.Count) { [int]$rightKickers[$i] } else { 0 }
        if ($leftValue -gt $rightValue) { return 1 }
        if ($leftValue -lt $rightValue) { return -1 }
    }
    return 0
}

function Award-Pots {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][hashtable]$HandResults
    )

    foreach ($pot in @($Game.Pots)) {
        $bestResult = $null
        $winners = @()

        foreach ($seat in @($pot.EligibleSeats)) {
            if (-not $HandResults.ContainsKey($seat)) {
                continue
            }

            $result = $HandResults[$seat]
            if ($null -eq $bestResult) {
                $bestResult = $result
                $winners = @($seat)
                continue
            }

            $comparison = Compare-PotHandResult -Left $result -Right $bestResult
            if ($comparison -gt 0) {
                $bestResult = $result
                $winners = @($seat)
            } elseif ($comparison -eq 0) {
                $winners += $seat
            }
        }

        if ($winners.Count -eq 0) {
            continue
        }

        $sortedWinners = @($winners | Sort-Object)
        $share = [Math]::Floor([int]$pot.Amount / $sortedWinners.Count)
        $remainder = [int]$pot.Amount % $sortedWinners.Count

        for ($i = 0; $i -lt $sortedWinners.Count; $i++) {
            $player = Get-PlayerBySeat -Game $Game -Seat $sortedWinners[$i]
            $bonus = if ($i -lt $remainder) { 1 } else { 0 }
            $player.Chips = [int]$player.Chips + $share + $bonus
        }
    }
}
