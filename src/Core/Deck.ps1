function New-Deck {
    $suits = @('S', 'H', 'D', 'C')
    foreach ($suit in $suits) {
        for ($rank = 2; $rank -le 14; $rank++) {
            New-Card -Rank $rank -Suit $suit
        }
    }
}

function Shuffle-Deck {
    param([Parameter(Mandatory = $true)][object[]]$Deck)

    $cards = @($Deck)
    for ($i = $cards.Count - 1; $i -gt 0; $i--) {
        $j = Get-Random -Minimum 0 -Maximum ($i + 1)
        $tmp = $cards[$i]
        $cards[$i] = $cards[$j]
        $cards[$j] = $tmp
    }
    return $cards
}
