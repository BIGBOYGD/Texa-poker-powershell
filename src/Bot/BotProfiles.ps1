$script:BotProfileNumericFields = @('vpip', 'aggression', 'bluffRate', 'callTolerance', 'raiseBias', 'riskTolerance', 'randomness')
$script:BotProfilePathCache = @{}

function New-BotProfileObject {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][double]$Vpip,
        [Parameter(Mandatory = $true)][double]$Aggression,
        [Parameter(Mandatory = $true)][double]$BluffRate,
        [Parameter(Mandatory = $true)][double]$CallTolerance,
        [Parameter(Mandatory = $true)][double]$RaiseBias,
        [Parameter(Mandatory = $true)][double]$RiskTolerance,
        [Parameter(Mandatory = $true)][double]$Randomness
    )

    [pscustomobject]@{
        Name = $Name
        enabled = $Enabled
        description = $Description
        vpip = $Vpip
        aggression = $Aggression
        bluffRate = $BluffRate
        callTolerance = $CallTolerance
        raiseBias = $RaiseBias
        riskTolerance = $RiskTolerance
        randomness = $Randomness
    }
}

function Get-DefaultBotProfileMap {
    $profiles = [ordered]@{}
    $profiles['RandomBot'] = (New-BotProfileObject -Name 'RandomBot' -Enabled $true -Description 'Random legal-action bot for tests.' -Vpip 0.30 -Aggression 0.30 -BluffRate 0.05 -CallTolerance 0.35 -RaiseBias 0.25 -RiskTolerance 0.35 -Randomness 0.35);
    $profiles['TightBot'] = (New-BotProfileObject -Name 'TightBot' -Enabled $true -Description 'Conservative tight bot.' -Vpip 0.18 -Aggression 0.25 -BluffRate 0.02 -CallTolerance 0.25 -RaiseBias 0.20 -RiskTolerance 0.20 -Randomness 0.10);
    $profiles['LooseBot'] = (New-BotProfileObject -Name 'LooseBot' -Enabled $true -Description 'Loose aggressive bot.' -Vpip 0.45 -Aggression 0.65 -BluffRate 0.12 -CallTolerance 0.60 -RaiseBias 0.45 -RiskTolerance 0.55 -Randomness 0.20);
    $profiles['RuleBot'] = (New-BotProfileObject -Name 'RuleBot' -Enabled $true -Description 'Rule-based strategy bot.' -Vpip 0.28 -Aggression 0.45 -BluffRate 0.06 -CallTolerance 0.42 -RaiseBias 0.35 -RiskTolerance 0.40 -Randomness 0.12);
    return $profiles
}

function Get-DefaultBotProfile {
    param([Parameter(Mandatory = $true)][string]$Name)

    $profiles = Get-DefaultBotProfileMap
    if (-not $profiles.Contains($Name)) {
        throw "Unknown bot profile '$Name'."
    }
    return $profiles[$Name]
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $false)][AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Limit-BotProfileValue {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][double]$Default
    )

    $number = $Default
    if ($null -ne $Value) {
        try {
            $number = [double]$Value
        } catch {
            $number = $Default
        }
    }

    if ($number -lt 0) { return 0.0 }
    if ($number -gt 1) { return 1.0 }
    return $number
}

function Merge-BotProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$DefaultProfile,
        [Parameter(Mandatory = $false)]$ConfigProfile = $null
    )

    $enabledValue = Get-ObjectPropertyValue -Object $ConfigProfile -Name 'enabled' -Default $DefaultProfile.enabled
    $descriptionValue = Get-ObjectPropertyValue -Object $ConfigProfile -Name 'description' -Default $DefaultProfile.description

    $values = @{}
    foreach ($field in $script:BotProfileNumericFields) {
        $configured = Get-ObjectPropertyValue -Object $ConfigProfile -Name $field -Default $DefaultProfile.$field
        $values[$field] = Limit-BotProfileValue -Value $configured -Default ([double]$DefaultProfile.$field)
    }

    return New-BotProfileObject `
        -Name $Name `
        -Enabled ([bool]$enabledValue) `
        -Description ([string]$descriptionValue) `
        -Vpip $values['vpip'] `
        -Aggression $values['aggression'] `
        -BluffRate $values['bluffRate'] `
        -CallTolerance $values['callTolerance'] `
        -RaiseBias $values['raiseBias'] `
        -RiskTolerance $values['riskTolerance'] `
        -Randomness $values['randomness']
}

function Load-BotProfiles {
    param(
        [Parameter(Mandatory = $false)][string]$Path,
        [Parameter(Mandatory = $false)]$ConfigObject
    )

    $cacheKey = $null
    $cacheTicks = $null
    if (-not $PSBoundParameters.ContainsKey('ConfigObject') -and -not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        $file = Get-Item -LiteralPath $Path
        $cacheKey = $file.FullName
        $cacheTicks = $file.LastWriteTimeUtc.Ticks
        if ($script:BotProfilePathCache.ContainsKey($cacheKey)) {
            $cached = $script:BotProfilePathCache[$cacheKey]
            if ($cached.LastWriteTimeUtcTicks -eq $cacheTicks) {
                return $cached.Profiles
            }
        }
    }

    if ($PSBoundParameters.ContainsKey('ConfigObject')) {
        $config = $ConfigObject
    } elseif ($null -ne $cacheKey) {
        $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    } else {
        $config = $null
    }

    $defaults = Get-DefaultBotProfileMap
    $profiles = [ordered]@{}
    foreach ($name in $defaults.Keys) {
        $configured = Get-ObjectPropertyValue -Object $config -Name $name -Default $null
        $profiles[$name] = (Merge-BotProfile -Name $name -DefaultProfile $defaults[$name] -ConfigProfile $configured)
    }

    if ($null -ne $cacheKey) {
        $script:BotProfilePathCache[$cacheKey] = [pscustomobject]@{
            LastWriteTimeUtcTicks = $cacheTicks
            Profiles = $profiles
        }
    }

    return $profiles
}

function Get-BotProfile {
    param(
        [Parameter(Mandatory = $true)]$Profiles,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Profiles -is [System.Collections.IDictionary] -and $Profiles.Contains($Name)) {
        return $Profiles[$Name]
    }

    $profile = Get-ObjectPropertyValue -Object $Profiles -Name $Name -Default $null
    if ($null -ne $profile) {
        return $profile
    }

    return Get-DefaultBotProfile -Name $Name
}

function Test-BotProfile {
    param([Parameter(Mandatory = $true)]$Profile)

    foreach ($field in @('Name', 'enabled', 'description') + $script:BotProfileNumericFields) {
        if ($Profile.PSObject.Properties.Name -notcontains $field) {
            return $false
        }
    }

    foreach ($field in $script:BotProfileNumericFields) {
        $value = [double]$Profile.$field
        if ($value -lt 0 -or $value -gt 1) {
            return $false
        }
    }

    return $true
}
