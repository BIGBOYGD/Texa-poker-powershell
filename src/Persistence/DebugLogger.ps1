$script:DebugLoggerState = [pscustomobject]@{
    Enabled = $false
    LogPath = $null
    Seq = 0
}

function Initialize-DebugLogger {
    param(
        [Parameter(Mandatory = $false)][bool]$Enabled = $false,
        [Parameter(Mandatory = $false)][string]$RootPath = (Get-Location).Path
    )

    $script:DebugLoggerState.Enabled = [bool]$Enabled
    $script:DebugLoggerState.LogPath = $null
    $script:DebugLoggerState.Seq = 0

    if (-not $Enabled) {
        return $null
    }

    $logDir = Join-Path $RootPath 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $logPath = Join-Path $logDir "session_${timestamp}_debug.jsonl"
    New-Item -ItemType File -Path $logPath -Force | Out-Null
    $script:DebugLoggerState.LogPath = $logPath

    return $logPath
}

function Disable-DebugLogger {
    $script:DebugLoggerState.Enabled = $false
    $script:DebugLoggerState.LogPath = $null
    $script:DebugLoggerState.Seq = 0
}

function Test-DebugLoggerEnabled {
    return ([bool]$script:DebugLoggerState.Enabled -and -not [string]::IsNullOrWhiteSpace($script:DebugLoggerState.LogPath))
}

function Get-DebugLogPath {
    return $script:DebugLoggerState.LogPath
}

function Write-DebugLogEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $false)]$Fields = $null
    )

    if (-not (Test-DebugLoggerEnabled)) {
        return
    }

    $script:DebugLoggerState.Seq = [int]$script:DebugLoggerState.Seq + 1
    $event = [ordered]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString('o')
        EventType = $EventType
        ConnectionId = $null
        PlayerId = $null
        MessageType = $null
        Seq = [int]$script:DebugLoggerState.Seq
        Direction = $null
        ErrorMessage = $null
    }

    if ($null -ne $Fields) {
        foreach ($property in $Fields.PSObject.Properties) {
            $event[$property.Name] = $property.Value
        }
    }

    $json = $event | ConvertTo-Json -Compress -Depth 8
    Add-Content -LiteralPath $script:DebugLoggerState.LogPath -Value $json -Encoding UTF8
}

function Write-BotDecisionDebugLog {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player,
        [Parameter(Mandatory = $true)]$Action
    )

    if (-not (Test-DebugLoggerEnabled)) {
        return
    }

    $legalActions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
    $botType = 'LooseBot'
    if ($Player.PSObject.Properties.Name -contains 'BotType' -and -not [string]::IsNullOrWhiteSpace($Player.BotType)) {
        $botType = [string]$Player.BotType
    }

    $profile = $null
    if (Get-Command Load-BotProfiles -ErrorAction SilentlyContinue) {
        $profiles = Load-BotProfiles -Path "$PSScriptRoot\..\..\data\bot_profiles.json"
        $profile = Get-BotProfile -Profiles $profiles -Name $botType
    }

    $context = if ($null -ne $profile -and (Get-Command New-BotDecisionContext -ErrorAction SilentlyContinue)) {
        New-BotDecisionContext -Game $Game -Player $Player -Profile $profile -LegalActions $legalActions
    } else {
        $potSize = 0
        foreach ($tablePlayer in $Game.Players) {
            $potSize += [int]$tablePlayer.TotalBetThisHand
        }

        [pscustomobject]@{
            HandId = $Game.HandId
            Street = $Game.Street
            BotSeat = $Player.Seat
            BotName = $Player.Name
            BotType = $botType
            PotSize = [int]$potSize
            CurrentBet = [int]$Game.CurrentBet
            MinRaise = [int]$Game.MinRaise
            ToCall = [Math]::Max(0, [int]$Game.CurrentBet - [int]$Player.StreetBet)
            LegalActions = $legalActions
            PreflopScore = 0
            PostflopScore = 0
            DrawScore = 0
            PositionScore = 0
            PotOdds = 0.0
        }
    }

    $finalScore = if ($Action.PSObject.Properties.Name -contains 'FinalScore') { [int]$Action.FinalScore } else { 0 }
    $reason = if ($Action.PSObject.Properties.Name -contains 'Reason') { [string]$Action.Reason } else { 'random legal action' }
    $selectedAmount = if ($Action.PSObject.Properties.Name -contains 'Amount') { $Action.Amount } else { $null }

    Write-DebugLogEvent -EventType 'BotDecision' -Fields ([pscustomobject]@{
        HandId = [int]$context.HandId
        Street = [string]$context.Street
        BotSeat = [int]$context.BotSeat
        BotName = [string]$context.BotName
        BotType = [string]$context.BotType
        ToCall = [int]$context.ToCall
        PotSize = [int]$context.PotSize
        CurrentBet = [int]$context.CurrentBet
        MinRaise = [int]$context.MinRaise
        PreflopScore = [int]$context.PreflopScore
        PostflopScore = [int]$context.PostflopScore
        DrawScore = [int]$context.DrawScore
        PositionScore = [int]$context.PositionScore
        PotOdds = [double]$context.PotOdds
        FinalScore = $finalScore
        LegalActions = @($context.LegalActions | ForEach-Object { $_.Command })
        SelectedAction = [string]$Action.Command
        SelectedAmount = $selectedAmount
        Reason = $reason
    })
}
