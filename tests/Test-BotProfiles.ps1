. "$PSScriptRoot\..\src\Bot\BotProfiles.ps1"

Run-TestCase "Bot profiles config loads required v0.4 profiles" {
    $profiles = Load-BotProfiles -Path "$PSScriptRoot\..\data\bot_profiles.json"

    foreach ($name in @('RandomBot', 'TightBot', 'LooseBot', 'RuleBot')) {
        $profile = Get-BotProfile -Profiles $profiles -Name $name

        Assert-True ($null -ne $profile) "$name should load."
        Assert-Equal $name $profile.Name
        Assert-True (Test-BotProfile -Profile $profile) "$name should pass profile validation."
    }
}

Run-TestCase "Bot profiles contain all numeric personality fields in range" {
    $profiles = Load-BotProfiles -Path "$PSScriptRoot\..\data\bot_profiles.json"
    $fields = @('vpip', 'aggression', 'bluffRate', 'callTolerance', 'raiseBias', 'riskTolerance', 'randomness')

    foreach ($name in @('TightBot', 'LooseBot', 'RuleBot')) {
        $profile = Get-BotProfile -Profiles $profiles -Name $name
        foreach ($field in $fields) {
            $value = [double]$profile.$field

            Assert-True ($profile.PSObject.Properties.Name -contains $field) "$name missing $field."
            Assert-True ($value -ge 0 -and $value -le 1) "$name $field should be between 0 and 1."
        }
    }
}

Run-TestCase "Missing bot profile fields fall back to defaults" {
    $partial = [pscustomobject]@{
        TightBot = [pscustomobject]@{
            enabled = $true
            vpip = 0.22
        }
    }

    $profiles = Load-BotProfiles -ConfigObject $partial
    $profile = Get-BotProfile -Profiles $profiles -Name 'TightBot'
    $default = Get-DefaultBotProfile -Name 'TightBot'

    Assert-Equal 0.22 ([double]$profile.vpip)
    Assert-Equal ([double]$default.aggression) ([double]$profile.aggression)
    Assert-Equal ([double]$default.bluffRate) ([double]$profile.bluffRate)
    Assert-True (Test-BotProfile -Profile $profile)
}
