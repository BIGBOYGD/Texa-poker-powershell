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

Run-TestCase "Render table uses compact terminal layout" {
    $youName = New-TestText @(0x4f60)
    $botNamePrefix = New-TestText @(0x673a, 0x5668, 0x4eba)
    $players = @(
        (New-PlayerState -Seat 1 -Name $youName -Type 'HumanLocal' -Chips 980),
        (New-PlayerState -Seat 2 -Name ($botNamePrefix + '2') -Type 'Bot' -Chips 980),
        (New-PlayerState -Seat 3 -Name ($botNamePrefix + '3') -Type 'Bot' -Chips 980),
        (New-PlayerState -Seat 4 -Name ($botNamePrefix + '4') -Type 'Bot' -Chips 980),
        (New-PlayerState -Seat 5 -Name ($botNamePrefix + '5') -Type 'Bot' -Chips 980),
        (New-PlayerState -Seat 6 -Name ($botNamePrefix + '6') -Type 'Bot' -Chips 980)
    )
    $players[1] | Add-Member -NotePropertyName BotType -NotePropertyValue 'RandomBot'
    $players[2] | Add-Member -NotePropertyName BotType -NotePropertyValue 'TightBot'
    $players[3] | Add-Member -NotePropertyName BotType -NotePropertyValue 'LooseBot'
    $players[4] | Add-Member -NotePropertyName BotType -NotePropertyValue 'RuleBot'
    $players[5] | Add-Member -NotePropertyName BotType -NotePropertyValue 'RandomBot'

    $game = New-GameState -Players $players -SmallBlind 10 -BigBlind 20
    $game.HandId = 1
    $game.Street = 'Flop'
    $game.DealerSeat = 1
    $game.ActionSeat = 1
    $game.CurrentBet = 0
    $players[0].HoleCards = @(
        [pscustomobject]@{ Rank = 4; Suit = 'C'; Text = '4c' },
        [pscustomobject]@{ Rank = 8; Suit = 'S'; Text = '8s' }
    )
    $game.CommunityCards = @(
        [pscustomobject]@{ Rank = 10; Suit = 'C'; Text = 'Tc' },
        [pscustomobject]@{ Rank = 4; Suit = 'S'; Text = '4s' },
        [pscustomobject]@{ Rank = 7; Suit = 'D'; Text = '7d' }
    )
    $players[0].TotalBetThisHand = 20
    $players[1].TotalBetThisHand = 20
    $players[2].TotalBetThisHand = 20
    $players[3].TotalBetThisHand = 20
    $players[4].TotalBetThisHand = 20
    $players[5].TotalBetThisHand = 20

    $output = @(& { Render-Table -Game $game -ViewerSeat 1 } 6>&1 | ForEach-Object { [string]$_ })

    $first = New-TestText @(0x7b2c)
    $hand = New-TestText @(0x624b)
    $dealer = New-TestText @(0x5e84)
    $flop = New-TestText @(0x7ffb, 0x724c)
    $blind = New-TestText @(0x76f2)
    $pot = New-TestText @(0x6c60)
    $bet = New-TestText @(0x6ce8)
    $seat = New-TestText @(0x5ea7)
    $playersLabel = New-TestText @(0x73a9, 0x5bb6)
    $kindLabel = New-TestText @(0x578b)
    $chips = New-TestText @(0x7b79, 0x7801)
    $status = New-TestText @(0x72b6, 0x6001)
    $bot = New-TestText @(0x673a, 0x5668, 0x4eba)
    $random = New-TestText @(0x968f, 0x673a)
    $tight = New-TestText @(0x7d27, 0x624b)
    $loose = New-TestText @(0x677e, 0x624b)
    $rule = New-TestText @(0x89c4, 0x5219)
    $waiting = New-TestText @(0x7b49, 0x5f85)
    $public = New-TestText @(0x516c, 0x5171)
    $club = New-TestText @(0x6885, 0x82b1)
    $spade = New-TestText @(0x9ed1, 0x6843)
    $diamond = New-TestText @(0x65b9, 0x5757)
    $holeCards = New-TestText @(0x624b, 0x724c)
    $best = New-TestText @(0x6700, 0x5927)
    $pair = New-TestText @(0x4e00, 0x5bf9)
    $prediction = New-TestText @(0x9884, 0x6d4b)
    $toCall = New-TestText @(0x9700, 0x8ddf)
    $command = New-TestText @(0x547d, 0x4ee4)
    $check = New-TestText @(0x8fc7, 0x724c)
    $fold = New-TestText @(0x5f03, 0x724c)

    $headerLine = '{0}1{1} | {2}1 | {3} | {4}10/20 | {5}120 | {6}0' -f $first, $hand, $dealer, $flop, $blind, $pot, $bet
    $tableHeader = '{0}  {1}      {2}    {3}  {4}  {5}' -f $seat, $playersLabel, $kindLabel, $chips, $bet, $status
    Assert-True ($output -contains $headerLine)
    Assert-True (-not ($output[0] -like "$(New-TestText @(0x5fb7, 0x5dde, 0x6251, 0x514b))*"))
    Assert-True ($output -contains $tableHeader)
    Assert-True (@($output | Where-Object { $_ -like ('2*' + $bot + '2*' + $random + '*980*0*' + $waiting) }).Count -eq 1)
    Assert-True (@($output | Where-Object { $_ -like ('3*' + $bot + '3*' + $tight + '*980*0*' + $waiting) }).Count -eq 1)
    Assert-True (@($output | Where-Object { $_ -like ('4*' + $bot + '4*' + $loose + '*980*0*' + $waiting) }).Count -eq 1)
    Assert-True (@($output | Where-Object { $_ -like ('5*' + $bot + '5*' + $rule + '*980*0*' + $waiting) }).Count -eq 1)

    $publicLine = '{0}: [{1}10] [{2}4] [{3}7] [??] [??]' -f $public, $club, $spade, $diamond
    $handLine = '{0}: [{1}4] [{2}8]    {3}: {4} 4' -f $holeCards, $club, $spade, $best, $pair
    $publicIndex = [Array]::IndexOf($output, $publicLine)
    $handIndex = [Array]::IndexOf($output, $handLine)
    Assert-True ($publicIndex -ge 0)
    Assert-True ($handIndex -gt $publicIndex)
    Assert-True (@($output | Where-Object { $_ -like ($prediction + ': 1.*  2.*  3.*') }).Count -eq 1)
    Assert-True ($output -contains ('{0}: 0' -f $toCall))
    Assert-True (@($output | Where-Object { $_ -like ($command + ': 1.' + $check + '*') -or $_ -like ($command + ': 1.' + $fold + '*') }).Count -eq 1)
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
    Assert-Equal "$raise`40-1000" (ConvertTo-DisplayAction -Action ([pscustomobject]@{ Command = 'raise'; MinAmount = 40; MaxAmount = 1000 }))
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

    Assert-Equal "1.$fold  2.$call  3.$raise`40-1000  4.$allin" (Format-NumberedLegalActions -Actions $actions)
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

    Assert-Equal 2 $lines.Count
    Assert-True ($lines[0].StartsWith((New-TestText @(0x6700, 0x5927))))
    Assert-True ($lines[1].StartsWith((New-TestText @(0x9884, 0x6d4b))))
    Assert-True ($lines[1] -match '^.+: 1\. ')
    Assert-True ($lines[1] -match '  2\. ')
    Assert-True ($lines[1] -match '  3\. ')
}
