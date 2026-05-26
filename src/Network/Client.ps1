function New-PokerClientState {
    param(
        [Parameter(Mandatory = $false)][string]$Name = 'Player',
        [Parameter(Mandatory = $false)][string]$HostAddress = '127.0.0.1',
        [Parameter(Mandatory = $false)][int]$Port = 7777
    )

    [pscustomobject]@{
        Name = $Name
        HostAddress = $HostAddress
        Port = $Port
        PlayerId = $null
        Seat = $null
        TcpClient = $null
        Reader = $null
        Writer = $null
        NextSeq = 1
        LastMessageType = $null
        LastSnapshot = $null
        LastActionRequest = $null
        LastError = $null
        IsFinished = $false
    }
}

function New-JoinRequestMessage {
    param(
        [Parameter(Mandatory = $false)][int]$Seq = 1,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )

    return New-ProtocolMessage -Type 'JoinRequest' -Seq $Seq -Payload ([pscustomobject]@{
        Name = $Name
    })
}

function Connect-PokerHost {
    param([Parameter(Mandatory = $true)]$Client)

    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        $tcpClient.Connect([string]$Client.HostAddress, [int]$Client.Port)
        $tcpClient.ReceiveTimeout = 3000
        $stream = $tcpClient.GetStream()
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $reader = New-Object System.IO.StreamReader($stream, $encoding)
        $writer = New-Object System.IO.StreamWriter($stream, $encoding)
        $writer.AutoFlush = $true

        $Client.TcpClient = $tcpClient
        $Client.Reader = $reader
        $Client.Writer = $writer
        return $Client
    } catch {
        throw "Connect to Host failed: $($_.Exception.Message)"
    }
}

function Send-JoinRequest {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $false)][int]$Seq = 1
    )

    if ($null -eq $Client.Writer) {
        throw 'Client is not connected.'
    }

    $message = New-JoinRequestMessage -Seq $Seq -Name $Client.Name
    $Client.NextSeq = [Math]::Max([int]$Client.NextSeq, $Seq + 1)
    $Client.Writer.WriteLine((ConvertTo-MessageJson -Message $message))
    return $message
}

function Read-ServerMessage {
    param([Parameter(Mandatory = $true)]$Client)

    if ($null -eq $Client.Reader) {
        throw 'Client is not connected.'
    }

    $line = $Client.Reader.ReadLine()
    if ($null -eq $line) {
        return $null
    }

    return ConvertFrom-MessageJson -Json $line
}

function Show-StateSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $payload = $Snapshot.Payload
    Write-Host "View $($Snapshot.PlayerId) | Hand $($payload.HandId) | $($payload.Street) | Pot $($payload.Pot) | Bet $($payload.CurrentBet)"
    foreach ($player in @($payload.Players | Sort-Object Seat)) {
        $marker = if ($player.IsYou) { 'YOU' } else { '' }
        Write-Host ("{0} {1} {2} Chips:{3} Bet:{4} Status:{5}" -f $player.Seat, $player.Name, $marker, $player.Chips, $player.Bet, $player.Status)
    }
}

function Get-ClientLegalActionsFromRequest {
    param([Parameter(Mandatory = $true)]$ActionRequest)

    $actions = @()
    foreach ($action in @($ActionRequest.Payload.LegalActions)) {
        $actions += [pscustomobject]@{
            Command = [string]$action.Command
            MinAmount = $action.MinAmount
            MaxAmount = $action.MaxAmount
        }
    }

    return $actions
}

function Test-ClientActionLegal {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LegalActions,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $false)]$Amount = $null
    )

    $commandName = $Command.ToLowerInvariant()
    $matches = @($LegalActions | Where-Object { $_.Command -eq $commandName })
    if ($matches.Count -eq 0) {
        return $false
    }

    $action = $matches[0]
    if ($null -ne $action.MinAmount) {
        if ($null -eq $Amount) {
            return $false
        }

        $amountValue = [int]$Amount
        if ($amountValue -lt [int]$action.MinAmount -or $amountValue -gt [int]$action.MaxAmount) {
            return $false
        }
    }

    return $true
}

function ConvertTo-ClientPlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$ActionRequest,
        [Parameter(Mandatory = $true)][string]$InputText,
        [Parameter(Mandatory = $false)][Nullable[int]]$Seq = $null
    )

    if ([string]::IsNullOrWhiteSpace([string]$Client.PlayerId)) {
        throw 'Client has no PlayerId.'
    }

    $legalActions = @(Get-ClientLegalActionsFromRequest -ActionRequest $ActionRequest)
    $rawAction = ConvertFrom-NumberedPlayerAction -InputText $InputText -LegalActions $legalActions
    if ($null -eq $rawAction) {
        $rawAction = ConvertTo-PlayerAction -InputText $InputText
    }

    switch ([string]$rawAction.Command) {
        'quit' {
            throw 'Player quit.'
        }
        'status' {
            throw 'Status command is local to the client.'
        }
        'help' {
            throw 'Help command is local to the client.'
        }
        'history' {
            throw 'History command is local to the client.'
        }
    }

    if (-not (Test-ClientActionLegal -LegalActions $legalActions -Command $rawAction.Command -Amount $rawAction.Amount)) {
        throw 'Action is not legal in current state.'
    }

    $payload = [pscustomobject]@{
        Command = ([string]$rawAction.Command).ToLowerInvariant()
    }
    if ($null -ne $rawAction.Amount) {
        $payload | Add-Member -NotePropertyName Amount -NotePropertyValue ([int]$rawAction.Amount)
    }

    $messageSeq = if ($null -ne $Seq) { [int]$Seq } else { [int]$Client.NextSeq }
    $Client.NextSeq = [Math]::Max([int]$Client.NextSeq, $messageSeq + 1)

    return New-ProtocolMessage -Type 'PlayerAction' -Seq $messageSeq -PlayerId ([string]$Client.PlayerId) -HandId ([int]$ActionRequest.HandId) -Payload $payload
}

function Send-PlayerAction {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$Message
    )

    if ($null -eq $Client.Writer) {
        throw 'Client is not connected.'
    }

    $Client.Writer.WriteLine((ConvertTo-MessageJson -Message $Message))
}

function Read-ClientActionInput {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$ActionRequest,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider
    )

    while ($true) {
        $inputText = if ($null -ne $ActionProvider) {
            & $ActionProvider $Client $ActionRequest
        } else {
            $legalActions = @(Get-ClientLegalActionsFromRequest -ActionRequest $ActionRequest)
            if (Get-Command Format-NumberedLegalActions -ErrorAction SilentlyContinue) {
                Write-Host "Actions: $(Format-NumberedLegalActions -Actions $legalActions)"
            }
            Read-Host '>'
        }

        try {
            return ConvertTo-ClientPlayerAction -Client $Client -ActionRequest $ActionRequest -InputText $inputText
        } catch {
            if ($_.Exception.Message -eq 'Player quit.') {
                throw
            }
            Write-Host "Invalid action: $($_.Exception.Message)"
        }
    }
}

function Handle-ServerMessage {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$Message,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider,
        [Parameter(Mandatory = $false)][switch]$Quiet
    )

    if ($null -eq $Message) {
        return
    }

    $Client.LastMessageType = [string]$Message.Type
    switch ([string]$Message.Type) {
        'JoinAccepted' {
            $Client.PlayerId = [string]$Message.Payload.PlayerId
            $Client.Seat = [int]$Message.Payload.Seat
            if (-not [string]::IsNullOrWhiteSpace([string]$Message.Payload.Name)) {
                $Client.Name = [string]$Message.Payload.Name
            }
            if (-not $Quiet) {
                Write-Host "Join accepted: $($Client.PlayerId), seat $($Client.Seat)."
            }
        }
        'StateSnapshot' {
            $Client.LastSnapshot = $Message.Payload
            if (-not $Quiet) {
                Show-StateSnapshot -Snapshot $Message
            }
        }
        'ActionRequest' {
            $Client.LastActionRequest = $Message
            if (-not $Quiet) {
                $action = Read-ClientActionInput -Client $Client -ActionRequest $Message -ActionProvider $ActionProvider
                Send-PlayerAction -Client $Client -Message $action
            }
        }
        'ErrorMessage' {
            $Client.LastError = [string]$Message.Payload.Message
            if (-not $Quiet) {
                Write-Host "Error: $($Client.LastError)"
            }
        }
        'HandResult' {
            $Client.LastSnapshot = $Message.Payload
            $Client.IsFinished = $true
            if (-not $Quiet) {
                Show-StateSnapshot -Snapshot $Message
            }
        }
        default {
            if (-not $Quiet) {
                Write-Host "Received message: $($Message.Type)"
            }
        }
    }
}

function Start-PokerClient {
    param(
        [Parameter(Mandatory = $false)][string]$HostAddress = '127.0.0.1',
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][string]$Name = 'Player',
        [Parameter(Mandatory = $false)][int]$MaxMessages = [int]::MaxValue,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider
    )

    $client = New-PokerClientState -Name $Name -HostAddress $HostAddress -Port $Port
    Connect-PokerHost -Client $client | Out-Null
    Send-JoinRequest -Client $client | Out-Null

    for ($i = 0; $i -lt $MaxMessages; $i++) {
        try {
            $message = Read-ServerMessage -Client $client
            if ($null -eq $message) {
                break
            }
            Handle-ServerMessage -Client $client -Message $message -ActionProvider $ActionProvider
            if ($client.IsFinished) {
                break
            }
        } catch {
            Write-Host "Read Host message failed: $($_.Exception.Message)"
            break
        }
    }

    return $client
}
