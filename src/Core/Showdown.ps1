function Get-ContendingPlayers {
    param([Parameter(Mandatory = $true)]$Game)

    return @($Game.Players | Where-Object { @('Folded', 'Out') -notcontains $_.Status })
}

function Get-TotalCommittedChips {
    param([Parameter(Mandatory = $true)]$Game)

    $total = 0
    foreach ($player in $Game.Players) {
        $total += [int]$player.TotalBetThisHand
    }
    return $total
}

function Resolve-Hand {
    param([Parameter(Mandatory = $true)]$Game)

    $contenders = @(Get-ContendingPlayers -Game $Game)
    if ($contenders.Count -eq 0) {
        $Game.Street = 'Finished'
        $Game.ActionSeat = $null
        return
    }

    if ($contenders.Count -eq 1) {
        $winner = $contenders[0]
        $amount = Get-TotalCommittedChips -Game $Game
        $winner.Chips = [int]$winner.Chips + $amount
        if (Get-Command Add-GameLog -ErrorAction SilentlyContinue) {
            Add-GameLog -Game $Game -ActorSeat $winner.Seat -Action 'award' -Message "Seat $($winner.Seat) wins uncontested pot $amount."
        }
        $Game.Pots = @([pscustomobject]@{ Amount = $amount; EligibleSeats = @([int]$winner.Seat) })
        $Game.Street = 'Finished'
        $Game.ActionSeat = $null
        return
    }

    if (@($Game.CommunityCards).Count -ne 5) {
        throw 'Showdown requires exactly 5 community cards.'
    }

    $results = @{}
    foreach ($player in $contenders) {
        $sevenCards = @($player.HoleCards) + @($Game.CommunityCards)
        $results[[int]$player.Seat] = Evaluate-Hand7 -Cards $sevenCards
    }

    $Game.Pots = @(Build-Pots -Game $Game)
    Award-Pots -Game $Game -HandResults $results

    if (Get-Command Add-GameLog -ErrorAction SilentlyContinue) {
        foreach ($seat in ($results.Keys | Sort-Object)) {
            $result = $results[$seat]
            Add-GameLog -Game $Game -ActorSeat ([int]$seat) -Action 'showdown' -Message "Seat $seat shows $($result.RankName)."
        }
    }

    $Game.Street = 'Finished'
    $Game.ActionSeat = $null
}
