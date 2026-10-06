# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Handoff receive and record core' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../skills/manage-task-handoff/scripts/HandoffRecordCore.psm1') -Force
        . (Join-Path $PSScriptRoot 'helpers/ProviderAgnosticMemoryTargetAdapter.ps1')
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

    It 'CoreT12 crosses caller resource and optional memory target without authorizing content I/O' {
        $target = [pscustomobject]@{
            targetId = 'memory-fixture'; selectionScope = 'task'; resource = 'fixture-store'; location = 'entry-1'
        }
        $binding = [pscustomobject]@{
            targetId = 'memory-fixture'; selectionScope = 'task'; resource = 'fixture-store'; location = 'entry-1'
            adapterId = 'fixture-adapter'
        }
        foreach ($sourceResourceSelected in @($false, $true)) {
            foreach ($memoryTargetSelected in @($false, $true)) {
                $source = if ($sourceResourceSelected) {
                    [pscustomobject]@{ Kind = 'external-resource'; Key = 'resource-42' }
                } else { 'caller' }
                $record = [pscustomobject]@{
                    'Authority Scope' = 'scope-a'; 'Task Key' = 'task-1'; Intent = 'finish'; Scope = 'test'
                    Current = 'candidate'; Source = $source; Lifecycle = 'Active'; 'Work State' = 'Running'
                }
                $callerStatus = if ($memoryTargetSelected) { 'denied' } else { 'unknown' }
                $actual = Invoke-HandoffRecordCore -Kind Common -Record $record `
                    -OperationId "op-$sourceResourceSelected-$memoryTargetSelected" `
                    -CallerResult ([pscustomobject]@{ Status = $callerStatus })
                $case = "source=$sourceResourceSelected target=$memoryTargetSelected"
                $actual.Status | Should -Be 'Accepted' -Because $case
                $actual.CallerOutcome | Should -Be $callerStatus -Because $case
                $actual.ExternalCalls | Should -Be 0 -Because $case
                $actual.Durable | Should -BeFalse -Because $case
                @($actual.Events | Where-Object Status -cne 'proposed').Count | Should -Be 0 -Because $case
                if ($sourceResourceSelected) {
                    $actual.Record.Source.Key | Should -Be 'resource-42' -Because $case
                } else {
                    $actual.Record.Source | Should -Be 'caller' -Because $case
                }

                $adapter = New-ProviderAgnosticMemoryAdapterDouble -Spec ([pscustomobject]@{
                    adapterId = 'fixture-adapter'
                })
                if ($memoryTargetSelected) {
                    $selection = Invoke-ProviderAgnosticMemoryTargetSelection -Target $target `
                        -Bindings @($binding) -Adapters @($adapter) -Content $actual.Record
                    $selection.SelectionStatus | Should -Be 'selected' -Because $case
                    $selection.SelectedAdapterId | Should -Be 'fixture-adapter' -Because $case
                    @($selection.Calls) | Should -Be @('selection') -Because $case
                    $selection.Durable | Should -BeFalse -Because $case
                    $selection.ContentRead | Should -BeFalse -Because $case
                    $selection.ContentWrite | Should -BeFalse -Because $case
                    $adapter.ActivationRequirementsInspected | Should -BeFalse -Because $case
                    $adapter.CapabilityInspected | Should -BeFalse -Because $case
                } else {
                    @($adapter.Calls).Count | Should -Be 0 -Because $case
                }
            }
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

    It 'CoreT41 reports <Operation> <Outcome> without promoting caller evidence' -ForEach @(
        foreach ($operation in @('rollback', 'disable', 'updateIfRevision')) {
            foreach ($outcome in @('readback-matched', 'denied', 'unavailable', 'partial', 'unknown', 'readback-mismatch')) {
                @{ Operation = $operation; Outcome = $outcome }
            }
        }
    ) {
        $report = @{
            SchemaVersion = 1; Operation = $Operation; OperationId = 'report-op'; Status = $Outcome
            Capability = 'supported'; Identity = 'verified'; Permission = 'authorized'
            AdapterVersion = 'fixture-v1'; Revision = 'r1'; Readback = 'not-attempted'; ReadbackRevision = $null
            Retryable = $false; PendingActions = @()
        }
        switch ($Outcome) {
            'readback-matched' { $report.Readback = 'matched'; $report.ReadbackRevision = 'r1' }
            'denied' { $report.Permission = 'denied' }
            'unavailable' { $report.Capability = 'unavailable'; $report.AdapterVersion = $null; $report.Revision = $null }
            'partial' { $report.Retryable = $true; $report.PendingActions = @('reconcile-event', 'readback') }
            'unknown' { $report.Retryable = $true; $report.PendingActions = @('reconcile-same-operation'); $report.Readback = 'unknown' }
            'readback-mismatch' { $report.Retryable = $true; $report.PendingActions = @('readback'); $report.Readback = 'mismatch'; $report.ReadbackRevision = 'r2' }
        }
        $record = New-TestCommon
        $record.Lifecycle = 'Archived'
        $actual = Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'report-op' -CallerResult $report
        $actual.Status | Should -Be 'Accepted'
        $actual.CallerOutcome | Should -Be $Outcome
        $actual.CallerResult.Operation | Should -Be $Operation
        $actual.CallerResult.OperationId | Should -Be 'report-op'
        $actual.CallerResult.AdapterVersion | Should -Be $report.AdapterVersion
        $actual.CallerResult.Revision | Should -Be $report.Revision
        $actual.CallerResult.Readback | Should -Be $report.Readback
        $actual.CallerResult.ReadbackRevision | Should -Be $report.ReadbackRevision
        $actual.CallerResult.Capability | Should -Be $report.Capability
        $actual.CallerResult.Identity | Should -Be $report.Identity
        $actual.CallerResult.Permission | Should -Be $report.Permission
        $actual.CallerResult.Retryable | Should -Be $report.Retryable
        ($actual.CallerResult.PendingActions -is [array]) | Should -BeTrue
        @($actual.CallerResult.PendingActions) | Should -Be @($report.PendingActions)
        @($actual.Events | Where-Object Status -cne 'proposed').Count | Should -Be 0
        $actual.ExternalCalls | Should -Be 0
        $actual.Durable | Should -BeFalse
    }

    It 'CoreT42 rejects contradictory or malformed result <Field>=<Value>' -ForEach @(
        @{Field='SchemaVersion';Value=2}, @{Field='SchemaVersion';Value='1'},
        @{Field='Operation';Value='automatic-fallback'}, @{Field='OperationId';Value='another-op'},
        @{Field='Capability';Value='unknown'}, @{Field='Identity';Value='denied'},
        @{Field='Permission';Value='unknown'}, @{Field='AdapterVersion';Value=$null},
        @{Field='Revision';Value=$null}, @{Field='Readback';Value='mismatch'},
        @{Field='ReadbackRevision';Value='different'}, @{Field='Retryable';Value='false'},
        @{Field='PendingActions';Value=@('unfinished')}, @{Field='Status';Value='durable'}
    ) {
        $report = @{
            SchemaVersion=1; Operation='rollback'; OperationId='report-op'; Status='readback-matched'
            Capability='supported'; Identity='verified'; Permission='authorized'
            AdapterVersion='fixture-v1'; Revision='r1'; Readback='matched'; ReadbackRevision='r1'
            Retryable=$false; PendingActions=@()
        }
        $report[$Field] = $Value
        $actual = Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $report
        $actual.Status | Should -Be 'Rejected'
        $actual.Reason | Should -Be 'invalid-caller-result'
        $actual.Record | Should -BeNullOrEmpty
        $actual.Events.Count | Should -Be 0
        $actual.ExternalCalls | Should -Be 0
        $actual.Durable | Should -BeFalse
    }

    It 'CoreT43 preserves retry state and rejects incomplete versioned reports' {
        $report = @{
            SchemaVersion=1; Operation='disable'; OperationId='report-op'; Status='unknown'
            Capability='unknown'; Identity='unknown'; Permission='unknown'
            AdapterVersion=$null; Revision=$null; Readback='unknown'; ReadbackRevision=$null
            Retryable=$true; PendingActions=@('reconcile-same-operation')
        }
        $actual = Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $report
        $actual.Status | Should -Be 'Accepted'
        $actual.CallerResult.PendingActions | Should -Contain 'reconcile-same-operation'
        foreach ($field in @($report.Keys)) {
            $incomplete = $report.Clone(); $incomplete.Remove($field)
            $rejected = Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $incomplete
            $rejected.Reason | Should -Be 'invalid-caller-result' -Because "missing $field"
        }
        foreach ($status in @('partial','unknown')) {
            $incomplete = $report.Clone(); $incomplete.Status=$status; $incomplete.PendingActions=@()
            (Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $incomplete).Reason |
                Should -Be 'invalid-caller-result'
        }
    }

    It 'CoreT44 retains <Failure> recovery evidence until matching readback' -ForEach @(
        @{Failure='branch-created-unindexed';Kind='Branch';Lifecycle='Active';Outcome='partial';Pending='index-branch-a';Operation='createIfAbsent'},
        @{Failure='archived-index-retained';Kind='Branch';Lifecycle='Archived';Outcome='partial';Pending='remove-index-branch-a';Operation='updateIfRevision'},
        @{Failure='common-readback-failed';Kind='Common';Lifecycle='Active';Outcome='unknown';Pending='common-readback';Operation='readback'}
    ) {
        $record = if ($Kind -ceq 'Branch') { New-TestBranch } else { New-TestCommon }
        $record.Lifecycle=$Lifecycle
        $report=@{
            SchemaVersion=1;Operation=$Operation;OperationId='recover-same-op';Status=$Outcome
            Capability='supported';Identity='verified';Permission='authorized';AdapterVersion='fixture-v1'
            Revision='r1';Readback='unknown';ReadbackRevision=$null;Retryable=$true;PendingActions=@($Pending)
        }
        $peer=New-TestBranch; $peer['Branch ID']='branch-b'; $peer.Current='peer untouched'; $peer.Revision='peer-r1'
        $common=New-TestCommon
        $common['Active Branches']=if ($Failure -ceq 'branch-created-unindexed') { @('branch-b') } else { @('branch-a','branch-b') }
        $incomplete=Invoke-HandoffRecordCore -Kind $Kind -Record $record -OperationId 'recover-same-op' -CallerResult $report -ParentRecord $common
        $incomplete.Status | Should -Be 'Accepted'
        $incomplete.CallerResult.Status | Should -Be $Outcome
        $incomplete.CallerResult.PendingActions | Should -Contain $Pending
        $incomplete.CallerResult.Retryable | Should -BeTrue
        $incomplete.Durable | Should -BeFalse
        @($incomplete.Events | Where-Object Status -cne 'proposed').Count | Should -Be 0
        # The caller's incomplete index snapshot is preserved; core does no repair I/O.
        @($common['Active Branches']) | Should -Be $(if ($Failure -ceq 'branch-created-unindexed') { @('branch-b') } else { @('branch-a','branch-b') })
        $old=$record.Clone();$old.Revision='r1'
        $report.Status='readback-matched';$report.Readback='matched';$report.ReadbackRevision='r1'
        $report.Retryable=$false;$report.PendingActions=@()
        $retried=Invoke-HandoffRecordCore -Kind $Kind -Record $record -OperationId 'recover-same-op' -ExpectedRevision 'r1' -ExistingRecords @($old,$peer) -ParentRecord $common -CallerResult $report
        $retried.Status | Should -Be 'Accepted'
        $retried.CallerResult.OperationId | Should -Be $incomplete.CallerResult.OperationId
        $retried.CallerResult.PendingActions.Count | Should -Be 0
        $retried.Events.Count | Should -Be 0
        $retried.Durable | Should -BeFalse
        $retried.ExternalCalls | Should -Be 0
        $peer.Current | Should -Be 'peer untouched'
        $incomplete.CallerOutcome | Should -Be $Outcome
        $incomplete.CallerResult.Status | Should -Be $Outcome
        $incomplete.CallerResult.PendingActions | Should -Contain $Pending
        $incomplete.CallerResult.Retryable | Should -BeTrue
    }

    It 'CoreT45 accepts all operation result shapes from the declared machine contract' {
        $contract=Get-Content -Raw (Join-Path $PSScriptRoot '../skills/manage-task-handoff/references/task-handoff-contract.json') | ConvertFrom-Json
        foreach ($operation in $contract.adapterResultReport.operations) {
            $report=[pscustomobject]@{
                SchemaVersion=1;Operation=$operation;OperationId='report-op';Status='readback-matched'
                Capability='supported';Identity='verified';Permission='authorized';AdapterVersion='fixture-v1'
                Revision='r1';Readback='matched';ReadbackRevision='r1';Retryable=$false;PendingActions=@()
            }
            @($report.PSObject.Properties.Name) | Should -Be @($contract.adapterResultReport.requiredFields)
            $actual=Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $report
            $actual.Status | Should -Be 'Accepted' -Because $operation
            $actual.CallerResult.Operation | Should -Be $operation
            ($actual.CallerResult.PendingActions -is [array]) | Should -BeTrue
            (Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $actual.CallerResult).Status |
                Should -Be 'Accepted'
            $actual.Durable | Should -BeFalse
        }
    }

    It 'CoreT46 treats Source as caller-owned domain data without performing storage calls' {
        $record=New-TestCommon
        $record.Source='retired-source-id'
        $actual=Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'source-free-core' `
            -CallerResult ([pscustomobject]@{ Status='unavailable' })

        $actual.Status | Should -Be 'Accepted'
        $actual.Record.Source | Should -Be 'retired-source-id'
        $actual.CallerOutcome | Should -Be 'unavailable'
        $actual.ExternalCalls | Should -Be 0
        $actual.Durable | Should -BeFalse
    }

    It 'CoreT47 snapshots mutable caller evidence from <Shape> reports' -ForEach @(
        @{Shape='hashtable'}, @{Shape='PSCustomObject'}
    ) {
        $pending=@('index-branch-a','readback')
        $report=@{
            SchemaVersion=1;Operation='rollback';OperationId='report-op';Status='partial'
            Capability='supported';Identity='verified';Permission='authorized';AdapterVersion='fixture-v1'
            Revision='r1';Readback='unknown';ReadbackRevision=$null;Retryable=$true;PendingActions=$pending
        }
        if ($Shape -ceq 'PSCustomObject') { $report=[pscustomobject]$report }
        $actual=Invoke-HandoffRecordCore -Kind Common -Record (New-TestCommon) -OperationId 'report-op' -CallerResult $report
        $report.Status='readback-matched';$report.Revision='r2';$report.Readback='matched';$report.ReadbackRevision='r2'
        $report.Retryable=$false;$report.PendingActions=@()
        $pending[0]='rewritten by caller'
        $actual.CallerOutcome | Should -Be 'partial'
        $actual.CallerResult.Status | Should -Be 'partial'
        $actual.CallerResult.Revision | Should -Be 'r1'
        $actual.CallerResult.Readback | Should -Be 'unknown'
        $actual.CallerResult.ReadbackRevision | Should -BeNullOrEmpty
        $actual.CallerResult.Retryable | Should -BeTrue
        @($actual.CallerResult.PendingActions) | Should -Be @('index-branch-a','readback')
        $actual.CallerResult.PendingActions[1]='changed response'
        $pending[1] | Should -Be 'readback'
        $actual.ExternalCalls | Should -Be 0
        $actual.Durable | Should -BeFalse
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

    It 'keeps a branch fork point fixed and rejects a stale continuation generation' {
        $old = New-TestBranch; $old.Revision = 'r1'; $old['Continuation Generation'] = 2
        $changedFork = New-TestBranch; $changedFork['Fork Point'] = 'other-base'; $changedFork['Continuation Generation'] = 2
        $forkResult = Invoke-HandoffRecordCore -Kind Branch -Record $changedFork -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-fork'
        $forkResult.Status | Should -Be 'Rejected'
        $forkResult.Reason | Should -Be 'fork-point-conflict'
        $forkResult.Record | Should -BeNullOrEmpty
        $forkResult.Events.Count | Should -Be 0

        $stale = New-TestBranch; $stale['Continuation Generation'] = 1
        $staleResult = Invoke-HandoffRecordCore -Kind Branch -Record $stale -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-stale-generation'
        $staleResult.Status | Should -Be 'Rejected'
        $staleResult.Reason | Should -Be 'generation-conflict'
        $staleResult.Record | Should -BeNullOrEmpty
        $staleResult.Events.Count | Should -Be 0

        $skipped = New-TestBranch; $skipped['Continuation Generation'] = 4
        $skippedResult = Invoke-HandoffRecordCore -Kind Branch -Record $skipped -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-skip-generation'
        $skippedResult.Status | Should -Be 'Rejected'
        $skippedResult.Reason | Should -Be 'generation-conflict'
        $skippedResult.Events.Count | Should -Be 0

        $continued = New-TestBranch; $continued['Continuation Generation'] = 3
        $accepted = Invoke-HandoffRecordCore -Kind Branch -Record $continued -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-next-generation'
        $accepted.Status | Should -Be 'Accepted'
        @($accepted.Events | Where-Object Field -eq 'Continuation Generation').Count | Should -Be 1
    }

    It 'restores an archived branch only with an atomic next-generation continuation' {
        $old = New-TestBranch; $old.Revision = 'r1'; $old.Lifecycle = 'Archived'; $old['Continuation Generation'] = 2
        $sameGeneration = New-TestBranch; $sameGeneration['Continuation Generation'] = 2
        $withoutFence = Invoke-HandoffRecordCore -Kind Branch -Record $sameGeneration -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-restore-without-fence'
        $withoutFence.Status | Should -Be 'Rejected'
        $withoutFence.Events.Count | Should -Be 0

        $stillArchived = New-TestBranch; $stillArchived.Lifecycle = 'Archived'; $stillArchived['Continuation Generation'] = 3
        $incrementOnly = Invoke-HandoffRecordCore -Kind Branch -Record $stillArchived -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-increment-without-restore'
        $incrementOnly.Status | Should -Be 'Rejected'
        $incrementOnly.Events.Count | Should -Be 0

        $restored = New-TestBranch; $restored['Continuation Generation'] = 3
        $accepted = Invoke-HandoffRecordCore -Kind Branch -Record $restored -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-restore-with-fence'
        $accepted.Status | Should -Be 'Accepted'
        @($accepted.Events | Where-Object Field -eq 'Lifecycle').Count | Should -Be 1
        @($accepted.Events | Where-Object Field -eq 'Continuation Generation').Count | Should -Be 1
        $accepted.Durable | Should -BeFalse
        $accepted.ExternalCalls | Should -Be 0
    }

    It 'does not refresh activity for a no-op, structural index change or archive alone' {
        $old = New-TestCommon; $old.Revision = 'r1'; $old['Last Activity At'] = '2026-09-20T00:00:00Z'
        foreach ($change in @('none', 'index', 'archive')) {
            $record = New-TestCommon
            $record['Last Activity At'] = '2026-09-27T00:00:00Z'
            if ($change -eq 'index') { $record['Active Branches'] = @('branch-a') }
            if ($change -eq 'archive') { $record.Lifecycle = 'Archived' }
            $actual = Invoke-HandoffRecordCore -Kind Common -Record $record -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId "op-$change"
            $actual.Status | Should -Be 'Rejected' -Because $change
            $actual.Reason | Should -Be 'activity-refresh-without-material-change' -Because $change
            $actual.Record | Should -BeNullOrEmpty -Because $change
            $actual.Events.Count | Should -Be 0 -Because $change
        }
        $material = New-TestCommon; $material.Current = 'new progress'; $material['Last Activity At'] = '2026-09-27T00:00:00Z'
        $accepted = Invoke-HandoffRecordCore -Kind Common -Record $material -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-material'
        $accepted.Status | Should -Be 'Accepted'
        @($accepted.Events | Where-Object Field -eq 'Current').Count | Should -Be 1
        @($accepted.Events | Where-Object Field -eq 'Last Activity At').Count | Should -Be 1

        $branchOld = New-TestBranch; $branchOld.Revision = 'r2'; $branchOld['Last Activity At'] = '2026-09-20T00:00:00Z'
        $branchNoop = New-TestBranch; $branchNoop['Last Activity At'] = '2026-09-27T00:00:00Z'
        $branchRejected = Invoke-HandoffRecordCore -Kind Branch -Record $branchNoop -ExistingRecords @($branchOld) -ExpectedRevision 'r2' -OperationId 'op-branch-noop'
        $branchRejected.Reason | Should -Be 'activity-refresh-without-material-change'
        $continued = New-TestBranch; $continued['Continuation Generation'] = 1; $continued['Last Activity At'] = '2026-09-27T00:00:00Z'
        (Invoke-HandoffRecordCore -Kind Branch -Record $continued -ExistingRecords @($branchOld) -ExpectedRevision 'r2' -OperationId 'op-branch-continue').Status | Should -Be 'Accepted'

        $commonOld = New-TestCommon; $commonOld.Revision = 'r3'; $commonOld['Active Branches'] = @('branch-a'); $commonOld['Last Activity At'] = '2026-09-20T00:00:00Z'
        $commonNew = New-TestCommon; $commonNew['Active Branches'] = @('branch-a'); $commonNew['Last Activity At'] = '2026-09-27T00:00:00Z'
        $activeBranch = New-TestBranch; $activeBranch['Last Activity At'] = '2026-09-27T00:00:00Z'
        $propagated = Invoke-HandoffRecordCore -Kind Common -Record $commonNew -ExistingRecords @($commonOld, $activeBranch) -ExpectedRevision 'r3' -OperationId 'op-branch-activity'
        $propagated.Status | Should -Be 'Accepted'
        @($propagated.Events | Where-Object Field -eq 'Last Activity At').Count | Should -Be 1

        $foreign = New-TestBranch; $foreign['Task Key'] = 'other-task'; $foreign['Last Activity At'] = '2026-09-27T00:00:00Z'
        (Invoke-HandoffRecordCore -Kind Common -Record $commonNew -ExistingRecords @($commonOld, $foreign) -ExpectedRevision 'r3' -OperationId 'op-foreign').Reason | Should -Be 'activity-refresh-without-material-change'
        $foreign['Task Key'] = 'task-1'; $foreign['Authority Scope'] = 'other-scope'
        (Invoke-HandoffRecordCore -Kind Common -Record $commonNew -ExistingRecords @($commonOld, $foreign) -ExpectedRevision 'r3' -OperationId 'op-cross-scope').Reason | Should -Be 'activity-refresh-without-material-change'
        $foreign['Authority Scope'] = 'scope-a'; $foreign['Branch ID'] = 'not-indexed'
        (Invoke-HandoffRecordCore -Kind Common -Record $commonNew -ExistingRecords @($commonOld, $foreign) -ExpectedRevision 'r3' -OperationId 'op-not-indexed').Reason | Should -Be 'activity-refresh-without-material-change'
        $archived = New-TestBranch; $archived.Lifecycle = 'Archived'; $archived['Last Activity At'] = '2026-09-27T00:00:00Z'
        (Invoke-HandoffRecordCore -Kind Common -Record $commonNew -ExistingRecords @($commonOld, $archived) -ExpectedRevision 'r3' -OperationId 'op-archived').Reason | Should -Be 'activity-refresh-without-material-change'
    }

    It 'does not archive a common handoff while its active branch index is populated' {
        $record = New-TestCommon; $record.Lifecycle = 'Archived'; $record['Active Branches'] = @('branch-a')
        $actual = Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'op-archive'
        $actual.Status | Should -Be 'Rejected'
        $actual.Reason | Should -Be 'active-branch-protects-common'
        $actual.Record | Should -BeNullOrEmpty
        $actual.Events.Count | Should -Be 0

        $record['Active Branches'] = @()
        (Invoke-HandoffRecordCore -Kind Common -Record $record -OperationId 'op-empty-index').Status | Should -Be 'Accepted'
        $activePeer = New-TestBranch
        (Invoke-HandoffRecordCore -Kind Common -Record $record -ExistingRecords @($activePeer) -OperationId 'op-stale-index').Reason | Should -Be 'active-branch-protects-common'
        $activePeer.Lifecycle = 'Archived'
        (Invoke-HandoffRecordCore -Kind Common -Record $record -ExistingRecords @($activePeer) -OperationId 'op-archived-peer').Status | Should -Be 'Accepted'
    }

    It 'represents an exact archived common restore as a non-durable proposal with activity' {
        $old = New-TestCommon; $old.Revision = 'r1'; $old.Lifecycle = 'Archived'; $old['Last Activity At'] = '2026-09-20T00:00:00Z'
        $restored = New-TestCommon; $restored.Lifecycle = 'Active'; $restored['Last Activity At'] = '2026-09-27T00:00:00Z'
        $actual = Invoke-HandoffRecordCore -Kind Common -Record $restored -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-restore-proposal'
        $actual.Status | Should -Be 'Accepted'
        $actual.Durable | Should -BeFalse
        $actual.ExternalCalls | Should -Be 0
        @($actual.Events | Where-Object Field -eq 'Lifecycle').Count | Should -Be 1
        @($actual.Events | Where-Object Field -eq 'Last Activity At').Count | Should -Be 1
        @($actual.Events | Where-Object Status -cne 'proposed').Count | Should -Be 0

        $active = New-TestCommon; $active.Revision = 'r2'; $active['Last Activity At'] = '2026-09-20T00:00:00Z'
        $timestampOnly = New-TestCommon; $timestampOnly['Last Activity At'] = '2026-09-27T00:00:00Z'
        (Invoke-HandoffRecordCore -Kind Common -Record $timestampOnly -ExistingRecords @($active) -ExpectedRevision 'r2' -OperationId 'explicit-resume').Reason | Should -Be 'activity-refresh-without-material-change'
        $archivedAgain = New-TestCommon; $archivedAgain.Lifecycle = 'Archived'; $archivedAgain['Last Activity At'] = '2026-09-27T00:00:00Z'
        (Invoke-HandoffRecordCore -Kind Common -Record $archivedAgain -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'explicit-resume').Reason | Should -Be 'activity-refresh-without-material-change'
        (Invoke-HandoffRecordCore -Kind Common -Record $restored -ExistingRecords @($old) -ExpectedRevision 'stale' -OperationId 'op-stale-restore').Reason | Should -Be 'revision-conflict'
    }

    It 'compares mapping content without key order while preserving value, key case and array order' {
        $old = New-TestCommon; $old.Revision = 'r1'; $old['Last Activity At'] = '2026-09-20T00:00:00Z'
        $old.Source = [ordered]@{ document='guide'; nested=[ordered]@{ revision='r1'; flags=@('a','b') } }
        $reordered = New-TestCommon; $reordered['Last Activity At'] = '2026-09-27T00:00:00Z'
        $reordered.Source = [ordered]@{ nested=[ordered]@{ flags=@('a','b'); revision='r1' }; document='guide' }
        $noOp = Invoke-HandoffRecordCore -Kind Common -Record $reordered -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-reordered'
        $noOp.Reason | Should -Be 'activity-refresh-without-material-change'
        $noOp.Events.Count | Should -Be 0
        $reordered['Last Activity At'] = '2026-09-20T00:00:00Z'
        $same = Invoke-HandoffRecordCore -Kind Common -Record $reordered -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-same-map'
        $same.Status | Should -Be 'Accepted'
        @($same.Events | Where-Object Field -eq 'Source').Count | Should -Be 0
        $reordered.Source = [pscustomobject]@{ nested = [pscustomobject]@{ flags=@('a','b'); revision='r1' }; document='guide' }
        $objectMap = Invoke-HandoffRecordCore -Kind Common -Record $reordered -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-object-map'
        $objectMap.Status | Should -Be 'Accepted'
        @($objectMap.Events | Where-Object Field -eq 'Source').Count | Should -Be 0

        $numericOld = New-TestCommon; $numericOld.Revision = 'r2'; $numericOld.Current = @{ count = [int]1 }
        $numericNew = New-TestCommon; $numericNew.Current = @{ count = [long]1 }
        $sameJsonNumber = Invoke-HandoffRecordCore -Kind Common -Record $numericNew -ExistingRecords @($numericOld) -ExpectedRevision 'r2' -OperationId 'op-same-number'
        $sameJsonNumber.Status | Should -Be 'Accepted'
        @($sameJsonNumber.Events | Where-Object Field -eq 'Current').Count | Should -Be 0

        $changed = New-TestCommon; $changed['Last Activity At'] = '2026-09-27T00:00:00Z'
        foreach ($source in @(
            ([ordered]@{ document='guide'; nested=[ordered]@{ revision='r2'; flags=@('a','b') } }),
            ([ordered]@{ document='guide'; nested=[ordered]@{ revision='r1'; flags=@('b','a') } }),
            ([ordered]@{ Document='guide'; nested=[ordered]@{ revision='r1'; flags=@('a','b') } })
        )) {
            $changed.Source = $source
            $actual = Invoke-HandoffRecordCore -Kind Common -Record $changed -ExistingRecords @($old) -ExpectedRevision 'r1' -OperationId 'op-changed-map'
            $actual.Status | Should -Be 'Accepted'
            @($actual.Events | Where-Object Field -eq 'Source').Count | Should -Be 1
            @($actual.Events | Where-Object Field -eq 'Last Activity At').Count | Should -Be 1
        }
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
