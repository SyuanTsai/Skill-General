# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Optional Git-ref Task Handoff adapter' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:Root 'skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1') -Force -ErrorAction Stop

        function New-WriterFixture {
            param([string] $Root, [string] $WriterId)
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
            return New-GitHandoffAdapter -RepositoryRoot $local -RemoteName origin
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

    # A and B share one Task Key and fork point; their own Current values and common Active index must stay separate.
    It 'InterT30_keeps_forked_peer_branches_and_common_index_distinct' {
        $root = Join-Path $TestDrive 'peer-branches'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $b = New-WriterFixture -Root $root -WriterId 'writer-b'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3' -Fields $script:InitialCommon -OperationId 'create-common-3' | Out-Null
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-3' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-a' | Out-Null
        New-GitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-3' -BranchId 'thread:B' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-b' | Out-Null
        $readA = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-3' -BranchId 'thread:A'
        $readB = Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-3' -BranchId 'thread:B'
        Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-3' -BranchId 'thread:A' -ExpectedRevision $readA.Revision -Changes ([ordered]@{Current='A tested version 1'}) -OperationId 'branch-a-update' | Out-Null
        Set-GitHandoffFields -Adapter $b -RecordKind branch -TaskKey 'demo:ABC-3' -BranchId 'thread:B' -ExpectedRevision $readB.Revision -Changes ([ordered]@{Current='B tested version 2'}) -OperationId 'branch-b-update' | Out-Null
        (Get-GitHandoffBranch -Adapter $b -TaskKey 'demo:ABC-3' -BranchId 'thread:A').Fields.Current | Should -Be 'A tested version 1'
        (Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-3' -BranchId 'thread:B').Fields.Current | Should -Be 'B tested version 2'
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-3').ActiveBranches | Sort-Object) | Should -Be @('thread:A','thread:B')
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
        Remove-Item -LiteralPath $flag
        $retried = New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-5' -Fields $script:InitialCommon -OperationId 'create-common-5'
        $retried.Revision | Should -Be $committed.Revision
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-5' -RecordKind common -OperationId 'create-common-5' -Field 'Current').ReadbackResult | Should -Be 'verified'
    }

    # A branch exists but an index push fails. Its exact Branch ID remains recoverable before Task Key-only lookup works.
    It 'InterT60_reconciles_a_durable_branch_after_common_index_failure' {
        $root = Join-Path $TestDrive 'index-rejection'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6' -Fields $script:InitialCommon -OperationId 'create-common-6' | Out-Null
        $commonBefore = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6'
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-index'
        Set-Content -LiteralPath $flag -Value 'synthetic common index failure'
        { New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-6' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-six' } | Should -Throw
        $branchBefore = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-6' -BranchId 'thread:A'
        $branchBefore.Revision | Should -Not -BeNullOrEmpty
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-6').ActiveBranches).Count | Should -Be 0
        Remove-Item -LiteralPath $flag
        $repaired = New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-6' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-six'
        $repaired.Indexed | Should -BeTrue
        $repaired.BranchRevision | Should -Be $branchBefore.Revision
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
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-8' -Fields $script:InitialCommon -OperationId 'create-common-8' | Out-Null
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-8'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-8' -ExpectedRevision $common.Revision -Changes ([ordered]@{'Work State'='Completed'}) -OperationId 'bad-workstate' } | Should -Throw
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-8' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-eight' | Out-Null
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-8' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-8' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Branch Outcome'='Selected'}) -OperationId 'no-decision' } | Should -Throw
    }

    It 'InterT90_repairs_an_archived_branch_index_and_restores_only_the_exact_peer' {
        $root = Join-Path $TestDrive 'archive-retry'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        $remote = Join-Path $root 'remote.git'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-9' -Fields $script:InitialCommon -OperationId 'create-common-9' | Out-Null
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-nine-a' | Out-Null
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-9' -BranchId 'thread:B' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-nine-b' | Out-Null
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

    It 'InterT100_blocks_common_archival_while_a_peer_is_still_indexed_active' {
        $root = Join-Path $TestDrive 'common-protection'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-10' -Fields $script:InitialCommon -OperationId 'create-common-10' | Out-Null
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-10' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-ten' | Out-Null
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
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-eleven' | Out-Null
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A'
        Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-11' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{Lifecycle='Archived'}) -OperationId 'archive-eleven' -SuppressActivity -Reason 'explicit branch archival after common checkpoint' | Out-Null
        Add-SelectiveRejectHook -RemoteRoot $remote
        $flag = Join-Path $remote 'deny-events'
        Set-Content -LiteralPath $flag -Value 'synthetic index event failure'
        $common = Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-11'
        { Set-GitHandoffFields -Adapter $a -RecordKind common -TaskKey 'demo:ABC-11' -ExpectedRevision $common.Revision -Changes ([ordered]@{'Active Branches'=@()}) -OperationId 'archive-eleven:index' -SuppressActivity } | Should -Throw
        $indexCommit = (Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-11').Revision
        @((Get-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-11').ActiveBranches).Count | Should -Be 0
        (Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-11' -RecordKind common -OperationId 'archive-eleven:index' -Field 'Active Branches') | Should -BeNullOrEmpty
        Remove-Item -LiteralPath $flag
        $retried = Set-GitHandoffBranchLifecycle -Adapter $a -TaskKey 'demo:ABC-11' -BranchId 'thread:A' -Lifecycle Archived -OperationId 'archive-eleven'
        $retried.Indexed | Should -BeFalse
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-11' -RecordKind common -OperationId 'archive-eleven:index' -Field 'Active Branches'
        $event.ReadbackResult | Should -Be 'verified'
        $event.RecordRevision | Should -Be $indexCommit
    }

    It 'InterT120_records_the_supplied_actor_reason_and_branch_integration_status' {
        $root = Join-Path $TestDrive 'event-provenance'
        [void](New-Item -ItemType Directory -Path $root)
        $a = New-WriterFixture -Root $root -WriterId 'writer-a'
        New-GitHandoffCommon -Adapter $a -TaskKey 'demo:ABC-12' -Fields $script:InitialCommon -OperationId 'create-common-12' | Out-Null
        New-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -ForkPoint 'shared-r1' -Fields $script:InitialBranch -OperationId 'fork-twelve' | Out-Null
        $branch = Get-GitHandoffBranch -Adapter $a -TaskKey 'demo:ABC-12' -BranchId 'thread:A'
        { Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Work State'='Awaiting Review'}) -OperationId 'review-without-reason' } | Should -Throw
        Set-GitHandoffFields -Adapter $a -RecordKind branch -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -ExpectedRevision $branch.Revision -Changes ([ordered]@{'Work State'='Awaiting Review'}) -OperationId 'review-twelve' -Actor 'agent:writer-a' -Reason 'specific tests passed; user review pending' | Out-Null
        $event = Get-GitHandoffEvent -Adapter $a -TaskKey 'demo:ABC-12' -BranchId 'thread:A' -RecordKind branch -OperationId 'review-twelve' -Field 'Work State'
        $event.Actor | Should -Be 'agent:writer-a'
        $event.Reason | Should -Be 'specific tests passed; user review pending'
        $event.IntegrationStatus | Should -Be 'branch-only'
        $event.PreviousState | Should -Be 'Running'
        $event.NewState | Should -Be 'Awaiting Review'
        $event.Source | Should -Be $script:InitialBranch.Source
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
        $long = New-GitHandoffAdapter -RepositoryRoot $a.RepositoryRoot -RefPrefix $prefix
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
