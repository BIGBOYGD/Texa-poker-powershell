. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Bot\BotEvaluator.ps1"

function New-BotEvaluatorTestCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

Run-TestCase "Preflop scoring orders premium and weak hands" {
    $aa = Get-PreflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('As', 'Ah'))
    $aks = Get-PreflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('As', 'Ks'))
    $ako = Get-PreflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('As', 'Kd'))
    $eights = Get-PreflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('8s', '8h'))
    $suitedConnector = Get-PreflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('7s', '6s'))
    $trash = Get-PreflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('7s', '2d'))

    Assert-True ($aa -ge 90) "AA should score as a premium hand."
    Assert-True ($trash -le 35) "72o should score as a weak hand."
    Assert-True ($aa -gt $aks) "AA should score higher than AKs."
    Assert-True ($aks -gt $ako) "AKs should score higher than AKo."
    Assert-True ($ako -gt $eights) "AKo should score higher than 88."
    Assert-True ($eights -gt $suitedConnector) "88 should score higher than 76s."
    Assert-True ($suitedConnector -gt $trash) "76s should score higher than 72o."
}

Run-TestCase "Postflop scoring orders made hands" {
    $flush = Get-PostflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('As', '2s')) -CommunityCards @(New-BotEvaluatorTestCards @('Ks', '9s', '4s', '7d', '3c'))
    $straight = Get-PostflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('8s', '7d')) -CommunityCards @(New-BotEvaluatorTestCards @('6c', '5h', '4d', 'Qs', '2c'))
    $trips = Get-PostflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('9s', '9d')) -CommunityCards @(New-BotEvaluatorTestCards @('9c', 'Kh', '4d', '2s', '3c'))
    $twoPair = Get-PostflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('As', 'Kd')) -CommunityCards @(New-BotEvaluatorTestCards @('Ah', 'Kc', '4d', '2s', '3c'))
    $pair = Get-PostflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('As', 'Qd')) -CommunityCards @(New-BotEvaluatorTestCards @('Ah', 'Kc', '4d', '2s', '3c'))
    $highCard = Get-PostflopHandScore -HoleCards @(New-BotEvaluatorTestCards @('Qs', 'Jd')) -CommunityCards @(New-BotEvaluatorTestCards @('Ah', 'Kc', '4d', '2s', '7c'))

    Assert-True ($flush -gt $straight)
    Assert-True ($straight -gt $trips)
    Assert-True ($trips -gt $twoPair)
    Assert-True ($twoPair -gt $pair)
    Assert-True ($pair -gt $highCard)
}

Run-TestCase "Draw potential scores flush and open ended straight draws" {
    $flushDraw = Get-DrawPotentialScore -HoleCards @(New-BotEvaluatorTestCards @('As', '2s')) -CommunityCards @(New-BotEvaluatorTestCards @('Ks', '9s', '4d'))
    $openEnded = Get-DrawPotentialScore -HoleCards @(New-BotEvaluatorTestCards @('8s', '7d')) -CommunityCards @(New-BotEvaluatorTestCards @('6c', '5h', '2d'))
    $noDraw = Get-DrawPotentialScore -HoleCards @(New-BotEvaluatorTestCards @('As', '7d')) -CommunityCards @(New-BotEvaluatorTestCards @('Kc', '9h', '4d'))

    Assert-True ($flushDraw -ge 12) "Four-card flush draw should be valuable."
    Assert-True ($openEnded -ge 10) "Open-ended straight draw should be valuable."
    Assert-True ($noDraw -le 4) "No draw should have little or no draw score."
}

Run-TestCase "River draw potential is zero" {
    $score = Get-DrawPotentialScore -HoleCards @(New-BotEvaluatorTestCards @('As', '2s')) -CommunityCards @(New-BotEvaluatorTestCards @('Ks', '9s', '4d', '7s', '3c'))

    Assert-Equal 0 $score
}

Run-TestCase "Pot odds handles calls and zero call cases" {
    Assert-Equal 0.25 (Get-PotOdds -ToCall 100 -PotSize 300)
    Assert-Equal 0.0 (Get-PotOdds -ToCall 0 -PotSize 300)
    Assert-Equal 0.0 (Get-PotOdds -ToCall 0 -PotSize 0)
}

Run-TestCase "Position score rewards later position" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 3 -Name 'C' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 4 -Name 'D' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.DealerSeat = 4
    $game.Street = 'PreFlop'

    $early = Get-PositionScore -Game $game -Player $players[0]
    $button = Get-PositionScore -Game $game -Player $players[3]

    Assert-True ($button -gt $early)
}
