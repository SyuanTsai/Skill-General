# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest
$script:HandoffIndexLock = [object]::new()

function Get-HandoffSha256 {
    param([Parameter(Mandatory = $true)][string] $Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
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
    param($Adapter,[Parameter(Mandatory = $true)] $Document,[string] $Parent,[ValidateSet('record.json','event.json')][string] $FileName)
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
        [string] $Actor='configured-adapter',[string] $Reason='initial checkpoint',[bool] $DecisionConfirmed=$false)
    $payload = [ordered]@{ recordKind=$RecordKind; taskKey=$TaskKey; branchId=$BranchId;
        changes=$Changes;actor=$Actor;reason=$Reason;decisionConfirmed=$DecisionConfirmed }
    return Get-HandoffSha256 -Value ($payload | ConvertTo-Json -Compress -Depth 50)
}

function New-HandoffOperation {
    param([string] $PayloadDigest,[string] $OperationId,[Parameter(Mandatory = $true)][array] $ChangedFields,
        [string] $Actor='configured-adapter',[string] $Reason='initial checkpoint',[bool] $DecisionConfirmed=$false)
    if ([string]::IsNullOrWhiteSpace($OperationId)) { throw 'Stable Operation ID is required for every mutation.' }
    return [ordered]@{
        id = $OperationId
        payloadDigest = $PayloadDigest
        changedFields = $ChangedFields
        occurredAt = [DateTimeOffset]::UtcNow.ToString('o')
        actor = $Actor
        reason = $Reason
        decisionConfirmed = $DecisionConfirmed
    }
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
    foreach ($name in $Fields.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$name) -or [string]$name -match '(?i)password|token|secret|private.?key') {
            throw 'A Handoff field has an empty or sensitive name; do not store credentials.'
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
        [Parameter(Mandatory = $true)] $Change,[string] $RecordRevision,[string] $OccurredAt,[string] $PayloadDigest,[string] $Source,
        [string] $Actor,[string] $Reason,[bool] $DecisionConfirmed)
    $field = [string]$Change.field
    $integrationStatus = if ($field -ceq 'Active Branches') { 'structural-index' }
        elseif ($RecordKind -eq 'branch' -and $field -ceq 'Branch Outcome' -and $DecisionConfirmed) { 'user-confirmed-branch-outcome' }
        elseif ($RecordKind -eq 'branch') { 'branch-only' }
        elseif ($DecisionConfirmed) { 'user-confirmed-common' }
        else { 'common-checkpoint' }
    $recordId = Get-HandoffRecordId -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $ref = Get-HandoffEventRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId -Field $field
    $expected = [ordered]@{
        schemaVersion = 1
        TaskKey = $TaskKey
        RecordKind = $RecordKind
        RecordId = $recordId
        BranchId = $BranchId
        OperationId = $OperationId
        Field = $field
        PreviousState = $Change.previous
        NewState = $Change.new
        OccurredAt = $OccurredAt
        Actor = $Actor
        Reason = $Reason
        Source = $Source
        RecordRevision = $RecordRevision
        IntegrationStatus = $integrationStatus
        ReadbackResult = 'verified'
        PayloadDigest = $PayloadDigest
    }
    $existing = Get-GitHandoffEvent -Adapter $Adapter -TaskKey $TaskKey -RecordKind $RecordKind -BranchId $BranchId -OperationId $OperationId -Field $field
    if ($null -ne $existing) {
        if (-not (Test-HandoffValueEqual -Left $expected -Right ([ordered]@{
            schemaVersion=$existing.schemaVersion;TaskKey=$existing.TaskKey;RecordKind=$existing.RecordKind;RecordId=$existing.RecordId;
            BranchId=$existing.BranchId;OperationId=$existing.OperationId;Field=$existing.Field;PreviousState=$existing.PreviousState;
            NewState=$existing.NewState;OccurredAt=$existing.OccurredAt;Actor=$existing.Actor;Reason=$existing.Reason;
            Source=$existing.Source;RecordRevision=$existing.RecordRevision;IntegrationStatus=$existing.IntegrationStatus;
            ReadbackResult=$existing.ReadbackResult;PayloadDigest=$existing.PayloadDigest
        }))) { throw "Event identity '$OperationId/$field' already exists with different content." }
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
    $operation = $current.Record.operations[$OperationId]
    if ($null -eq $operation) { throw "Operation ID '$OperationId' was not persisted in the record." }
    $origin = Get-GitHandoffOperationOrigin -Adapter $Adapter -Current $current -OperationId $OperationId
    foreach ($change in @($operation.changedFields)) {
        $field = [string]$change.field
        try {
            Write-GitHandoffEventIfAbsent -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId `
                -Change $change -RecordRevision $origin.Revision -OccurredAt $operation.occurredAt -PayloadDigest $operation.payloadDigest `
                -Source ([string]$origin.Record.fields.Source) -Actor ([string]$operation.actor) -Reason ([string]$operation.reason) `
                -DecisionConfirmed ([bool]$operation.decisionConfirmed) | Out-Null
        }
        catch { throw "Operation ID '$OperationId' committed its record, but field event '$field' is pending or unverified: $($_.Exception.Message)" }
    }
    return $current
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

function New-GitHandoffRecord {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $ForkPoint,
        [Parameter(Mandatory = $true)] $Fields,[string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Actor)
    Assert-HandoffFieldsSafe -Fields $Fields -RecordKind $RecordKind
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'A Handoff creation event requires the actual writer actor.' }
    if (@($Fields.Keys | Where-Object { [string]$_ -ieq 'Active Branches' }).Count -gt 0) {
        throw "Active Branches is a structural common index; create the record first, then use the branch index reconciliation operation."
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
    $operation = New-HandoffOperation -PayloadDigest $digest -OperationId $OperationId -ChangedFields $changes -Actor $Actor
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

function Set-GitHandoffFields {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][ValidateSet('common','branch')][string] $RecordKind,
        [Parameter(Mandatory = $true)][string] $TaskKey,[string] $BranchId,
        [Parameter(Mandatory = $true)][string] $ExpectedRevision,[Parameter(Mandatory = $true)] $Changes,
        [Parameter(Mandatory = $true)][string] $OperationId,[switch] $SuppressActivity,[switch] $DecisionConfirmed,
        [switch] $ExplicitContinuation,[string] $Actor='configured-adapter',[string] $Reason)
    Assert-HandoffFieldsSafe -Fields $Changes -RecordKind $RecordKind -DecisionConfirmed:$DecisionConfirmed
    if (@($Changes.Keys | Where-Object { $_ -cin @('Lifecycle','Work State','Branch Outcome') }).Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($Reason)) {
        throw 'A status transition requires a concrete reason and traceable Source.'
    }
    if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = 'field checkpoint with traceable Source' }
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'A Handoff field event requires an actor.' }
    if ($RecordKind -eq 'branch' -and [string]::IsNullOrWhiteSpace($BranchId)) { throw 'An exact Branch ID is required for its own record.' }
    $digest = Get-OperationPayloadDigest -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -Changes $Changes `
        -Actor $Actor -Reason $Reason -DecisionConfirmed ([bool]$DecisionConfirmed)
    $old = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $old) { throw 'The exact Handoff record could not be found; no replacement was created.' }
    $existingOp = $old.Record.operations[$OperationId]
    if ($null -ne $existingOp) {
        if ($existingOp.payloadDigest -cne $digest) { throw 'An Operation ID was reused with different changed fields.' }
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
        return [pscustomobject]@{RecordId=$old.Record.recordId;Revision=$old.Revision;Status='already-applied'}
    }
    if ($old.Revision -cne $ExpectedRevision) { throw 'Conditional Handoff revision conflict; re-read formal authority and records.' }
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
        if ($fieldName -cin @('Task Key','Branch ID','Fork Point','Last Activity At')) { throw 'Handoff identity and activity cannot be replaced through changed fields.' }
        $previous = Get-HandoffFieldValue -Record $newRecord -Field $fieldName
        $next = $Changes[$field]
        if (Test-HandoffValueEqual -Left $previous -Right $next) { continue }
        $actualChanges.Add([ordered]@{field=$fieldName;previous=$previous;new=$next})
        if ($fieldName -ceq 'Active Branches') { $newRecord.activeBranches = @($next) }
        else { $newRecord.fields[$fieldName] = $next }
    }
    Assert-HandoffRequiredFields -Fields $newRecord.fields -RecordKind $RecordKind
    if ($actualChanges.Count -eq 0) { return [pscustomobject]@{RecordId=$old.Record.recordId;Revision=$old.Revision;Status='no-op'} }
    $operation = New-HandoffOperation -PayloadDigest $digest -OperationId $OperationId -ChangedFields $actualChanges.ToArray() `
        -Actor $Actor -Reason $Reason -DecisionConfirmed ([bool]$DecisionConfirmed)
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
    return [pscustomobject]@{RecordId=$read.Record.recordId;Revision=$read.Revision;Status='updated'}
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
    $branch = New-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId -ForkPoint $ForkPoint -Fields $Fields -OperationId $OperationId -Actor $Actor
    if ((Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId).Fields.Lifecycle -ceq 'Archived') {
        throw 'An archived branch must be restored by exact explicit continuation, not indexed as a new branch.'
    }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
        if ($common.Fields.Lifecycle -cne 'Active') {
            throw "Branch '$BranchId' is durable but cannot be indexed under an Archived common record; restore common explicitly and retry the exact operation."
        }
        if ($common.ActiveBranches -ccontains $BranchId) {
            $indexedRecord = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
            if ($null -ne $indexedRecord.Record.operations["${OperationId}:index"]) {
                Complete-GitHandoffEvents -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -OperationId "${OperationId}:index" | Out-Null
            }
            return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$branch.Revision;CommonRevision=$common.Revision;Indexed=$true}
        }
        $newIndex = @($common.ActiveBranches) + @($BranchId)
        try {
            $index = Set-GitHandoffFields -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -ExpectedRevision $common.Revision `
                -Changes ([ordered]@{'Active Branches'=$newIndex}) -OperationId "${OperationId}:index" -SuppressActivity `
                -Actor $Actor -Reason 'index exact peer branch after creation'
            $rechecked = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
            if ($rechecked.ActiveBranches -ccontains $BranchId) {
                return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$branch.Revision;CommonRevision=$index.Revision;Indexed=$true}
            }
        }
        catch { if ($attempt -eq 2) { throw "Branch '$BranchId' is durable but unindexed; retain Operation ID '$OperationId' and retry only common index: $($_.Exception.Message)" } }
    }
    throw "Branch '$BranchId' was not fully indexed after creation; retain its exact ID and Operation ID '$OperationId'."
}

function Set-GitHandoffBranchLifecycle {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [Parameter(Mandatory = $true)][ValidateSet('Active','Archived')][string] $Lifecycle,
        [Parameter(Mandatory = $true)][string] $OperationId,[switch] $ExplicitContinuation,
        [string] $Actor='configured-adapter',[string] $Reason)
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
    if ($Lifecycle -ceq 'Active' -and $common.Fields.Lifecycle -ceq 'Archived') {
        Set-GitHandoffFields -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -ExpectedRevision $common.Revision `
            -Changes ([ordered]@{Lifecycle='Active'}) -OperationId "${OperationId}:common-restore" -ExplicitContinuation `
            -Actor $Actor -Reason 'restore exact common before peer continuation' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
        if ($common.Fields.Lifecycle -cne 'Active') { throw 'The exact common restore was not read back; retain the operation ID.' }
    }
    if ($branch.Fields.Lifecycle -cne $Lifecycle) {
        Set-GitHandoffFields -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId -ExpectedRevision $branch.Revision `
            -Changes ([ordered]@{Lifecycle=$Lifecycle}) -OperationId $OperationId -SuppressActivity:($Lifecycle -ceq 'Archived') `
            -ExplicitContinuation:$ExplicitContinuation -Actor $Actor -Reason $Reason | Out-Null
    }
    else {
        $existing = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId
        if ($null -ne $existing.Record.operations[$OperationId]) {
            Complete-GitHandoffEvents -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
        }
    }
    $branch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
    $requestedBranchRevision = if ($branch.Fields.Lifecycle -ceq $Lifecycle) { [string]$branch.Revision } else { $null }
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $branch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
        $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
        if ($null -eq $branch -or $null -eq $common) { throw 'The exact common or branch record disappeared during lifecycle reconciliation.' }
        $effectiveLifecycle = [string]$branch.Fields.Lifecycle
        $shouldBeIndexed = ($effectiveLifecycle -ceq 'Active')
        $indexOperationId = if ($null -ne $requestedBranchRevision -and $branch.Revision -ceq $requestedBranchRevision -and $effectiveLifecycle -ceq $Lifecycle) {
            "${OperationId}:index"
        }
        else {
            "${OperationId}:index:reconcile:$($branch.Revision)"
        }
        $indexed = ($common.ActiveBranches -ccontains $BranchId)
        if ($indexed -eq $shouldBeIndexed) {
            $indexedRecord = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
            if ($null -ne $indexedRecord.Record.operations[$indexOperationId]) {
                Complete-GitHandoffEvents -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -OperationId $indexOperationId | Out-Null
            }
            return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$branch.Revision;CommonRevision=$common.Revision;Lifecycle=$effectiveLifecycle;Indexed=$indexed}
        }
        if ($shouldBeIndexed) { $newIndex = @($common.ActiveBranches) + @($BranchId) }
        else { $newIndex = @($common.ActiveBranches | Where-Object { $_ -cne $BranchId }) }
        $observedBranchRevision = [string]$branch.Revision
        try {
            Set-GitHandoffFields -Adapter $Adapter -RecordKind common -TaskKey $TaskKey -ExpectedRevision $common.Revision `
                -Changes ([ordered]@{'Active Branches'=$newIndex}) -OperationId $indexOperationId -SuppressActivity `
                -Actor $Actor -Reason 'reconcile exact peer Active index after lifecycle change' | Out-Null
            $verifiedBranch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
            $verifiedCommon = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
            if ($verifiedBranch.Revision -ceq $observedBranchRevision -and
                (($verifiedCommon.ActiveBranches -ccontains $BranchId) -eq $shouldBeIndexed)) {
                return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$verifiedBranch.Revision;CommonRevision=$verifiedCommon.Revision;Lifecycle=$effectiveLifecycle;Indexed=$shouldBeIndexed}
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
    New-GitHandoffCommon,New-GitHandoffBranch,Set-GitHandoffFields,Set-GitHandoffBranchLifecycle
