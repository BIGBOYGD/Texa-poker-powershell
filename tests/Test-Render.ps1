. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\Deck.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\HandEvaluator.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"

$advisorPath = "$PSScriptRoot\..\src\Core\HandAdvisor.ps1"
if (Test-Path -LiteralPath $advisorPath) {
    . $advisorPath
}

. "$PSScriptRoot\..\src\UI\Render.ps1"

function New-TestText {
    param([Parameter(Mandatory = $true)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

Run-TestCase "Render table accepts an empty board" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'PreFlop'
    $game.DealerSeat = 1
    $game.ActionSeat = 1
    $game.CurrentBet = 20
    $game.CommunityCards = @()

    Render-Table -Game $game -ViewerSeat 1
}

Run-TestCase "Render helpers translate street actions and cards to Chinese display text" {
    $diamond = New-TestText @(0x65b9, 0x5757)
    $heart = New-TestText @(0x7ea2, 0x6843)
    $preflop = New-TestText @(0x7ffb, 0x724c, 0x524d)
    $fold = New-TestText @(0x5f03, 0x724c)
    $raise = New-TestText @(0x52a0, 0x6ce8)

    $cards = @(
        [pscustomobject]@{ Rank = 11; Suit = 'D'; Text = 'Jd' },
        [pscustomobject]@{ Rank = 10; Suit = 'H'; Text = 'Th' }
    )

    Assert-Equal $preflop (ConvertTo-DisplayStreet -Street 'PreFlop')
    Assert-Equal "[$diamond`J] [$heart`10]" (Format-CardList -Cards $cards)
    Assert-Equal $fold (ConvertTo-DisplayAction -Action ([pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null }))
    Assert-Equal "$raise 40-1000" (ConvertTo-DisplayAction -Action ([pscustomobject]@{ Command = 'raise'; MinAmount = 40; MaxAmount = 1000 }))
}

Run-TestCase "Legal actions are displayed as numbered commands" {
    Assert-True ([bool](Get-Command Format-NumberedLegalActions -ErrorAction SilentlyContinue)) "Format-NumberedLegalActions should exist."

    $fold = New-TestText @(0x5f03, 0x724c)
    $call = New-TestText @(0x8ddf, 0x6ce8)
    $raise = New-TestText @(0x52a0, 0x6ce8)
    $allin = New-TestText @(0x5168, 0x4e0b)
    $actions = @(
        [pscustomobject]@{ Command = 'fold'; MinAmount = $null; MaxAmount = $null },
        [pscustomobject]@{ Command = 'call'; MinAmount = $null; MaxAmount = $null },
        [pscustomobject]@{ Command = 'raise'; MinAmount = 40; MaxAmount = 1000 },
        [pscustomobject]@{ Command = 'allin'; MinAmount = $null; MaxAmount = $null }
    )

    Assert-Equal "1. $fold, 2. $call, 3. $raise 40-1000, 4. $allin" (Format-NumberedLegalActions -Actions $actions)
}

Run-TestCase "Revealed hands include every player's hole cards at hand end" {
    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Finished'
    $game.CommunityCards = @(
        [pscustomobject]@{ Rank = 14; Suit = 'H'; Text = 'Ah' },
        [pscustomobject]@{ Rank = 13; Suit = 'H'; Text = 'Kh' },
        [pscustomobject]@{ Rank = 12; Suit = 'H'; Text = 'Qh' },
        [pscustomobject]@{ Rank = 2; Suit = 'D'; Text = '2d' },
        [pscustomobject]@{ Rank = 3; Suit = 'C'; Text = '3c' }
    )
    $game.Players[0].HoleCards = @(
        [pscustomobject]@{ Rank = 11; Suit = 'H'; Text = 'Jh' },
        [pscustomobject]@{ Rank = 10; Suit = 'H'; Text = 'Th' }
    )
    $game.Players[1].HoleCards = @(
        [pscustomobject]@{ Rank = 14; Suit = 'S'; Text = 'As' },
        [pscustomobject]@{ Rank = 11; Suit = 'C'; Text = 'Jc' }
    )

    $lines = @(Get-RevealedHandsLines -Game $game)

    Assert-Equal 3 $lines.Count
    Assert-Equal "$(New-TestText @(0x6240, 0x6709, 0x73a9, 0x5bb6, 0x624b, 0x724c)):" $lines[0]
    Assert-Equal "$(New-TestText @(0x5ea7, 0x4f4d))1 A: [$(New-TestText @(0x7ea2, 0x6843))J] [$(New-TestText @(0x7ea2, 0x6843))10]  $(New-TestText @(0x6700, 0x5927, 0x724c, 0x578b)): $(New-TestText @(0x540c, 0x82b1, 0x987a)) A" $lines[1]
    Assert-Equal "$(New-TestText @(0x5ea7, 0x4f4d))2 B: [$(New-TestText @(0x9ed1, 0x6843))A] [$(New-TestText @(0x6885, 0x82b1))J]  $(New-TestText @(0x6700, 0x5927, 0x724c, 0x578b)): $(New-TestText @(0x4e00, 0x5bf9)) A" $lines[2]
}

Run-TestCase "Player advice lines show current hand and three Chinese predictions" {
    Assert-True ([bool](Get-Command Get-PlayerAdviceLines -ErrorAction SilentlyContinue)) "Get-PlayerAdviceLines should exist."

    $players = @(
        (New-PlayerState -Seat 1 -Name 'A' -Type 'HumanLocal' -Chips 1000),
        (New-PlayerState -Seat 2 -Name 'B' -Type 'Bot' -Chips 1000)
    )
    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.Street = 'Flop'
    $game.Players[0].HoleCards = @(
        [pscustomobject]@{ Rank = 14; Suit = 'S'; Text = 'As' },
        [pscustomobject]@{ Rank = 13; Suit = 'S'; Text = 'Ks' }
    )
    $game.CommunityCards = @(
        [pscustomobject]@{ Rank = 12; Suit = 'S'; Text = 'Qs' },
        [pscustomobject]@{ Rank = 11; Suit = 'S'; Text = 'Js' },
        [pscustomobject]@{ Rank = 2; Suit = 'D'; Text = '2d' }
    )

    $lines = @(Get-PlayerAdviceLines -Game $game -ViewerSeat 1)

    Assert-True ($lines.Count -ge 5)
    Assert-True ($lines[0].StartsWith((New-TestText @(0x5f53, 0x524d, 0x6700, 0x5927, 0x724c, 0x578b))))
    Assert-Equal "$(New-TestText @(0x9ad8, 0x6982, 0x7387, 0x6210, 0x724c, 0x9884, 0x6d4b)):" $lines[1]
    Assert-True ($lines[2] -match '^1\. ')
    Assert-True ($lines[3] -match '^2\. ')
    Assert-True ($lines[4] -match '^3\. ')
}
