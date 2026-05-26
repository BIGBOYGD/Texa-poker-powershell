param(
    [Parameter(Mandatory = $false)][switch]$Full,
    [Parameter(Mandatory = $false)][switch]$Stress,
    [Parameter(Mandatory = $false)][string[]]$Name = @()
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Assert.ps1"
. "$PSScriptRoot\TestManifest.ps1"

$testFiles = @(Resolve-TestFiles -Full:$Full -Stress:$Stress -Name $Name)
if ($testFiles.Count -eq 0) {
    Write-Host "No test files matched."
    exit 1
}

$mode = if ($Stress) {
    'stress'
} elseif ($Full) {
    'full'
} else {
    'quick'
}
Write-Host "Running $mode test set: $($testFiles.Count) file(s)."

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
Write-Host "All selected tests passed."
exit 0
