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
    param([string]$Status, [string]$Reason, $Record, [object[]]$Events, [string]$CallerOutcome, $CallerResult)
    return [pscustomobject]@{
        Status = $Status
        Reason = $Reason
        Record = $Record
        Events = @($Events)
        CallerOutcome = $CallerOutcome
        CallerResult = $CallerResult
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

$script:HandoffOrderedHashtableType = 'System.Management.Automation.OrderedHashtable' -as [type]

function Test-HandoffPlainData {
    param($Value, [int]$Depth = 0)
    if ($Depth -gt 16) { return $false }
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $true }
    if ($Value -is [array]) {
        foreach ($item in $Value) { if (-not (Test-HandoffPlainData $item ($Depth + 1))) { return $false } }
        return $true
    }
    $valueType = $Value.GetType()
    if ($valueType -eq [hashtable] -or
        $valueType -eq [System.Collections.Specialized.OrderedDictionary] -or
        ($null -ne $script:HandoffOrderedHashtableType -and $valueType -eq $script:HandoffOrderedHashtableType)) {
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

function Test-HandoffCallerResult {
    param($Value, [string]$OperationId)
    $status = Get-HandoffField $Value 'Status'
    if ($status -isnot [string] -or $status -cnotin @('denied', 'unavailable', 'partial', 'unknown', 'readback-mismatch', 'readback-matched')) {
        return $false
    }
    $entries = @(Get-HandoffMapEntries $Value)
    # Preserve the original Status-only input. Any structured evidence uses v1.
    if ($entries.Count -eq 1 -and $entries[0].Name -ceq 'Status') { return $true }
    $fields = @('SchemaVersion', 'Operation', 'OperationId', 'Status', 'Capability', 'Identity', 'Permission',
        'AdapterVersion', 'Revision', 'Readback', 'ReadbackRevision', 'Retryable', 'PendingActions')
    if ($entries.Count -ne $fields.Count) { return $false }
    foreach ($field in $fields) {
        if (@($entries | Where-Object Name -ceq $field).Count -ne 1) { return $false }
    }
    $version = Get-HandoffField $Value 'SchemaVersion'
    if (($version -isnot [int] -and $version -isnot [long]) -or $version -ne 1) { return $false }
    $operation = Get-HandoffField $Value 'Operation'
    if ($operation -isnot [string] -or $operation -cnotin @('createIfAbsent', 'updateIfRevision', 'appendEventIfAbsent', 'lookup', 'readback', 'rollback', 'disable')) { return $false }
    $reportedOperation = Get-HandoffField $Value 'OperationId'
    if ($reportedOperation -isnot [string] -or $reportedOperation -cne $OperationId) { return $false }
    foreach ($field in @('AdapterVersion', 'Revision', 'ReadbackRevision')) {
        $part = Get-HandoffField $Value $field
        if ($null -ne $part -and ($part -isnot [string] -or [string]::IsNullOrWhiteSpace($part))) { return $false }
    }
    $capability = Get-HandoffField $Value 'Capability'
    $identity = Get-HandoffField $Value 'Identity'
    $permission = Get-HandoffField $Value 'Permission'
    $readback = Get-HandoffField $Value 'Readback'
    if ($capability -isnot [string] -or $capability -cnotin @('supported', 'unsupported', 'unavailable', 'unknown') -or
        $identity -isnot [string] -or $identity -cnotin @('verified', 'denied', 'unknown') -or
        $permission -isnot [string] -or $permission -cnotin @('authorized', 'denied', 'unknown') -or
        $readback -isnot [string] -or $readback -cnotin @('matched', 'mismatch', 'not-attempted', 'unknown')) { return $false }
    $retryable = Get-HandoffField $Value 'Retryable'
    $pending = Get-HandoffField $Value 'PendingActions'
    if ($retryable -isnot [bool] -or $pending -isnot [array]) { return $false }
    foreach ($action in $pending) {
        if ($action -isnot [string] -or [string]::IsNullOrWhiteSpace($action)) { return $false }
    }
    if ($status -cin @('partial', 'unknown', 'readback-mismatch') -and ($pending.Count -eq 0 -or -not $retryable)) { return $false }
    if ($status -ceq 'denied' -and $identity -cne 'denied' -and $permission -cne 'denied') { return $false }
    if ($status -ceq 'unavailable' -and $capability -cnotin @('unsupported', 'unavailable')) { return $false }
    if ($status -ceq 'readback-mismatch' -and $readback -cne 'mismatch') { return $false }
    if ($readback -ceq 'matched') {
        $revision = Get-HandoffField $Value 'Revision'
        if ($null -eq $revision -or (Get-HandoffField $Value 'ReadbackRevision') -cne $revision) { return $false }
    }
    if ($status -ceq 'readback-matched' -and ($capability -cne 'supported' -or $identity -cne 'verified' -or
        $permission -cne 'authorized' -or $readback -cne 'matched' -or
        $null -eq (Get-HandoffField $Value 'AdapterVersion') -or $pending.Count -ne 0 -or $retryable)) { return $false }
    # This validates the caller's report, never its external truth or authority.
    return $true
}

function Copy-HandoffCallerResult {
    param($Value)
    if ($null -eq $Value) { return $null }
    $snapshot = [ordered]@{}
    foreach ($entry in @(Get-HandoffMapEntries $Value)) {
        # Validated reports contain only scalars and the flat PendingActions string array.
        if ($entry.Data -is [array]) {
            $snapshot[$entry.Name] = $entry.Data.Clone()
        } else {
            $snapshot[$entry.Name] = $entry.Data
        }
    }
    return [pscustomobject]$snapshot
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
        if (-not (Test-HandoffCallerResult $CallerResult $OperationId)) {
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
    $callerSnapshot = Copy-HandoffCallerResult $CallerResult
    return New-HandoffRecordResponse 'Accepted' $null $Record $events $callerOutcome $callerSnapshot
}

function Test-HandoffHasField {
    param($Value, [string]$Name)
    if ($null -eq $Value) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $Value.Contains($Name) }
    return ($null -ne $Value.PSObject.Properties[$Name])
}

function Get-HandoffArchiveRecordProblem {
    param($Record, [ValidateSet('Common','Branch')][string]$Kind)
    if (-not (Test-HandoffPlainData $Record) -or
        ($Record -isnot [System.Collections.IDictionary] -and $Record -isnot [pscustomobject])) {
        return 'invalid-record-shape'
    }
    $required = if ($Kind -ceq 'Common') {
        @('Authority Scope','Task Key','Intent','Scope','Current','Source','Lifecycle','Work State')
    } else {
        @('Authority Scope','Task Key','Branch ID','Fork Point','Continuation Generation','Current','Source','Lifecycle','Work State')
    }
    foreach ($field in $required) {
        if (-not (Test-HandoffHasField $Record $field)) { return 'missing-required-field' }
        $value = Get-HandoffField $Record $field
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            return 'missing-required-field'
        }
    }
    $scope = Get-HandoffField $Record 'Authority Scope'
    $task = Get-HandoffField $Record 'Task Key'
    if ($scope -isnot [string] -or [string]::IsNullOrWhiteSpace($scope) -or
        $task -isnot [string] -or [string]::IsNullOrWhiteSpace($task)) { return 'invalid-identity' }
    $branchId = Get-HandoffField $Record 'Branch ID'
    if (($Kind -ceq 'Branch' -and ($branchId -isnot [string] -or [string]::IsNullOrWhiteSpace($branchId))) -or
        ($Kind -ceq 'Common' -and $null -ne $branchId -and
            ($branchId -isnot [string] -or -not [string]::IsNullOrWhiteSpace($branchId)))) {
        return 'invalid-identity'
    }
    $revision = Get-HandoffField $Record 'Revision'
    if ($revision -isnot [string] -or [string]::IsNullOrWhiteSpace($revision)) { return 'invalid-revision' }
    $lifecycle = Get-HandoffField $Record 'Lifecycle'
    if ($lifecycle -isnot [string] -or $lifecycle -cnotin @('Active','Archived')) { return 'invalid-lifecycle' }
    $workState = Get-HandoffField $Record 'Work State'
    if ($workState -isnot [string] -or
        $workState -cnotin @('Running','Awaiting Review','Interrupted','Blocked','Failed')) { return 'invalid-work-state' }
    if ($Kind -ceq 'Branch') {
        $generation = Get-HandoffField $Record 'Continuation Generation'
        if (($generation -isnot [int] -and $generation -isnot [long]) -or $generation -lt 0) {
            return 'invalid-generation'
        }
    }
    return $null
}

function Get-HandoffArchiveParsedTime {
    param($Value, [switch]$AllowDateOnly)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject]@{ Valid = $false; Value = $null }
    }
    if ($AllowDateOnly -and $Value -cmatch '^\d{4}-\d{2}-\d{2}$') {
        $date = [datetime]::MinValue
        if ([datetime]::TryParseExact($Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$date)) {
            $endOfDay = if ($date.Date -eq [datetime]::MaxValue.Date) {
                [datetime]::MaxValue
            } else {
                $date.Date.AddDays(1).AddTicks(-1)
            }
            return [pscustomobject]@{ Valid = $true; Value = [DateTimeOffset]::new($endOfDay, [TimeSpan]::Zero) }
        }
        return [pscustomobject]@{ Valid = $false; Value = $null }
    }
    if ($Value -cnotmatch '(?:Z|[+-]\d{2}:\d{2})$') {
        return [pscustomobject]@{ Valid = $false; Value = $null }
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return [pscustomobject]@{ Valid = $false; Value = $null }
    }
    return [pscustomobject]@{ Valid = $true; Value = $parsed }
}

function Get-HandoffArchiveTimeProblem {
    param($Record, [DateTimeOffset]$Now)
    $activity = Get-HandoffArchiveParsedTime (Get-HandoffField $Record 'Last Activity At')
    if (-not $activity.Valid) { return 'invalid-last-activity' }
    if ($activity.Value -gt $Now) { return 'future-last-activity' }
    $keepUntil = Get-HandoffField $Record 'Keep Active Until'
    if ($null -ne $keepUntil) {
        $keep = Get-HandoffArchiveParsedTime $keepUntil -AllowDateOnly
        if (-not $keep.Valid) { return 'invalid-keep-active-until' }
        if ($keep.Value -gt $Now) { return 'future-keep-active-until' }
    }
    if (($Now - $activity.Value) -lt [TimeSpan]::FromDays(7)) {
        return 'inactivity-period-not-reached'
    }
    return $null
}

function Get-HandoffArchiveActiveIndex {
    param($Common)
    $index = Get-HandoffField $Common 'Active Branches'
    if (-not (Test-HandoffHasField $Common 'Active Branches') -or $null -eq $index) {
        return [pscustomobject]@{ Valid = $false; Ids = [string[]]@(); Reason = 'invalid-active-branch-index' }
    }
    if ($index -isnot [array]) { return [pscustomobject]@{ Valid = $false; Ids = [string[]]@(); Reason = 'invalid-active-branch-index' } }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($branchId in $index) {
        if ($branchId -isnot [string] -or [string]::IsNullOrWhiteSpace($branchId) -or -not $seen.Add($branchId)) {
            return [pscustomobject]@{ Valid = $false; Ids = [string[]]@(); Reason = 'invalid-active-branch-index' }
        }
        $ids.Add($branchId)
    }
    return [pscustomobject]@{ Valid = $true; Ids = [string[]]$ids.ToArray(); Reason = $null }
}

function Get-HandoffArchiveReviewedBranchContentSha256 {
    param($Branch)
    try {
        $entries = @(Get-HandoffMapEntries $Branch)
        $names = [string[]]@($entries | ForEach-Object { [string]$_.Name } |
            Where-Object { $_ -cnotin @('Lifecycle','Branch Outcome','Last Activity At','Revision') })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $fields = [ordered]@{}
        foreach ($name in $names) {
            $match = @($entries | Where-Object { [string]::Equals($_.Name, $name, [StringComparison]::Ordinal) })
            if ($match.Count -ne 1) { return $null }
            $fields[$name] = $match[0].Data
        }
        $identity = [ordered]@{
            taskKey = [string](Get-HandoffField $Branch 'Task Key')
            branchId = [string](Get-HandoffField $Branch 'Branch ID')
            forkPoint = [string](Get-HandoffField $Branch 'Fork Point')
            fields = $fields
        }
        $json = ConvertTo-Json -InputObject $identity -Compress -Depth 50
        $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [Convert]::ToHexString($sha.ComputeHash($strictUtf8.GetBytes($json))).ToLowerInvariant() }
        finally { $sha.Dispose() }
    } catch {
        return $null
    }
}

function Test-HandoffArchiveVerifiedFinalizationProof {
    param($Common, $Branch, $Binding, [object[]]$VerifiedFinalizationProofs = @())
    $scope = [string](Get-HandoffField $Common 'Authority Scope')
    $task = [string](Get-HandoffField $Common 'Task Key')
    $branchId = [string](Get-HandoffField $Branch 'Branch ID')
    $proofs = @($VerifiedFinalizationProofs | Where-Object {
        [string](Get-HandoffField $_ 'AuthorityScope') -ceq $scope -and
        [string](Get-HandoffField $_ 'TaskKey') -ceq $task -and
        [string](Get-HandoffField $_ 'BranchId') -ceq $branchId
    })
    if ($proofs.Count -ne 1) { return $false }

    $proof = $proofs[0]
    if ($proof -isnot [System.Collections.IDictionary] -and $proof -isnot [pscustomobject]) { return $false }
    $required = @('ProofKind','AuthorityScope','TaskKey','BranchId','DecisionCommonRevision',
        'CurrentCommonRevision','ReviewedBranchRevision','CurrentBranchRevision','ReviewedContentSha256',
        'ContinuationGeneration','Outcome')
    $entries = @(Get-HandoffMapEntries $proof)
    if ($entries.Count -ne $required.Count -or
        @($entries | Where-Object { $_.Name -cnotin $required }).Count -gt 0) { return $false }
    foreach ($name in $required) {
        if (@($entries | Where-Object Name -ceq $name).Count -ne 1) { return $false }
    }

    foreach ($name in @('ProofKind','AuthorityScope','TaskKey','BranchId','DecisionCommonRevision',
            'CurrentCommonRevision','ReviewedBranchRevision','CurrentBranchRevision','ReviewedContentSha256','Outcome')) {
        if ((Get-HandoffField $proof $name) -isnot [string]) { return $false }
    }
    $decisionRevision = [string](Get-HandoffField $proof 'DecisionCommonRevision')
    $commonRevision = [string](Get-HandoffField $proof 'CurrentCommonRevision')
    $reviewedRevision = [string](Get-HandoffField $proof 'ReviewedBranchRevision')
    $currentRevision = [string](Get-HandoffField $proof 'CurrentBranchRevision')
    $proofContent = [string](Get-HandoffField $proof 'ReviewedContentSha256')
    $generation = Get-HandoffField $proof 'ContinuationGeneration'
    $proofOutcome = [string](Get-HandoffField $proof 'Outcome')
    if ([string](Get-HandoffField $proof 'ProofKind') -cne 'GitBranchFinalizationDescendant' -or
        $decisionRevision -cnotmatch '^[0-9a-fA-F]{40,64}$' -or
        $commonRevision -cnotmatch '^[0-9a-fA-F]{40,64}$' -or
        $reviewedRevision -cnotmatch '^[0-9a-fA-F]{40,64}$' -or
        $currentRevision -cnotmatch '^[0-9a-fA-F]{40,64}$' -or
        $proofContent -cnotmatch '^[0-9a-fA-F]{64}$' -or
        ($generation -isnot [int] -and $generation -isnot [long]) -or
        $generation -is [bool] -or $generation -lt 0 -or
        $proofOutcome -cnotin @('Selected','Partially Selected','Superseded')) { return $false }

    $boundGeneration = Get-HandoffField $Binding 'continuationGeneration'
    $boundContent = [string](Get-HandoffField $Binding 'reviewedContentSha256')
    $branchOutcome = Get-HandoffField $Branch 'Branch Outcome'
    return ($scope -ceq [string](Get-HandoffField $Branch 'Authority Scope') -and
        $task -ceq [string](Get-HandoffField $Branch 'Task Key') -and
        $branchId -ceq [string](Get-HandoffField $Binding 'branchId') -and
        $commonRevision -ceq [string](Get-HandoffField $Common 'Revision') -and
        $reviewedRevision -ceq [string](Get-HandoffField $Binding 'reviewedRevision') -and
        $currentRevision -ceq [string](Get-HandoffField $Branch 'Revision') -and
        $currentRevision -cne $reviewedRevision -and
        $proofContent.ToLowerInvariant() -ceq $boundContent.ToLowerInvariant() -and
        $generation -eq $boundGeneration -and
        $generation -eq (Get-HandoffField $Branch 'Continuation Generation') -and
        $proofOutcome -ceq [string](Get-HandoffField $Binding 'outcome') -and
        $proofOutcome -ceq [string]$branchOutcome)
}

function Get-HandoffArchiveDecisionBindingProblem {
    param($Common, $Branch, [object[]]$VerifiedFinalizationProofs = @())
    $branchId = [string](Get-HandoffField $Branch 'Branch ID')
    $bindings = Get-HandoffField $Common 'Decision Branch Bindings'
    if ($bindings -isnot [array]) { return 'decision-binding-missing' }
    $matches = @($bindings | Where-Object {
        [string](Get-HandoffField $_ 'branchId') -ceq $branchId
    })
    if ($matches.Count -ne 1) { return 'decision-binding-missing' }
    $binding = $matches[0]
    $entries = @(Get-HandoffMapEntries $binding)
    $required = @('branchId','reviewedRevision','reviewedContentSha256','continuationGeneration','outcome')
    if (($binding -isnot [System.Collections.IDictionary] -and $binding -isnot [pscustomobject]) -or
        $entries.Count -ne $required.Count -or
        @($entries | Where-Object { $_.Name -cnotin $required }).Count -gt 0) { return 'invalid-decision-binding' }
    foreach ($name in $required) {
        if (@($entries | Where-Object Name -ceq $name).Count -ne 1) { return 'invalid-decision-binding' }
    }
    if ((Get-HandoffField $binding 'branchId') -isnot [string] -or
        (Get-HandoffField $binding 'branchId') -cne $branchId -or
        (Get-HandoffField $binding 'reviewedRevision') -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string](Get-HandoffField $binding 'reviewedRevision')) -or
        (Get-HandoffField $binding 'reviewedContentSha256') -isnot [string] -or
        [string](Get-HandoffField $binding 'reviewedContentSha256') -cnotmatch '^[0-9a-fA-F]{64}$' -or
        (Get-HandoffField $binding 'outcome') -isnot [string] -or
        (Get-HandoffField $binding 'outcome') -cnotin @('Selected','Partially Selected','Superseded')) {
        return 'invalid-decision-binding'
    }
    if ((Get-HandoffField $binding 'reviewedRevision') -cne (Get-HandoffField $Branch 'Revision') -and
        -not (Test-HandoffArchiveVerifiedFinalizationProof -Common $Common -Branch $Branch -Binding $binding -VerifiedFinalizationProofs $VerifiedFinalizationProofs)) {
        return 'decision-revision-mismatch'
    }
    $boundGeneration = Get-HandoffField $binding 'continuationGeneration'
    $generation = Get-HandoffField $Branch 'Continuation Generation'
    if (($boundGeneration -isnot [int] -and $boundGeneration -isnot [long]) -or
        $boundGeneration -lt 0 -or $boundGeneration -ne $generation) { return 'decision-generation-mismatch' }
    $outcome = Get-HandoffField $Branch 'Branch Outcome'
    if ($outcome -isnot [string] -or $outcome -cne (Get-HandoffField $binding 'outcome')) {
        return 'decision-outcome-mismatch'
    }
    $actualIdentity = Get-HandoffArchiveReviewedBranchContentSha256 $Branch
    if ($null -eq $actualIdentity -or
        $actualIdentity -cne ([string](Get-HandoffField $binding 'reviewedContentSha256')).ToLowerInvariant()) {
        return 'decision-content-mismatch'
    }
    return $null
}

function New-HandoffArchiveDecision {
    param($Record, [string]$Kind, [string]$Reason, $Parent)
    $generation = if ($Kind -ceq 'Branch') { Get-HandoffField $Record 'Continuation Generation' } else { $null }
    $parentRevision = if ($Kind -ceq 'Branch' -and $null -ne $Parent) { Get-HandoffField $Parent 'Revision' } else { $null }
    return [pscustomobject]@{
        Kind = $Kind
        AuthorityScope = Get-HandoffField $Record 'Authority Scope'
        TaskKey = Get-HandoffField $Record 'Task Key'
        BranchId = Get-HandoffField $Record 'Branch ID'
        Revision = Get-HandoffField $Record 'Revision'
        ParentRevision = $parentRevision
        ContinuationGeneration = $generation
        BranchOutcome = Get-HandoffField $Record 'Branch Outcome'
        Reason = $Reason
    }
}

function Get-HandoffArchiveSelection {
    [CmdletBinding()]
    param(
        [object[]]$CommonRecords = @(),
        [object[]]$BranchRecords = @(),
        [Parameter(Mandatory)][scriptblock]$Clock,
        [Parameter(Mandatory)][bool]$InventoryComplete,
        [object[]]$VerifiedFinalizationProofs = @()
    )

    $now = $null
    try {
        $clockValues = @(& $Clock 2>$null)
        if ($clockValues.Count -eq 1 -and $clockValues[0] -is [DateTimeOffset]) {
            $now = $clockValues[0].ToUniversalTime()
        }
    } catch { }
    $selected = [System.Collections.Generic.List[object]]::new()
    $protected = [System.Collections.Generic.List[object]]::new()
    foreach ($common in $CommonRecords) {
        $reason = if ($null -eq $now) { 'invalid-clock' }
            elseif (-not $InventoryComplete) { 'inventory-incomplete' }
            else { Get-HandoffArchiveRecordProblem $common 'Common' }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $scope = Get-HandoffField $common 'Authority Scope'
            $task = Get-HandoffField $common 'Task Key'
            $duplicates = @($CommonRecords | Where-Object {
                [string](Get-HandoffField $_ 'Authority Scope') -ceq $scope -and
                [string](Get-HandoffField $_ 'Task Key') -ceq $task
            })
            if ($duplicates.Count -ne 1) { $reason = 'duplicate-common-identity' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            if ((Get-HandoffField $common 'Lifecycle') -ceq 'Archived') { $reason = 'already-archived' }
            elseif ((Get-HandoffField $common 'Work State') -cin @('Running','Blocked')) { $reason = 'active-work' }
            elseif ((Get-HandoffField $common 'Conflict') -ceq 'Conflict') { $reason = 'unresolved-conflict' }
            elseif ($null -ne (Get-HandoffField $common 'Conflict')) { $reason = 'invalid-conflict-state' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $index = Get-HandoffArchiveActiveIndex $common
            if (-not $index.Valid) { $reason = $index.Reason }
            elseif ($index.Ids.Count -gt 0) { $reason = 'active-branch-index' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $scope = Get-HandoffField $common 'Authority Scope'
            $task = Get-HandoffField $common 'Task Key'
            $livePeers = @($BranchRecords | Where-Object {
                [string](Get-HandoffField $_ 'Authority Scope') -ceq $scope -and
                [string](Get-HandoffField $_ 'Task Key') -ceq $task -and
                (Get-HandoffField $_ 'Lifecycle') -cne 'Archived'
            })
            if ($livePeers.Count -gt 0) { $reason = 'active-branch-missing-from-index' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $reason = Get-HandoffArchiveTimeProblem $common $now
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $selected.Add((New-HandoffArchiveDecision $common 'Common' 'inactivity-expired' $null))
        } else {
            $protected.Add((New-HandoffArchiveDecision $common 'Common' $reason $null))
        }
    }

    foreach ($branch in $BranchRecords) {
        $reason = if ($null -eq $now) { 'invalid-clock' }
            elseif (-not $InventoryComplete) { 'inventory-incomplete' }
            else { Get-HandoffArchiveRecordProblem $branch 'Branch' }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $scope = Get-HandoffField $branch 'Authority Scope'
            $task = Get-HandoffField $branch 'Task Key'
            $branchId = Get-HandoffField $branch 'Branch ID'
            $duplicates = @($BranchRecords | Where-Object {
                [string](Get-HandoffField $_ 'Authority Scope') -ceq $scope -and
                [string](Get-HandoffField $_ 'Task Key') -ceq $task -and
                [string](Get-HandoffField $_ 'Branch ID') -ceq $branchId
            })
            if ($duplicates.Count -ne 1) { $reason = 'duplicate-branch-identity' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            if ((Get-HandoffField $branch 'Lifecycle') -ceq 'Archived') { $reason = 'already-archived' }
            elseif ((Get-HandoffField $branch 'Work State') -cin @('Running','Blocked')) { $reason = 'active-work' }
        }
        $parent = $null
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $scope = Get-HandoffField $branch 'Authority Scope'
            $task = Get-HandoffField $branch 'Task Key'
            $parents = @($CommonRecords | Where-Object {
                [string](Get-HandoffField $_ 'Authority Scope') -ceq $scope -and
                [string](Get-HandoffField $_ 'Task Key') -ceq $task
            })
            if ($parents.Count -ne 1) { $reason = 'missing-or-ambiguous-common' }
            else { $parent = $parents[0] }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $parentProblem = Get-HandoffArchiveRecordProblem $parent 'Common'
            if (-not [string]::IsNullOrWhiteSpace($parentProblem)) { $reason = 'invalid-common-parent' }
            elseif ((Get-HandoffField $parent 'Lifecycle') -cne 'Active') { $reason = 'common-not-active' }
            elseif ((Get-HandoffField $parent 'Work State') -cin @('Running','Blocked')) { $reason = 'common-active-work' }
            elseif ((Get-HandoffField $parent 'Conflict') -ceq 'Conflict') { $reason = 'common-unresolved-conflict' }
            elseif ($null -ne (Get-HandoffField $parent 'Conflict')) { $reason = 'common-invalid-conflict-state' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $index = Get-HandoffArchiveActiveIndex $parent
            if (-not $index.Valid) { $reason = 'invalid-common-index' }
            elseif ($index.Ids -cnotcontains [string](Get-HandoffField $branch 'Branch ID')) { $reason = 'branch-not-indexed' }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $parentTimeProblem = Get-HandoffArchiveTimeProblem $parent $now
            if ($parentTimeProblem -cin @('future-keep-active-until','invalid-keep-active-until')) {
                $reason = "common-$parentTimeProblem"
            }
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            # Proofs are trusted Adapter/inventory-caller facts, like InventoryComplete;
            # never derive them by copying values from untrusted Common or Branch records.
            $reason = Get-HandoffArchiveDecisionBindingProblem $parent $branch $VerifiedFinalizationProofs
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $reason = Get-HandoffArchiveTimeProblem $branch $now
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $selected.Add((New-HandoffArchiveDecision $branch 'Branch' 'inactivity-expired' $parent))
        } else {
            $protected.Add((New-HandoffArchiveDecision $branch 'Branch' $reason $parent))
        }
    }
    return [pscustomobject]@{
        AsOfUtc = $now
        ClockValid = ($null -ne $now)
        Selected = [object[]]$selected.ToArray()
        Protected = [object[]]$protected.ToArray()
        Durable = $false
    }
}

function New-HandoffArchiveCycleCursor {
    param($Decision)
    return [pscustomobject]@{
        Kind = Get-HandoffField $Decision 'Kind'
        AuthorityScope = Get-HandoffField $Decision 'AuthorityScope'
        TaskKey = Get-HandoffField $Decision 'TaskKey'
        BranchId = Get-HandoffField $Decision 'BranchId'
        Revision = Get-HandoffField $Decision 'Revision'
        ParentRevision = Get-HandoffField $Decision 'ParentRevision'
        ContinuationGeneration = Get-HandoffField $Decision 'ContinuationGeneration'
    }
}

function Get-HandoffArchiveCycleOperationId {
    param([string]$CycleOperationId, $Cursor)
    $identity = [ordered]@{ CycleOperationId = $CycleOperationId; Cursor = $Cursor }
    $json = ConvertTo-Json -InputObject $identity -Compress -Depth 8
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = [Convert]::ToHexString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
    } finally { $sha.Dispose() }
    return "${CycleOperationId}:archive:${digest}"
}

function Test-HandoffArchiveCyclePendingAction {
    param($PendingAction)
    $decision = Get-HandoffField $PendingAction 'Decision'
    $cursor = Get-HandoffField $PendingAction 'Cursor'
    $operationId = Get-HandoffField $PendingAction 'OperationId'
    if ($null -eq $decision -or $null -eq $cursor -or
        $operationId -isnot [string] -or [string]::IsNullOrWhiteSpace($operationId)) {
        return $false
    }
    $kind = Get-HandoffField $decision 'Kind'
    $scope = Get-HandoffField $decision 'AuthorityScope'
    $task = Get-HandoffField $decision 'TaskKey'
    $revision = Get-HandoffField $decision 'Revision'
    $reason = Get-HandoffField $decision 'Reason'
    if ($kind -cnotin @('Common','Branch') -or
        $scope -isnot [string] -or [string]::IsNullOrWhiteSpace($scope) -or
        $task -isnot [string] -or [string]::IsNullOrWhiteSpace($task) -or
        $revision -isnot [string] -or [string]::IsNullOrWhiteSpace($revision) -or
        $reason -isnot [string] -or $reason -cne 'inactivity-expired') {
        return $false
    }
    if ($kind -ceq 'Branch') {
        $branchId = Get-HandoffField $decision 'BranchId'
        $parentRevision = Get-HandoffField $decision 'ParentRevision'
        $generation = Get-HandoffField $decision 'ContinuationGeneration'
        if ($branchId -isnot [string] -or [string]::IsNullOrWhiteSpace($branchId) -or
            $parentRevision -isnot [string] -or [string]::IsNullOrWhiteSpace($parentRevision) -or
            ($generation -isnot [int] -and $generation -isnot [long]) -or $generation -lt 0) {
            return $false
        }
    } elseif ($null -ne (Get-HandoffField $decision 'BranchId') -or
        $null -ne (Get-HandoffField $decision 'ParentRevision') -or
        $null -ne (Get-HandoffField $decision 'ContinuationGeneration')) {
        return $false
    }
    $expected = New-HandoffArchiveCycleCursor $decision
    foreach ($field in @('Kind','AuthorityScope','TaskKey','BranchId','Revision','ParentRevision','ContinuationGeneration')) {
        if ((Get-HandoffField $cursor $field) -cne (Get-HandoffField $expected $field)) { return $false }
    }
    $separator = $operationId.LastIndexOf(':archive:', [StringComparison]::Ordinal)
    if ($separator -le 0) { return $false }
    $cycleOperationId = $operationId.Substring(0, $separator)
    $digest = $operationId.Substring($separator + ':archive:'.Length)
    if ($digest -cnotmatch '\A[0-9a-f]{64}\z') { return $false }
    $expectedOperationId = Get-HandoffArchiveCycleOperationId -CycleOperationId $cycleOperationId -Cursor $cursor
    if ($operationId -cne $expectedOperationId) { return $false }
    return $true
}

function Get-HandoffArchiveCycleIdentityKey {
    param($Decision, [switch]$TaskOnly)
    $fields = if ($TaskOnly) { @('AuthorityScope','TaskKey') } else { @('Kind','AuthorityScope','TaskKey') }
    if (-not $TaskOnly -and (Get-HandoffField $Decision 'Kind') -ceq 'Branch') { $fields += 'BranchId' }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($field in $fields) {
        $value = Get-HandoffField $Decision $field
        $text = if ($null -eq $value) { '' } else { [string]$value }
        $parts.Add(('{0}:{1}' -f $text.Length,$text))
    }
    return [string]::Join('|',$parts.ToArray())
}

function Test-HandoffArchiveCycleValueEqual {
    param($Left, $Right)
    if ($Left -is [int] -or $Left -is [long]) {
        if ($Right -isnot [int] -and $Right -isnot [long]) { return $false }
        return ([long]$Left -eq [long]$Right)
    }
    return [object]::Equals($Left,$Right)
}

function Test-HandoffArchiveCycleDecisionCursorEqual {
    param($LeftDecision, $LeftCursor, $RightDecision, $RightCursor)
    foreach ($field in @('Kind','AuthorityScope','TaskKey','BranchId','Revision','ParentRevision','ContinuationGeneration','BranchOutcome','Reason')) {
        $leftValue = Get-HandoffField $LeftDecision $field
        $rightValue = Get-HandoffField $RightDecision $field
        if (-not (Test-HandoffArchiveCycleValueEqual $leftValue $rightValue)) { return $false }
    }
    foreach ($field in @('Kind','AuthorityScope','TaskKey','BranchId','Revision','ParentRevision','ContinuationGeneration')) {
        $leftValue = Get-HandoffField $LeftCursor $field
        $rightValue = Get-HandoffField $RightCursor $field
        if (-not (Test-HandoffArchiveCycleValueEqual $leftValue $rightValue)) { return $false }
    }
    return $true
}

function Test-HandoffArchiveCyclePendingActionEqual {
    param($Left, $Right)
    if (-not (Test-HandoffArchiveCycleDecisionCursorEqual -LeftDecision (Get-HandoffField $Left 'Decision') -LeftCursor (Get-HandoffField $Left 'Cursor') -RightDecision (Get-HandoffField $Right 'Decision') -RightCursor (Get-HandoffField $Right 'Cursor'))) {
        return $false
    }
    $leftOperationId = Get-HandoffField $Left 'OperationId'
    $rightOperationId = Get-HandoffField $Right 'OperationId'
    return [StringComparer]::Ordinal.Equals([string]$leftOperationId,[string]$rightOperationId)
}

function Invoke-HandoffArchiveCycle {
    [CmdletBinding()]
    param(
        [object[]]$CommonRecords = @(),
        [object[]]$BranchRecords = @(),
        [Parameter(Mandatory)][scriptblock]$Clock,
        [Parameter(Mandatory)][bool]$InventoryComplete,
        [Parameter(Mandatory)][bool]$CandidateBatchAuthorized,
        [object[]]$VerifiedFinalizationProofs = @(),
        [object[]]$PendingActions = @(),
        [string]$OperationId,
        [Parameter(Mandatory)][scriptblock]$ArchiveAction
    )

    $selected = [System.Collections.Generic.List[object]]::new()
    $protected = [System.Collections.Generic.List[object]]::new()
    $completed = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.List[object]]::new()
    $actions = [System.Collections.Generic.List[object]]::new()
    $pendingActionsToRetry = [System.Collections.Generic.List[object]]::new()
    $pendingByRecordIdentity = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $pendingTaskIdentities = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $asOfUtc = $null
    $clockValid = $false
    $gateReason = $null
    $freshCandidatesDeferred = $false
    $cycleOperationId = $OperationId

    if (-not $CandidateBatchAuthorized) { $gateReason = 'candidate-batch-unauthorized' }
    elseif (-not $InventoryComplete) { $gateReason = 'inventory-incomplete' }
    if ($null -ne $gateReason) {
        foreach ($item in $PendingActions) { $pending.Add($item) }
        return [pscustomobject]@{
            AsOfUtc = $asOfUtc; ClockValid = $clockValid; GateReason = $gateReason
            Selected = [object[]]@(); Protected = [object[]]@()
            Completed = [object[]]@(); Pending = [object[]]$pending.ToArray(); Durable = $false
        }
    }

    if ($PendingActions.Count -gt 0) {
        foreach ($item in $PendingActions) {
            if (-not (Test-HandoffArchiveCyclePendingAction $item)) {
                return [pscustomobject]@{
                    AsOfUtc = $asOfUtc; ClockValid = $clockValid; GateReason = 'invalid-pending-action'
                    Selected = [object[]]@(); Protected = [object[]]@()
                    Completed = [object[]]@(); Pending = [object[]]$PendingActions; Durable = $false
                }
            }
            $decision = Get-HandoffField $item 'Decision'
            $recordIdentity = Get-HandoffArchiveCycleIdentityKey $decision
            if ($pendingByRecordIdentity.ContainsKey($recordIdentity)) {
                if (-not (Test-HandoffArchiveCyclePendingActionEqual $pendingByRecordIdentity[$recordIdentity] $item)) {
                    return [pscustomobject]@{
                        AsOfUtc = $asOfUtc; ClockValid = $clockValid; GateReason = 'conflicting-pending-actions'
                        Selected = [object[]]@(); Protected = [object[]]@()
                        Completed = [object[]]@(); Pending = [object[]]$PendingActions; Durable = $false
                    }
                }
                continue
            }
            $pendingByRecordIdentity.Add($recordIdentity,$item)
            $pendingTaskIdentities.Add((Get-HandoffArchiveCycleIdentityKey $decision -TaskOnly)) | Out-Null
            $pendingActionsToRetry.Add($item)
        }
        foreach ($item in $pendingActionsToRetry) {
            $decision = Get-HandoffField $item 'Decision'
            $cursor = Get-HandoffField $item 'Cursor'
            $operationId = Get-HandoffField $item 'OperationId'
            $selected.Add($decision)
            $actions.Add([pscustomobject]@{ Decision = $decision; Cursor = $cursor; OperationId = $operationId })
        }
    }

    $hasFreshCandidates = $CommonRecords.Count -gt 0 -or $BranchRecords.Count -gt 0
    if ($PendingActions.Count -eq 0 -or $hasFreshCandidates) {
        $selection = Get-HandoffArchiveSelection -CommonRecords $CommonRecords -BranchRecords $BranchRecords -Clock $Clock -InventoryComplete $InventoryComplete -VerifiedFinalizationProofs $VerifiedFinalizationProofs
        $asOfUtc = $selection.AsOfUtc
        $clockValid = $selection.ClockValid
        foreach ($decision in $selection.Protected) { $protected.Add($decision) }
        $freshOperationIdRequired = $false
        foreach ($decision in $selection.Selected) {
            $recordIdentity = Get-HandoffArchiveCycleIdentityKey $decision
            if ($pendingByRecordIdentity.ContainsKey($recordIdentity)) {
                $pendingAction = $pendingByRecordIdentity[$recordIdentity]
                $freshCursor = New-HandoffArchiveCycleCursor $decision
                if (Test-HandoffArchiveCycleDecisionCursorEqual -LeftDecision $decision -LeftCursor $freshCursor -RightDecision (Get-HandoffField $pendingAction 'Decision') -RightCursor (Get-HandoffField $pendingAction 'Cursor')) {
                    continue
                }
                $selected.Add($decision)
                $freshCandidatesDeferred = $true
                if ([string]::IsNullOrWhiteSpace($cycleOperationId)) { $freshOperationIdRequired = $true }
                continue
            }
            $taskIdentity = Get-HandoffArchiveCycleIdentityKey $decision -TaskOnly
            if ($pendingTaskIdentities.Contains($taskIdentity)) {
                $selected.Add($decision)
                $freshCandidatesDeferred = $true
                if ([string]::IsNullOrWhiteSpace($cycleOperationId)) { $freshOperationIdRequired = $true }
                continue
            }
            $selected.Add($decision)
            if ([string]::IsNullOrWhiteSpace($cycleOperationId)) {
                $freshOperationIdRequired = $true
                continue
            }
            $cursor = New-HandoffArchiveCycleCursor $decision
            $actions.Add([pscustomobject]@{
                Decision = $decision
                Cursor = $cursor
                OperationId = Get-HandoffArchiveCycleOperationId -CycleOperationId $cycleOperationId -Cursor $cursor
            })
        }
        if ($freshOperationIdRequired) { $gateReason = 'stable-operation-id-required' }
        elseif ($freshCandidatesDeferred) { $gateReason = 'pending-task-cursor-in-flight' }
    }

    foreach ($action in $actions) {
        $decision = $action.Decision
        $cursor = $action.Cursor
        $operationId = [string]$action.OperationId
        $acknowledgements = @()
        $actionError = $false
        try { $acknowledgements = @(& $ArchiveAction $decision $cursor $operationId 2>$null) }
        catch { $actionError = $true }
        $ack = if (-not $actionError -and $acknowledgements.Count -eq 1) { $acknowledgements[0] } else { $null }
        $durable = $null -ne $ack -and (Get-HandoffField $ack 'Durable') -is [bool] -and (Get-HandoffField $ack 'Durable') -eq $true
        $readback = $null -ne $ack -and (Get-HandoffField $ack 'ReadbackVerified') -is [bool] -and (Get-HandoffField $ack 'ReadbackVerified') -eq $true
        $ackOperationId = Get-HandoffField $ack 'OperationId'
        if ($durable -and $readback -and $ackOperationId -is [string] -and $ackOperationId -ceq $operationId) {
            $completed.Add([pscustomobject]@{ Decision = $decision; Cursor = $cursor; OperationId = $operationId; Acknowledgement = $ack })
        } else {
            $reason = if ($actionError) { 'archive-action-error' } else { 'durable-readback-not-confirmed' }
            $pending.Add([pscustomobject]@{ Decision = $decision; Cursor = $cursor; OperationId = $operationId; Reason = $reason })
        }
    }

    return [pscustomobject]@{
        AsOfUtc = $asOfUtc; ClockValid = $clockValid; GateReason = $gateReason
        Selected = [object[]]$selected.ToArray(); Protected = [object[]]$protected.ToArray()
        Completed = [object[]]$completed.ToArray(); Pending = [object[]]$pending.ToArray()
        Durable = ($selected.Count -gt 0 -and $completed.Count -eq $selected.Count -and $pending.Count -eq 0)
    }
}

Export-ModuleMember -Function Invoke-HandoffRecordCore, Get-HandoffArchiveSelection, Invoke-HandoffArchiveCycle
