. "$PSScriptRoot\..\src\Core\Card.ps1"
. "$PSScriptRoot\..\src\Core\GameState.ps1"
. "$PSScriptRoot\..\src\Core\Betting.ps1"
. "$PSScriptRoot\..\src\Network\Protocol.ps1"
. "$PSScriptRoot\..\src\Network\Server.ps1"
. "$PSScriptRoot\..\src\Network\Client.ps1"

Run-TestCase "JoinRequest can be constructed by client" {
    $join = New-JoinRequestMessage -Seq 7 -Name 'Alice'

    Assert-Equal 'JoinRequest' $join.Type
    Assert-Equal 7 $join.Seq
    Assert-Equal 'Alice' $join.Payload.Name
    Assert-Equal $true (Test-ProtocolMessage -Message $join).IsValid
}

Run-TestCase "JoinRequest with empty name is rejected" {
    $server = New-PokerServerState -MaxSeats 6
    $connection = New-PokerClientConnectionState -ConnectionId 'C1'
    $join = New-JoinRequestMessage -Seq 1 -Name ''

    $response = Handle-JoinRequest -Server $server -Connection $connection -Message $join

    Assert-Equal 'ErrorMessage' $response.Type
    Assert-True ($response.Payload.Message -match 'Name')
    Assert-Equal 0 @($server.Game.Players).Count
}

Run-TestCase "JoinAccepted assigns PlayerId and first available Seat" {
    $server = New-PokerServerState -MaxSeats 6
    $connection = New-PokerClientConnectionState -ConnectionId 'C1'
    $join = New-JoinRequestMessage -Seq 1 -Name 'Alice'

    $response = Handle-JoinRequest -Server $server -Connection $connection -Message $join

    Assert-Equal 'JoinAccepted' $response.Type
    Assert-Equal 'P1' $response.Payload.PlayerId
    Assert-Equal 1 ([int]$response.Payload.Seat)
    Assert-Equal 'Alice' $response.Payload.Name
    Assert-Equal 'P1' $connection.PlayerId
    Assert-Equal 1 ([int]$connection.Seat)
    Assert-Equal 1 @($server.Game.Players).Count
    Assert-Equal 'RemoteHuman' $server.Game.Players[0].Type
}

Run-TestCase "Server ignores client requested Seat and prevents duplicate seats" {
    $server = New-PokerServerState -MaxSeats 6
    $first = New-PokerClientConnectionState -ConnectionId 'C1'
    $second = New-PokerClientConnectionState -ConnectionId 'C2'

    $joinOne = New-ProtocolMessage -Type 'JoinRequest' -Seq 1 -Payload ([pscustomobject]@{ Name = 'Alice'; Seat = 6 })
    $joinTwo = New-ProtocolMessage -Type 'JoinRequest' -Seq 2 -Payload ([pscustomobject]@{ Name = 'Bob'; Seat = 1 })

    $firstResponse = Handle-JoinRequest -Server $server -Connection $first -Message $joinOne
    $secondResponse = Handle-JoinRequest -Server $server -Connection $second -Message $joinTwo

    Assert-Equal 'JoinAccepted' $firstResponse.Type
    Assert-Equal 1 ([int]$firstResponse.Payload.Seat)
    Assert-Equal 'JoinAccepted' $secondResponse.Type
    Assert-Equal 2 ([int]$secondResponse.Payload.Seat)
    Assert-SequenceEqual @(1, 2) @($server.Game.Players | Sort-Object Seat | ForEach-Object { [int]$_.Seat })
}

Run-TestCase "Full table returns ErrorMessage" {
    $server = New-PokerServerState -MaxSeats 2

    $response1 = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C1') -Message (New-JoinRequestMessage -Seq 1 -Name 'Alice')
    $response2 = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C2') -Message (New-JoinRequestMessage -Seq 2 -Name 'Bob')
    $response3 = Handle-JoinRequest -Server $server -Connection (New-PokerClientConnectionState -ConnectionId 'C3') -Message (New-JoinRequestMessage -Seq 3 -Name 'Carol')

    Assert-Equal 'JoinAccepted' $response1.Type
    Assert-Equal 'JoinAccepted' $response2.Type
    Assert-Equal 'ErrorMessage' $response3.Type
    Assert-True ($response3.Payload.Message -match 'full')
    Assert-Equal 2 @($server.Game.Players).Count
}

Run-TestCase "Client can parse JoinAccepted and store session identity" {
    $client = New-PokerClientState -Name 'Alice'
    $message = New-ProtocolMessage -Type 'JoinAccepted' -Seq 1 -PlayerId 'P1' -Payload ([pscustomobject]@{
        PlayerId = 'P1'
        Seat = 1
        Name = 'Alice'
    })

    Handle-ServerMessage -Client $client -Message $message -Quiet

    Assert-Equal 'P1' $client.PlayerId
    Assert-Equal 1 ([int]$client.Seat)
    Assert-Equal 'Alice' $client.Name
}

Run-TestCase "Client can parse StateSnapshot without creating GameState" {
    $client = New-PokerClientState -Name 'Alice'
    $snapshot = New-ProtocolMessage -Type 'StateSnapshot' -Seq 2 -PlayerId 'P1' -HandId 0 -Payload ([pscustomobject]@{
        HandId = 0
        Street = 'Finished'
        Pot = 0
        CurrentBet = 0
        ActionSeat = $null
        CommunityCards = @()
        YourHoleCards = @()
        Players = @()
        LegalActions = @()
    })

    Handle-ServerMessage -Client $client -Message $snapshot -Quiet

    Assert-Equal 'StateSnapshot' $client.LastMessageType
    Assert-Equal 0 ([int]$client.LastSnapshot.HandId)
    Assert-False ($client.PSObject.Properties.Name -contains 'Game')
}
