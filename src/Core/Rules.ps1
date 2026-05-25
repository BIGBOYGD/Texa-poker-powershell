function Get-PlayingSeats {
    param([Parameter(Mandatory = $true)]$Game)
    return @($Game.Players | Where-Object { [int]$_.Chips -gt 0 -or [int]$_.TotalBetThisHand -gt 0 } | Sort-Object Seat | ForEach-Object { [int]$_.Seat })
}

function Get-NextSeat {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat,
        [Parameter(Mandatory = $false)][switch]$ActionableOnly
    )

    $ordered = @($Game.Players | Sort-Object Seat)
    $seats = @($ordered | ForEach-Object { [int]$_.Seat })
    $startIndex = [Array]::IndexOf($seats, $Seat)
    if ($startIndex -lt 0) {
        $startIndex = -1
    }

    for ($offset = 1; $offset -le $seats.Count; $offset++) {
        $candidateSeat = $seats[($startIndex + $offset) % $seats.Count]
        $player = Get-PlayerBySeat -Game $Game -Seat $candidateSeat
        if ($ActionableOnly) {
            if (@('Folded', 'AllIn', 'Out') -notcontains $player.Status) {
                return $candidateSeat
            }
        } elseif ($player.Status -ne 'Out' -or $player.Chips -gt 0) {
            return $candidateSeat
        }
    }

    return $null
}

function Draw-GameCard {
    param([Parameter(Mandatory = $true)]$Game)

    if (@($Game.Deck).Count -eq 0) {
        throw 'Deck is empty.'
    }

    $card = $Game.Deck[0]
    if (@($Game.Deck).Count -eq 1) {
        $Game.Deck = @()
    } else {
        $Game.Deck = @($Game.Deck[1..($Game.Deck.Count - 1)])
    }
    return $card
}

function Post-Blind {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat,
        [Parameter(Mandatory = $true)][int]$Amount
    )

    $player = Get-PlayerBySeat -Game $Game -Seat $Seat
    $paid = [Math]::Min($Amount, [int]$player.Chips)
    $player.Chips = [int]$player.Chips - $paid
    $player.StreetBet = [int]$player.StreetBet + $paid
    $player.TotalBetThisHand = [int]$player.TotalBetThisHand + $paid
    if ($player.Chips -eq 0) {
        $player.Status = 'AllIn'
    } else {
        $player.Status = 'Waiting'
    }
}

function Reset-StreetBets {
    param([Parameter(Mandatory = $true)]$Game)

    foreach ($player in $Game.Players) {
        $player.StreetBet = 0
        $player.HasActedThisRound = $false
        if (@('Folded', 'AllIn', 'Out') -notcontains $player.Status) {
            $player.Status = 'Waiting'
        }
    }

    $Game.CurrentBet = 0
    $Game.MinRaise = $Game.BigBlind
    $nextSeat = Get-NextSeat -Game $Game -Seat $Game.DealerSeat -ActionableOnly
    $Game.ActionSeat = $nextSeat
}

function Start-NewHand {
    param([Parameter(Mandatory = $true)]$Game)

    $playersWithChips = @($Game.Players | Where-Object { [int]$_.Chips -gt 0 } | Sort-Object Seat)
    if ($playersWithChips.Count -lt 2) {
        throw 'At least two players with chips are required.'
    }

    $Game.HandId = [int]$Game.HandId + 1
    $Game.Street = 'PreFlop'
    $Game.Deck = @(Shuffle-Deck -Deck @(New-Deck))
    $Game.CommunityCards = @()
    $Game.Pots = @()
    $Game.Log = @()
    $Game.CurrentBet = 0
    $Game.MinRaise = $Game.BigBlind

    foreach ($player in $Game.Players) {
        $player.HoleCards = @()
        $player.StreetBet = 0
        $player.TotalBetThisHand = 0
        $player.HasActedThisRound = $false
        $player.Status = if ($player.Chips -gt 0) { 'Waiting' } else { 'Out' }
    }

    if ($Game.DealerSeat -le 0) {
        $Game.DealerSeat = [int]$playersWithChips[0].Seat
    } else {
        $Game.DealerSeat = Get-NextSeat -Game $Game -Seat $Game.DealerSeat
    }

    $activeSeats = @(Get-PlayingSeats -Game $Game)
    for ($round = 0; $round -lt 2; $round++) {
        foreach ($seat in $activeSeats) {
            $player = Get-PlayerBySeat -Game $Game -Seat $seat
            $player.HoleCards = @($player.HoleCards) + (Draw-GameCard -Game $Game)
        }
    }

    if ($activeSeats.Count -eq 2) {
        $smallBlindSeat = $Game.DealerSeat
        $bigBlindSeat = Get-NextSeat -Game $Game -Seat $smallBlindSeat
        $firstActionSeat = $smallBlindSeat
    } else {
        $smallBlindSeat = Get-NextSeat -Game $Game -Seat $Game.DealerSeat
        $bigBlindSeat = Get-NextSeat -Game $Game -Seat $smallBlindSeat
        $firstActionSeat = Get-NextSeat -Game $Game -Seat $bigBlindSeat -ActionableOnly
    }

    Post-Blind -Game $Game -Seat $smallBlindSeat -Amount $Game.SmallBlind
    Post-Blind -Game $Game -Seat $bigBlindSeat -Amount $Game.BigBlind

    $Game.CurrentBet = [Math]::Max(
        (Get-PlayerBySeat -Game $Game -Seat $smallBlindSeat).StreetBet,
        (Get-PlayerBySeat -Game $Game -Seat $bigBlindSeat).StreetBet
    )
    $Game.MinRaise = $Game.BigBlind
    $Game.ActionSeat = $firstActionSeat
}

function Advance-Street {
    param([Parameter(Mandatory = $true)]$Game)

    $contenders = @($Game.Players | Where-Object { @('Folded', 'Out') -notcontains $_.Status })
    if ($contenders.Count -le 1) {
        $Game.Street = 'Finished'
        $Game.ActionSeat = $null
        return
    }

    switch ($Game.Street) {
        'PreFlop' {
            Reset-StreetBets -Game $Game
            $Game.CommunityCards = @($Game.CommunityCards) + (Draw-GameCard -Game $Game) + (Draw-GameCard -Game $Game) + (Draw-GameCard -Game $Game)
            $Game.Street = 'Flop'
        }
        'Flop' {
            Reset-StreetBets -Game $Game
            $Game.CommunityCards = @($Game.CommunityCards) + (Draw-GameCard -Game $Game)
            $Game.Street = 'Turn'
        }
        'Turn' {
            Reset-StreetBets -Game $Game
            $Game.CommunityCards = @($Game.CommunityCards) + (Draw-GameCard -Game $Game)
            $Game.Street = 'River'
        }
        'River' {
            Reset-StreetBets -Game $Game
            $Game.Street = 'Showdown'
            $Game.ActionSeat = $null
        }
        'Showdown' {
            $Game.Street = 'Finished'
            $Game.ActionSeat = $null
        }
        default {
            throw "Cannot advance from street '$($Game.Street)'."
        }
    }
}
