function Get-ActiveHandPlayers {
    param([Parameter(Mandatory = $true)]$Game)
    return @($Game.Players | Where-Object { @('Folded', 'Out') -notcontains $_.Status })
}

function Get-ActionablePlayers {
    param([Parameter(Mandatory = $true)]$Game)
    return @($Game.Players | Where-Object { @('Folded', 'AllIn', 'Out') -notcontains $_.Status })
}

function New-LegalAction {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)][Nullable[int]]$MinAmount,
        [Parameter(Mandatory = $false)][Nullable[int]]$MaxAmount
    )

    [pscustomobject]@{
        Command = $Command
        MinAmount = $MinAmount
        MaxAmount = $MaxAmount
    }
}

function Get-LegalActions {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat
    )

    $player = Get-PlayerBySeat -Game $Game -Seat $Seat
    if (@('Folded', 'AllIn', 'Out') -contains $player.Status) {
        return @()
    }

    $actions = @()
    $toCall = [Math]::Max(0, [int]$Game.CurrentBet - [int]$player.StreetBet)
    $maxTotal = [int]$player.StreetBet + [int]$player.Chips

    $actions += New-LegalAction -Command 'fold'

    if ($toCall -eq 0) {
        $actions += New-LegalAction -Command 'check'
        if ($Game.CurrentBet -eq 0 -and $player.Chips -ge $Game.BigBlind) {
            $actions += New-LegalAction -Command 'bet' -MinAmount $Game.BigBlind -MaxAmount $maxTotal
        } elseif ($Game.CurrentBet -gt 0 -and $maxTotal -ge ($Game.CurrentBet + $Game.MinRaise)) {
            $actions += New-LegalAction -Command 'raise' -MinAmount ($Game.CurrentBet + $Game.MinRaise) -MaxAmount $maxTotal
        }
    } else {
        $actions += New-LegalAction -Command 'call'
        if ($maxTotal -ge ($Game.CurrentBet + $Game.MinRaise)) {
            $actions += New-LegalAction -Command 'raise' -MinAmount ($Game.CurrentBet + $Game.MinRaise) -MaxAmount $maxTotal
        }
    }

    if ($player.Chips -gt 0) {
        $actions += New-LegalAction -Command 'allin'
    }

    return $actions
}

function Test-PlayerActionLegal {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)][Nullable[int]]$Amount
    )

    $commandName = $Command.ToLowerInvariant()
    $legal = @(Get-LegalActions -Game $Game -Seat $Seat | Where-Object { $_.Command -eq $commandName })
    if ($legal.Count -eq 0) {
        return $false
    }

    $action = $legal[0]
    if ($null -ne $action.MinAmount) {
        if ($null -eq $Amount) { return $false }
        if ($Amount -lt $action.MinAmount -or $Amount -gt $action.MaxAmount) { return $false }
    }

    return $true
}

function Add-PlayerChipsToPot {
    param(
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $true)][int]$Amount
    )

    $paid = [Math]::Min($Amount, [int]$Player.Chips)
    $Player.Chips = [int]$Player.Chips - $paid
    $Player.StreetBet = [int]$Player.StreetBet + $paid
    $Player.TotalBetThisHand = [int]$Player.TotalBetThisHand + $paid

    if ($Player.Chips -eq 0 -and $Player.Status -ne 'Folded') {
        $Player.Status = 'AllIn'
    } elseif ($Player.Status -ne 'Folded') {
        $Player.Status = 'Waiting'
    }

    return $paid
}

function Reset-OtherActionFlags {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$ActorSeat
    )

    foreach ($player in $Game.Players) {
        if ($player.Seat -ne $ActorSeat -and @('Folded', 'AllIn', 'Out') -notcontains $player.Status) {
            $player.HasActedThisRound = $false
        }
    }
}

function Apply-PlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)][Nullable[int]]$Amount
    )

    $commandName = $Command.ToLowerInvariant()
    if (-not (Test-PlayerActionLegal -Game $Game -Seat $Seat -Command $commandName -Amount $Amount)) {
        throw "Illegal action '$Command' for seat $Seat."
    }

    $player = Get-PlayerBySeat -Game $Game -Seat $Seat
    $message = ''

    switch ($commandName) {
        'fold' {
            $player.Status = 'Folded'
            $message = "Seat $Seat folds."
        }
        'check' {
            $message = "Seat $Seat checks."
        }
        'call' {
            $toCall = [Math]::Max(0, [int]$Game.CurrentBet - [int]$player.StreetBet)
            $paid = Add-PlayerChipsToPot -Player $player -Amount $toCall
            $message = "Seat $Seat calls $paid."
        }
        'bet' {
            $targetTotal = [int]$Amount
            $paid = Add-PlayerChipsToPot -Player $player -Amount ($targetTotal - [int]$player.StreetBet)
            $Game.CurrentBet = $player.StreetBet
            $Game.MinRaise = [Math]::Max($Game.BigBlind, $player.StreetBet)
            Reset-OtherActionFlags -Game $Game -ActorSeat $Seat
            $message = "Seat $Seat bets $paid."
        }
        'raise' {
            $previousBet = [int]$Game.CurrentBet
            $targetTotal = [int]$Amount
            $paid = Add-PlayerChipsToPot -Player $player -Amount ($targetTotal - [int]$player.StreetBet)
            $Game.CurrentBet = $player.StreetBet
            $Game.MinRaise = [int]$Game.CurrentBet - $previousBet
            Reset-OtherActionFlags -Game $Game -ActorSeat $Seat
            $message = "Seat $Seat raises to $($Game.CurrentBet)."
        }
        'allin' {
            $previousBet = [int]$Game.CurrentBet
            $targetTotal = [int]$player.StreetBet + [int]$player.Chips
            $paid = Add-PlayerChipsToPot -Player $player -Amount $player.Chips
            if ($targetTotal -gt $previousBet) {
                $raiseDelta = $targetTotal - $previousBet
                $Game.CurrentBet = $targetTotal
                if ($raiseDelta -ge $Game.MinRaise) {
                    $Game.MinRaise = $raiseDelta
                    Reset-OtherActionFlags -Game $Game -ActorSeat $Seat
                }
            }
            $message = "Seat $Seat is all-in for $paid."
        }
    }

    $player.HasActedThisRound = $true
    if (Get-Command Add-GameLog -ErrorAction SilentlyContinue) {
        Add-GameLog -Game $Game -ActorSeat $Seat -Action $commandName -Message $message
    }
}

function Is-BettingRoundClosed {
    param([Parameter(Mandatory = $true)]$Game)

    $active = @(Get-ActiveHandPlayers -Game $Game)
    if ($active.Count -le 1) {
        return $true
    }

    $actionable = @(Get-ActionablePlayers -Game $Game)
    foreach ($player in $actionable) {
        if (-not $player.HasActedThisRound) {
            return $false
        }
        if ([int]$player.StreetBet -ne [int]$Game.CurrentBet) {
            return $false
        }
    }

    return $true
}

function Set-NextActionSeat {
    param([Parameter(Mandatory = $true)]$Game)

    if (Is-BettingRoundClosed -Game $Game) {
        $Game.ActionSeat = $null
        return
    }

    $seats = @($Game.Players | Sort-Object Seat | ForEach-Object { $_.Seat })
    $currentIndex = [Array]::IndexOf($seats, [int]$Game.ActionSeat)
    if ($currentIndex -lt 0) {
        $currentIndex = 0
    }

    for ($offset = 1; $offset -le $seats.Count; $offset++) {
        $seat = $seats[($currentIndex + $offset) % $seats.Count]
        $player = Get-PlayerBySeat -Game $Game -Seat $seat
        if (@('Folded', 'AllIn', 'Out') -notcontains $player.Status) {
            $Game.ActionSeat = $seat
            return
        }
    }

    $Game.ActionSeat = $null
}
