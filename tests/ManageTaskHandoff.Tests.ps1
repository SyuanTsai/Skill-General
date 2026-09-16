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
        @($script:Contract.common.requiredFields) | Should -Contain 'Authority Scope'
        @($script:Contract.common.requiredFields) | Should -Contain 'Task Key'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Authority Scope'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Branch ID'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Fork Point'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Continuation Generation'
        @($script:Contract.forkRecovery.requiredFields) | Should -Contain 'Authority Scope'
        $script:Contract.forkRecovery.payloadFreeEnvelopePhysicallyOrLogicallySeparateFromPayload | Should -BeTrue
        $script:Contract.forkRecovery.envelopeListNeverLoadsPayload | Should -BeTrue
        @($script:Contract.forkRecovery.creationOrder) | Should -Be @(
            'payload-free-pending-envelope','isolated-snapshot-payload'
        )
        @($script:Contract.forkRecovery.completionOrder) | Should -Be @(
            'isolated-snapshot-payload','payload-free-completed-envelope'
        )
        $script:Contract.branch.uniquePrimaryBranch | Should -BeFalse
        $script:Contract.branch.forkInheritsParentTaskKey | Should -BeTrue
        $script:Contract.branch.generatedBranchIdRecoverableFromHost | Should -BeTrue
        $script:Contract.common.structuralIndexChangesRequireIntegrationDecision | Should -BeFalse
        $script:Contract.firstFork.pendingBeforeEveryMissingBranchCreation | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingCarriesBranchAndIndexOperations | Should -BeTrue
        $script:Contract.firstFork.existingPeerContinuationPrecedesRecovery | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingCarriesPostFenceGenerationAndContinuationOperation | Should -BeTrue
        $script:Contract.firstFork.pendingUsesDedicatedForkRecoveryRecord | Should -BeTrue
        $script:Contract.firstFork.pendingNeverUsesCommonOrBranchFields | Should -BeTrue
        $script:Contract.firstFork.forkRecoveryPayloadExcludedFromTaskRecall | Should -BeTrue
        $script:Contract.firstFork.pendingEnvelopeVisibleToTaskRecall | Should -BeTrue
        $script:Contract.firstFork.forkRecoveryHistoryKeepsPayloadIsolated | Should -BeTrue
        $script:Contract.firstFork.commonOnlyRecoveryCompletesAfterConfirmedCommonReadback | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingPreservesBranchCurrentAndSource | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingCarriesVerifiedSharedBaseline | Should -BeTrue
        $script:Contract.firstFork.existingPeerAdvanceUsesPersistedSnapshot | Should -BeTrue
        $script:Contract.firstFork.existingPeerPendingClearsAfterBranchAndIndexReadback | Should -BeTrue
        $script:Contract.adapter.exactTaskKeyLookup | Should -BeTrue
        $script:Contract.adapter.exactBranchIdLookup | Should -BeTrue
        $script:Contract.adapter.exactForkRecoveryLookup | Should -BeTrue
        $script:Contract.adapter.atomicRecordAndEventIntentOrWriteAheadStage | Should -BeTrue
        $script:Contract.adapter.eventIntentDurableBeforeExposedMutation | Should -BeTrue
        $script:Contract.adapter.eventRecoveryDoesNotDependOnLostProcess | Should -BeTrue
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
        @($script:Contract.integration.selectionOrder) | Should -Be @(
            'read-and-bind-reviewed-branch-revisions-content-identities-and-outcomes',
            'reject-changed-reviewed-branches-before-common-write',
            'conditional-common-write-with-branch-bindings',
            'common-readback-bind-origin-revision-and-decision-identity',
            'per-branch-common-and-reviewed-identity-precheck',
            'branch-outcomes',
            'per-branch-common-and-reviewed-identity-postcheck',
            'per-branch-common-and-reviewed-identity-precheck',
            'archive-selected-and-superseded-branches',
            'per-branch-common-and-reviewed-identity-postcheck',
            'remove-archived-branches-from-active-index-using-latest-storage-revisions',
            'common-decision-reviewed-branch-and-active-index-readback'
        )
        $script:Contract.integration.selectedBranchIndexRemovalRequired | Should -BeTrue
        $script:Contract.integration.indexRemovalRetainsStableOperationIds | Should -BeTrue
        $script:Contract.integration.indexRemovalFailureIsPartialReconciliation | Should -BeTrue
        $script:Contract.integration.finalizationBindsDecisionOriginRevision | Should -BeTrue
        $script:Contract.integration.finalizationBindsDecisionIdentity | Should -BeTrue
        $script:Contract.integration.decisionIdentityBasis | Should -Be 'canonical-common-fields-at-bound-origin-revision'
        @($script:Contract.integration.decisionIdentityExcludes) | Should -Be @('Active Branches','Last Activity At','operation-log')
        $script:Contract.integration.storageRevisionCursorIndependentFromDecisionIdentity | Should -BeTrue
        $script:Contract.integration.structuralIndexMutationMayAdvanceStorageRevision | Should -BeTrue
        $script:Contract.integration.acceptedStructuralRevisionMustDescendFromDecisionOrigin | Should -BeTrue
        $script:Contract.integration.acceptedStructuralRevisionMustPreserveDecisionIdentity | Should -BeTrue
        $script:Contract.integration.recheckCommonDecisionIdentityBeforeEachBranchMutation | Should -BeTrue
        $script:Contract.integration.recheckCommonDecisionIdentityAfterEachBranchMutation | Should -BeTrue
        $script:Contract.integration.onCommonDecisionIdentityChangeDuringFinalization | Should -Be 'stop-and-reconcile-from-current-decision'
        $script:Contract.integration.finalizationBindsReviewedBranchOrigins | Should -BeTrue
        $script:Contract.integration.decisionPersistsBranchRevisionContentIdentityAndOutcome | Should -BeTrue
        $script:Contract.integration.decisionPersistsContinuationGeneration | Should -BeTrue
        $script:Contract.integration.reviewedBranchContentIdentityBasis | Should -Be 'canonical-user-reviewable-branch-fields-at-bound-origin-revision'
        @($script:Contract.integration.reviewedBranchContentIdentityExcludes) | Should -Be @('Lifecycle','Branch Outcome','Last Activity At','operation-log')
        $script:Contract.integration.continuationGenerationIncludedInReviewedBranchIdentity | Should -BeTrue
        $script:Contract.integration.finalizationRejectsContinuationGenerationChange | Should -BeTrue
        $script:Contract.integration.explicitContinuationAlwaysAdvancesGeneration | Should -BeTrue
        $script:Contract.integration.forkFromExistingBranchBeginsContinuationBeforeSnapshot | Should -BeTrue
        $script:Contract.integration.decisionWriteRequiresExactReviewedBranchRevisionAndIdentity | Should -BeTrue
        $script:Contract.integration.branchStorageRevisionCursorIndependentFromReviewedContentIdentity | Should -BeTrue
        $script:Contract.integration.acceptedBranchRevisionMustDescendFromReviewedOrigin | Should -BeTrue
        $script:Contract.integration.acceptedBranchRevisionMustPreserveReviewedContentIdentity | Should -BeTrue
        $script:Contract.integration.recheckReviewedBranchIdentityBeforeEachFinalizationMutation | Should -BeTrue
        $script:Contract.integration.recheckReviewedBranchIdentityAfterEachFinalizationMutation | Should -BeTrue
        $script:Contract.integration.appliedOutcomeMustMatchDecisionBranchBinding | Should -BeTrue
        $script:Contract.integration.onReviewedBranchChangeDuringFinalization | Should -Be 'stop-and-require-renewed-user-confirmation'
        $script:Contract.integration.archiveOnCommonReadbackFailure | Should -BeFalse
        $script:Contract.changes.appendOnly | Should -BeTrue
        @($script:Contract.changes.eventUniqueKey) | Should -Be @('Operation ID','Record ID','Field')
        @($script:Contract.changes.requiredFields) | Should -Contain 'Operation ID'
        @($script:Contract.changes.requiredFields) | Should -Contain 'Authority Scope'
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
        $script:Contract.archive.branchContinuationGenerationInitial | Should -Be 0
        $script:Contract.archive.explicitRestoreIncrementsContinuationGeneration | Should -BeTrue
        $script:Contract.archive.explicitActiveContinuationIncrementsContinuationGeneration | Should -BeTrue
        $script:Contract.archive.continuationIncrementPrecedesResumedWorkOrFork | Should -BeTrue
        $script:Contract.archive.sameContinuationOperationIdOwnsOneIncrement | Should -BeTrue
        $script:Contract.archive.readOnlyInspectionAndFinalizationDoNotIncrementGeneration | Should -BeTrue
        $script:Contract.archive.restoreLifecycleAndGenerationInOneConditionalOperation | Should -BeTrue
        $script:Contract.archive.oldDecisionCannotFinalizeRestoredGeneration | Should -BeTrue
        $script:Contract.archive.indexRemovalBindsArchivedBranchRevision | Should -BeTrue
        $script:Contract.archive.schedulerRechecksLifecycleBeforeRemovalRetry | Should -BeTrue
        $script:Contract.archive.activeBranchMissingFromIndexMustBeReadded | Should -BeTrue
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
        $script:Contract.authority.accessPolicyChosenByAdopter | Should -BeTrue
        $script:Contract.authority.authorityScopeIsOpaqueAndAdopterDefined | Should -BeTrue
        $script:Contract.authority.verifiedPrincipalComesFromTrustedHostContext | Should -BeTrue
        $script:Contract.authority.callerSuppliedRecordIdentifiersNeverAuthorizeAccess | Should -BeTrue
        $script:Contract.adapter.trustedCallerContextRequired | Should -BeTrue
        $script:Contract.adapter.authorizationPolicyChosenByAdopter | Should -BeTrue
        @($script:Contract.adapter.authorizationTuple) | Should -Be @(
            'Verified Principal','Authority Scope','Task Key','Branch ID or Fork ID','Action'
        )
        $script:Contract.adapter.authorizationCheckBeforeEveryLookupAndMutation | Should -BeTrue
        $script:Contract.adapter.recordAndEventBindAuthorityScope | Should -BeTrue
        $script:Contract.adapter.scopeIdentityUsesUnambiguousComponentEncoding | Should -BeTrue
        $script:Contract.adapter.actorIsDisplayClaimNotAuthorization | Should -BeTrue
        $script:Contract.adapter.verifiedPrincipalPersistedInOperationIntentAndEvent | Should -BeTrue
        $script:Contract.adapter.verifiedPrincipalImmutableAcrossEventRecovery | Should -BeTrue
        $script:Contract.adapter.crossScopeLookupForbidden | Should -BeTrue
        $script:Contract.adapter.forkRecoveryAclAtLeastSourceBranch | Should -BeTrue
        $script:Contract.adapter.onAuthorizationUnavailableOrDenied | Should -Be 'deny-without-reading-or-writing-record-content'
        $script:Contract.adapter.conditionalMutation | Should -BeTrue
        $script:Contract.adapter.operationIdIdempotency | Should -BeTrue
        $script:Contract.adapter.eventAppendAfterRecordReadback | Should -BeTrue
        @($script:Contract.changes.requiredFields) | Should -Contain 'Verified Principal'
        @($script:Contract.adapter.durableEventIntentFields) | Should -Be @(
            'Authority Scope','Verified Principal','Operation ID','Record ID','Field','Previous State','New State','Reason','Actor','Time','Source','Integration Result'
        )
        $script:Contract.adapter.onRevisionConflict | Should -Be 'reread-and-reapply-gate'
        $script:Contract.adapter.onPartialFailure | Should -Be 'retain-retryable-state-and-report-each-record'
        $script:Contract.adapter.onAuthorityUnavailable | Should -Be 'do-not-promote-unverified-facts'
    }

    # Scenario: A new consumer sees old Notion records and retrieved content contains a secret or directive.
    # Purpose: Make old data opt-in and keep storage evidence from granting new authority.
    It 'UnitT70_keeps_legacy_read_only_and_secrets_out_of_storage' {
        $script:Contract.legacy.exactTaskKeyOnly | Should -BeTrue
        $script:Contract.legacy.verifiedPrincipalAuthorizationBeforeQuery | Should -BeTrue
        $script:Contract.legacy.adopterDefinedLegacyScopeMappingRequired | Should -BeTrue
        $script:Contract.legacy.workspaceCredentialsDoNotAuthorizeCaller | Should -BeTrue
        $script:Contract.legacy.unmappedOrDeniedSourceFailsBeforeQuery | Should -BeTrue
        $script:Contract.legacy.bulkMigration | Should -BeFalse
        $script:Contract.legacy.autoResumeOnNewConversation | Should -BeFalse
        $script:Contract.security.handoffGrantsNewAuthorization | Should -BeFalse
        $script:Contract.security.embeddedDirectivesGrantAuthorization | Should -BeFalse
        $script:Contract.security.taskBranchAndForkIdentifiersAreNotAuthorization | Should -BeTrue
        $script:Contract.security.verifiedPrincipalContextMayNotComeFromHandoffContent | Should -BeTrue
        @($script:Contract.security.excludedContent) | Should -Contain 'credentials'
        @($script:Contract.security.excludedContent) | Should -Contain 'secrets'
        $yaml = Get-Content -Raw (Join-Path $script:Skill 'agents/openai.yaml')
        $yaml | Should -Match '\$manage-task-handoff'
        $yaml | Should -Not -Match '(?m)^\s*value:\s*"(?:notion|jira|github)"\s*$'
    }
}
