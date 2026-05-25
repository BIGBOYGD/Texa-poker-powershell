function ConvertTo-PlayerAction {
    param([Parameter(Mandatory = $true)][string]$InputText)

    $parts = @($InputText.Trim() -split '\s+' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) {
        throw 'Empty command.'
    }

    $command = ConvertTo-CanonicalCommand -CommandText $parts[0]
    $amount = $null

    if (@('bet', 'raise') -contains $command) {
        if ($parts.Count -ne 2) {
            throw "$command requires an amount."
        }
        $parsed = 0
        if (-not [int]::TryParse($parts[1], [ref]$parsed)) {
            throw "Invalid amount '$($parts[1])'."
        }
        $amount = $parsed
    } elseif ($parts.Count -ne 1) {
        throw "Command '$command' does not take extra arguments."
    }

    if (@('help', 'status', 'history', 'quit', 'fold', 'check', 'call', 'allin', 'bet', 'raise') -notcontains $command) {
        throw "Unknown command '$command'."
    }

    [pscustomobject]@{
        Command = $command
        Amount = $amount
    }
}

function ConvertFrom-NumberedPlayerAction {
    param(
        [Parameter(Mandatory = $true)][string]$InputText,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LegalActions
    )

    $parts = @($InputText.Trim() -split '\s+' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) {
        throw 'Empty command.'
    }

    $index = 0
    if (-not [int]::TryParse($parts[0], [ref]$index)) {
        return $null
    }

    $actions = @($LegalActions)
    if ($index -lt 1 -or $index -gt $actions.Count) {
        throw "Numbered command '$index' is not available."
    }

    $selected = $actions[$index - 1]
    $amount = $null
    if ($null -ne $selected.MinAmount) {
        if ($parts.Count -gt 2) {
            throw "Numbered command '$index' has too many arguments."
        }
        if ($parts.Count -eq 2) {
            $parsed = 0
            if (-not [int]::TryParse($parts[1], [ref]$parsed)) {
                throw "Invalid amount '$($parts[1])'."
            }
            $amount = $parsed
        } else {
            $amount = [int]$selected.MinAmount
        }
    } elseif ($parts.Count -ne 1) {
        throw "Numbered command '$index' does not take an amount."
    }

    [pscustomobject]@{
        Command = $selected.Command
        Amount = $amount
    }
}

function New-CommandText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function ConvertTo-CanonicalCommand {
    param([Parameter(Mandatory = $true)][string]$CommandText)

    $command = $CommandText.ToLowerInvariant()
    $aliases = @{
        (New-CommandText @(0x5f03, 0x724c)) = 'fold'
        (New-CommandText @(0x8fc7, 0x724c)) = 'check'
        (New-CommandText @(0x8ddf, 0x6ce8)) = 'call'
        (New-CommandText @(0x4e0b, 0x6ce8)) = 'bet'
        (New-CommandText @(0x52a0, 0x6ce8)) = 'raise'
        (New-CommandText @(0x5168, 0x4e0b)) = 'allin'
        (New-CommandText @(0x72b6, 0x6001)) = 'status'
        (New-CommandText @(0x5e2e, 0x52a9)) = 'help'
        (New-CommandText @(0x5386, 0x53f2)) = 'history'
        (New-CommandText @(0x9000, 0x51fa)) = 'quit'
    }

    if ($aliases.ContainsKey($command)) {
        return $aliases[$command]
    }

    return $command
}

function Read-PlayerCommand {
    return (Read-Host '>')
}
