function Get-BotAction {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player
    )

    $botType = 'LooseBot'
    if ($Player.PSObject.Properties.Name -contains 'BotType' -and -not [string]::IsNullOrWhiteSpace($Player.BotType)) {
        $botType = [string]$Player.BotType
    }

    switch ($botType) {
        'RuleBot' {
            if (Get-Command Get-RuleBotAction -ErrorAction SilentlyContinue) {
                return Get-RuleBotAction -Game $Game -Player $Player
            }
            if (Get-Command Get-RandomBotAction -ErrorAction SilentlyContinue) {
                return Get-RandomBotAction -Game $Game -Player $Player
            }
        }
        'TightBot' {
            if (Get-Command Get-TightBotAction -ErrorAction SilentlyContinue) {
                return Get-TightBotAction -Game $Game -Player $Player
            }
        }
        'LooseBot' {
            if (Get-Command Get-LooseBotAction -ErrorAction SilentlyContinue) {
                return Get-LooseBotAction -Game $Game -Player $Player
            }
        }
        'RandomBot' {
            if (Get-Command Get-RandomBotAction -ErrorAction SilentlyContinue) {
                return Get-RandomBotAction -Game $Game -Player $Player
            }
        }
        default {
            if (Get-Command Get-LooseBotAction -ErrorAction SilentlyContinue) {
                return Get-LooseBotAction -Game $Game -Player $Player
            }
            if (Get-Command Get-RuleBotAction -ErrorAction SilentlyContinue) {
                return Get-RuleBotAction -Game $Game -Player $Player
            }
            if (Get-Command Get-RandomBotAction -ErrorAction SilentlyContinue) {
                return Get-RandomBotAction -Game $Game -Player $Player
            }
        }
    }

    $actions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
    if ($actions.Count -eq 0) {
        throw "Bot at seat $($Player.Seat) has no legal action."
    }

    $action = $actions[0]
    return [pscustomobject]@{ Command = $action.Command; Amount = $action.MinAmount }
}
