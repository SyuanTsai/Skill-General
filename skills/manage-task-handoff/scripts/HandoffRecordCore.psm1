# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

function Get-HandoffField {
    param($Value, [string]$Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) { return ,$Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return ,$property.Value
}

function New-HandoffRecordResponse {
    param([string]$Status, [string]$Reason, $Record, [object[]]$Events, [string]$CallerOutcome)
    return [pscustomobject]@{
        Status = $Status
        Reason = $Reason
        Record = $Record
        Events = @($Events)
        CallerOutcome = $CallerOutcome
        ExternalCalls = 0
        Durable = $false
    }
}

function Test-HandoffSensitiveField {
    param($Value, [int]$Depth = 0)
    if ($null -eq $Value -or $Depth -gt 16 -or $Value -is [string] -or $Value -is [ValueType]) { return $false }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
        foreach ($item in $Value) { if (Test-HandoffSensitiveField $item ($Depth + 1)) { return $true } }
        return $false
    }
    $names = if ($Value -is [System.Collections.IDictionary]) { @($Value.Keys) } else { @($Value.PSObject.Properties.Name) }
    foreach ($name in $names) {
        $normalized = ([string]$name -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
        if ($normalized -match '(secret|password|credential|token|authorization|verificationcode|privatekey|apikey)') { return $true }
        if (Test-HandoffSensitiveField (Get-HandoffField $Value ([string]$name)) ($Depth + 1)) { return $true }
    }
    return $false
}

function Test-HandoffIdentity {
    param($Value, [bool]$RequireBranch)
    foreach ($field in @('Authority Scope', 'Task Key')) {
        $part = $null
        if ($Value -is [System.Collections.IDictionary]) { $part = $Value[$field] }
        else { $part = $Value.PSObject.Properties[$field].Value }
        if ($part -isnot [string] -or [string]::IsNullOrWhiteSpace($part)) { return $false }
    }
    $branch = $null
    if ($Value -is [System.Collections.IDictionary]) { $branch = $Value['Branch ID'] }
    else { $branch = $Value.PSObject.Properties['Branch ID'].Value }
    if ($RequireBranch) { return ($branch -is [string] -and -not [string]::IsNullOrWhiteSpace($branch)) }
    return ($null -eq $branch)
}

function Test-HandoffPlainData {
    param($Value, [int]$Depth = 0)
    if ($Depth -gt 16) { return $false }
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $true }
    if ($Value -is [array]) {
        foreach ($item in $Value) { if (-not (Test-HandoffPlainData $item ($Depth + 1))) { return $false } }
        return $true
    }
    if ($Value.GetType() -eq [hashtable] -or $Value.GetType() -eq [System.Collections.Specialized.OrderedDictionary]) {
        foreach ($key in $Value.Keys) {
            if ($key -isnot [string] -or -not (Test-HandoffPlainData $Value[$key] ($Depth + 1))) { return $false }
        }
        return $true
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.MemberType -ne 'NoteProperty') { return $false }
            if (-not (Test-HandoffPlainData $property.Value ($Depth + 1))) { return $false }
        }
        return $true
    }
    return $false
}

function Get-HandoffMapEntries {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            [pscustomobject]@{ Name = [string]$key; Data = $Value[$key] }
        }
    } else {
        foreach ($property in $Value.PSObject.Properties) {
            [pscustomobject]@{ Name = [string]$property.Name; Data = $property.Value }
        }
    }
}

function Test-HandoffSamePlainData {
    param($Left, $Right, [int]$Depth = 0)
    if ($Depth -gt 16) { return $false }
    if ($null -eq $Left -or $null -eq $Right) { return ($null -eq $Left -and $null -eq $Right) }
    if ($Left -is [array]) {
        if ($Right -isnot [array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($index = 0; $index -lt $Left.Count; $index++) {
            if (-not (Test-HandoffSamePlainData $Left[$index] $Right[$index] ($Depth + 1))) { return $false }
        }
        return $true
    }
    if ($Right -is [array]) { return $false }
    $leftIsMap = $Left -is [System.Collections.IDictionary] -or $Left -is [pscustomobject]
    $rightIsMap = $Right -is [System.Collections.IDictionary] -or $Right -is [pscustomobject]
    if ($leftIsMap -or $rightIsMap) {
        if (-not $leftIsMap -or -not $rightIsMap) { return $false }
        $leftEntries = @(Get-HandoffMapEntries $Left)
        $rightEntries = @(Get-HandoffMapEntries $Right)
        if ($leftEntries.Count -ne $rightEntries.Count) { return $false }
        foreach ($entry in $leftEntries) {
            $matches = @($rightEntries | Where-Object { [string]::Equals($_.Name, $entry.Name, [StringComparison]::Ordinal) })
            if ($matches.Count -ne 1 -or
                -not (Test-HandoffSamePlainData $entry.Data $matches[0].Data ($Depth + 1))) { return $false }
        }
        return $true
    }
    if (($Left -isnot [string] -and $Left -isnot [ValueType]) -or
        ($Right -isnot [string] -and $Right -isnot [ValueType])) { return $false }
    # Preserve the previous JSON value semantics for supported scalar data.
    return (ConvertTo-Json -InputObject $Left -Depth 20 -Compress) -ceq
        (ConvertTo-Json -InputObject $Right -Depth 20 -Compress)
}

function Invoke-HandoffRecordCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Common', 'Branch')][string]$Kind,
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$OperationId,
        [object[]]$ExistingRecords = @(),
        [string]$ExpectedRevision,
        $ParentRecord,
        $CallerResult
    )

    $empty = @()
    if (-not (Test-HandoffPlainData $Record) -or
        -not (Test-HandoffPlainData $ExistingRecords) -or
        -not (Test-HandoffPlainData $ParentRecord) -or
        -not (Test-HandoffPlainData $CallerResult)) {
        return New-HandoffRecordResponse 'Rejected' 'invalid-input-shape' $null $empty $null
    }
    $required = if ($Kind -eq 'Common') {
        @('Authority Scope', 'Task Key', 'Intent', 'Scope', 'Current', 'Source', 'Lifecycle', 'Work State')
    } else {
        @('Authority Scope', 'Task Key', 'Branch ID', 'Fork Point', 'Continuation Generation', 'Current', 'Source', 'Lifecycle', 'Work State')
    }
    if ([string]::IsNullOrWhiteSpace($OperationId)) {
        return New-HandoffRecordResponse 'Rejected' 'missing-operation-id' $null $empty $null
    }
    foreach ($field in $required) {
        $value = Get-HandoffField $Record $field
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            return New-HandoffRecordResponse 'Rejected' 'missing-required-field' $null $empty $null
        }
    }
    if ((Test-HandoffSensitiveField $Record) -or
        (Test-HandoffSensitiveField $ExistingRecords) -or
        (Test-HandoffSensitiveField $ParentRecord) -or
        (Test-HandoffSensitiveField $CallerResult)) {
        return New-HandoffRecordResponse 'Rejected' 'sensitive-field' $null $empty $null
    }
    if (-not (Test-HandoffIdentity $Record ($Kind -eq 'Branch')) -or
        ($null -ne $ParentRecord -and -not (Test-HandoffIdentity $ParentRecord $false))) {
        return New-HandoffRecordResponse 'Rejected' 'invalid-identity' $null $empty $null
    }
    foreach ($existing in $ExistingRecords) {
        $existingBranch = $null
        if ($existing -is [System.Collections.IDictionary]) { $existingBranch = $existing['Branch ID'] }
        else { $existingBranch = $existing.PSObject.Properties['Branch ID'].Value }
        if ($null -ne $existingBranch -and $existingBranch -isnot [string]) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-identity' $null $empty $null
        }
        if (-not (Test-HandoffIdentity $existing (-not [string]::IsNullOrWhiteSpace($existingBranch)))) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-identity' $null $empty $null
        }
    }
    if ($Kind -eq 'Common') {
        foreach ($field in @('Fork Point', 'Continuation Generation', 'Candidate Conclusion', 'Applicability Scope', 'Branch Outcome')) {
            if ($null -ne (Get-HandoffField $Record $field)) {
                return New-HandoffRecordResponse 'Rejected' 'invalid-record-kind' $null $empty $null
            }
        }
        $conflict = Get-HandoffField $Record 'Conflict'
        if ($null -ne $conflict -and ($conflict -isnot [string] -or $conflict -cne 'Conflict')) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-state' $null $empty $null
        }
    } else {
        foreach ($field in @('Intent', 'Scope', 'Active Branches', 'Fork Baselines', 'Integrated Decisions', 'Decision Branch Bindings', 'Conflict')) {
            if ($null -ne (Get-HandoffField $Record $field)) {
                return New-HandoffRecordResponse 'Rejected' 'invalid-record-kind' $null $empty $null
            }
        }
        $outcome = Get-HandoffField $Record 'Branch Outcome'
        if ($null -ne $outcome -and ($outcome -isnot [string] -or $outcome -cnotin @('Selected', 'Partially Selected', 'Superseded'))) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-state' $null $empty $null
        }
    }
    $lifecycle = Get-HandoffField $Record 'Lifecycle'
    $workState = Get-HandoffField $Record 'Work State'
    if ($lifecycle -isnot [string] -or $lifecycle -cnotin @('Active', 'Archived') -or
        $workState -isnot [string] -or $workState -cnotin @('Running', 'Awaiting Review', 'Interrupted', 'Blocked', 'Failed')) {
        return New-HandoffRecordResponse 'Rejected' 'invalid-state' $null $empty $null
    }
    if ($Kind -eq 'Common' -and $lifecycle -ceq 'Archived') {
        $activeBranchIndex = Get-HandoffField $Record 'Active Branches'
        if ($null -ne $activeBranchIndex -and $activeBranchIndex.Count -gt 0) {
            return New-HandoffRecordResponse 'Rejected' 'active-branch-protects-common' $null $empty $null
        }
        foreach ($existing in $ExistingRecords) {
            $existingBranch = Get-HandoffField $existing 'Branch ID'
            if ($existingBranch -is [string] -and -not [string]::IsNullOrWhiteSpace($existingBranch) -and
                (Get-HandoffField $existing 'Authority Scope') -ceq (Get-HandoffField $Record 'Authority Scope') -and
                (Get-HandoffField $existing 'Task Key') -ceq (Get-HandoffField $Record 'Task Key') -and
                (Get-HandoffField $existing 'Lifecycle') -cne 'Archived') {
                return New-HandoffRecordResponse 'Rejected' 'active-branch-protects-common' $null $empty $null
            }
        }
    }
    if ($Kind -eq 'Branch') {
        $generation = Get-HandoffField $Record 'Continuation Generation'
        if ($generation -isnot [int] -and $generation -isnot [long]) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-generation' $null $empty $null
        }
        if ($generation -lt 0) { return New-HandoffRecordResponse 'Rejected' 'invalid-generation' $null $empty $null }
    }

    $scope = [string](Get-HandoffField $Record 'Authority Scope')
    $task = [string](Get-HandoffField $Record 'Task Key')
    $branch = if ($Kind -eq 'Branch') { [string](Get-HandoffField $Record 'Branch ID') } else { $null }
    if ($Kind -eq 'Common' -and -not [string]::IsNullOrWhiteSpace([string](Get-HandoffField $Record 'Branch ID'))) {
        return New-HandoffRecordResponse 'Rejected' 'invalid-association' $null $empty $null
    }
    if ($Kind -eq 'Branch' -and $null -ne $ParentRecord -and (
        [string](Get-HandoffField $ParentRecord 'Authority Scope') -cne $scope -or
        [string](Get-HandoffField $ParentRecord 'Task Key') -cne $task -or
        -not [string]::IsNullOrWhiteSpace([string](Get-HandoffField $ParentRecord 'Branch ID')))) {
        return New-HandoffRecordResponse 'Rejected' 'invalid-association' $null $empty $null
    }
    $matching = @($ExistingRecords | Where-Object {
        [string](Get-HandoffField $_ 'Authority Scope') -ceq $scope -and
        [string](Get-HandoffField $_ 'Task Key') -ceq $task -and
        (($Kind -eq 'Common' -and [string]::IsNullOrWhiteSpace([string](Get-HandoffField $_ 'Branch ID'))) -or
         ($Kind -eq 'Branch' -and [string](Get-HandoffField $_ 'Branch ID') -ceq $branch))
    })
    if ($matching.Count -gt 1) {
        return New-HandoffRecordResponse 'Rejected' 'duplicate-identity' $null $empty $null
    }
    $previous = if ($matching.Count -eq 1) { $matching[0] } else { $null }
    if ($null -ne $previous) {
        $revision = [string](Get-HandoffField $previous 'Revision')
        if ([string]::IsNullOrWhiteSpace($ExpectedRevision) -or $ExpectedRevision -cne $revision) {
            return New-HandoffRecordResponse 'Rejected' 'revision-conflict' $null $empty $null
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($ExpectedRevision)) {
        return New-HandoffRecordResponse 'Rejected' 'revision-conflict' $null $empty $null
    }
    if ($Kind -eq 'Branch' -and $null -ne $previous) {
        $previousForkPoint = Get-HandoffField $previous 'Fork Point'
        $previousGeneration = Get-HandoffField $previous 'Continuation Generation'
        if ($previousForkPoint -isnot [string] -or [string]::IsNullOrWhiteSpace($previousForkPoint) -or
            ($previousGeneration -isnot [int] -and $previousGeneration -isnot [long])) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-existing-branch' $null $empty $null
        }
        if ([string](Get-HandoffField $Record 'Fork Point') -cne $previousForkPoint) {
            return New-HandoffRecordResponse 'Rejected' 'fork-point-conflict' $null $empty $null
        }
        $nextGeneration = Get-HandoffField $Record 'Continuation Generation'
        if ($nextGeneration -lt $previousGeneration -or
            $nextGeneration -gt ([decimal]$previousGeneration + 1)) {
            return New-HandoffRecordResponse 'Rejected' 'generation-conflict' $null $empty $null
        }
        if ((Get-HandoffField $previous 'Lifecycle') -ceq 'Archived' -and
            (($lifecycle -ceq 'Active' -and $nextGeneration -ne ([decimal]$previousGeneration + 1)) -or
             ($lifecycle -ceq 'Archived' -and $nextGeneration -ne $previousGeneration))) {
            return New-HandoffRecordResponse 'Rejected' 'restore-generation-conflict' $null $empty $null
        }
    }

    $callerOutcome = $null
    if ($null -ne $CallerResult) {
        $callerOutcome = Get-HandoffField $CallerResult 'Status'
        if ($callerOutcome -isnot [string] -or $callerOutcome -cnotin @('denied', 'partial', 'unknown', 'readback-mismatch', 'readback-matched')) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-caller-result' $null $empty $null
        }
    }

    $mutable = if ($Kind -eq 'Common') {
        @('Intent', 'Scope', 'Current', 'Source', 'Lifecycle', 'Work State', 'Active Branches', 'Fork Baselines', 'Integrated Decisions', 'Decision Branch Bindings', 'Conflict', 'Keep Active Until', 'Last Activity At')
    } else {
        @('Continuation Generation', 'Current', 'Source', 'Lifecycle', 'Work State', 'Candidate Conclusion', 'Applicability Scope', 'Branch Outcome', 'Keep Active Until', 'Last Activity At')
    }
    $events = @(
        foreach ($field in $mutable) {
            $old = Get-HandoffField $previous $field
            $new = Get-HandoffField $Record $field
            if ($null -eq $old -and $null -eq $new) { continue }
            if (-not (Test-HandoffSamePlainData $old $new)) {
                [pscustomobject]@{
                    'Authority Scope' = $scope
                    'Task Key' = $task
                    'Branch ID' = $branch
                    'Operation ID' = $OperationId
                    Field = $field
                    'Previous State' = $old
                    'New State' = $new
                    Status = 'proposed'
                }
            }
        }
    )
    if ($null -ne $previous -and @($events | Where-Object { $_.Field -ceq 'Last Activity At' }).Count -gt 0) {
        $materialFields = if ($Kind -eq 'Common') {
            @('Intent', 'Scope', 'Current', 'Source', 'Work State', 'Integrated Decisions',
              'Decision Branch Bindings', 'Conflict', 'Keep Active Until')
        } else {
            @('Continuation Generation', 'Current', 'Source', 'Work State',
              'Candidate Conclusion', 'Applicability Scope', 'Branch Outcome', 'Keep Active Until')
        }
        $materialChange = @($events | Where-Object { $materialFields -ccontains $_.Field }).Count -gt 0
        $activeBranchActivity = $false
        if (-not $materialChange -and $Kind -eq 'Common') {
            $activity = Get-HandoffField $Record 'Last Activity At'
            $activeBranches = Get-HandoffField $Record 'Active Branches'
            if ($activity -is [string] -and -not [string]::IsNullOrWhiteSpace($activity)) {
                foreach ($existing in $ExistingRecords) {
                    $existingBranch = Get-HandoffField $existing 'Branch ID'
                    if ($existingBranch -is [string] -and $activeBranches -ccontains $existingBranch -and
                        (Get-HandoffField $existing 'Authority Scope') -ceq $scope -and
                        (Get-HandoffField $existing 'Task Key') -ceq $task -and
                        (Get-HandoffField $existing 'Lifecycle') -ceq 'Active' -and
                        (Get-HandoffField $existing 'Last Activity At') -ceq $activity) {
                        $activeBranchActivity = $true
                        break
                    }
                }
            }
        }
        # The core can represent a restore, but only the caller or selected adapter
        # can establish explicit user intent and authorize a durable state change.
        $commonRestoreProposal = $Kind -eq 'Common' -and
            (Get-HandoffField $previous 'Lifecycle') -ceq 'Archived' -and $lifecycle -ceq 'Active' -and
            @($events | Where-Object { $_.Field -ceq 'Lifecycle' }).Count -eq 1
        if (-not $materialChange -and -not $activeBranchActivity -and -not $commonRestoreProposal) {
            return New-HandoffRecordResponse 'Rejected' 'activity-refresh-without-material-change' $null $empty $null
        }
    }
    return New-HandoffRecordResponse 'Accepted' $null $Record $events $callerOutcome
}

Export-ModuleMember -Function Invoke-HandoffRecordCore
