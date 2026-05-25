. "$PSScriptRoot\..\src\UI\CommandParser.ps1"

function New-TestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

Run-TestCase "Chinese command aliases parse to internal English commands" {
    $cases = @(
        @{ Text = (New-TestText @(0x5f03, 0x724c)); Command = 'fold'; Amount = $null },
        @{ Text = (New-TestText @(0x8fc7, 0x724c)); Command = 'check'; Amount = $null },
        @{ Text = (New-TestText @(0x8ddf, 0x6ce8)); Command = 'call'; Amount = $null },
        @{ Text = "$(New-TestText @(0x4e0b, 0x6ce8)) 80"; Command = 'bet'; Amount = 80 },
        @{ Text = "$(New-TestText @(0x52a0, 0x6ce8)) 160"; Command = 'raise'; Amount = 160 },
        @{ Text = (New-TestText @(0x5168, 0x4e0b)); Command = 'allin'; Amount = $null },
        @{ Text = (New-TestText @(0x72b6, 0x6001)); Command = 'status'; Amount = $null },
        @{ Text = (New-TestText @(0x5e2e, 0x52a9)); Command = 'help'; Amount = $null },
        @{ Text = (New-TestText @(0x9000, 0x51fa)); Command = 'quit'; Amount = $null }
    )

    foreach ($case in $cases) {
        $action = ConvertTo-PlayerAction -InputText $case.Text
        Assert-Equal $case.Command $action.Command
        if ($null -eq $case.Amount) {
            Assert-True ($null -eq $action.Amount)
        } else {
            Assert-Equal $case.Amount $action.Amount
        }
    }
}

Run-TestCase "Numbered commands resolve against current legal actions" {
    Assert-True ([bool](Get-Command ConvertFrom-NumberedPlayerAction -ErrorAction SilentlyContinue)) "ConvertFrom-NumberedPlayerAction should exist."

    $legalActions = @(
        [pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null },
        [pscustomobject]@{ Command = 'call'; MinAmount = $null; MaxAmount = $null },
        [pscustomobject]@{ Command = 'raise'; MinAmount = 40; MaxAmount = 1000 },
        [pscustomobject]@{ Command = 'allin'; MinAmount = $null; MaxAmount = $null }
    )

    $call = ConvertFrom-NumberedPlayerAction -InputText '2' -LegalActions $legalActions
    Assert-Equal 'call' $call.Command
    Assert-True ($null -eq $call.Amount)

    $minimumRaise = ConvertFrom-NumberedPlayerAction -InputText '3' -LegalActions $legalActions
    Assert-Equal 'raise' $minimumRaise.Command
    Assert-Equal 40 $minimumRaise.Amount

    $customRaise = ConvertFrom-NumberedPlayerAction -InputText '3 200' -LegalActions $legalActions
    Assert-Equal 'raise' $customRaise.Command
    Assert-Equal 200 $customRaise.Amount
}
