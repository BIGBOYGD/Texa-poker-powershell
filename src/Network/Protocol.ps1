$script:ProtocolMessageTypes = @(
    'JoinRequest',
    'JoinAccepted',
    'StateSnapshot',
    'ActionRequest',
    'PlayerAction',
    'ErrorMessage',
    'HandResult'
)

function Test-ProtocolPropertyExists {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return $null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name
}

function New-ProtocolValidationResult {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Errors)

    [pscustomobject]@{
        IsValid = ($Errors.Count -eq 0)
        Errors = @($Errors)
    }
}

function New-ProtocolMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][int]$Seq,
        [Parameter(Mandatory = $false)][string]$PlayerId = $null,
        [Parameter(Mandatory = $false)][Nullable[int]]$HandId = $null,
        [Parameter(Mandatory = $false)]$Payload = $null
    )

    if ($null -eq $Payload) {
        $Payload = [pscustomobject]@{}
    }

    [pscustomobject]@{
        Type = $Type
        Seq = $Seq
        PlayerId = $PlayerId
        HandId = $HandId
        Payload = $Payload
    }
}

function ConvertTo-MessageJson {
    param([Parameter(Mandatory = $true)]$Message)

    return ($Message | ConvertTo-Json -Compress -Depth 20)
}

function ConvertFrom-MessageJson {
    param([Parameter(Mandatory = $true)][string]$Json)

    try {
        return ($Json | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return [pscustomobject]@{
            IsValid = $false
            Error = $_.Exception.Message
        }
    }
}

function Test-ProtocolMessage {
    param([Parameter(Mandatory = $true)]$Message)

    $errors = @()

    if (Test-ProtocolPropertyExists -Object $Message -Name 'IsValid') {
        if ($Message.IsValid -eq $false) {
            $errors += 'Message parse failed.'
            return New-ProtocolValidationResult -Errors $errors
        }
    }

    if (-not (Test-ProtocolPropertyExists -Object $Message -Name 'Type') -or [string]::IsNullOrWhiteSpace([string]$Message.Type)) {
        $errors += 'Type is required.'
    } elseif ($script:ProtocolMessageTypes -notcontains [string]$Message.Type) {
        $errors += "Unknown Type '$($Message.Type)'."
    }

    if (-not (Test-ProtocolPropertyExists -Object $Message -Name 'Seq') -or $null -eq $Message.Seq) {
        $errors += 'Seq is required.'
    }

    if (-not (Test-ProtocolPropertyExists -Object $Message -Name 'Payload') -or $null -eq $Message.Payload) {
        $errors += 'Payload is required.'
    }

    if ($errors.Count -eq 0 -and [string]$Message.Type -eq 'PlayerAction') {
        if (-not (Test-ProtocolPropertyExists -Object $Message.Payload -Name 'Command') -or [string]::IsNullOrWhiteSpace([string]$Message.Payload.Command)) {
            $errors += 'PlayerAction.Payload.Command is required.'
        } else {
            $command = ([string]$Message.Payload.Command).ToLowerInvariant()
            if (@('bet', 'raise') -contains $command) {
                if (-not (Test-ProtocolPropertyExists -Object $Message.Payload -Name 'Amount') -or $null -eq $Message.Payload.Amount) {
                    $errors += "PlayerAction '$command' requires Payload.Amount."
                }
            }
        }
    }

    return New-ProtocolValidationResult -Errors $errors
}

function ConvertTo-NetworkCardText {
    param([Parameter(Mandatory = $true)]$Card)

    if ($Card.PSObject.Properties.Name -contains 'Text' -and -not [string]::IsNullOrWhiteSpace([string]$Card.Text)) {
        return [string]$Card.Text
    }

    if ((Get-Command Get-RankText -ErrorAction SilentlyContinue) -and $Card.PSObject.Properties.Name -contains 'Rank' -and $Card.PSObject.Properties.Name -contains 'Suit') {
        return "$(Get-RankText -Rank ([int]$Card.Rank))$(([string]$Card.Suit).ToLowerInvariant())"
    }

    return [string]$Card
}

function ConvertTo-NetworkCardTextList {
    param([Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Cards = @())

    return @($Cards | ForEach-Object { ConvertTo-NetworkCardText -Card $_ })
}

function Get-ProtocolPlayerId {
    param([Parameter(Mandatory = $true)]$Player)

    if ($Player.PSObject.Properties.Name -contains 'PlayerId' -and -not [string]::IsNullOrWhiteSpace([string]$Player.PlayerId)) {
        return [string]$Player.PlayerId
    }

    return "P$($Player.Seat)"
}

function Get-ProtocolPlayerByIdOrSeat {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $false)][string]$PlayerId = $null,
        [Parameter(Mandatory = $false)][Nullable[int]]$Seat = $null
    )

    if (-not [string]::IsNullOrWhiteSpace($PlayerId)) {
        $player = @($Game.Players | Where-Object { (Get-ProtocolPlayerId -Player $_) -eq $PlayerId } | Select-Object -First 1)
        if ($player.Count -gt 0) {
            return $player[0]
        }
    }

    if ($null -ne $Seat) {
        return Get-PlayerBySeat -Game $Game -Seat $Seat
    }

    throw 'Target player was not found.'
}

function Get-ProtocolPotTotal {
    param([Parameter(Mandatory = $true)]$Game)

    $total = 0
    foreach ($player in @($Game.Players)) {
        $total += [int]$player.TotalBetThisHand
    }

    if ($total -eq 0 -and (Test-ProtocolPropertyExists -Object $Game -Name 'Pots')) {
        foreach ($pot in @($Game.Pots)) {
            if (Test-ProtocolPropertyExists -Object $pot -Name 'Amount') {
                $total += [int]$pot.Amount
            }
        }
    }

    return $total
}

function ConvertTo-NetworkLegalActions {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$Seat
    )

    if (-not (Get-Command Get-LegalActions -ErrorAction SilentlyContinue)) {
        return @()
    }

    $actions = @()
    foreach ($action in @(Get-LegalActions -Game $Game -Seat $Seat)) {
        $actions += [pscustomobject]@{
            Command = [string]$action.Command
            MinAmount = $action.MinAmount
            MaxAmount = $action.MaxAmount
        }
    }

    return $actions
}

function New-StateSnapshotForPlayer {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $false)][string]$PlayerId = $null,
        [Parameter(Mandatory = $false)][Nullable[int]]$Seat = $null,
        [Parameter(Mandatory = $false)][int]$Seq = 0
    )

    $target = Get-ProtocolPlayerByIdOrSeat -Game $Game -PlayerId $PlayerId -Seat $Seat
    $targetPlayerId = Get-ProtocolPlayerId -Player $target
    $showAllHoleCards = @('Showdown', 'Finished') -contains [string]$Game.Street

    $players = @()
    foreach ($player in @($Game.Players | Sort-Object Seat)) {
        $isTarget = ([int]$player.Seat -eq [int]$target.Seat)
        $holeCards = $null
        if ($isTarget -or $showAllHoleCards) {
            $holeCards = @(ConvertTo-NetworkCardTextList -Cards @($player.HoleCards))
        }

        $players += [pscustomobject]@{
            Seat = [int]$player.Seat
            PlayerId = Get-ProtocolPlayerId -Player $player
            Name = [string]$player.Name
            Type = [string]$player.Type
            Chips = [int]$player.Chips
            Bet = [int]$player.StreetBet
            TotalBetThisHand = [int]$player.TotalBetThisHand
            Status = [string]$player.Status
            IsYou = $isTarget
            HoleCards = $holeCards
        }
    }

    $payload = [pscustomobject]@{
        HandId = [int]$Game.HandId
        Street = [string]$Game.Street
        Pot = Get-ProtocolPotTotal -Game $Game
        CurrentBet = [int]$Game.CurrentBet
        ActionSeat = $Game.ActionSeat
        DealerSeat = [int]$Game.DealerSeat
        SmallBlind = [int]$Game.SmallBlind
        BigBlind = [int]$Game.BigBlind
        CommunityCards = @(ConvertTo-NetworkCardTextList -Cards @($Game.CommunityCards))
        YourHoleCards = @(ConvertTo-NetworkCardTextList -Cards @($target.HoleCards))
        Players = @($players)
        LegalActions = @(ConvertTo-NetworkLegalActions -Game $Game -Seat ([int]$target.Seat))
    }

    return New-ProtocolMessage -Type 'StateSnapshot' -Seq $Seq -PlayerId $targetPlayerId -HandId ([int]$Game.HandId) -Payload $payload
}
