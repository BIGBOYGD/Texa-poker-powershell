$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Assert.ps1"

$testFiles = @(
    'Test-Deck.ps1',
    'Test-HandEvaluator.ps1',
    'Test-HandAdvisor.ps1',
    'Test-Betting.ps1',
    'Test-Pot.ps1',
    'Test-IntegrationAllInFlow.ps1',
    'Test-Showdown.ps1',
    'Test-Bot.ps1',
    'Test-CommandParser.ps1',
    'Test-Stability.ps1',
    'Test-Rules.ps1',
    'Test-Render.ps1',
    'Test-GameLoop.ps1'
)

foreach ($testFile in $testFiles) {
    . "$PSScriptRoot\$testFile"
}

$failureCount = Get-TestFailureCount
if ($failureCount -gt 0) {
    Write-Host ""
    Write-Host "$failureCount test(s) failed."
    exit 1
}

Write-Host ""
Write-Host "All tests passed."
exit 0
