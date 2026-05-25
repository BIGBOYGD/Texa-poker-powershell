function Get-RandomBotAction {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player
    )

    $actions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
    if ($actions.Count -eq 0) {
        throw "Bot at seat $($Player.Seat) has no legal action."
    }

    $preferredCommands = @()
    $commandNames = @($actions | ForEach-Object { $_.Command })

    if ($commandNames -contains 'check') {
        $preferredCommands += 'check'
        if (($commandNames -contains 'bet') -and ((Get-Random -Minimum 1 -Maximum 101) -le 10)) {
            $preferredCommands = @('bet')
        }
    } elseif ($commandNames -contains 'call') {
        $preferredCommands += 'call'
    } elseif ($commandNames -contains 'fold') {
        $preferredCommands += 'fold'
    } else {
        $preferredCommands += $commandNames
    }

    $selectedCommand = $preferredCommands | Get-Random
    $action = @($actions | Where-Object { $_.Command -eq $selectedCommand } | Select-Object -First 1)[0]
    $amount = $null
    if ($null -ne $action.MinAmount) {
        $amount = $action.MinAmount
    }

    [pscustomobject]@{
        Command = $action.Command
        Amount = $amount
    }
}
