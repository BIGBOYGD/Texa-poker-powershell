. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Core\Rules.ps1"
. "$PSScriptRoot\..\src\Bot\RandomBot.ps1"
. "$PSScriptRoot\..\src\Bot\BotBase.ps1"

Run-TestCase "RandomBot chooses only legal actions for 1000 decisions" {
    for ($i = 0; $i -lt 1000; $i++) {
        $players = @(
            (New-PlayerState -Seat 1 -Name 'Bot-A' -Type 'Bot' -Chips 1000),
            (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000),
            (New-PlayerState -Seat 3 -Name 'Bot-C' -Type 'Bot' -Chips 1000)
        )
        $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
        Start-NewHand -Game $game
        $player = Get-PlayerBySeat -Game $game -Seat $game.ActionSeat

        $action = Get-RandomBotAction -Game $game -Player $player

        Assert-True (Test-PlayerActionLegal -Game $game -Seat $player.Seat -Command $action.Command -Amount $action.Amount)
    }
}

Run-TestCase "BotBase delegates bot decisions to RandomBot" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'Bot-A' -Type 'Bot' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'Bot-B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    Start-NewHand -Game $game
    $player = Get-PlayerBySeat -Game $game -Seat $game.ActionSeat

    $action = Get-BotAction -Game $game -Player $player

    Assert-True (Test-PlayerActionLegal -Game $game -Seat $player.Seat -Command $action.Command -Amount $action.Amount)
    Assert-True (@('fold', 'check', 'call', 'bet', 'raise', 'allin') -contains $action.Command)
}
