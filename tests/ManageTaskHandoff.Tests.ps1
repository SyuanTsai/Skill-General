# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'manage-task-handoff Skill contract' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Skill = Join-Path $script:Root 'skills/manage-task-handoff'
        $script:Contract = Get-Content -Raw (Join-Path $script:Skill 'references/task-handoff-contract.json') | ConvertFrom-Json -Depth 30
        $script:Cases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-task-handoff/scenarios.json') | ConvertFrom-Json -Depth 30
    }

    # Scenario: Explicit risk, an unlisted risk, and a new conversation produce different actions.
    # Purpose: Preserve handoff checkpoints without maintenance scans or timer-only writes.
    It 'UnitT10_routes_interruption_risk_without_scanning_on_new_conversation' {
        foreach ($case in $script:Cases.routing) {
            $must = @($case.signals | Where-Object { $_ -cin @($script:Contract.routing.mustWriteSignals) }).Count -gt 0
            $risk = @($case.risk | Where-Object { $_ -cin @($script:Contract.routing.riskQuestions) }).Count -gt 0
            $skip = @($case.signals | Where-Object { $_ -cin @($script:Contract.routing.skipSignals) }).Count -gt 0
            $action = if (-not $case.stableKey -and ($must -or $risk)) { 'report-identity-limit' }
                elseif ($must -or ($risk -and -not $skip)) { 'write' } else { 'skip' }
            $action | Should -Be $case.expected
        }
        $script:Contract.routing.newConversationAutoScan | Should -BeFalse
        $script:Contract.routing.elapsedTimeAloneTriggersWrite | Should -BeFalse
    }

    # Scenario: A fork creates A and B from the same point, with neither branch privileged.
    # Purpose: Stop cross-branch last-write-wins and exact-key integrity failures.
    It 'InterT20_resolves_exact_common_and_peer_branch_identity' {
        @($script:Contract.common.requiredFields) | Should -Contain 'Task Key'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Branch ID'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Fork Point'
        $script:Contract.branch.uniquePrimaryBranch | Should -BeFalse
        $script:Contract.branch.forkInheritsParentTaskKey | Should -BeTrue
        $script:Contract.branch.generatedBranchIdRecoverableFromHost | Should -BeTrue
        $script:Contract.common.structuralIndexChangesRequireIntegrationDecision | Should -BeFalse
        $script:Contract.firstFork.pendingBeforeEveryMissingBranchCreation | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingCarriesBranchAndIndexOperations | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingPreservesReplacedCommonCurrent | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingClearsAfterBranchAndIndexReadback | Should -BeTrue
        $script:Contract.adapter.exactTaskKeyLookup | Should -BeTrue
        $script:Contract.adapter.exactBranchIdLookup | Should -BeTrue
        foreach ($case in $script:Cases.lookup) {
            $action = if ($case.mainCount -gt 1 -or $case.branchMatches -gt 1) { 'stop-integrity-conflict' }
                elseif ($case.branchId -and $case.branchMatches -eq 1) { 'exact-branch' }
                elseif ($case.activeBranches -eq 1) { 'unique-active' }
                else { 'resolve-or-ask-material' }
            $action | Should -Be $case.expected
        }
    }

    # Scenario: Objective evidence and candidate choices compete for a common Handoff write.
    # Purpose: Require provenance and user choice for direction-changing integration.
    It 'UnitT30_gates_common_integration_and_conflicting_evidence' {
        foreach ($case in $script:Cases.integration) {
            $action = if ($case.changesDirection -or $case.kind -cin @($script:Contract.integration.userDecisionKinds)) { 'user-decision' }
                elseif ($case.verified -and $case.traceableSource -and $case.kind -cin @($script:Contract.integration.autoKinds)) { 'auto-common-with-provenance' }
                else { 'branch-only' }
            $action | Should -Be $case.expected
        }
        foreach ($case in $script:Cases.conflicts) {
            $action = if (-not $case.revalidated) { 'revalidate-or-supersede' }
                elseif (-not $case.sameVersionEnvironmentScope) { 'retain-applicability' }
                elseif ($case.mutuallyExclusive -and $case.material) { 'conflict-user-decision' }
                else { 'retain-applicability' }
            $action | Should -Be $case.expected
        }
        @($script:Contract.common.conflictMarker.values) | Should -Contain 'Conflict'
    }

    # Scenario: A branch is selected after a common write that may fail on readback.
    # Purpose: Keep every related branch recoverable until the common decision is verified.
    It 'InterT40_preserves_order_and_append_only_status_history' {
        @($script:Contract.integration.selectionOrder) | Should -Be @('conditional-common-write','common-readback','branch-outcomes','archive-selected-and-superseded-branches')
        $script:Contract.integration.archiveOnCommonReadbackFailure | Should -BeFalse
        $script:Contract.changes.appendOnly | Should -BeTrue
        @($script:Contract.changes.eventUniqueKey) | Should -Be @('Operation ID','Record ID','Field')
        @($script:Contract.changes.requiredFields) | Should -Contain 'Operation ID'
        @($script:Contract.changes.requiredFields) | Should -Contain 'Previous State'
        @($script:Contract.changes.requiredFields) | Should -Contain 'New State'
        @($script:Contract.branch.outcomeValues) | Should -Be @('Selected','Partially Selected','Superseded')
        @($script:Contract.branch.optionalFields) | Should -Contain 'Applicability Scope'
        @($script:Contract.branch.lifecycleValues) | Should -Be @('Active','Archived')
        @($script:Contract.branch.workStateValues) | Should -Be @('Running','Awaiting Review','Interrupted','Blocked','Failed')
        @($script:Contract.common.lifecycleValues) | Should -Not -Contain 'Conflict'
    }

    # Scenario: Common and branch inactivity reach the exact seven-day boundary with holds and peers.
    # Purpose: Archive only expired records without refreshing activity from reads or no-op writes.
    It 'UnitT50_evaluates_activity_boundary_and_active_peer_protection' {
        $script:Contract.archive.defaultInactivityDays | Should -Be 7
        $script:Contract.archive.inactivityDaysConfigurable | Should -BeTrue
        $script:Contract.archive.readRefreshesActivity | Should -BeFalse
        $script:Contract.archive.noOpRefreshesActivity | Should -BeFalse
        $script:Contract.archive.exactArchivedBranchOnlyRestored | Should -BeTrue
        $script:Contract.archive.otherPeersRemainArchived | Should -BeTrue
        foreach ($case in $script:Cases.archive) {
            $now = [DateTimeOffset]$case.now
            $last = [DateTimeOffset]$case.lastActivity
            $hold = if ($case.keepActiveUntil) { [DateTimeOffset]$case.keepActiveUntil } else { $null }
            $expired = $now -ge $last.AddDays([int]$script:Contract.archive.defaultInactivityDays)
            $protected = ($hold -and $hold -gt $now) -or ($case.record -eq 'common' -and $case.activeBranches -gt 0)
            $actual = if ($expired -and -not $protected) { 'Archived' } else { 'Active' }
            $actual | Should -Be $case.expected
        }
    }

    # Scenario: A retry arrives after an uncertain write and a peer modifies the revision.
    # Purpose: Prevent duplicate events and silent overwrites on an arbitrary storage platform.
    It 'InterT60_requires_conditional_writes_and_idempotent_retries' {
        $script:Contract.adapter.fixedAuthorityPlatform | Should -BeNullOrEmpty
        $script:Contract.adapter.conditionalMutation | Should -BeTrue
        $script:Contract.adapter.operationIdIdempotency | Should -BeTrue
        $script:Contract.adapter.eventAppendAfterRecordReadback | Should -BeTrue
        $script:Contract.adapter.onRevisionConflict | Should -Be 'reread-and-reapply-gate'
        $script:Contract.adapter.onPartialFailure | Should -Be 'retain-retryable-state-and-report-each-record'
        $script:Contract.adapter.onAuthorityUnavailable | Should -Be 'do-not-promote-unverified-facts'
    }

    # Scenario: A new consumer sees old Notion records and retrieved content contains a secret or directive.
    # Purpose: Make old data opt-in and keep storage evidence from granting new authority.
    It 'UnitT70_keeps_legacy_read_only_and_secrets_out_of_storage' {
        $script:Contract.legacy.exactTaskKeyOnly | Should -BeTrue
        $script:Contract.legacy.bulkMigration | Should -BeFalse
        $script:Contract.legacy.autoResumeOnNewConversation | Should -BeFalse
        $script:Contract.security.handoffGrantsNewAuthorization | Should -BeFalse
        $script:Contract.security.embeddedDirectivesGrantAuthorization | Should -BeFalse
        @($script:Contract.security.excludedContent) | Should -Contain 'credentials'
        @($script:Contract.security.excludedContent) | Should -Contain 'secrets'
        $yaml = Get-Content -Raw (Join-Path $script:Skill 'agents/openai.yaml')
        $yaml | Should -Match '\$manage-task-handoff'
        $yaml | Should -Not -Match '(?m)^\s*value:\s*"(?:notion|jira|github)"\s*$'
    }
}
