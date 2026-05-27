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

function Close-PokerClient {
    param([Parameter(Mandatory = $true)]$Client)

    if ($null -ne $Client.Writer) {
        try {
            $Client.Writer.Close()
        } catch {
        }
    }

    if ($null -ne $Client.Reader) {
        try {
            $Client.Reader.Close()
        } catch {
        }
    }

    if ($null -ne $Client.TcpClient) {
        try {
            $Client.TcpClient.Close()
        } catch {
        }
    }

    $Client.Writer = $null
    $Client.Reader = $null
    $Client.TcpClient = $null
}

function Close-ActivePokerClientForShutdown {
    if ($null -ne $script:ActivePokerClientForShutdown) {
        Close-PokerClient -Client $script:ActivePokerClientForShutdown
    }
}

function Unregister-PokerClientShutdownHandler {
    if ($null -ne $script:PokerClientCancelHandler) {
        [Console]::remove_CancelKeyPress($script:PokerClientCancelHandler)
        $script:PokerClientCancelHandler = $null
    }

    $script:ActivePokerClientForShutdown = $null
}

function Register-PokerClientShutdownHandler {
    param([Parameter(Mandatory = $true)]$Client)

    Unregister-PokerClientShutdownHandler
    $script:ActivePokerClientForShutdown = $Client
    $script:PokerClientCancelHandler = [System.ConsoleCancelEventHandler]{
        param($Sender, $EventArgs)
        try {
            Close-ActivePokerClientForShutdown
        } catch {
        }
    }
    [Console]::add_CancelKeyPress($script:PokerClientCancelHandler)
}

function New-ClientRenderText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function ConvertTo-ClientDisplayStreet {
    param([Parameter(Mandatory = $true)][string]$Street)

    switch ($Street) {
        'PreFlop' { return (New-ClientRenderText @(0x7ffb, 0x524d)) }
        'Flop' { return (New-ClientRenderText @(0x7ffb, 0x724c)) }
        'Turn' { return (New-ClientRenderText @(0x8f6c, 0x724c)) }
        'River' { return (New-ClientRenderText @(0x6cb3, 0x724c)) }
        'Showdown' { return (New-ClientRenderText @(0x644a, 0x724c)) }
        'Finished' { return (New-ClientRenderText @(0x7ed3, 0x675f)) }
        default { return $Street }
    }
}

function ConvertTo-ClientDisplayStatus {
    param([Parameter(Mandatory = $true)][string]$Status)

    switch ($Status) {
        'Waiting' { return (New-ClientRenderText @(0x7b49, 0x5f85)) }
        'Acting' { return (New-ClientRenderText @(0x884c, 0x52a8, 0x4e2d)) }
        'Folded' { return (New-ClientRenderText @(0x5df2, 0x5f03, 0x724c)) }
        'AllIn' { return (New-ClientRenderText @(0x5168, 0x4e0b)) }
        'Out' { return (New-ClientRenderText @(0x51fa, 0x5c40)) }
        default { return $Status }
    }
}

function ConvertTo-ClientDisplayPlayerKind {
    param([Parameter(Mandatory = $true)]$Player)

    if ($Player.PSObject.Properties.Name -contains 'IsYou' -and [bool]$Player.IsYou) {
        return (New-ClientRenderText @(0x4f60))
    }

    if ([string]$Player.Type -eq 'RemoteHuman') {
        return (New-ClientRenderText @(0x8054, 0x673a))
    }

    if ([string]$Player.Type -eq 'HumanLocal') {
        return (New-ClientRenderText @(0x771f, 0x4eba))
    }

    $botType = ''
    if ($Player.PSObject.Properties.Name -contains 'BotType') {
        $botType = [string]$Player.BotType
    }

    switch ($botType) {
        'RandomBot' { return (New-ClientRenderText @(0x968f, 0x673a)) }
        'TightBot' { return (New-ClientRenderText @(0x7d27, 0x624b)) }
        'LooseBot' { return (New-ClientRenderText @(0x677e, 0x624b)) }
        'RuleBot' { return (New-ClientRenderText @(0x89c4, 0x5219)) }
        default { return (New-ClientRenderText @(0x673a, 0x5668, 0x4eba)) }
    }
}

function ConvertTo-ClientDisplaySuit {
    param([Parameter(Mandatory = $true)][string]$Suit)

    switch ($Suit.ToUpperInvariant()) {
        'S' { return (New-ClientRenderText @(0x9ed1, 0x6843)) }
        'H' { return (New-ClientRenderText @(0x7ea2, 0x6843)) }
        'D' { return (New-ClientRenderText @(0x65b9, 0x5757)) }
        'C' { return (New-ClientRenderText @(0x6885, 0x82b1)) }
        default { return $Suit }
    }
}

function ConvertTo-ClientDisplayRank {
    param([Parameter(Mandatory = $true)][string]$RankText)

    switch ($RankText.ToUpperInvariant()) {
        'T' { return '10' }
        default { return $RankText.ToUpperInvariant() }
    }
}

function ConvertTo-ClientDisplayCard {
    param([Parameter(Mandatory = $true)]$Card)

    $text = [string]$Card
    if ($Card -isnot [string] -and $Card.PSObject.Properties.Name -contains 'Text') {
        $text = [string]$Card.Text
    }

    $trimmed = $text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -eq '??') {
        return '??'
    }

    if ($trimmed.Length -lt 2) {
        return $trimmed
    }

    $suit = $trimmed.Substring($trimmed.Length - 1, 1)
    $rank = $trimmed.Substring(0, $trimmed.Length - 1)
    return "$(ConvertTo-ClientDisplaySuit -Suit $suit)$(ConvertTo-ClientDisplayRank -RankText $rank)"
}

function Format-ClientCardList {
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Cards = @(),
        [Parameter(Mandatory = $false)][int]$TotalSlots = 0
    )

    $items = @($Cards | Where-Object { $null -ne $_ } | ForEach-Object { "[$(ConvertTo-ClientDisplayCard -Card $_)]" })
    while ($items.Count -lt $TotalSlots) {
        $items += '[??]'
    }
    if ($items.Count -eq 0) {
        return '(none)'
    }
    return ($items -join ' ')
}

function ConvertTo-ClientDisplayAction {
    param([Parameter(Mandatory = $true)]$Action)

    $name = switch ([string]$Action.Command) {
        'fold' { New-ClientRenderText @(0x5f03, 0x724c) }
        'check' { New-ClientRenderText @(0x8fc7, 0x724c) }
        'call' { New-ClientRenderText @(0x8ddf, 0x6ce8) }
        'bet' { New-ClientRenderText @(0x4e0b, 0x6ce8) }
        'raise' { New-ClientRenderText @(0x52a0, 0x6ce8) }
        'allin' { New-ClientRenderText @(0x5168, 0x4e0b) }
        default { $Action.Command }
    }

    if ($null -ne $Action.MinAmount) {
        return "$name$($Action.MinAmount)-$($Action.MaxAmount)"
    }

    return $name
}

function Format-ClientNumberedLegalActions {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actions)

    $items = @()
    $index = 1
    foreach ($action in @($Actions)) {
        $items += "$index.$(ConvertTo-ClientDisplayAction -Action $action)"
        $index++
    }

    return ($items -join '  ')
}

function Get-StateSnapshotViewerRow {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $payload = $Snapshot.Payload
    $players = @($payload.Players)
    $viewer = @($players | Where-Object { $_.PSObject.Properties.Name -contains 'IsYou' -and [bool]$_.IsYou } | Select-Object -First 1)
    if ($viewer.Count -gt 0) {
        return $viewer[0]
    }

    $viewer = @($players | Where-Object { [string]$_.PlayerId -eq [string]$Snapshot.PlayerId } | Select-Object -First 1)
    if ($viewer.Count -gt 0) {
        return $viewer[0]
    }

    return $null
}

function ConvertTo-ClientCardObjects {
    param([Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Cards = @())

    if (-not (Get-Command ConvertTo-Card -ErrorAction SilentlyContinue)) {
        return @()
    }

    $converted = @()
    foreach ($card in @($Cards | Where-Object { $null -ne $_ })) {
        try {
            $converted += ConvertTo-Card -Text ([string]$card)
        } catch {
        }
    }

    return $converted
}

function Get-StateSnapshotAdviceLines {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (-not (Get-Command Get-CurrentBestHandSummary -ErrorAction SilentlyContinue) -or -not (Get-Command Get-HandTypePredictions -ErrorAction SilentlyContinue)) {
        return @()
    }

    $payload = $Snapshot.Payload
    $holeCards = @(ConvertTo-ClientCardObjects -Cards @($payload.YourHoleCards))
    if ($holeCards.Count -eq 0) {
        return @()
    }

    $communityCards = @(ConvertTo-ClientCardObjects -Cards @($payload.CommunityCards))
    $current = Get-CurrentBestHandSummary -HoleCards $holeCards -CommunityCards $communityCards
    $currentText = [string]$current.RankName
    if (-not [string]::IsNullOrWhiteSpace([string]$current.Detail)) {
        $currentText = "$currentText $($current.Detail)"
    }

    $maxLabel = New-ClientRenderText @(0x6700, 0x5927)
    $predictionLabel = New-ClientRenderText @(0x9884, 0x6d4b)
    $lines = @("$maxLabel`: $currentText")
    $predictions = @(Get-HandTypePredictions -HoleCards $holeCards -CommunityCards $communityCards -Top 3)
    if ($predictions.Count -gt 0) {
        $items = @()
        for ($i = 0; $i -lt $predictions.Count; $i++) {
            $items += "$($i + 1). $($predictions[$i].RankName)$($predictions[$i].Probability)%"
        }
        $lines += "$predictionLabel`: $($items -join '  ')"
    }

    return $lines
}

function Format-ClientHandSummaryText {
    param([Parameter(Mandatory = $true)]$Summary)

    $text = [string]$Summary.RankName
    if (-not [string]::IsNullOrWhiteSpace([string]$Summary.Detail)) {
        $text = "$text $($Summary.Detail)"
    }
    return $text
}

function Get-StateSnapshotPlayerBestHandText {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)]$Player
    )

    if (-not (Get-Command Get-CurrentBestHandSummary -ErrorAction SilentlyContinue)) {
        return $null
    }

    $holeCards = @(ConvertTo-ClientCardObjects -Cards @($Player.HoleCards))
    if ($holeCards.Count -eq 0) {
        return $null
    }

    $communityCards = @(ConvertTo-ClientCardObjects -Cards @($Snapshot.Payload.CommunityCards))
    $summary = Get-CurrentBestHandSummary -HoleCards $holeCards -CommunityCards $communityCards
    return Format-ClientHandSummaryText -Summary $summary
}

function Get-StateSnapshotPauseMessage {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $payload = $Snapshot.Payload
    $isPaused = ($payload.PSObject.Properties.Name -contains 'IsPaused') -and [bool]$payload.IsPaused
    if (-not $isPaused) {
        return $null
    }

    if ($payload.PSObject.Properties.Name -contains 'PauseMessage' -and -not [string]::IsNullOrWhiteSpace([string]$payload.PauseMessage)) {
        return [string]$payload.PauseMessage
    }

    return New-ClientRenderText @(0x724c, 0x5c40, 0x6682, 0x505c, 0xff0c, 0x7b49, 0x5f85, 0x79bb, 0x7ebf, 0x73a9, 0x5bb6, 0x91cd, 0x65b0, 0x8fde, 0x63a5)
}

function Format-PreHandStateSnapshotLines {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $payload = $Snapshot.Payload
    $names = @($payload.Players | Sort-Object Seat | ForEach-Object { [string]$_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $roomLabel = New-ClientRenderText @(0x623f, 0x95f4)
    $joinedLabel = New-ClientRenderText @(0x5df2, 0x52a0, 0x5165)
    $waitingLabel = New-ClientRenderText @(0x7b49, 0x5f85, 0x5f00, 0x5c40)

    $lines = if ($names.Count -eq 0) {
        @("$roomLabel`: $waitingLabel")
    } else {
        @("$roomLabel`: $($names -join ', ') $joinedLabel, $waitingLabel")
    }
    $lines = @($lines)

    $pauseMessage = Get-StateSnapshotPauseMessage -Snapshot $Snapshot
    if (-not [string]::IsNullOrWhiteSpace([string]$pauseMessage)) {
        $lines += $pauseMessage
    }

    return $lines
}

function Format-StateSnapshotLines {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $payload = $Snapshot.Payload
    if (($payload.PSObject.Properties.Name -contains 'HandId') -and [int]$payload.HandId -le 0) {
        return @(Format-PreHandStateSnapshotLines -Snapshot $Snapshot)
    }

    $dealerSeat = if ($payload.PSObject.Properties.Name -contains 'DealerSeat') { $payload.DealerSeat } else { '?' }
    $smallBlind = if ($payload.PSObject.Properties.Name -contains 'SmallBlind') { $payload.SmallBlind } else { '?' }
    $bigBlind = if ($payload.PSObject.Properties.Name -contains 'BigBlind') { $payload.BigBlind } else { '?' }
    $lines = @()
    $firstLabel = New-ClientRenderText @(0x7b2c)
    $handLabel = New-ClientRenderText @(0x624b)
    $dealerLabel = New-ClientRenderText @(0x5e84)
    $blindLabel = New-ClientRenderText @(0x76f2)
    $potLabel = New-ClientRenderText @(0x6c60)
    $currentBetLabel = New-ClientRenderText @(0x6ce8)

    $lines += "$firstLabel$($payload.HandId)$handLabel | $dealerLabel$dealerSeat | $(ConvertTo-ClientDisplayStreet -Street ([string]$payload.Street)) | $blindLabel$smallBlind/$bigBlind | $potLabel$($payload.Pot) | $currentBetLabel$($payload.CurrentBet)"
    $lines += '----------------------------------------------------'
    $lines += "$(New-ClientRenderText @(0x5ea7))  $(New-ClientRenderText @(0x73a9, 0x5bb6))      $(New-ClientRenderText @(0x578b))    $(New-ClientRenderText @(0x7b79, 0x7801))  $(New-ClientRenderText @(0x6ce8))  $(New-ClientRenderText @(0x72b6, 0x6001))"

    foreach ($player in @($payload.Players | Sort-Object Seat)) {
        $kind = ConvertTo-ClientDisplayPlayerKind -Player $player
        $status = ConvertTo-ClientDisplayStatus -Status ([string]$player.Status)
        $bet = if ($player.PSObject.Properties.Name -contains 'Bet') { [int]$player.Bet } else { 0 }
        $lines += ("{0,-3} {1,-8} {2,-4} {3,-5} {4,-3} {5}" -f $player.Seat, $player.Name, $kind, $player.Chips, $bet, $status)
    }

    $lines += '----------------------------------------------------'
    $lines += "$(New-ClientRenderText @(0x516c, 0x5171)): $(Format-ClientCardList -Cards @($payload.CommunityCards) -TotalSlots 5)"

    $adviceLines = @(Get-StateSnapshotAdviceLines -Snapshot $Snapshot)
    $handLine = "$(New-ClientRenderText @(0x624b, 0x724c)): $(Format-ClientCardList -Cards @($payload.YourHoleCards))"
    if ($adviceLines.Count -gt 0) {
        $handLine = "$handLine    $($adviceLines[0])"
    }
    $lines += $handLine
    if ($adviceLines.Count -gt 1) {
        for ($i = 1; $i -lt $adviceLines.Count; $i++) {
            $lines += $adviceLines[$i]
        }
    }

    if ([string]$payload.Street -ne 'Finished') {
        $viewer = Get-StateSnapshotViewerRow -Snapshot $Snapshot
        $isPaused = ($payload.PSObject.Properties.Name -contains 'IsPaused') -and [bool]$payload.IsPaused
        $isViewerTurn = $null -ne $viewer -and $null -ne $payload.ActionSeat -and [int]$viewer.Seat -eq [int]$payload.ActionSeat

        if ($isPaused) {
            $lines += (Get-StateSnapshotPauseMessage -Snapshot $Snapshot)
        } elseif (-not $isViewerTurn) {
            $waitingName = if ($payload.PSObject.Properties.Name -contains 'WaitingPlayerName') { [string]$payload.WaitingPlayerName } else { '' }
            $waitText = New-ClientRenderText @(0x8bf7, 0x7b49, 0x5f85, 0x5176, 0x4ed6, 0x73a9, 0x5bb6, 0x51b3, 0x7b56)
            if ([string]::IsNullOrWhiteSpace($waitingName)) {
                $lines += $waitText
            } else {
                $lines += "$waitText`: $waitingName"
            }
        } else {
            $viewerBet = if ($null -ne $viewer -and $viewer.PSObject.Properties.Name -contains 'Bet') { [int]$viewer.Bet } else { 0 }
            $toCall = [Math]::Max(0, [int]$payload.CurrentBet - $viewerBet)
            $lines += "$(New-ClientRenderText @(0x9700, 0x8ddf)): $toCall"
            $lines += "$(New-ClientRenderText @(0x547d, 0x4ee4)): $(Format-ClientNumberedLegalActions -Actions @($payload.LegalActions))"
        }
    } else {
        $lines += (New-ClientRenderText @(0x672c, 0x624b, 0x724c, 0x5df2, 0x7ed3, 0x675f))
        $revealedPlayers = @($payload.Players | Where-Object { $_.PSObject.Properties.Name -contains 'HoleCards' -and $null -ne $_.HoleCards -and @($_.HoleCards).Count -gt 0 })
        if ($revealedPlayers.Count -gt 0) {
            $lines += '----------------------------------------------------'
            $lines += "$(New-ClientRenderText @(0x6240, 0x6709, 0x73a9, 0x5bb6, 0x624b, 0x724c)):"
            $bestLabel = New-ClientRenderText @(0x6700, 0x5927, 0x724c, 0x578b)
            foreach ($player in @($revealedPlayers | Sort-Object Seat)) {
                $line = "$(New-ClientRenderText @(0x5ea7, 0x4f4d))$($player.Seat) $($player.Name): $(Format-ClientCardList -Cards @($player.HoleCards))"
                $bestHand = Get-StateSnapshotPlayerBestHandText -Snapshot $Snapshot -Player $player
                if (-not [string]::IsNullOrWhiteSpace([string]$bestHand)) {
                    $line = "$line  $bestLabel`: $bestHand"
                }
                $lines += $line
            }
        }
        $pauseMessage = Get-StateSnapshotPauseMessage -Snapshot $Snapshot
        if (-not [string]::IsNullOrWhiteSpace([string]$pauseMessage)) {
            $lines += $pauseMessage
        }
    }

    return $lines
}

function Render-StateSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    foreach ($line in @(Format-StateSnapshotLines -Snapshot $Snapshot)) {
        Write-Host $line
    }
}

function Show-StateSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    Render-StateSnapshot -Snapshot $Snapshot
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
            throw (New-ClientRenderText @(0x72b6, 0x6001, 0x547d, 0x4ee4, 0x4ec5, 0x9650, 0x672c, 0x5730, 0x5ba2, 0x6237, 0x7aef, 0x3002))
        }
        'help' {
            throw (New-ClientRenderText @(0x5e2e, 0x52a9, 0x547d, 0x4ee4, 0x4ec5, 0x9650, 0x672c, 0x5730, 0x5ba2, 0x6237, 0x7aef, 0x3002))
        }
        'history' {
            throw (New-ClientRenderText @(0x5386, 0x53f2, 0x547d, 0x4ee4, 0x4ec5, 0x9650, 0x672c, 0x5730, 0x5ba2, 0x6237, 0x7aef, 0x3002))
        }
    }

    if (-not (Test-ClientActionLegal -LegalActions $legalActions -Command $rawAction.Command -Amount $rawAction.Amount)) {
        throw (New-ClientRenderText @(0x5f53, 0x524d, 0x72b6, 0x6001, 0x4e0b, 0x8be5, 0x64cd, 0x4f5c, 0x4e0d, 0x5408, 0x6cd5, 0x3002))
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
            Read-Host '>'
        }

        if ([string]::IsNullOrWhiteSpace([string]$inputText)) {
            Write-Host (New-ClientRenderText @(0x8bf7, 0x8f93, 0x5165, 0x6709, 0x6548, 0x547d, 0x4ee4))
            continue
        }

        try {
            return ConvertTo-ClientPlayerAction -Client $Client -ActionRequest $ActionRequest -InputText $inputText
        } catch {
            if ($_.Exception.Message -eq 'Player quit.') {
                throw
            }
            Write-Host "$(New-ClientRenderText @(0x65e0, 0x6548, 0x64cd, 0x4f5c)): $($_.Exception.Message)"
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
    try {
        Register-PokerClientShutdownHandler -Client $client
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
    } finally {
        Close-PokerClient -Client $client
        Unregister-PokerClientShutdownHandler
    }

    return $client
}
