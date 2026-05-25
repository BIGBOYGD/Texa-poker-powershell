. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"

Run-TestCase "Deck has 52 unique cards" {
    $deck = @(New-Deck)
    $unique = @($deck | ForEach-Object { $_.Text } | Sort-Object -Unique)

    Assert-Equal 52 $deck.Count
    Assert-Equal 52 $unique.Count
}

Run-TestCase "Deck contains all suits and ranks" {
    $deck = @(New-Deck)
    $suits = @($deck | ForEach-Object { $_.Suit } | Sort-Object -Unique)
    $ranks = @($deck | ForEach-Object { $_.Rank } | Sort-Object -Unique)

    Assert-SequenceEqual @('C', 'D', 'H', 'S') $suits
    Assert-SequenceEqual @(2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14) $ranks
}

Run-TestCase "Shuffle preserves the same card set" {
    $deck = @(New-Deck)
    $shuffled = @(Shuffle-Deck -Deck $deck)

    $before = @($deck | ForEach-Object { $_.Text } | Sort-Object)
    $after = @($shuffled | ForEach-Object { $_.Text } | Sort-Object)

    Assert-Equal 52 $shuffled.Count
    Assert-SequenceEqual $before $after
}
