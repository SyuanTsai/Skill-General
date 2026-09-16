# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest
$script:HandoffIndexLock = [object]::new()
$script:HandoffInternalOperationPrefix = '__handoff_internal_v1__:'

function Get-HandoffSha256 {
    param([Parameter(Mandatory = $true)][string] $Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Assert-HandoffOperationId {
    param([Parameter(Mandatory = $true)][string] $OperationId,[switch] $Internal)
    if ([string]::IsNullOrWhiteSpace($OperationId)) { throw 'Stable Operation ID is required for every mutation.' }
    $reserved = $OperationId.StartsWith($script:HandoffInternalOperationPrefix,[StringComparison]::Ordinal)
    if ($Internal -and -not $reserved) { throw 'An internal Handoff mutation requires a reserved internal Operation ID.' }
    if (-not $Internal -and $reserved) { throw 'The reserved internal Operation ID namespace cannot be supplied by an adopter.' }
}

function Get-HandoffInternalOperationScopePrefix {
    param([Parameter(Mandatory = $true)][string] $Purpose,[Parameter(Mandatory = $true)][string] $ParentOperationId,
        [string] $BranchId)
    $parentDigest = Get-HandoffSha256 -Value $ParentOperationId
    $branchDigest = Get-HandoffSha256 -Value ([string]$BranchId)
    return "$($script:HandoffInternalOperationPrefix)${Purpose}:${parentDigest}:${branchDigest}:"
}

function Get-HandoffInternalOperationId {
    param([Parameter(Mandatory = $true)][string] $Purpose,[Parameter(Mandatory = $true)][string] $TaskKey,
        [string] $BranchId,[Parameter(Mandatory = $true)][string] $ParentOperationId,
        [Parameter(Mandatory = $true)][string] $Binding)
    $identity = [ordered]@{
        purpose = $Purpose
        taskKey = $TaskKey
        branchId = $BranchId
        parentOperationId = $ParentOperationId
        binding = $Binding
    }
    $digest = Get-HandoffSha256 -Value ($identity | ConvertTo-Json -Compress -Depth 10)
    return "$(Get-HandoffInternalOperationScopePrefix -Purpose $Purpose -ParentOperationId $ParentOperationId -BranchId $BranchId)${digest}"
}

function Assert-HandoffIdentity {
    param([Parameter(Mandatory = $true)][string] $TaskKey)
    if ([string]::IsNullOrWhiteSpace($TaskKey)) { throw 'Task Key must be stable and nonempty.' }
}

function Assert-GitAdapter {
    param([Parameter(Mandatory = $true)] $Adapter)
    foreach ($name in @('RepositoryRoot','RemoteName','RefPrefix')) {
        if ($null -eq $Adapter.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$Adapter.$name)) {
            throw "Git Handoff adapter configuration is missing '$name'."
        }
    }
    if ([string]$Adapter.RefPrefix -cnotmatch '^refs/heads/[a-z0-9][a-z0-9/-]*$' -or
        [string]$Adapter.RefPrefix -cmatch '(^|/)\.\.?(/|$)' -or [string]$Adapter.RefPrefix -cmatch '\.lock($|/)') {
        throw 'The adapter ref namespace is unsafe.'
    }
    if (-not (Test-Path -LiteralPath ([string]$Adapter.RepositoryRoot) -PathType Container)) {
        throw 'The configured local Git object store is unavailable.'
    }
}

function Get-HandoffRecordId {
    param([Parameter(Mandatory = $true)][string] $RecordKind,[Parameter(Mandatory = $true)][string] $TaskKey,[string] $BranchId)
    if ($RecordKind -notin @('common','branch')) { throw 'Unknown Handoff record kind.' }
    if ($RecordKind -eq 'branch' -and [string]::IsNullOrWhiteSpace($BranchId)) { throw 'Branch ID is required.' }
    Assert-HandoffIdentity -TaskKey $TaskKey
    if ($RecordKind -eq 'common') { return "common:$TaskKey" }
    $taskHash = Get-HandoffSha256 -Value $TaskKey
    $branchHash = Get-HandoffSha256 -Value $BranchId
    return "branch:${taskHash}:${branchHash}"
}

function Get-HandoffRecordRef {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId)
    Assert-GitAdapter -Adapter $Adapter
    $taskHash = Get-HandoffSha256 -Value $TaskKey
    if ($RecordKind -eq 'common') { return "$($Adapter.RefPrefix)/records/$taskHash/common" }
    if ($RecordKind -eq 'branch') { return "$($Adapter.RefPrefix)/records/$taskHash/branch/$(Get-HandoffSha256 -Value $BranchId)" }
    throw 'Unknown Handoff record kind.'
}

function Get-HandoffForkRecoveryId {
    param([Parameter(Mandatory = $true)][string] $TaskKey,[Parameter(Mandatory = $true)][string] $ForkId)
    Assert-HandoffIdentity -TaskKey $TaskKey
    if ([string]::IsNullOrWhiteSpace($ForkId)) { throw 'Fork ID must be stable and nonempty.' }
    return "fork-recovery:$(Get-HandoffSha256 -Value $TaskKey):$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffForkRecoveryRef {
    param($Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,[Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitAdapter -Adapter $Adapter
    [void](Get-HandoffForkRecoveryId -TaskKey $TaskKey -ForkId $ForkId)
    return "$($Adapter.RefPrefix)/recovery/$(Get-HandoffSha256 -Value $TaskKey)/$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffEventRef {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $OperationId,[string] $Field)
    if ([string]::IsNullOrWhiteSpace($OperationId) -or [string]::IsNullOrWhiteSpace($Field)) { throw 'Event identity is incomplete.' }
    $recordId = Get-HandoffRecordId -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    # One full digest retains the composite identity without creating a long Windows ref path.
    $composite = "${OperationId}`0${recordId}`0${Field}"
    $digest = Get-HandoffSha256 -Value $composite
    return "$($Adapter.RefPrefix)/events/$digest"
}

function Get-RemoteHandoffRevision {
    param($Adapter,[string] $Ref)
    Assert-GitAdapter -Adapter $Adapter
    $lines = & git -C $Adapter.RepositoryRoot ls-remote --exit-code $Adapter.RemoteName $Ref 2>$null
    $status = $LASTEXITCODE
    if ($status -eq 2) { return $null }
    if ($status -ne 0) { throw 'The selected Git storage remote cannot be queried.' }
    $matching = @(
        foreach ($line in @($lines)) {
            $parts = ([string]$line) -split "`t", 2
            if ($parts.Count -eq 2 -and $parts[1] -ceq $Ref) { $parts[0] }
        }
    )
    if ($matching.Count -ne 1 -or $matching[0] -cnotmatch '^[0-9a-f]{40,64}$') {
        throw 'The exact Handoff ref has a duplicate or invalid remote revision.'
    }
    return [string]$matching[0]
}

function Read-GitHandoffDocument {
    param($Adapter,[string] $Ref,[string] $Revision,[string] $FileName)
    & git -C $Adapter.RepositoryRoot fetch --quiet --no-tags $Adapter.RemoteName $Ref 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'The exact Handoff ref could not be fetched for readback.' }
    $text = & git -C $Adapter.RepositoryRoot show "${Revision}:${FileName}" 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'The Handoff commit does not contain the expected document.' }
    try { return (@($text) -join "`n") | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw 'The Handoff document could not be parsed without ambiguity.' }
}

function New-GitHandoffCommit {
    param($Adapter,[Parameter(Mandatory = $true)] $Document,[string] $Parent,[ValidateSet('record.json','event.json','recovery.json')][string] $FileName)
    Assert-GitAdapter -Adapter $Adapter
    $json = $Document | ConvertTo-Json -Compress -Depth 50
    $blob = ($json | & git -C $Adapter.RepositoryRoot hash-object -w --stdin 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]$blob -cnotmatch '^[0-9a-f]{40,64}$') { throw 'Could not write the isolated Handoff blob.' }
    # A separate Git index avoids PowerShell's native stdin CRLF becoming part of a tree filename.
    $indexPath = Join-Path $Adapter.RepositoryRoot ('.handoff-index-' + [guid]::NewGuid().ToString('N'))
    [Threading.Monitor]::Enter($script:HandoffIndexLock)
    try {
        $priorIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process')
        try {
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',$indexPath,'Process')
            & git -C $Adapter.RepositoryRoot update-index --add --cacheinfo "100644,${blob},${FileName}" 2>$null
            if ($LASTEXITCODE -ne 0) { throw 'Could not stage the isolated Handoff blob.' }
            $tree = & git -C $Adapter.RepositoryRoot write-tree 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]$tree -cnotmatch '^[0-9a-f]{40,64}$') { throw 'Could not build the isolated Handoff tree.' }
        }
        finally {
            # An empty process variable is still visible to Git and can make a later git add
            # fail with "unable to write new index file". Remove it when no prior path exists.
            if ([string]::IsNullOrEmpty($priorIndex)) {
                Remove-Item Env:GIT_INDEX_FILE -ErrorAction Stop
            }
            else { [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',$priorIndex,'Process') }
            if (Test-Path -LiteralPath $indexPath -PathType Leaf) { Remove-Item -LiteralPath $indexPath -Force }
        }
    }
    finally { [Threading.Monitor]::Exit($script:HandoffIndexLock) }
    $args = @('-C',[string]$Adapter.RepositoryRoot,'commit-tree',[string]$tree)
    if (-not [string]::IsNullOrWhiteSpace($Parent)) { $args += @('-p',$Parent) }
    $args += @('-m','Update isolated Task Handoff data')
    $commit = & git @args 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]$commit -cnotmatch '^[0-9a-f]{40,64}$') { throw 'Could not create the isolated Handoff commit.' }
    return [string]$commit
}

function Push-GitHandoffIfRevision {
    param($Adapter,[string] $Ref,[AllowEmptyString()][string] $ExpectedRevision,[string] $Commit)
    Assert-GitAdapter -Adapter $Adapter
    $lease = "--force-with-lease=${Ref}:${ExpectedRevision}"
    $refspec = "${Commit}:${Ref}"
    $pushOutput = @(& git -C $Adapter.RepositoryRoot push --quiet $lease $Adapter.RemoteName $refspec 2>&1)
    $status = $LASTEXITCODE
    $observed = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $Ref
    if ($observed -ceq $Commit) { return $Commit }
    $expectedRemote = if ([string]::IsNullOrEmpty($ExpectedRevision)) { $null } else { $ExpectedRevision }
    if ($status -ne 0 -and $observed -cne $expectedRemote) { throw 'Conditional Handoff revision conflict; re-read formal authority and records.' }
    $pushDiagnostic = @($pushOutput | ForEach-Object { [string]$_ }) -join "`n"
    if ($status -ne 0 -and $pushDiagnostic -match '(?i)file\s*name too long') {
        throw 'Git Handoff ref path is too long for the selected storage remote; check its long-ref support or use a shorter isolated store path.'
    }
    if ($status -ne 0 -and $pushDiagnostic -match '(?is)cannot lock ref.+unable to create directory') {
        throw 'Git Handoff ref path or directory is unavailable for the selected storage remote; check long-ref support, path depth, and permissions.'
    }
    throw 'The selected Git Handoff storage write was not verified; retain this operation ID.'
}

function Read-GitHandoffRecord {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId)
    $recordId = Get-HandoffRecordId -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $ref = Get-HandoffRecordRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $record = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'record.json'
    if ($record.schemaVersion -ne 1 -or $record.recordKind -cne $RecordKind -or
        $record.taskKey -cne $TaskKey -or $record.recordId -cne $recordId -or
        ($RecordKind -eq 'branch' -and $record.branchId -cne $BranchId) -or
        ($RecordKind -eq 'common' -and $null -ne $record.branchId)) {
        throw 'The exact Handoff ref contains a mismatched task or branch association.'
    }
    return [pscustomobject]@{ Revision=$revision; Ref=$ref; Record=$record }
}

function Assert-HandoffForkRecoveryPayload {
    param([Parameter(Mandatory = $true)] $Payload)
    if ($Payload -isnot [Collections.IDictionary]) { throw 'Fork recovery payload must be an ordered mapping.' }
    $required = @('Fork Point','Source Branch ID','Intended Branch IDs','Source Snapshot','Shared Baseline',
        'Verified Active Branches','Step Operation IDs')
    foreach ($field in $required) {
        if (-not $Payload.Contains($field) -or $null -eq $Payload[$field]) {
            throw "Fork recovery payload is missing '$field'."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$Payload['Fork Point']) -or
        [string]::IsNullOrWhiteSpace([string]$Payload['Source Branch ID']) -or
        @($Payload['Intended Branch IDs']).Count -lt 1 -or
        $Payload['Source Snapshot'] -isnot [Collections.IDictionary] -or
        $Payload['Shared Baseline'] -isnot [Collections.IDictionary] -or
        $Payload['Step Operation IDs'] -isnot [Collections.IDictionary]) {
        throw 'Fork recovery payload has an invalid identity, snapshot, baseline, or operation map.'
    }
}

function Get-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId)
    $ref = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $document = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'recovery.json'
    $recordId = Get-HandoffForkRecoveryId -TaskKey $TaskKey -ForkId $ForkId
    if ($document.schemaVersion -ne 1 -or $document.recordKind -cne 'fork-recovery' -or
        $document.taskKey -cne $TaskKey -or $document.forkId -cne $ForkId -or $document.recordId -cne $recordId -or
        [string]$document.status -cnotin @('Pending','Completed')) {
        throw 'The exact fork-recovery ref contains a mismatched identity or status.'
    }
    Assert-HandoffForkRecoveryPayload -Payload $document.payload
    return [pscustomobject]@{TaskKey=$TaskKey;ForkId=$ForkId;Status=[string]$document.status;
        Revision=$revision;Payload=$document.payload;Record=$document}
}

function Get-GitHandoffPendingForkRecoveries {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey)
    Assert-HandoffIdentity -TaskKey $TaskKey
    $prefix = "$($Adapter.RefPrefix)/recovery/$(Get-HandoffSha256 -Value $TaskKey)/"
    $lines = @(& git -C $Adapter.RepositoryRoot ls-remote $Adapter.RemoteName "$prefix*" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Pending fork-recovery envelopes could not be listed.' }
    $envelopes = [Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        $parts = ([string]$line) -split "`t", 2
        if ($parts.Count -ne 2 -or [string]$parts[0] -cnotmatch '^[0-9a-f]{40,64}$' -or
            -not ([string]$parts[1]).StartsWith($prefix,[StringComparison]::Ordinal)) {
            throw 'Fork-recovery envelope listing returned an invalid ref.'
        }
        $document = Read-GitHandoffDocument -Adapter $Adapter -Ref ([string]$parts[1]) -Revision ([string]$parts[0]) -FileName 'recovery.json'
        if ($document.taskKey -cne $TaskKey -or $document.recordKind -cne 'fork-recovery') {
            throw 'Fork-recovery envelope does not match its Task Key.'
        }
        if ([string]$document.status -ceq 'Pending') {
            $envelopes.Add([pscustomobject]@{TaskKey=$TaskKey;ForkId=[string]$document.forkId;
                Status='Pending';Revision=[string]$parts[0]})
        }
    }
    return $envelopes.ToArray()
}

function New-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId,[Parameter(Mandatory = $true)] $Payload,
        [Parameter(Mandatory = $true)][string] $OperationId,[string] $Actor='configured-adapter')
    Assert-HandoffOperationId -OperationId $OperationId
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'Fork recovery creation requires the actual writer actor.' }
    Assert-HandoffForkRecoveryPayload -Payload $Payload
    $recordId = Get-HandoffForkRecoveryId -TaskKey $TaskKey -ForkId $ForkId
    $digest = Get-HandoffSha256 -Value (([ordered]@{taskKey=$TaskKey;forkId=$ForkId;payload=$Payload;
        operationId=$OperationId;actor=$Actor}) | ConvertTo-Json -Compress -Depth 50)
    $existing = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -ne $existing) {
        if ($existing.Record.creationOperationId -cne $OperationId -or $existing.Record.payloadDigest -cne $digest) {
            throw 'A different fork-recovery operation already owns this Task Key and Fork ID.'
        }
        return $existing
    }
    $document = [ordered]@{schemaVersion=1;recordKind='fork-recovery';recordId=$recordId;taskKey=$TaskKey;
        forkId=$ForkId;status='Pending';payload=$Payload;creationOperationId=$OperationId;payloadDigest=$digest;
        actor=$Actor;createdAt=[DateTimeOffset]::UtcNow.ToString('o');completionOperationId=$null;completedAt=$null}
    $ref = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document -FileName 'recovery.json'
    Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision '' -Commit $commit | Out-Null
    $readback = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $readback -or $readback.Revision -cne $commit -or $readback.Record.payloadDigest -cne $digest) {
        throw "Fork recovery '$ForkId' creation was not read back."
    }
    return $readback
}

function Complete-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId,[Parameter(Mandatory = $true)][string] $ExpectedRevision,
        [Parameter(Mandatory = $true)][string] $OperationId)
    Assert-HandoffOperationId -OperationId $OperationId
    $current = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $current) { throw 'The exact fork-recovery record was not found.' }
    if ($current.Status -ceq 'Completed') {
        if ($current.Record.completionOperationId -cne $OperationId) { throw 'Fork recovery is already completed by another operation.' }
        return $current
    }
    if ($current.Revision -cne $ExpectedRevision) { throw 'Conditional fork-recovery revision conflict.' }
    $document = $current.Record
    $document.status = 'Completed'
    $document.completionOperationId = $OperationId
    $document.completedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $ref = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document -Parent $current.Revision -FileName 'recovery.json'
    Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision $current.Revision -Commit $commit | Out-Null
    $readback = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($readback.Revision -cne $commit -or $readback.Status -cne 'Completed' -or
        $readback.Record.completionOperationId -cne $OperationId) { throw "Fork recovery '$ForkId' completion was not read back." }
    return $readback
}

function New-GitHandoffAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $RepositoryRoot,[string] $RemoteName='origin',[string] $RefPrefix='refs/heads/handoff-v1')
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $adapter = [pscustomobject]@{ RepositoryRoot=$root; RemoteName=$RemoteName; RefPrefix=$RefPrefix }
    Assert-GitAdapter -Adapter $adapter
    & git -C $root rev-parse --git-dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The selected local Git object store is not a repository.' }
    & git -C $root remote get-url $RemoteName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The selected Git storage remote is not configured.' }
    return $adapter
}

function Get-OperationPayloadDigest {
    param([string] $RecordKind,[string] $TaskKey,[string] $BranchId,[Parameter(Mandatory = $true)] $Changes,
        [string] $Actor='configured-adapter',[string] $Reason='initial checkpoint',[bool] $DecisionConfirmed=$false,
        [string] $DecisionCommonRevision)
    $payload = [ordered]@{ recordKind=$RecordKind; taskKey=$TaskKey; branchId=$BranchId;
        changes=$Changes;actor=$Actor;reason=$Reason;decisionConfirmed=$DecisionConfirmed }
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        $payload.decisionCommonRevision = $DecisionCommonRevision
    }
    return Get-HandoffSha256 -Value ($payload | ConvertTo-Json -Compress -Depth 50)
}

function Get-HandoffIntegrationStatus {
    param([Parameter(Mandatory = $true)][string] $RecordKind,
        [Parameter(Mandatory = $true)][string] $Field,[bool] $DecisionConfirmed=$false)
    if ($Field -ceq 'Active Branches') { return 'structural-index' }
    if ($RecordKind -eq 'branch' -and $Field -ceq 'Branch Outcome' -and $DecisionConfirmed) {
        return 'user-confirmed-branch-outcome'
    }
    if ($RecordKind -eq 'branch') { return 'branch-only' }
    if ($DecisionConfirmed) { return 'user-confirmed-common' }
    return 'common-checkpoint'
}

function New-HandoffOperation {
    param([string] $PayloadDigest,[string] $OperationId,[Parameter(Mandatory = $true)][array] $ChangedFields,
        [Parameter(Mandatory = $true)][string] $RecordKind,[Parameter(Mandatory = $true)][string] $RecordId,
        [Parameter(Mandatory = $true)] $Source,[string] $Actor='configured-adapter',
        [string] $Reason='initial checkpoint',[bool] $DecisionConfirmed=$false,[string] $DecisionCommonRevision,
        [switch] $Internal)
    Assert-HandoffOperationId -OperationId $OperationId -Internal:$Internal
    $occurredAt = [DateTimeOffset]::UtcNow.ToString('o')
    $eventIntents = @(
        foreach ($change in $ChangedFields) {
            $field = [string]$change.field
            $intent = [ordered]@{
                operationId = $OperationId
                recordId = $RecordId
                field = $field
                previousState = $change.previous
                newState = $change.new
                actor = $Actor
                occurredAt = $occurredAt
                reason = $Reason
                source = $Source
                integrationStatus = Get-HandoffIntegrationStatus -RecordKind $RecordKind -Field $field `
                    -DecisionConfirmed $DecisionConfirmed
            }
            if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
                $intent.decisionCommonRevision = $DecisionCommonRevision
            }
            $intent
        }
    )
    $operation = [ordered]@{
        id = $OperationId
        payloadDigest = $PayloadDigest
        changedFields = $ChangedFields
        eventIntents = $eventIntents
        occurredAt = $occurredAt
        actor = $Actor
        reason = $Reason
        decisionConfirmed = $DecisionConfirmed
    }
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        $operation.decisionCommonRevision = $DecisionCommonRevision
    }
    return $operation
}

function Get-HandoffFieldValue {
    param([Parameter(Mandatory = $true)] $Record,[Parameter(Mandatory = $true)][string] $Field)
    if ($Field -ceq 'Active Branches') { return ,@($Record.activeBranches) }
    return $Record.fields[$Field]
}

function Test-HandoffValueEqual {
    param($Left,$Right)
    # Pipeline enumeration loses the distinction between an empty collection and null,
    # and unwraps a one-item Active index. Compare the actual stored JSON values.
    return ((ConvertTo-Json -InputObject $Left -Compress -Depth 50) -ceq
        (ConvertTo-Json -InputObject $Right -Compress -Depth 50))
}

function Assert-HandoffFieldsSafe {
    param([Parameter(Mandatory = $true)] $Fields,[string] $RecordKind,[switch] $DecisionConfirmed)
    if ($Fields -isnot [Collections.IDictionary]) { throw 'Changed Handoff fields must be an ordered mapping.' }
    $canonicalFields = @('Task Key','Branch ID','Fork Point','Intent','Scope','Current','Source','Lifecycle',
        'Work State','Branch Outcome','Active Branches','Last Activity At','Keep Active Until','Conflict',
        'Candidate Conclusion','Applicability Scope','Fork Baselines','Integrated Decisions')
    foreach ($name in $Fields.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$name) -or [string]$name -match '(?i)password|token|secret|private.?key') {
            throw 'A Handoff field has an empty or sensitive name; do not store credentials.'
        }
        $canonicalName = @($canonicalFields | Where-Object {
            [StringComparer]::OrdinalIgnoreCase.Equals([string]$_,[string]$name)
        }) | Select-Object -First 1
        if ($null -ne $canonicalName -and -not [StringComparer]::Ordinal.Equals([string]$canonicalName,[string]$name)) {
            throw "Canonical Handoff field '$canonicalName' must use its exact spelling and case."
        }
        $value = $Fields[$name]
        if ([string]$name -ceq 'Lifecycle' -and [string]$value -cnotin @('Active','Archived')) {
            throw 'Lifecycle must be Active or Archived.'
        }
        if ([string]$name -ceq 'Work State' -and [string]$value -cnotin @('Running','Awaiting Review','Interrupted','Blocked','Failed')) {
            throw 'Work State is outside the Task Handoff v1 contract.'
        }
        if ([string]$name -ceq 'Branch Outcome') {
            if ($RecordKind -cne 'branch' -or [string]$value -cnotin @('Selected','Partially Selected','Superseded') -or -not $DecisionConfirmed) {
                throw 'Branch Outcome requires a selected branch outcome after an explicit user decision and common readback.'
            }
        }
    }
}

function Assert-HandoffRequiredFields {
    param([Parameter(Mandatory = $true)] $Fields,[Parameter(Mandatory = $true)][ValidateSet('common','branch')][string] $RecordKind)
    $required = if ($RecordKind -eq 'common') {
        @('Task Key','Intent','Scope','Current','Source','Lifecycle','Work State')
    }
    else {
        @('Task Key','Branch ID','Fork Point','Current','Source','Lifecycle','Work State')
    }
    foreach ($field in $required) {
        if (-not $Fields.Contains($field) -or $null -eq $Fields[$field] -or
            ($Fields[$field] -is [string] -and [string]::IsNullOrWhiteSpace([string]$Fields[$field]))) {
            throw "Required Handoff field '$field' is absent or empty."
        }
    }
}

function Get-GitHandoffOperationOrigin {
    param($Adapter,[Parameter(Mandatory = $true)] $Current,[string] $OperationId)
    $history = @(& git -C $Adapter.RepositoryRoot rev-list --first-parent $Current.Revision 2>$null)
    if ($LASTEXITCODE -ne 0 -or $history.Count -eq 0) { throw 'The operation record history could not be verified.' }
    $origin = $null
    foreach ($revision in $history) {
        if ([string]$revision -cnotmatch '^[0-9a-f]{40,64}$') { throw 'The operation record history contains an invalid revision.' }
        $text = @(& git -C $Adapter.RepositoryRoot show "${revision}:record.json" 2>$null) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'A historical operation record is unreadable.' }
        try { $snapshot = $text | ConvertFrom-Json -AsHashtable -Depth 50 }
        catch { throw 'A historical operation record is not valid JSON.' }
        if ($null -eq $snapshot.operations[$OperationId]) { break }
        if ($snapshot.recordId -cne $Current.Record.recordId -or $snapshot.operations[$OperationId].payloadDigest -cne $Current.Record.operations[$OperationId].payloadDigest) {
            throw 'An operation record changed identity or payload in Git history.'
        }
        $origin = [pscustomobject]@{Revision=[string]$revision;Record=$snapshot}
    }
    if ($null -eq $origin) { throw "The first record revision for Operation ID '$OperationId' is missing." }
    foreach ($change in @($origin.Record.operations[$OperationId].changedFields)) {
        $stored = Get-HandoffFieldValue -Record $origin.Record -Field ([string]$change.field)
        if (-not (Test-HandoffValueEqual -Left $stored -Right $change.new)) {
            throw "The original operation commit did not contain field '$($change.field)' result."
        }
    }
    return $origin
}

function Get-GitHandoffEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][ValidateSet('common','branch')][string] $RecordKind,
        [string] $BranchId,[Parameter(Mandatory = $true)][string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Field)
    $ref = Get-HandoffEventRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId -Field $Field
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $event = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'event.json'
    $recordId = Get-HandoffRecordId -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($event.schemaVersion -ne 1 -or $event.TaskKey -cne $TaskKey -or $event.RecordId -cne $recordId -or
        $event.RecordKind -cne $RecordKind -or $event.BranchId -cne $BranchId -or
        $event.OperationId -cne $OperationId -or $event.Field -cne $Field) {
        throw 'The exact event ref contains a mismatched immutable field identity.'
    }
    return [pscustomobject]$event
}

function Write-GitHandoffEventIfAbsent {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $OperationId,
        [Parameter(Mandatory = $true)] $Intent,[string] $RecordRevision,[string] $PayloadDigest)
    $field = [string]$Intent.field
    $recordId = [string]$Intent.recordId
    $ref = Get-HandoffEventRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId -Field $field
    $expected = [ordered]@{
        schemaVersion = 1
        TaskKey = $TaskKey
        RecordKind = $RecordKind
        RecordId = $recordId
        BranchId = $BranchId
        OperationId = $OperationId
        Field = $field
        PreviousState = $Intent.previousState
        NewState = $Intent.newState
        OccurredAt = [string]$Intent.occurredAt
        Actor = [string]$Intent.actor
        Reason = [string]$Intent.reason
        Source = $Intent.source
        RecordRevision = $RecordRevision
        IntegrationStatus = [string]$Intent.integrationStatus
        ReadbackResult = 'verified'
        PayloadDigest = $PayloadDigest
    }
    if ($Intent -is [Collections.IDictionary] -and $Intent.Contains('decisionCommonRevision') -and
        -not [string]::IsNullOrWhiteSpace([string]$Intent['decisionCommonRevision'])) {
        $expected.DecisionCommonRevision = [string]$Intent['decisionCommonRevision']
    }
    $existing = Get-GitHandoffEvent -Adapter $Adapter -TaskKey $TaskKey -RecordKind $RecordKind -BranchId $BranchId -OperationId $OperationId -Field $field
    if ($null -ne $existing) {
        $existingComparable = [ordered]@{
            schemaVersion=$existing.schemaVersion;TaskKey=$existing.TaskKey;RecordKind=$existing.RecordKind;RecordId=$existing.RecordId;
            BranchId=$existing.BranchId;OperationId=$existing.OperationId;Field=$existing.Field;PreviousState=$existing.PreviousState;
            NewState=$existing.NewState;OccurredAt=$existing.OccurredAt;Actor=$existing.Actor;Reason=$existing.Reason;
            Source=$existing.Source;RecordRevision=$existing.RecordRevision;IntegrationStatus=$existing.IntegrationStatus;
            ReadbackResult=$existing.ReadbackResult;PayloadDigest=$existing.PayloadDigest
        }
        if ($null -ne $existing.PSObject.Properties['DecisionCommonRevision']) {
            $existingComparable.DecisionCommonRevision = $existing.DecisionCommonRevision
        }
        if (-not (Test-HandoffValueEqual -Left $expected -Right $existingComparable)) {
            throw "Event identity '$OperationId/$field' already exists with different content."
        }
        return $existing
    }
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $expected -FileName 'event.json'
    Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision '' -Commit $commit | Out-Null
    $readback = Get-GitHandoffEvent -Adapter $Adapter -TaskKey $TaskKey -RecordKind $RecordKind -BranchId $BranchId -OperationId $OperationId -Field $field
    if ($null -eq $readback -or $readback.PayloadDigest -cne $PayloadDigest -or $readback.ReadbackResult -cne 'verified') {
        throw "Event '$OperationId/$field' could not be read back. Retain the pending event key."
    }
    return $readback
}

function Complete-GitHandoffEvents {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $OperationId)
    $current = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $current) { throw "Record missing while reconciling Operation ID '$OperationId'." }
    $origin = Get-GitHandoffOperationOrigin -Adapter $Adapter -Current $current -OperationId $OperationId
    $operation = $origin.Record.operations[$OperationId]
    if ($null -eq $operation) { throw "Operation ID '$OperationId' was not persisted in the record." }
    $recordId = Get-HandoffRecordId -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $changes = @($operation.changedFields)
    $intents = @($operation.eventIntents)
    if ($intents.Count -ne $changes.Count) { throw "Operation ID '$OperationId' does not contain one durable event intent per changed field." }
    foreach ($change in $changes) {
        $field = [string]$change.field
        $matchingIntents = @($intents | Where-Object { [string]$_.field -ceq $field })
        if ($matchingIntents.Count -ne 1) { throw "Operation ID '$OperationId' has an ambiguous durable event intent for field '$field'." }
        $intent = $matchingIntents[0]
        if ([string]$intent.operationId -cne $OperationId -or [string]$intent.recordId -cne $recordId -or
            -not (Test-HandoffValueEqual -Left $intent.previousState -Right $change.previous) -or
            -not (Test-HandoffValueEqual -Left $intent.newState -Right $change.new)) {
            throw "Operation ID '$OperationId' durable event intent does not match field '$field'."
        }
        try {
            Write-GitHandoffEventIfAbsent -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId `
                -Intent $intent -RecordRevision $origin.Revision -PayloadDigest $operation.payloadDigest | Out-Null
        }
        catch { throw "Operation ID '$OperationId' committed its record, but field event '$field' is pending or unverified: $($_.Exception.Message)" }
    }
    return $current
}

function Complete-GitHandoffInternalEvents {
    param($Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $Purpose,
        [Parameter(Mandatory = $true)][string] $ParentOperationId,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [string[]] $AdditionalOperationIds=@())
    $current = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
    if ($null -eq $current) { throw 'The common record disappeared while reconciling internal events.' }
    $scopePrefix = Get-HandoffInternalOperationScopePrefix -Purpose $Purpose -ParentOperationId $ParentOperationId `
        -BranchId $BranchId
    $ids = [Collections.Generic.List[string]]::new()
    foreach ($operationKey in @($current.Record.operations.Keys)) {
        $candidate = [string]$operationKey
        if ($candidate.StartsWith($scopePrefix,[StringComparison]::Ordinal) -and -not $ids.Contains($candidate)) {
            $ids.Add($candidate)
        }
    }
    foreach ($candidate in @($AdditionalOperationIds)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            $candidate.StartsWith($scopePrefix,[StringComparison]::Ordinal) -and
            $null -ne $current.Record.operations[$candidate] -and -not $ids.Contains($candidate)) {
            $ids.Add($candidate)
        }
    }
    foreach ($candidate in $ids) {
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -OperationId $candidate | Out-Null
    }
    return $ids.ToArray()
}

function Get-GitHandoffCommon {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey)
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
    if ($null -eq $read) { return $null }
    return [pscustomobject]@{
        TaskKey=$read.Record.taskKey;RecordId=$read.Record.recordId;Revision=$read.Revision;
        Fields=$read.Record.fields;ActiveBranches=@($read.Record.activeBranches);
        LastActivityAt=$read.Record.lastActivityAt
    }
}

function Get-GitHandoffBranch {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId)
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $read) { return $null }
    return [pscustomobject]@{
        TaskKey=$read.Record.taskKey;BranchId=$read.Record.branchId;ForkPoint=$read.Record.forkPoint;
        RecordId=$read.Record.recordId;Revision=$read.Revision;Fields=$read.Record.fields;
        LastActivityAt=$read.Record.lastActivityAt
    }
}

function Assert-GitHandoffDecisionCommonRevision {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ExpectedRevision,[switch] $AllowStructuralDescendant)
    if ($ExpectedRevision -cnotmatch '^[0-9a-f]{40,64}$') { throw 'A verified common decision revision is required.' }
    $current = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
    if ($null -eq $current) { throw 'The common decision record is missing.' }
    if ($current.Revision -ceq $ExpectedRevision) { return $current }
    if (-not $AllowStructuralDescendant) {
        throw 'The common decision revision changed before branch finalization; reconcile from the current decision.'
    }
    & git -C $Adapter.RepositoryRoot merge-base --is-ancestor $ExpectedRevision $current.Revision 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'The bound common decision revision is not an ancestor of current common state.' }
    $text = @(& git -C $Adapter.RepositoryRoot show "${ExpectedRevision}:record.json" 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'The bound common decision revision cannot be read.' }
    try { $bound = $text | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw 'The bound common decision revision is not valid JSON.' }
    if ($bound.recordKind -cne 'common' -or $bound.taskKey -cne $TaskKey -or
        -not (Test-HandoffValueEqual -Left $bound.fields -Right $current.Record.fields)) {
        throw 'The common decision fields changed during branch finalization; reconcile from the current decision.'
    }
    return $current
}

function New-GitHandoffRecord {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $ForkPoint,
        [Parameter(Mandatory = $true)] $Fields,[string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Actor)
    Assert-HandoffOperationId -OperationId $OperationId
    Assert-HandoffFieldsSafe -Fields $Fields -RecordKind $RecordKind
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'A Handoff creation event requires the actual writer actor.' }
    $creationManagedFields = @($Fields.Keys | Where-Object {
        [string]$_ -ieq 'Active Branches' -or [string]$_ -ieq 'Last Activity At'
    })
    if ($creationManagedFields.Count -gt 0) {
        throw "Active Branches and Last Activity At are system-managed fields; create the record without caller values."
    }
    $recordId = Get-HandoffRecordId -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($RecordKind -eq 'branch' -and [string]::IsNullOrWhiteSpace($ForkPoint)) { throw 'Fork Point is required.' }
    $logicalFields = [ordered]@{ 'Task Key'=$TaskKey }
    if ($RecordKind -eq 'branch') {
        $logicalFields['Branch ID'] = $BranchId
        $logicalFields['Fork Point'] = $ForkPoint
    }
    foreach ($field in $Fields.Keys) {
        if ($logicalFields.Contains([string]$field)) { throw "A system identity field was duplicated: '$field'." }
        $logicalFields[[string]$field] = $Fields[$field]
    }
    Assert-HandoffRequiredFields -Fields $logicalFields -RecordKind $RecordKind
    if ($logicalFields.Lifecycle -cne 'Active') { throw 'A new Handoff record starts Active; exact Archived continuation uses restore.' }
    $payload = [ordered]@{ fields=$Fields;forkPoint=$ForkPoint }
    $digest = Get-OperationPayloadDigest -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -Changes $payload -Actor $Actor
    $old = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -ne $old) {
        $existingOp = $old.Record.operations[$OperationId]
        if ($null -eq $existingOp -or $existingOp.payloadDigest -cne $digest) {
            throw 'A different Handoff record or operation already owns this exact Task Key and Branch ID.'
        }
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
        return [pscustomobject]@{RecordId=$recordId;Revision=$old.Revision;Status='already-created'}
    }
    $changes = @(
        foreach ($field in $logicalFields.Keys) { [ordered]@{field=[string]$field;previous=$null;new=$logicalFields[$field]} }
    )
    $operation = New-HandoffOperation -PayloadDigest $digest -OperationId $OperationId -ChangedFields $changes `
        -RecordKind $RecordKind -RecordId $recordId -Source $logicalFields.Source -Actor $Actor
    $record = [ordered]@{
        schemaVersion=1;recordKind=$RecordKind;recordId=$recordId;taskKey=$TaskKey;
        branchId= $(if ($RecordKind -eq 'branch') { $BranchId } else { $null });
        forkPoint= $(if ($RecordKind -eq 'branch') { $ForkPoint } else { $null });
        fields=$logicalFields;activeBranches=@();lastActivityAt=$operation.occurredAt;
        operations=[ordered]@{ $OperationId=$operation }
    }
    $ref = Get-HandoffRecordRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $record -FileName 'record.json'
    Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision '' -Commit $commit | Out-Null
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $read -or $read.Revision -cne $commit -or $read.Record.operations[$OperationId].payloadDigest -cne $digest) {
        throw "Record creation for Operation ID '$OperationId' was not fully read back; retain the exact ID."
    }
    Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
    return [pscustomobject]@{RecordId=$recordId;Revision=$read.Revision;Status='created'}
}

function New-GitHandoffCommon {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)] $Fields,[Parameter(Mandatory = $true)][string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Actor)
    return New-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -Fields $Fields -OperationId $OperationId -Actor $Actor
}

function Invoke-GitHandoffFieldsMutation {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][ValidateSet('common','branch')][string] $RecordKind,
        [Parameter(Mandatory = $true)][string] $TaskKey,[string] $BranchId,
        [Parameter(Mandatory = $true)][string] $ExpectedRevision,[Parameter(Mandatory = $true)] $Changes,
        [Parameter(Mandatory = $true)][string] $OperationId,[switch] $SuppressActivity,[switch] $DecisionConfirmed,
        [string] $DecisionCommonRevision,[switch] $ExplicitContinuation,[string] $Actor='configured-adapter',
        [string] $Reason,[switch] $InternalOperation)
    Assert-HandoffOperationId -OperationId $OperationId -Internal:$InternalOperation
    Assert-HandoffFieldsSafe -Fields $Changes -RecordKind $RecordKind -DecisionConfirmed:$DecisionConfirmed
    if (@($Changes.Keys | Where-Object { $_ -cin @('Lifecycle','Work State','Branch Outcome') }).Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($Reason)) {
        throw 'A status transition requires a concrete reason and traceable Source.'
    }
    if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = 'field checkpoint with traceable Source' }
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'A Handoff field event requires an actor.' }
    if ($RecordKind -eq 'branch' -and [string]::IsNullOrWhiteSpace($BranchId)) { throw 'An exact Branch ID is required for its own record.' }
    $hasBranchOutcome = ($RecordKind -eq 'branch' -and $Changes.Contains('Branch Outcome'))
    if ($hasBranchOutcome -and [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        throw 'Branch Outcome requires the exact verified common decision revision.'
    }
    $isArchive = ($RecordKind -eq 'branch' -and $Changes.Contains('Lifecycle') -and
        [string]$Changes['Lifecycle'] -ceq 'Archived')
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision) -and
        ($RecordKind -ne 'branch' -or (-not $hasBranchOutcome -and -not $isArchive))) {
        throw 'A common decision revision may bind only Branch Outcome or branch archival.'
    }
    $digest = Get-OperationPayloadDigest -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -Changes $Changes `
        -Actor $Actor -Reason $Reason -DecisionConfirmed ([bool]$DecisionConfirmed) `
        -DecisionCommonRevision $DecisionCommonRevision
    $old = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $old) { throw 'The exact Handoff record could not be found; no replacement was created.' }
    $existingOp = $old.Record.operations[$OperationId]
    if ($null -ne $existingOp) {
        if ($existingOp.payloadDigest -cne $digest) { throw 'An Operation ID was reused with different changed fields.' }
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
            Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
        }
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
        return [pscustomobject]@{RecordId=$old.Record.recordId;Revision=$old.Revision;Status='already-applied';
            DecisionCommonRevision=$DecisionCommonRevision}
    }
    if ($old.Revision -cne $ExpectedRevision) { throw 'Conditional Handoff revision conflict; re-read formal authority and records.' }
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
            -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
    }
    if ($Changes.Contains('Lifecycle')) {
        if ($Changes.Lifecycle -ceq 'Archived' -and $Changes.Count -ne 1) {
            throw 'Archival changes Lifecycle alone and never refreshes material activity.'
        }
        if ($old.Record.fields.Lifecycle -ceq 'Archived' -and $Changes.Lifecycle -ceq 'Active' -and -not $ExplicitContinuation) {
            throw 'Only exact explicit continuation can restore an Archived Handoff.'
        }
        if ($RecordKind -eq 'common' -and $Changes.Lifecycle -ceq 'Archived' -and @($old.Record.activeBranches).Count -gt 0) {
            throw 'An indexed Active branch protects common; reconcile branch and index before common archival.'
        }
    }
    $newRecord = $old.Record
    $actualChanges = [Collections.Generic.List[object]]::new()
    foreach ($field in $Changes.Keys) {
        $fieldName = [string]$field
        if ($fieldName -ceq 'Active Branches' -and $RecordKind -ne 'common') { throw 'Only common may change the structural Active index.' }
        if ($fieldName -ceq 'Active Branches' -and -not $InternalOperation) {
            throw 'Active Branches may be changed only by adapter-owned branch lifecycle reconciliation.'
        }
        if ($fieldName -cin @('Task Key','Branch ID','Fork Point','Last Activity At')) { throw 'Handoff identity and activity cannot be replaced through changed fields.' }
        $previous = Get-HandoffFieldValue -Record $newRecord -Field $fieldName
        $next = $Changes[$field]
        if (Test-HandoffValueEqual -Left $previous -Right $next) { continue }
        $actualChanges.Add([ordered]@{field=$fieldName;previous=$previous;new=$next})
        if ($fieldName -ceq 'Active Branches') { $newRecord.activeBranches = @($next) }
        else { $newRecord.fields[$fieldName] = $next }
    }
    Assert-HandoffRequiredFields -Fields $newRecord.fields -RecordKind $RecordKind
    if ($actualChanges.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
            Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
        }
        return [pscustomobject]@{RecordId=$old.Record.recordId;Revision=$old.Revision;Status='no-op';
            DecisionCommonRevision=$DecisionCommonRevision}
    }
    $operation = New-HandoffOperation -PayloadDigest $digest -OperationId $OperationId -ChangedFields $actualChanges.ToArray() `
        -RecordKind $RecordKind -RecordId ([string]$old.Record.recordId) -Source $newRecord.fields.Source `
        -Actor $Actor -Reason $Reason -DecisionConfirmed ([bool]$DecisionConfirmed) `
        -DecisionCommonRevision $DecisionCommonRevision -Internal:$InternalOperation
    $newRecord.operations[$OperationId] = $operation
    $archiving = ($Changes.Contains('Lifecycle') -and [string]$Changes['Lifecycle'] -ceq 'Archived')
    if (-not $SuppressActivity -and -not $archiving -and
        @($actualChanges | Where-Object { $_.field -cne 'Active Branches' }).Count -gt 0) {
        $newRecord.lastActivityAt = $operation.occurredAt
    }
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $newRecord -Parent $old.Revision -FileName 'record.json'
    Push-GitHandoffIfRevision -Adapter $Adapter -Ref $old.Ref -ExpectedRevision $ExpectedRevision -Commit $commit | Out-Null
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $read -or $read.Revision -cne $commit -or $read.Record.operations[$OperationId].payloadDigest -cne $digest) {
        throw "Operation ID '$OperationId' may have committed, but record readback is unverified."
    }
    Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
            -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
    }
    return [pscustomobject]@{RecordId=$read.Record.recordId;Revision=$read.Revision;Status='updated';
        DecisionCommonRevision=$DecisionCommonRevision}
}

function Set-GitHandoffFields {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][ValidateSet('common','branch')][string] $RecordKind,
        [Parameter(Mandatory = $true)][string] $TaskKey,[string] $BranchId,
        [Parameter(Mandatory = $true)][string] $ExpectedRevision,[Parameter(Mandatory = $true)] $Changes,
        [Parameter(Mandatory = $true)][string] $OperationId,[switch] $SuppressActivity,[switch] $DecisionConfirmed,
        [string] $DecisionCommonRevision,[switch] $ExplicitContinuation,[string] $Actor='configured-adapter',[string] $Reason)
    return Invoke-GitHandoffFieldsMutation -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey `
        -BranchId $BranchId -ExpectedRevision $ExpectedRevision -Changes $Changes -OperationId $OperationId `
        -SuppressActivity:$SuppressActivity -DecisionConfirmed:$DecisionConfirmed -DecisionCommonRevision $DecisionCommonRevision `
        -ExplicitContinuation:$ExplicitContinuation `
        -Actor $Actor -Reason $Reason
}

function New-GitHandoffBranch {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,[Parameter(Mandatory = $true)][string] $ForkPoint,
        [Parameter(Mandatory = $true)] $Fields,[Parameter(Mandatory = $true)][string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Actor)
    $initialCommon = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
    if ($null -eq $initialCommon) { throw 'Branch creation requires the exact common Task Key.' }
    if ($initialCommon.Fields.Lifecycle -cne 'Active') {
        throw 'Branch creation requires an Active common record; restore the exact common by explicit continuation first.'
    }
    New-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId `
        -ForkPoint $ForkPoint -Fields $Fields -OperationId $OperationId -Actor $Actor | Out-Null
    $indexOperationIds = [Collections.Generic.List[string]]::new()
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $branchRecord = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
        $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
        if ($null -eq $branchRecord -or $null -eq $common) {
            throw 'The exact common or newly created branch disappeared during index reconciliation.'
        }
        $effectiveLifecycle = [string]$branchRecord.Fields.Lifecycle
        $shouldBeIndexed = ($effectiveLifecycle -ceq 'Active')
        if ($shouldBeIndexed -and $common.Fields.Lifecycle -cne 'Active') {
            throw "Branch '$BranchId' is durable but cannot be indexed under an Archived common record; restore common explicitly and retry the exact operation."
        }
        $indexOperationId = Get-HandoffInternalOperationId -Purpose 'branch-create-index' -TaskKey $TaskKey `
            -BranchId $BranchId -ParentOperationId $OperationId `
            -Binding "$($branchRecord.Revision)|${effectiveLifecycle}"
        if (-not $indexOperationIds.Contains($indexOperationId)) { $indexOperationIds.Add($indexOperationId) }
        $indexed = ($common.ActiveBranches -ccontains $BranchId)
        if ($indexed -eq $shouldBeIndexed) {
            $verifiedBranch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
            $verifiedCommon = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
            if ($verifiedBranch.Revision -cne $branchRecord.Revision -or
                ([string]$verifiedBranch.Fields.Lifecycle -ceq 'Active') -ne $shouldBeIndexed -or
                (($verifiedCommon.ActiveBranches -ccontains $BranchId) -ne $shouldBeIndexed)) {
                continue
            }
            $completedIndexIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                -Purpose 'branch-create-index' -ParentOperationId $OperationId -BranchId $BranchId `
                -AdditionalOperationIds $indexOperationIds.ToArray())
            return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$verifiedBranch.Revision;CommonRevision=$verifiedCommon.Revision;
                Lifecycle=$effectiveLifecycle;Indexed=$shouldBeIndexed;
                IndexOperationId=$(if ($completedIndexIds -ccontains $indexOperationId) { $indexOperationId } else { $null });
                IndexOperationIds=$completedIndexIds}
        }
        if ($shouldBeIndexed) { $newIndex = @($common.ActiveBranches) + @($BranchId) }
        else { $newIndex = @($common.ActiveBranches | Where-Object { $_ -cne $BranchId }) }
        $observedBranchRevision = [string]$branchRecord.Revision
        try {
            $index = Invoke-GitHandoffFieldsMutation -Adapter $Adapter -RecordKind common -TaskKey $TaskKey `
                -ExpectedRevision $common.Revision -Changes ([ordered]@{'Active Branches'=$newIndex}) `
                -OperationId $indexOperationId -SuppressActivity -Actor $Actor `
                -Reason 'reconcile exact peer index after branch creation' -InternalOperation
            $verifiedBranch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
            $verifiedCommon = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
            if ($verifiedBranch.Revision -ceq $observedBranchRevision -and
                ([string]$verifiedBranch.Fields.Lifecycle -ceq 'Active') -eq $shouldBeIndexed -and
                (($verifiedCommon.ActiveBranches -ccontains $BranchId) -eq $shouldBeIndexed)) {
                $completedIndexIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                    -Purpose 'branch-create-index' -ParentOperationId $OperationId -BranchId $BranchId `
                    -AdditionalOperationIds $indexOperationIds.ToArray())
                return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$verifiedBranch.Revision;
                    CommonRevision=$verifiedCommon.Revision;Lifecycle=$effectiveLifecycle;Indexed=$shouldBeIndexed;
                    IndexOperationId=$indexOperationId;IndexOperationIds=$completedIndexIds}
            }
        }
        catch { if ($attempt -eq 5) { throw "Branch '$BranchId' is durable but its lifecycle/index reconciliation is pending; retain Operation ID '$OperationId': $($_.Exception.Message)" } }
    }
    throw "Branch '$BranchId' lifecycle and common Active index were not jointly verified after creation; retain its exact ID and Operation ID '$OperationId'."
}

function Set-GitHandoffBranchLifecycle {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [Parameter(Mandatory = $true)][ValidateSet('Active','Archived')][string] $Lifecycle,
        [Parameter(Mandatory = $true)][string] $OperationId,[switch] $ExplicitContinuation,
        [string] $DecisionCommonRevision,[string] $Actor='configured-adapter',[string] $Reason)
    Assert-HandoffOperationId -OperationId $OperationId
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision) -and $Lifecycle -cne 'Archived') {
        throw 'A common decision revision may bind only branch archival, not restoration.'
    }
    if ($Lifecycle -ceq 'Active' -and -not $ExplicitContinuation) {
        throw 'Only exact explicit continuation can restore an archived branch.'
    }
    if ([string]::IsNullOrWhiteSpace($Reason)) {
        $Reason = if ($Lifecycle -ceq 'Archived') { 'archive the exact peer after the validated Gate' }
            else { 'restore the exact peer on explicit continuation' }
    }
    $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
    $branch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $common -or $null -eq $branch) { throw 'The exact common or branch record is missing; no lifecycle write was made.' }
    $indexOperationIds = [Collections.Generic.List[string]]::new()
    $commonRestoreOperationIds = [Collections.Generic.List[string]]::new()
    if ($Lifecycle -ceq 'Active' -and $common.Fields.Lifecycle -ceq 'Archived') {
        $commonRestoreOperationId = Get-HandoffInternalOperationId -Purpose 'common-restore' -TaskKey $TaskKey `
            -BranchId $BranchId -ParentOperationId $OperationId -Binding "$($common.Revision)|$($branch.Revision)"
        $commonRestoreOperationIds.Add($commonRestoreOperationId)
        Invoke-GitHandoffFieldsMutation -Adapter $Adapter -RecordKind common -TaskKey $TaskKey `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{Lifecycle='Active'}) `
            -OperationId $commonRestoreOperationId -ExplicitContinuation -Actor $Actor `
            -Reason 'restore exact common before peer continuation' -InternalOperation | Out-Null
        $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
        if ($common.Fields.Lifecycle -cne 'Active') { throw 'The exact common restore was not read back; retain the operation ID.' }
    }
    if ($branch.Fields.Lifecycle -cne $Lifecycle) {
        Set-GitHandoffFields -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId -ExpectedRevision $branch.Revision `
            -Changes ([ordered]@{Lifecycle=$Lifecycle}) -OperationId $OperationId -SuppressActivity:($Lifecycle -ceq 'Archived') `
            -DecisionCommonRevision $DecisionCommonRevision -ExplicitContinuation:$ExplicitContinuation `
            -Actor $Actor -Reason $Reason | Out-Null
    }
    else {
        $existing = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId
        $existingOperation = $existing.Record.operations[$OperationId]
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision) -and $null -eq $existingOperation) {
            throw 'The branch already has the requested lifecycle but no matching decision-bound operation; reconcile explicitly.'
        }
        if ($null -ne $existingOperation) {
            $lifecycleChanges = @($existingOperation.changedFields | Where-Object {
                [string]$_.field -ceq 'Lifecycle' -and [string]$_.new -ceq $Lifecycle
            })
            if ($lifecycleChanges.Count -ne 1) {
                throw 'The supplied lifecycle Operation ID does not own this branch lifecycle transition.'
            }
            if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
                if (-not ($existingOperation -is [Collections.IDictionary]) -or
                    -not $existingOperation.Contains('decisionCommonRevision') -or
                    [string]$existingOperation['decisionCommonRevision'] -cne $DecisionCommonRevision) {
                    throw 'The existing branch lifecycle operation is not bound to the supplied common decision revision.'
                }
                $expectedArchiveDigest = Get-OperationPayloadDigest -RecordKind branch -TaskKey $TaskKey `
                    -BranchId $BranchId -Changes ([ordered]@{Lifecycle=$Lifecycle}) -Actor $Actor `
                    -Reason $Reason -DecisionCommonRevision $DecisionCommonRevision
                if ([string]$existingOperation.payloadDigest -cne $expectedArchiveDigest) {
                    throw 'A decision-bound lifecycle retry must retain its original actor and reason.'
                }
                Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                    -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
            }
            Complete-GitHandoffEvents -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey `
                -BranchId $BranchId -OperationId $OperationId | Out-Null
        }
    }
    $branch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $branch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
        $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
        if ($null -eq $branch -or $null -eq $common) { throw 'The exact common or branch record disappeared during lifecycle reconciliation.' }
        $effectiveLifecycle = [string]$branch.Fields.Lifecycle
        $shouldBeIndexed = ($effectiveLifecycle -ceq 'Active')
        $indexOperationId = Get-HandoffInternalOperationId -Purpose 'branch-lifecycle-index' -TaskKey $TaskKey `
            -BranchId $BranchId -ParentOperationId $OperationId -Binding "$($branch.Revision)|${effectiveLifecycle}"
        if (-not $indexOperationIds.Contains($indexOperationId)) { $indexOperationIds.Add($indexOperationId) }
        if ($shouldBeIndexed -and $common.Fields.Lifecycle -cne 'Active') {
            $commonRestoreOperationId = Get-HandoffInternalOperationId -Purpose 'common-restore' -TaskKey $TaskKey `
                -BranchId $BranchId -ParentOperationId $OperationId -Binding "$($common.Revision)|$($branch.Revision)"
            if (-not $commonRestoreOperationIds.Contains($commonRestoreOperationId)) {
                $commonRestoreOperationIds.Add($commonRestoreOperationId)
            }
            try {
                Invoke-GitHandoffFieldsMutation -Adapter $Adapter -RecordKind common -TaskKey $TaskKey `
                    -ExpectedRevision $common.Revision -Changes ([ordered]@{Lifecycle='Active'}) `
                    -OperationId $commonRestoreOperationId -ExplicitContinuation -Actor $Actor `
                    -Reason 'restore exact common before peer index reconciliation' -InternalOperation | Out-Null
                $restoredCommon = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
                if ($restoredCommon.Fields.Lifecycle -cne 'Active') {
                    throw 'The exact common restore was not read back before branch indexing.'
                }
                continue
            }
            catch {
                if ($attempt -eq 5) {
                    throw "Branch '$BranchId' is Active but common restore is pending; retain Operation ID '$OperationId': $($_.Exception.Message)"
                }
                continue
            }
        }
        $indexed = ($common.ActiveBranches -ccontains $BranchId)
        if ($indexed -eq $shouldBeIndexed) {
            if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
                Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                    -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
            }
            $completedIndexIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                -Purpose 'branch-lifecycle-index' -ParentOperationId $OperationId `
                -BranchId $BranchId -AdditionalOperationIds $indexOperationIds.ToArray())
            $completedRestoreIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                -Purpose 'common-restore' -ParentOperationId $OperationId `
                -BranchId $BranchId -AdditionalOperationIds $commonRestoreOperationIds.ToArray())
            return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$branch.Revision;CommonRevision=$common.Revision;
                Lifecycle=$effectiveLifecycle;Indexed=$indexed;IndexOperationIds=$completedIndexIds;
                CommonRestoreOperationIds=$completedRestoreIds;DecisionCommonRevision=$DecisionCommonRevision}
        }
        if ($shouldBeIndexed) { $newIndex = @($common.ActiveBranches) + @($BranchId) }
        else { $newIndex = @($common.ActiveBranches | Where-Object { $_ -cne $BranchId }) }
        $observedBranchRevision = [string]$branch.Revision
        try {
            Invoke-GitHandoffFieldsMutation -Adapter $Adapter -RecordKind common -TaskKey $TaskKey `
                -ExpectedRevision $common.Revision -Changes ([ordered]@{'Active Branches'=$newIndex}) `
                -OperationId $indexOperationId -SuppressActivity -Actor $Actor `
                -Reason 'reconcile exact peer Active index after lifecycle change' -InternalOperation | Out-Null
            $verifiedBranch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
            $verifiedCommon = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
            if ($verifiedBranch.Revision -ceq $observedBranchRevision -and
                (($verifiedCommon.ActiveBranches -ccontains $BranchId) -eq $shouldBeIndexed) -and
                (-not $shouldBeIndexed -or $verifiedCommon.Fields.Lifecycle -ceq 'Active')) {
                if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
                    Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                        -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
                }
                $completedIndexIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                    -Purpose 'branch-lifecycle-index' -ParentOperationId $OperationId `
                    -BranchId $BranchId -AdditionalOperationIds $indexOperationIds.ToArray())
                $completedRestoreIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                    -Purpose 'common-restore' -ParentOperationId $OperationId `
                    -BranchId $BranchId -AdditionalOperationIds $commonRestoreOperationIds.ToArray())
                return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$verifiedBranch.Revision;
                    CommonRevision=$verifiedCommon.Revision;Lifecycle=$effectiveLifecycle;Indexed=$shouldBeIndexed;
                    IndexOperationIds=$completedIndexIds;CommonRestoreOperationIds=$completedRestoreIds;
                    DecisionCommonRevision=$DecisionCommonRevision}
            }
        }
        catch {
            if ($attempt -eq 5) {
                throw "Branch '$BranchId' lifecycle is durable but common index reconciliation is pending; retain Operation ID '$OperationId': $($_.Exception.Message)"
            }
        }
    }
    throw "Branch '$BranchId' common Active index was not verified; retain Operation ID '$OperationId'."
}

Export-ModuleMember -Function New-GitHandoffAdapter,Get-GitHandoffCommon,Get-GitHandoffBranch,Get-GitHandoffEvent,
    Get-GitHandoffForkRecovery,Get-GitHandoffPendingForkRecoveries,New-GitHandoffForkRecovery,Complete-GitHandoffForkRecovery,
    New-GitHandoffCommon,New-GitHandoffBranch,Set-GitHandoffFields,Set-GitHandoffBranchLifecycle
