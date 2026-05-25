$script:TestFailures = New-Object System.Collections.Generic.List[string]

function Run-TestCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    try {
        & $Body
        Write-Host "[PASS] $Name"
    } catch {
        $message = $_.Exception.Message
        $script:TestFailures.Add("$Name`: $message") | Out-Null
        Write-Host "[FAIL] $Name"
        Write-Host "       $message"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $false)][string]$Message = "Expected condition to be true."
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-False {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $false)][string]$Message = "Expected condition to be false."
    )

    if ($Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $false)][string]$Message = ""
    )

    if ($Expected -ne $Actual) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = "Expected '$Expected', got '$Actual'."
        }
        throw $Message
    }
}

function Assert-SequenceEqual {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $false)][string]$Message = ""
    )

    $expectedArray = @($Expected)
    $actualArray = @($Actual)

    if ($expectedArray.Count -ne $actualArray.Count) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = "Expected sequence length $($expectedArray.Count), got $($actualArray.Count)."
        }
        throw $Message
    }

    for ($i = 0; $i -lt $expectedArray.Count; $i++) {
        if ($expectedArray[$i] -ne $actualArray[$i]) {
            if ([string]::IsNullOrWhiteSpace($Message)) {
                $Message = "Expected sequence item $i to be '$($expectedArray[$i])', got '$($actualArray[$i])'."
            }
            throw $Message
        }
    }
}

function Get-TestFailureCount {
    return $script:TestFailures.Count
}
