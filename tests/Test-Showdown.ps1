. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"
. "$PSScriptRoot\..\src\Core\Showdown.ps1"

function New-ShowdownCards {
    param([Parameter(Mandatory = $true)][string[]]$Texts)

    foreach ($text in $Texts) {
        ConvertTo-Card -Text $text
    }
}

Run-TestCase "Resolve hand awards uncontested pot to remaining player" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 900),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'Bot' -Chips 900)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'PreFlop'
    $game.Players[0].TotalBetThisHand = 100
    $game.Players[0].Status = 'Waiting'
    $game.Players[1].TotalBetThisHand = 100
    $game.Players[1].Status = 'Folded'

    Resolve-Hand -Game $game

    Assert-Equal 'Finished' $game.Street
    Assert-Equal 1100 $game.Players[0].Chips
    Assert-Equal 900 $game.Players[1].Chips
}

Run-TestCase "Resolve hand evaluates showdown and pays the best hand" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 900),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'Bot' -Chips 900)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Showdown'
    $game.CommunityCards = @(New-ShowdownCards @('As', 'Ks', 'Qs', '2d', '3c'))
    $game.Players[0].HoleCards = @(New-ShowdownCards @('Js', 'Ts'))
    $game.Players[1].HoleCards = @(New-ShowdownCards @('Ah', 'Ad'))
    $game.Players[0].TotalBetThisHand = 100
    $game.Players[1].TotalBetThisHand = 100

    Resolve-Hand -Game $game

    Assert-Equal 'Finished' $game.Street
    Assert-Equal 1100 $game.Players[0].Chips
    Assert-Equal 900 $game.Players[1].Chips
}
