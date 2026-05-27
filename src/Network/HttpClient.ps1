function New-PokerHttpClientState {
    param(
        [Parameter(Mandatory = $false)][string]$Name = 'Player',
        [Parameter(Mandatory = $false)][string]$HostAddress = '127.0.0.1',
        [Parameter(Mandatory = $false)][int]$Port = 7777
    )

    [pscustomobject]@{
        Name = $Name
        HostAddress = $HostAddress
        Port = $Port
        PlayerId = $null
        Seat = $null
        Token = $null
        NextSeq = 1
        LastSnapshotFingerprint = $null
        IsFinished = $false
    }
}

function Get-PokerHttpBaseUrl {
    param([Parameter(Mandatory = $true)]$Client)

    return "http://$($Client.HostAddress):$($Client.Port)"
}

function Invoke-PokerHttpRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $false)]$Body = $null
    )

    $request = [System.Net.WebRequest]::Create($Uri)
    $request.Method = $Method.ToUpperInvariant()
    $request.Timeout = 5000
    $request.ContentType = 'application/json; charset=utf-8'

    if ($null -ne $Body) {
        $json = ($Body | ConvertTo-Json -Compress -Depth 20)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try {
            $stream.Write($bytes, 0, $bytes.Length)
        } finally {
            $stream.Close()
        }
    }

    $response = $request.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
    } finally {
        $response.Close()
    }

    return ConvertFrom-MessageJson -Json $text
}

function Join-PokerHttpHost {
    param([Parameter(Mandatory = $true)]$Client)

    $response = Invoke-PokerHttpRequest -Method 'POST' -Uri "$(Get-PokerHttpBaseUrl -Client $Client)/join" -Body ([pscustomobject]@{
        Name = [string]$Client.Name
    })

    if ([string]$response.Type -ne 'JoinAccepted') {
        throw "Join failed: $($response.Payload.Message)"
    }

    $Client.PlayerId = [string]$response.Payload.PlayerId
    $Client.Seat = [int]$response.Payload.Seat
    $Client.Token = [string]$response.Payload.Token
    if (-not [string]::IsNullOrWhiteSpace([string]$response.Payload.Name)) {
        $Client.Name = [string]$response.Payload.Name
    }

    Write-Host "Join accepted: $($Client.PlayerId), seat $($Client.Seat)."
    return $response
}

function Get-PokerHttpState {
    param([Parameter(Mandatory = $true)]$Client)

    $playerId = [System.Uri]::EscapeDataString([string]$Client.PlayerId)
    $token = [System.Uri]::EscapeDataString([string]$Client.Token)
    return Invoke-PokerHttpRequest -Method 'GET' -Uri "$(Get-PokerHttpBaseUrl -Client $Client)/state?playerId=$playerId&token=$token"
}

function Send-PokerHttpAction {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$ActionMessage
    )

    $payload = [pscustomobject]@{
        PlayerId = [string]$Client.PlayerId
        Token = [string]$Client.Token
        Command = [string]$ActionMessage.Payload.Command
    }
    if (Test-ProtocolPropertyExists -Object $ActionMessage.Payload -Name 'Amount') {
        $payload | Add-Member -NotePropertyName Amount -NotePropertyValue ([int]$ActionMessage.Payload.Amount)
    }

    return Invoke-PokerHttpRequest -Method 'POST' -Uri "$(Get-PokerHttpBaseUrl -Client $Client)/action" -Body $payload
}

function Leave-PokerHttpHost {
    param([Parameter(Mandatory = $true)]$Client)

    if ([string]::IsNullOrWhiteSpace([string]$Client.PlayerId) -or [string]::IsNullOrWhiteSpace([string]$Client.Token)) {
        return
    }

    try {
        Invoke-PokerHttpRequest -Method 'POST' -Uri "$(Get-PokerHttpBaseUrl -Client $Client)/leave" -Body ([pscustomobject]@{
            PlayerId = [string]$Client.PlayerId
            Token = [string]$Client.Token
        }) | Out-Null
    } catch {
    }
}

function Get-PokerHttpSnapshotFingerprint {
    param([Parameter(Mandatory = $true)]$Snapshot)

    return ($Snapshot.Payload | ConvertTo-Json -Compress -Depth 12)
}

function Test-PokerHttpClientTurn {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    $payload = $Snapshot.Payload
    $isPaused = ($payload.PSObject.Properties.Name -contains 'IsPaused') -and [bool]$payload.IsPaused
    $legalActions = if ($payload.PSObject.Properties.Name -contains 'LegalActions') {
        @($payload.LegalActions)
    } else {
        @()
    }

    return [string]$Snapshot.Type -eq 'StateSnapshot' -and
        -not $isPaused -and
        $legalActions.Count -gt 0 -and
        [string]$payload.Street -ne 'Finished' -and
        $null -ne $payload.ActionSeat -and
        [int]$payload.ActionSeat -eq [int]$Client.Seat
}

function New-PokerHttpActionRequest {
    param(
        [Parameter(Mandatory = $true)]$Client,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    return New-ProtocolMessage -Type 'ActionRequest' -Seq ([int]$Snapshot.Seq) -PlayerId ([string]$Client.PlayerId) -HandId ([int]$Snapshot.HandId) -Payload ([pscustomobject]@{
        HandId = [int]$Snapshot.Payload.HandId
        Seat = [int]$Client.Seat
        ActionSeat = $Snapshot.Payload.ActionSeat
        ToCall = 0
        LegalActions = @($Snapshot.Payload.LegalActions)
    })
}

function Start-PokerHttpClient {
    param(
        [Parameter(Mandatory = $false)][string]$HostAddress = '127.0.0.1',
        [Parameter(Mandatory = $false)][int]$Port = 7777,
        [Parameter(Mandatory = $false)][string]$Name = 'Player',
        [Parameter(Mandatory = $false)][int]$PollMilliseconds = 300,
        [Parameter(Mandatory = $false)][scriptblock]$ActionProvider
    )

    $client = New-PokerHttpClientState -Name $Name -HostAddress $HostAddress -Port $Port
    Join-PokerHttpHost -Client $client | Out-Null

    try {
        while ($true) {
            $snapshot = Get-PokerHttpState -Client $client
            if ([string]$snapshot.Type -eq 'ErrorMessage') {
                Write-Host "Error: $($snapshot.Payload.Message)"
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }

            $fingerprint = Get-PokerHttpSnapshotFingerprint -Snapshot $snapshot
            if ($fingerprint -ne $client.LastSnapshotFingerprint) {
                Show-StateSnapshot -Snapshot $snapshot
                $client.LastSnapshotFingerprint = $fingerprint
            }

            if (Test-PokerHttpClientTurn -Client $client -Snapshot $snapshot) {
                $actionRequest = New-PokerHttpActionRequest -Client $client -Snapshot $snapshot
                try {
                    $action = Read-ClientActionInput -Client $client -ActionRequest $actionRequest -ActionProvider $ActionProvider
                    $result = Send-PokerHttpAction -Client $client -ActionMessage $action
                    if ([string]$result.Type -eq 'ErrorMessage') {
                        Write-Host "Error: $($result.Payload.Message)"
                    }
                } catch {
                    if ($_.Exception.Message -eq 'Player quit.') {
                        Leave-PokerHttpHost -Client $client
                        break
                    }
                    throw
                }
            } else {
                Start-Sleep -Milliseconds $PollMilliseconds
            }
        }
    } finally {
        Leave-PokerHttpHost -Client $client
    }

    return $client
}
