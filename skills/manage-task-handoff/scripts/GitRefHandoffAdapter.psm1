# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest
$script:HandoffIndexLock = [object]::new()
$script:HandoffInternalOperationPrefix = '__handoff_internal_v1__:'

function Get-HandoffSha256 {
    param([Parameter(Mandatory = $true)][string] $Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $strictUtf8 = [Text.UTF8Encoding]::new($false,$true)
        try { $bytes = $strictUtf8.GetBytes($Value) }
        catch [Text.EncoderFallbackException] {
            throw 'Handoff identities and fields must contain well-formed Unicode without unpaired UTF-16 surrogates.'
        }
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
    foreach ($name in @('RepositoryRoot','RemoteName','RefPrefix','AuthorityScope')) {
        if ($null -eq $Adapter.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$Adapter.$name)) {
            throw "Git Handoff adapter configuration is missing '$name'."
        }
    }
    foreach ($name in @('GetVerifiedPrincipal','Authorize')) {
        if ($null -eq $Adapter.PSObject.Properties[$name] -or $Adapter.$name -isnot [scriptblock]) {
            throw "Git Handoff adapter configuration is missing trusted '$name' policy code."
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

function Get-HandoffScopedTaskHash {
    param([Parameter(Mandatory = $true)][string] $AuthorityScope,
        [Parameter(Mandatory = $true)][string] $TaskKey)
    $scopeHash = Get-HandoffSha256 -Value $AuthorityScope
    $taskHash = Get-HandoffSha256 -Value $TaskKey
    return Get-HandoffSha256 -Value ($scopeHash + $taskHash)
}

function Assert-GitHandoffAuthorized {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $Action,
        [Parameter(Mandatory = $true)][string] $TaskKey,[string] $BranchId,[string] $ForkId)
    Assert-GitAdapter -Adapter $Adapter
    $principalResolver = [scriptblock]$Adapter.GetVerifiedPrincipal
    try { $principalItems = @($principalResolver.Invoke()) }
    catch { throw 'Git Handoff authorization is unavailable; no record content was read or written.' }
    if ($principalItems.Count -ne 1) {
        throw 'Git Handoff authorization is unavailable; no record content was read or written.'
    }
    $principal = $principalItems[0]
    if ($principal -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$principal)) {
        throw 'Git Handoff authorization is unavailable; no record content was read or written.'
    }
    $principal = [string]$principal
    $request = [pscustomobject]@{
        Principal=$principal;AuthorityScope=[string]$Adapter.AuthorityScope;TaskKey=$TaskKey;
        BranchId=$BranchId;ForkId=$ForkId;Action=$Action
    }
    $authorizationPolicy = [scriptblock]$Adapter.Authorize
    try { $authorizationResults = @($authorizationPolicy.Invoke($request)) }
    catch { throw 'Git Handoff authorization is unavailable; no record content was read or written.' }
    if ($authorizationResults.Count -ne 1 -or $authorizationResults[0] -isnot [bool] -or -not $authorizationResults[0]) {
        throw 'Git Handoff access was denied; no record content was read or written.'
    }
    return $principal
}

function Get-HandoffRecordId {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $RecordKind,
        [Parameter(Mandatory = $true)][string] $TaskKey,[string] $BranchId)
    if ($RecordKind -notin @('common','branch')) { throw 'Unknown Handoff record kind.' }
    if ($RecordKind -eq 'branch' -and [string]::IsNullOrWhiteSpace($BranchId)) { throw 'Branch ID is required.' }
    Assert-HandoffIdentity -TaskKey $TaskKey
    $scopeHash = Get-HandoffSha256 -Value ([string]$Adapter.AuthorityScope)
    if ($RecordKind -eq 'common') { return "common:${scopeHash}:$TaskKey" }
    $taskHash = Get-HandoffSha256 -Value $TaskKey
    $branchHash = Get-HandoffSha256 -Value $BranchId
    return "branch:${scopeHash}:${taskHash}:${branchHash}"
}

function Get-HandoffRecordRef {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId)
    Assert-GitAdapter -Adapter $Adapter
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    if ($RecordKind -eq 'common') { return "$($Adapter.RefPrefix)/records/$scopedTaskHash/common" }
    if ($RecordKind -eq 'branch') { return "$($Adapter.RefPrefix)/records/$scopedTaskHash/branch/$(Get-HandoffSha256 -Value $BranchId)" }
    throw 'Unknown Handoff record kind.'
}

function Get-HandoffForkRecoveryId {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId)
    Assert-HandoffIdentity -TaskKey $TaskKey
    if ([string]::IsNullOrWhiteSpace($ForkId)) { throw 'Fork ID must be stable and nonempty.' }
    return "fork-recovery:$(Get-HandoffSha256 -Value ([string]$Adapter.AuthorityScope)):$(Get-HandoffSha256 -Value $TaskKey):$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffForkRecoveryRef {
    param($Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,[Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitAdapter -Adapter $Adapter
    [void](Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId)
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    return "$($Adapter.RefPrefix)/recovery/$scopedTaskHash/$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffForkRecoveryEnvelopeRef {
    param($Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,[Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitAdapter -Adapter $Adapter
    [void](Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId)
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    return "$($Adapter.RefPrefix)/recovery-envelopes/$scopedTaskHash/$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffForkRecoveryControlRef {
    param($Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,[Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitAdapter -Adapter $Adapter
    [void](Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId)
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    return "$($Adapter.RefPrefix)/recovery-controls/$scopedTaskHash/$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffForkRecoveryIndexRef {
    param($Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,[Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitAdapter -Adapter $Adapter
    [void](Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId)
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    return "$($Adapter.RefPrefix)/recovery-index/$scopedTaskHash/$(Get-HandoffSha256 -Value $ForkId)"
}

function Get-HandoffEventRef {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $OperationId,[string] $Field)
    if ([string]::IsNullOrWhiteSpace($OperationId) -or [string]::IsNullOrWhiteSpace($Field)) { throw 'Event identity is incomplete.' }
    $recordId = Get-HandoffRecordId -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    # Fixed-width component hashes retain the composite identity without delimiter ambiguity or long Windows refs.
    $composite = (Get-HandoffSha256 -Value $OperationId) + (Get-HandoffSha256 -Value $recordId) +
        (Get-HandoffSha256 -Value $Field)
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
    # Disable the configured refmap so exact reads populate only FETCH_HEAD/object storage.
    # Mirroring these opaque refs under refs/remotes/origin can exceed Windows path limits.
    $fetchOutput = @(& git -C $Adapter.RepositoryRoot fetch --quiet --no-tags '--refmap=' $Adapter.RemoteName $Ref 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "The exact Handoff ref could not be fetched for readback: $($fetchOutput -join ' ')"
    }
    $text = & git -C $Adapter.RepositoryRoot show "${Revision}:${FileName}" 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'The Handoff commit does not contain the expected document.' }
    try { return (@($text) -join "`n") | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw 'The Handoff document could not be parsed without ambiguity.' }
}

function New-GitHandoffCommit {
    param($Adapter,[Parameter(Mandatory = $true)] $Document,[string] $Parent,[ValidateSet('record.json','event.json','recovery.json','envelope.json','control.json','index.json')][string] $FileName)
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

function Push-GitHandoffForkBranchIfCommonRevision {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $BranchRef,
        [Parameter(Mandatory = $true)][string] $BranchCommit,[Parameter(Mandatory = $true)][string] $CommonRef,
        [Parameter(Mandatory = $true)][string] $ExpectedCommonRevision,
        [Parameter(Mandatory = $true)][string] $CommonFenceCommit)
    $arguments = @('-C',[string]$Adapter.RepositoryRoot,'push','--quiet','--atomic',
        "--force-with-lease=${BranchRef}:","--force-with-lease=${CommonRef}:${ExpectedCommonRevision}",
        [string]$Adapter.RemoteName,"${BranchCommit}:${BranchRef}","${CommonFenceCommit}:${CommonRef}")
    $pushOutput = @(& git @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $remoteBranch = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $BranchRef
        $remoteCommon = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $CommonRef
        if ($null -eq $remoteBranch -and $remoteCommon -cne $ExpectedCommonRevision) {
            throw 'The common recovery fence changed before bound branch creation; no branch was written.'
        }
        throw "The bound fork branch write was not verified; no partial atomic update is accepted: $($pushOutput -join ' ')"
    }
    $verifiedBranch = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $BranchRef
    $verifiedCommon = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $CommonRef
    if ($verifiedBranch -cne $BranchCommit -or $verifiedCommon -cne $CommonFenceCommit) {
        throw 'The bound branch and common recovery fence were not atomically read back.'
    }
    return [pscustomobject]@{BranchRevision=$verifiedBranch;CommonRevision=$verifiedCommon}
}

function Assert-GitHandoffForkRecoveryCommonFence {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ExpectedRevision,[Parameter(Mandatory = $true)][string] $FailureMessage)
    $current = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
    if ($null -eq $current) { throw $FailureMessage }
    if ([string]$current.Revision -ceq $ExpectedRevision) { return $current }
    try {
        $expectedDocument = Read-GitHandoffDocument -Adapter $Adapter -Ref $current.Ref `
            -Revision $ExpectedRevision -FileName 'record.json'
        $expectedJson = $expectedDocument | ConvertTo-Json -Compress -Depth 50
        $currentJson = $current.Record | ConvertTo-Json -Compress -Depth 50
        if ([string]$expectedJson -ceq [string]$currentJson) { return $current }
    }
    catch { }
    throw $FailureMessage
}

function Push-GitHandoffForkRecoveryPayloadIfRevisions {
    param([Parameter(Mandatory = $true)] $Adapter,
        [Parameter(Mandatory = $true)][string] $PayloadRef,
        [AllowEmptyString()][string] $ExpectedPayloadRevision,
        [Parameter(Mandatory = $true)][string] $PayloadCommit,
        [Parameter(Mandatory = $true)][string] $EnvelopeRef,
        [Parameter(Mandatory = $true)][string] $ExpectedEnvelopeRevision,
        [Parameter(Mandatory = $true)][string] $EnvelopeCommit)
    $arguments = @('-C',[string]$Adapter.RepositoryRoot,'push','--quiet','--atomic',
        "--force-with-lease=$($PayloadRef):$ExpectedPayloadRevision",
        "--force-with-lease=$($EnvelopeRef):$ExpectedEnvelopeRevision",[string]$Adapter.RemoteName,
        "${PayloadCommit}:$PayloadRef","${EnvelopeCommit}:$EnvelopeRef")
    $pushOutput = @(& git @arguments 2>&1)
    $status = $LASTEXITCODE
    $observedPayload = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $PayloadRef
    $observedEnvelope = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $EnvelopeRef
    if ($observedPayload -ceq $PayloadCommit -and $observedEnvelope -ceq $EnvelopeCommit) {
        return [pscustomobject]@{PayloadRevision=$observedPayload;EnvelopeRevision=$observedEnvelope}
    }
    if (($observedPayload -ceq $PayloadCommit) -xor ($observedEnvelope -ceq $EnvelopeCommit)) {
        throw 'The remote violated atomic fork-recovery payload and envelope updates; preserve both observed revisions.'
    }
    $expectedPayload = if ([string]::IsNullOrEmpty($ExpectedPayloadRevision)) { $null } else { $ExpectedPayloadRevision }
    if ($observedPayload -cne $expectedPayload -or $observedEnvelope -cne $ExpectedEnvelopeRevision) {
        throw 'Conditional fork-recovery payload/envelope revision conflict; re-read the recovery state.'
    }
    if ($status -ne 0) {
        throw "The fork-recovery payload and envelope were rejected atomically; neither advanced: $($pushOutput -join ' ')"
    }
    throw 'The fork-recovery payload and envelope were not atomically read back.'
}

function Push-GitHandoffForkRecoveryTerminalIfRevisions {
    param([Parameter(Mandatory = $true)] $Adapter,
        [Parameter(Mandatory = $true)][string] $EnvelopeRef,
        [Parameter(Mandatory = $true)][string] $ExpectedEnvelopeRevision,
        [Parameter(Mandatory = $true)][string] $EnvelopeCommit,
        [Parameter(Mandatory = $true)][string] $IndexRef,
        [Parameter(Mandatory = $true)][string] $ExpectedIndexRevision,
        [Parameter(Mandatory = $true)][string] $IndexCommit)
    $arguments = @('-C',[string]$Adapter.RepositoryRoot,'push','--quiet','--atomic',
        "--force-with-lease=${EnvelopeRef}:${ExpectedEnvelopeRevision}",
        "--force-with-lease=${IndexRef}:${ExpectedIndexRevision}",[string]$Adapter.RemoteName,
        "${EnvelopeCommit}:${EnvelopeRef}","${IndexCommit}:${IndexRef}")
    $pushOutput = @(& git @arguments 2>&1)
    $status = $LASTEXITCODE
    $observedEnvelope = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $EnvelopeRef
    $observedIndex = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $IndexRef
    if ($observedEnvelope -ceq $EnvelopeCommit -and $observedIndex -ceq $IndexCommit) {
        return [pscustomobject]@{EnvelopeRevision=$observedEnvelope;IndexRevision=$observedIndex}
    }
    if (($observedEnvelope -ceq $EnvelopeCommit) -xor ($observedIndex -ceq $IndexCommit)) {
        throw 'The remote violated atomic terminal recovery updates; stop and preserve both observed revisions.'
    }
    if ($observedEnvelope -cne $ExpectedEnvelopeRevision -or $observedIndex -cne $ExpectedIndexRevision) {
        throw 'Conditional terminal recovery revision conflict; re-read the envelope and protected index.'
    }
    if ($status -ne 0) {
        throw "The terminal recovery envelope and protected index were rejected atomically; both remain nonterminal: $($pushOutput -join ' ')"
    }
    throw 'The terminal recovery envelope and protected index were not atomically read back.'
}

function Read-GitHandoffRecord {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId)
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action "${RecordKind}:read" -TaskKey $TaskKey -BranchId $BranchId | Out-Null
    $recordId = Get-HandoffRecordId -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $ref = Get-HandoffRecordRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $record = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'record.json'
    if ($record.schemaVersion -ne 1 -or $record.recordKind -cne $RecordKind -or
        $record.authorityScope -cne [string]$Adapter.AuthorityScope -or
        $record.fields['Authority Scope'] -cne [string]$Adapter.AuthorityScope -or
        $record.taskKey -cne $TaskKey -or $record.recordId -cne $recordId -or
        ($RecordKind -eq 'branch' -and $record.branchId -cne $BranchId) -or
        ($RecordKind -eq 'common' -and $null -ne $record.branchId)) {
        throw 'The exact Handoff ref contains a mismatched task or branch association.'
    }
    if ($RecordKind -eq 'branch' -and
        (-not $record.Contains('forkRecovery') -or $record.forkRecovery -isnot [Collections.IDictionary] -or
         [string]::IsNullOrWhiteSpace([string]$record.forkRecovery.forkId) -or
         [string]::IsNullOrWhiteSpace([string]$record.forkRecovery.creationOperationId) -or
         [string]$record.forkRecovery.payloadDigest -cnotmatch '^[0-9a-f]{64}$' -or
         [string]$record.forkRecovery.payloadRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
         [string]$record.forkRecovery.controlRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
         [string]$record.forkRecovery.claimEnvelopeRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
         [string]$record.forkRecovery.expectedBranchPayloadDigest -cnotmatch '^[0-9a-f]{64}$' -or
         [string]$record.forkRecovery.commonRevision -cnotmatch '^[0-9a-f]{40,64}$')) {
        throw 'The exact branch record lacks its bound fork-recovery evidence.'
    }
    return [pscustomobject]@{ Revision=$revision; Ref=$ref; Record=$record }
}

function Assert-HandoffForkRecoveryPayload {
    param([Parameter(Mandatory = $true)] $Payload)
    if ($Payload -isnot [Collections.IDictionary]) { throw 'Fork recovery payload must be an ordered mapping.' }
    $required = @('Fork Point','Source Branch ID','Intended Branch IDs','Source Snapshot','Shared Baseline',
        'Verified Active Branches','Branch Creation Operations','Step Operation IDs')
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
        $Payload['Branch Creation Operations'] -isnot [Collections.IDictionary] -or
        $Payload['Step Operation IDs'] -isnot [Collections.IDictionary]) {
        throw 'Fork recovery payload has an invalid identity, snapshot, baseline, or operation map.'
    }
    foreach ($name in @('Source Snapshot','Shared Baseline')) {
        if (-not $Payload[$name].Contains('Current') -or -not $Payload[$name].Contains('Source') -or
            [string]::IsNullOrWhiteSpace([string]$Payload[$name]['Current']) -or
            [string]::IsNullOrWhiteSpace([string]$Payload[$name]['Source'])) {
            throw "Fork recovery $name must contain nonempty Current and Source values."
        }
    }
}

function Get-HandoffForkBranchPayloadDigest {
    param([Parameter(Mandatory = $true)][string] $ForkPoint,[Parameter(Mandatory = $true)] $Fields)
    if ($Fields -isnot [Collections.IDictionary]) { throw 'Fork branch creation fields must be a mapping.' }
    $required = @('Current','Source','Lifecycle','Work State')
    $names = @($Fields.Keys | ForEach-Object { [string]$_ })
    if ($names.Count -ne $required.Count -or @($names | Where-Object { $_ -cnotin $required }).Count -gt 0) {
        throw 'A fork target must be created from exactly Current, Source, Lifecycle, and Work State.'
    }
    $canonical = [ordered]@{forkPoint=$ForkPoint;fields=[ordered]@{
        Current=$Fields['Current'];Source=$Fields['Source'];Lifecycle=$Fields['Lifecycle'];'Work State'=$Fields['Work State']
    }}
    return Get-HandoffSha256 -Value ($canonical | ConvertTo-Json -Compress -Depth 20)
}

function Get-HandoffCommonSemanticDigest {
    param([Parameter(Mandatory = $true)] $CommonRecord)
    if ($CommonRecord.recordKind -cne 'common') { throw 'A common recovery fence requires a common record.' }
    return Get-HandoffSha256 -Value ($CommonRecord.fields | ConvertTo-Json -Compress -Depth 50)
}

function Get-HandoffForkRecoveryEnvelopeEvidence {
    param([Parameter(Mandatory = $true)] $Payload)
    Assert-HandoffForkRecoveryPayload -Payload $Payload
    $active = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($branchId in @($Payload['Verified Active Branches'])) {
        if ([string]::IsNullOrWhiteSpace([string]$branchId)) {
            throw 'Fork recovery verified Active branches contain an invalid identity.'
        }
        if (-not $active.Add([string]$branchId)) {
            throw 'Fork recovery verified Active branches must be unique.'
        }
    }
    $targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $intended = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($branchId in @($Payload['Intended Branch IDs'])) {
        if ([string]::IsNullOrWhiteSpace([string]$branchId)) {
            throw 'Fork recovery intended branches contain an invalid identity.'
        }
        if (-not $intended.Add([string]$branchId)) {
            throw 'Fork recovery intended branch identities must be unique.'
        }
        if (-not $active.Contains([string]$branchId)) { [void]$targets.Add([string]$branchId) }
    }
    if ($targets.Count -lt 1) { throw 'Fork recovery requires at least one absent branch creation target.' }
    $targetDigests = @($targets | ForEach-Object { Get-HandoffSha256 -Value $_ } | Sort-Object -Unique)
    $creationOperations = $Payload['Branch Creation Operations']
    if ($creationOperations.Count -ne $targets.Count) {
        throw 'Fork recovery Branch Creation Operations must contain every absent target and no other branch.'
    }
    $creationOperationDigests = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $bindingEntries = [Collections.Generic.List[object]]::new()
    foreach ($entry in $creationOperations.GetEnumerator()) {
        $branchId = [string]$entry.Key
        $operationId = [string]$entry.Value
        if ([string]::IsNullOrWhiteSpace($branchId) -or -not $targets.Contains($branchId)) {
            throw 'Fork recovery Branch Creation Operations contains a non-target branch identity.'
        }
        Assert-HandoffOperationId -OperationId $operationId
        $operationDigest = Get-HandoffSha256 -Value $operationId
        if (-not $creationOperationDigests.Add($operationDigest)) {
            throw 'Fork recovery requires a distinct creation Operation ID for every absent target.'
        }
        $bindingEntries.Add([pscustomobject]@{
            TargetDigest=(Get-HandoffSha256 -Value $branchId);OperationDigest=$operationDigest
        })
    }
    $bindings = [ordered]@{}
    $expectedPayloadDigests = [ordered]@{}
    $expectedPayloadDigestsByTargetDigest = [ordered]@{}
    foreach ($entry in @($bindingEntries | Sort-Object TargetDigest)) {
        $bindings[$entry.TargetDigest] = $entry.OperationDigest
    }
    foreach ($branchId in @($targets | Sort-Object)) {
        $baseline = if ($branchId -ceq [string]$Payload['Source Branch ID']) {
            $Payload['Source Snapshot']
        }
        else { $Payload['Shared Baseline'] }
        $expectedFields = [ordered]@{Current=$baseline['Current'];Source=$baseline['Source'];Lifecycle='Active';'Work State'='Running'}
        $payloadDigest = Get-HandoffForkBranchPayloadDigest -ForkPoint ([string]$Payload['Fork Point']) -Fields $expectedFields
        $expectedPayloadDigests[$branchId] = $payloadDigest
        $expectedPayloadDigestsByTargetDigest[(Get-HandoffSha256 -Value $branchId)] = $payloadDigest
    }
    return [pscustomobject]@{
        BranchCreationTargetDigests=@($targetDigests)
        BranchCreationOperationDigests=@($creationOperationDigests | Sort-Object)
        BranchCreationBindings=$bindings
        BranchCreationOperations=$creationOperations
        ExpectedBranchPayloadDigests=$expectedPayloadDigests
        ExpectedBranchPayloadDigestsByTargetDigest=$expectedPayloadDigestsByTargetDigest
    }
}

function Test-HandoffSha256Array {
    param($Value,[int] $MinimumCount=1)
    $items = @($Value)
    if ($items.Count -lt $MinimumCount) { return $false }
    foreach ($item in $items) {
        if ([string]$item -cnotmatch '^[0-9a-f]{64}$') { return $false }
    }
    return @($items | Sort-Object -Unique).Count -eq $items.Count
}

function Assert-HandoffForkRecoveryClaimShape {
    param([Parameter(Mandatory = $true)] $Document)
    if (-not $Document.Contains('branchCreationBindings') -or
        $Document.branchCreationBindings -isnot [Collections.IDictionary] -or
        -not $Document.Contains('branchCreationClaims') -or
        $Document.branchCreationClaims -isnot [Collections.IDictionary]) {
        throw 'The fork-recovery envelope lacks its branch-creation binding or claim map.'
    }
    $targets = @($Document.branchCreationTargetDigests)
    $operations = @($Document.branchCreationOperationDigests)
    if ($Document.branchCreationBindings.Count -ne $targets.Count -or $operations.Count -ne $targets.Count) {
        throw 'The fork-recovery envelope branch-creation binding is not exact.'
    }
    foreach ($target in $targets) {
        if (-not $Document.branchCreationBindings.Contains($target) -or
            [string]$Document.branchCreationBindings[$target] -cnotmatch '^[0-9a-f]{64}$' -or
            $operations -cnotcontains [string]$Document.branchCreationBindings[$target]) {
            throw 'The fork-recovery envelope contains an invalid target-operation binding.'
        }
    }
    if (@($Document.branchCreationBindings.Values | Sort-Object -Unique).Count -ne $targets.Count) {
        throw 'The fork-recovery envelope reuses a branch-creation operation across targets.'
    }
    foreach ($entry in $Document.branchCreationClaims.GetEnumerator()) {
        if ($targets -cnotcontains [string]$entry.Key -or $entry.Value -isnot [Collections.IDictionary] -or
            [string]$entry.Value.operationDigest -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$Document.branchCreationBindings[[string]$entry.Key] -cne [string]$entry.Value.operationDigest -or
            [string]$entry.Value.commonRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
            [string]$entry.Value.payloadRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
            [string]$entry.Value.controlRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
            [string]$entry.Value.expectedBranchPayloadDigest -cnotmatch '^[0-9a-f]{64}$' -or
            [string]::IsNullOrWhiteSpace([string]$entry.Value.verifiedPrincipal) -or
            [string]::IsNullOrWhiteSpace([string]$entry.Value.claimedAt)) {
            throw 'The fork-recovery envelope contains an invalid branch-creation claim.'
        }
    }
}

function Read-GitHandoffForkRecoveryEnvelope {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId)
    $ref = Get-HandoffForkRecoveryEnvelopeRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $document = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'envelope.json'
    $recordId = Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($document.schemaVersion -ne 1 -or $document.recordKind -cne 'fork-recovery-envelope' -or
        $document.authorityScope -cne [string]$Adapter.AuthorityScope -or $document.taskKey -cne $TaskKey -or
        $document.forkId -cne $ForkId -or $document.recordId -cne $recordId -or
        [string]$document.status -cnotin @('Pending','Completed','Abandoned') -or
        [string]::IsNullOrWhiteSpace([string]$document.payloadDigest) -or
        ($document.Contains('payloadRevision') -and $null -ne $document.payloadRevision -and
         [string]$document.payloadRevision -cnotmatch '^[0-9a-f]{40,64}$') -or
        [string]$document.verifiedCommonRevisionAtCreation -cnotmatch '^[0-9a-f]{40,64}$' -or
        -not (Test-HandoffSha256Array -Value $document.branchCreationTargetDigests) -or
        -not (Test-HandoffSha256Array -Value $document.branchCreationOperationDigests `
            -MinimumCount @($document.branchCreationTargetDigests).Count) -or
        [string]::IsNullOrWhiteSpace([string]$document.creationOperationId) -or
        [string]::IsNullOrWhiteSpace([string]$document.actor) -or
        [string]::IsNullOrWhiteSpace([string]$document.verifiedPrincipal) -or
        $document.Contains('payload')) {
        throw 'The exact fork-recovery envelope contains a mismatched identity, status, or payload.'
    }
    if ([string]$document.status -ceq 'Completed' -and
        ([string]::IsNullOrWhiteSpace([string]$document.completionOperationId) -or
         [string]::IsNullOrWhiteSpace([string]$document.completionVerifiedPrincipal) -or
         [string]::IsNullOrWhiteSpace([string]$document.completedAt))) {
        throw 'The completed fork-recovery envelope lacks immutable completion evidence.'
    }
    if ([string]$document.status -ceq 'Abandoned' -and
        ([string]::IsNullOrWhiteSpace([string]$document.abandonmentOperationId) -or
         [string]::IsNullOrWhiteSpace([string]$document.abandonmentVerifiedPrincipal) -or
         [string]::IsNullOrWhiteSpace([string]$document.abandonmentReason) -or
         [string]::IsNullOrWhiteSpace([string]$document.abandonedAt))) {
        throw 'The abandoned fork-recovery envelope lacks immutable abandonment evidence.'
    }
    Assert-HandoffForkRecoveryClaimShape -Document $document
    return [pscustomobject]@{AuthorityScope=[string]$document.authorityScope;TaskKey=$TaskKey;
        ForkId=$ForkId;Status=[string]$document.status;Revision=$revision;Record=$document}
}

function Read-GitHandoffForkRecoveryControl {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:control-read' `
        -TaskKey $TaskKey -ForkId $ForkId | Out-Null
    $ref = Get-HandoffForkRecoveryControlRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $document = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'control.json'
    $recordId = Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($document.schemaVersion -ne 1 -or $document.recordKind -cne 'fork-recovery-control' -or
        $document.recordId -cne $recordId -or $document.authorityScope -cne [string]$Adapter.AuthorityScope -or
        $document.taskKey -cne $TaskKey -or $document.forkId -cne $ForkId -or
        [string]::IsNullOrWhiteSpace([string]$document.sourceBranchId) -or
        [string]::IsNullOrWhiteSpace([string]$document.sourceAclLocator) -or
        [string]$document.sourceAclLocator -cne [string]$document.sourceBranchId -or
        $document.branchCreationOperations -isnot [Collections.IDictionary] -or
        $document.expectedBranchPayloadDigests -isnot [Collections.IDictionary] -or
        $document.branchCreationOperations.Count -ne $document.expectedBranchPayloadDigests.Count -or
        [string]$document.payloadDigest -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$document.payloadObjectRef -cne (Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId) -or
        [string]$document.verifiedCommonRevisionAtCreation -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$document.commonSemanticDigest -cnotmatch '^[0-9a-f]{64}$') {
        throw 'The protected fork-recovery control record is invalid.'
    }
    $sourceBindingFields = @('sourceBranchRevision','sourceBranchForkPoint','sourceContinuationGeneration')
    $presentSourceBindingFields = @($sourceBindingFields | Where-Object { $document.Contains($_) })
    if ($presentSourceBindingFields.Count -gt 0) {
        if ($presentSourceBindingFields.Count -ne $sourceBindingFields.Count) {
            throw 'The protected fork-recovery source binding is incomplete.'
        }
        if ($null -ne $document.sourceBranchRevision -and
            [string]$document.sourceBranchRevision -cnotmatch '^[0-9a-f]{40,64}$') {
            throw 'The protected fork-recovery source branch revision is invalid.'
        }
        if ($null -ne $document.sourceBranchForkPoint -and
            [string]::IsNullOrWhiteSpace([string]$document.sourceBranchForkPoint)) {
            throw 'The protected fork-recovery source branch Fork Point is invalid.'
        }
        if ($null -ne $document.sourceContinuationGeneration) {
            try { $sourceGeneration = [int64]$document.sourceContinuationGeneration }
            catch { throw 'The protected fork-recovery source continuation generation is invalid.' }
            if ($sourceGeneration -lt 0) {
                throw 'The protected fork-recovery source continuation generation is invalid.'
            }
        }
    }
    foreach ($entry in $document.branchCreationOperations.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Key) -or
            [string]::IsNullOrWhiteSpace([string]$entry.Value) -or
            -not $document.expectedBranchPayloadDigests.Contains([string]$entry.Key) -or
            [string]$document.expectedBranchPayloadDigests[[string]$entry.Key] -cnotmatch '^[0-9a-f]{64}$') {
            throw 'The protected fork-recovery control bindings are invalid.'
        }
    }
    return [pscustomobject]@{Revision=$revision;Record=$document}
}

function Write-GitHandoffForkRecoveryIndex {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId,[Parameter(Mandatory = $true)][ValidateSet('Pending','Completed','Abandoned')][string] $Status,
        [Parameter(Mandatory = $true)][string] $EnvelopeRevision,
        [AllowEmptyString()][string] $ExpectedRevision='')
    if ($EnvelopeRevision -cnotmatch '^[0-9a-f]{40,64}$') { throw 'Recovery index requires the exact envelope revision.' }
    $document = [ordered]@{schemaVersion=1;recordKind='fork-recovery-index';authorityScope=[string]$Adapter.AuthorityScope;
        taskKey=$TaskKey;forkId=$ForkId;status=$Status;envelopeRevision=$EnvelopeRevision;
        updatedAt=[DateTimeOffset]::UtcNow.ToString('o')}
    $ref = Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document -Parent $ExpectedRevision -FileName 'index.json'
    Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision $ExpectedRevision -Commit $commit | Out-Null
    return $commit
}

function Read-GitHandoffForkRecoveryIndex {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId)
    $ref = Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $document = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'index.json'
    if ($document.schemaVersion -ne 1 -or $document.recordKind -cne 'fork-recovery-index' -or
        $document.authorityScope -cne [string]$Adapter.AuthorityScope -or $document.taskKey -cne $TaskKey -or
        $document.forkId -cne $ForkId -or [string]$document.status -cnotin @('Pending','Completed','Abandoned') -or
        [string]$document.envelopeRevision -cnotmatch '^[0-9a-f]{40,64}$') {
        throw 'The protected fork-recovery index has a mismatched identity, status, or envelope revision.'
    }
    return [pscustomobject]@{Revision=$revision;Status=[string]$document.status;Record=$document}
}

function Get-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId)
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:read' -TaskKey $TaskKey -ForkId $ForkId | Out-Null
    $ref = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    $envelope = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $revision) {
        if ($null -ne $envelope -and $envelope.Record.Contains('payloadRevision') -and
            $null -ne $envelope.Record.payloadRevision) {
            throw 'The fork-recovery envelope records a payload revision that is missing from its isolated ref.'
        }
        return $null
    }
    if ($null -eq $envelope) {
        throw 'The fork-recovery payload exists without its payload-free envelope.'
    }
    # The control is payload-free. Read it and authorize its bound source branch
    # before the isolated recovery payload can be fetched or parsed.
    $control = Read-GitHandoffForkRecoveryControl -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $control) {
        throw "Fork recovery '$ForkId' payload-free control is missing."
    }
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'branch:read' -TaskKey $TaskKey `
        -BranchId ([string]$control.Record.sourceAclLocator) | Out-Null
    $document = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'recovery.json'
    if (-not $envelope.Record.Contains('payloadRevision') -or
        [string]$envelope.Record.payloadRevision -cnotmatch '^[0-9a-f]{40,64}$') {
        throw 'The fork-recovery payload revision is not atomically bound by its envelope.'
    }
    & git -C $Adapter.RepositoryRoot merge-base --is-ancestor `
        ([string]$envelope.Record.payloadRevision) ([string]$revision) 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'The fork-recovery payload ref no longer descends from its atomically bound envelope revision.'
    }
    $recordId = Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($document.schemaVersion -ne 1 -or $document.recordKind -cne 'fork-recovery' -or
        $document.authorityScope -cne [string]$Adapter.AuthorityScope -or
        $document.taskKey -cne $TaskKey -or $document.forkId -cne $ForkId -or $document.recordId -cne $recordId -or
        [string]$document.status -cnotin @('Pending','Completed') -or
        [string]::IsNullOrWhiteSpace([string]$document.creationOperationId) -or
        [string]::IsNullOrWhiteSpace([string]$document.actor) -or
        [string]::IsNullOrWhiteSpace([string]$document.verifiedPrincipal)) {
        throw 'The exact fork-recovery ref contains a mismatched identity or status.'
    }
    Assert-HandoffForkRecoveryPayload -Payload $document.payload
    $expectedDigest = Get-HandoffSha256 -Value (([ordered]@{authorityScope=[string]$Adapter.AuthorityScope;
        taskKey=$TaskKey;forkId=$ForkId;payload=$document.payload;
        operationId=[string]$document.creationOperationId;actor=[string]$document.actor}) |
        ConvertTo-Json -Compress -Depth 50)
    if ([string]$document.payloadDigest -cne $expectedDigest) {
        throw 'The exact fork-recovery payload digest is invalid.'
    }
    if ([string]$document.status -ceq 'Completed' -and
        ([string]::IsNullOrWhiteSpace([string]$document.completionOperationId) -or
         [string]::IsNullOrWhiteSpace([string]$document.completionVerifiedPrincipal) -or
         [string]::IsNullOrWhiteSpace([string]$document.completedAt))) {
        throw 'The completed fork-recovery payload lacks immutable completion evidence.'
    }
    $payloadEvidence = Get-HandoffForkRecoveryEnvelopeEvidence -Payload $document.payload
    $statusConsistent = ($null -ne $envelope -and $null -ne $control -and ($envelope.Status -ceq [string]$document.status -or
        ([string]$document.status -ceq 'Completed' -and $envelope.Status -ceq 'Pending')))
    $completionConsistent = ($null -ne $envelope -and
        ([string]$document.status -ceq 'Pending' -or $envelope.Status -ceq 'Pending' -or
         ($envelope.Record.completionOperationId -ceq $document.completionOperationId -and
          $envelope.Record.completionVerifiedPrincipal -ceq $document.completionVerifiedPrincipal -and
          $envelope.Record.completedAt -ceq $document.completedAt)))
    if (-not $statusConsistent -or -not $completionConsistent -or
        $envelope.Record.payloadDigest -cne $document.payloadDigest -or
        $envelope.Record.creationOperationId -cne $document.creationOperationId -or
        $envelope.Record.actor -cne $document.actor -or
        $envelope.Record.verifiedPrincipal -cne $document.verifiedPrincipal -or
        (@($envelope.Record.branchCreationTargetDigests) | ConvertTo-Json -Compress) -cne
            (@($payloadEvidence.BranchCreationTargetDigests) | ConvertTo-Json -Compress) -or
        (@($envelope.Record.branchCreationOperationDigests) | ConvertTo-Json -Compress) -cne
            (@($payloadEvidence.BranchCreationOperationDigests) | ConvertTo-Json -Compress) -or
        ($envelope.Record.branchCreationBindings | ConvertTo-Json -Compress) -cne
            ($payloadEvidence.BranchCreationBindings | ConvertTo-Json -Compress) -or
        $control.Record.payloadDigest -cne $document.payloadDigest -or
        $control.Record.verifiedCommonRevisionAtCreation -cne $envelope.Record.verifiedCommonRevisionAtCreation -or
        ($control.Record.branchCreationOperations | ConvertTo-Json -Compress) -cne
            ($payloadEvidence.BranchCreationOperations | ConvertTo-Json -Compress) -or
        ($control.Record.expectedBranchPayloadDigests | ConvertTo-Json -Compress) -cne
            ($payloadEvidence.ExpectedBranchPayloadDigests | ConvertTo-Json -Compress) -or
        [string]$document.payload['Fork Point'] -cne [string]$envelope.Record.verifiedCommonRevisionAtCreation) {
        throw 'The fork-recovery payload and payload-free envelope do not match.'
    }
    return [pscustomobject]@{AuthorityScope=[string]$document.authorityScope;
        TaskKey=$TaskKey;ForkId=$ForkId;Status=[string]$document.status;
        Revision=$revision;EnvelopeStatus=$envelope.Status;EnvelopeRevision=$envelope.Revision;
        PayloadRevision=[string]$envelope.Record.payloadRevision;
        ControlRevision=$control.Revision;Control=$control.Record;
        Payload=$document.payload;Record=$document}
}

function Get-GitHandoffPendingForkRecoveryIndexEntries {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey)
    Assert-HandoffIdentity -TaskKey $TaskKey
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:list' -TaskKey $TaskKey | Out-Null
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    $prefix = "$($Adapter.RefPrefix)/recovery-index/$scopedTaskHash/"
    $lines = @(& git -C $Adapter.RepositoryRoot ls-remote $Adapter.RemoteName "$prefix*" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Pending fork-recovery index could not be listed.' }
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        $parts = ([string]$line) -split "`t", 2
        if ($parts.Count -ne 2 -or [string]$parts[0] -cnotmatch '^[0-9a-f]{40,64}$' -or
            -not ([string]$parts[1]).StartsWith($prefix,[StringComparison]::Ordinal)) {
            throw 'Fork-recovery pending-index listing returned an invalid ref.'
        }
        $document = Read-GitHandoffDocument -Adapter $Adapter -Ref ([string]$parts[1]) -Revision ([string]$parts[0]) -FileName 'index.json'
        if ($document.schemaVersion -ne 1 -or $document.authorityScope -cne [string]$Adapter.AuthorityScope -or
            $document.taskKey -cne $TaskKey -or $document.recordKind -cne 'fork-recovery-index' -or
            [string]::IsNullOrWhiteSpace([string]$document.forkId) -or
            [string]$document.envelopeRevision -cnotmatch '^[0-9a-f]{40,64}$' -or
            [string]$document.status -cnotin @('Pending','Completed','Abandoned') -or
            (Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId ([string]$document.forkId)) -cne [string]$parts[1]) {
            throw 'Fork-recovery pending-index listing does not match its scoped Task Key.'
        }
        $entries.Add([pscustomobject]@{AuthorityScope=[string]$document.authorityScope;
            TaskKey=$TaskKey;ForkId=[string]$document.forkId;Status=[string]$document.status;
            Revision=[string]$document.envelopeRevision;IndexRevision=[string]$parts[0]})
    }
    return $entries.ToArray()
}

function Get-GitHandoffPendingForkRecoveries {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey)
    $indexEntries = @(Get-GitHandoffPendingForkRecoveryIndexEntries -Adapter $Adapter -TaskKey $TaskKey)
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($indexEntry in $indexEntries) {
        if ($indexEntry.Status -ceq 'Pending') {
            try {
                Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:list-item' `
                    -TaskKey $TaskKey -ForkId ([string]$indexEntry.ForkId) | Out-Null
            }
            catch {
                if ($_.Exception.Message -match 'access was denied') { continue }
                throw
            }
            $entries.Add($indexEntry)
        }
    }
    return $entries.ToArray()
}

function Test-GitHandoffPendingForkRecoveryBlocker {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey)
    # Common archival must account for every protected index entry, even when
    # the caller may not inspect an individual recovery. Return no identifiers.
    $indexEntries = @(Get-GitHandoffPendingForkRecoveryIndexEntries -Adapter $Adapter -TaskKey $TaskKey)
    return [pscustomobject]@{HasPending=(@($indexEntries | Where-Object { $_.Status -ceq 'Pending' }).Count -gt 0)}
}

function Get-GitHandoffForkRecoveryTargetEnvelopes {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId)
    $targetDigest = Get-HandoffSha256 -Value $BranchId
    $targetEnvelopes = [Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-GitHandoffPendingForkRecoveries -Adapter $Adapter -TaskKey $TaskKey)) {
        $validated = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $entry.ForkId
        if (@($validated.Record.branchCreationTargetDigests) -ccontains $targetDigest) {
            $targetEnvelopes.Add($validated)
        }
    }
    return $targetEnvelopes.ToArray()
}

function Add-GitHandoffForkRecoveryBranchClaim {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,[Parameter(Mandatory = $true)][string] $OperationId)
    $targetDigest = Get-HandoffSha256 -Value $BranchId
    $operationDigest = Get-HandoffSha256 -Value $OperationId
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $targetEnvelopes = @(Get-GitHandoffForkRecoveryTargetEnvelopes -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId)
        $pending = @($targetEnvelopes | Where-Object { $_.Status -ceq 'Pending' })
        if ($pending.Count -gt 1) { throw 'Multiple Pending fork recoveries target the same branch creation.' }
        if ($pending.Count -eq 0) {
            throw 'Branch creation requires one exact Pending fork recovery for this target.'
        }
        $envelope = $pending[0]
        $claimPrincipal = Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:claim' `
            -TaskKey $TaskKey -ForkId $envelope.ForkId -BranchId $BranchId
        if ([string]$envelope.Record.branchCreationBindings[$targetDigest] -cne $operationDigest) {
            throw 'The branch Operation ID does not match the Pending fork-recovery target-operation binding.'
        }
        $recovery = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $envelope.ForkId
        if ($null -eq $recovery -or $recovery.Status -cne 'Pending') {
            throw 'The isolated fork-recovery payload is not valid and Pending; branch creation remains blocked.'
        }
        if (-not $recovery.Control.branchCreationOperations.Contains($BranchId) -or
            [string]$recovery.Control.branchCreationOperations[$BranchId] -cne $OperationId -or
            -not $recovery.Control.expectedBranchPayloadDigests.Contains($BranchId)) {
            throw 'The protected recovery control does not bind this exact branch and creation operation.'
        }
        $common = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
        if ($null -eq $common -or
            (Get-HandoffCommonSemanticDigest -CommonRecord $common.Record) -cne [string]$recovery.Control.commonSemanticDigest) {
            throw 'The verified common recovery fence changed before the branch target claim.'
        }
        $expectedBranchPayloadDigest = [string]$recovery.Control.expectedBranchPayloadDigests[$BranchId]
        $existingClaim = $envelope.Record.branchCreationClaims[$targetDigest]
        if ($null -ne $existingClaim) {
            if ([string]$existingClaim.operationDigest -cne $operationDigest -or
                [string]$existingClaim.payloadRevision -cne [string]$recovery.Revision -or
                [string]$existingClaim.controlRevision -cne [string]$recovery.ControlRevision -or
                [string]$existingClaim.expectedBranchPayloadDigest -cne $expectedBranchPayloadDigest) {
                throw 'Another operation already claimed this fork-recovery branch target.'
            }
            if ([string]$existingClaim.commonRevision -ceq [string]$common.Revision) {
                return [pscustomobject]@{Envelope=$envelope;ForkId=$envelope.ForkId;Claim=$existingClaim;
                    PayloadDigest=[string]$recovery.Record.payloadDigest}
            }
        }
        $document = $envelope.Record
        $document.branchCreationClaims[$targetDigest] = [ordered]@{
            operationDigest=$operationDigest;verifiedPrincipal=$claimPrincipal;
            commonRevision=[string]$common.Revision;payloadRevision=[string]$recovery.Revision;
            controlRevision=[string]$recovery.ControlRevision;
            expectedBranchPayloadDigest=$expectedBranchPayloadDigest;
            claimedAt=[DateTimeOffset]::UtcNow.ToString('o')
        }
        $ref = Get-HandoffForkRecoveryEnvelopeRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $envelope.ForkId
        $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document `
            -Parent $envelope.Revision -FileName 'envelope.json'
        try {
            Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref `
                -ExpectedRevision $envelope.Revision -Commit $commit | Out-Null
        }
        catch {
            if ($_.Exception.Message -match 'Conditional Handoff revision conflict' -and $attempt -lt 5) { continue }
            throw
        }
        $readback = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $envelope.ForkId
        $claim = $readback.Record.branchCreationClaims[$targetDigest]
        if ($readback.Revision -cne $commit -or [string]$claim.operationDigest -cne $operationDigest -or
            [string]$claim.verifiedPrincipal -cne $claimPrincipal -or
            [string]$claim.commonRevision -cne [string]$common.Revision -or
            [string]$claim.payloadRevision -cne [string]$recovery.Revision -or
            [string]$claim.expectedBranchPayloadDigest -cne $expectedBranchPayloadDigest) {
            throw 'The fork-recovery branch-creation claim was not read back.'
        }
        return [pscustomobject]@{Envelope=$readback;ForkId=$readback.ForkId;Claim=$claim;
            PayloadDigest=[string]$recovery.Record.payloadDigest}
    }
    throw 'The fork-recovery branch target could not be claimed after concurrent envelope changes.'
}

function Get-GitHandoffForkRecoverySourceBinding {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)] $Payload,[Parameter(Mandatory = $true)] $CommonRecord,
        [Parameter(Mandatory = $true)][string] $CommonRevision)
    $sourceBranchId = [string]$Payload['Source Branch ID']
    $activeBranches = @($CommonRecord.activeBranches | ForEach-Object { [string]$_ })
    $sourceBranch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $sourceBranchId
    if ($activeBranches.Count -eq 0) {
        if ($null -ne $sourceBranch) {
            throw 'A common-only fork cannot use an existing source branch while the common Active index is empty.'
        }
        return [pscustomobject]@{BranchId=$sourceBranchId;Revision=$null;ForkPoint=$null;ContinuationGeneration=$null}
    }
    if ($activeBranches -cnotcontains $sourceBranchId) {
        throw 'Fork recovery Source Branch ID must be one exact branch in the live common Active index.'
    }
    if ($null -eq $sourceBranch) {
        throw 'Fork recovery Source Branch ID is indexed Active but its exact branch record is missing.'
    }
    if ([string]$sourceBranch.Fields.Lifecycle -cne 'Active') {
        throw 'Fork recovery Source Branch ID must resolve to a live Active branch.'
    }
    $sourceSnapshot = $Payload['Source Snapshot']
    if ([string]$sourceSnapshot['Current'] -cne [string]$sourceBranch.Fields['Current'] -or
        [string]$sourceSnapshot['Source'] -cne [string]$sourceBranch.Fields['Source']) {
        throw 'Fork recovery Source Snapshot does not match the live source branch Current and Source.'
    }
    return [pscustomobject]@{BranchId=$sourceBranchId;Revision=[string]$sourceBranch.Revision;
        ForkPoint=[string]$sourceBranch.ForkPoint;ContinuationGeneration=[int64]$sourceBranch.ContinuationGeneration}
}

function New-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId,[Parameter(Mandatory = $true)] $Payload,
        [Parameter(Mandatory = $true)][string] $OperationId,[string] $Actor='configured-adapter')
    Assert-HandoffOperationId -OperationId $OperationId
    $verifiedPrincipal = Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:create' -TaskKey $TaskKey -ForkId $ForkId
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'Fork recovery creation requires a nonempty display actor label.' }
    Assert-HandoffForkRecoveryPayload -Payload $Payload
    $envelopeEvidence = Get-HandoffForkRecoveryEnvelopeEvidence -Payload $Payload
    $recordId = Get-HandoffForkRecoveryId -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $digest = Get-HandoffSha256 -Value (([ordered]@{authorityScope=[string]$Adapter.AuthorityScope;
        taskKey=$TaskKey;forkId=$ForkId;payload=$Payload;
        operationId=$OperationId;actor=$Actor}) | ConvertTo-Json -Compress -Depth 50)
    $envelope = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $sourceBinding = $null
    if ($null -eq $envelope) {
        $common = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
        if ($null -eq $common) { throw 'Fork recovery requires the exact common Task Key.' }
        $verifiedCommonRevision = [string]$common.Revision
        $actualActive = @($common.Record.activeBranches | Sort-Object -Unique)
        $declaredActive = @($Payload['Verified Active Branches'] | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (($actualActive | ConvertTo-Json -Compress) -cne ($declaredActive | ConvertTo-Json -Compress)) {
            throw 'Fork recovery Verified Active Branches do not match the exact scoped common index.'
        }
        if ([string]$Payload['Fork Point'] -cne $verifiedCommonRevision) {
            throw 'A fork recovery Fork Point must equal the exact verified common revision.'
        }
        $sourceBinding = Get-GitHandoffForkRecoverySourceBinding -Adapter $Adapter -TaskKey $TaskKey `
            -Payload $Payload -CommonRecord $common.Record -CommonRevision $verifiedCommonRevision
        $createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        $envelopeDocument = [ordered]@{schemaVersion=1;recordKind='fork-recovery-envelope';recordId=$recordId;
            authorityScope=[string]$Adapter.AuthorityScope;taskKey=$TaskKey;forkId=$ForkId;status='Pending';
            payloadDigest=$digest;payloadRevision=$null;verifiedCommonRevisionAtCreation=$verifiedCommonRevision;
            branchCreationTargetDigests=@($envelopeEvidence.BranchCreationTargetDigests);
            branchCreationOperationDigests=@($envelopeEvidence.BranchCreationOperationDigests);
            branchCreationBindings=$envelopeEvidence.BranchCreationBindings;
            branchCreationClaims=[ordered]@{};
            creationOperationId=$OperationId;actor=$Actor;verifiedPrincipal=$verifiedPrincipal;
            createdAt=$createdAt;completionOperationId=$null;
            completionVerifiedPrincipal=$null;completedAt=$null;abandonmentOperationId=$null;
            abandonmentVerifiedPrincipal=$null;abandonmentReason=$null;abandonedAt=$null}
        $envelopeRef = Get-HandoffForkRecoveryEnvelopeRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $envelopeCommit = New-GitHandoffCommit -Adapter $Adapter -Document $envelopeDocument -FileName 'envelope.json'
        $controlDocument = [ordered]@{schemaVersion=1;recordKind='fork-recovery-control';recordId=$recordId;
            authorityScope=[string]$Adapter.AuthorityScope;taskKey=$TaskKey;forkId=$ForkId;
            sourceBranchId=[string]$Payload['Source Branch ID'];sourceAclLocator=[string]$Payload['Source Branch ID'];
            sourceBranchRevision=$sourceBinding.Revision;sourceBranchForkPoint=$sourceBinding.ForkPoint;
            sourceContinuationGeneration=$sourceBinding.ContinuationGeneration;
            branchCreationOperations=$envelopeEvidence.BranchCreationOperations;
            expectedBranchPayloadDigests=$envelopeEvidence.ExpectedBranchPayloadDigests;
            payloadObjectRef=(Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId);
            payloadDigest=$digest;verifiedCommonRevisionAtCreation=$verifiedCommonRevision;
            commonSemanticDigest=(Get-HandoffCommonSemanticDigest -CommonRecord $common.Record);
            creationOperationId=$OperationId;verifiedPrincipal=$verifiedPrincipal;createdAt=$createdAt}
        $controlRef = Get-HandoffForkRecoveryControlRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $controlCommit = New-GitHandoffCommit -Adapter $Adapter -Document $controlDocument -FileName 'control.json'
        $indexDocument = [ordered]@{schemaVersion=1;recordKind='fork-recovery-index';authorityScope=[string]$Adapter.AuthorityScope;
            taskKey=$TaskKey;forkId=$ForkId;status='Pending';envelopeRevision=$envelopeCommit;
            updatedAt=$createdAt}
        $indexRef = Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $indexCommit = New-GitHandoffCommit -Adapter $Adapter -Document $indexDocument -FileName 'index.json'
        $commonFenceCommit = New-GitHandoffCommit -Adapter $Adapter -Document $common.Record `
            -Parent $verifiedCommonRevision -FileName 'record.json'
        $pushOutput = @(& git -C $Adapter.RepositoryRoot push --quiet --atomic `
            "--force-with-lease=${envelopeRef}:" "--force-with-lease=${controlRef}:" `
            "--force-with-lease=${indexRef}:" "--force-with-lease=$($common.Ref):${verifiedCommonRevision}" `
            $Adapter.RemoteName "${envelopeCommit}:${envelopeRef}" "${controlCommit}:${controlRef}" `
            "${indexCommit}:${indexRef}" "${commonFenceCommit}:$($common.Ref)" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Fork recovery envelope, protected control, pending index, and common revision fence were not atomically created: $($pushOutput -join ' ')"
        }
        $envelope = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $control = Read-GitHandoffForkRecoveryControl -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $indexRevision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $indexRef
        $indexReadback = if ($null -eq $indexRevision) { $null } else {
            Read-GitHandoffDocument -Adapter $Adapter -Ref $indexRef -Revision $indexRevision -FileName 'index.json'
        }
        $commonReadback = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
        if ($null -eq $envelope -or $envelope.Revision -cne $envelopeCommit -or
            $null -eq $control -or $control.Revision -cne $controlCommit -or
            $indexRevision -cne $indexCommit -or $null -eq $indexReadback -or
            [string]$indexReadback.status -cne 'Pending' -or
            [string]$indexReadback.envelopeRevision -cne $envelopeCommit -or
            $null -eq $commonReadback -or [string]$commonReadback.Revision -cne $commonFenceCommit) {
            throw "Fork recovery '$ForkId' atomic envelope, control, pending index, and common revision fence were not read back."
        }
    }
    if ($envelope.Status -ceq 'Abandoned') {
        throw 'This fork-recovery envelope was abandoned and its Fork ID cannot be reused.'
    }
    if ($envelope.Record.creationOperationId -cne $OperationId -or $envelope.Record.payloadDigest -cne $digest -or
        [string]$envelope.Record.actor -cne $Actor -or
        (@($envelope.Record.branchCreationTargetDigests) | ConvertTo-Json -Compress) -cne
            (@($envelopeEvidence.BranchCreationTargetDigests) | ConvertTo-Json -Compress) -or
        (@($envelope.Record.branchCreationOperationDigests) | ConvertTo-Json -Compress) -cne
            (@($envelopeEvidence.BranchCreationOperationDigests) | ConvertTo-Json -Compress) -or
        ($envelope.Record.branchCreationBindings | ConvertTo-Json -Compress) -cne
            ($envelopeEvidence.BranchCreationBindings | ConvertTo-Json -Compress)) {
        throw 'A different fork-recovery envelope operation already owns this Task Key and Fork ID.'
    }
    $originPrincipal = [string]$envelope.Record.verifiedPrincipal
    if ([string]::IsNullOrWhiteSpace($originPrincipal)) { throw 'Fork-recovery envelope lacks its verified principal.' }
    $control = Read-GitHandoffForkRecoveryControl -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $indexRef = Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $indexRevision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $indexRef
    if ($null -eq $control -or $null -eq $indexRevision) {
        throw "Fork recovery '$ForkId' has an incomplete initial atomic recovery set."
    }
    $indexDocument = Read-GitHandoffDocument -Adapter $Adapter -Ref $indexRef -Revision $indexRevision -FileName 'index.json'
    if ($indexDocument.schemaVersion -ne 1 -or $indexDocument.recordKind -cne 'fork-recovery-index' -or
        $indexDocument.authorityScope -cne [string]$Adapter.AuthorityScope -or $indexDocument.taskKey -cne $TaskKey -or
        $indexDocument.forkId -cne $ForkId -or [string]$indexDocument.status -cne [string]$envelope.Status -or
        [string]$indexDocument.envelopeRevision -cnotmatch '^[0-9a-f]{40,64}$') {
        throw "Fork recovery '$ForkId' pending index does not match its atomic envelope."
    }
    if ($envelope.Status -ceq 'Pending') {
        & git -C $Adapter.RepositoryRoot merge-base --is-ancestor `
            ([string]$indexDocument.envelopeRevision) ([string]$envelope.Revision) 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Fork recovery '$ForkId' pending index does not descend to the live envelope."
        }
    }
    elseif ([string]$indexDocument.envelopeRevision -cne [string]$envelope.Revision) {
        throw "Fork recovery '$ForkId' terminal index does not match the live envelope."
    }
    if ($control.Record.payloadDigest -cne $digest -or
        [string]$control.Record.creationOperationId -cne $OperationId -or
        [string]$control.Record.verifiedPrincipal -cne $originPrincipal -or
        [string]$control.Record.verifiedCommonRevisionAtCreation -cne
            [string]$envelope.Record.verifiedCommonRevisionAtCreation -or
        ($control.Record.branchCreationOperations | ConvertTo-Json -Compress) -cne
            ($envelopeEvidence.BranchCreationOperations | ConvertTo-Json -Compress) -or
        ($control.Record.expectedBranchPayloadDigests | ConvertTo-Json -Compress) -cne
            ($envelopeEvidence.ExpectedBranchPayloadDigests | ConvertTo-Json -Compress)) {
        throw 'A different protected recovery control already owns this Fork ID.'
    }
    $existing = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -ne $existing) {
        if ($existing.Record.creationOperationId -cne $OperationId -or $existing.Record.payloadDigest -cne $digest) {
            throw 'A different fork-recovery operation already owns this Task Key and Fork ID.'
        }
        if ($envelope.Record.branchCreationClaims.Count -eq 0) {
            Assert-GitHandoffForkRecoveryCommonFence -Adapter $Adapter -TaskKey $TaskKey `
                -ExpectedRevision ([string]$envelope.Record.verifiedCommonRevisionAtCreation) `
                -FailureMessage 'The verified pre-fork common revision changed before branch creation began.' | Out-Null
        }
        return $existing
    }
    Assert-GitHandoffForkRecoveryCommonFence -Adapter $Adapter -TaskKey $TaskKey `
        -ExpectedRevision ([string]$envelope.Record.verifiedCommonRevisionAtCreation) `
        -FailureMessage 'The verified pre-fork common revision changed before the recovery payload became durable.' | Out-Null
    $document = [ordered]@{schemaVersion=1;recordKind='fork-recovery';recordId=$recordId;
        authorityScope=[string]$Adapter.AuthorityScope;taskKey=$TaskKey;
        forkId=$ForkId;status='Pending';payload=$Payload;creationOperationId=$OperationId;payloadDigest=$digest;
        actor=$Actor;verifiedPrincipal=$originPrincipal;createdAt=[DateTimeOffset]::UtcNow.ToString('o');
        completionOperationId=$null;completionVerifiedPrincipal=$null;completedAt=$null}
    $ref = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document -FileName 'recovery.json'
    $envelopeAfterPayload = $envelope.Record
    $envelopeAfterPayload.payloadRevision = $commit
    $envelopeRef = Get-HandoffForkRecoveryEnvelopeRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $envelopeCommit = New-GitHandoffCommit -Adapter $Adapter -Document $envelopeAfterPayload `
        -Parent $envelope.Revision -FileName 'envelope.json'
    Push-GitHandoffForkRecoveryPayloadIfRevisions -Adapter $Adapter `
        -PayloadRef $ref -ExpectedPayloadRevision '' -PayloadCommit $commit `
        -EnvelopeRef $envelopeRef -ExpectedEnvelopeRevision $envelope.Revision -EnvelopeCommit $envelopeCommit | Out-Null
    $readback = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $envelopeReadback = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $readback -or $readback.Revision -cne $commit -or
        $readback.Record.payloadDigest -cne $digest -or $readback.Record.verifiedPrincipal -cne $originPrincipal -or
        $readback.EnvelopeRevision -cne $envelopeCommit -or
        $null -eq $envelopeReadback -or $envelopeReadback.Revision -cne $envelopeCommit -or
        [string]$envelopeReadback.Record.payloadRevision -cne [string]$commit) {
        throw "Fork recovery '$ForkId' creation was not read back."
    }
    Assert-GitHandoffForkRecoveryCommonFence -Adapter $Adapter -TaskKey $TaskKey `
        -ExpectedRevision ([string]$envelope.Record.verifiedCommonRevisionAtCreation) `
        -FailureMessage 'The verified pre-fork common revision changed while the recovery payload was being written.' | Out-Null
    return $readback
}

function Complete-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId,[Parameter(Mandatory = $true)][string] $ExpectedRevision,
        [Parameter(Mandatory = $true)][string] $OperationId)
    Assert-HandoffOperationId -OperationId $OperationId
    $verifiedPrincipal = Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:complete' -TaskKey $TaskKey -ForkId $ForkId
    $current = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $current) { throw 'The exact fork-recovery record was not found.' }
    $commonReadback = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
    if ($null -eq $commonReadback) { throw 'Fork recovery completion requires the exact common record.' }
    foreach ($entry in $current.Control.branchCreationOperations.GetEnumerator()) {
        $branchId = [string]$entry.Key
        $branchReadback = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $branchId
        if ($null -eq $branchReadback -or $branchReadback.Record.forkRecovery.forkId -cne $ForkId -or
            $branchReadback.Record.forkRecovery.creationOperationId -cne [string]$entry.Value -or
            $branchReadback.Record.forkRecovery.expectedBranchPayloadDigest -cne
                [string]$current.Control.expectedBranchPayloadDigests[$branchId]) {
            throw "Fork recovery target '$branchId' was not created from its bound operation and payload."
        }
        $creationFields = [ordered]@{Current=$branchReadback.Record.fields.Current;Source=$branchReadback.Record.fields.Source;
            Lifecycle=$branchReadback.Record.fields.Lifecycle;'Work State'=$branchReadback.Record.fields['Work State']}
        if ((Get-HandoffForkBranchPayloadDigest -ForkPoint ([string]$branchReadback.Record.forkPoint) -Fields $creationFields) -cne
            [string]$current.Control.expectedBranchPayloadDigests[$branchId]) {
            throw "Fork recovery target '$branchId' no longer matches its attested creation payload."
        }
        if ([string]$branchReadback.Record.fields.Lifecycle -ceq 'Active' -and
            @($commonReadback.ActiveBranches) -cnotcontains $branchId) {
            throw "Fork recovery target '$branchId' is not present in the common Active index."
        }
    }
    if ($current.Status -ceq 'Completed') {
        if ($current.Record.completionOperationId -cne $OperationId) { throw 'Fork recovery is already completed by another operation.' }
    }
    else {
        if ($current.Revision -cne $ExpectedRevision) { throw 'Conditional fork-recovery revision conflict.' }
        $document = $current.Record
        $document.status = 'Completed'
        $document.completionOperationId = $OperationId
        $document.completionVerifiedPrincipal = $verifiedPrincipal
        $document.completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        $ref = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document -Parent $current.Revision -FileName 'recovery.json'
        Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision $current.Revision -Commit $commit | Out-Null
        $current = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        if ($current.Revision -cne $commit -or $current.Status -cne 'Completed' -or
            $current.Record.completionOperationId -cne $OperationId -or
            $current.Record.completionVerifiedPrincipal -cne $verifiedPrincipal) {
            throw "Fork recovery '$ForkId' payload completion was not read back."
        }
    }
    $envelope = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $envelope) { throw "Fork recovery '$ForkId' payload-free envelope is missing." }
    $index = Read-GitHandoffForkRecoveryIndex -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $index) { throw "Fork recovery '$ForkId' protected pending index is missing." }
    if ($envelope.Status -ceq 'Pending') {
        if ($index.Status -cne 'Pending') {
            throw "Fork recovery '$ForkId' has a terminal index while its envelope is still Pending."
        }
        & git -C $Adapter.RepositoryRoot merge-base --is-ancestor `
            ([string]$index.Record.envelopeRevision) ([string]$envelope.Revision) 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Fork recovery '$ForkId' pending index does not descend to the live envelope."
        }
        $envelopeDocument = $envelope.Record
        $envelopeDocument.status = 'Completed'
        $envelopeDocument.completionOperationId = $OperationId
        $envelopeDocument.completionVerifiedPrincipal = [string]$current.Record.completionVerifiedPrincipal
        $envelopeDocument.completedAt = [string]$current.Record.completedAt
        $envelopeRef = Get-HandoffForkRecoveryEnvelopeRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $envelopeCommit = New-GitHandoffCommit -Adapter $Adapter -Document $envelopeDocument `
            -Parent $envelope.Revision -FileName 'envelope.json'
        $indexDocument = $index.Record
        $indexDocument.status = 'Completed'
        $indexDocument.envelopeRevision = $envelopeCommit
        $indexDocument.updatedAt = [string]$current.Record.completedAt
        $indexRef = Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
        $indexCommit = New-GitHandoffCommit -Adapter $Adapter -Document $indexDocument `
            -Parent $index.Revision -FileName 'index.json'
        # The common fence is the common ref's payload-free no-op storage cursor, not a separate lock ref.
        # Target/common readbacks above prove the durable cursor can advance through normal reconciliation.
        Push-GitHandoffForkRecoveryTerminalIfRevisions -Adapter $Adapter `
            -EnvelopeRef $envelopeRef -ExpectedEnvelopeRevision $envelope.Revision -EnvelopeCommit $envelopeCommit `
            -IndexRef $indexRef -ExpectedIndexRevision $index.Revision -IndexCommit $indexCommit | Out-Null
    }
    elseif ($envelope.Record.completionOperationId -cne $OperationId) {
        throw 'Fork-recovery envelope is already completed by another operation.'
    }
    $readback = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $indexReadback = Read-GitHandoffForkRecoveryIndex -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($readback.Status -cne 'Completed' -or $readback.EnvelopeStatus -cne 'Completed' -or
        $readback.Record.completionOperationId -cne $OperationId -or $null -eq $indexReadback -or
        $indexReadback.Status -cne 'Completed' -or
        [string]$indexReadback.Record.envelopeRevision -cne [string]$readback.EnvelopeRevision) {
        throw "Fork recovery '$ForkId' completed payload, envelope, and protected index were not read back."
    }
    return $readback
}

function Abandon-GitHandoffForkRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ForkId,[Parameter(Mandatory = $true)][string] $ExpectedEnvelopeRevision,
        [Parameter(Mandatory = $true)][string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Reason)
    Assert-HandoffOperationId -OperationId $OperationId
    $verifiedPrincipal = Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'fork-recovery:abandon' `
        -TaskKey $TaskKey -ForkId $ForkId
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Fork-recovery abandonment requires a concrete reason.' }
    $envelope = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $envelope) { throw 'The exact fork-recovery envelope was not found.' }
    $index = Read-GitHandoffForkRecoveryIndex -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $index) { throw "Fork recovery '$ForkId' protected pending index is missing." }
    if ($envelope.Status -ceq 'Abandoned') {
        if ($envelope.Record.abandonmentOperationId -cne $OperationId) {
            throw 'Fork-recovery envelope is already abandoned by another operation.'
        }
        if ($index.Status -cne 'Abandoned' -or
            [string]$index.Record.envelopeRevision -cne [string]$envelope.Revision) {
            throw 'Fork-recovery abandonment is incomplete because its protected index is not atomically terminal.'
        }
        return $envelope
    }
    if ($envelope.Status -ceq 'Completed') { throw 'A completed fork-recovery envelope cannot be abandoned.' }
    if ($envelope.Record.branchCreationClaims.Count -gt 0) {
        throw 'Fork-recovery abandonment is unsafe because branch creation has already been claimed.'
    }
    if ($envelope.Revision -cne $ExpectedEnvelopeRevision) {
        throw 'Conditional fork-recovery envelope revision conflict.'
    }
    if ($index.Status -cne 'Pending') {
        throw 'Fork-recovery abandonment requires the protected index to remain Pending until the atomic terminal step.'
    }
    & git -C $Adapter.RepositoryRoot merge-base --is-ancestor `
        ([string]$index.Record.envelopeRevision) ([string]$envelope.Revision) 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Fork recovery '$ForkId' pending index does not descend to the live envelope."
    }

    $payloadRef = Get-HandoffForkRecoveryRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($envelope.Record.Contains('payloadRevision') -and $null -ne $envelope.Record.payloadRevision) {
        throw 'Fork-recovery abandonment is unsafe because the isolated payload exists and the envelope already binds it.'
    }
    if ($null -ne (Get-RemoteHandoffRevision -Adapter $Adapter -Ref $payloadRef)) {
        throw 'Fork-recovery abandonment is unsafe because the isolated payload exists.'
    }
    $control = Read-GitHandoffForkRecoveryControl -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($null -eq $control) { throw 'Fork-recovery abandonment requires the protected control record.' }
    $targetDigests = @($envelope.Record.branchCreationTargetDigests)
    $scopedTaskHash = Get-HandoffScopedTaskHash -AuthorityScope ([string]$Adapter.AuthorityScope) -TaskKey $TaskKey
    foreach ($targetEntry in $control.Record.branchCreationOperations.GetEnumerator()) {
        $branchId = [string]$targetEntry.Key
        Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'branch:read' -TaskKey $TaskKey -BranchId $branchId | Out-Null
        $targetDigest = Get-HandoffSha256 -Value $branchId
        $branchRef = "$($Adapter.RefPrefix)/records/$scopedTaskHash/branch/$targetDigest"
        # Branch creation outcomes are embedded in and evented only after a durable branch record.
        # This adapter never deletes record refs, so exact ref absence also proves no target outcome committed.
        if ($null -ne (Get-RemoteHandoffRevision -Adapter $Adapter -Ref $branchRef)) {
            throw 'Fork-recovery abandonment is unsafe because a branch-creation target exists.'
        }
    }
    $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
    if ($null -ne $common) {
        foreach ($branchId in @($common.ActiveBranches)) {
            if ($targetDigests -ccontains (Get-HandoffSha256 -Value ([string]$branchId))) {
                throw 'Fork-recovery abandonment is unsafe because a branch-creation target is indexed.'
            }
        }
    }

    $document = $envelope.Record
    $document.status = 'Abandoned'
    $document.abandonmentOperationId = $OperationId
    $document.abandonmentVerifiedPrincipal = $verifiedPrincipal
    $document.abandonmentReason = $Reason
    $document.abandonedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $envelopeRef = Get-HandoffForkRecoveryEnvelopeRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $document `
        -Parent $envelope.Revision -FileName 'envelope.json'
    $indexDocument = $index.Record
    $indexDocument.status = 'Abandoned'
    $indexDocument.envelopeRevision = $commit
    $indexDocument.updatedAt = [string]$document.abandonedAt
    $indexRef = Get-HandoffForkRecoveryIndexRef -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $indexCommit = New-GitHandoffCommit -Adapter $Adapter -Document $indexDocument `
        -Parent $index.Revision -FileName 'index.json'
    Push-GitHandoffForkRecoveryTerminalIfRevisions -Adapter $Adapter `
        -EnvelopeRef $envelopeRef -ExpectedEnvelopeRevision $envelope.Revision -EnvelopeCommit $commit `
        -IndexRef $indexRef -ExpectedIndexRevision $index.Revision -IndexCommit $indexCommit | Out-Null
    $readback = Read-GitHandoffForkRecoveryEnvelope -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    $indexReadback = Read-GitHandoffForkRecoveryIndex -Adapter $Adapter -TaskKey $TaskKey -ForkId $ForkId
    if ($readback.Revision -cne $commit -or $readback.Status -cne 'Abandoned' -or
        $readback.Record.abandonmentOperationId -cne $OperationId -or
        $readback.Record.abandonmentVerifiedPrincipal -cne $verifiedPrincipal -or
        $readback.Record.abandonmentReason -cne $Reason -or $null -eq $indexReadback -or
        $indexReadback.Revision -cne $indexCommit -or $indexReadback.Status -cne 'Abandoned' -or
        [string]$indexReadback.Record.envelopeRevision -cne [string]$readback.Revision) {
        throw "Fork recovery '$ForkId' abandonment was not read back."
    }
    return $readback
}

function New-GitHandoffAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [Parameter(Mandatory = $true)][string] $AuthorityScope,
        [Parameter(Mandatory = $true)][scriptblock] $GetVerifiedPrincipal,
        [Parameter(Mandatory = $true)][scriptblock] $Authorize,
        [string] $RemoteName='origin',[string] $RefPrefix='refs/heads/handoff-v1')
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $adapter = [pscustomobject]@{ RepositoryRoot=$root;RemoteName=$RemoteName;RefPrefix=$RefPrefix;
        AuthorityScope=$AuthorityScope;GetVerifiedPrincipal=$GetVerifiedPrincipal;Authorize=$Authorize }
    Assert-GitAdapter -Adapter $adapter
    & git -C $root rev-parse --git-dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The selected local Git object store is not a repository.' }
    & git -C $root remote get-url $RemoteName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The selected Git storage remote is not configured.' }
    return $adapter
}

function Get-OperationPayloadDigest {
    param([Parameter(Mandatory = $true)][string] $AuthorityScope,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,
        [Parameter(Mandatory = $true)] $Changes,
        [string] $Actor='configured-adapter',[string] $Reason='initial checkpoint',[bool] $DecisionConfirmed=$false,
        [string] $DecisionCommonRevision,[string] $DecisionBranchRevision,[string] $DecisionBranchContentSha256,
        [Nullable[int64]] $DecisionBranchContinuationGeneration)
    $payload = [ordered]@{ authorityScope=$AuthorityScope;recordKind=$RecordKind; taskKey=$TaskKey; branchId=$BranchId;
        changes=$Changes;actor=$Actor;reason=$Reason;decisionConfirmed=$DecisionConfirmed }
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        $payload.decisionCommonRevision = $DecisionCommonRevision
    }
    if (-not [string]::IsNullOrWhiteSpace($DecisionBranchRevision)) {
        $payload.decisionBranchRevision = $DecisionBranchRevision
        $payload.decisionBranchContentSha256 = $DecisionBranchContentSha256
        $payload.decisionBranchContinuationGeneration = $DecisionBranchContinuationGeneration
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
        [Parameter(Mandatory = $true)][string] $AuthorityScope,
        [Parameter(Mandatory = $true)][string] $VerifiedPrincipal,
        [Parameter(Mandatory = $true)][string] $RecordKind,[Parameter(Mandatory = $true)][string] $RecordId,
        [Parameter(Mandatory = $true)] $Source,[string] $Actor='configured-adapter',
        [string] $Reason='initial checkpoint',[bool] $DecisionConfirmed=$false,[string] $DecisionCommonRevision,
        [string] $DecisionBranchRevision,[string] $DecisionBranchContentSha256,
        [Nullable[int64]] $DecisionBranchContinuationGeneration,
        [switch] $Internal)
    Assert-HandoffOperationId -OperationId $OperationId -Internal:$Internal
    $occurredAt = [DateTimeOffset]::UtcNow.ToString('o')
    $eventIntents = @(
        foreach ($change in $ChangedFields) {
            $field = [string]$change.field
            $intent = [ordered]@{
                authorityScope = $AuthorityScope
                verifiedPrincipal = $VerifiedPrincipal
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
            if (-not [string]::IsNullOrWhiteSpace($DecisionBranchRevision)) {
                $intent.decisionBranchRevision = $DecisionBranchRevision
                $intent.decisionBranchContentSha256 = $DecisionBranchContentSha256
                $intent.decisionBranchContinuationGeneration = $DecisionBranchContinuationGeneration
            }
            $intent
        }
    )
    $operation = [ordered]@{
        authorityScope = $AuthorityScope
        verifiedPrincipal = $VerifiedPrincipal
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
    if (-not [string]::IsNullOrWhiteSpace($DecisionBranchRevision)) {
        $operation.decisionBranchRevision = $DecisionBranchRevision
        $operation.decisionBranchContentSha256 = $DecisionBranchContentSha256
        $operation.decisionBranchContinuationGeneration = $DecisionBranchContinuationGeneration
    }
    return $operation
}

function Get-HandoffFieldValue {
    param([Parameter(Mandatory = $true)] $Record,[Parameter(Mandatory = $true)][string] $Field)
    if ($Field -ceq 'Active Branches') { return ,@($Record.activeBranches) }
    if ($Field -ceq 'Decision Branch Bindings') { return ,@($Record.fields[$Field]) }
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
    $canonicalFields = @('Authority Scope','Task Key','Branch ID','Fork Point','Continuation Generation','Intent','Scope','Current','Source','Lifecycle',
        'Work State','Branch Outcome','Active Branches','Last Activity At','Keep Active Until','Conflict',
        'Candidate Conclusion','Applicability Scope','Fork Baselines','Integrated Decisions','Decision Branch Bindings')
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
        if ([string]$name -ceq 'Continuation Generation') {
            $generationValid = $RecordKind -ceq 'branch' -and $value -is [ValueType] -and $value -isnot [bool]
            if ($generationValid) {
                try {
                    $generationNumber = [decimal]$value
                    $generationValid = $generationNumber -ge 0 -and $generationNumber -eq [Math]::Floor($generationNumber)
                }
                catch { $generationValid = $false }
            }
            if (-not $generationValid) { throw 'Continuation Generation must be a nonnegative branch integer.' }
        }
        if ([string]$name -ceq 'Decision Branch Bindings' -and ($RecordKind -cne 'common' -or -not $DecisionConfirmed)) {
            throw 'Decision Branch Bindings belong only to an explicitly confirmed common decision.'
        }
    }
}

function Assert-HandoffRequiredFields {
    param([Parameter(Mandatory = $true)] $Fields,[Parameter(Mandatory = $true)][ValidateSet('common','branch')][string] $RecordKind)
    $required = if ($RecordKind -eq 'common') {
        @('Authority Scope','Task Key','Intent','Scope','Current','Source','Lifecycle','Work State')
    }
    else {
        @('Authority Scope','Task Key','Branch ID','Fork Point','Continuation Generation','Current','Source','Lifecycle','Work State')
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
        if ($snapshot.authorityScope -cne [string]$Adapter.AuthorityScope -or
            $snapshot.fields['Authority Scope'] -cne [string]$Adapter.AuthorityScope) {
            throw 'An operation record history entry has a mismatched Authority Scope.'
        }
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
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'event:read' -TaskKey $TaskKey -BranchId $BranchId | Out-Null
    $ref = Get-HandoffEventRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId -Field $Field
    $revision = Get-RemoteHandoffRevision -Adapter $Adapter -Ref $ref
    if ($null -eq $revision) { return $null }
    $event = Read-GitHandoffDocument -Adapter $Adapter -Ref $ref -Revision $revision -FileName 'event.json'
    $recordId = Get-HandoffRecordId -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($event.schemaVersion -ne 1 -or $event.AuthorityScope -cne [string]$Adapter.AuthorityScope -or
        $event.TaskKey -cne $TaskKey -or $event.RecordId -cne $recordId -or
        $event.RecordKind -cne $RecordKind -or $event.BranchId -cne $BranchId -or
        $event.OperationId -cne $OperationId -or $event.Field -cne $Field -or
        [string]::IsNullOrWhiteSpace([string]$event.VerifiedPrincipal)) {
        throw 'The exact event ref contains a mismatched immutable field identity.'
    }
    return [pscustomobject]$event
}

function Write-GitHandoffEventIfAbsent {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $OperationId,
        [Parameter(Mandatory = $true)] $Intent,[string] $RecordRevision,[string] $PayloadDigest)
    $field = [string]$Intent.field
    $recordId = [string]$Intent.recordId
    Assert-GitHandoffAuthorized -Adapter $Adapter -Action 'event:write' -TaskKey $TaskKey -BranchId $BranchId | Out-Null
    if ([string]$Intent.authorityScope -cne [string]$Adapter.AuthorityScope) {
        throw 'The durable event intent has a mismatched Authority Scope.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Intent.verifiedPrincipal)) {
        throw 'The durable event intent is missing its verified principal.'
    }
    $ref = Get-HandoffEventRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId -Field $field
    $expected = [ordered]@{
        schemaVersion = 1
        AuthorityScope = [string]$Intent.authorityScope
        VerifiedPrincipal = [string]$Intent.verifiedPrincipal
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
    if ($Intent -is [Collections.IDictionary] -and $Intent.Contains('decisionBranchRevision') -and
        -not [string]::IsNullOrWhiteSpace([string]$Intent['decisionBranchRevision'])) {
        $expected.DecisionBranchRevision = [string]$Intent['decisionBranchRevision']
        $expected.DecisionBranchContentSha256 = [string]$Intent['decisionBranchContentSha256']
        $expected.DecisionBranchContinuationGeneration = [int64]$Intent['decisionBranchContinuationGeneration']
    }
    $existing = Get-GitHandoffEvent -Adapter $Adapter -TaskKey $TaskKey -RecordKind $RecordKind -BranchId $BranchId -OperationId $OperationId -Field $field
    if ($null -ne $existing) {
        $existingComparable = [ordered]@{
            schemaVersion=$existing.schemaVersion;AuthorityScope=$existing.AuthorityScope;VerifiedPrincipal=$existing.VerifiedPrincipal;
            TaskKey=$existing.TaskKey;RecordKind=$existing.RecordKind;RecordId=$existing.RecordId;
            BranchId=$existing.BranchId;OperationId=$existing.OperationId;Field=$existing.Field;PreviousState=$existing.PreviousState;
            NewState=$existing.NewState;OccurredAt=$existing.OccurredAt;Actor=$existing.Actor;Reason=$existing.Reason;
            Source=$existing.Source;RecordRevision=$existing.RecordRevision;IntegrationStatus=$existing.IntegrationStatus;
            ReadbackResult=$existing.ReadbackResult;PayloadDigest=$existing.PayloadDigest
        }
        if ($null -ne $existing.PSObject.Properties['DecisionCommonRevision']) {
            $existingComparable.DecisionCommonRevision = $existing.DecisionCommonRevision
        }
        if ($null -ne $existing.PSObject.Properties['DecisionBranchRevision']) {
            $existingComparable.DecisionBranchRevision = $existing.DecisionBranchRevision
            $existingComparable.DecisionBranchContentSha256 = $existing.DecisionBranchContentSha256
            $existingComparable.DecisionBranchContinuationGeneration = $existing.DecisionBranchContinuationGeneration
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
    if ($operation.authorityScope -cne [string]$Adapter.AuthorityScope) {
        throw "Operation ID '$OperationId' has a mismatched Authority Scope."
    }
    if ([string]::IsNullOrWhiteSpace([string]$operation.verifiedPrincipal)) {
        throw "Operation ID '$OperationId' lacks its immutable verified principal."
    }
    $recordId = Get-HandoffRecordId -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $changes = @($operation.changedFields)
    $intents = @($operation.eventIntents)
    if ($intents.Count -ne $changes.Count) { throw "Operation ID '$OperationId' does not contain one durable event intent per changed field." }
    foreach ($change in $changes) {
        $field = [string]$change.field
        $matchingIntents = @($intents | Where-Object { [string]$_.field -ceq $field })
        if ($matchingIntents.Count -ne 1) { throw "Operation ID '$OperationId' has an ambiguous durable event intent for field '$field'." }
        $intent = $matchingIntents[0]
        if ([string]$intent.operationId -cne $OperationId -or [string]$intent.recordId -cne $recordId -or
            [string]$intent.verifiedPrincipal -cne [string]$operation.verifiedPrincipal -or
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
        AuthorityScope=$read.Record.authorityScope;TaskKey=$read.Record.taskKey;
        RecordId=$read.Record.recordId;Revision=$read.Revision;
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
        AuthorityScope=$read.Record.authorityScope;TaskKey=$read.Record.taskKey;
        BranchId=$read.Record.branchId;ForkPoint=$read.Record.forkPoint;
        ContinuationGeneration=[int64]$read.Record.fields['Continuation Generation'];
        RecordId=$read.Record.recordId;Revision=$read.Revision;Fields=$read.Record.fields;
        LastActivityAt=$read.Record.lastActivityAt
    }
}

function Assert-GitHandoffDecisionOriginRevision {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $Revision)
    $text = @(& git -C $Adapter.RepositoryRoot show "${Revision}:record.json" 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'The bound common decision revision cannot be read.' }
    try { $bound = $text | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw 'The bound common decision revision is not valid JSON.' }
    if ($bound.recordKind -cne 'common' -or $bound.authorityScope -cne [string]$Adapter.AuthorityScope -or
        $bound.taskKey -cne $TaskKey -or -not $bound.fields.Contains('Decision Branch Bindings')) {
        throw 'The bound common revision is not a scoped branch decision.'
    }
    $parentRevision = [string](& git -C $Adapter.RepositoryRoot rev-parse "${Revision}^" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $parentRevision -cnotmatch '^[0-9a-f]{40,64}$') {
        throw 'A common decision must be a mutation of an existing common record.'
    }
    $parentText = @(& git -C $Adapter.RepositoryRoot show "${parentRevision}:record.json" 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'The common decision parent cannot be read.' }
    try { $parent = $parentText | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw 'The common decision parent is not valid JSON.' }
    $newOperationIds = @($bound.operations.Keys | Where-Object { -not $parent.operations.Contains([string]$_) })
    $decisionOperations = @(
        foreach ($operationId in $newOperationIds) {
            $operation = $bound.operations[[string]$operationId]
            if ($operation.decisionConfirmed -ne $true) { continue }
            $bindingChanges = @($operation.changedFields | Where-Object {
                [string]$_.field -ceq 'Decision Branch Bindings'
            })
            if ($bindingChanges.Count -eq 1 -and
                (Test-HandoffValueEqual -Left $bindingChanges[0].new -Right $bound.fields['Decision Branch Bindings'])) {
                $operation
            }
        }
    )
    if ($decisionOperations.Count -ne 1) {
        throw 'The supplied common revision did not originate the confirmed branch decision.'
    }
    return $bound
}

function Assert-GitHandoffDecisionCommonRevision {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $ExpectedRevision,[switch] $AllowStructuralDescendant)
    if ($ExpectedRevision -cnotmatch '^[0-9a-f]{40,64}$') { throw 'A verified common decision revision is required.' }
    $current = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
    if ($null -eq $current) { throw 'The common decision record is missing.' }
    [void](Assert-GitHandoffDecisionOriginRevision -Adapter $Adapter -TaskKey $TaskKey -Revision $ExpectedRevision)
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
    if ($bound.recordKind -cne 'common' -or $bound.authorityScope -cne [string]$Adapter.AuthorityScope -or
        $bound.fields['Authority Scope'] -cne [string]$Adapter.AuthorityScope -or $bound.taskKey -cne $TaskKey -or
        -not (Test-HandoffValueEqual -Left $bound.fields -Right $current.Record.fields)) {
        throw 'The common decision fields changed during branch finalization; reconcile from the current decision.'
    }
    return $current
}

function Get-GitHandoffReviewedBranchContentSha256 {
    param([Parameter(Mandatory = $true)] $Record)
    if ($Record.recordKind -cne 'branch') { throw 'Reviewed branch identity requires a branch record.' }
    $fieldNames = [string[]]@($Record.fields.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($fieldNames,[StringComparer]::Ordinal)
    $reviewedFields = [ordered]@{}
    foreach ($name in $fieldNames) {
        if ($name -cin @('Lifecycle','Branch Outcome','Last Activity At')) { continue }
        $reviewedFields[$name] = $Record.fields[$name]
    }
    $identity = [ordered]@{
        taskKey = [string]$Record.taskKey
        branchId = [string]$Record.branchId
        forkPoint = [string]$Record.forkPoint
        fields = $reviewedFields
    }
    return Get-HandoffSha256 -Value ($identity | ConvertTo-Json -Compress -Depth 50)
}

function Assert-GitHandoffDecisionBranchBindingShape {
    param([Parameter(Mandatory = $true)] $Binding)
    if ($Binding -isnot [Collections.IDictionary]) { throw 'Each Decision Branch Binding must be a mapping.' }
    $requiredNames = @('branchId','reviewedRevision','reviewedContentSha256','continuationGeneration','outcome')
    $actualNames = @($Binding.Keys | ForEach-Object { [string]$_ })
    if ($actualNames.Count -ne $requiredNames.Count -or
        @($actualNames | Where-Object { $_ -cnotin $requiredNames }).Count -gt 0) {
        throw 'Each Decision Branch Binding must contain only branchId, reviewedRevision, reviewedContentSha256, continuationGeneration, and outcome.'
    }
    foreach ($name in $requiredNames) {
        if (-not $Binding.Contains($name) -or [string]::IsNullOrWhiteSpace([string]$Binding[$name])) {
            throw "Decision Branch Binding is missing '$name'."
        }
    }
    if ([string]$Binding['reviewedRevision'] -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$Binding['reviewedContentSha256'] -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Decision Branch Binding has an invalid reviewed revision or content identity.'
    }
    if ([string]$Binding['outcome'] -cnotin @('Selected','Partially Selected','Superseded')) {
        throw 'Decision Branch Binding has an invalid intended outcome.'
    }
    $generation = $Binding['continuationGeneration']
    if ($generation -isnot [ValueType] -or $generation -is [bool] -or [decimal]$generation -lt 0 -or
        [decimal]$generation -ne [Math]::Floor([decimal]$generation)) {
        throw 'Decision Branch Binding has an invalid Continuation Generation.'
    }
}

function Get-GitHandoffBranchReviewBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [Parameter(Mandatory = $true)][ValidateSet('Selected','Partially Selected','Superseded')][string] $Outcome)
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $read) { throw 'The exact reviewed branch could not be found.' }
    return [ordered]@{
        branchId = $BranchId
        reviewedRevision = [string]$read.Revision
        reviewedContentSha256 = Get-GitHandoffReviewedBranchContentSha256 -Record $read.Record
        continuationGeneration = [int64]$read.Record.fields['Continuation Generation']
        outcome = $Outcome
    }
}

function Assert-GitHandoffDecisionBranchBindingsForWrite {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)] $Bindings,[switch] $AllowFinalizationDescendant)
    $items = @($Bindings)
    if ($items.Count -eq 0) { throw 'A branch selection decision requires at least one Decision Branch Binding.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($binding in $items) {
        Assert-GitHandoffDecisionBranchBindingShape -Binding $binding
        $branchId = [string]$binding['branchId']
        if (-not $seen.Add($branchId)) { throw "Decision Branch Binding duplicates Branch ID '$branchId'." }
        $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $branchId
        if ($null -eq $read) { throw "Decision Branch Binding branch '$branchId' is missing." }
        $reviewedRevision = [string]$binding['reviewedRevision']
        if ($read.Revision -cne $reviewedRevision) {
            if (-not $AllowFinalizationDescendant) {
                throw "Reviewed branch '$branchId' changed before the common decision write; renewed user confirmation is required."
            }
            & git -C $Adapter.RepositoryRoot merge-base --is-ancestor $reviewedRevision $read.Revision 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Reviewed branch '$branchId' no longer descends from its bound revision." }
        }
        if ([int64]$read.Record.fields['Continuation Generation'] -ne [int64]$binding['continuationGeneration']) {
            throw "Reviewed branch '$branchId' was explicitly continued; renewed user confirmation is required."
        }
        $actualIdentity = Get-GitHandoffReviewedBranchContentSha256 -Record $read.Record
        if ($actualIdentity -cne [string]$binding['reviewedContentSha256']) {
            throw "Reviewed branch '$branchId' content changed; renewed user confirmation is required."
        }
    }
}

function Get-GitHandoffDecisionBranchBinding {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [Parameter(Mandatory = $true)][string] $DecisionCommonRevision)
    Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
        -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
    $text = @(& git -C $Adapter.RepositoryRoot show "${DecisionCommonRevision}:record.json" 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'The bound common decision record cannot be read.' }
    try { $bound = $text | ConvertFrom-Json -AsHashtable -Depth 50 }
    catch { throw 'The bound common decision record is not valid JSON.' }
    if ($bound.recordKind -cne 'common' -or $bound.authorityScope -cne [string]$Adapter.AuthorityScope -or
        $bound.fields['Authority Scope'] -cne [string]$Adapter.AuthorityScope -or $bound.taskKey -cne $TaskKey) {
        throw 'The bound common decision record has a mismatched scoped identity.'
    }
    if (-not $bound.fields.Contains('Decision Branch Bindings')) {
        throw 'The common decision has no reviewed branch bindings; renewed user confirmation is required.'
    }
    $matches = @($bound.fields['Decision Branch Bindings'] | Where-Object {
        $_ -is [Collections.IDictionary] -and [string]$_['branchId'] -ceq $BranchId
    })
    if ($matches.Count -ne 1) { throw "The common decision does not contain exactly one binding for branch '$BranchId'." }
    Assert-GitHandoffDecisionBranchBindingShape -Binding $matches[0]
    return $matches[0]
}

function Assert-GitHandoffDecisionBranchBinding {
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [Parameter(Mandatory = $true)][string] $DecisionCommonRevision,[string] $ExpectedOutcome)
    $binding = Get-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
        -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision
    if (-not [string]::IsNullOrWhiteSpace($ExpectedOutcome) -and
        [string]$binding['outcome'] -cne $ExpectedOutcome) {
        throw "Branch '$BranchId' outcome does not match the reviewed common decision binding."
    }
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $read) { throw "Reviewed branch '$BranchId' is missing during finalization." }
    $reviewedRevision = [string]$binding['reviewedRevision']
    if ($read.Revision -cne $reviewedRevision) {
        & git -C $Adapter.RepositoryRoot merge-base --is-ancestor $reviewedRevision $read.Revision 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Reviewed branch '$BranchId' no longer descends from its bound revision." }
    }
    if ([int64]$read.Record.fields['Continuation Generation'] -ne [int64]$binding['continuationGeneration']) {
        throw "Reviewed branch '$BranchId' was explicitly continued during finalization; renewed user confirmation is required."
    }
    $actualIdentity = Get-GitHandoffReviewedBranchContentSha256 -Record $read.Record
    if ($actualIdentity -cne [string]$binding['reviewedContentSha256']) {
        throw "Reviewed branch '$BranchId' content changed during finalization; renewed user confirmation is required."
    }
    return [pscustomobject]@{
        BranchId=$BranchId;ReviewedRevision=$reviewedRevision;
        ReviewedContentSha256=[string]$binding['reviewedContentSha256'];
        ReviewedContinuationGeneration=[int64]$binding['continuationGeneration'];Outcome=[string]$binding['outcome'];
        CurrentRevision=[string]$read.Revision
    }
}

function New-GitHandoffRecord {
    param($Adapter,[string] $RecordKind,[string] $TaskKey,[string] $BranchId,[string] $ForkPoint,
        [Parameter(Mandatory = $true)] $Fields,[string] $OperationId,
        [Parameter(Mandatory = $true)][string] $Actor)
    Assert-HandoffOperationId -OperationId $OperationId
    $verifiedPrincipal = Assert-GitHandoffAuthorized -Adapter $Adapter -Action "${RecordKind}:create" -TaskKey $TaskKey -BranchId $BranchId
    Assert-HandoffFieldsSafe -Fields $Fields -RecordKind $RecordKind
    if ([string]::IsNullOrWhiteSpace($Actor)) { throw 'A Handoff creation event requires a nonempty display actor label.' }
    $creationManagedFields = @($Fields.Keys | Where-Object {
        [string]$_ -ieq 'Authority Scope' -or [string]$_ -ieq 'Continuation Generation' -or
        [string]$_ -ieq 'Active Branches' -or [string]$_ -ieq 'Last Activity At'
    })
    if ($creationManagedFields.Count -gt 0) {
        throw "Authority Scope, Continuation Generation, Active Branches, and Last Activity At are system-managed fields; create the record without caller values."
    }
    $recordId = Get-HandoffRecordId -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($RecordKind -eq 'branch' -and [string]::IsNullOrWhiteSpace($ForkPoint)) { throw 'Fork Point is required.' }
    $logicalFields = [ordered]@{ 'Authority Scope'=[string]$Adapter.AuthorityScope;'Task Key'=$TaskKey }
    if ($RecordKind -eq 'branch') {
        $logicalFields['Branch ID'] = $BranchId
        $logicalFields['Fork Point'] = $ForkPoint
        $logicalFields['Continuation Generation'] = [int64]0
    }
    foreach ($field in $Fields.Keys) {
        if ($logicalFields.Contains([string]$field)) { throw "A system identity field was duplicated: '$field'." }
        $logicalFields[[string]$field] = $Fields[$field]
    }
    Assert-HandoffRequiredFields -Fields $logicalFields -RecordKind $RecordKind
    if ($logicalFields.Lifecycle -cne 'Active') { throw 'A new Handoff record starts Active; exact Archived continuation uses restore.' }
    $payload = [ordered]@{ fields=$logicalFields;forkPoint=$ForkPoint }
    $digest = Get-OperationPayloadDigest -AuthorityScope ([string]$Adapter.AuthorityScope) `
        -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -Changes $payload -Actor $Actor
    $old = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -ne $old) {
        $existingOp = $old.Record.operations[$OperationId]
        if ($null -eq $existingOp -or $existingOp.payloadDigest -cne $digest) {
            throw 'A different Handoff record or operation already owns this exact Task Key and Branch ID.'
        }
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
        return [pscustomobject]@{RecordId=$recordId;Revision=$old.Revision;Status='already-created'}
    }
    $forkClaimContext = $null
    if ($RecordKind -eq 'branch') {
        $forkClaimContext = Add-GitHandoffForkRecoveryBranchClaim -Adapter $Adapter -TaskKey $TaskKey `
            -BranchId $BranchId -OperationId $OperationId
        $proposedPayloadDigest = Get-HandoffForkBranchPayloadDigest -ForkPoint $ForkPoint -Fields $Fields
        if ($proposedPayloadDigest -cne [string]$forkClaimContext.Claim.expectedBranchPayloadDigest) {
            throw 'The proposed branch Fork Point or fields do not match the attested recovery payload.'
        }
    }
    $changes = @(
        foreach ($field in $logicalFields.Keys) { [ordered]@{field=[string]$field;previous=$null;new=$logicalFields[$field]} }
    )
    $operation = New-HandoffOperation -PayloadDigest $digest -OperationId $OperationId -ChangedFields $changes `
        -AuthorityScope ([string]$Adapter.AuthorityScope) -VerifiedPrincipal $verifiedPrincipal `
        -RecordKind $RecordKind -RecordId $recordId `
        -Source $logicalFields.Source -Actor $Actor
    $record = [ordered]@{
        schemaVersion=1;recordKind=$RecordKind;recordId=$recordId;
        authorityScope=[string]$Adapter.AuthorityScope;taskKey=$TaskKey;
        branchId= $(if ($RecordKind -eq 'branch') { $BranchId } else { $null });
        forkPoint= $(if ($RecordKind -eq 'branch') { $ForkPoint } else { $null });
        fields=$logicalFields;activeBranches=@();lastActivityAt=$operation.occurredAt;
        operations=[ordered]@{ $OperationId=$operation }
    }
    if ($RecordKind -eq 'branch') {
        $record.forkRecovery = [ordered]@{forkId=[string]$forkClaimContext.ForkId;
            creationOperationId=$OperationId;payloadDigest=[string]$forkClaimContext.PayloadDigest;
            payloadRevision=[string]$forkClaimContext.Claim.payloadRevision;
            controlRevision=[string]$forkClaimContext.Claim.controlRevision;
            claimEnvelopeRevision=[string]$forkClaimContext.Envelope.Revision;
            expectedBranchPayloadDigest=[string]$forkClaimContext.Claim.expectedBranchPayloadDigest;
            commonRevision=[string]$forkClaimContext.Claim.commonRevision}
    }
    $ref = Get-HandoffRecordRef -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    $commit = New-GitHandoffCommit -Adapter $Adapter -Document $record -FileName 'record.json'
    $commonFenceRevision = $null
    if ($RecordKind -eq 'branch') {
        $common = Read-GitHandoffRecord -Adapter $Adapter -RecordKind common -TaskKey $TaskKey
        if ($null -eq $common -or $common.Revision -cne [string]$forkClaimContext.Claim.commonRevision) {
            throw 'The common recovery fence changed before the bound branch write; no branch was written.'
        }
        $commonFenceCommit = New-GitHandoffCommit -Adapter $Adapter -Document $common.Record `
            -Parent $common.Revision -FileName 'record.json'
        $atomicReadback = Push-GitHandoffForkBranchIfCommonRevision -Adapter $Adapter -BranchRef $ref `
            -BranchCommit $commit -CommonRef $common.Ref -ExpectedCommonRevision $common.Revision `
            -CommonFenceCommit $commonFenceCommit
        $commonFenceRevision = [string]$atomicReadback.CommonRevision
    }
    else {
        Push-GitHandoffIfRevision -Adapter $Adapter -Ref $ref -ExpectedRevision '' -Commit $commit | Out-Null
    }
    $read = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $read -or $read.Revision -cne $commit -or $read.Record.operations[$OperationId].payloadDigest -cne $digest) {
        throw "Record creation for Operation ID '$OperationId' was not fully read back; retain the exact ID."
    }
    Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
    return [pscustomobject]@{RecordId=$recordId;Revision=$read.Revision;Status='created';
        CommonFenceRevision=$commonFenceRevision}
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
        [string] $Reason,[switch] $InternalOperation,[switch] $LifecycleReconciliation)
    Assert-HandoffOperationId -OperationId $OperationId -Internal:$InternalOperation
    $verifiedPrincipal = Assert-GitHandoffAuthorized -Adapter $Adapter -Action "${RecordKind}:update" -TaskKey $TaskKey -BranchId $BranchId
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
    if ($hasBranchOutcome -and $Changes.Count -ne 1) {
        throw 'A decision-bound Branch Outcome mutation may change only Branch Outcome.'
    }
    $isArchive = ($RecordKind -eq 'branch' -and $Changes.Contains('Lifecycle') -and
        [string]$Changes['Lifecycle'] -ceq 'Archived')
    $hasDecisionBranchBindings = ($RecordKind -eq 'common' -and $Changes.Contains('Decision Branch Bindings'))
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision) -and
        ($RecordKind -ne 'branch' -or (-not $hasBranchOutcome -and -not $isArchive))) {
        throw 'A common decision revision may bind only Branch Outcome or branch archival.'
    }
    $old = Read-GitHandoffRecord -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $old) { throw 'The exact Handoff record could not be found; no replacement was created.' }
    if ($RecordKind -eq 'branch' -and $ExplicitContinuation) {
        if (-not $Changes.Contains('Continuation Generation') -or
            [int64]$Changes['Continuation Generation'] -ne ([int64]$old.Record.fields['Continuation Generation'] + 1)) {
            throw 'Explicit branch continuation must increment Continuation Generation exactly once.'
        }
        $unexpectedContinuationFields = @($Changes.Keys | Where-Object {
            [string]$_ -cne 'Continuation Generation' -and [string]$_ -cne 'Lifecycle'
        })
        if ($unexpectedContinuationFields.Count -gt 0 -or
            ($Changes.Contains('Lifecycle') -and [string]$Changes['Lifecycle'] -cne 'Active')) {
            throw 'Explicit branch continuation may change only Continuation Generation and optional Lifecycle Active.'
        }
        if ([string]$old.Record.fields.Lifecycle -ceq 'Archived' -and
            (-not $Changes.Contains('Lifecycle') -or [string]$Changes['Lifecycle'] -cne 'Active')) {
            throw 'Explicit continuation of an Archived branch must atomically restore Lifecycle Active.'
        }
    }
    elseif ($RecordKind -eq 'branch' -and $Changes.Contains('Continuation Generation')) {
        throw 'Continuation Generation changes only during exact explicit continuation of that branch.'
    }
    $existingOp = $old.Record.operations[$OperationId]
    if ($null -ne $existingOp) {
        # Finish immutable evidence for an already committed mutation before any current-state
        # decision, reviewed-content, or generation check can reject the retry.
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey `
            -BranchId $BranchId -OperationId $OperationId | Out-Null
    }
    if ($hasDecisionBranchBindings) {
        Assert-GitHandoffDecisionBranchBindingsForWrite -Adapter $Adapter -TaskKey $TaskKey `
            -Bindings $Changes['Decision Branch Bindings'] -AllowFinalizationDescendant:($null -ne $existingOp)
    }
    $decisionBranchBinding = $null
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        $expectedOutcome = if ($hasBranchOutcome) { [string]$Changes['Branch Outcome'] } else { '' }
        $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
            -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision -ExpectedOutcome $expectedOutcome
        if ([string]$decisionBranchBinding.CurrentRevision -cne [string]$old.Revision) {
            throw "Reviewed branch '$BranchId' changed while preparing finalization; re-read before retrying."
        }
    }
    $decisionBranchRevision = if ($null -ne $decisionBranchBinding) { [string]$decisionBranchBinding.ReviewedRevision } else { '' }
    $decisionBranchContentSha256 = if ($null -ne $decisionBranchBinding) { [string]$decisionBranchBinding.ReviewedContentSha256 } else { '' }
    $decisionBranchContinuationGeneration = if ($null -ne $decisionBranchBinding) {
        [Nullable[int64]]$decisionBranchBinding.ReviewedContinuationGeneration
    } else { $null }
    $digest = Get-OperationPayloadDigest -AuthorityScope ([string]$Adapter.AuthorityScope) `
        -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -Changes $Changes `
        -Actor $Actor -Reason $Reason -DecisionConfirmed ([bool]$DecisionConfirmed) `
        -DecisionCommonRevision $DecisionCommonRevision -DecisionBranchRevision $decisionBranchRevision `
        -DecisionBranchContentSha256 $decisionBranchContentSha256 `
        -DecisionBranchContinuationGeneration $decisionBranchContinuationGeneration
    if ($null -ne $existingOp) {
        if ($existingOp.payloadDigest -cne $digest) { throw 'An Operation ID was reused with different changed fields.' }
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
            Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
        }
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind $RecordKind -TaskKey $TaskKey -BranchId $BranchId -OperationId $OperationId | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
            $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
                -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision -ExpectedOutcome $expectedOutcome
        }
        return [pscustomobject]@{RecordId=$old.Record.recordId;Revision=$old.Revision;Status='already-applied';
            DecisionCommonRevision=$DecisionCommonRevision;DecisionBranchRevision=$decisionBranchRevision;
            DecisionBranchContentSha256=$decisionBranchContentSha256;
            DecisionBranchContinuationGeneration=$decisionBranchContinuationGeneration}
    }
    if ($old.Revision -cne $ExpectedRevision) { throw 'Conditional Handoff revision conflict; re-read formal authority and records.' }
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
            -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
    }
    if ($Changes.Contains('Lifecycle')) {
        if ($RecordKind -eq 'branch' -and -not $LifecycleReconciliation) {
            throw 'Branch Lifecycle changes must use Set-GitHandoffBranchLifecycle so the common Active index is reconciled.'
        }
        if ($Changes.Lifecycle -ceq 'Archived' -and $Changes.Count -ne 1) {
            throw 'Archival changes Lifecycle alone and never refreshes material activity.'
        }
        if ($old.Record.fields.Lifecycle -ceq 'Archived' -and $Changes.Lifecycle -ceq 'Active' -and -not $ExplicitContinuation) {
            throw 'Only exact explicit continuation can restore an Archived Handoff.'
        }
        if ($RecordKind -eq 'common' -and $Changes.Lifecycle -ceq 'Archived' -and @($old.Record.activeBranches).Count -gt 0) {
            throw 'An indexed Active branch protects common; reconcile branch and index before common archival.'
        }
        if ($RecordKind -eq 'common' -and $Changes.Lifecycle -ceq 'Archived') {
            $pendingRecoveryBlocker = Test-GitHandoffPendingForkRecoveryBlocker -Adapter $Adapter -TaskKey $TaskKey
            if ($pendingRecoveryBlocker.HasPending) {
                throw 'A Pending fork recovery protects common until every branch creation and index step is reconciled.'
            }
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
        if ($fieldName -cin @('Authority Scope','Task Key','Branch ID','Fork Point','Last Activity At')) {
            throw 'Handoff identity and activity cannot be replaced through changed fields.'
        }
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
        if ($hasDecisionBranchBindings) {
            Assert-GitHandoffDecisionBranchBindingsForWrite -Adapter $Adapter -TaskKey $TaskKey `
                -Bindings $Changes['Decision Branch Bindings']
        }
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
            $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
                -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision -ExpectedOutcome $expectedOutcome
        }
        return [pscustomobject]@{RecordId=$old.Record.recordId;Revision=$old.Revision;Status='no-op';
            DecisionCommonRevision=$DecisionCommonRevision;DecisionBranchRevision=$decisionBranchRevision;
            DecisionBranchContentSha256=$decisionBranchContentSha256;
            DecisionBranchContinuationGeneration=$decisionBranchContinuationGeneration}
    }
    $operation = New-HandoffOperation -PayloadDigest $digest -OperationId $OperationId -ChangedFields $actualChanges.ToArray() `
        -AuthorityScope ([string]$Adapter.AuthorityScope) -VerifiedPrincipal $verifiedPrincipal -RecordKind $RecordKind `
        -RecordId ([string]$old.Record.recordId) -Source $newRecord.fields.Source `
        -Actor $Actor -Reason $Reason -DecisionConfirmed ([bool]$DecisionConfirmed) `
        -DecisionCommonRevision $DecisionCommonRevision -DecisionBranchRevision $decisionBranchRevision `
        -DecisionBranchContentSha256 $decisionBranchContentSha256 `
        -DecisionBranchContinuationGeneration $decisionBranchContinuationGeneration -Internal:$InternalOperation
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
        $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
            -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision -ExpectedOutcome $expectedOutcome
    }
    if ($hasDecisionBranchBindings) {
        Assert-GitHandoffDecisionBranchBindingsForWrite -Adapter $Adapter -TaskKey $TaskKey `
            -Bindings $read.Record.fields['Decision Branch Bindings'] -AllowFinalizationDescendant
    }
    return [pscustomobject]@{RecordId=$read.Record.recordId;Revision=$read.Revision;Status='updated';
        DecisionCommonRevision=$DecisionCommonRevision;DecisionBranchRevision=$decisionBranchRevision;
        DecisionBranchContentSha256=$decisionBranchContentSha256;
        DecisionBranchContinuationGeneration=$decisionBranchContinuationGeneration}
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
                Lifecycle=$effectiveLifecycle;ContinuationGeneration=$verifiedBranch.ContinuationGeneration;Indexed=$shouldBeIndexed;
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
                    CommonRevision=$verifiedCommon.Revision;Lifecycle=$effectiveLifecycle;
                    ContinuationGeneration=$verifiedBranch.ContinuationGeneration;Indexed=$shouldBeIndexed;
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
        throw 'Only exact explicit continuation can begin or restore an Active branch generation.'
    }
    if ([string]::IsNullOrWhiteSpace($Reason)) {
        $Reason = if ($Lifecycle -ceq 'Archived') { 'archive the exact peer after the validated Gate' }
            else { 'restore the exact peer on explicit continuation' }
    }
    $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
    $branch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId
    if ($null -eq $common -or $null -eq $branch) { throw 'The exact common or branch record is missing; no lifecycle write was made.' }
    $existing = Read-GitHandoffRecord -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId
    $existingOperation = $existing.Record.operations[$OperationId]
    if ($null -ne $existingOperation) {
        Complete-GitHandoffEvents -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey `
            -BranchId $BranchId -OperationId $OperationId | Out-Null
    }
    $decisionBranchBinding = $null
    if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
        $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
            -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision
        if ($Lifecycle -ceq 'Archived' -and
            [string]$branch.Fields['Branch Outcome'] -cne [string]$decisionBranchBinding.Outcome) {
            throw 'Decision-driven archival requires the exact bound Branch Outcome to be recorded first.'
        }
        if ([string]$decisionBranchBinding.CurrentRevision -cne [string]$branch.Revision) {
            throw "Reviewed branch '$BranchId' changed while preparing archival; re-read before retrying."
        }
    }
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
    $needsActiveContinuationWrite = ($Lifecycle -ceq 'Active' -and $ExplicitContinuation -and $null -eq $existingOperation)
    if ($branch.Fields.Lifecycle -cne $Lifecycle -or $needsActiveContinuationWrite) {
        $lifecycleChanges = if ($Lifecycle -ceq 'Active') {
            [ordered]@{Lifecycle='Active';'Continuation Generation'=([int64]$branch.Fields['Continuation Generation'] + 1)}
        }
        else { [ordered]@{Lifecycle=$Lifecycle} }
        Invoke-GitHandoffFieldsMutation -Adapter $Adapter -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId -ExpectedRevision $branch.Revision `
            -Changes $lifecycleChanges -OperationId $OperationId -SuppressActivity:($Lifecycle -ceq 'Archived') `
            -DecisionCommonRevision $DecisionCommonRevision -ExplicitContinuation:$ExplicitContinuation `
            -Actor $Actor -Reason $Reason -LifecycleReconciliation | Out-Null
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision) -and $null -eq $existingOperation) {
            throw 'The branch already has the requested lifecycle but no matching decision-bound operation; reconcile explicitly.'
        }
        if ($null -ne $existingOperation) {
            $lifecycleChanges = @($existingOperation.changedFields | Where-Object {
                [string]$_.field -ceq 'Lifecycle' -and [string]$_.new -ceq $Lifecycle
            })
            if ($Lifecycle -ceq 'Archived' -and $lifecycleChanges.Count -ne 1) {
                throw 'The supplied lifecycle Operation ID does not own this branch lifecycle transition.'
            }
            if ($Lifecycle -ceq 'Active') {
                if ($lifecycleChanges.Count -gt 1) {
                    throw 'The supplied continuation Operation ID has ambiguous Lifecycle changes.'
                }
                $generationChanges = @($existingOperation.changedFields | Where-Object {
                    [string]$_.field -ceq 'Continuation Generation'
                })
                $unexpectedContinuationChanges = @($existingOperation.changedFields | Where-Object {
                    [string]$_.field -cne 'Continuation Generation' -and [string]$_.field -cne 'Lifecycle'
                })
                if ($generationChanges.Count -ne 1 -or
                    $unexpectedContinuationChanges.Count -gt 0 -or
                    [int64]$generationChanges[0].new -ne ([int64]$generationChanges[0].previous + 1) -or
                    [int64]$existing.Record.fields['Continuation Generation'] -ne [int64]$generationChanges[0].new) {
                    throw 'The supplied continuation Operation ID does not own one exact Continuation Generation increment.'
                }
                $expectedRestoreChanges = [ordered]@{
                    Lifecycle='Active';'Continuation Generation'=[int64]$generationChanges[0].new
                }
                $expectedRestoreDigest = Get-OperationPayloadDigest -AuthorityScope ([string]$Adapter.AuthorityScope) `
                    -RecordKind branch -TaskKey $TaskKey -BranchId $BranchId -Changes $expectedRestoreChanges `
                    -Actor $Actor -Reason $Reason
                if ([string]$existingOperation.payloadDigest -cne $expectedRestoreDigest) {
                    throw 'An explicit continuation retry must retain its original actor and reason.'
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($DecisionCommonRevision)) {
                if (-not ($existingOperation -is [Collections.IDictionary]) -or
                    -not $existingOperation.Contains('decisionCommonRevision') -or
                    [string]$existingOperation['decisionCommonRevision'] -cne $DecisionCommonRevision -or
                    -not $existingOperation.Contains('decisionBranchRevision') -or
                    [string]$existingOperation['decisionBranchRevision'] -cne [string]$decisionBranchBinding.ReviewedRevision -or
                    -not $existingOperation.Contains('decisionBranchContentSha256') -or
                    [string]$existingOperation['decisionBranchContentSha256'] -cne [string]$decisionBranchBinding.ReviewedContentSha256 -or
                    -not $existingOperation.Contains('decisionBranchContinuationGeneration') -or
                    [int64]$existingOperation['decisionBranchContinuationGeneration'] -ne [int64]$decisionBranchBinding.ReviewedContinuationGeneration) {
                    throw 'The existing branch lifecycle operation is not bound to the supplied common decision revision.'
                }
                $expectedArchiveDigest = Get-OperationPayloadDigest -AuthorityScope ([string]$Adapter.AuthorityScope) `
                    -RecordKind branch -TaskKey $TaskKey `
                    -BranchId $BranchId -Changes ([ordered]@{Lifecycle=$Lifecycle}) -Actor $Actor `
                    -Reason $Reason -DecisionCommonRevision $DecisionCommonRevision `
                    -DecisionBranchRevision ([string]$decisionBranchBinding.ReviewedRevision) `
                    -DecisionBranchContentSha256 ([string]$decisionBranchBinding.ReviewedContentSha256) `
                    -DecisionBranchContinuationGeneration ([int64]$decisionBranchBinding.ReviewedContinuationGeneration)
                if ([string]$existingOperation.payloadDigest -cne $expectedArchiveDigest) {
                    throw 'A decision-bound lifecycle retry must retain its original actor and reason.'
                }
                Assert-GitHandoffDecisionCommonRevision -Adapter $Adapter -TaskKey $TaskKey `
                    -ExpectedRevision $DecisionCommonRevision -AllowStructuralDescendant | Out-Null
                $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
                    -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision
            }
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
                $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
                    -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision
            }
            $completedIndexIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                -Purpose 'branch-lifecycle-index' -ParentOperationId $OperationId `
                -BranchId $BranchId -AdditionalOperationIds $indexOperationIds.ToArray())
            $completedRestoreIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                -Purpose 'common-restore' -ParentOperationId $OperationId `
                -BranchId $BranchId -AdditionalOperationIds $commonRestoreOperationIds.ToArray())
            return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$branch.Revision;CommonRevision=$common.Revision;
                Lifecycle=$effectiveLifecycle;ContinuationGeneration=[int64]$branch.Fields['Continuation Generation'];
                Indexed=$indexed;IndexOperationIds=$completedIndexIds;
                CommonRestoreOperationIds=$completedRestoreIds;DecisionCommonRevision=$DecisionCommonRevision;
                DecisionBranchRevision=if ($null -ne $decisionBranchBinding) { $decisionBranchBinding.ReviewedRevision } else { $null };
                DecisionBranchContentSha256=if ($null -ne $decisionBranchBinding) { $decisionBranchBinding.ReviewedContentSha256 } else { $null };
                DecisionBranchContinuationGeneration=if ($null -ne $decisionBranchBinding) { $decisionBranchBinding.ReviewedContinuationGeneration } else { $null }}
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
                    $decisionBranchBinding = Assert-GitHandoffDecisionBranchBinding -Adapter $Adapter -TaskKey $TaskKey `
                        -BranchId $BranchId -DecisionCommonRevision $DecisionCommonRevision
                }
                $completedIndexIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                    -Purpose 'branch-lifecycle-index' -ParentOperationId $OperationId `
                    -BranchId $BranchId -AdditionalOperationIds $indexOperationIds.ToArray())
                $completedRestoreIds = @(Complete-GitHandoffInternalEvents -Adapter $Adapter -TaskKey $TaskKey `
                    -Purpose 'common-restore' -ParentOperationId $OperationId `
                    -BranchId $BranchId -AdditionalOperationIds $commonRestoreOperationIds.ToArray())
                return [pscustomobject]@{BranchId=$BranchId;BranchRevision=$verifiedBranch.Revision;
                    CommonRevision=$verifiedCommon.Revision;Lifecycle=$effectiveLifecycle;
                    ContinuationGeneration=[int64]$verifiedBranch.Fields['Continuation Generation'];Indexed=$shouldBeIndexed;
                    IndexOperationIds=$completedIndexIds;CommonRestoreOperationIds=$completedRestoreIds;
                    DecisionCommonRevision=$DecisionCommonRevision;
                    DecisionBranchRevision=if ($null -ne $decisionBranchBinding) { $decisionBranchBinding.ReviewedRevision } else { $null };
                    DecisionBranchContentSha256=if ($null -ne $decisionBranchBinding) { $decisionBranchBinding.ReviewedContentSha256 } else { $null };
                    DecisionBranchContinuationGeneration=if ($null -ne $decisionBranchBinding) { $decisionBranchBinding.ReviewedContinuationGeneration } else { $null }}
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

function Start-GitHandoffBranchContinuation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
        [Parameter(Mandatory = $true)][string] $BranchId,
        [Parameter(Mandatory = $true)][string] $OperationId,
        [string] $Actor='configured-adapter',[string] $Reason='begin explicit continuation of the exact branch')
    return Set-GitHandoffBranchLifecycle -Adapter $Adapter -TaskKey $TaskKey -BranchId $BranchId `
        -Lifecycle Active -OperationId $OperationId -ExplicitContinuation -Actor $Actor -Reason $Reason
}

Export-ModuleMember -Function New-GitHandoffAdapter,Get-GitHandoffCommon,Get-GitHandoffBranch,Get-GitHandoffEvent,
    Get-GitHandoffForkRecovery,Get-GitHandoffPendingForkRecoveries,New-GitHandoffForkRecovery,Complete-GitHandoffForkRecovery,
    Abandon-GitHandoffForkRecovery,
    Get-GitHandoffBranchReviewBinding,New-GitHandoffCommon,New-GitHandoffBranch,Set-GitHandoffFields,Set-GitHandoffBranchLifecycle,
    Start-GitHandoffBranchContinuation
