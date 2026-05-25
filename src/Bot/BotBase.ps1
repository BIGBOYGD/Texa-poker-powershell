function Get-BotAction {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player
    )

    if (Get-Command Get-RandomBotAction -ErrorAction SilentlyContinue) {
        return Get-RandomBotAction -Game $Game -Player $Player
    }

    $actions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
    if ($actions.Count -eq 0) {
        throw "Bot at seat $($Player.Seat) has no legal action."
    }

    $action = $actions[0]
    return [pscustomobject]@{ Command = $action.Command; Amount = $action.MinAmount }
}