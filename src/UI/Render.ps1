function New-RenderText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function ConvertTo-DisplayStatus {
    param([Parameter(Mandatory = $true)][string]$Status)

    switch ($Status) {
        'Waiting' { return (New-RenderText @(0x7b49, 0x5f85)) }
        'Acting' { return (New-RenderText @(0x884c, 0x52a8, 0x4e2d)) }
        'Folded' { return (New-RenderText @(0x5df2, 0x5f03, 0x724c)) }
        'AllIn' { return (New-RenderText @(0x5168, 0x4e0b)) }
        'Out' { return (New-RenderText @(0x51fa, 0x5c40)) }
        default { return $Status }
    }
}

function ConvertTo-DisplayType {
    param([Parameter(Mandatory = $true)][string]$Type)

    switch ($Type) {
        'HumanLocal' { return (New-RenderText @(0x771f, 0x4eba)) }
        'Bot' { return (New-RenderText @(0x673a, 0x5668, 0x4eba)) }
        'RemoteHuman' { return (New-RenderText @(0x8054, 0x673a, 0x73a9, 0x5bb6)) }
        default { return $Type }
    }
}

function ConvertTo-DisplayStreet {
    param([Parameter(Mandatory = $true)][string]$Street)

    switch ($Street) {
        'PreFlop' { return (New-RenderText @(0x7ffb, 0x724c, 0x524d)) }
        'Flop' { return (New-RenderText @(0x7ffb, 0x724c, 0x5708)) }
        'Turn' { return (New-RenderText @(0x8f6c, 0x724c, 0x5708)) }
        'River' { return (New-RenderText @(0x6cb3, 0x724c, 0x5708)) }
        'Showdown' { return (New-RenderText @(0x644a, 0x724c)) }
        'Finished' { return (New-RenderText @(0x5df2, 0x7ed3, 0x675f)) }
        default { return $Street }
    }
}

function ConvertTo-DisplayRank {
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

function ConvertTo-DisplaySuit {
    param([Parameter(Mandatory = $true)][string]$Suit)

    switch ($Suit) {
        'S' { return (New-RenderText @(0x9ed1, 0x6843)) }
        'H' { return (New-RenderText @(0x7ea2, 0x6843)) }
        'D' { return (New-RenderText @(0x65b9, 0x5757)) }
        'C' { return (New-RenderText @(0x6885, 0x82b1)) }
        default { return $Suit }
    }
}

function ConvertTo-DisplayCard {
    param([Parameter(Mandatory = $true)]$Card)

    return "$(ConvertTo-DisplaySuit -Suit $Card.Suit)$(ConvertTo-DisplayRank -Rank $Card.Rank)"
}

function ConvertTo-DisplayAction {
    param([Parameter(Mandatory = $true)]$Action)

    $name = switch ($Action.Command) {
        'fold' { New-RenderText @(0x5f03, 0x724c) }
        'check' { New-RenderText @(0x8fc7, 0x724c) }
        'call' { New-RenderText @(0x8ddf, 0x6ce8) }
        'bet' { New-RenderText @(0x4e0b, 0x6ce8) }
        'raise' { New-RenderText @(0x52a0, 0x6ce8) }
        'allin' { New-RenderText @(0x5168, 0x4e0b) }
        default { $Action.Command }
    }

    if ($null -ne $Action.MinAmount) {
        return "$name $($Action.MinAmount)-$($Action.MaxAmount)"
    }

    return $name
}

function Format-NumberedLegalActions {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actions)

    $items = @()
    $index = 1
    foreach ($action in @($Actions)) {
        $items += "$index. $(ConvertTo-DisplayAction -Action $action)"
        $index++
    }

    return ($items -join ', ')
}

function Format-CardList {
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Cards = @(),
        [Parameter(Mandatory = $false)][int]$TotalSlots = 0
    )

    $items = @($Cards | ForEach-Object { "[$(ConvertTo-DisplayCard -Card $_)]" })
    while ($items.Count -lt $TotalSlots) {
        $items += '[??]'
    }
    if ($items.Count -eq 0) {
        return '(none)'
    }
    return ($items -join ' ')
}

function Format-HandSummaryText {
    param([Parameter(Mandatory = $true)]$Summary)

    $text = [string]$Summary.RankName
    if (-not [string]::IsNullOrWhiteSpace([string]$Summary.Detail)) {
        $text = "$text $($Summary.Detail)"
    }
    return $text
}

function Get-RevealedHandsLines {
    param([Parameter(Mandatory = $true)]$Game)

    $seatLabel = New-RenderText @(0x5ea7, 0x4f4d)
    $header = "$(New-RenderText @(0x6240, 0x6709, 0x73a9, 0x5bb6, 0x624b, 0x724c)):"
    $bestLabel = New-RenderText @(0x6700, 0x5927, 0x724c, 0x578b)
    $lines = @($header)

    foreach ($player in @($Game.Players | Sort-Object Seat)) {
        if (@($player.HoleCards).Count -gt 0) {
            $line = "$seatLabel$($player.Seat) $($player.Name): $(Format-CardList -Cards @($player.HoleCards))"
            if (Get-Command Get-CurrentBestHandSummary -ErrorAction SilentlyContinue) {
                $summary = Get-CurrentBestHandSummary -HoleCards @($player.HoleCards) -CommunityCards @($Game.CommunityCards)
                $line = "$line  $bestLabel`: $(Format-HandSummaryText -Summary $summary)"
            }
            $lines += $line
        }
    }

    return $lines
}

function Get-PotTotal {
    param([Parameter(Mandatory = $true)]$Game)

    $total = 0
    foreach ($player in $Game.Players) {
        $total += [int]$player.TotalBetThisHand
    }
    return $total
}

function Get-PlayerAdviceLines {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$ViewerSeat
    )

    if (-not (Get-Command Get-CurrentBestHandSummary -ErrorAction SilentlyContinue) -or -not (Get-Command Get-HandTypePredictions -ErrorAction SilentlyContinue)) {
        return @()
    }

    $viewer = Get-PlayerBySeat -Game $Game -Seat $ViewerSeat
    if ($null -eq $viewer -or @($viewer.HoleCards).Count -eq 0) {
        return @()
    }

    $currentLabel = New-RenderText @(0x5f53, 0x524d, 0x6700, 0x5927, 0x724c, 0x578b)
    $predictionLabel = New-RenderText @(0x9ad8, 0x6982, 0x7387, 0x6210, 0x724c, 0x9884, 0x6d4b)
    $lines = @()

    $current = Get-CurrentBestHandSummary -HoleCards @($viewer.HoleCards) -CommunityCards @($Game.CommunityCards)
    $currentText = Format-HandSummaryText -Summary $current
    $lines += "$currentLabel`: $currentText"

    $predictions = @(Get-HandTypePredictions -HoleCards @($viewer.HoleCards) -CommunityCards @($Game.CommunityCards) -Top 3)
    if ($predictions.Count -gt 0) {
        $lines += "$predictionLabel`:"
        for ($i = 0; $i -lt $predictions.Count; $i++) {
            $lines += "$($i + 1). $($predictions[$i].RankName) $($predictions[$i].Probability)%"
        }
    }

    return $lines
}

function Render-Table {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $false)][Nullable[int]]$ViewerSeat,
        [Parameter(Mandatory = $false)][switch]$ShowAllCards
    )

    Write-Host '============================================================'
    $pokerName = New-RenderText @(0x5fb7, 0x5dde, 0x6251, 0x514b)
    $firstLabel = New-RenderText @(0x7b2c)
    $handLabel = New-RenderText @(0x624b, 0x724c)
    $blindLabel = New-RenderText @(0x76f2, 0x6ce8)
    Write-Host "PowerShell $pokerName  $firstLabel $($Game.HandId) $handLabel  $blindLabel $($Game.SmallBlind)/$($Game.BigBlind)"

    $dealerLabel = New-RenderText @(0x5e84, 0x5bb6)
    $seatLabel = New-RenderText @(0x5ea7, 0x4f4d)
    $streetLabel = New-RenderText @(0x9636, 0x6bb5)
    $potLabel = New-RenderText @(0x5e95, 0x6c60)
    $currentBetLabel = New-RenderText @(0x5f53, 0x524d, 0x4e0b, 0x6ce8)
    Write-Host "$dealerLabel`: $seatLabel $($Game.DealerSeat)   $streetLabel`: $(ConvertTo-DisplayStreet -Street $Game.Street)   $potLabel`: $(Get-PotTotal -Game $Game)   $currentBetLabel`: $($Game.CurrentBet)"

    $boardLabel = New-RenderText @(0x516c, 0x5171, 0x724c)
    Write-Host "$boardLabel`: $(Format-CardList -Cards @($Game.CommunityCards) -TotalSlots 5)"
    Write-Host '------------------------------------------------------------'

    $chipsLabel = New-RenderText @(0x7b79, 0x7801)
    $betLabel = New-RenderText @(0x672c, 0x8f6e, 0x4e0b, 0x6ce8)
    $statusLabel = New-RenderText @(0x72b6, 0x6001)
    $youLabel = New-RenderText @(0x4f60)
    foreach ($player in @($Game.Players | Sort-Object Seat)) {
        $marker = if ($player.Seat -eq $ViewerSeat) { $youLabel } else { ConvertTo-DisplayType -Type $player.Type }
        $displayStatus = ConvertTo-DisplayStatus -Status $player.Status
        Write-Host ("{0}{1,-2} {2,-12} {3}:{4,-5} {5}:{6,-4} {7}:{8,-8} {9}" -f $seatLabel, $player.Seat, $player.Name, $chipsLabel, $player.Chips, $betLabel, $player.StreetBet, $statusLabel, $displayStatus, $marker)
    }

    Write-Host '------------------------------------------------------------'
    if ($null -ne $ViewerSeat) {
        $viewer = Get-PlayerBySeat -Game $Game -Seat $ViewerSeat
        $yourCardsLabel = New-RenderText @(0x4f60, 0x7684, 0x624b, 0x724c)
        Write-Host "$yourCardsLabel`: $(Format-CardList -Cards @($viewer.HoleCards))"
        foreach ($line in @(Get-PlayerAdviceLines -Game $Game -ViewerSeat $ViewerSeat)) {
            Write-Host $line
        }
        if ($Game.Street -ne 'Finished') {
            $toCallLabel = New-RenderText @(0x9700, 0x8981, 0x8ddf, 0x6ce8)
            $toCall = [Math]::Max(0, [int]$Game.CurrentBet - [int]$viewer.StreetBet)
            Write-Host "$toCallLabel`: $toCall"
            $actions = @(Get-LegalActions -Game $Game -Seat $ViewerSeat)
            $legalActionsLabel = New-RenderText @(0x53ef, 0x7528, 0x547d, 0x4ee4)
            Write-Host "$legalActionsLabel`: $(Format-NumberedLegalActions -Actions $actions)"
        } else {
            Write-Host (New-RenderText @(0x672c, 0x624b, 0x724c, 0x5df2, 0x7ed3, 0x675f))
        }
    }

    if ($ShowAllCards -or $Game.Street -eq 'Showdown' -or $Game.Street -eq 'Finished') {
        Write-Host '------------------------------------------------------------'
        foreach ($line in @(Get-RevealedHandsLines -Game $Game)) {
            Write-Host $line
        }
    }
}
