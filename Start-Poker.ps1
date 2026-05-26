param(
    [Parameter(Mandatory = $false)][ValidateSet('Local', 'LocalHotSeat', 'Host', 'Client')][string]$Mode = 'Local',
    [Parameter(Mandatory = $false)][ValidateRange(0, 5)][int]$Bots = 5,
    [Parameter(Mandatory = $false)][ValidateRange(2, 6)][int]$Players = 2,
    [Parameter(Mandatory = $false)][ValidateRange(1, 1000)][int]$Hands = 1,
    [Parameter(Mandatory = $false)][ValidateRange(1, 65535)][int]$Port = 7777,
    [Parameter(Mandatory = $false)][Alias('Host')][string]$HostAddress = '127.0.0.1',
    [Parameter(Mandatory = $false)][string]$Name = 'Player',
    [Parameter(Mandatory = $false)][switch]$AutoPlay,
    [Parameter(Mandatory = $false)][switch]$Help
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\src\Core\Card.ps1"
. "$PSScriptRoot\src\Core\Deck.ps1"
. "$PSScriptRoot\src\Core\GameState.ps1"
. "$PSScriptRoot\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\src\Core\HandAdvisor.ps1"
. "$PSScriptRoot\src\Core\Betting.ps1"
. "$PSScriptRoot\src\Core\Pot.ps1"
. "$PSScriptRoot\src\Core\Rules.ps1"
. "$PSScriptRoot\src\Core\Showdown.ps1"
. "$PSScriptRoot\src\UI\CommandParser.ps1"
. "$PSScriptRoot\src\UI\Render.ps1"
. "$PSScriptRoot\src\Bot\BotProfiles.ps1"
. "$PSScriptRoot\src\Bot\BotEvaluator.ps1"
. "$PSScriptRoot\src\Bot\BotDecision.ps1"
. "$PSScriptRoot\src\Bot\RandomBot.ps1"
. "$PSScriptRoot\src\Bot\TightBot.ps1"
. "$PSScriptRoot\src\Bot\LooseBot.ps1"
. "$PSScriptRoot\src\Bot\RuleBot.ps1"
. "$PSScriptRoot\src\Bot\BotBase.ps1"
. "$PSScriptRoot\src\Persistence\DebugLogger.ps1"
. "$PSScriptRoot\src\Local\GameLoop.ps1"
. "$PSScriptRoot\src\Network\Protocol.ps1"
. "$PSScriptRoot\src\Network\Server.ps1"
. "$PSScriptRoot\src\Network\Client.ps1"

function Show-PokerHelp {
    Write-Host "PokerTerminalPS"
    Write-Host ""
    Write-Host "$(New-RenderText @(0x672c, 0x5730, 0x6f14, 0x793a)):"
    Write-Host "  .\Start-Poker.ps1 -Mode Local -Bots 1"
    Write-Host "  .\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 3"
    Write-Host "  .\Start-Poker.ps1 -Mode LocalHotSeat -Players 3"
    Write-Host "  .\Start-Poker.ps1 -Mode Host -Port 7777"
    Write-Host "  .\Start-Poker.ps1 -Mode Client -Host 127.0.0.1 -Port 7777 -Name Alice"
    Write-Host ""
    Write-Host "$(New-RenderText @(0x5e38, 0x7528, 0x547d, 0x4ee4)):"
    $fold = New-RenderText @(0x5f03, 0x724c)
    $check = New-RenderText @(0x8fc7, 0x724c)
    $call = New-RenderText @(0x8ddf, 0x6ce8)
    $bet = New-RenderText @(0x4e0b, 0x6ce8)
    $raise = New-RenderText @(0x52a0, 0x6ce8)
    $allin = New-RenderText @(0x5168, 0x4e0b)
    $status = New-RenderText @(0x72b6, 0x6001)
    $helpText = New-RenderText @(0x5e2e, 0x52a9)
    $quitText = New-RenderText @(0x9000, 0x51fa)
    Write-Host "  fold/$fold / check/$check / call/$call / bet 80/$bet 80 / raise 160/$raise 160 / allin/$allin / status/$status / help/$helpText / quit/$quitText"
    Write-Host ""
    Write-Host "LAN stage 3: Host/Client join and remote actions are enabled."
}

if ($Help) {
    Show-PokerHelp
    exit 0
}

if ($Mode -eq 'Host') {
    Start-PokerServer -Port $Port -MaxSeats 6 -BotCount $Bots
    exit 0
}

if ($Mode -eq 'Client') {
    Start-PokerClient -HostAddress $HostAddress -Port $Port -Name $Name | Out-Null
    exit 0
}

$seatCount = if ($Mode -eq 'Local') { [Math]::Min(6, [Math]::Max(2, 1 + $Bots)) } else { $Players }
$tablePlayers = @()
$humanName = New-RenderText @(0x4f60)
$botPrefix = New-RenderText @(0x673a, 0x5668, 0x4eba)
$playerPrefix = New-RenderText @(0x73a9, 0x5bb6)

for ($seat = 1; $seat -le $seatCount; $seat++) {
    if ($seat -eq 1) {
        $tablePlayers += New-PlayerState -Seat $seat -Name $humanName -Type 'HumanLocal' -Chips 1000
    } elseif ($Mode -eq 'Local') {
        $bot = New-PlayerState -Seat $seat -Name "$botPrefix$seat" -Type 'Bot' -Chips 1000
        $botTypes = @('RandomBot', 'TightBot', 'LooseBot', 'RuleBot')
        $bot | Add-Member -NotePropertyName BotType -NotePropertyValue $botTypes[($seat - 2) % $botTypes.Count]
        $tablePlayers += $bot
    } else {
        $tablePlayers += New-PlayerState -Seat $seat -Name "$playerPrefix$seat" -Type 'HumanLocal' -Chips 1000
    }
}

$game = New-GameState -Players $tablePlayers -SmallBlind 10 -BigBlind 20 -Mode 'Local'
$debugEnabled = $PSBoundParameters.ContainsKey('Debug') -or $DebugPreference -ne 'SilentlyContinue'
$debugLogPath = Initialize-DebugLogger -Enabled:([bool]$debugEnabled) -RootPath $PSScriptRoot
$handsWasSpecified = $PSBoundParameters.ContainsKey('Hands')
$handsToPlay = if ($AutoPlay -or $handsWasSpecified) { $Hands } else { [int]::MaxValue }

for ($hand = 1; $hand -le $handsToPlay; $hand++) {
    if ($AutoPlay) {
        foreach ($player in $game.Players) {
            if ($player.Type -eq 'HumanLocal') {
                $player.Type = 'Bot'
            }
        }
    }

    try {
        Invoke-LocalHand -Game $game
    } catch {
        if ($_.Exception.Message -eq 'Player quit.') {
            Write-Host (New-RenderText @(0x5df2, 0x9000, 0x51fa, 0x6e38, 0x620f))
            break
        }
        throw
    }

    Render-Table -Game $game -ViewerSeat 1 -ShowAllCards

    Write-Host ""
    Write-Host "$(New-RenderText @(0x7b2c)) $($game.HandId) $(New-RenderText @(0x624b, 0x724c, 0x7ed3, 0x675f))"

    if (-not (Test-CanStartNextHand -Game $game)) {
        Write-Host (New-RenderText @(0x53ef, 0x7ee7, 0x7eed, 0x73a9, 0x5bb6, 0x4e0d, 0x8db3, 0x20, 0x32, 0x20, 0x4eba, 0xff0c, 0x724c, 0x5c40, 0x7ed3, 0x675f))
        break
    }

    if (-not $AutoPlay -and -not (Test-PlayerCanContinue -Game $game -Seat 1)) {
        Write-Host (New-RenderText @(0x4f60, 0x7684, 0x7b79, 0x7801, 0x5df2, 0x4e3a, 0x20, 0x30, 0xff0c, 0x724c, 0x5c40, 0x7ed3, 0x675f))
        break
    }

    if (-not $AutoPlay -and -not $handsWasSpecified) {
        $continuePrompt = New-RenderText @(0x6309, 0x20, 0x45, 0x6e, 0x74, 0x65, 0x72, 0x20, 0x7ee7, 0x7eed, 0x4e0b, 0x4e00, 0x624b, 0xff0c, 0x8f93, 0x5165, 0x20, 0x71, 0x75, 0x69, 0x74, 0x20, 0x6216, 0x20)
        $quitText = New-RenderText @(0x9000, 0x51fa)
        $suffix = New-RenderText @(0x20, 0x7ed3, 0x675f)
        $answer = Read-Host "$continuePrompt$quitText$suffix"
        if ($answer -ne '') {
            try {
                $nextAction = ConvertTo-PlayerAction -InputText $answer
                if ($nextAction.Command -eq 'quit') {
                    break
                }
            } catch {
                Write-Host (New-RenderText @(0x8f93, 0x5165, 0x672a, 0x8bc6, 0x522b, 0xff0c, 0x7ee7, 0x7eed, 0x4e0b, 0x4e00, 0x624b))
            }
        }
    }
}

Write-Host ""
Write-Host "$(New-RenderText @(0x8fd0, 0x884c)) .\tests\Run-Tests.ps1 $(New-RenderText @(0x8fdb, 0x884c, 0x81ea, 0x52a8, 0x5316, 0x9a8c, 0x8bc1))"
