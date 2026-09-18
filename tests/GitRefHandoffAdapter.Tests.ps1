# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Optional Git-ref Task Handoff adapter' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1') -Force -ErrorAction Stop
        $script:PriorCommonCreationActorDefault = $PSDefaultParameterValues['New-GitHandoffCommon:Actor']
        $script:PriorBranchCreationActorDefault = $PSDefaultParameterValues['New-GitHandoffBranch:Actor']
        $PSDefaultParameterValues['New-GitHandoffCommon:Actor'] = 'synthetic-test-writer'
        $PSDefaultParameterValues['New-GitHandoffBranch:Actor'] = 'synthetic-test-writer'

        function New-WriterFixture {
            param([string] $Root, [string] $WriterId, [string] $AuthorityScope='synthetic-scope')
            $remote = Join-Path $Root 'remote.git'
            $local = Join-Path $Root $WriterId
            if (-not (Test-Path -LiteralPath $remote)) {
                & git init --bare --quiet $remote
                if ($LASTEXITCODE) { throw 'Could not create isolated bare Git fixture.' }
            }
            & git clone --quiet $remote $local 2>$null
            if ($LASTEXITCODE) { throw 'Could not create a separate test writer.' }
            & git -C $local config user.name "Synthetic $WriterId"
            & git -C $local config user.email "$WriterId@example.invalid"
            return New-GitHandoffAdapter -RepositoryRoot $local -RemoteName origin `
                -AuthorityScope $AuthorityScope -GetVerifiedPrincipal { 'synthetic-principal' } `
                -Authorize { param($request) $true }
        }

        function New-TestGitHandoffBranch {
            param([Parameter(Mandatory = $true)] $Adapter,[Parameter(Mandatory = $true)][string] $TaskKey,
                [Parameter(Mandatory = $true)][string] $BranchId,[Parameter(Mandatory = $true)][string] $ForkPoint,
                [Parameter(Mandatory = $true)] $Fields,[Parameter(Mandatory = $true)][string] $OperationId,
                [string] $Actor='synthetic-test-writer')
            $fixtureForkId = "fixture-$OperationId"
            $pending = @(Get-GitHandoffPendingForkRecoveries -Adapter $Adapter -TaskKey $TaskKey)
            if ($pending.Count -eq 0) {
                $common = Get-GitHandoffCommon -Adapter $Adapter -TaskKey $TaskKey
                if ($null -eq $common) { throw 'The synthetic branch fixture requires common first.' }
                $effectiveForkPoint = [string]$common.Revision
                $sourceBranchId = $BranchId
                $sourceSnapshot = [ordered]@{Current=$Fields.Current;Source=$Fields.Source}
                $sharedBaseline = [ordered]@{Current=$Fields.Current;Source=$Fields.Source}
                if (@($common.ActiveBranches).Count -gt 0) {
                    $sourceBranchId = [string](@($common.ActiveBranches | Sort-Object)[0])
                    $sourceBranch = Get-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey -BranchId $sourceBranchId
                    if ($null -eq $sourceBranch) { throw 'The synthetic branch fixture source branch is missing.' }
                    $sourceSnapshot = [ordered]@{Current=$sourceBranch.Fields.Current;Source=$sourceBranch.Fields.Source}
                }
                $payload = [ordered]@{
                    'Fork Point' = $effectiveForkPoint
                    'Source Branch ID' = $sourceBranchId
                    'Intended Branch IDs' = @($BranchId)
                    'Source Snapshot' = $sourceSnapshot
                    'Shared Baseline' = $sharedBaseline
                    'Verified Active Branches' = @($common.ActiveBranches)
                    'Branch Creation Operations' = [ordered]@{$BranchId=$OperationId}
                    'Step Operation IDs' = [ordered]@{create=$OperationId}
                }
                New-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey `
                    -ForkId "fixture-$OperationId" -Payload $payload -OperationId "prepare-$OperationId" `
                    -Actor $Actor | Out-Null
                $ForkPoint = $effectiveForkPoint
            }
            else {
                $fixtureRecovery = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey `
                    -ForkId $fixtureForkId -ErrorAction SilentlyContinue
                if ($null -ne $fixtureRecovery) { $ForkPoint = [string]$fixtureRecovery.Payload['Fork Point'] }
            }
            $result = GitRefHandoffAdapter\New-GitHandoffBranch -Adapter $Adapter -TaskKey $TaskKey `
                -BranchId $BranchId -ForkPoint $ForkPoint -Fields $Fields -OperationId $OperationId -Actor $Actor
            $fixtureRecovery = Get-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey `
                -ForkId $fixtureForkId -ErrorAction SilentlyContinue
            if ($null -ne $fixtureRecovery -and $fixtureRecovery.Status -eq 'Pending' -and
                @($fixtureRecovery.Payload['Intended Branch IDs']).Count -eq 1) {
                Complete-GitHandoffForkRecovery -Adapter $Adapter -TaskKey $TaskKey `
                    -ForkId $fixtureForkId -ExpectedRevision $fixtureRecovery.Revision `
                    -OperationId "complete-$OperationId" | Out-Null
            }
            return $result
        }

        function Add-SelectiveRejectHook {
            param([string] $RemoteRoot)
            $hook = Join-Path $RemoteRoot 'hooks/pre-receive'
            $script = @'
#!/bin/sh
while read old new ref; do
  if [ -f "$GIT_DIR/deny-events" ]; then
    case "$ref" in refs/heads/handoff-v1/events/*) exit 1 ;; esac
  fi
  if [ -f "$GIT_DIR/deny-index" ]; then
    case "$ref" in refs/heads/handoff-v1/records/*/common) exit 1 ;; esac
  fi
  if [ -f "$GIT_DIR/deny-records" ]; then
    case "$ref" in refs/heads/handoff-v1/records/*) exit 1 ;; esac
  fi
  if [ -f "$GIT_DIR/deny-recovery-payload" ]; then
    case "$ref" in refs/heads/handoff-v1/recovery/*) exit 1 ;; esac
  fi
  if [ -f "$GIT_DIR/deny-recovery-control" ]; then
    case "$ref" in refs/heads/handoff-v1/recovery-controls/*) exit 1 ;; esac
  fi
  if [ -f "$GIT_DIR/deny-terminal-recovery-envelope" ]; then
    case "$ref" in refs/heads/handoff-v1/recovery-envelopes/*) exit 1 ;; esac
  fi
  if [ -f "$GIT_DIR/deny-terminal-recovery-index" ]; then
    case "$ref" in refs/heads/handoff-v1/recovery-index/*) exit 1 ;; esac
  fi
done
exit 0
'@
            Set-Content -LiteralPath $hook -Value $script -Encoding utf8
            if (-not $IsWindows) {
                $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
                [IO.File]::SetUnixFileMode($hook, $mode)
            }
        }

        $script:InitialCommon = [ordered]@{
            Intent = 'Review two parser options without selecting one'
            Scope = 'S1 Active: version 2; S0 Superseded: version 1'
            Current = 'Initial checkpoint; A and B may both explore'
            Source = 'synthetic fixture revision r2'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        $script:InitialBranch = [ordered]@{
            Current = 'Separate peer checkpoint'
            Source = 'synthetic fixture revision r2'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
    }

    AfterAll {
        if ($null -eq $script:PriorCommonCreationActorDefault) { $PSDefaultParameterValues.Remove('New-GitHandoffCommon:Actor') }
        else { $PSDefaultParameterValues['New-GitHandoffCommon:Actor'] = $script:PriorCommonCreationActorDefault }
        if ($null -eq $script:PriorBranchCreationActorDefault) { $PSDefaultParameterValues.Remove('New-GitHandoffBranch:Actor') }
        else { $PSDefaultParameterValues['New-GitHandoffBranch:Actor'] = $script:PriorBranchCreationActorDefault }
    }

    # Scenario: Two adopters use the same remote and Task Key under different scopes, while another caller is denied.
    # Purpose: Bind physical identity to Authority Scope and require trusted-principal policy checks before record access.
    It 'InterT05_authorizes_every_scoped_identity_without_cross_scope_lookup' {
        $root = Join-Path $TestDrive 'authorized-scopes'
        [void](New-Item -ItemType Directory -Path $root)
        $alpha = New-WriterFixture -Root $root -WriterId 'alpha' -AuthorityScope 'scope:alpha'
        $beta = New-WriterFixture -Root $root -WriterId 'beta' -AuthorityScope 'scope:beta'
        New-GitHandoffCommon -Adapter $alpha -TaskKey 'demo:same-key' -Fields $script:InitialCommon `
            -OperationId 'create-alpha' -Actor 'writer-alpha' | Out-Null
        $betaFields = [ordered]@{}
        foreach ($name in $script:InitialCommon.Keys) { $betaFields[$name] = $script:InitialCommon[$name] }
        $betaFields.Current = 'Independent beta scope'
        New-GitHandoffCommon -Adapter $beta -TaskKey 'demo:same-key' -Fields $betaFields `
            -OperationId 'create-beta' -Actor 'writer-beta' | Out-Null

        $alphaRead = Get-GitHandoffCommon -Adapter $alpha -TaskKey 'demo:same-key'
        $betaRead = Get-GitHandoffCommon -Adapter $beta -TaskKey 'demo:same-key'
        $alphaRead.AuthorityScope | Should -Be 'scope:alpha'
        $betaRead.AuthorityScope | Should -Be 'scope:beta'
        $alphaRead.Fields.Current | Should -Be $script:InitialCommon.Current
        $betaRead.Fields.Current | Should -Be 'Independent beta scope'
        $alphaRead.RecordId | Should -Not -Be $betaRead.RecordId

        $denied = New-GitHandoffAdapter -RepositoryRoot $alpha.RepositoryRoot -RemoteName origin `
            -AuthorityScope 'scope:alpha' -GetVerifiedPrincipal { 'denied-principal' } `
            -Authorize { param($request) $false }
        { Get-GitHandoffCommon -Adapter $denied -TaskKey 'demo:same-key' } | Should -Throw '*access was denied*'
        $unverified = New-GitHandoffAdapter -RepositoryRoot $alpha.RepositoryRoot -RemoteName origin `
            -AuthorityScope 'scope:alpha' -GetVerifiedPrincipal { $null } `
            -Authorize { param($request) $true }
        { Get-GitHandoffCommon -Adapter $unverified -TaskKey 'demo:same-key' } | Should -Throw '*authorization is unavailable*'

        # These tuples produced the same `scope + NUL + task` byte sequence in the earlier mapping.
        $scopeWithNul = 'a' + [char]0 + 'b'
        $taskWithNul = 'b' + [char]0 + 'c'
        $tupleOne = New-WriterFixture -Root $root -WriterId 'tuple-one' -AuthorityScope $scopeWithNul
        $tupleTwo = New-WriterFixture -Root $root -WriterId 'tuple-two' -AuthorityScope 'a'
        New-GitHandoffCommon -Adapter $tupleOne -TaskKey 'c' -Fields $script:InitialCommon `
            -OperationId 'create-nul-tuple-one' -Actor 'tuple-one-label' | Out-Null
        $tupleTwoFields = [ordered]@{}
        foreach ($name in $script:InitialCommon.Keys) { $tupleTwoFields[$name] = $script:InitialCommon[$name] }
        $tupleTwoFields.Current = 'Independent NUL-collision tuple'
        New-GitHandoffCommon -Adapter $tupleTwo -TaskKey $taskWithNul -Fields $tupleTwoFields `
            -OperationId 'create-nul-tuple-two' -Actor 'tuple-two-label' | Out-Null
        (Get-GitHandoffCommon -Adapter $tupleOne -TaskKey 'c').Fields.Current | Should -Be $script:InitialCommon.Current
        (Get-GitHandoffCommon -Adapter $tupleTwo -TaskKey $taskWithNul).Fields.Current | Should -Be 'Independent NUL-collision tuple'
    }

    # A real bare remote, two independent clones, and an explicit expected ref prove the uniqueness boundary.
    It 'InterT10_creates_one_exact_common_and_rejects_another_operation' {
        $root = Join-Path $TestDrive 'one-common'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $created = New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-1' -Fields $script:InitialCommon -OperationId 'create-common-1'
        $created.Revision | Should -Not -BeNullOrEmpty
        (Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-1').Fields.Intent | Should -Be $script:InitialCommon.Intent
        $retry = New-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-1' -Fields $script:InitialCommon -OperationId 'create-common-1'
        $retry.Revision | Should -Be $created.Revision
        { New-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-1' -Fields $script:InitialCommon -OperationId 'create-common-2' } | Should -Throw
    }

    # Scenario: An adopter supplies a display actor label that could name someone other than the authenticated caller.
    # Purpose: Preserve the label while binding immutable provenance to the trusted principal resolver.
    It 'InterT15_records_the_actor_label_and_the_verified_creation_principal' {
        $root = Join-Path $TestDrive 'creation-actor'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $actorParameterAttributes = @(
            (Get-Command New-GitHandoffCommon).Parameters.Actor.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        )
        $actorParameterAttributes.Mandatory | Should -Contain $true
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:actor' -Fields $script:InitialCommon `
            -OperationId 'create-with-actor' -Actor 'claimed-admin' | Out-Null
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:actor' -RecordKind common `
            -OperationId 'create-with-actor' -Field 'Current'
        $event.Actor | Should -Be 'claimed-admin'
        $event.VerifiedPrincipal | Should -Be 'synthetic-principal'
    }

    # Scenario: A caller supplies the structural Active Branches index while creating common.
    # Purpose: Reject an unsupported creation payload before a durable record can diverge from its canonical index.
    It 'InterT17_rejects_active_branches_before_record_creation' {
        $root = Join-Path $TestDrive 'creation-active-branches'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $fields = [ordered]@{}
        foreach ($name in $script:InitialCommon.Keys) { $fields[$name] = $script:InitialCommon[$name] }
        $fields['Active Branches'] = @('thread:A')
        { New-GitHandoffCommon -Adapter $a -TaskKey 'demo:active-branches' -Fields $fields `
            -OperationId 'create-with-index' -Actor 'writer-a' } | Should -Throw
        Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:active-branches' | Should -BeNullOrEmpty
    }

    # Scenario: Creation supplies the adapter-managed activity timestamp and an ordinary caller writes the structural index.
    # Purpose: Keep both system fields single-sourced by the adapter's verified operations.
    It 'InterT17a_rejects_system_managed_activity_creation_and_external_index_writes' {
        $root = Join-Path $TestDrive 'system-fields'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $fields = [ordered]@{}
        foreach ($name in $script:InitialCommon.Keys) { $fields[$name] = $script:InitialCommon[$name] }
        $fields['Last Activity At'] = '2026-09-16T00:00:00Z'
        { New-GitHandoffCommon -Adapter $a -TaskKey 'demo:managed-activity' -Fields $fields `
            -OperationId 'create-with-activity' -Actor 'writer-a' } | Should -Throw
        Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:managed-activity' | Should -BeNullOrEmpty

        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:external-index' -Fields $script:InitialCommon `
            -OperationId 'create-external-index-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:external-index'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:external-index' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{'Active Branches'=@('ghost')}) `
            -OperationId 'external-index-write' -Actor 'writer-a' } | Should -Throw
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:external-index').ActiveBranches).Count | Should -Be 0
    }

    # Scenario: Legal Task Key and Branch ID pairs contain colons but concatenate to the same text.
    # Purpose: Keep branch record and event identities collision-free for every legal identifier pair.
    It 'InterT18_encodes_task_and_branch_identity_without_delimiter_collisions' {
        $root = Join-Path $TestDrive 'idc'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'a:b' -Fields $script:InitialCommon `
            -OperationId 'create-common-ab' -Actor 'writer-a' | Out-Null
        New-GitHandoffCommon -Adapter $a -TaskKey 'a' -Fields $script:InitialCommon `
            -OperationId 'create-common-a' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'a:b' -BranchId 'c' -ForkPoint 'shared-r1' `
            -Fields $script:InitialBranch -OperationId 'create-colliding-branch' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'a' -BranchId 'b:c' -ForkPoint 'shared-r1' `
            -Fields $script:InitialBranch -OperationId 'create-colliding-branch' -Actor 'writer-a' | Out-Null
        $first = Get-GitHandoffBranch -Adapter $a -TaskKey 'a:b' -BranchId 'c'
        $second = Get-GitHandoffBranch -Adapter $a -TaskKey 'a' -BranchId 'b:c'
        $first.RecordId | Should -Not -Be $second.RecordId
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'a:b' -BranchId 'c' -RecordKind branch `
            -OperationId 'create-colliding-branch' -Field 'Current').RecordId | Should -Be $first.RecordId
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'a' -BranchId 'b:c' -RecordKind branch `
            -OperationId 'create-colliding-branch' -Field 'Current').RecordId | Should -Be $second.RecordId
    }

    It 'InterT19_rejects_unpaired_utf16_before_hashing_any_identity' {
        $root = Join-Path $TestDrive 'unicode'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $badTaskKey = 'demo:bad-' + [char]0xD800
        { New-GitHandoffCommon -Adapter $a -TaskKey $badTaskKey -Fields $script:InitialCommon `
            -OperationId 'reject-invalid-unicode' -Actor 'writer-a' } |
            Should -Throw '*well-formed Unicode*'
        @(& git -C $a.RepositoryRoot ls-remote origin 'refs/heads/handoff-v1/*').Count | Should -Be 0
    }

    # Two writers start from the same SHA. A's success must make B's stale write fail without changing A's fields.
    It 'InterT20_rejects_stale_common_revision_without_overwriting_peer' {
        $root = Join-Path $TestDrive 'stale-common'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-2' -Fields $script:InitialCommon -OperationId 'create-common-2' | Out-Null
        $beforeA = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-2'
        $beforeB = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-2'
        $changed = Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-2' -ExpectedRevision $beforeA.Revision -Changes ([ordered]@{Current='A verified version 2'}) -OperationId 'update-a'
        { Set-GitHandoffFields -Adapter $b -RecordKind common -TaskKey 'demo:ABC-2' -ExpectedRevision $beforeB.Revision -Changes ([ordered]@{Current='B competing assertion'}) -OperationId 'update-b' } | Should -Throw
        $observed = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-2'
        $observed.Revision | Should -Be $changed.Revision
        $observed.Fields.Current | Should -Be 'A verified version 2'
    }

    # A writer can die after pending is durable but before A exists; a new writer must recover A from that payload.
    It 'InterT28_recovers_A_from_durable_pending_after_pre_branch_failure' {
        $root = Join-Path $TestDrive 'pa'
        [void](New-Item -ItemType Directory -Path $root)
        $originalWriter = New-WriterFixture -Root $root -WriterId 'a'
        $commonFields = [ordered]@{
            Intent = 'Compare parser options; no option selected'
            Scope = 'Confirmed version 2 requirement'
            Current = 'A tested parser X with exact input q; result still unselected'
            Source = 'synthetic revision r2; A evidence q-1'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-GitHandoffCommon -Adapter $originalWriter -TaskKey 'demo:ABC-28' -Fields $commonFields -OperationId 'create-common-28' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $originalWriter -TaskKey 'demo:ABC-28'
        $recoveryPayload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current=$preFork.Fields.Current;Source=$preFork.Fields.Source;HostIdentity='thread:A'}
            'Shared Baseline' = [ordered]@{Current='Confirmed version 2 requirement; no parser selected';Source='synthetic revision r2; confirmed requirement'}
            'Verified Active Branches' = @($preFork.ActiveBranches)
            'Branch Creation Operations' = [ordered]@{'thread:A'='fork-a-28';'thread:B'='fork-b-28'}
            'Step Operation IDs' = [ordered]@{createA='fork-a-28';createB='fork-b-28';finish='fork-finish-28'}
        }
        New-GitHandoffForkRecovery -Adapter $originalWriter -TaskKey 'demo:ABC-28' -ForkId 'first-fork-28' `
            -Payload $recoveryPayload -OperationId 'fork-pending-28' -Actor 'writer-a' | Out-Null
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        Set-Content -LiteralPath (Join-Path $remoteRoot 'deny-records') -Value 'reject A branch' -Encoding ascii
        $attemptedA = [ordered]@{Current=$preFork.Fields.Current;Source=$preFork.Fields.Source;Lifecycle='Active';'Work State'='Running'}
        { New-TestGitHandoffBranch -Adapter $originalWriter -TaskKey 'demo:ABC-28' -BranchId 'thread:A' -ForkPoint $preFork.Revision `
            -Fields $attemptedA -OperationId 'fork-a-28' } | Should -Throw
        (Get-GitHandoffBranch -Adapter $originalWriter -TaskKey 'demo:ABC-28' -BranchId 'thread:A') | Should -BeNullOrEmpty
        (Get-GitHandoffCommon -Adapter $originalWriter -TaskKey 'demo:ABC-28').Fields.Current | Should -Be $commonFields.Current
        Remove-Item -LiteralPath (Join-Path $remoteRoot 'deny-records') -Force

        # No preFork/current/session values are passed to this new writer's construction path.
        $restartedWriter = New-WriterFixture -Root $root -WriterId 'r'
        $recovery = Get-GitHandoffForkRecovery -Adapter $restartedWriter -TaskKey 'demo:ABC-28' -ForkId 'first-fork-28'
        $persisted = $recovery.Payload
        $recovery.Status | Should -Be 'Pending'
        $persisted['Source Snapshot'].Current | Should -Be $commonFields.Current
        $persisted['Source Snapshot'].Source | Should -Be $commonFields.Source
        $persisted['Shared Baseline'].Current | Should -Not -Match 'parser X'
        $envelope = @(Get-GitHandoffPendingForkRecoveries -Adapter $restartedWriter -TaskKey 'demo:ABC-28')
        $envelope.Count | Should -Be 1
        $envelope[0].PSObject.Properties.Name | Should -Not -Contain 'Payload'
        $recoverA = [ordered]@{Current=$persisted['Source Snapshot'].Current;Source=$persisted['Source Snapshot'].Source;Lifecycle='Active';'Work State'='Running'}
        $recoverB = [ordered]@{Current=$persisted['Shared Baseline'].Current;Source=$persisted['Shared Baseline'].Source;Lifecycle='Active';'Work State'='Running'}
        New-TestGitHandoffBranch -Adapter $restartedWriter -TaskKey 'demo:ABC-28' -BranchId $persisted['Intended Branch IDs'][0] `
            -ForkPoint $persisted['Fork Point'] -Fields $recoverA -OperationId $persisted['Step Operation IDs'].createA | Out-Null
        New-TestGitHandoffBranch -Adapter $restartedWriter -TaskKey 'demo:ABC-28' -BranchId $persisted['Intended Branch IDs'][1] `
            -ForkPoint $persisted['Fork Point'] -Fields $recoverB -OperationId $persisted['Step Operation IDs'].createB | Out-Null
        $readA = Get-GitHandoffBranch -Adapter $restartedWriter -TaskKey 'demo:ABC-28' -BranchId 'thread:A'
        $readB = Get-GitHandoffBranch -Adapter $restartedWriter -TaskKey 'demo:ABC-28' -BranchId 'thread:B'
        $readA.Fields.Current | Should -Be $commonFields.Current
        $readA.Fields.Source | Should -Be $commonFields.Source
        $readB.Fields.Current | Should -Not -Match 'parser X'
        $readA.ForkPoint | Should -Be $readB.ForkPoint
        @((Get-GitHandoffCommon -Adapter $restartedWriter -TaskKey 'demo:ABC-28').ActiveBranches | Sort-Object) | Should -Be @('thread:A','thread:B')
        $indexedCommon = Get-GitHandoffCommon -Adapter $restartedWriter -TaskKey 'demo:ABC-28'
        Set-GitHandoffFields -Adapter $restartedWriter -RecordKind common -TaskKey 'demo:ABC-28' -ExpectedRevision $indexedCommon.Revision `
            -Changes ([ordered]@{Current="$($persisted['Shared Baseline'].Current); A/B active";Source=$persisted['Shared Baseline'].Source}) `
            -OperationId $persisted['Step Operation IDs'].finish | Out-Null
        $finalCommon = Get-GitHandoffCommon -Adapter $restartedWriter -TaskKey 'demo:ABC-28'
        $finalCommon.Fields.Current | Should -Be "$($persisted['Shared Baseline'].Current); A/B active"
        $finalCommon.Fields.Source | Should -Be $persisted['Shared Baseline'].Source
        $finalCommon.Fields.Source | Should -Not -Match 'A evidence'
        Complete-GitHandoffForkRecovery -Adapter $restartedWriter -TaskKey 'demo:ABC-28' -ForkId 'first-fork-28' `
            -ExpectedRevision $recovery.Revision -OperationId 'complete-fork-28' | Out-Null
        @(Get-GitHandoffPendingForkRecoveries -Adapter $restartedWriter -TaskKey 'demo:ABC-28').Count | Should -Be 0
    }

    # Scenario: The payload-free Pending envelope commits, then the isolated snapshot payload write fails.
    # Purpose: Normal pending-list authorization must still block unsafe resume without loading or requiring the payload ref.
    It 'InterT29_lists_a_pending_envelope_without_loading_a_failed_recovery_payload' {
        $root = Join-Path $TestDrive 'payload-free-envelope'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:envelope-only' -Fields $script:InitialCommon `
            -OperationId 'create-envelope-common' -Actor 'display-writer' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:envelope-only'
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-recovery-payload'
        Set-Content -LiteralPath $flag -Value 'reject isolated recovery payload' -Encoding ascii
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='private A candidate';Source='private A evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='fork-envelope-b'}
            'Step Operation IDs' = [ordered]@{createB='fork-envelope-b';indexB='fork-envelope-index'}
        }
        try {
            { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:envelope-only' -ForkId 'fork-envelope-only' `
                -Payload $payload -OperationId 'create-envelope-only' -Actor 'display-writer' } | Should -Throw
            $pending = @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:envelope-only')
            $pending.Count | Should -Be 1
            $pending[0].ForkId | Should -Be 'fork-envelope-only'
            $pending[0].PSObject.Properties.Name | Should -Not -Contain 'Payload'
            Get-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:envelope-only' `
                -ForkId 'fork-envelope-only' | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
        }
        $recovered = New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:envelope-only' `
            -ForkId 'fork-envelope-only' -Payload $payload -OperationId 'create-envelope-only' -Actor 'display-writer'
        $recovered.Status | Should -Be 'Pending'
        $recovered.EnvelopeStatus | Should -Be 'Pending'
        $recovered.PayloadRevision | Should -Be $recovered.Revision
        $recovered.Record.verifiedPrincipal | Should -Be 'synthetic-principal'
        $envelopeRefs = @(& git --git-dir=$remoteRoot for-each-ref --format='%(objectname)' 'refs/heads/handoff-v1/recovery-envelopes')
        $envelopeRefs.Count | Should -Be 1
        $envelopeJson = ((& git --git-dir=$remoteRoot show "$($envelopeRefs[0]):envelope.json") -join "`n") | ConvertFrom-Json
        $envelopeJson.payloadRevision | Should -Be $recovered.Revision
    }

    # Scenario: The remote rejects one member of the initial recovery bootstrap set.
    # Purpose: An atomic failure must not expose an envelope or index without its protected control record.
    It 'InterT29c_creates_envelope_control_and_pending_index_atomically' {
        $root = Join-Path $TestDrive 'atomic-recovery-bootstrap'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:atomic-bootstrap' -Fields $script:InitialCommon `
            -OperationId 'create-atomic-bootstrap-common' -Actor 'display-writer' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:atomic-bootstrap'
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-recovery-control'
        Set-Content -LiteralPath $flag -Value 'reject protected recovery control' -Encoding ascii
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='private A candidate';Source='private A evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='create-atomic-bootstrap-b'}
            'Step Operation IDs' = [ordered]@{createB='create-atomic-bootstrap-b';indexB='index-atomic-bootstrap-b'}
        }
        try {
            { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-bootstrap' `
                -ForkId 'fork-atomic-bootstrap' -Payload $payload `
                -OperationId 'prepare-atomic-bootstrap' -Actor 'display-writer' } | Should -Throw
            @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-bootstrap').Count | Should -Be 0
            $bootstrapRefs = @(& git --git-dir=$remoteRoot for-each-ref --format='%(refname)' `
                refs/heads/handoff-v1/recovery-envelopes `
                refs/heads/handoff-v1/recovery-controls `
                refs/heads/handoff-v1/recovery-index)
            $bootstrapRefs.Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
        }
        $recovered = New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-bootstrap' `
            -ForkId 'fork-atomic-bootstrap' -Payload $payload `
            -OperationId 'prepare-atomic-bootstrap' -Actor 'display-writer'
        $recovered.Status | Should -Be 'Pending'
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-bootstrap').Count | Should -Be 1
    }

    # Scenario: The remote rejects the index half of a terminal completion update.
    # Purpose: The payload may complete first, but envelope and index must remain Pending together until one retry commits both.
    It 'InterT29ca_completes_envelope_and_pending_index_atomically' {
        $root = Join-Path $TestDrive 'atc'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:atomic-completion' -Fields $script:InitialCommon `
            -OperationId 'create-atomic-completion-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:atomic-completion'
        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:B'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='confirmed state';Source='confirmed evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed state';Source='confirmed evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='create-atomic-completion-b'}
            'Step Operation IDs' = [ordered]@{createB='create-atomic-completion-b'}
        }
        $recovery = New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-completion' `
            -ForkId 'fork-atomic-completion' -Payload $payload `
            -OperationId 'prepare-atomic-completion' -Actor 'writer-a'
        $branchFields = [ordered]@{Current='confirmed state';Source='confirmed evidence';Lifecycle='Active';'Work State'='Running'}
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:atomic-completion' -BranchId 'thread:B' `
            -ForkPoint $common.Revision -Fields $branchFields -OperationId 'create-atomic-completion-b' | Out-Null
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-terminal-recovery-index'
        Set-Content -LiteralPath $flag -Value 'reject terminal index' -Encoding ascii
        try {
            { Complete-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-completion' `
                -ForkId 'fork-atomic-completion' -ExpectedRevision $recovery.Revision `
                -OperationId 'complete-atomic-completion' } | Should -Throw
        }
        finally { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
        $partial = Get-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-completion' `
            -ForkId 'fork-atomic-completion'
        $partial.Status | Should -Be 'Completed'
        $partial.EnvelopeStatus | Should -Be 'Pending'
        $partial.PayloadRevision | Should -Be $recovery.PayloadRevision
        $partial.Revision | Should -Not -Be $partial.PayloadRevision
        $partial.Record.payloadDigest | Should -Be $recovery.Record.payloadDigest
        ($partial.Payload | ConvertTo-Json -Compress -Depth 50) | Should -Be ($recovery.Payload | ConvertTo-Json -Compress -Depth 50)
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-completion').Count | Should -Be 1
        $completed = Complete-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-completion' `
            -ForkId 'fork-atomic-completion' -ExpectedRevision $recovery.Revision `
            -OperationId 'complete-atomic-completion'
        $completed.Status | Should -Be 'Completed'
        $completed.EnvelopeStatus | Should -Be 'Completed'
        $completed.PayloadRevision | Should -Be $recovery.PayloadRevision
        $completed.Record.payloadDigest | Should -Be $recovery.Record.payloadDigest
        ($completed.Payload | ConvertTo-Json -Compress -Depth 50) | Should -Be ($recovery.Payload | ConvertTo-Json -Compress -Depth 50)
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-completion').Count | Should -Be 0
    }

    # Scenario: A common-only envelope is durable without its payload, then the common record advances.
    # Purpose: Reject the stale pre-fork snapshot instead of attaching it to a newer common revision.
    It 'InterT29d_rejects_a_stale_common_only_payload_after_envelope_creation' {
        $root = Join-Path $TestDrive 'stale-envelope'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:stale-envelope' -Fields $script:InitialCommon `
            -OperationId 'create-stale-common' -Actor 'writer-a' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:stale-envelope'
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='private A candidate';Source='private A evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='create-stale-b'}
            'Step Operation IDs' = [ordered]@{createB='create-stale-b'}
        }
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-recovery-payload'
        Set-Content -LiteralPath $flag -Value 'reject isolated recovery payload' -Encoding ascii
        try {
            { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:stale-envelope' -ForkId 'stale-fork' `
                -Payload $payload -OperationId 'create-stale-envelope' -Actor 'writer-a' } | Should -Throw
        }
        finally { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
        $current = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:stale-envelope'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:stale-envelope' `
            -ExpectedRevision $current.Revision -Changes ([ordered]@{Current='newer confirmed common state'}) `
            -OperationId 'advance-stale-common' | Out-Null
        { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:stale-envelope' -ForkId 'stale-fork' `
            -Payload $payload -OperationId 'create-stale-envelope' -Actor 'writer-a' } |
            Should -Throw '*verified pre-fork common revision changed*'
        Get-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:stale-envelope' `
            -ForkId 'stale-fork' | Should -BeNullOrEmpty
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:stale-envelope').Count | Should -Be 1
    }

    # Scenario: Two absent targets have distinct creation operations, but a caller swaps them.
    # Purpose: Bind each branch identity to its own operation before any branch record is written.
    It 'InterT29e_rejects_cross_swapped_branch_creation_operations' {
        $root = Join-Path $TestDrive 'swapped-operations'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:swapped-operations' -Fields $script:InitialCommon `
            -OperationId 'create-swapped-common' -Actor 'writer-a' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:swapped-operations'
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current='private A candidate';Source='private A evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:A'='create-swapped-a';'thread:B'='create-swapped-b'}
            'Step Operation IDs' = [ordered]@{createA='create-swapped-a';createB='create-swapped-b'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:swapped-operations' -ForkId 'swapped-fork' `
            -Payload $payload -OperationId 'create-swapped-recovery' -Actor 'writer-a' | Out-Null
        { New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:swapped-operations' -BranchId 'thread:A' `
            -ForkPoint $preFork.Revision -Fields $script:InitialBranch -OperationId 'create-swapped-b' } |
            Should -Throw '*target-operation binding*'
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:swapped-operations' `
            -BranchId 'thread:A' | Should -BeNullOrEmpty
        $expectedA = [ordered]@{Current=$payload['Source Snapshot'].Current;Source=$payload['Source Snapshot'].Source;Lifecycle='Active';'Work State'='Running'}
        $created = New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:swapped-operations' -BranchId 'thread:A' `
            -ForkPoint $preFork.Revision -Fields $expectedA -OperationId 'create-swapped-a'
        $created.Indexed | Should -BeTrue
    }

    It 'InterT29f_requires_pending_attestation_and_rejects_stale_or_mismatched_branch_creation' {
        $root = Join-Path $TestDrive 'bound-branch-create'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:bound-create' -Fields $script:InitialCommon `
            -OperationId 'create-bound-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:bound-create'
        { GitRefHandoffAdapter\New-GitHandoffBranch -Adapter $a -TaskKey 'demo:bound-create' `
            -BranchId 'thread:A' -ForkPoint $common.Revision -Fields $script:InitialBranch `
            -OperationId 'create-without-pending' -Actor 'writer-a' } | Should -Throw '*Pending fork recovery*'

        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A')
            'Source Snapshot' = [ordered]@{Current=$script:InitialBranch.Current;Source=$script:InitialBranch.Source}
            'Shared Baseline' = [ordered]@{Current=$script:InitialBranch.Current;Source=$script:InitialBranch.Source}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:A'='create-bound-a'}
            'Step Operation IDs' = [ordered]@{create='create-bound-a'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:bound-create' -ForkId 'bound-fork' `
            -Payload $payload -OperationId 'prepare-bound-fork' -Actor 'writer-a' | Out-Null
        $wrongFields = [ordered]@{Current='unattested branch content';Source=$script:InitialBranch.Source;Lifecycle='Active';'Work State'='Running'}
        { GitRefHandoffAdapter\New-GitHandoffBranch -Adapter $a -TaskKey 'demo:bound-create' `
            -BranchId 'thread:A' -ForkPoint $common.Revision -Fields $wrongFields `
            -OperationId 'create-bound-a' -Actor 'writer-a' } | Should -Throw '*attested recovery payload*'
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:bound-create' -BranchId 'thread:A' | Should -BeNullOrEmpty

        $current = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:bound-create'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:bound-create' `
            -ExpectedRevision $current.Revision -Changes ([ordered]@{Current='semantic state advanced'}) `
            -OperationId 'advance-bound-common' -Actor 'writer-a' -Reason 'advance after recovery capture' | Out-Null
        { GitRefHandoffAdapter\New-GitHandoffBranch -Adapter $a -TaskKey 'demo:bound-create' `
            -BranchId 'thread:A' -ForkPoint $common.Revision -Fields $script:InitialBranch `
            -OperationId 'create-bound-a' -Actor 'writer-a' } | Should -Throw '*recovery fence changed*'
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:bound-create' -BranchId 'thread:A' | Should -BeNullOrEmpty
    }

    It 'InterT29g_filters_denied_pending_items_and_blocks_common_archival' {
        $root = Join-Path $TestDrive 'pending-authorization'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:pending-auth' -Fields $script:InitialCommon `
            -OperationId 'create-pending-auth-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:pending-auth'
        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A')
            'Source Snapshot' = [ordered]@{Current=$script:InitialBranch.Current;Source=$script:InitialBranch.Source}
            'Shared Baseline' = [ordered]@{Current=$script:InitialBranch.Current;Source=$script:InitialBranch.Source}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:A'='create-pending-auth-a'}
            'Step Operation IDs' = [ordered]@{create='create-pending-auth-a'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:pending-auth' -ForkId 'pending-auth-fork' `
            -Payload $payload -OperationId 'prepare-pending-auth' -Actor 'writer-a' | Out-Null
        $commonAfterRecovery = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:pending-auth'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:pending-auth' `
            -ExpectedRevision $commonAfterRecovery.Revision -Changes ([ordered]@{Lifecycle='Archived'}) `
            -OperationId 'archive-with-pending' -Actor 'writer-a' -Reason 'must remain protected' } |
            Should -Throw '*Pending fork recovery protects common*'

        $filtered = New-GitHandoffAdapter -RepositoryRoot $a.RepositoryRoot -RemoteName origin `
            -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'filtered-principal' } `
            -Authorize {
                param($request)
                if ($request.Action -eq 'fork-recovery:list-item') { return $false }
                if ($request.Action -in @('fork-recovery:list','common:update','common:read')) { return $true }
                throw "unexpected authorization action: $($request.Action)"
            }
        @(Get-GitHandoffPendingForkRecoveries -Adapter $filtered -TaskKey 'demo:pending-auth').Count | Should -Be 0
        { Set-GitHandoffFields -Adapter $filtered -RecordKind common -TaskKey 'demo:pending-auth' `
            -ExpectedRevision $commonAfterRecovery.Revision -Changes ([ordered]@{Lifecycle='Archived'}) `
            -OperationId 'archive-hidden-pending' -Actor 'filtered-principal' -Reason 'hidden pending must still protect common' } |
            Should -Throw '*Pending fork recovery protects common*'
    }

    It 'InterT29h_requires_live_source_binding_before_recovery_admission' {
        $root = Join-Path $TestDrive 'source-binding'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:source-binding' -Fields $script:InitialCommon `
            -OperationId 'create-source-binding-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:source-binding' -BranchId 'thread:A' `
            -ForkPoint 'ignored-by-fixture' -Fields $script:InitialBranch -OperationId 'create-source-binding-a' `
            -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:source-binding'
        $source = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:source-binding' -BranchId 'thread:A'
        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current=$source.Fields.Current;Source=$source.Fields.Source}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @($common.ActiveBranches)
            'Branch Creation Operations' = [ordered]@{'thread:B'='source-binding-b'}
            'Step Operation IDs' = [ordered]@{createB='source-binding-b'}
        }
        $recovery = New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:source-binding' `
            -ForkId 'source-binding-fork' -Payload $payload -OperationId 'prepare-source-binding' -Actor 'writer-a'
        $recovery.Control.sourceBranchId | Should -Be 'thread:A'
        $recovery.Control.sourceAclLocator | Should -Be 'thread:A'
        $recovery.Control.sourceBranchRevision | Should -Be $source.Revision
        [int64]$recovery.Control.sourceContinuationGeneration | Should -Be $source.ContinuationGeneration
        $recovery.Control.sourceBranchForkPoint | Should -Be $source.ForkPoint

        $stalePayload = [ordered]@{}
        foreach ($name in $payload.Keys) { $stalePayload[$name] = $payload[$name] }
        $currentCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:source-binding'
        $stalePayload['Fork Point'] = $currentCommon.Revision
        $stalePayload['Verified Active Branches'] = @($currentCommon.ActiveBranches)
        $stalePayload['Source Snapshot'] = [ordered]@{Current='fabricated source state';Source=$source.Fields.Source}
        { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:source-binding' `
            -ForkId 'source-binding-stale-fork' -Payload $stalePayload `
            -OperationId 'prepare-source-binding-stale' -Actor 'writer-a' } |
            Should -Throw '*Source Snapshot does not match*'
        Get-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:source-binding' `
            -ForkId 'source-binding-stale-fork' | Should -BeNullOrEmpty

        $fabricatedPayload = [ordered]@{}
        foreach ($name in $payload.Keys) { $fabricatedPayload[$name] = $payload[$name] }
        $fabricatedPayload['Fork Point'] = $currentCommon.Revision
        $fabricatedPayload['Verified Active Branches'] = @($currentCommon.ActiveBranches)
        $fabricatedPayload['Source Branch ID'] = 'thread:unrelated'
        { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:source-binding' `
            -ForkId 'source-binding-fabricated-fork' -Payload $fabricatedPayload `
            -OperationId 'prepare-source-binding-fabricated' -Actor 'writer-a' } |
            Should -Throw '*live common Active index*'
    }

    It 'InterT29i_requires_source_branch_authorization_before_recovery_payload_read' {
        $root = Join-Path $TestDrive 'source-read-authorization'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:source-read-auth' -Fields $script:InitialCommon `
            -OperationId 'create-source-read-auth-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:source-read-auth'
        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='private source state';Source='private source evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='source-read-auth-b'}
            'Step Operation IDs' = [ordered]@{createB='source-read-auth-b'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:source-read-auth' `
            -ForkId 'source-read-auth-fork' -Payload $payload -OperationId 'prepare-source-read-auth' -Actor 'writer-a' | Out-Null
        $denied = New-GitHandoffAdapter -RepositoryRoot $a.RepositoryRoot -RemoteName origin `
            -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'source-denied-principal' } -Authorize {
                param($request)
                if ($request.Action -eq 'branch:read') { return $false }
                return $true
            }
        { Get-GitHandoffForkRecovery -Adapter $denied -TaskKey 'demo:source-read-auth' `
            -ForkId 'source-read-auth-fork' } | Should -Throw '*access was denied*'
    }

    It 'InterT29j_blocks_exact_branch_mutation_while_fork_recovery_is_pending' {
        $root = Join-Path $TestDrive 'pending-branch-mutation'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $commonFields = [ordered]@{
            Intent = 'Compare options without selecting one'
            Scope = 'Confirmed version 2 requirement'
            Current = 'Confirmed baseline before branch exploration'
            Source = 'synthetic revision pending-branch-mutation'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:pending-branch-mutation' `
            -Fields $commonFields -OperationId 'create-common-pending-branch-mutation' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:pending-branch-mutation'
        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current=$common.Fields.Current;Source=$common.Fields.Source}
            'Shared Baseline' = [ordered]@{Current=$common.Fields.Current;Source=$common.Fields.Source}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:A'='create-pending-A';'thread:B'='create-pending-B'}
            'Step Operation IDs' = [ordered]@{createA='create-pending-A';createB='create-pending-B';finish='finish-pending-branch-mutation'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:pending-branch-mutation' -ForkId 'pending-branch-mutation-fork' `
            -Payload $payload -OperationId 'prepare-pending-branch-mutation' -Actor 'writer-a' | Out-Null
        $branchFields = [ordered]@{Current=$common.Fields.Current;Source=$common.Fields.Source;Lifecycle='Active';'Work State'='Running'}
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:pending-branch-mutation' -BranchId 'thread:A' `
            -ForkPoint $common.Revision -Fields $branchFields -OperationId 'create-pending-A' -Actor 'writer-a' | Out-Null
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:pending-branch-mutation' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:pending-branch-mutation' -BranchId 'thread:A' `
            -ExpectedRevision $branch.Revision -Changes ([ordered]@{Current='unsafe branch continuation'}) `
            -OperationId 'unsafe-pending-branch-update' } | Should -Throw '*Pending fork recovery blocks branch mutation*'
        { Start-GitHandoffBranchContinuation -Adapter $a -TaskKey 'demo:pending-branch-mutation' -BranchId 'thread:A' `
            -OperationId 'unsafe-pending-branch-continuation' } | Should -Throw '*Pending fork recovery blocks branch lifecycle mutation*'
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:pending-branch-mutation' -BranchId 'thread:A').Fields.Current |
            Should -Be $common.Fields.Current
    }

    It 'InterT85_isolates_existing_peer_snapshot_and_revalidates_common_before_new_branch_claim' {
        $root = Join-Path $TestDrive 'epf'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $b = New-WriterFixture -Root $root -WriterId 'b'
        $commonFields = [ordered]@{
            Intent = 'Compare options without selecting one'
            Scope = 'Confirmed shared requirement before the existing-peer fork'
            Current = 'Confirmed shared baseline before the existing-peer fork'
            Source = 'synthetic shared evidence before the existing-peer fork'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        $sourceFields = [ordered]@{
            Current = 'A private candidate before the existing-peer fork'
            Source = 'A private evidence before the existing-peer fork'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:existing-peer-fence' -Fields $commonFields `
            -OperationId 'existing-peer-create-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:existing-peer-fence' -BranchId 'thread:A' `
            -ForkPoint 'ignored-by-fixture' -Fields $sourceFields -OperationId 'existing-peer-create-A' -Actor 'writer-a' | Out-Null

        $commonBefore = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:existing-peer-fence'
        $sourceBefore = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:existing-peer-fence' -BranchId 'thread:A'
        $payload = [ordered]@{
            'Fork Point' = $commonBefore.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current=$sourceBefore.Fields.Current;Source=$sourceBefore.Fields.Source}
            'Shared Baseline' = [ordered]@{Current=$commonBefore.Fields.Current;Source=$commonBefore.Fields.Source}
            'Verified Active Branches' = @('thread:A')
            'Branch Creation Operations' = [ordered]@{'thread:B'='existing-peer-create-B'}
            'Step Operation IDs' = [ordered]@{createB='existing-peer-create-B';finish='existing-peer-finish'}
        }
        $recovery = New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:existing-peer-fence' `
            -ForkId 'existing-peer-fence-fork' -Payload $payload -OperationId 'existing-peer-prepare' -Actor 'writer-a'
        $persisted = (Get-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:existing-peer-fence' `
            -ForkId 'existing-peer-fence-fork').Payload
        $recovery.Status | Should -Be 'Pending'
        $persisted['Source Snapshot'].Current | Should -Be $sourceBefore.Fields.Current
        $persisted['Source Snapshot'].Source | Should -Be $sourceBefore.Fields.Source
        $persisted['Shared Baseline'].Current | Should -Be $commonBefore.Fields.Current
        $persisted['Shared Baseline'].Source | Should -Be $commonBefore.Fields.Source
        $recovery.Control.sourceBranchRevision | Should -Be $sourceBefore.Revision

        $commonAfterAdmission = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:existing-peer-fence'
        $commonAfterAdmission.Fields.Current | Should -Be $commonBefore.Fields.Current
        $commonAfterAdmission.Fields.Source | Should -Be $commonBefore.Fields.Source
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:existing-peer-fence' -RecordKind common `
            -OperationId 'existing-peer-prepare' -Field 'Current') | Should -BeNullOrEmpty
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:existing-peer-fence' -BranchId 'thread:A' `
            -ExpectedRevision $sourceBefore.Revision -Changes ([ordered]@{Current='A advanced while B was pending'}) `
            -OperationId 'existing-peer-unsafe-A-update' } | Should -Throw '*Pending fork recovery blocks branch mutation*'

        $commonPeer = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:existing-peer-fence'
        Set-GitHandoffFields -Adapter $b -RecordKind common -TaskKey 'demo:existing-peer-fence' `
            -ExpectedRevision $commonPeer.Revision -Changes ([ordered]@{
                Current='Superseding shared state before B creation'
                Source='new shared evidence before B creation'
            }) -OperationId 'existing-peer-advance-common' -Actor 'writer-b' `
            -Reason 'supersede the shared state before the pending peer is claimed' | Out-Null
        $sharedBaselineFields = [ordered]@{
            Current=$persisted['Shared Baseline'].Current
            Source=$persisted['Shared Baseline'].Source
            Lifecycle='Active'
            'Work State'='Running'
        }
        { GitRefHandoffAdapter\New-GitHandoffBranch -Adapter $a -TaskKey 'demo:existing-peer-fence' `
            -BranchId 'thread:B' -ForkPoint $persisted['Fork Point'] -Fields $sharedBaselineFields `
            -OperationId 'existing-peer-create-B' -Actor 'writer-a' } | Should -Throw '*verified common recovery fence changed*'
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:existing-peer-fence' -BranchId 'thread:B' | Should -BeNullOrEmpty
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:existing-peer-fence').Fields.Current |
            Should -Be 'Superseding shared state before B creation'
    }

    # Scenario: A recovery admission and common archival both read the same Active common revision.
    # Purpose: The admission must fence the common revision before either writer can commit its decision.
    It 'InterT2_serializes_recovery_admission_against_common_archival' {
        $root = Join-Path $TestDrive 't2-common-fence'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:t2-common-fence' -Fields $script:InitialCommon `
            -OperationId 't2-create-common' -Actor 'writer-a' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:t2-common-fence'
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='source A';Source='source evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared';Source='confirmed evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='t2-create-b'}
            'Step Operation IDs' = [ordered]@{createB='t2-create-b'}
        }
        $bin = Join-Path $root 'git-barrier-bin'
        [void](New-Item -ItemType Directory -Path $bin)
        $gitWrapper = Join-Path $bin 'git.cmd'
        $gitWrapperText = @'
@echo off
setlocal EnableDelayedExpansion
if /I "%SYP_TEST_BARRIER_ROLE%"=="archive" (
  set "HANDOFF_IS_PUSH=0"
  for %%A in (%*) do if /I "%%~A"=="push" set "HANDOFF_IS_PUSH=1"
  if "!HANDOFF_IS_PUSH!"=="1" (
    >"%SYP_TEST_BARRIER_ENTERED%" echo archive push invoked
    :wait_for_release
    if exist "%SYP_TEST_BARRIER_BLOCK%" (
      %SystemRoot%\System32\ping.exe -n 2 -w 100 127.0.0.1 >nul
      goto wait_for_release
    )
  )
)
"%SYP_TEST_REAL_GIT%" %*
exit /b %ERRORLEVEL%
'@
        Set-Content -LiteralPath $gitWrapper -Value $gitWrapperText -Encoding ascii
        $blockArchivePush = Join-Path $remote 'block-archive-push'
        $archivePushEntered = Join-Path $remote 'archive-push-entered'
        Set-Content -LiteralPath $blockArchivePush -Value 'hold archive push' -Encoding ascii
        $modulePath = Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
        $realGit = (Get-Command git.exe -ErrorAction Stop).Source
        $recoveryJob = $null
        $archiveJob = $null
        try {
            $archiveJob = Start-Job -ScriptBlock {
                param($ModulePath,$RepositoryRoot,$GitWrapperDir,$GitWrapperEntered,$GitWrapperBlock,$RealGit)
                $env:Path = "$GitWrapperDir;$env:Path"
                $env:SYP_TEST_BARRIER_ROLE = 'archive'
                $env:SYP_TEST_BARRIER_ENTERED = $GitWrapperEntered
                $env:SYP_TEST_BARRIER_BLOCK = $GitWrapperBlock
                $env:SYP_TEST_REAL_GIT = $RealGit
                Import-Module $ModulePath -Force
                $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                    -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                    -Authorize { param($request) $true }
                try {
                    $common = Get-GitHandoffCommon -Adapter $adapter -TaskKey 'demo:t2-common-fence'
                    Set-GitHandoffFields -Adapter $adapter -RecordKind common -TaskKey 'demo:t2-common-fence' `
                        -ExpectedRevision $common.Revision -Changes ([ordered]@{Lifecycle='Archived'}) `
                        -OperationId 't2-archive-common' -Actor 'writer-b' -Reason 'archive after exact inactivity check' | Out-Null
                    [pscustomobject]@{status='succeeded'}
                }
                catch { [pscustomobject]@{status='failed';error=$_.Exception.Message} }
            } -ArgumentList $modulePath,$b.RepositoryRoot,$bin,$archivePushEntered,$blockArchivePush,$realGit
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $archivePushEntered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            Test-Path -LiteralPath $archivePushEntered | Should -BeTrue

            $recoveryJob = Start-Job -ScriptBlock {
                param($ModulePath,$RepositoryRoot,$Payload)
                Import-Module $ModulePath -Force
                $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                    -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                    -Authorize { param($request) $true }
                try {
                    $result = New-GitHandoffForkRecovery -Adapter $adapter -TaskKey 'demo:t2-common-fence' `
                        -ForkId 't2-fork' -Payload $Payload -OperationId 't2-prepare-fork' -Actor 'writer-a'
                    [pscustomobject]@{status='succeeded';result=$result}
                }
                catch { [pscustomobject]@{status='failed';error=$_.Exception.Message} }
            } -ArgumentList $modulePath,$a.RepositoryRoot,$payload
            $recoveryResult = Receive-Job -Job $recoveryJob -Wait -AutoRemoveJob -ErrorAction Stop
            $recoveryJob = $null
            if ($recoveryResult.status -ne 'succeeded') { throw "T2 recovery writer failed before the race was established: $($recoveryResult.error)" }
            Remove-Item -LiteralPath $blockArchivePush -Force

            $archiveResult = Receive-Job -Job $archiveJob -Wait -AutoRemoveJob -ErrorAction Stop
            $archiveJob = $null
            $archiveResult.status | Should -Be 'failed'
            $archiveResult.error | Should -Match 'Conditional Handoff revision conflict|Pending fork recovery protects common'
            $commonAfterRace = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:t2-common-fence'
            $commonAfterRace.Revision | Should -Not -Be $preFork.Revision
            $commonAfterRace.Fields.Lifecycle | Should -Be 'Active'
            @(Get-GitHandoffPendingForkRecoveries -Adapter $b -TaskKey 'demo:t2-common-fence').Count | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $blockArchivePush -Force -ErrorAction SilentlyContinue
            if ($null -ne $recoveryJob) { Stop-Job -Job $recoveryJob -ErrorAction SilentlyContinue; Remove-Job -Job $recoveryJob -Force -ErrorAction SilentlyContinue }
            if ($null -ne $archiveJob) { Stop-Job -Job $archiveJob -ErrorAction SilentlyContinue; Remove-Job -Job $archiveJob -Force -ErrorAction SilentlyContinue }
        }
    }

    # Scenario: A payload writer and an authorized abandonment both observe an empty payload.
    # Purpose: Payload creation and terminal abandonment must compete on one envelope revision.
    It 'InterT6_serializes_payload_creation_against_abandonment' {
        $root = Join-Path $TestDrive 't6-payload-abandon'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:t6-payload-abandon' -Fields $script:InitialCommon `
            -OperationId 't6-create-common' -Actor 'writer-a' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:t6-payload-abandon'
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='source A';Source='source evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed shared';Source='confirmed evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='t6-create-b'}
            'Step Operation IDs' = [ordered]@{createB='t6-create-b'}
        }
        $hook = Join-Path $remote 'hooks/pre-receive'
        $hookText = @'
#!/bin/sh
while read old new ref; do
  case "$ref" in
    refs/heads/handoff-v1/recovery/*)
      if [ -f "$GIT_DIR/block-payload" ]; then
        : > "$GIT_DIR/payload-entered"
        while [ -f "$GIT_DIR/block-payload" ]; do sleep 0.02; done
      fi
      ;;
    refs/heads/handoff-v1/recovery-envelopes/*|refs/heads/handoff-v1/recovery-index/*)
      if [ -f "$GIT_DIR/block-abandon-terminal" ]; then
        : > "$GIT_DIR/abandon-terminal-entered"
        while [ -f "$GIT_DIR/block-abandon-terminal" ]; do sleep 0.02; done
      fi
      ;;
  esac
done
exit 0
'@
        Set-Content -LiteralPath $hook -Value $hookText -Encoding utf8
        if (-not $IsWindows) {
            $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
            [IO.File]::SetUnixFileMode($hook, $mode)
        }
        $blockPayload = Join-Path $remote 'block-payload'
        $payloadEntered = Join-Path $remote 'payload-entered'
        $blockAbandon = Join-Path $remote 'block-abandon-terminal'
        $abandonEntered = Join-Path $remote 'abandon-terminal-entered'
        Set-Content -LiteralPath $blockPayload -Value 'hold payload creation' -Encoding ascii
        $modulePath = Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
        $recoveryJob = $null
        $abandonJob = $null
        try {
            $recoveryJob = Start-Job -ScriptBlock {
                param($ModulePath,$RepositoryRoot,$Payload)
                Import-Module $ModulePath -Force
                $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                    -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                    -Authorize { param($request) $true }
                try {
                    $result = New-GitHandoffForkRecovery -Adapter $adapter -TaskKey 'demo:t6-payload-abandon' `
                        -ForkId 't6-fork' -Payload $Payload -OperationId 't6-prepare-fork' -Actor 'writer-a'
                    [pscustomobject]@{status='succeeded';result=$result}
                }
                catch { [pscustomobject]@{status='failed';error=$_.Exception.Message} }
            } -ArgumentList $modulePath,$a.RepositoryRoot,$payload
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $payloadEntered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            Test-Path -LiteralPath $payloadEntered | Should -BeTrue
            $pending = @(Get-GitHandoffPendingForkRecoveries -Adapter $b -TaskKey 'demo:t6-payload-abandon')
            $pending.Count | Should -Be 1
            Set-Content -LiteralPath $blockAbandon -Value 'hold terminal abandonment' -Encoding ascii

            $abandonJob = Start-Job -ScriptBlock {
                param($ModulePath,$RepositoryRoot,$ExpectedEnvelopeRevision)
                Import-Module $ModulePath -Force
                $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                    -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                    -Authorize { param($request) $true }
                try {
                    $result = Abandon-GitHandoffForkRecovery -Adapter $adapter -TaskKey 'demo:t6-payload-abandon' `
                        -ForkId 't6-fork' -ExpectedEnvelopeRevision $ExpectedEnvelopeRevision `
                        -OperationId 't6-abandon-fork' -Reason 'payload creation did not become durable'
                    [pscustomobject]@{status='succeeded';result=$result}
                }
                catch { [pscustomobject]@{status='failed';error=$_.Exception.Message} }
            } -ArgumentList $modulePath,$b.RepositoryRoot,$pending[0].Revision
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $abandonEntered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            Test-Path -LiteralPath $abandonEntered | Should -BeTrue
            Remove-Item -LiteralPath $blockAbandon -Force
            $abandonResult = Receive-Job -Job $abandonJob -Wait -AutoRemoveJob -ErrorAction Stop
            $abandonJob = $null
            Remove-Item -LiteralPath $blockPayload -Force
            $recoveryResult = Receive-Job -Job $recoveryJob -Wait -AutoRemoveJob -ErrorAction Stop
            $recoveryJob = $null

            $abandonResult.status | Should -Be 'succeeded'
            $recoveryResult.status | Should -Be 'failed'
            $payloadRefs = @(& git -C $a.RepositoryRoot ls-remote origin 'refs/heads/handoff-v1/recovery/*')
            $payloadRefs.Count | Should -Be 0
            @(Get-GitHandoffPendingForkRecoveries -Adapter $b -TaskKey 'demo:t6-payload-abandon').Count | Should -Be 0
            $envelopeRefLines = @(& git --git-dir=$remote for-each-ref --format='%(objectname)' 'refs/heads/handoff-v1/recovery-envelopes')
            $indexRefLines = @(& git --git-dir=$remote for-each-ref --format='%(objectname)' 'refs/heads/handoff-v1/recovery-index')
            $envelopeRefLines.Count | Should -Be 1
            $indexRefLines.Count | Should -Be 1
            $envelopeJson = ((& git --git-dir=$remote show "$($envelopeRefLines[0]):envelope.json") -join "`n") | ConvertFrom-Json
            $indexJson = ((& git --git-dir=$remote show "$($indexRefLines[0]):index.json") -join "`n") | ConvertFrom-Json
            $envelopeJson.status | Should -Be 'Abandoned'
            $indexJson.status | Should -Be 'Abandoned'
            $envelopeJson.payloadRevision | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $blockPayload,$blockAbandon -Force -ErrorAction SilentlyContinue
            if ($null -ne $recoveryJob) { Stop-Job -Job $recoveryJob -ErrorAction SilentlyContinue; Remove-Job -Job $recoveryJob -Force -ErrorAction SilentlyContinue }
            if ($null -ne $abandonJob) { Stop-Job -Job $abandonJob -ErrorAction SilentlyContinue; Remove-Job -Job $abandonJob -Force -ErrorAction SilentlyContinue }
        }
    }

    # Scenario: The payload never commits for an existing-A fork and none of the missing branch work starts.
    # Purpose: Release singleton blocking through a reviewed terminal envelope without treating the existing source as new work.
    It 'InterT29a_abandons_only_an_empty_envelope_and_never_reuses_its_fork_id' {
        $root = Join-Path $TestDrive 'ae'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:abandon-empty' -Fields $script:InitialCommon `
            -OperationId 'create-abandon-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:abandon-empty' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'create-existing-a' -Actor 'writer-a' | Out-Null
        $existingCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:abandon-empty'
        $existingSource = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:abandon-empty' -BranchId 'thread:A'
        $payload = [ordered]@{
            'Fork Point' = $existingCommon.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current=$existingSource.Fields.Current;Source=$existingSource.Fields.Source}
            'Shared Baseline' = [ordered]@{Current='confirmed shared state';Source='confirmed shared evidence'}
            'Verified Active Branches' = @($existingCommon.ActiveBranches)
            'Branch Creation Operations' = [ordered]@{'thread:B'='create-missing-b'}
            'Step Operation IDs' = [ordered]@{createB='create-missing-b';indexB='index-missing-b'}
        }
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-recovery-payload'
        Set-Content -LiteralPath $flag -Value 'reject isolated recovery payload' -Encoding ascii
        try {
            { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:abandon-empty' -ForkId 'fork-empty' `
                -Payload $payload -OperationId 'create-empty-envelope' -Actor 'writer-a' } | Should -Throw
        }
        finally { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
        $pending = @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:abandon-empty')
        $pending.Count | Should -Be 1
        $abandoned = Abandon-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:abandon-empty' `
            -ForkId 'fork-empty' -ExpectedEnvelopeRevision $pending[0].Revision `
            -OperationId 'abandon-empty-envelope' -Reason 'payload creation failed before missing branch work began'
        $abandoned.Status | Should -Be 'Abandoned'
        $abandoned.Record.abandonmentVerifiedPrincipal | Should -Be 'synthetic-principal'
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:abandon-empty').Count | Should -Be 0
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:abandon-empty' -BranchId 'thread:A').Fields.Current | Should -Be $script:InitialBranch.Current
        { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:abandon-empty' -ForkId 'fork-empty' `
            -Payload $payload -OperationId 'create-empty-envelope' -Actor 'writer-a' } | Should -Throw '*cannot be reused*'
        (Abandon-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:abandon-empty' `
            -ForkId 'fork-empty' -ExpectedEnvelopeRevision $pending[0].Revision `
            -OperationId 'abandon-empty-envelope' -Reason 'idempotent retry').Status | Should -Be 'Abandoned'
    }

    # Scenario: The remote rejects the envelope half of terminal abandonment.
    # Purpose: Atomic push must leave both envelope and index Pending so the same operation can retry safely.
    It 'InterT29aa_abandons_envelope_and_pending_index_atomically' {
        $root = Join-Path $TestDrive 'ata'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:atomic-abandonment' -Fields $script:InitialCommon `
            -OperationId 'create-atomic-abandonment-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:atomic-abandonment'
        $payload = [ordered]@{
            'Fork Point' = $common.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='private candidate';Source='private evidence'}
            'Shared Baseline' = [ordered]@{Current='confirmed state';Source='confirmed evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='create-atomic-abandonment-b'}
            'Step Operation IDs' = [ordered]@{createB='create-atomic-abandonment-b'}
        }
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $payloadFlag = Join-Path $remoteRoot 'deny-recovery-payload'
        Set-Content -LiteralPath $payloadFlag -Value 'reject isolated payload' -Encoding ascii
        try {
            { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-abandonment' `
                -ForkId 'fork-atomic-abandonment' -Payload $payload `
                -OperationId 'prepare-atomic-abandonment' -Actor 'writer-a' } | Should -Throw
        }
        finally { Remove-Item -LiteralPath $payloadFlag -Force -ErrorAction SilentlyContinue }
        $pending = @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-abandonment')
        $pending.Count | Should -Be 1
        $terminalFlag = Join-Path $remoteRoot 'deny-terminal-recovery-envelope'
        Set-Content -LiteralPath $terminalFlag -Value 'reject terminal envelope' -Encoding ascii
        try {
            { Abandon-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-abandonment' `
                -ForkId 'fork-atomic-abandonment' -ExpectedEnvelopeRevision $pending[0].Revision `
                -OperationId 'abandon-atomic-abandonment' -Reason 'payload creation failed' } | Should -Throw
        }
        finally { Remove-Item -LiteralPath $terminalFlag -Force -ErrorAction SilentlyContinue }
        $stillPending = @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-abandonment')
        $stillPending.Count | Should -Be 1
        $stillPending[0].Revision | Should -Be $pending[0].Revision
        $abandoned = Abandon-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:atomic-abandonment' `
            -ForkId 'fork-atomic-abandonment' -ExpectedEnvelopeRevision $pending[0].Revision `
            -OperationId 'abandon-atomic-abandonment' -Reason 'payload creation failed'
        $abandoned.Status | Should -Be 'Abandoned'
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:atomic-abandonment').Count | Should -Be 0
    }

    # Scenario: A recovery payload or a durable branch-creation claim exists when abandonment is attempted.
    # Purpose: Keep any durable fork step Pending for exact reconciliation instead of hiding partial work.
    It 'InterT29b_rejects_abandonment_after_payload_or_branch_creation_claim' {
        $root = Join-Path $TestDrive 'ua'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:payload-exists' -Fields $script:InitialCommon `
            -OperationId 'create-payload-common' -Actor 'writer-a' | Out-Null
        $payloadCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:payload-exists'
        $payload = [ordered]@{
            'Fork Point' = $payloadCommon.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='source state';Source='source evidence'}
            'Shared Baseline' = [ordered]@{Current='shared state';Source='shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='create-payload-b'}
            'Step Operation IDs' = [ordered]@{createB='create-payload-b'}
        }
        $recovery = New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:payload-exists' -ForkId 'payload-present' `
            -Payload $payload -OperationId 'create-payload-recovery' -Actor 'writer-a'
        { Abandon-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:payload-exists' -ForkId 'payload-present' `
            -ExpectedEnvelopeRevision $recovery.EnvelopeRevision -OperationId 'unsafe-payload-abandon' `
            -Reason 'must remain pending' } | Should -Throw '*isolated payload exists*'
        (Get-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:payload-exists' -ForkId 'payload-present').Status | Should -Be 'Pending'

        $claimRoot = Join-Path $TestDrive 'uc'
        [void](New-Item -ItemType Directory -Path $claimRoot)
        $claimWriter = New-WriterFixture -Root $claimRoot -WriterId 'a'
        New-GitHandoffCommon -Adapter $claimWriter -TaskKey 'demo:claim-exists' -Fields $script:InitialCommon `
            -OperationId 'create-claim-common' -Actor 'writer-a' | Out-Null
        $claimCommon = Get-GitHandoffCommon -Adapter $claimWriter -TaskKey 'demo:claim-exists'
        $claimPayload = [ordered]@{}
        foreach ($name in $payload.Keys) { $claimPayload[$name] = $payload[$name] }
        $claimPayload['Fork Point'] = $claimCommon.Revision
        New-GitHandoffForkRecovery -Adapter $claimWriter -TaskKey 'demo:claim-exists' -ForkId 'claim-present' `
            -Payload $claimPayload -OperationId 'create-claim-recovery' -Actor 'writer-a' | Out-Null
        $remoteRoot = Join-Path $claimRoot 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-records'
        Set-Content -LiteralPath $flag -Value 'reject branch after envelope claim' -Encoding ascii
        $branchFailure = $null
        try {
            try { New-TestGitHandoffBranch -Adapter $claimWriter -TaskKey 'demo:claim-exists' -BranchId 'thread:B' `
                -ForkPoint $claimCommon.Revision -Fields ([ordered]@{Current='shared state';Source='shared evidence';Lifecycle='Active';'Work State'='Running'}) `
                -OperationId 'create-payload-b' `
                -Actor 'writer-a' | Out-Null }
            catch { $branchFailure = [string]$_.Exception.Message }
        }
        finally { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
        $branchFailure | Should -Match 'bound fork branch write was not verified'
        (Get-GitHandoffBranch -Adapter $claimWriter -TaskKey 'demo:claim-exists' -BranchId 'thread:B') | Should -BeNullOrEmpty
        $payloadRefs = @(& git -C $claimWriter.RepositoryRoot ls-remote origin 'refs/heads/handoff-v1/recovery/*')
        $payloadRefs.Count | Should -Be 1
        $payloadRef = (([string]$payloadRefs[0]) -split "`t",2)[1]
        & git -C $claimWriter.RepositoryRoot push --quiet origin ":$payloadRef"
        $LASTEXITCODE | Should -Be 0
        $claimPending = @(Get-GitHandoffPendingForkRecoveries -Adapter $claimWriter -TaskKey 'demo:claim-exists')
        { Abandon-GitHandoffForkRecovery -Adapter $claimWriter -TaskKey 'demo:claim-exists' -ForkId 'claim-present' `
            -ExpectedEnvelopeRevision $claimPending[0].Revision -OperationId 'unsafe-claim-abandon' `
            -Reason 'must remain pending' } | Should -Throw '*branch creation has already been claimed*'
        @(Get-GitHandoffPendingForkRecoveries -Adapter $claimWriter -TaskKey 'demo:claim-exists').Count | Should -Be 1
    }

    # Scenario: An untrusted principal tries to abandon a visible envelope.
    # Purpose: Deny before any recovery or task record content is read.
    It 'InterT29c_authorizes_abandonment_before_loading_recovery_state' {
        $root = Join-Path $TestDrive 'da'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:deny-abandon' -Fields $script:InitialCommon `
            -OperationId 'create-denied-common' -Actor 'writer-a' | Out-Null
        $preFork = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:deny-abandon'
        $payload = [ordered]@{
            'Fork Point' = $preFork.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:B')
            'Source Snapshot' = [ordered]@{Current='source state';Source='source evidence'}
            'Shared Baseline' = [ordered]@{Current='shared state';Source='shared evidence'}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:B'='denied-create-b'}
            'Step Operation IDs' = [ordered]@{createB='denied-create-b'}
        }
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        $flag = Join-Path $remoteRoot 'deny-recovery-payload'
        Set-Content -LiteralPath $flag -Value 'reject isolated recovery payload' -Encoding ascii
        try {
            { New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:deny-abandon' -ForkId 'deny-abandon' `
                -Payload $payload -OperationId 'create-denied-envelope' -Actor 'writer-a' } | Should -Throw
        }
        finally { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
        $pending = @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:deny-abandon')
        $denied = New-GitHandoffAdapter -RepositoryRoot $a.RepositoryRoot -RemoteName origin `
            -AuthorityScope $a.AuthorityScope -GetVerifiedPrincipal { 'denied-principal' } `
            -Authorize { param($request) $false }
        { Abandon-GitHandoffForkRecovery -Adapter $denied -TaskKey 'demo:deny-abandon' -ForkId 'deny-abandon' `
            -ExpectedEnvelopeRevision $pending[0].Revision -OperationId 'denied-abandon-operation' `
            -Reason 'caller is unauthorized' } | Should -Throw '*access was denied*'
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:deny-abandon').Count | Should -Be 1
    }

    # A common-only conversation first materializes its own A branch, then B from the confirmed fork baseline.
    It 'InterT30_keeps_forked_peer_branches_and_common_index_distinct' {
        $root = Join-Path $TestDrive 'pb'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $b = New-WriterFixture -Root $root -WriterId 'b'
        $commonOnlyA = [ordered]@{
            Intent = 'Compare parser options; no option selected'
            Scope = 'S1 Active: confirmed version 2 requirement'
            Current = 'Confirmed version 2 requirement; A candidate parser X tested but not selected'
            Source = 'synthetic revision r2; A candidate evidence x-1'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3' -Fields $commonOnlyA -OperationId 'create-common-3' | Out-Null
        $forkSnapshot = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3'
        $recoveryPayload = [ordered]@{
            'Fork Point' = $forkSnapshot.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current=$forkSnapshot.Fields.Current;Source=$forkSnapshot.Fields.Source;HostIdentity='thread:A'}
            'Shared Baseline' = [ordered]@{Current='Confirmed version 2 requirement; no parser selected';Source='synthetic revision r2; confirmed requirement'}
            'Verified Active Branches' = @($forkSnapshot.ActiveBranches)
            'Branch Creation Operations' = [ordered]@{'thread:A'='fork-a';'thread:B'='fork-b'}
            'Step Operation IDs' = [ordered]@{createA='fork-a';createB='fork-b';finish='fork-finish-3'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:ABC-3' -ForkId 'first-fork-3' `
            -Payload $recoveryPayload -OperationId 'fork-pending-3' -Actor 'writer-a' | Out-Null
        (Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-3').Fields.Current | Should -Be $commonOnlyA.Current
        $recovery = Get-GitHandoffForkRecovery -Adapter $b -TaskKey 'demo:ABC-3' -ForkId 'first-fork-3'
        $persisted = $recovery.Payload
        $recovery.Status | Should -Be 'Pending'
        $persisted['Source Snapshot'].Current | Should -Be $forkSnapshot.Fields.Current
        $persisted['Source Snapshot'].Source | Should -Be $forkSnapshot.Fields.Source
        $persisted['Intended Branch IDs'] | Should -Be @('thread:A','thread:B')
        $sourceA = [ordered]@{
            Current = $persisted['Source Snapshot'].Current
            Source = $persisted['Source Snapshot'].Source
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        $newB = [ordered]@{
            Current = $persisted['Shared Baseline'].Current
            Source = $persisted['Shared Baseline'].Source
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-TestGitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-3' -BranchId $persisted['Intended Branch IDs'][0] -ForkPoint $persisted['Fork Point'] -Fields $sourceA -OperationId $persisted['Step Operation IDs'].createA | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-3' -BranchId $persisted['Intended Branch IDs'][1] -ForkPoint $persisted['Fork Point'] -Fields $newB -OperationId $persisted['Step Operation IDs'].createB | Out-Null
        $readA = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-3' -BranchId 'thread:A'
        $readB = Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-3' -BranchId 'thread:B'
        $readA.ForkPoint | Should -Be $forkSnapshot.Revision
        $readB.ForkPoint | Should -Be $forkSnapshot.Revision
        $readA.Fields.Current | Should -Be $forkSnapshot.Fields.Current
        $readA.Fields.Source | Should -Be $forkSnapshot.Fields.Source
        $readB.Fields.Current | Should -Not -Match 'parser X tested'
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3').ActiveBranches | Sort-Object) | Should -Be @('thread:A','thread:B')
        $indexedCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-3' -ExpectedRevision $indexedCommon.Revision `
            -Changes ([ordered]@{Current="$($persisted['Shared Baseline'].Current); A/B active";Source=$persisted['Shared Baseline'].Source}) `
            -OperationId $persisted['Step Operation IDs'].finish | Out-Null
        $finalCommon = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-3'
        $finalCommon.Fields.Current | Should -Be "$($persisted['Shared Baseline'].Current); A/B active"
        $finalCommon.Fields.Source | Should -Be $persisted['Shared Baseline'].Source
        $finalCommon.Fields.Source | Should -Not -Match 'A candidate evidence'
        Complete-GitHandoffForkRecovery -Adapter $b -TaskKey 'demo:ABC-3' -ForkId 'first-fork-3' `
            -ExpectedRevision $recovery.Revision -OperationId 'complete-fork-3' | Out-Null
        Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-3' -BranchId 'thread:A' -ExpectedRevision $readA.Revision -Changes ([ordered]@{Current='A tested version 1'}) -OperationId 'branch-a-update' | Out-Null
        Set-GitHandoffFields -Adapter $b -RecordKind branch -TaskKey 'demo:ABC-3' -BranchId 'thread:B' -ExpectedRevision $readB.Revision -Changes ([ordered]@{Current='B tested version 2'}) -OperationId 'branch-b-update' | Out-Null
        (Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-3' -BranchId 'thread:A').Fields.Current | Should -Be 'A tested version 1'
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-3' -BranchId 'thread:B').Fields.Current | Should -Be 'B tested version 2'
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3').ActiveBranches | Sort-Object) | Should -Be @('thread:A','thread:B')
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3').Fields.Current | Should -Be "$($persisted['Shared Baseline'].Current); A/B active"
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3').Fields.Source | Should -Be $persisted['Shared Baseline'].Source
    }

    # A failed second index write leaves B exact-readable and fork recovery Pending until the same operation is reconciled.
    It 'InterT35_recovers_a_partial_first_fork_without_losing_A_or_promoting_B' {
        $root = Join-Path $TestDrive 'pf'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $b = New-WriterFixture -Root $root -WriterId 'b'
        $commonFields = [ordered]@{
            Intent = 'Compare options without selecting one'
            Scope = 'Confirmed version 2 requirement'
            Current = 'A candidate evidence retained; decision pending'
            Source = 'synthetic revision r2; A evidence x-2'
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-35' -Fields $commonFields -OperationId 'create-common-35' | Out-Null
        $forkSnapshot = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-35'
        $recoveryPayload = [ordered]@{
            'Fork Point' = $forkSnapshot.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A','thread:B')
            'Source Snapshot' = [ordered]@{Current=$forkSnapshot.Fields.Current;Source=$forkSnapshot.Fields.Source;HostIdentity='thread:A'}
            'Shared Baseline' = [ordered]@{Current='Confirmed version 2 requirement; no option selected';Source='synthetic revision r2; confirmed baseline only'}
            'Verified Active Branches' = @($forkSnapshot.ActiveBranches)
            'Branch Creation Operations' = [ordered]@{'thread:A'='fork-a-35';'thread:B'='fork-b-35'}
            'Step Operation IDs' = [ordered]@{createA='fork-a-35';createB='fork-b-35';finish='fork-finish-35'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:ABC-35' -ForkId 'first-fork-35' `
            -Payload $recoveryPayload -OperationId 'fork-pending-35' -Actor 'writer-a' | Out-Null
        $recovery = Get-GitHandoffForkRecovery -Adapter $b -TaskKey 'demo:ABC-35' -ForkId 'first-fork-35'
        $persisted = $recovery.Payload
        $persisted['Source Snapshot'].Current | Should -Be $forkSnapshot.Fields.Current
        $persisted['Source Snapshot'].Source | Should -Be $forkSnapshot.Fields.Source
        $sourceA = [ordered]@{Current=$persisted['Source Snapshot'].Current;Source=$persisted['Source Snapshot'].Source;Lifecycle='Active';'Work State'='Running'}
        $newB = [ordered]@{Current=$persisted['Shared Baseline'].Current;Source=$persisted['Shared Baseline'].Source;Lifecycle='Active';'Work State'='Running'}
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-35' -BranchId $persisted['Intended Branch IDs'][0] -ForkPoint $persisted['Fork Point'] -Fields $sourceA -OperationId $persisted['Step Operation IDs'].createA | Out-Null
        $recoveryRetry = New-GitHandoffForkRecovery -Adapter $b -TaskKey 'demo:ABC-35' -ForkId 'first-fork-35' `
            -Payload $recoveryPayload -OperationId 'fork-pending-35' -Actor 'writer-a'
        $recoveryRetry.Status | Should -Be 'Pending'
        $recoveryRetry.Revision | Should -Be $recovery.Revision
        $remoteRoot = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remoteRoot
        Set-Content -LiteralPath (Join-Path $remoteRoot 'deny-index') -Value 'reject B index' -Encoding ascii
        { New-TestGitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-35' -BranchId $persisted['Intended Branch IDs'][1] -ForkPoint $persisted['Fork Point'] -Fields $newB -OperationId $persisted['Step Operation IDs'].createB } | Should -Throw
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-35' -BranchId 'thread:A').Fields.Current | Should -Be $forkSnapshot.Fields.Current
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-35' -BranchId 'thread:B' | Should -BeNullOrEmpty
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-35').ActiveBranches) | Should -Be @('thread:A')
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-35').Fields.Current | Should -Be $commonFields.Current
        @(Get-GitHandoffPendingForkRecoveries -Adapter $a -TaskKey 'demo:ABC-35').Count | Should -Be 1
        Remove-Item -LiteralPath (Join-Path $remoteRoot 'deny-index') -Force
        $recovered = New-TestGitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-35' -BranchId $persisted['Intended Branch IDs'][1] -ForkPoint $persisted['Fork Point'] -Fields $newB -OperationId $persisted['Step Operation IDs'].createB
        $recovered.Indexed | Should -BeTrue
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-35').ActiveBranches | Sort-Object) | Should -Be @('thread:A','thread:B')
        $indexedCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-35'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-35' -ExpectedRevision $indexedCommon.Revision `
            -Changes ([ordered]@{Current="$($persisted['Shared Baseline'].Current); A/B active";Source=$persisted['Shared Baseline'].Source}) `
            -OperationId $persisted['Step Operation IDs'].finish | Out-Null
        $finalCommon = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-35'
        $finalCommon.Fields.Current | Should -Be "$($persisted['Shared Baseline'].Current); A/B active"
        $finalCommon.Fields.Source | Should -Be $persisted['Shared Baseline'].Source
        $finalCommon.Fields.Source | Should -Not -Match 'A evidence'
        Complete-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:ABC-35' -ForkId 'first-fork-35' `
            -ExpectedRevision $recovery.Revision -OperationId 'complete-fork-35' | Out-Null
    }

    # An uncertain response after a multi-field update must not duplicate or drop either field event on retry.
    It 'InterT40_retries_one_operation_and_preserves_each_field_event' {
        $root = Join-Path $TestDrive 'field-events'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-4' -Fields $script:InitialCommon -OperationId 'create-common-4' | Out-Null
        $before = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-4'
        $changes = [ordered]@{Current='Ready for human review'; 'Work State'='Awaiting Review'}
        $first = Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-4' -ExpectedRevision $before.Revision -Changes $changes -OperationId 'review-op-4' -Reason 'implementation checks passed'
        $retry = Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-4' -ExpectedRevision $before.Revision -Changes $changes -OperationId 'review-op-4' -Reason 'implementation checks passed'
        $first.Revision | Should -Be $retry.Revision
        foreach ($field in @('Current','Work State')) {
            $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-4' -RecordKind common -OperationId 'review-op-4' -Field $field
            $event.OperationId | Should -Be 'review-op-4'
            $event.Field | Should -Be $field
            $event.ReadbackResult | Should -Be 'verified'
        }
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-4').Fields.'Work State' | Should -Be 'Awaiting Review'
    }

    # The remote rejects events after the record succeeds. The same operation must finish pending events on retry.
    It 'InterT50_recovers_a_committed_record_after_event_push_failure' {
        $root = Join-Path $TestDrive 'event-rejection'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-events'
        Set-Content -LiteralPath $flag -Value 'synthetic event failure'
        { New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-5' -Fields $script:InitialCommon -OperationId 'create-common-5' } | Should -Throw
        $committed = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-5'
        $committed.Revision | Should -Not -BeNullOrEmpty
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-5' -RecordKind common -OperationId 'create-common-5' -Field 'Current') | Should -BeNullOrEmpty
        $rawRecord = (@(& git -C $a.RepositoryRoot show "$($committed.Revision):record.json") -join "`n") |
            ConvertFrom-Json -AsHashtable -Depth 50
        $intents = @($rawRecord.operations['create-common-5'].eventIntents)
        $intents.Count | Should -Be $rawRecord.operations['create-common-5'].changedFields.Count
        $rawRecord.operations['create-common-5'].verifiedPrincipal | Should -Be 'synthetic-principal'
        $currentIntent = @($intents | Where-Object { $_.field -ceq 'Current' })
        $currentIntent.Count | Should -Be 1
        $currentIntent[0].operationId | Should -Be 'create-common-5'
        $currentIntent[0].recordId | Should -Be $rawRecord.recordId
        $currentIntent[0].previousState | Should -BeNullOrEmpty
        $currentIntent[0].newState | Should -Be $script:InitialCommon.Current
        $currentIntent[0].source | Should -Be $script:InitialCommon.Source
        $currentIntent[0].integrationStatus | Should -Be 'common-checkpoint'
        $currentIntent[0].verifiedPrincipal | Should -Be 'synthetic-principal'
        Remove-Item -LiteralPath $flag
        $replacementFixture = New-WriterFixture -Root $root -WriterId 'writer-replacement'
        $replacementWriter = New-GitHandoffAdapter -RepositoryRoot $replacementFixture.RepositoryRoot `
            -RemoteName $replacementFixture.RemoteName -RefPrefix $replacementFixture.RefPrefix `
            -AuthorityScope $replacementFixture.AuthorityScope `
            -GetVerifiedPrincipal { 'replacement-principal' } -Authorize { param($request) $true }
        $retried = New-GitHandoffCommon -Adapter $replacementWriter -TaskKey 'demo:ABC-5' -Fields $script:InitialCommon -OperationId 'create-common-5'
        $retried.Revision | Should -Be $committed.Revision
        $recoveredEvent = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-5' -RecordKind common `
            -OperationId 'create-common-5' -Field 'Current'
        $recoveredEvent.ReadbackResult | Should -Be 'verified'
        $recoveredEvent.VerifiedPrincipal | Should -Be 'synthetic-principal'
    }

    # The atomic branch/common fence is rejected before later Active-index reconciliation can begin.
    It 'InterT60_retries_branch_creation_after_atomic_common_fence_failure' {
        $root = Join-Path $TestDrive 'index-rejection'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6' -Fields $script:InitialCommon -OperationId 'create-common-6' | Out-Null
        $commonBefore = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6'
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-index'
        Set-Content -LiteralPath $flag -Value 'synthetic common index failure'
        { New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-6' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-six' } | Should -Throw
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-6' -BranchId 'thread:A' | Should -BeNullOrEmpty
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6').ActiveBranches).Count | Should -Be 0
        Remove-Item -LiteralPath $flag
        $repaired = New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-6' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-six'
        $repaired.Indexed | Should -BeTrue
        $repaired.BranchRevision | Should -Not -BeNullOrEmpty
        $commonAfter = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6'
        $commonAfter.ActiveBranches | Should -Contain 'thread:A'
        $commonAfter.LastActivityAt | Should -Be $commonBefore.LastActivityAt
    }

    It 'InterT70_reconciles_the_original_event_after_a_newer_peer_changed_the_field' {
        $root = Join-Path $TestDrive 'late-event'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-7' -Fields $script:InitialCommon -OperationId 'create-common-7' | Out-Null
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-events'
        Set-Content -LiteralPath $flag -Value 'synthetic event failure'
        $before = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-7'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-7' -ExpectedRevision $before.Revision -Changes ([ordered]@{Current='A verified fact'}) -OperationId 'fact-seven' } | Should -Throw
        $firstCommit = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-7').Revision
        Remove-Item -LiteralPath $flag
        $peer = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-7'
        Set-GitHandoffFields -Adapter $b -RecordKind common -TaskKey 'demo:ABC-7' -ExpectedRevision $peer.Revision -Changes ([ordered]@{Current='B later fact'}) -OperationId 'peer-seven' | Out-Null
        $retry = Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-7' -ExpectedRevision $before.Revision -Changes ([ordered]@{Current='A verified fact'}) -OperationId 'fact-seven'
        $retry.Status | Should -Be 'already-applied'
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-7' -RecordKind common -OperationId 'fact-seven' -Field 'Current'
        $event.NewState | Should -Be 'A verified fact'
        $event.RecordRevision | Should -Be $firstCommit
        (Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:ABC-7').Fields.Current | Should -Be 'B later fact'
    }

    It 'InterT80_rejects_invalid_lifecycle_work_state_and_unconfirmed_outcome' {
        $root = Join-Path $TestDrive 'invalid-enums'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $bad = [ordered]@{}
        foreach ($name in $script:InitialCommon.Keys) { $bad[$name] = $script:InitialCommon[$name] }
        $bad.Lifecycle = 'Completed'
        { New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-8' -Fields $bad -OperationId 'bad-lifecycle' } | Should -Throw
        $caseBypass = [ordered]@{}
        foreach ($name in $script:InitialCommon.Keys) {
            if ([string]$name -cne 'Work State') { $caseBypass[$name] = $script:InitialCommon[$name] }
        }
        $caseBypass['work state'] = 'Completed'
        { New-GitHandoffCommon -Adapter $a -TaskKey 'demo:case-bypass' -Fields $caseBypass `
            -OperationId 'case-bypass-create' } | Should -Throw
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-8' -Fields $script:InitialCommon -OperationId 'create-common-8' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-8'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-8' -ExpectedRevision $common.Revision -Changes ([ordered]@{'Work State'='Completed'}) -OperationId 'bad-workstate' } | Should -Throw
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-8' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-eight' | Out-Null
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-8' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-8' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Branch Outcome'='Selected'}) -OperationId 'no-decision' } | Should -Throw
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-8' `
            -BranchId 'thread:A' -ExpectedRevision $branch.Revision `
            -Changes ([ordered]@{'branch outcome'='Selected'}) -OperationId 'case-bypass-outcome' `
            -DecisionConfirmed } | Should -Throw
    }

    # Scenario: Callers use casing variants for every optional field named by the public contract.
    # Purpose: Make canonical field spelling complete for case-sensitive storage consumers.
    It 'InterT82_rejects_case_variants_for_all_recognized_optional_fields' {
        $root = Join-Path $TestDrive 'canonical-optional-fields'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        foreach ($field in @('fork baselines','integrated decisions','conflict','keep active until')) {
            $fields = [ordered]@{}
            foreach ($name in $script:InitialCommon.Keys) { $fields[$name] = $script:InitialCommon[$name] }
            $fields[$field] = 'fixture'
            { New-GitHandoffCommon -Adapter $a -TaskKey "demo:common-$($field.Replace(' ', '-'))" `
                -Fields $fields -OperationId "bad-common-$($field.Replace(' ', '-'))" -Actor 'writer-a' } | Should -Throw
        }
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:branch-optional-case' -Fields $script:InitialCommon `
            -OperationId 'create-branch-optional-case-common' -Actor 'writer-a' | Out-Null
        foreach ($field in @('candidate conclusion','applicability scope')) {
            $fields = [ordered]@{}
            foreach ($name in $script:InitialBranch.Keys) { $fields[$name] = $script:InitialBranch[$name] }
            $fields[$field] = 'fixture'
            { New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:branch-optional-case' `
                -BranchId "thread:$($field.Replace(' ', '-'))" -ForkPoint 'shared-r1' `
                -Fields $fields -OperationId "bad-branch-$($field.Replace(' ', '-'))" -Actor 'writer-a' } | Should -Throw
        }
    }

    # Scenario: Two peer branches are finalized from one verified common decision while another writer can advance common.
    # Purpose: Reject stale decisions and retain the exact decision revision through outcomes, archives, events, and index-only descendants.
    It 'InterT83_binds_each_branch_finalization_to_the_verified_common_decision_revision' {
        $root = Join-Path $TestDrive 'q83'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $b = New-WriterFixture -Root $root -WriterId 'b'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83' -Fields $script:InitialCommon `
            -OperationId 'create-decision-binding-common' -Actor 'writer-a' | Out-Null
        foreach ($branchId in @('thread:A','thread:B')) {
            New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:q83' -BranchId $branchId `
                -ForkPoint 'shared-r1' -Fields $script:InitialBranch `
                -OperationId "create-$($branchId.Replace(':','-'))" -Actor 'writer-a' | Out-Null
        }

        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83'
        $bindings = @(
            Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q83' -BranchId 'thread:A' -Outcome Superseded
            Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q83' -BranchId 'thread:B' -Outcome Superseded
        )
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q83' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Decision revision one';'Decision Branch Bindings'=$bindings
            }) `
            -OperationId 'decision-one' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'initial user decision superseded both peer results' | Out-Null
        $staleDecisionRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83').Revision

        $peerCommon = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:q83'
        $peerBindings = @(
            Get-GitHandoffBranchReviewBinding -Adapter $b -TaskKey 'demo:q83' -BranchId 'thread:A' -Outcome Selected
            Get-GitHandoffBranchReviewBinding -Adapter $b -TaskKey 'demo:q83' -BranchId 'thread:B' -Outcome Selected
        )
        Set-GitHandoffFields -Adapter $b -RecordKind common -TaskKey 'demo:q83' `
            -ExpectedRevision $peerCommon.Revision -Changes ([ordered]@{
                Current='Decision revision two';'Decision Branch Bindings'=$peerBindings
            }) `
            -OperationId 'decision-two' -DecisionConfirmed -Actor 'writer-b' `
            -Reason 'user replaced the prior branch decision' | Out-Null
        $branchA = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q83' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -ExpectedRevision $branchA.Revision `
            -Changes ([ordered]@{'Branch Outcome'='Selected'}) -OperationId 'outcome-a' `
            -DecisionConfirmed -DecisionCommonRevision $staleDecisionRevision `
            -Actor 'writer-a' -Reason 'adopt branch A' } | Should -Throw
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-a' `
            -DecisionCommonRevision $staleDecisionRevision -Actor 'writer-a' `
            -Reason 'archive branch A after integration' } | Should -Throw
        $branchA = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q83' -BranchId 'thread:A'
        $branchA.Fields.Contains('Branch Outcome') | Should -BeFalse
        $branchA.Fields.Lifecycle | Should -Be 'Active'

        $decisionRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83').Revision
        $preOutcomeA = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q83' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -ExpectedRevision $preOutcomeA.Revision `
            -Changes ([ordered]@{'Branch Outcome'='Selected';Current='mixed finalization write'}) `
            -OperationId 'mixed-outcome-a' -DecisionConfirmed -DecisionCommonRevision $decisionRevision `
            -Actor 'writer-a' -Reason 'reject mixed outcome mutation' } | Should -Throw '*only Branch Outcome*'
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-before-outcome-a' `
            -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'outcome evidence must exist first' } | Should -Throw '*Branch Outcome*recorded first*'
        foreach ($branchId in @('thread:A','thread:B')) {
            $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q83' -BranchId $branchId
            Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q83' `
                -BranchId $branchId -ExpectedRevision $branch.Revision `
                -Changes ([ordered]@{'Branch Outcome'='Selected'}) `
                -OperationId "outcome-$($branchId.Substring($branchId.Length - 1).ToLowerInvariant())" `
                -DecisionConfirmed -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
                -Reason "adopt $branchId" | Out-Null
        }
        $archiveA = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-a' `
            -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'archive branch A after integration'
        $archiveB = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:B' -Lifecycle Archived -OperationId 'archive-b' `
            -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'archive branch B after integration'

        $archiveA.DecisionCommonRevision | Should -Be $decisionRevision
        $archiveB.DecisionCommonRevision | Should -Be $decisionRevision
        $archiveB.CommonRevision | Should -Not -Be $decisionRevision
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83').ActiveBranches).Count | Should -Be 0
        foreach ($branchId in @('thread:A','thread:B')) {
            (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q83' -BranchId $branchId).Fields.Lifecycle | Should -Be 'Archived'
        }
        $outcomeEvent = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q83' `
            -RecordKind branch -BranchId 'thread:A' -OperationId 'outcome-a' -Field 'Branch Outcome'
        $archiveEvent = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q83' `
            -RecordKind branch -BranchId 'thread:B' -OperationId 'archive-b' -Field 'Lifecycle'
        $outcomeEvent.DecisionCommonRevision | Should -Be $decisionRevision
        $archiveEvent.DecisionCommonRevision | Should -Be $decisionRevision
        $outcomeEvent.DecisionBranchRevision | Should -Be $peerBindings[0].reviewedRevision
        $outcomeEvent.DecisionBranchContentSha256 | Should -Be $peerBindings[0].reviewedContentSha256
        $outcomeEvent.DecisionBranchContinuationGeneration | Should -Be $peerBindings[0].continuationGeneration
        $archiveEvent.DecisionBranchRevision | Should -Be $peerBindings[1].reviewedRevision
        $archiveEvent.DecisionBranchContentSha256 | Should -Be $peerBindings[1].reviewedContentSha256
        $archiveEvent.DecisionBranchContinuationGeneration | Should -Be $peerBindings[1].continuationGeneration
        $retriedArchiveA = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-a' `
            -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'archive branch A after integration'
        $retriedArchiveA.DecisionCommonRevision | Should -Be $decisionRevision
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-a' `
            -DecisionCommonRevision $decisionRevision -Actor 'different-writer' `
            -Reason 'archive branch A after integration' } | Should -Throw
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:B' -Lifecycle Archived -OperationId 'archive-b-different' `
            -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'duplicate archive must not synthesize a new event' } | Should -Throw
        $postDecisionCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q83' `
            -ExpectedRevision $postDecisionCommon.Revision -Changes ([ordered]@{Current='ordinary revision inheriting prior bindings'}) `
            -OperationId 'ordinary-after-decision' -Actor 'writer-a' -Reason 'prove inherited bindings are not fresh authority' | Out-Null
        $inheritedRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q83').Revision
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q83' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'reject-inherited-decision' `
            -DecisionCommonRevision $inheritedRevision -Actor 'writer-a' `
            -Reason 'an ordinary descendant cannot authorize finalization' } | Should -Throw '*did not originate*'
    }

    It 'InterT84c_fences_decision_bound_branch_write_against_a_live_common_decision_change' {
        $root = Join-Path $TestDrive 'q84c'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $b = New-WriterFixture -Root $root -WriterId 'b'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84c' -Fields $script:InitialCommon `
            -OperationId 'create-q84c-common' -Actor 'writer-a' | Out-Null
        foreach ($branchId in @('thread:A','thread:B')) {
            New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:q84c' -BranchId $branchId `
                -ForkPoint 'shared-r1' -Fields $script:InitialBranch `
                -OperationId "create-$($branchId.Replace(':','-'))" -Actor 'writer-a' | Out-Null
        }
        $bindingOne = @(
            Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q84c' -BranchId 'thread:A' -Outcome Superseded
            Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q84c' -BranchId 'thread:B' -Outcome Superseded
        )
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84c'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84c' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Decision one';'Decision Branch Bindings'=$bindingOne
            }) -OperationId 'q84c-decision-one' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'first confirmed branch decision' | Out-Null
        $decisionOneRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84c').Revision

        $bin = Join-Path $root 'git-barrier-bin'
        [void](New-Item -ItemType Directory -Path $bin)
        $gitWrapper = Join-Path $bin 'git.cmd'
        $gitWrapperText = @'
@echo off
setlocal EnableDelayedExpansion
if /I "%SYP_TEST_BARRIER_ROLE%"=="decision-finalize" (
  set "HANDOFF_IS_COMMIT_TREE=0"
  for %%A in (%*) do if /I "%%~A"=="commit-tree" set "HANDOFF_IS_COMMIT_TREE=1"
  if "!HANDOFF_IS_COMMIT_TREE!"=="1" (
    if not exist "%SYP_TEST_BARRIER_FIRST%" (
      >"%SYP_TEST_BARRIER_FIRST%" echo common fence commit created
    ) else (
      >"%SYP_TEST_BARRIER_ENTERED%" echo decision-bound branch commit created
      :wait_for_release
      if exist "%SYP_TEST_BARRIER_BLOCK%" (
        %SystemRoot%\System32\ping.exe -n 2 -w 100 127.0.0.1 >nul
        goto wait_for_release
      )
    )
  )
)
"%SYP_TEST_REAL_GIT%" %*
exit /b %ERRORLEVEL%
'@
        Set-Content -LiteralPath $gitWrapper -Value $gitWrapperText -Encoding ascii
        $remote = Join-Path $root 'remote.git'
        $blockFinalizePush = Join-Path $remote 'block-finalize-push'
        $finalizePushEntered = Join-Path $remote 'finalize-push-entered'
        $commitTreeFirst = Join-Path $remote 'commit-tree-first'
        Set-Content -LiteralPath $blockFinalizePush -Value 'hold decision-bound branch push' -Encoding ascii
        $modulePath = Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
        $realGit = (Get-Command git.exe -ErrorAction Stop).Source
        $priorGitFunction = Get-Command git -CommandType Function -ErrorAction SilentlyContinue
        function global:git {
            $gitArguments = @($args)
            if ($env:SYP_TEST_BARRIER_ROLE -eq 'decision-finalize' -and $gitArguments -contains 'commit-tree') {
                if (-not (Test-Path -LiteralPath $env:SYP_TEST_BARRIER_FIRST)) {
                    Set-Content -LiteralPath $env:SYP_TEST_BARRIER_FIRST -Value 'common fence commit created' -Encoding ascii
                }
                else {
                    Set-Content -LiteralPath $env:SYP_TEST_BARRIER_ENTERED -Value 'decision-bound branch commit created' -Encoding ascii
                    while (Test-Path -LiteralPath $env:SYP_TEST_BARRIER_BLOCK) {
                        Start-Sleep -Milliseconds 50
                    }
                }
            }
            & $env:SYP_TEST_REAL_GIT @gitArguments
        }
        $decisionJob = $null
        $originalPath = $env:Path
        $originalBarrierRole = $env:SYP_TEST_BARRIER_ROLE
        $originalBarrierEntered = $env:SYP_TEST_BARRIER_ENTERED
        $originalBarrierBlock = $env:SYP_TEST_BARRIER_BLOCK
        $originalBarrierFirst = $env:SYP_TEST_BARRIER_FIRST
        $originalRealGit = $env:SYP_TEST_REAL_GIT
        try {
            $decisionJob = Start-Job -ScriptBlock {
                param($ModulePath,$RepositoryRoot,$GitWrapperDir,$BarrierEntered,$BarrierBlock)
                $env:Path = (($env:Path -split ';') | Where-Object { $_ -and $_ -ne $GitWrapperDir }) -join ';'
                $env:SYP_TEST_BARRIER_ROLE = ''
                Import-Module $ModulePath -Force
                $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                    -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                    -Authorize { param($request) $true }
                $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
                while (-not (Test-Path -LiteralPath $BarrierEntered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 50
                }
                if (-not (Test-Path -LiteralPath $BarrierEntered)) { throw 'The branch writer did not reach the push barrier.' }
                $commonB = Get-GitHandoffCommon -Adapter $adapter -TaskKey 'demo:q84c'
                $bindingTwo = @(
                    Get-GitHandoffBranchReviewBinding -Adapter $adapter -TaskKey 'demo:q84c' -BranchId 'thread:A' -Outcome Selected
                    Get-GitHandoffBranchReviewBinding -Adapter $adapter -TaskKey 'demo:q84c' -BranchId 'thread:B' -Outcome Selected
                )
                Set-GitHandoffFields -Adapter $adapter -RecordKind common -TaskKey 'demo:q84c' `
                    -ExpectedRevision $commonB.Revision -Changes ([ordered]@{
                        Current='Decision two';'Decision Branch Bindings'=$bindingTwo
                    }) -OperationId 'q84c-decision-two' -DecisionConfirmed -Actor 'writer-b' `
                    -Reason 'user replaced the prior branch decision' | Out-Null
                Remove-Item -LiteralPath $BarrierBlock -Force -ErrorAction SilentlyContinue
                [pscustomobject]@{status='succeeded'}
            } -ArgumentList $modulePath,$b.RepositoryRoot,$bin,$finalizePushEntered,$blockFinalizePush

            $env:Path = "$bin;$env:Path"
            $env:SYP_TEST_BARRIER_ROLE = 'decision-finalize'
            $env:SYP_TEST_BARRIER_ENTERED = $finalizePushEntered
            $env:SYP_TEST_BARRIER_BLOCK = $blockFinalizePush
            $env:SYP_TEST_BARRIER_FIRST = $commitTreeFirst
            $env:SYP_TEST_REAL_GIT = $realGit
            $finalizeFailure = $null
            try {
                $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84c' -BranchId 'thread:A'
                Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84c' -BranchId 'thread:A' `
                    -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Branch Outcome'='Superseded'}) `
                    -OperationId 'q84c-race-outcome' -DecisionConfirmed -DecisionCommonRevision $decisionOneRevision `
                    -Actor 'writer-a' -Reason 'archive the reviewed branch after decision' | Out-Null
            }
            catch { $finalizeFailure = [string]$_.Exception.Message }
            $finalizePushEntered | Should -Exist
            $finalizeFailure | Should -Match 'live common decision|decision-bound branch|atomic|Conditional|supplied common revision'
            $decisionResult = Receive-Job -Job $decisionJob -Wait -AutoRemoveJob -ErrorAction Stop
            $decisionJob = $null
            $decisionResult.status | Should -Be 'succeeded'
            $afterRace = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84c' -BranchId 'thread:A'
            $afterRace.Fields.Contains('Branch Outcome') | Should -BeFalse
            (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q84c' -RecordKind branch `
                -BranchId 'thread:A' -OperationId 'q84c-race-outcome' -Field 'Branch Outcome') | Should -BeNullOrEmpty
            (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84c').Fields.Current | Should -Be 'Decision two'
        }
        finally {
            $env:Path = $originalPath
            $env:SYP_TEST_BARRIER_ROLE = $originalBarrierRole
            $env:SYP_TEST_BARRIER_ENTERED = $originalBarrierEntered
            $env:SYP_TEST_BARRIER_BLOCK = $originalBarrierBlock
            $env:SYP_TEST_BARRIER_FIRST = $originalBarrierFirst
            $env:SYP_TEST_REAL_GIT = $originalRealGit
            if ($null -ne $priorGitFunction) {
                Set-Item -Path Function:\git -Value $priorGitFunction.ScriptBlock
            }
            else {
                Remove-Item -Path Function:\git -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $blockFinalizePush -Force -ErrorAction SilentlyContinue
            if ($null -ne $decisionJob) {
                Stop-Job -Job $decisionJob -ErrorAction SilentlyContinue
                Remove-Job -Job $decisionJob -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Scenario: A peer changes reviewed branch content after a common decision but before its finalization.
    # Purpose: Stop old-decision outcomes and archival until the user confirms a new exact branch revision and content identity.
    It 'InterT84_binds_finalization_to_the_exact_reviewed_branch_revision_and_content' {
        $root = Join-Path $TestDrive 'q84'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $b = New-WriterFixture -Root $root -WriterId 'b'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84' -Fields $script:InitialCommon `
            -OperationId 'create-q84-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch `
            -OperationId 'create-q84-a' -Actor 'writer-a' | Out-Null

        $binding = Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q84' `
            -BranchId 'thread:A' -Outcome Selected
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84'
        $malformedBinding = [ordered]@{
            branchId=$binding.branchId;reviewedRevision=$binding.reviewedRevision;
            reviewedContentSha256=$binding.reviewedContentSha256
        }
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Malformed binding';'Decision Branch Bindings'=@($malformedBinding)
            }) -OperationId 'reject-malformed-binding' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'reject incomplete reviewed branch identity' } | Should -Throw
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Duplicate binding';'Decision Branch Bindings'=@($binding,$binding)
            }) -OperationId 'reject-duplicate-binding' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'reject ambiguous reviewed branch identity' } | Should -Throw

        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Decision over exact branch A';'Decision Branch Bindings'=@($binding)
            }) -OperationId 'q84-decision-one' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'user selected reviewed branch A' | Out-Null
        $oldDecisionRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84').Revision

        $branchBeforePeer = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84' `
            -BranchId 'thread:A' -ExpectedRevision $branchBeforePeer.Revision `
            -Changes ([ordered]@{'Branch Outcome'='Superseded'}) -OperationId 'wrong-outcome' `
            -DecisionConfirmed -DecisionCommonRevision $oldDecisionRevision -Actor 'writer-a' `
            -Reason 'outcome does not match confirmed selection' } | Should -Throw

        $peerBranch = Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:q84' -BranchId 'thread:A'
        Set-GitHandoffFields -Adapter $b -RecordKind branch -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -ExpectedRevision $peerBranch.Revision -Changes ([ordered]@{Current='Peer changed reviewed content'}) `
            -OperationId 'peer-advanced-content' -Actor 'writer-b' `
            -Reason 'continue exploring branch A' | Out-Null
        $advanced = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -ExpectedRevision $advanced.Revision -Changes ([ordered]@{'Branch Outcome'='Selected'}) `
            -OperationId 'old-decision-outcome' -DecisionConfirmed -DecisionCommonRevision $oldDecisionRevision `
            -Actor 'writer-a' -Reason 'must reject changed branch content' } | Should -Throw
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'old-decision-archive' -DecisionCommonRevision $oldDecisionRevision `
            -Actor 'writer-a' -Reason 'must reject changed branch content' } | Should -Throw
        $afterRejectedFinalization = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A'
        $afterRejectedFinalization.Fields.Contains('Branch Outcome') | Should -BeFalse
        $afterRejectedFinalization.Fields.Lifecycle | Should -Be 'Active'

        $newBinding = Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q84' `
            -BranchId 'thread:A' -Outcome Selected
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Renewed decision over changed branch A';'Decision Branch Bindings'=@($newBinding)
            }) -OperationId 'q84-decision-two' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'user renewed selection over current branch A' | Out-Null
        $newDecisionRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84').Revision
        $currentBranch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A'
        Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -ExpectedRevision $currentBranch.Revision -Changes ([ordered]@{'Branch Outcome'='Selected'}) `
            -OperationId 'new-decision-outcome' -DecisionConfirmed -DecisionCommonRevision $newDecisionRevision `
            -Actor 'writer-a' -Reason 'adopt renewed branch A' | Out-Null
        $archive = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'new-decision-archive' -DecisionCommonRevision $newDecisionRevision `
            -Actor 'writer-a' -Reason 'archive renewed branch A after integration'

        $outcomeEvent = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q84' -RecordKind branch `
            -BranchId 'thread:A' -OperationId 'new-decision-outcome' -Field 'Branch Outcome'
        $archiveEvent = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q84' -RecordKind branch `
            -BranchId 'thread:A' -OperationId 'new-decision-archive' -Field 'Lifecycle'
        foreach ($event in @($outcomeEvent,$archiveEvent)) {
            $event.DecisionCommonRevision | Should -Be $newDecisionRevision
            $event.DecisionBranchRevision | Should -Be $newBinding.reviewedRevision
            $event.DecisionBranchContentSha256 | Should -Be $newBinding.reviewedContentSha256
            $event.DecisionBranchContinuationGeneration | Should -Be $newBinding.continuationGeneration
        }
        $archive.DecisionBranchRevision | Should -Be $newBinding.reviewedRevision
        $archive.DecisionBranchContentSha256 | Should -Be $newBinding.reviewedContentSha256
        $archive.DecisionBranchContinuationGeneration | Should -Be $newBinding.continuationGeneration
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'new-decision-archive' -DecisionCommonRevision $newDecisionRevision `
            -Actor 'different-writer' -Reason 'archive renewed branch A after integration' } | Should -Throw
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'new-decision-archive' -DecisionCommonRevision $newDecisionRevision `
            -Actor 'writer-a' -Reason 'different retry reason' } | Should -Throw
        $restored = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -Lifecycle Active -OperationId 'restore-after-decision' -ExplicitContinuation `
            -Actor 'writer-a' -Reason 'continue the exact archived branch'
        $restored.ContinuationGeneration | Should -Be ([int64]$newBinding.continuationGeneration + 1)
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'stale-decision-after-restore' -DecisionCommonRevision $newDecisionRevision `
            -Actor 'writer-a' -Reason 'old decision cannot archive restored branch' } | Should -Throw
        $continued = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84' -BranchId 'thread:A'
        $continued.Fields.Lifecycle | Should -Be 'Active'
        $continued.ContinuationGeneration | Should -Be ([int64]$newBinding.continuationGeneration + 1)
    }

    # Scenario: A confirmed decision exists while its reviewed branch is still Active and the user resumes that branch.
    # Purpose: Fence stale finalization before resumed work or a new fork can begin.
    It 'InterT84a_advances_generation_when_an_active_branch_is_explicitly_continued' {
        $root = Join-Path $TestDrive 'q84a'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84a' -Fields $script:InitialCommon `
            -OperationId 'create-q84a-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:q84a' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch `
            -OperationId 'create-q84a-a' -Actor 'writer-a' | Out-Null

        $binding = Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q84a' `
            -BranchId 'thread:A' -Outcome Selected
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84a'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84a' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Decision before active continuation';'Decision Branch Bindings'=@($binding)
            }) -OperationId 'q84a-decision' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'user selected reviewed active branch A' | Out-Null
        $decisionRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84a').Revision

        $continued = Start-GitHandoffBranchContinuation -Adapter $a -TaskKey 'demo:q84a' `
            -BranchId 'thread:A' -OperationId 'continue-active-q84a' -Actor 'writer-a' `
            -Reason 'resume exact active branch before new work'
        $continued.Lifecycle | Should -Be 'Active'
        $continued.Indexed | Should -BeTrue
        $continued.ContinuationGeneration | Should -Be ([int64]$binding.continuationGeneration + 1)

        $retried = Start-GitHandoffBranchContinuation -Adapter $a -TaskKey 'demo:q84a' `
            -BranchId 'thread:A' -OperationId 'continue-active-q84a' -Actor 'writer-a' `
            -Reason 'resume exact active branch before new work'
        $retried.ContinuationGeneration | Should -Be $continued.ContinuationGeneration
        $retried.BranchRevision | Should -Be $continued.BranchRevision
        { Start-GitHandoffBranchContinuation -Adapter $a -TaskKey 'demo:q84a' `
            -BranchId 'thread:A' -OperationId 'continue-active-q84a' -Actor 'different-writer' `
            -Reason 'resume exact active branch before new work' } | Should -Throw

        $current = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84a' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84a' -BranchId 'thread:A' `
            -ExpectedRevision $current.Revision -Changes ([ordered]@{'Branch Outcome'='Selected'}) `
            -OperationId 'q84a-stale-outcome' -DecisionConfirmed -DecisionCommonRevision $decisionRevision `
            -Actor 'writer-a' -Reason 'old decision cannot finalize active continuation' } | Should -Throw
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:q84a' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'q84a-stale-archive' -DecisionCommonRevision $decisionRevision `
            -Actor 'writer-a' -Reason 'old decision cannot archive active continuation' } | Should -Throw

        $generationEvent = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q84a' -RecordKind branch `
            -BranchId 'thread:A' -OperationId 'continue-active-q84a' -Field 'Continuation Generation'
        $generationEvent.PreviousState | Should -Be ([int64]$binding.continuationGeneration)
        $generationEvent.NewState | Should -Be ([int64]$binding.continuationGeneration + 1)
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84a' -BranchId 'thread:A').Fields.Lifecycle | Should -Be 'Active'
    }

    It 'InterT84b_reconciles_finalization_and_continuation_events_before_stale_checks' {
        $root = Join-Path $TestDrive 'q84b'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'a'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84b' -Fields $script:InitialCommon `
            -OperationId 'create-q84b-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:q84b' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch `
            -OperationId 'create-q84b-a' -Actor 'writer-a' | Out-Null
        $binding = Get-GitHandoffBranchReviewBinding -Adapter $a -TaskKey 'demo:q84b' `
            -BranchId 'thread:A' -Outcome Selected
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84b'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84b' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{
                Current='Exact q84b decision';'Decision Branch Bindings'=@($binding)
            }) -OperationId 'q84b-decision' -DecisionConfirmed -Actor 'writer-a' `
            -Reason 'user selected exact q84b branch' | Out-Null
        $decisionRevision = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84b').Revision

        Add-SelectiveRejectHook -RemoteRoot $remote
        $eventFlag = Join-Path $remote 'deny-events'
        Set-Content -LiteralPath $eventFlag -Value 'block outcome event once'
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84b' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84b' `
            -BranchId 'thread:A' -ExpectedRevision $branch.Revision `
            -Changes ([ordered]@{'Branch Outcome'='Selected'}) -OperationId 'q84b-outcome' `
            -DecisionConfirmed -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'persist selected outcome' } | Should -Throw
        Remove-Item -LiteralPath $eventFlag
        $advancedCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:q84b'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:q84b' `
            -ExpectedRevision $advancedCommon.Revision -Changes ([ordered]@{Current='Decision context advanced after outcome commit'}) `
            -OperationId 'q84b-advance-common' -Actor 'writer-a' -Reason 'invalidate old decision context' | Out-Null
        $committedOutcomeBranch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:q84b' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:q84b' `
            -BranchId 'thread:A' -ExpectedRevision $committedOutcomeBranch.Revision `
            -Changes ([ordered]@{'Branch Outcome'='Selected'}) -OperationId 'q84b-outcome' `
            -DecisionConfirmed -DecisionCommonRevision $decisionRevision -Actor 'writer-a' `
            -Reason 'persist selected outcome' } | Should -Throw
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q84b' -RecordKind branch `
            -BranchId 'thread:A' -OperationId 'q84b-outcome' -Field 'Branch Outcome').ReadbackResult | Should -Be 'verified'

        Set-Content -LiteralPath $eventFlag -Value 'block continuation event once'
        { Start-GitHandoffBranchContinuation -Adapter $a -TaskKey 'demo:q84b' -BranchId 'thread:A' `
            -OperationId 'q84b-continue' -Actor 'writer-a' -Reason 'continue after committed outcome' } | Should -Throw
        Remove-Item -LiteralPath $eventFlag
        $continued = Start-GitHandoffBranchContinuation -Adapter $a -TaskKey 'demo:q84b' -BranchId 'thread:A' `
            -OperationId 'q84b-continue' -Actor 'writer-a' -Reason 'continue after committed outcome'
        $continued.ContinuationGeneration | Should -Be 1
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:q84b' -RecordKind branch `
            -BranchId 'thread:A' -OperationId 'q84b-continue' -Field 'Continuation Generation').ReadbackResult | Should -Be 'verified'
    }

    # Scenario: An update tries to clear a required field after creation validation has already passed.
    # Purpose: Keep every committed common and branch record readable under the required-field contract.
    It 'InterT85_rejects_updates_that_remove_required_record_fields' {
        $root = Join-Path $TestDrive 'q85'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:required-update' -Fields $script:InitialCommon `
            -OperationId 'create-required-update' -Actor 'writer-a' | Out-Null
        $before = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:required-update'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:required-update' `
            -ExpectedRevision $before.Revision -Changes ([ordered]@{Source=$null}) `
            -OperationId 'clear-required-source' -Actor 'writer-a' } | Should -Throw
        $after = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:required-update'
        $after.Revision | Should -Be $before.Revision
        $after.Fields.Source | Should -Be $script:InitialCommon.Source
    }

    # Scenario: A caller creates a new peer while the exact common record is archived.
    # Purpose: Require explicit common continuation before a durable Active branch can exist.
    It 'InterT87_rejects_branch_creation_under_an_archived_common_record' {
        $root = Join-Path $TestDrive 'q87'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:archived-common' -Fields $script:InitialCommon `
            -OperationId 'create-archived-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:archived-common'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:archived-common' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{Lifecycle='Archived'}) `
            -OperationId 'archive-common-before-branch' -Actor 'writer-a' -Reason 'explicit close with no active peers' | Out-Null
        { New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:archived-common' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'forbidden-peer-create' `
            -Actor 'writer-a' } | Should -Throw
        Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:archived-common' -BranchId 'thread:A' | Should -BeNullOrEmpty
    }

    # Scenario: A prior common mutation legitimately owns the old derived `${OperationId}:index` text.
    # Purpose: Keep adapter-owned structural operation identities in a reserved collision-free namespace.
    It 'InterT88_uses_a_reserved_internal_identity_for_branch_index_creation' {
        $root = Join-Path $TestDrive 'q88'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:index-operation-collision' -Fields $script:InitialCommon `
            -OperationId 'create-index-collision-common' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:index-operation-collision'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:index-operation-collision' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{Current='prior legitimate common checkpoint'}) `
            -OperationId 'create-collision-branch:index' -Actor 'writer-a' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:index-operation-collision'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:index-operation-collision' `
            -ExpectedRevision $common.Revision -Changes ([ordered]@{Current='attempt reserved identity'}) `
            -OperationId '__handoff_internal_v1__:adopter-claim' -Actor 'writer-a' } | Should -Throw
        $created = New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:index-operation-collision' `
            -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch `
            -OperationId 'create-collision-branch' -Actor 'writer-a'
        $created.Indexed | Should -BeTrue
        $created.IndexOperationId | Should -Match '^__handoff_internal_v1__:'
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:index-operation-collision').ActiveBranches | Should -Contain 'thread:A'
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:index-operation-collision' `
            -BranchId 'thread:A' -Lifecycle Active -ExplicitContinuation `
            -OperationId '__handoff_internal_v1__:lifecycle-claim' -Actor 'writer-a' } | Should -Throw
    }

    It 'InterT90_repairs_an_archived_branch_index_and_restores_only_the_exact_peer' {
        $root = Join-Path $TestDrive 'archive-retry'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-9' -Fields $script:InitialCommon -OperationId 'create-common-9' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-nine-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:B' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-nine-b' | Out-Null
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-index'
        Set-Content -LiteralPath $flag -Value 'synthetic archive index failure'
        $lastActivity = (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A').LastActivityAt
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-nine-a' } | Should -Throw
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A').Fields.Lifecycle | Should -Be 'Archived'
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-9').ActiveBranches | Should -Contain 'thread:A'
        Remove-Item -LiteralPath $flag
        $repair = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-nine-a'
        $repair.Indexed | Should -BeFalse
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-9'
        $common.ActiveBranches | Should -Contain 'thread:B'
        $common.ActiveBranches | Should -Not -Contain 'thread:A'
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A').LastActivityAt | Should -Be $lastActivity
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A' -Lifecycle Active -OperationId 'restore-nine-a' } | Should -Throw
        $restored = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A' -Lifecycle Active -OperationId 'restore-nine-a' -ExplicitContinuation
        $restored.Indexed | Should -BeTrue
        $post = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-9'
        $post.ActiveBranches | Should -Contain 'thread:A'
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:B').Fields.Lifecycle | Should -Be 'Active'
    }

    # Scenario: Archive pauses while updating common, then another writer restores the same branch before the stale index push completes.
    # Purpose: Reconcile the common index from the latest branch revision instead of the archive caller's stale lifecycle.
    It 'InterT95_revalidates_branch_lifecycle_after_a_concurrent_restore' {
        $root = Join-Path $TestDrive 'q95'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:lifecycle-race' -Fields $script:InitialCommon `
            -OperationId 'create-race-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:lifecycle-race' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'create-race-branch' `
            -Actor 'writer-a' | Out-Null

        $hook = Join-Path $remote 'hooks/pre-receive'
        $hookText = @'
#!/bin/sh
while read old new ref; do
  case "$ref" in
    refs/heads/handoff-v1/records/*/common)
      if [ -f "$GIT_DIR/block-index" ]; then
        : > "$GIT_DIR/index-entered"
        while [ -f "$GIT_DIR/block-index" ]; do sleep 0.05; done
      fi
      ;;
    refs/heads/handoff-v1/events/*)
      if [ -f "$GIT_DIR/deny-event-once" ]; then
        compact=$(git show "$new:event.json" | tr -d '\r\n ')
        if printf '%s' "$compact" | grep -Fq '"RecordKind":"common"' && \
           printf '%s' "$compact" | grep -Fq '"Field":"Active Branches"'; then
          rm -f "$GIT_DIR/deny-event-once"
          exit 1
        fi
      fi
      ;;
  esac
done
exit 0
'@
        Set-Content -LiteralPath $hook -Value $hookText -Encoding utf8
        if (-not $IsWindows) {
            $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
            [IO.File]::SetUnixFileMode($hook, $mode)
        }
        $block = Join-Path $remote 'block-index'
        $entered = Join-Path $remote 'index-entered'
        $denyEventOnce = Join-Path $remote 'deny-event-once'
        Set-Content -LiteralPath $block -Value 'pause stale archive index write'
        Set-Content -LiteralPath $denyEventOnce -Value 'reject the first archive index event only'
        $modulePath = Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
        $archiveJob = Start-Job -ScriptBlock {
            param($ModulePath,$RepositoryRoot)
            Import-Module $ModulePath -Force
            $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                -Authorize { param($request) $true }
            Set-GitHandoffBranchLifecycle -Adapter $adapter -TaskKey 'demo:lifecycle-race' `
                -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-race' `
                -Actor 'writer-a' -Reason 'archive after branch review'
        } -ArgumentList $modulePath,$a.RepositoryRoot
        try {
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $entered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            Test-Path -LiteralPath $entered | Should -BeTrue
            $restored = Set-GitHandoffBranchLifecycle -Adapter $b -TaskKey 'demo:lifecycle-race' `
                -BranchId 'thread:A' -Lifecycle Active -OperationId 'restore-race' `
                -ExplicitContinuation -Actor 'writer-b' -Reason 'explicitly continue the exact branch'
            $restored.Indexed | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $block -Force -ErrorAction SilentlyContinue
        }
        $archiveResult = Receive-Job -Job $archiveJob -Wait -AutoRemoveJob -ErrorAction Stop
        $archiveResult | Should -Not -BeNullOrEmpty
        @($archiveResult.IndexOperationIds).Count | Should -Be 2
        foreach ($indexOperationId in @($archiveResult.IndexOperationIds)) {
            $event = Get-GitHandoffEvent -Adapter $b -TaskKey 'demo:lifecycle-race' `
                -RecordKind common -OperationId $indexOperationId -Field 'Active Branches'
            $event.ReadbackResult | Should -Be 'verified'
        }
        $finalBranch = Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:lifecycle-race' -BranchId 'thread:A'
        $finalCommon = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:lifecycle-race'
        $finalBranch.Fields.Lifecycle | Should -Be 'Active'
        $finalCommon.ActiveBranches | Should -Contain 'thread:A'
    }

    # Scenario: Branch creation pauses before its common-index write while another writer archives that new branch.
    # Purpose: Prevent a stale create path from leaving an Archived branch in the Active index.
    It 'InterT96_reconciles_creation_index_against_a_concurrent_archive' {
        $root = Join-Path $TestDrive 'q96'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:create-archive-race' -Fields $script:InitialCommon `
            -OperationId 'create-race-common' -Actor 'writer-a' | Out-Null
        $createRaceCommon = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:create-archive-race'
        $createRaceFields = [ordered]@{
            Current='Separate peer checkpoint';Source='synthetic fixture revision r2';
            Lifecycle='Active';'Work State'='Running'
        }
        $createRacePayload = [ordered]@{
            'Fork Point' = $createRaceCommon.Revision
            'Source Branch ID' = 'thread:A'
            'Intended Branch IDs' = @('thread:A')
            'Source Snapshot' = [ordered]@{Current=$createRaceFields.Current;Source=$createRaceFields.Source}
            'Shared Baseline' = [ordered]@{Current=$createRaceFields.Current;Source=$createRaceFields.Source}
            'Verified Active Branches' = @()
            'Branch Creation Operations' = [ordered]@{'thread:A'='create-race-branch'}
            'Step Operation IDs' = [ordered]@{create='create-race-branch'}
        }
        New-GitHandoffForkRecovery -Adapter $a -TaskKey 'demo:create-archive-race' `
            -ForkId 'fixture-create-race-branch' -Payload $createRacePayload `
            -OperationId 'prepare-create-race-branch' -Actor 'writer-a' | Out-Null

        $hook = Join-Path $remote 'hooks/pre-receive'
        $hookText = @'
#!/bin/sh
while read old new ref; do
  case "$ref" in
    refs/heads/handoff-v1/records/*/common)
      compact=$(git show "$new:record.json" | tr -d '\r\n ')
      if [ -f "$GIT_DIR/block-create-index" ] && printf '%s' "$compact" | grep -Fq '"activeBranches":["thread:A"]'; then
        : > "$GIT_DIR/create-index-entered"
        while [ -f "$GIT_DIR/block-create-index" ]; do sleep 0.05; done
      fi
      ;;
  esac
done
exit 0
'@
        Set-Content -LiteralPath $hook -Value $hookText -Encoding utf8
        if (-not $IsWindows) {
            $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
            [IO.File]::SetUnixFileMode($hook, $mode)
        }
        $block = Join-Path $remote 'block-create-index'
        $entered = Join-Path $remote 'create-index-entered'
        Set-Content -LiteralPath $block -Value 'pause stale creation index write'
        $modulePath = Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
        $createJob = Start-Job -ScriptBlock {
            param($ModulePath,$RepositoryRoot,$ForkPoint)
            Import-Module $ModulePath -Force
            $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                -Authorize { param($request) $true }
            New-GitHandoffBranch -Adapter $adapter -TaskKey 'demo:create-archive-race' `
                -BranchId 'thread:A' -ForkPoint $ForkPoint -Fields ([ordered]@{
                    Current='Separate peer checkpoint';Source='synthetic fixture revision r2';
                    Lifecycle='Active';'Work State'='Running'
                }) -OperationId 'create-race-branch' -Actor 'writer-a'
        } -ArgumentList $modulePath,$a.RepositoryRoot,$createRaceCommon.Revision
        try {
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
            while (-not (Test-Path -LiteralPath $entered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            Test-Path -LiteralPath $entered | Should -BeTrue
            Set-GitHandoffBranchLifecycle -Adapter $b -TaskKey 'demo:create-archive-race' `
                -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-during-create' `
                -Actor 'writer-b' -Reason 'archive newly created inactive branch' | Out-Null
        }
        finally {
            Remove-Item -LiteralPath $block -Force -ErrorAction SilentlyContinue
        }
        $createResult = Receive-Job -Job $createJob -Wait -AutoRemoveJob -ErrorAction Stop
        $createResult.Indexed | Should -BeFalse
        (Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:create-archive-race' -BranchId 'thread:A').Fields.Lifecycle | Should -Be 'Archived'
        (Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:create-archive-race').ActiveBranches | Should -Not -Contain 'thread:A'
    }

    # Scenario: Branch restore pauses before re-indexing and another writer archives the empty common record.
    # Purpose: Restore and verify common lifecycle again before an Active branch can be placed in its index.
    It 'InterT97_revalidates_common_lifecycle_before_restoring_the_branch_index' {
        $root = Join-Path $TestDrive 'q97'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:common-archive-race' -Fields $script:InitialCommon `
            -OperationId 'create-common-archive-race' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:common-archive-race' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'create-common-archive-race-branch' `
            -Actor 'writer-a' | Out-Null
        Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:common-archive-race' `
            -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-before-common-race' `
            -Actor 'writer-a' -Reason 'prepare an unindexed archived branch' | Out-Null

        $hook = Join-Path $remote 'hooks/pre-receive'
        $hookText = @'
#!/bin/sh
while read old new ref; do
  case "$ref" in
    refs/heads/handoff-v1/records/*/common)
      compact=$(git show "$new:record.json" | tr -d '\r\n ')
      if [ -f "$GIT_DIR/block-active-index" ] && printf '%s' "$compact" | grep -Fq '"activeBranches":["thread:A"]'; then
        : > "$GIT_DIR/active-index-entered"
        while [ -f "$GIT_DIR/block-active-index" ]; do sleep 0.05; done
      fi
      ;;
  esac
done
exit 0
'@
        Set-Content -LiteralPath $hook -Value $hookText -Encoding utf8
        if (-not $IsWindows) {
            $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
            [IO.File]::SetUnixFileMode($hook, $mode)
        }
        $block = Join-Path $remote 'block-active-index'
        $entered = Join-Path $remote 'active-index-entered'
        Set-Content -LiteralPath $block -Value 'pause restore index write'
        $modulePath = Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
        $restoreJob = Start-Job -ScriptBlock {
            param($ModulePath,$RepositoryRoot)
            Import-Module $ModulePath -Force
            $adapter = New-GitHandoffAdapter -RepositoryRoot $RepositoryRoot -RemoteName origin `
                -AuthorityScope 'synthetic-scope' -GetVerifiedPrincipal { 'synthetic-principal' } `
                -Authorize { param($request) $true }
            Set-GitHandoffBranchLifecycle -Adapter $adapter -TaskKey 'demo:common-archive-race' `
                -BranchId 'thread:A' -Lifecycle Active -OperationId 'restore-common-race' `
                -ExplicitContinuation -Actor 'writer-a' -Reason 'explicitly restore exact branch'
        } -ArgumentList $modulePath,$a.RepositoryRoot
        try {
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath $entered) -and [DateTimeOffset]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            Test-Path -LiteralPath $entered | Should -BeTrue
            $common = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:common-archive-race'
            Set-GitHandoffFields -Adapter $b -RecordKind common -TaskKey 'demo:common-archive-race' `
                -ExpectedRevision $common.Revision -Changes ([ordered]@{Lifecycle='Archived'}) `
                -OperationId 'concurrent-common-archive' -Actor 'writer-b' `
                -Reason 'archive empty common while branch restore is not indexed' | Out-Null
        }
        finally {
            Remove-Item -LiteralPath $block -Force -ErrorAction SilentlyContinue
        }
        $restoreResult = Receive-Job -Job $restoreJob -Wait -AutoRemoveJob -ErrorAction Stop
        $restoreResult.Indexed | Should -BeTrue
        $finalCommon = Get-GitHandoffCommon -Adapter $b -TaskKey 'demo:common-archive-race'
        $finalCommon.Fields.Lifecycle | Should -Be 'Active'
        $finalCommon.ActiveBranches | Should -Contain 'thread:A'
    }

    It 'InterT100_blocks_common_archival_while_a_peer_is_still_indexed_active' {
        $root = Join-Path $TestDrive 'common-protection'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-10' -Fields $script:InitialCommon -OperationId 'create-common-10' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-10' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-ten' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-10'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-10' -ExpectedRevision $common.Revision -Changes ([ordered]@{Lifecycle='Archived'}) -OperationId 'premature-common-archive' -Reason 'explicit close after recorded state' } | Should -Throw
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-10').Fields.Lifecycle | Should -Be 'Active'
        Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-10' -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-ten' | Out-Null
        $ready = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-10'
        Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-10' -ExpectedRevision $ready.Revision -Changes ([ordered]@{Lifecycle='Archived'}) -OperationId 'safe-common-archive' -SuppressActivity -Reason 'all peers archived and index read back' | Out-Null
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-10').Fields.Lifecycle | Should -Be 'Archived'
    }

    It 'InterT110_reconciles_the_common_index_event_when_its_record_was_already_committed' {
        $root = Join-Path $TestDrive 'index-event-retry'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-11' -Fields $script:InitialCommon -OperationId 'create-common-11' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-eleven' | Out-Null
        Add-SelectiveRejectHook -RemoteRoot $remote
        $indexFlag = Join-Path $remote 'deny-index'
        Set-Content -LiteralPath $indexFlag -Value 'synthetic common index failure'
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'archive-eleven' } | Should -Throw
        Remove-Item -LiteralPath $indexFlag
        $flag = Join-Path $remote 'deny-events'
        Set-Content -LiteralPath $flag -Value 'synthetic index event failure'
        { Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'archive-eleven' } | Should -Throw
        $indexCommit = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-11').Revision
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-11').ActiveBranches).Count | Should -Be 0
        Remove-Item -LiteralPath $flag
        $retried = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-eleven'
        $retried.Indexed | Should -BeFalse
        @($retried.IndexOperationIds).Count | Should -Be 1
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-11' -RecordKind common `
            -OperationId $retried.IndexOperationIds[0] -Field 'Active Branches'
        $event.ReadbackResult | Should -Be 'verified'
        $event.RecordRevision | Should -Be $indexCommit
    }

    It 'InterT120_records_the_supplied_actor_reason_and_branch_integration_status' {
        $root = Join-Path $TestDrive 'event-provenance'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-12' -Fields $script:InitialCommon -OperationId 'create-common-12' | Out-Null
        $branchFields = [ordered]@{
            Current = $script:InitialBranch.Current
            Source = [ordered]@{revision='r2';environment='fixture';evidence=@('check-1','check-2')}
            Lifecycle = 'Active'
            'Work State' = 'Running'
        }
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $branchFields -OperationId 'fork-twelve' | Out-Null
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-12' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Work State'='Awaiting Review'}) -OperationId 'review-without-reason' } | Should -Throw
        Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Work State'='Awaiting Review'}) -OperationId 'review-twelve' -Actor 'agent:writer-a' -Reason 'specific tests passed; user review pending' | Out-Null
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -RecordKind branch -OperationId 'review-twelve' -Field 'Work State'
        $event.Actor | Should -Be 'agent:writer-a'
        $event.Reason | Should -Be 'specific tests passed; user review pending'
        $event.IntegrationStatus | Should -Be 'branch-only'
        $event.PreviousState | Should -Be 'Running'
        $event.NewState | Should -Be 'Awaiting Review'
        $event.Source.revision | Should -Be 'r2'
        $event.Source.environment | Should -Be 'fixture'
        @($event.Source.evidence) | Should -Be @('check-1','check-2')
    }

    # Scenario: One actor archives a branch and the adapter mutates both the branch and common index.
    # Purpose: Preserve the same display Actor label across the complete lifecycle operation.
    It 'InterT125_forwards_the_lifecycle_actor_to_the_common_index_event' {
        $root = Join-Path $TestDrive 'q125'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:index-actor' -Fields $script:InitialCommon `
            -OperationId 'create-index-actor-common' -Actor 'writer-a' | Out-Null
        New-TestGitHandoffBranch -Adapter $a -TaskKey 'demo:index-actor' -BranchId 'thread:A' `
            -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'create-index-actor-branch' `
            -Actor 'writer-a' | Out-Null
        $result = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:index-actor' -BranchId 'thread:A' `
            -Lifecycle Archived -OperationId 'archive-with-actor' -Actor 'agent:writer-a' `
            -Reason 'archive after verified branch integration'
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:index-actor' -RecordKind common `
            -OperationId $result.IndexOperationIds[0] -Field 'Active Branches'
        $event.Actor | Should -Be 'agent:writer-a'
    }

    # Scenario: A configured remote refuses the create-only record ref while it remains absent.
    # Purpose: A storage capacity/permission failure must not claim a peer revision conflict.
    It 'InterT130_reports_unverified_create_write_without_false_revision_conflict' {
        $root = Join-Path $TestDrive 'rejected-record-create'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-records'
        Set-Content -LiteralPath $flag -Value 'synthetic create ref refusal'
        $message = $null
        try { New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-13' -Fields $script:InitialCommon -OperationId 'create-thirteen' | Out-Null }
        catch { $message = [string]$_.Exception.Message }
        $message | Should -Match 'selected Git Handoff storage write was not verified'
        $message | Should -Not -Match 'revision conflict'
        (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-13') | Should -BeNullOrEmpty
        Remove-Item -LiteralPath $flag
        $recovered = New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-13' -Fields $script:InitialCommon -OperationId 'create-thirteen'
        $recovered.Status | Should -Be 'created'
    }

    # Scenario: A Windows bare remote cannot create a long loose ref lock under the adopter's chosen prefix.
    # Purpose: Give a concrete path-capacity error and preserve the same operation for a configured retry.
    It 'InterT140_reports_windows_ref_path_failure_then_recovers_after_opt_in_git_configuration' -Skip:(-not $IsWindows) {
        $root = Join-Path $TestDrive 'windows-long-ref'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        $prefix = 'refs/heads/handoff-v1/' + ('x' * 200)
        $long = New-GitHandoffAdapter -RepositoryRoot $a.RepositoryRoot -RefPrefix $prefix `
            -AuthorityScope $a.AuthorityScope -GetVerifiedPrincipal $a.GetVerifiedPrincipal -Authorize $a.Authorize
        $message = $null
        try { New-GitHandoffCommon -Adapter $long -TaskKey 'demo:ABC-14' -Fields $script:InitialCommon -OperationId 'create-fourteen' | Out-Null }
        catch { $message = [string]$_.Exception.Message }
        $message | Should -Match 'Git Handoff ref path or directory is unavailable'
        $message | Should -Not -Match 'revision conflict'
        (Get-GitHandoffCommon -Adapter $long -TaskKey 'demo:ABC-14') | Should -BeNullOrEmpty
        & git -C $remote config core.longpaths true
        & git -C $a.RepositoryRoot config core.longpaths true
        $recovered = New-GitHandoffCommon -Adapter $long -TaskKey 'demo:ABC-14' -Fields $script:InitialCommon -OperationId 'create-fourteen'
        $recovered.Status | Should -Be 'created'
        (Get-GitHandoffCommon -Adapter $long -TaskKey 'demo:ABC-14').Revision | Should -Be $recovered.Revision
    }
}
