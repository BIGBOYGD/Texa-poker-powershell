$manifestPath = "$PSScriptRoot\TestManifest.ps1"
if (Test-Path -LiteralPath $manifestPath) {
    . $manifestPath
}

function Assert-TestRunnerManifestImported {
    Assert-True ([bool](Get-Command Resolve-TestFiles -ErrorAction SilentlyContinue)) 'Resolve-TestFiles should exist.'
}

Run-TestCase "Test runner default uses quick tests and excludes stress suites" {
    Assert-TestRunnerManifestImported

    $quick = @(Resolve-TestFiles)

    Assert-True ($quick -contains 'Test-Render.ps1') 'Quick tests should include render coverage.'
    Assert-True ($quick -contains 'Test-Pot.ps1') 'Quick tests should include pot coverage.'
    Assert-True ($quick -contains 'Test-TestRunner.ps1') 'Quick tests should include test runner coverage.'
    Assert-False ($quick -contains 'Test-BotTuning.ps1') 'Quick tests should exclude bot tuning stress coverage.'
    Assert-False ($quick -contains 'Test-Stability.ps1') 'Quick tests should exclude long stability coverage.'
}

Run-TestCase "Test runner full and stress modes expose expected suites" {
    Assert-TestRunnerManifestImported

    $full = @(Resolve-TestFiles -Full)
    $stress = @(Resolve-TestFiles -Stress)

    Assert-True ($full -contains 'Test-Render.ps1') 'Full tests should include quick test files.'
    Assert-True ($full -contains 'Test-BotTuning.ps1') 'Full tests should include stress test files.'
    Assert-True ($full -contains 'Test-Stability.ps1') 'Full tests should include stability tests.'
    Assert-True ($stress -contains 'Test-BotTuning.ps1') 'Stress tests should include bot tuning.'
    Assert-True ($stress -contains 'Test-Stability.ps1') 'Stress tests should include stability simulation.'
    Assert-False ($stress -contains 'Test-Render.ps1') 'Stress tests should not include normal render tests.'
}

Run-TestCase "Test runner name filter selects matching test files" {
    Assert-TestRunnerManifestImported

    $render = @(Resolve-TestFiles -Name 'Render')
    $botStress = @(Resolve-TestFiles -Stress -Name 'Bot')

    Assert-SequenceEqual @('Test-Render.ps1') $render
    Assert-True ($botStress -contains 'Test-BotTuning.ps1') 'Stress Bot filter should include bot tuning.'
    Assert-True ($botStress -contains 'Test-BotStrategy.ps1') 'Stress Bot filter should include bot strategy.'
    Assert-False ($botStress -contains 'Test-Stability.ps1') 'Stress Bot filter should exclude non-matching stability tests.'
}
