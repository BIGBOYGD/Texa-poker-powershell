function New-PlayerState {
    param(
        [Parameter(Mandatory = $true)][int]$Seat,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('HumanLocal', 'Bot', 'RemoteHuman')][string]$Type,
        [Parameter(Mandatory = $false)][int]$Chips = 1000
    )

    [pscustomobject]@{
        Seat = $Seat
        Name = $Name
        Type = $Type
        Chips = $Chips
        HoleCards = @()
        StreetBet = 0
        TotalBetThisHand = 0
        Status = if ($Chips -gt 0) { 'Waiting' } else { 'Out' }
        HasActedThisRound = $false
        ConnectionId = $null
    }
}

function New-GameState {
    param(
        [Parameter(Mandatory = $true)][object[]]$Players,
        [Parameter(Mandatory = $false)][int]$SmallBlind = 10,
        [Parameter(Mandatory = $false)][int]$BigBlind = 20,
        [Parameter(Mandatory = $false)][ValidateSet('Local', 'Host', 'Client')][string]$Mode = 'Local'
    )

    [pscustomobject]@{
        HandId = 0
        Street = 'Finished'
        Players = @($Players)
        Deck = @()
        CommunityCards = @()
        DealerSeat = 0
        SmallBlind = $SmallBlind
        BigBlind = $BigBlind
        CurrentBet = 0
        MinRaise = $BigBlind
        Pots = @()
        ActionSeat = $null
        Log = @()
        Mode = $Mode
    }
}

function Get-PlayerBySeat {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat
    )

    $player = @($Game.Players | Where-Object { $_.Seat -eq $Seat } | Select-Object -First 1)
    if ($player.Count -eq 0) {
        throw "Seat $Seat does not exist."
    }
    return $player[0]
}

function Add-GameLog {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $false)][Nullable[int]]$ActorSeat,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('s')
        HandId = $Game.HandId
        Street = $Game.Street
        ActorSeat = $ActorSeat
        Action = $Action
        Message = $Message
    }
    $Game.Log = @($Game.Log) + $entry
}
