# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

function Get-HandoffField {
    param($Value, [string]$Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
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
        if ([string]$name -in @('secret', 'password', 'credential', 'apiKey', 'accessToken', 'refreshToken', 'privateKey')) { return $true }
        if (Test-HandoffSensitiveField (Get-HandoffField $Value ([string]$name)) ($Depth + 1)) { return $true }
    }
    return $false
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
    if (Test-HandoffSensitiveField $Record) {
        return New-HandoffRecordResponse 'Rejected' 'sensitive-field' $null $empty $null
    }
    if ((Get-HandoffField $Record 'Lifecycle') -cnotin @('Active', 'Archived') -or
        (Get-HandoffField $Record 'Work State') -cnotin @('Running', 'Awaiting Review', 'Interrupted', 'Blocked', 'Failed')) {
        return New-HandoffRecordResponse 'Rejected' 'invalid-state' $null $empty $null
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

    $callerOutcome = $null
    if ($null -ne $CallerResult) {
        $callerOutcome = [string](Get-HandoffField $CallerResult 'Status')
        if ($callerOutcome -cnotin @('denied', 'partial', 'unknown', 'readback-mismatch', 'readback-matched')) {
            return New-HandoffRecordResponse 'Rejected' 'invalid-caller-result' $null $empty $null
        }
    }

    $events = @(
        foreach ($field in $required) {
            if ($field -in @('Authority Scope', 'Task Key', 'Branch ID', 'Fork Point', 'Continuation Generation')) { continue }
            $old = Get-HandoffField $previous $field
            $new = Get-HandoffField $Record $field
            if (($null -eq $previous) -or ((ConvertTo-Json -InputObject $old -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $new -Depth 20 -Compress))) {
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
    return New-HandoffRecordResponse 'Accepted' $null $Record $events $callerOutcome
}

Export-ModuleMember -Function Invoke-HandoffRecordCore
