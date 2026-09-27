# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Handoff receive and record core' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../skills/manage-task-handoff/scripts/HandoffRecordCore.psm1') -Force
        function New-TestCommon {
            return @{ 'Authority Scope'='scope-a'; 'Task Key'='task-1'; Intent='finish'; Scope='test'; Current='same'; Source='caller'; Lifecycle='Active'; 'Work State'='Running' }
        }
        function New-TestBranch {
            return @{ 'Authority Scope'='scope-a'; 'Task Key'='task-1'; 'Branch ID'='branch-a'; 'Fork Point'='base'; 'Continuation Generation'=0; Current='same'; Source='caller'; Lifecycle='Active'; 'Work State'='Running' }
        }
    }

    It 'accepts two caller-supplied source shapes through the same interface without external metadata or calls' {
        foreach ($source in @(
            @{ Kind = 'issue'; Key = 'ABC-1' },
            @{ Kind = 'conversation'; Key = 'thread-42' }
        )) {
            $record = [pscustomobject]@{
                'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; 'Branch ID' = 'branch-a'
                'Fork Point' = 'base-1'; 'Continuation Generation' = 0
                Current = 'checked'; Source = $source; Lifecycle = 'Active'; 'Work State' = 'Running'
            }
            $actual = Invoke-HandoffRecordCore -Kind Branch -Record $record -OperationId 'op-1'
            $actual.Status | Should -Be 'Accepted'
            $actual.Record.Source.Key | Should -Be $source.Key
            $actual.ExternalCalls | Should -Be 0
            $actual.Durable | Should -BeFalse
            $actual.Events.Count | Should -BeGreaterThan 0
        }
    }

    It 'rejects malformed input before producing a record or event' {
        $record = [pscustomobject]@{ 'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; Current = 'x' }
        $actual = Invoke-HandoffRecordCore -Kind Branch -Record $record -OperationId 'op-1'
        $actual.Status | Should -Be 'Rejected'
        $actual.Reason | Should -Be 'missing-required-field'
        $actual.Record | Should -BeNullOrEmpty
        $actual.Events.Count | Should -Be 0
        $actual.ExternalCalls | Should -Be 0
        $sensitive = [pscustomobject]@{
            'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; Intent = 'finish'; Scope = 'local'
            Current = @{ credential = 'fixture-value' }; Source = 'caller'; Lifecycle = 'Active'; 'Work State' = 'Running'
        }
        $secretResult = Invoke-HandoffRecordCore -Kind Common -Record $sensitive -OperationId 'op-2'
        $secretResult.Reason | Should -Be 'sensitive-field'
        $secretResult.Record | Should -BeNullOrEmpty
    }

    It 'rejects executable properties in caller data without evaluating them' {
        $script:probeCalls = 0
        $record = [pscustomobject]@{
            'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; Intent = 'finish'; Scope = 'local'
            Current = 'checked'; Source = 'caller'; Lifecycle = 'Active'; 'Work State' = 'Running'
        }
        $record | Add-Member -MemberType ScriptProperty -Name Probe -Value { $script:probeCalls++; 'unsafe' }
        $actual = Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'op-1'
        $actual.Status | Should -Be 'Rejected'
        $actual.Reason | Should -Be 'invalid-input-shape'
        $script:probeCalls | Should -Be 0
        $actual.ExternalCalls | Should -Be 0
    }

    It 'rejects duplicate identity and stale revision without touching another branch' {
        $record = [pscustomobject]@{
            'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; 'Branch ID' = 'branch-a'
            'Fork Point' = 'base-1'; 'Continuation Generation' = 0
            Current = 'new'; Source = 'test'; Lifecycle = 'Active'; 'Work State' = 'Running'
        }
        $other = [pscustomobject]@{ 'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; 'Branch ID' = 'branch-b'; Revision = 'r2'; Current = 'other' }
        $duplicate = Invoke-HandoffRecordCore -Kind Branch -Record $record -OperationId 'op-1' -ExistingRecords @($record, $record)
        $duplicate.Reason | Should -Be 'duplicate-identity'
        $stale = Invoke-HandoffRecordCore -Kind Branch -Record $record -OperationId 'op-1' -ExistingRecords @($other, ([pscustomobject]@{ 'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; 'Branch ID' = 'branch-a'; Revision = 'r2'; Current = 'old' })) -ExpectedRevision 'r1'
        $stale.Reason | Should -Be 'revision-conflict'
        $other.Current | Should -Be 'other'
        $stale.ExternalCalls | Should -Be 0
        $wrongParent = [pscustomobject]@{ 'Authority Scope' = 'scope-b'; 'Task Key' = 'task-1' }
        $association = Invoke-HandoffRecordCore -Kind Branch -Record $record -OperationId 'op-1' -ParentRecord $wrongParent
        $association.Reason | Should -Be 'invalid-association'
        $association.Events.Count | Should -Be 0
    }

    It 'records caller outcomes without claiming a durable external save' {
        $record = [pscustomobject]@{
            'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; Intent = 'finish'; Scope = 'local'
            Current = 'candidate'; Source = 'caller'; Lifecycle = 'Active'; 'Work State' = 'Awaiting Review'
        }
        foreach ($outcome in @('denied', 'partial', 'unknown', 'readback-mismatch', 'readback-matched')) {
            $peer = [pscustomobject]@{ 'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; 'Branch ID' = 'branch-a'; Revision = 'r1' }
            $actual = Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'op-1' -ExistingRecords @($peer) -CallerResult ([pscustomobject]@{ Status = $outcome })
            $actual.Status | Should -Be 'Accepted'
            $actual.CallerOutcome | Should -Be $outcome
            $actual.Durable | Should -BeFalse
            $actual.ExternalCalls | Should -Be 0
        }
    }

    It 'emits optional field additions, changes and removals, but no unchanged events' {
        $old = New-TestCommon; $old.Revision = 'r1'; $old['Keep Active Until'] = '2026-09-28'
        $new = New-TestCommon; $new['Keep Active Until'] = '2026-09-29'; $new.Conflict = 'Conflict'
        $actual = Invoke-HandoffRecordCore -Kind Common -Record $new -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-optional'
        $actual.Status | Should -Be 'Accepted'
        @($actual.Events | Where-Object Field -eq 'Keep Active Until').Count | Should -Be 1
        @($actual.Events | Where-Object Field -eq 'Conflict').Count | Should -Be 1
        @($actual.Events | Where-Object Field -eq 'Current').Count | Should -Be 0
        @($actual.Events | Where-Object { $_.'Operation ID' -cne 'op-optional' -or $_.Status -cne 'proposed' }).Count | Should -Be 0
        $unchanged = New-TestCommon; $unchanged['Keep Active Until'] = '2026-09-28'
        $sameResult = Invoke-HandoffRecordCore -Kind Common -Record $unchanged -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-same'
        $sameResult.Events.Count | Should -Be 0
        $removed = New-TestCommon
        $removedResult = Invoke-HandoffRecordCore -Kind Common -Record $removed -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-remove'
        @($removedResult.Events | Where-Object { $_.Field -eq 'Keep Active Until' -and $null -eq $_.'New State' }).Count | Should -Be 1
        $branchOld = New-TestBranch; $branchOld.Revision = 'r2'; $branchOld['Candidate Conclusion'] = 'prior'
        $branchNew = New-TestBranch; $branchNew['Candidate Conclusion'] = 'next'
        $branchResult = Invoke-HandoffRecordCore -Kind Branch -Record $branchNew -ExistingRecords @($branchOld) -ExpectedRevision 'r2' -OperationId 'op-branch'
        @($branchResult.Events | Where-Object Field -eq 'Candidate Conclusion').Count | Should -Be 1
        $branchNew['Continuation Generation'] = 1
        $generationResult = Invoke-HandoffRecordCore -Kind Branch -Record $branchNew -ExistingRecords @($branchOld) -ExpectedRevision 'r2' -OperationId 'op-generation'
        @($generationResult.Events | Where-Object Field -eq 'Continuation Generation').Count | Should -Be 1
    }

    It 'rejects non-string or malformed identities in record, parent and existing records' {
        $record = New-TestBranch; $record['Authority Scope'] = @{ id='scope-a' }
        $parent = New-TestCommon; $parent['Authority Scope'] = @{ id='different' }
        $invalid = Invoke-HandoffRecordCore -Kind Branch -Record $record -ParentRecord $parent -OperationId 'op-identity'
        $invalid.Status | Should -Be 'Rejected'
        $invalid.Record | Should -BeNullOrEmpty
        $invalid.Events.Count | Should -Be 0
        $record = New-TestBranch
        $parent['Authority Scope'] = 'scope-a'; $parent['Task Key'] = @('task-1')
        (Invoke-HandoffRecordCore -Kind Branch -Record $record -ParentRecord $parent -OperationId 'op-parent').Status | Should -Be 'Rejected'
        $existing = New-TestBranch; $existing['Branch ID'] = @{ id='branch-a' }
        (Invoke-HandoffRecordCore -Kind Branch -Record $record -ExistingRecords @($existing) -OperationId 'op-existing').Status | Should -Be 'Rejected'
        $existing['Branch ID'] = ''
        (Invoke-HandoffRecordCore -Kind Branch -Record $record -ExistingRecords @($existing) -OperationId 'op-empty-existing').Status | Should -Be 'Rejected'
        $record['Branch ID'] = '  '
        (Invoke-HandoffRecordCore -Kind Branch -Record $record -OperationId 'op-empty').Status | Should -Be 'Rejected'
    }

    It 'rejects normalized sensitive keys at any nesting level without echoing values' {
        foreach ($key in @('client_secret','Access-Token','authorization','verificationCode','PAYMENT_AUTHORIZATION')) {
            $record = New-TestCommon; $record.Current = @{ nested = @([pscustomobject]@{ $key = 'fixture-only-value' }) }
            $actual = Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'op-sensitive'
            $actual.Reason | Should -Be 'sensitive-field'
            $actual.Record | Should -BeNullOrEmpty
            $actual.Events.Count | Should -Be 0
            ($actual | ConvertTo-Json -Depth 20) | Should -Not -Match 'fixture-only-value'
        }
        $safe = New-TestCommon; $safe.Current = @{ nested = @([pscustomobject]@{ title = 'ordinary data' }) }
        (Invoke-HandoffRecordCore -Kind Common -Record $safe -OperationId 'op-safe').Status | Should -Be 'Accepted'
        $old = New-TestCommon; $old.Revision = 'r1'; $old.Current = @{ client_secret = 'fixture-only-value' }
        $safeResult = Invoke-HandoffRecordCore -Kind Common -Record $safe -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-old-sensitive'
        $safeResult.Reason | Should -Be 'sensitive-field'
        ($safeResult | ConvertTo-Json -Depth 20) | Should -Not -Match 'fixture-only-value'
        $deep = New-TestCommon; $deep.Current = @{}
        $cursor = $deep.Current
        for ($i = 0; $i -lt 18; $i++) { $cursor.next = @{}; $cursor = $cursor.next }
        (Invoke-HandoffRecordCore -Kind Common -Record $deep -OperationId 'op-deep').Reason | Should -Be 'invalid-input-shape'
    }

    It 'enforces optional enums and record-kind fields while accepting an unset branch outcome' {
        $branch = New-TestBranch
        (Invoke-HandoffRecordCore -Kind Branch -Record $branch -OperationId 'op-unset').Status | Should -Be 'Accepted'
        foreach ($value in @('Selected','Partially Selected','Superseded')) {
            $branch['Branch Outcome'] = $value
            (Invoke-HandoffRecordCore -Kind Branch -Record $branch -OperationId 'op-valid').Status | Should -Be 'Accepted'
        }
        foreach ($value in @('Completed','Rejected')) {
            $branch['Branch Outcome'] = $value
            (Invoke-HandoffRecordCore -Kind Branch -Record $branch -OperationId 'op-invalid').Status | Should -Be 'Rejected'
        }
        $branch['Branch Outcome'] = @('Selected')
        (Invoke-HandoffRecordCore -Kind Branch -Record $branch -OperationId 'op-array-outcome').Status | Should -Be 'Rejected'
        $common = New-TestCommon; $common['Branch Outcome'] = 'Selected'
        (Invoke-HandoffRecordCore -Kind Common -Record $common -OperationId 'op-kind').Status | Should -Be 'Rejected'
        $common.Remove('Branch Outcome'); $common.Conflict = 'Resolved'
        (Invoke-HandoffRecordCore -Kind Common -Record $common -OperationId 'op-conflict').Status | Should -Be 'Rejected'
    }
}
