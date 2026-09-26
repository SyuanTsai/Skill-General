# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Handoff receive and record core' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../skills/manage-task-handoff/scripts/HandoffRecordCore.psm1') -Force
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
}
