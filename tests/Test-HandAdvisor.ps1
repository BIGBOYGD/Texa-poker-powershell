. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"

$advisorPath = "$PSScriptRoot\..\src\Core\HandAdvisor.ps1"
if (Test-Path -LiteralPath $advisorPath) {
    . $advisorPath
}

function New-TestCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

function New-TestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

Run-TestCase "Current best hand summary returns Chinese made hand name" {
    Assert-True ([bool](Get-Command Get-CurrentBestHandSummary -ErrorAction SilentlyContinue)) "Get-CurrentBestHandSummary should exist."

    $holeCards = @(New-TestCards @('As', 'Ks'))
    $communityCards = @(New-TestCards @('Qs', 'Js', 'Ts', '2d', '3c'))
    $result = Get-CurrentBestHandSummary -HoleCards $holeCards -CommunityCards $communityCards

    Assert-Equal (New-TestText @(0x540c, 0x82b1, 0x987a)) $result.RankName
}

Run-TestCase "Current best hand summary handles preflop high card in Chinese" {
    Assert-True ([bool](Get-Command Get-CurrentBestHandSummary -ErrorAction SilentlyContinue)) "Get-CurrentBestHandSummary should exist."

    $holeCards = @(New-TestCards @('Kd', '7h'))
    $result = Get-CurrentBestHandSummary -HoleCards $holeCards -CommunityCards @()

    Assert-Equal (New-TestText @(0x9ad8, 0x724c)) $result.RankName
    Assert-Equal 'K' $result.Detail
}

Run-TestCase "Hand type predictions return top three Chinese probabilities" {
    Assert-True ([bool](Get-Command Get-HandTypePredictions -ErrorAction SilentlyContinue)) "Get-HandTypePredictions should exist."

    $holeCards = @(New-TestCards @('As', 'Ks'))
    $communityCards = @(New-TestCards @('Qs', 'Js', '2d'))
    $results = @(Get-HandTypePredictions -HoleCards $holeCards -CommunityCards $communityCards -Top 3)

    Assert-Equal 3 $results.Count
    foreach ($result in $results) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($result.RankName))
        Assert-True ($result.Probability -gt 0)
        Assert-True ($result.RankName -notmatch 'Straight|Flush|Pair|House|Card|Kind')
    }
}
