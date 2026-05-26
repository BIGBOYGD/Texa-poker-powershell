function Limit-BotScore {
    param([Parameter(Mandatory = $true)][double]$Score)

    if ($Score -lt 0) { return 0 }
    if ($Score -gt 100) { return 100 }
    return [int][Math]::Round($Score)
}

function Get-VisibleHandResult {
    param([Parameter(Mandatory = $true)][object[]]$Cards)

    $visibleCards = @($Cards)
    if ($visibleCards.Count -lt 5) {
        return $null
    }

    if ($visibleCards.Count -eq 5) {
        return Evaluate-Hand5 -Cards $visibleCards
    }

    if ($visibleCards.Count -eq 7) {
        return Evaluate-Hand7 -Cards $visibleCards
    }

    $best = $null
    for ($a = 0; $a -lt ($visibleCards.Count - 4); $a++) {
        for ($b = $a + 1; $b -lt ($visibleCards.Count - 3); $b++) {
            for ($c = $b + 1; $c -lt ($visibleCards.Count - 2); $c++) {
                for ($d = $c + 1; $d -lt ($visibleCards.Count - 1); $d++) {
                    for ($e = $d + 1; $e -lt $visibleCards.Count; $e++) {
                        $result = Evaluate-Hand5 -Cards @($visibleCards[$a], $visibleCards[$b], $visibleCards[$c], $visibleCards[$d], $visibleCards[$e])
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

function Get-PreflopHandScore {
    param([Parameter(Mandatory = $true)][object[]]$HoleCards)

    $cards = @($HoleCards)
    if ($cards.Count -ne 2) {
        throw 'Get-PreflopHandScore requires exactly two hole cards.'
    }

    $rankA = [int]$cards[0].Rank
    $rankB = [int]$cards[1].Rank
    $high = [Math]::Max($rankA, $rankB)
    $low = [Math]::Min($rankA, $rankB)
    $gap = $high - $low

    $score = $high * 4
    if ($rankA -eq $rankB) { $score += 35 }
    if ($cards[0].Suit -eq $cards[1].Suit) { $score += 6 }
    if ($gap -eq 1) { $score += 8 }
    elseif ($gap -eq 2) { $score += 4 }
    if ($rankA -ge 10 -and $rankB -ge 10) { $score += 10 }
    if ($high -eq 14 -and $low -ge 10) { $score += 8 }
    if ($rankA -ne $rankB -and $high -le 7 -and $cards[0].Suit -ne $cards[1].Suit -and $gap -gt 1) { $score -= 15 }

    return Limit-BotScore -Score $score
}

function Get-PostflopHandScore {
    param(
        [Parameter(Mandatory = $true)][object[]]$HoleCards,
        [Parameter(Mandatory = $true)][object[]]$CommunityCards
    )

    $cards = @($HoleCards) + @($CommunityCards)
    $result = Get-VisibleHandResult -Cards $cards
    if ($null -eq $result) {
        return Get-PreflopHandScore -HoleCards $HoleCards
    }

    $topKicker = if (@($result.Kickers).Count -gt 0) { [int]@($result.Kickers)[0] } else { 0 }
    switch ([int]$result.RankLevel) {
        9 { return Limit-BotScore -Score (98 + (($topKicker - 5) / 9) * 2) }
        8 { return Limit-BotScore -Score (95 + (($topKicker - 2) / 12) * 4) }
        7 { return Limit-BotScore -Score (90 + (($topKicker - 2) / 12) * 7) }
        6 { return Limit-BotScore -Score (82 + (($topKicker - 2) / 12) * 10) }
        5 { return Limit-BotScore -Score (78 + (($topKicker - 5) / 9) * 12) }
        4 { return Limit-BotScore -Score (68 + (($topKicker - 2) / 12) * 14) }
        3 { return Limit-BotScore -Score (58 + (($topKicker - 2) / 12) * 14) }
        2 {
            $pairRank = $topKicker
            if ($pairRank -ge 10) {
                return Limit-BotScore -Score (45 + (($pairRank - 10) / 4) * 20)
            }
            return Limit-BotScore -Score (30 + (($pairRank - 2) / 7) * 18)
        }
        default { return Limit-BotScore -Score (($topKicker - 2) / 12 * 35) }
    }
}

function Get-DrawPotentialScore {
    param(
        [Parameter(Mandatory = $true)][object[]]$HoleCards,
        [Parameter(Mandatory = $true)][object[]]$CommunityCards
    )

    $community = @($CommunityCards)
    if ($community.Count -ge 5) {
        return 0
    }

    $cards = @($HoleCards) + $community
    $score = 0

    $suitGroups = $cards | Group-Object Suit
    if (@($suitGroups | Where-Object { $_.Count -ge 4 }).Count -gt 0) {
        $score += 15
    }

    $ranks = @($cards | ForEach-Object { [int]$_.Rank })
    if ($ranks -contains 14) {
        $ranks += 1
    }
    $uniqueRanks = @($ranks | Sort-Object -Unique)

    $openEnded = $false
    $gutshot = $false
    for ($start = 1; $start -le 10; $start++) {
        $window = @($start..($start + 4))
        $hits = @($window | Where-Object { $uniqueRanks -contains $_ }).Count
        $missing = @($window | Where-Object { $uniqueRanks -notcontains $_ })

        if ($hits -eq 4) {
            if ($missing[0] -eq $start -or $missing[0] -eq ($start + 4)) {
                $openEnded = $true
            } else {
                $gutshot = $true
            }
        }
    }

    if ($openEnded) {
        $score += 12
    } elseif ($gutshot) {
        $score += 6
    }

    $holeRanks = @($HoleCards | ForEach-Object { [int]$_.Rank })
    if ($holeRanks.Count -eq 2 -and $holeRanks[0] -ge 10 -and $holeRanks[1] -ge 10 -and $holeRanks[0] -ne $holeRanks[1]) {
        $hasPair = @($cards | Group-Object Rank | Where-Object { $_.Count -ge 2 }).Count -gt 0
        if (-not $hasPair) {
            $score += 4
        }
    }

    if (@($cards | Group-Object Rank | Where-Object { $_.Count -eq 2 }).Count -gt 0) {
        $score += 5
    }

    return Limit-BotScore -Score $score
}

function Get-PotOdds {
    param(
        [Parameter(Mandatory = $true)][int]$ToCall,
        [Parameter(Mandatory = $true)][int]$PotSize
    )

    if ($ToCall -le 0) {
        return 0.0
    }

    $denominator = $PotSize + $ToCall
    if ($denominator -le 0) {
        return 0.0
    }

    return [Math]::Round(($ToCall / $denominator), 4)
}

function Get-PositionScore {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player
    )

    $activeSeats = @($Game.Players | Where-Object { @('Folded', 'Out') -notcontains $_.Status } | Sort-Object Seat | ForEach-Object { [int]$_.Seat })
    if ($activeSeats.Count -le 1) {
        return 0
    }

    $dealerIndex = [Array]::IndexOf($activeSeats, [int]$Game.DealerSeat)
    $playerIndex = [Array]::IndexOf($activeSeats, [int]$Player.Seat)
    if ($dealerIndex -lt 0 -or $playerIndex -lt 0) {
        return 0
    }

    if ([int]$Player.Seat -eq [int]$Game.DealerSeat) {
        return 8
    }

    $distanceAfterDealer = ($playerIndex - $dealerIndex + $activeSeats.Count) % $activeSeats.Count
    if ($Game.Street -ne 'PreFlop' -and $distanceAfterDealer -eq 1) {
        return -3
    }

    if ($distanceAfterDealer -ge ($activeSeats.Count - 2)) {
        return 8
    }

    if ($distanceAfterDealer -ge [Math]::Floor($activeSeats.Count / 2)) {
        return 3
    }

    return 0
}
