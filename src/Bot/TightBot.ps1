function Get-TightBotAction {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)]$Player
    )

    $legalActions = @(Get-LegalActions -Game $Game -Seat $Player.Seat)
    if ($legalActions.Count -eq 0) {
        throw "TightBot at seat $($Player.Seat) has no legal action."
    }

    $profiles = Load-BotProfiles -Path "$PSScriptRoot\..\..\data\bot_profiles.json"
    $profile = Get-BotProfile -Profiles $profiles -Name 'TightBot'
    $context = New-BotDecisionContext -Game $Game -Player $Player -Profile $profile -LegalActions $legalActions

    return Get-BotDecision -Context $context -LegalActions $legalActions
}
