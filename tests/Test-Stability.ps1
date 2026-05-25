. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Pot.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Core\Showdown.ps1"
. "$PSScriptRoot\..\src\Bot\RandomBot.ps1"
. "$PSScriptRoot\..\src\Bot\BotBase.ps1"
. "$PSScriptRoot\..\src\Local\GameLoop.ps1"

Run-TestCase "Auto simulation completes 20 hands without changing total chips" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Human-Auto' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-2' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 3 -Name 'Bot-3' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 4 -Name 'Bot-4' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 5 -Name 'Bot-5' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 6 -Name 'Bot-6' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20

    for ($hand = 1; $hand -le 20; $hand++) {
        Invoke-LocalHand -Game $game -MaxTurns 500

        $total = 0
        foreach ($player in $game.Players) {
            $total += [int]$player.Chips
        }

        Assert-Equal 6000 $total
        Assert-Equal 'Finished' $game.Street
        Assert-Equal $hand $game.HandId
    }
}

Run-TestCase "Local human with five bots can complete one scripted hand" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Human' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-2' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 3 -Name 'Bot-3' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 4 -Name 'Bot-4' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 5 -Name 'Bot-5' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 6 -Name 'Bot-6' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $provider = {
        param($CurrentGame, $Player)

        $actions = @(Get-LegalActions -Game $CurrentGame -Seat $Player.Seat)
        if (@($actions | Where-Object { $_.Command -eq 'check' }).Count -gt 0) {
            return 'check'
        }
        if (@($actions | Where-Object { $_.Command -eq 'call' }).Count -gt 0) {
            return 'call'
        }
        return 'fold'
    }

    Invoke-LocalHand -Game $game -ActionProvider $provider -MaxTurns 500

    $total = 0
    foreach ($player in $game.Players) {
        $total += [int]$player.Chips
    }

    Assert-Equal 'Finished' $game.Street
    Assert-Equal 6000 $total
}
