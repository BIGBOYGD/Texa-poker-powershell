function New-HandResult {
    param(
        [Parameter(Mandatory = $true)][int]$RankLevel,
        [Parameter(Mandatory = $true)][string]$RankName,
        [Parameter(Mandatory = $true)][int[]]$Kickers,
        [Parameter(Mandatory = $true)][object[]]$BestCards
    )

    [pscustomobject]@{
        RankLevel = $RankLevel
        RankName = $RankName
        Kickers = @($Kickers)
        BestCards = @($BestCards)
    }
}

function Get-StraightHigh {
    param([Parameter(Mandatory = $true)][int[]]$Ranks)

    $unique = @($Ranks | Sort-Object -Unique -Descending)
    if ($unique.Count -ne 5) {
        return $null
    }

    if (($unique -contains 14) -and ($unique -contains 5) -and ($unique -contains 4) -and ($unique -contains 3) -and ($unique -contains 2)) {
        return 5
    }

    if (($unique[0] - $unique[4]) -eq 4) {
        return $unique[0]
    }

    return $null
}

function Get-RankGroups {
    param([Parameter(Mandatory = $true)][int[]]$Ranks)

    $counts = @{}
    foreach ($rank in $Ranks) {
        if (-not $counts.ContainsKey($rank)) {
            $counts[$rank] = 0
        }
        $counts[$rank]++
    }

    $groups = foreach ($key in $counts.Keys) {
        [pscustomobject]@{
            Rank = [int]$key
            Count = [int]$counts[$key]
        }
    }

    return @($groups | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Rank'; Descending = $true })
}

function Evaluate-Hand5 {
    param([Parameter(Mandatory = $true)][object[]]$Cards)

    if (@($Cards).Count -ne 5) {
        throw "Evaluate-Hand5 requires exactly 5 cards."
    }

    $ranks = @($Cards | ForEach-Object { [int]$_.Rank } | Sort-Object -Descending)
    $suitCount = @($Cards | ForEach-Object { $_.Suit } | Sort-Object -Unique).Count
    $isFlush = $suitCount -eq 1
    $straightHigh = Get-StraightHigh -Ranks $ranks
    $groups = @(Get-RankGroups -Ranks $ranks)

    if ($isFlush -and $null -ne $straightHigh) {
        return New-HandResult -RankLevel 9 -RankName 'Straight Flush' -Kickers @($straightHigh) -BestCards $Cards
    }

    if ($groups[0].Count -eq 4) {
        $kickerGroup = $groups | Where-Object { $_.Count -eq 1 } | Select-Object -First 1
        $kicker = $kickerGroup.Rank
        return New-HandResult -RankLevel 8 -RankName 'Four of a Kind' -Kickers @($groups[0].Rank, $kicker) -BestCards $Cards
    }

    if ($groups[0].Count -eq 3 -and $groups[1].Count -eq 2) {
        return New-HandResult -RankLevel 7 -RankName 'Full House' -Kickers @($groups[0].Rank, $groups[1].Rank) -BestCards $Cards
    }

    if ($isFlush) {
        return New-HandResult -RankLevel 6 -RankName 'Flush' -Kickers $ranks -BestCards $Cards
    }

    if ($null -ne $straightHigh) {
        return New-HandResult -RankLevel 5 -RankName 'Straight' -Kickers @($straightHigh) -BestCards $Cards
    }

    if ($groups[0].Count -eq 3) {
        $kickers = @($groups | Where-Object { $_.Count -eq 1 } | ForEach-Object { $_.Rank } | Sort-Object -Descending)
        $combinedKickers = @($groups[0].Rank) + $kickers
        return New-HandResult -RankLevel 4 -RankName 'Three of a Kind' -Kickers $combinedKickers -BestCards $Cards
    }

    if ($groups[0].Count -eq 2 -and $groups[1].Count -eq 2) {
        $pairs = @($groups | Where-Object { $_.Count -eq 2 } | ForEach-Object { $_.Rank } | Sort-Object -Descending)
        $kickerGroup = $groups | Where-Object { $_.Count -eq 1 } | Select-Object -First 1
        $kicker = $kickerGroup.Rank
        return New-HandResult -RankLevel 3 -RankName 'Two Pair' -Kickers @($pairs[0], $pairs[1], $kicker) -BestCards $Cards
    }

    if ($groups[0].Count -eq 2) {
        $kickers = @($groups | Where-Object { $_.Count -eq 1 } | ForEach-Object { $_.Rank } | Sort-Object -Descending)
        $combinedKickers = @($groups[0].Rank) + $kickers
        return New-HandResult -RankLevel 2 -RankName 'One Pair' -Kickers $combinedKickers -BestCards $Cards
    }

    return New-HandResult -RankLevel 1 -RankName 'High Card' -Kickers $ranks -BestCards $Cards
}

function Compare-HandResult {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )

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

function Evaluate-Hand7 {
    param([Parameter(Mandatory = $true)][object[]]$Cards)

    if (@($Cards).Count -ne 7) {
        throw "Evaluate-Hand7 requires exactly 7 cards."
    }

    $best = $null
    for ($a = 0; $a -lt 3; $a++) {
        for ($b = $a + 1; $b -lt 4; $b++) {
            for ($c = $b + 1; $c -lt 5; $c++) {
                for ($d = $c + 1; $d -lt 6; $d++) {
                    for ($e = $d + 1; $e -lt 7; $e++) {
                        $combo = @($Cards[$a], $Cards[$b], $Cards[$c], $Cards[$d], $Cards[$e])
                        $result = Evaluate-Hand5 -Cards $combo
                        if ($null -eq $best -or (Compare-HandResult -Left $result -Right $best) -gt 0) {
                            $best = $result
                        }
                    }
                }
            }
        }
    }

    return $best
}
