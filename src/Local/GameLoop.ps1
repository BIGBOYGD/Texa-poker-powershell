function New-LocalText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Test-CanStartNextHand {
    param([Parameter(Mandatory = $true)]$Game)

    $playersWithChips = @($Game.Players | Where-Object { [int]$_.Chips -gt 0 })
    return $playersWithChips.Count -ge 2
}

function Test-PlayerCanContinue {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat
    )

    $player = Get-PlayerBySeat -Game $Game -Seat $Seat
    return [int]$player.Chips -gt 0
}

function Get-LocalActionForPlayer {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider
    )

    if ($Player.Type -eq 'Bot') {
        return Get-BotAction -Game $Game -Player $Player
    }

    while ($true) {
        $rawAction = $null
        if ($null -ne $ActionProvider) {
            $rawAction = & $ActionProvider $Game $Player
        } else {
            Render-Table -Game $Game -ViewerSeat $Player.Seat
            $rawAction = Read-PlayerCommand
        }

        if ($rawAction -is [string]) {
            try {
                $legalActions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
                $numberedAction = ConvertFrom-NumberedPlayerAction -InputText $rawAction -LegalActions $legalActions
                if ($null -ne $numberedAction) {
                    $rawAction = $numberedAction
                } else {
                    $rawAction = ConvertTo-PlayerAction -InputText $rawAction
                }
            } catch {
                $message = New-LocalText @(0x65e0, 0x6548, 0x547d, 0x4ee4, 0xff0c, 0x8bf7, 0x8f93, 0x5165, 0x20, 0x68, 0x65, 0x6c, 0x70, 0x20, 0x6216, 0x20)
                $help = New-LocalText @(0x5e2e, 0x52a9)
                $suffix = New-LocalText @(0x20, 0x67e5, 0x770b, 0x53ef, 0x7528, 0x547d, 0x4ee4)
                Write-Host "$message$help$suffix"
                continue
            }
        }

        switch ($rawAction.Command) {
            'status' {
                Render-Table -Game $Game -ViewerSeat $Player.Seat
                continue
            }
            'help' {
                $availableCommands = New-LocalText @(0x53ef, 0x7528, 0x547d, 0x4ee4)
                $legalActions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
                $status = New-LocalText @(0x72b6, 0x6001)
                $help = New-LocalText @(0x5e2e, 0x52a9)
                $quit = New-LocalText @(0x9000, 0x51fa)
                Write-Host "$availableCommands`: $(Format-NumberedLegalActions -Actions $legalActions), $status, $help, $quit"
                continue
            }
            'history' {
                foreach ($entry in @($Game.Log)) {
                    Write-Host $entry.Message
                }
                continue
            }
            'quit' {
                throw 'Player quit.'
            }
            default {
                if (Test-PlayerActionLegal -Game $Game -Seat $Player.Seat -Command $rawAction.Command -Amount $rawAction.Amount) {
                    return $rawAction
                }
                Write-Host (New-LocalText @(0x5f53, 0x524d, 0x72b6, 0x6001, 0x4e0b, 0x4e0d, 0x80fd, 0x6267, 0x884c, 0x8be5, 0x52a8, 0x4f5c))
                continue
            }
        }
    }
}

function Invoke-BettingRound {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider,
        [Parameter(Mandatory = $false)][int]$MaxTurns = 200
    )

    $turns = 0
    while (-not (Is-BettingRoundClosed -Game $Game)) {
        $turns++
        if ($turns -gt $MaxTurns) {
            throw "Betting round exceeded $MaxTurns turns."
        }

        if ($null -eq $Game.ActionSeat) {
            $Game.ActionSeat = Get-NextSeat -Game $Game -Seat $Game.DealerSeat -ActionableOnly
        }

        $player = Get-PlayerBySeat -Game $Game -Seat $Game.ActionSeat
        $action = Get-LocalActionForPlayer -Game $Game -Player $player -ActionProvider $ActionProvider

        Apply-PlayerAction -Game $Game -Seat $player.Seat -Command $action.Command -Amount $action.Amount
        Set-NextActionSeat -Game $Game
    }
}

function Invoke-LocalHand {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider,
        [Parameter(Mandatory = $false)][int]$MaxTurns = 500
    )

    Start-NewHand -Game $Game

    while ($Game.Street -ne 'Finished') {
        if ($Game.Street -eq 'Showdown') {
            Resolve-Hand -Game $Game
            break
        }

        Invoke-BettingRound -Game $Game -ActionProvider $ActionProvider -MaxTurns $MaxTurns

        $contenders = @(Get-ContendingPlayers -Game $Game)
        if ($contenders.Count -le 1) {
            Resolve-Hand -Game $Game
            break
        }

        Advance-Street -Game $Game
    }
}
