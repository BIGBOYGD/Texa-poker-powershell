. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"

function New-TestCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

Run-TestCase "Royal flush is recognized as straight flush" {
    $cards = @(New-TestCards @('As', 'Ks', 'Qs', 'Js', 'Ts', '2d', '3c'))
    $result = Evaluate-Hand7 -Cards $cards

    Assert-Equal 9 $result.RankLevel
    Assert-Equal 'Straight Flush' $result.RankName
    Assert-SequenceEqual @(14) $result.Kickers
}

Run-TestCase "Wheel straight is recognized as five high" {
    $cards = @(New-TestCards @('As', '2d', '3h', '4c', '5s', 'Kd', 'Qc'))
    $result = Evaluate-Hand7 -Cards $cards

    Assert-Equal 5 $result.RankLevel
    Assert-Equal 'Straight' $result.RankName
    Assert-SequenceEqual @(5) $result.Kickers
}

Run-TestCase "Two pair kicker decides winner" {
    $left = Evaluate-Hand7 -Cards @(New-TestCards @('As', 'Ah', 'Kd', 'Kc', 'Qs', '2d', '3c'))
    $right = Evaluate-Hand7 -Cards @(New-TestCards @('Ad', 'Ac', 'Kh', 'Ks', 'Js', '2c', '3d'))

    Assert-True ((Compare-HandResult -Left $left -Right $right) -gt 0)
}

Run-TestCase "Flush comparison starts at highest card" {
    $aceFlush = Evaluate-Hand7 -Cards @(New-TestCards @('As', 'Js', '9s', '7s', '2s', 'Kd', '3c'))
    $kingFlush = Evaluate-Hand7 -Cards @(New-TestCards @('Ks', 'Qs', '9s', '7s', '2s', 'Ad', '3c'))

    Assert-Equal 'Flush' $aceFlush.RankName
    Assert-True ((Compare-HandResult -Left $aceFlush -Right $kingFlush) -gt 0)
}

Run-TestCase "Full house compares trips before pair" {
    $acesFull = Evaluate-Hand7 -Cards @(New-TestCards @('As', 'Ah', 'Ad', '2c', '2d', 'Kh', 'Qc'))
    $kingsFull = Evaluate-Hand7 -Cards @(New-TestCards @('Ks', 'Kh', 'Kd', 'Ac', 'Ad', 'Qh', 'Jc'))

    Assert-Equal 'Full House' $acesFull.RankName
    Assert-True ((Compare-HandResult -Left $acesFull -Right $kingsFull) -gt 0)
}

Run-TestCase "Four of a kind beats full house" {
    $quads = Evaluate-Hand7 -Cards @(New-TestCards @('9s', '9h', '9d', '9c', '2d', 'Ah', 'Kc'))
    $fullHouse = Evaluate-Hand7 -Cards @(New-TestCards @('As', 'Ah', 'Ad', 'Kc', 'Kd', '2h', '3c'))

    Assert-True ((Compare-HandResult -Left $quads -Right $fullHouse) -gt 0)
}
