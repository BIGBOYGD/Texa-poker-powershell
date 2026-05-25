function New-AdvisorText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function ConvertTo-ChineseHandRankName {
    param([Parameter(Mandatory = $true)][string]$RankName)

    switch ($RankName) {
        'Straight Flush' { return (New-AdvisorText @(0x540c, 0x82b1, 0x987a)) }
        'Four of a Kind' { return (New-AdvisorText @(0x56db, 0x6761)) }
        'Full House' { return (New-AdvisorText @(0x846b, 0x82a6)) }
        'Flush' { return (New-AdvisorText @(0x540c, 0x82b1)) }
        'Straight' { return (New-AdvisorText @(0x987a, 0x5b50)) }
        'Three of a Kind' { return (New-AdvisorText @(0x4e09, 0x6761)) }
        'Two Pair' { return (New-AdvisorText @(0x4e24, 0x5bf9)) }
        'One Pair' { return (New-AdvisorText @(0x4e00, 0x5bf9)) }
        'High Card' { return (New-AdvisorText @(0x9ad8, 0x724c)) }
        default { return $RankName }
    }
}

function ConvertTo-AdvisorRankText {
    param([Parameter(Mandatory = $true)][int]$Rank)

    switch ($Rank) {
        14 { return 'A' }
        13 { return 'K' }
        12 { return 'Q' }
        11 { return 'J' }
        10 { return '10' }
        default { return [string]$Rank }
    }
}

function New-AdvisorHandSummary {
    param(
        [Parameter(Mandatory = $true)][int]$RankLevel,
        [Parameter(Mandatory = $true)][string]$RankName,
        [Parameter(Mandatory = $false)][string]$Detail = ''
    )

    [pscustomobject]@{
        RankLevel = $RankLevel
        RankName = $RankName
        Detail = $Detail
    }
}

function Get-PartialHandSummary {
    param([Parameter(Mandatory = $true)][object[]]$Cards)

    $rankCounts = @{}
    foreach ($card in @($Cards)) {
        $rank = [int]$card.Rank
        if (-not $rankCounts.ContainsKey($rank)) {
            $rankCounts[$rank] = 0
        }
        $rankCounts[$rank]++
    }

    $groupRows = foreach ($key in $rankCounts.Keys) {
        [pscustomobject]@{ Rank = [int]$key; Count = [int]$rankCounts[$key] }
    }
    $groups = @($groupRows | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Rank'; Descending = $true })

    if ($groups.Count -eq 0) {
        return New-AdvisorHandSummary -RankLevel 0 -RankName (New-AdvisorText @(0x672a, 0x77e5))
    }

    if ($groups[0].Count -ge 4) {
        return New-AdvisorHandSummary -RankLevel 8 -RankName (ConvertTo-ChineseHandRankName -RankName 'Four of a Kind') -Detail (ConvertTo-AdvisorRankText -Rank $groups[0].Rank)
    }

    if ($groups[0].Count -eq 3) {
        return New-AdvisorHandSummary -RankLevel 4 -RankName (ConvertTo-ChineseHandRankName -RankName 'Three of a Kind') -Detail (ConvertTo-AdvisorRankText -Rank $groups[0].Rank)
    }

    $pairs = @($groups | Where-Object { $_.Count -eq 2 } | Sort-Object Rank -Descending)
    if ($pairs.Count -ge 2) {
        return New-AdvisorHandSummary -RankLevel 3 -RankName (ConvertTo-ChineseHandRankName -RankName 'Two Pair') -Detail "$(ConvertTo-AdvisorRankText -Rank $pairs[0].Rank)/$(ConvertTo-AdvisorRankText -Rank $pairs[1].Rank)"
    }

    if ($pairs.Count -eq 1) {
        return New-AdvisorHandSummary -RankLevel 2 -RankName (ConvertTo-ChineseHandRankName -RankName 'One Pair') -Detail (ConvertTo-AdvisorRankText -Rank $pairs[0].Rank)
    }

    $highRank = @($Cards | ForEach-Object { [int]$_.Rank } | Sort-Object -Descending | Select-Object -First 1)[0]
    return New-AdvisorHandSummary -RankLevel 1 -RankName (ConvertTo-ChineseHandRankName -RankName 'High Card') -Detail (ConvertTo-AdvisorRankText -Rank $highRank)
}

function Evaluate-BestKnownHand {
    param([Parameter(Mandatory = $true)][object[]]$Cards)

    $knownCards = @($Cards)
    if ($knownCards.Count -lt 5) {
        return Get-PartialHandSummary -Cards $knownCards
    }

    if ($knownCards.Count -eq 5) {
        return Evaluate-Hand5 -Cards $knownCards
    }

    $best = $null
    for ($a = 0; $a -lt ($knownCards.Count - 4); $a++) {
        for ($b = $a + 1; $b -lt ($knownCards.Count - 3); $b++) {
            for ($c = $b + 1; $c -lt ($knownCards.Count - 2); $c++) {
                for ($d = $c + 1; $d -lt ($knownCards.Count - 1); $d++) {
                    for ($e = $d + 1; $e -lt $knownCards.Count; $e++) {
                        $combo = @($knownCards[$a], $knownCards[$b], $knownCards[$c], $knownCards[$d], $knownCards[$e])
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

function Get-CurrentBestHandSummary {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$HoleCards,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CommunityCards
    )

    $cards = @($HoleCards) + @($CommunityCards)
    $result = Evaluate-BestKnownHand -Cards $cards
    $detail = ''
    if ($result.PSObject.Properties.Name -contains 'Detail') {
        $detail = [string]$result.Detail
    } elseif ($result.Kickers.Count -gt 0) {
        $detail = ConvertTo-AdvisorRankText -Rank ([int]$result.Kickers[0])
    }

    return New-AdvisorHandSummary -RankLevel ([int]$result.RankLevel) -RankName (ConvertTo-ChineseHandRankName -RankName $result.RankName) -Detail $detail
}

function Get-RemainingAdvisorDeck {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$HoleCards,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CommunityCards
    )

    $known = @{}
    foreach ($card in (@($HoleCards) + @($CommunityCards))) {
        $known[[string]$card.Text] = $true
    }

    return @(New-Deck | Where-Object { -not $known.ContainsKey([string]$_.Text) })
}

function Select-AdvisorRandomCards {
    param(
        [Parameter(Mandatory = $true)][object[]]$Cards,
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][System.Random]$Random
    )

    $pool = @($Cards)
    for ($i = 0; $i -lt $Count; $i++) {
        $index = $Random.Next($i, $pool.Count)
        $tmp = $pool[$i]
        $pool[$i] = $pool[$index]
        $pool[$index] = $tmp
    }

    if ($Count -le 0) {
        return @()
    }

    return @($pool[0..($Count - 1)])
}

function Add-AdvisorPredictionCount {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Counts,
        [Parameter(Mandatory = $true)][hashtable]$Levels,
        [Parameter(Mandatory = $true)][object[]]$Cards
    )

    $result = Evaluate-BestKnownHand -Cards $Cards
    $rankName = [string]$result.RankName
    if (-not $Counts.ContainsKey($rankName)) {
        $Counts[$rankName] = 0
        $Levels[$rankName] = [int]$result.RankLevel
    }
    $Counts[$rankName]++
}

function Get-HandTypePredictions {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$HoleCards,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CommunityCards,
        [Parameter(Mandatory = $false)][ValidateRange(1, 10000)][int]$SampleCount = 120,
        [Parameter(Mandatory = $false)][int]$Seed = 1776,
        [Parameter(Mandatory = $false)][ValidateRange(1, 10)][int]$Top = 3
    )

    if (@($CommunityCards).Count -gt 5) {
        throw "Community cards cannot exceed 5."
    }

    $missing = 5 - @($CommunityCards).Count
    $deck = @(Get-RemainingAdvisorDeck -HoleCards @($HoleCards) -CommunityCards @($CommunityCards))
    if ($missing -gt $deck.Count) {
        throw "Not enough remaining cards to complete the board."
    }

    $counts = @{}
    $levels = @{}
    $total = 0

    if ($missing -eq 0) {
        Add-AdvisorPredictionCount -Counts $counts -Levels $levels -Cards (@($HoleCards) + @($CommunityCards))
        $total = 1
    } elseif ($missing -eq 1) {
        for ($i = 0; $i -lt $deck.Count; $i++) {
            Add-AdvisorPredictionCount -Counts $counts -Levels $levels -Cards (@($HoleCards) + @($CommunityCards) + @($deck[$i]))
            $total++
        }
    } else {
        $random = [System.Random]::new($Seed)
        for ($sample = 0; $sample -lt $SampleCount; $sample++) {
            $drawn = @(Select-AdvisorRandomCards -Cards $deck -Count $missing -Random $random)
            Add-AdvisorPredictionCount -Counts $counts -Levels $levels -Cards (@($HoleCards) + @($CommunityCards) + $drawn)
            $total++
        }
    }

    $rankRows = foreach ($rankName in $counts.Keys) {
        [pscustomobject]@{
            RankName = ConvertTo-ChineseHandRankName -RankName $rankName
            Count = [int]$counts[$rankName]
            Probability = [Math]::Round(([double]$counts[$rankName] * 100.0 / [double]$total), 1)
            RankLevel = [int]$levels[$rankName]
        }
    }

    return @($rankRows | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'RankLevel'; Descending = $true } | Select-Object -First $Top)
}
