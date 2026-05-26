$script:QuickTestFiles = @(
    'Test-TestRunner.ps1',
    'Test-Deck.ps1',
    'Test-HandEvaluator.ps1',
    'Test-HandAdvisor.ps1',
    'Test-BotProfiles.ps1',
    'Test-BotEvaluator.ps1',
    'Test-Betting.ps1',
    'Test-Pot.ps1',
    'Test-IntegrationAllInFlow.ps1',
    'Test-Showdown.ps1',
    'Test-DebugLogger.ps1',
    'Test-NetworkProtocol.ps1',
    'Test-CommandParser.ps1',
    'Test-Rules.ps1',
    'Test-Render.ps1',
    'Test-GameLoop.ps1'
)

$script:StressTestFiles = @(
    'Test-Bot.ps1',
    'Test-BotDecision.ps1',
    'Test-BotStrategy.ps1',
    'Test-BotTuning.ps1',
    'Test-Stability.ps1'
)

function Get-AllTestFiles {
    $seen = @{}
    $files = @()
    foreach ($file in @($script:QuickTestFiles + $script:StressTestFiles)) {
        if (-not $seen.ContainsKey($file)) {
            $seen[$file] = $true
            $files += $file
        }
    }

    return $files
}

function Select-TestFilesByName {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Files,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]]$Name = @()
    )

    $filters = @($Name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($filters.Count -eq 0) {
        return @($Files)
    }

    return @($Files | Where-Object {
        $file = $_
        @($filters | Where-Object { $file -like "*$_*" }).Count -gt 0
    })
}

function Resolve-TestFiles {
    param(
        [Parameter(Mandatory = $false)][switch]$Full,
        [Parameter(Mandatory = $false)][switch]$Stress,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]]$Name = @()
    )

    if ($Full -and $Stress) {
        throw 'Use either -Full or -Stress, not both.'
    }

    $files = if ($Stress) {
        @($script:StressTestFiles)
    } elseif ($Full) {
        @(Get-AllTestFiles)
    } else {
        @($script:QuickTestFiles)
    }

    return @(Select-TestFilesByName -Files $files -Name $Name)
}
