function Get-RankText {
    param([Parameter(Mandatory = $true)][int]$Rank)

    switch ($Rank) {
        14 { return 'A' }
        13 { return 'K' }
        12 { return 'Q' }
        11 { return 'J' }
        10 { return 'T' }
        default { return [string]$Rank }
    }
}

function ConvertFrom-RankText {
    param([Parameter(Mandatory = $true)][string]$RankText)

    switch ($RankText.ToUpperInvariant()) {
        'A' { return 14 }
        'K' { return 13 }
        'Q' { return 12 }
        'J' { return 11 }
        'T' { return 10 }
        default {
            $rank = 0
            if (-not [int]::TryParse($RankText, [ref]$rank)) {
                throw "Invalid rank '$RankText'."
            }
            if ($rank -lt 2 -or $rank -gt 9) {
                throw "Invalid numeric rank '$RankText'."
            }
            return $rank
        }
    }
}

function New-Card {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(2, 14)][int]$Rank,
        [Parameter(Mandatory = $true)][ValidateSet('S', 'H', 'D', 'C')][string]$Suit
    )

    $rankText = Get-RankText -Rank $Rank
    [pscustomobject]@{
        Rank = $Rank
        Suit = $Suit
        Text = "$rankText$($Suit.ToLowerInvariant())"
    }
}

function ConvertTo-Card {
    param([Parameter(Mandatory = $true)][string]$Text)

    $trimmed = $Text.Trim()
    if ($trimmed.Length -lt 2 -or $trimmed.Length -gt 3) {
        throw "Invalid card text '$Text'."
    }

    $suit = $trimmed.Substring($trimmed.Length - 1, 1).ToUpperInvariant()
    if (@('S', 'H', 'D', 'C') -notcontains $suit) {
        throw "Invalid card suit '$Text'."
    }

    $rankText = $trimmed.Substring(0, $trimmed.Length - 1)
    $rank = ConvertFrom-RankText -RankText $rankText
    New-Card -Rank $rank -Suit $suit
}
