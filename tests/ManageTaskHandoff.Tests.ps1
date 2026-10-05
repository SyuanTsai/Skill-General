# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'manage-task-handoff Skill contract' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Skill = Join-Path $script:Root 'skills/manage-task-handoff'
        $script:Contract = Get-Content -Raw (Join-Path $script:Skill 'references/task-handoff-contract.json') | ConvertFrom-Json -Depth 30
        $script:Cases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-task-handoff/scenarios.json') | ConvertFrom-Json -Depth 30
        $script:LegacyCases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/handoff-cases.json') | ConvertFrom-Json -Depth 30
        . (Join-Path $PSScriptRoot 'helpers/ProviderAgnosticMemoryTargetAdapter.ps1')
        Import-Module (Join-Path $script:Skill 'scripts/LegacyNotionHandoffReplay.psm1') -Force
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
        $script:Contract.routing.defaultRiskRecheckMinutes | Should -Be 5
        $script:Contract.routing.riskRecheckMinutesConfigurable | Should -BeTrue
    }

    It 'ContractT11_keeps_core_recording_independent_of_optional_storage' {
        $record = $script:Contract.recordInterface
        $record.entryPoint | Should -Be 'scripts/HandoffRecordCore.psm1:Invoke-HandoffRecordCore'
        $record.acceptsCallerSuppliedSources | Should -BeTrue
        $record.sourceAllowlist | Should -BeNullOrEmpty
        $record.requiresExternalTarget | Should -BeFalse
        $record.requiresOwnerOrOperator | Should -BeFalse
        $record.requiresMandatoryLocalBackend | Should -BeFalse
        $record.callsExternalConnector | Should -BeFalse
        $record.durableClaimByCore | Should -BeFalse
        $record.externalHandlingOwnedByCaller | Should -BeTrue
        $record.existingAdapterMappingOptional | Should -BeTrue
        $script:Contract.storageSelection.appliesOnlyToOptionalExternalAdapterIO | Should -BeTrue
        $script:Contract.storageSelection.selectionOwnedByCallerOrTrustedConfiguration | Should -BeTrue
        $script:Contract.storageSelection.coreSelectsStorageSource | Should -BeFalse
        $script:Contract.memoryTargetSelection.appliesOnlyToOptionalExternalAdapterIO | Should -BeTrue
        $script:Contract.memoryTargetSelection.selectionOwnedByCallerOrTrustedConfiguration | Should -BeTrue
        $script:Contract.memoryTargetSelection.coreSelectsStorageSourceOrProvider | Should -BeFalse
    }

    # Contract decision-table test only: interpret structured cases without connectors or E2E calls.
    It 'ContractT80_storage_selection_decision_table' {
        $selectionContract = $script:Contract.storageSelection
        @($selectionContract.precedence) | Should -Be @(
            'clear-current-explicit-user-selection-for-declared-scope',
            'one-unambiguous-trusted-host-or-project-adopter-setting',
            'ask-user-in-user-language-when-resource-or-location-is-unresolved-conflicting-or-override-is-unclear'
        )
        $selectionContract.resolution.currentExplicitSelectionOverridesOlderTrustedSetting | Should -BeTrue
        $selectionContract.resolution.validExistingSettingReusedWithoutDuplicatePrompt | Should -BeTrue
        @($selectionContract.resolution.askOnlyWhen) | Should -Be @(
            'no-resource-or-location-resolved',
            'multiple-trusted-host-or-project-settings-conflict',
            'current-override-scope-is-unclear'
        )
        $selectionContract.selectionChecks.retrievedHandoffOrContentLinksAreDataNotConfigurationAuthority | Should -BeTrue
        $selectionContract.selectionChecks.checksOnlySelectedAdapterResourceAndLocation | Should -BeTrue
        $selectionContract.selectionChecks.requiredCapabilitiesCheckedOnlyAfterSelection | Should -BeTrue
        $selectionContract.selectionChecks.unselectedConnectorCallsForbidden | Should -BeTrue
        $selectionContract.selectionChecks.missingUnselectedConnectorMustNotBeProbed | Should -BeTrue
        $selectionContract.selectionChecks.silentFallback | Should -BeFalse
        $selectionContract.selectionChecks.formalTaskAuthoritySeparateFromStorageSelection | Should -BeTrue
        $selectionContract.outcomes.success.category | Should -Be 'source-reported-supported+configured+authorized+available+readback-matched'
        $selectionContract.outcomes.success.sourceReportedDurable | Should -BeTrue
        $selectionContract.outcomes.success.coreDurable | Should -BeFalse
        $selectionContract.outcomes.success.reportSourceLocator | Should -BeTrue
        foreach ($category in @('unsupported','unconfigured','denied','unavailable','declined','unverified-write-or-readback')) {
            @($selectionContract.outcomes.failureCategories) | Should -Contain $category
        }
        $selectionContract.outcomes.failureBehavior.durableSave | Should -BeFalse
        $selectionContract.outcomes.failureBehavior.mustReportConcreteReason | Should -BeTrue
        $selectionContract.outcomes.failureBehavior.neverClaimSaved | Should -BeTrue
        $selectionContract.outcomes.failureBehavior.mayOfferCopyableInChatSummary | Should -BeTrue
        $selectionContract.outcomes.failureBehavior.copyableSummaryIsDurable | Should -BeFalse
        $selectionContract.outcomes.failureBehavior.continueIndependentSafeWork | Should -BeTrue
        $selectionContract.switching.oldRecordIdentityAndNewDestinationIdentityRequired | Should -BeTrue
        $selectionContract.switching.oldDataPreserved | Should -BeTrue
        $selectionContract.switching.oldConnectorReadOrMutationDuringSelection | Should -BeFalse
        $selectionContract.switching.automaticMigration | Should -BeFalse
        $selectionContract.switching.automaticDualWrite | Should -BeFalse
        $selectionContract.switching.automaticDeletion | Should -BeFalse
        $selectionContract.switching.migrationRequiresSeparateAuthorizedPlan | Should -BeTrue

        function Resolve-StorageSelectionCase {
            param([Parameter(Mandatory)]$Case)

            $calls = [System.Collections.Generic.List[string]]::new()
            $trusted = @(
                if ($null -eq $Case.trustedSettings) { @() } else { @($Case.trustedSettings) }
            )
            $handoffDataProperty = $Case.PSObject.Properties['handoffData']
            $oldRecordProperty = $Case.PSObject.Properties['oldRecord']
            $modeProperty = $Case.PSObject.Properties['mode']
            $legacyContinuationProperty = $Case.PSObject.Properties['legacyContinuation']
            $selectedCapabilityProperty = $Case.PSObject.Properties['selectedCapability']
            $handoffData = if ($null -eq $handoffDataProperty) { $null } else { $handoffDataProperty.Value }
            $oldRecord = if ($null -eq $oldRecordProperty) { $null } else { $oldRecordProperty.Value }
            $mode = if ($null -eq $modeProperty) { $null } else { [string]$modeProperty.Value }
            $legacyContinuation = if ($null -eq $legacyContinuationProperty) { $null } else { $legacyContinuationProperty.Value }
            $selectedCapability = if ($null -eq $selectedCapabilityProperty) { $null } else { $selectedCapabilityProperty.Value }
            $dataLinksPresent = $null -ne $handoffData
            $result = [ordered]@{
                Selection = 'none'
                Prompt = $false
                AskFor = $null
                ConnectorCalls = @()
                UnselectedConnectorCalls = @()
                DurableSave = $false
                FailureCategory = $null
                CopyableSummary = $false
                Fallback = $false
                Switch = $false
                OldRecordId = $null
                NewDestination = $null
                OldDataPreserved = $null
                AutomaticMigration = $null
                AutomaticDualWrite = $null
                AutomaticDeletion = $null
                Path = $null
                V1ConcurrentWriteClaimed = $null
                WriteCalls = @()
                DataLinksAreNotConfiguration = $dataLinksPresent
            }

            if (-not [bool]$Case.handoffNeeded) {
                return [pscustomobject]$result
            }

            $selection = $null
            $askFor = $null
            $prompt = $false
            $explicit = $Case.explicitSelection
            if ($null -ne $explicit) {
                $selection = [ordered]@{
                    storage = [string]$explicit.storage
                    scope = [string]$explicit.scope
                    resource = [string]$explicit.resource
                    location = [string]$explicit.location
                }
                $sameStorage = @($trusted | Where-Object { [string]$_.storage -ceq $selection.storage })
                if ([string]::IsNullOrWhiteSpace($selection.resource) -and $sameStorage.Count -eq 1) {
                    $selection.resource = [string]$sameStorage[0].resource
                }
                if ([string]::IsNullOrWhiteSpace($selection.location) -and $sameStorage.Count -eq 1) {
                    $selection.location = [string]$sameStorage[0].location
                }
                $differentTrusted = @($trusted | Where-Object {
                    ([string]$_.storage -cne $selection.storage) -or
                    ([string]$_.scope -cne $selection.scope) -or
                    ([string]$_.resource -cne $selection.resource) -or
                    ([string]$_.location -cne $selection.location)
                })
                $result.Switch = $differentTrusted.Count -gt 0
                if ([string]::IsNullOrWhiteSpace($selection.resource) -or [string]::IsNullOrWhiteSpace($selection.location)) {
                    $prompt = $true
                    $askFor = 'resource-or-location'
                }
            } elseif ($trusted.Count -eq 1) {
                $candidate = $trusted[0]
                if ([string]::IsNullOrWhiteSpace([string]$candidate.resource) -or [string]::IsNullOrWhiteSpace([string]$candidate.location)) {
                    $prompt = $true
                    $askFor = 'resource-or-location'
                } else {
                    $selection = [ordered]@{
                        storage = [string]$candidate.storage
                        scope = [string]$candidate.scope
                        resource = [string]$candidate.resource
                        location = [string]$candidate.location
                    }
                }
            } else {
                $prompt = $true
                $askFor = if ($trusted.Count -eq 0) { 'resource-or-location' } else { 'conflicting-storage-settings' }
            }

            if ($prompt) {
                $result.Selection = 'ask'
                $result.Prompt = $true
                $result.AskFor = $askFor
                return [pscustomobject]$result
            }

            $selected = [string]$selection.storage
            $result.Selection = $selected
            $old = if ($null -ne $oldRecord) {
                $oldRecord
            } else {
                @($trusted | Where-Object {
                    [void]($recordIdProperty = $_.PSObject.Properties['recordId'])
                    $null -ne $recordIdProperty -and
                        -not [string]::IsNullOrWhiteSpace([string]$recordIdProperty.Value)
                } | Select-Object -First 1)
            }
            $oldRecordIdProperty = if ($null -eq $old) { $null } else { $old.PSObject.Properties['recordId'] }
            if ($result.Switch -and $null -ne $oldRecordIdProperty) {
                $result.OldRecordId = [string]$oldRecordIdProperty.Value
                $result.NewDestination = [pscustomobject]@{
                    storage = $selection.storage
                    resource = $selection.resource
                    location = $selection.location
                }
                $result.OldDataPreserved = if ($null -ne $oldRecord) { [bool]$old.preserved } else { $true }
                $result.AutomaticMigration = $false
                $result.AutomaticDualWrite = $false
                $result.AutomaticDeletion = $false
            }

            if ($mode -ceq 'legacy-read-only') {
                $legacy = $legacyContinuation
                [void]$calls.Add("${selected}:legacy-capability")
                $legacySupported = $null -ne $legacy -and
                    [bool]$legacy.exactTaskKey -and
                    [bool]$legacy.authorized -and
                    [bool]$legacy.scopeMapped -and
                    [bool]$legacy.readOnlySupported -and
                    -not [bool]$legacy.v1ConcurrentWriteSupported
                if ($legacySupported) {
                    [void]$calls.Add("${selected}:legacy-read")
                    $result.Path = 'legacy-read-only'
                    $result.V1ConcurrentWriteClaimed = $false
                } else {
                    $result.FailureCategory = 'unavailable'
                    $result.CopyableSummary = $true
                }
                $result.ConnectorCalls = @($calls.ToArray())
                return [pscustomobject]$result
            }

            $capability = $selectedCapability
            [void]$calls.Add("${selected}:capability")
            if ($null -eq $capability) {
                $result.FailureCategory = 'unavailable'
            } elseif (-not [bool]$capability.supported) {
                $result.FailureCategory = 'unsupported'
            } elseif (-not [bool]$capability.configured) {
                $result.FailureCategory = 'unconfigured'
            } elseif (-not [bool]$capability.authorized) {
                $result.FailureCategory = 'denied'
            } elseif (-not [bool]$capability.available) {
                $result.FailureCategory = 'unavailable'
            }
            if ($null -ne $result.FailureCategory) {
                $result.CopyableSummary = $true
                $result.ConnectorCalls = @($calls.ToArray())
                return [pscustomobject]$result
            }

            [void]$calls.Add("${selected}:save")
            $result.WriteCalls = @("${selected}:save")
            if (-not [bool]$capability.readback) {
                $result.FailureCategory = 'unverified-write-or-readback'
                $result.CopyableSummary = $true
                $result.ConnectorCalls = @($calls.ToArray())
                return [pscustomobject]$result
            }
            [void]$calls.Add("${selected}:readback")
            $result.DurableSave = $true
            $result.ConnectorCalls = @($calls.ToArray())
            return [pscustomobject]$result
        }

        foreach ($case in $script:Cases.storageSelection) {
            $actual = Resolve-StorageSelectionCase -Case $case
            $actual.Selection | Should -Be $case.expected.selection -Because $case.id
            $actual.Prompt | Should -Be ([bool]$case.expected.prompt) -Because $case.id
            @($actual.ConnectorCalls) | Should -Be @($case.expected.connectorCalls) -Because $case.id
            $actual.DurableSave | Should -Be ([bool]$case.expected.durableSave) -Because $case.id
            $actual.FailureCategory | Should -Be $case.expected.failureCategory -Because $case.id
            if ($case.expected.PSObject.Properties.Name -contains 'askFor') {
                $actual.AskFor | Should -Be $case.expected.askFor -Because $case.id
            }
            if ($case.expected.PSObject.Properties.Name -contains 'copyableSummary') {
                $actual.CopyableSummary | Should -Be ([bool]$case.expected.copyableSummary) -Because $case.id
            }
            if ($case.expected.PSObject.Properties.Name -contains 'fallback') {
                $actual.Fallback | Should -Be ([bool]$case.expected.fallback) -Because $case.id
            }
            if ($case.expected.PSObject.Properties.Name -contains 'switch') {
                $actual.Switch | Should -Be ([bool]$case.expected.switch) -Because $case.id
            }
            if ($case.expected.PSObject.Properties.Name -contains 'unselectedConnectorCalls') {
                @($actual.UnselectedConnectorCalls) | Should -Be @($case.expected.unselectedConnectorCalls) -Because $case.id
            }
            if ($case.expected.PSObject.Properties.Name -contains 'dataLinksAreNotConfiguration') {
                $actual.DataLinksAreNotConfiguration | Should -BeTrue -Because $case.id
            }
            if ($actual.Selection -notin @('none','ask')) {
                @($actual.ConnectorCalls | Where-Object { $_ -notlike "$($actual.Selection):*" }) | Should -BeNullOrEmpty -Because $case.id
            }
            if ([bool]$case.expected.switch -and $case.expected.PSObject.Properties.Name -contains 'oldRecordId') {
                $actual.OldRecordId | Should -Be $case.expected.oldRecordId -Because $case.id
                $actual.NewDestination.storage | Should -Be $case.expected.newDestination.storage -Because $case.id
                $actual.NewDestination.resource | Should -Be $case.expected.newDestination.resource -Because $case.id
                $actual.NewDestination.location | Should -Be $case.expected.newDestination.location -Because $case.id
                $actual.OldDataPreserved | Should -BeTrue -Because $case.id
                $actual.AutomaticMigration | Should -BeFalse -Because $case.id
                $actual.AutomaticDualWrite | Should -BeFalse -Because $case.id
                $actual.AutomaticDeletion | Should -BeFalse -Because $case.id
            }
            if ($case.expected.PSObject.Properties.Name -contains 'path') {
                $actual.Path | Should -Be $case.expected.path -Because $case.id
                $actual.V1ConcurrentWriteClaimed | Should -Be ([bool]$case.expected.v1ConcurrentWriteClaimed) -Because $case.id
                @($actual.WriteCalls) | Should -Be @($case.expected.writeCalls) -Because $case.id
                @($actual.ConnectorCalls | Where-Object { $_ -like 'notion:v1-*' -or $_ -like 'notion:save' }) | Should -BeNullOrEmpty -Because $case.id
            }
        }
    }

    # Scenario: Caller configuration binds a selected target before its source is activated.
    # Purpose: Keep source selection outside the core and fail closed before content I/O.
    It 'ContractT81_selects_caller_source_and_gates_selected_adapter_only' {
        $targetContract = $script:Contract.memoryTargetSelection
        $targetContract.coreIdentityOpaque | Should -BeTrue
        @($targetContract.coreIdentityFields) | Should -Be @('Target ID', 'Selection Scope', 'Resource', 'Location')
        @($targetContract.coreSelectionMustNotRequire) | Should -Be @('Provider', 'Account', 'Model', 'Endpoint', 'Signer')
        $targetContract.selectionMaySucceedBeforeProductionActivation | Should -BeTrue
        $targetContract.binding.suppliedByTrustedHostProjectOrAdopterConfiguration | Should -BeTrue
        $targetContract.binding.opaqueToCore | Should -BeTrue
        $targetContract.binding.exactTargetIdentityRequired | Should -BeTrue
        @($targetContract.binding.identityFields) | Should -Be @('Target ID', 'Selection Scope', 'Resource', 'Location')
        $targetContract.binding.retrievedHandoffCannotDefineBinding | Should -BeTrue
        $targetContract.binding.silentFallback | Should -BeFalse
        $targetContract.productionActivation.checkedOnlyWhenSelectedTargetContentIOIsAttempted | Should -BeTrue
        $targetContract.productionActivation.requirementsDeclaredBySelectedAdapterOnly | Should -BeTrue
        $targetContract.productionActivation.unselectedAdapterRequirementsNeverInspected | Should -BeTrue
        $targetContract.productionActivation.missingOrUnverifiedFailsClosedBeforeContentIO | Should -BeTrue
        $targetContract.productionActivation.capabilityDeniedOrUnavailableFailsClosedBeforeContentIO | Should -BeTrue
        $targetContract.productionActivation.readbackMismatchIsNonDurable | Should -BeTrue
        $targetContract.productionActivation.matchingReadbackIsSourceReportedDurable | Should -BeTrue
        $targetContract.productionActivation.coreDurable | Should -BeFalse
        $targetContract.binding.retiredGitRefExplicitlyUnsupportedWithoutIo | Should -BeTrue
        $targetContract.binding.inferSourceFromRecordForbidden | Should -BeTrue

        foreach ($case in $script:Cases.memoryTargetSelection) {
            $forbiddenFields = @('provider', 'account', 'model', 'endpoint', 'signer')
            $targetPropertyNames = @($case.target.PSObject.Properties.Name | ForEach-Object { $_.ToLowerInvariant() })
            foreach ($field in $forbiddenFields) {
                $targetPropertyNames | Should -Not -Contain $field -Because $case.id
            }

            $adapters = @($case.adapters | ForEach-Object {
                New-ProviderAgnosticMemoryAdapterDouble -Spec $_
            })
            $attemptProperty = $case.PSObject.Properties['attemptProductionWrite']
            $attemptProductionWrite = if ($null -eq $attemptProperty) { $true } else { [bool]$attemptProperty.Value }
            $actual = Invoke-ProviderAgnosticMemoryTargetSelection `
                -Target $case.target `
                -Bindings $case.bindings `
                -Adapters $adapters `
                -Content ([pscustomobject]@{ value = 'neutral-test-content' }) `
                -AttemptProductionWrite:$attemptProductionWrite

            $actual.SelectionStatus | Should -Be $case.expected.selectionStatus -Because $case.id
            $actual.SelectedAdapterId | Should -Be $case.expected.selectedAdapterId -Because $case.id
            $actual.ProductionStatus | Should -Be $case.expected.productionStatus -Because $case.id
            $actual.FailureCategory | Should -Be $case.expected.failureCategory -Because $case.id
            $actual.Durable | Should -Be ([bool]$case.expected.durable) -Because $case.id
            $actual.ContentRead | Should -Be ([bool]$case.expected.contentRead) -Because $case.id
            $actual.ContentWrite | Should -Be ([bool]$case.expected.contentWrite) -Because $case.id
            @($actual.Calls) | Should -Be @($case.expected.calls) -Because $case.id

            $selected = @($adapters | Where-Object { $_.AdapterId -ceq $actual.SelectedAdapterId })
            $selected.Count | Should -Be 1 -Because $case.id
            @($selected[0].Calls) | Should -Be @($case.expected.calls) -Because $case.id
            $selected[0].ActivationRequirementsInspected | Should -Be ($actual.Calls -contains 'activation') -Because $case.id
            $selected[0].CapabilityInspected | Should -Be ($actual.Calls -contains 'capability') -Because $case.id
            foreach ($unselected in @($adapters | Where-Object { $_.AdapterId -cne $actual.SelectedAdapterId })) {
                @($unselected.Calls).Count | Should -Be 0 -Because $case.id
                $unselected.ActivationRequirementsInspected | Should -BeFalse -Because $case.id
                $unselected.CapabilityInspected | Should -BeFalse -Because $case.id
            }

            if ($case.expected.productionStatus -in @('activation-not-ready', 'unsupported', 'unconfigured', 'denied', 'unavailable')) {
                @($actual.Calls | Where-Object { $_ -in @('content-read', 'content-write', 'readback') }) |
                    Should -BeNullOrEmpty -Because $case.id
            }
            if ($case.expected.productionStatus -eq 'unverified-write-or-readback') {
                $actual.Durable | Should -BeFalse -Because $case.id
                @($actual.Calls | Where-Object { $_ -in @('content-read', 'content-write', 'readback') }).Count |
                    Should -Be 3 -Because $case.id
            }
        }
    }

    # Scenario: A task has one common record and independently identified peer branch records.
    # Purpose: Preserve exact task and branch identity without a storage-owned fork-recovery protocol.
    It 'InterT20_resolves_exact_common_and_peer_branch_identity' {
        @($script:Contract.common.requiredFields) | Should -Contain 'Authority Scope'
        @($script:Contract.common.requiredFields) | Should -Contain 'Task Key'
        @($script:Contract.common.uniqueKey) | Should -Be @('Authority Scope','Task Key')
        @($script:Contract.branch.requiredFields) | Should -Contain 'Authority Scope'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Branch ID'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Fork Point'
        @($script:Contract.branch.requiredFields) | Should -Contain 'Continuation Generation'
        @($script:Contract.branch.uniqueKey) | Should -Be @('Authority Scope','Task Key','Branch ID')
        $script:Contract.branch.uniquePrimaryBranch | Should -BeFalse
        $script:Contract.branch.forkInheritsParentTaskKey | Should -BeTrue
        $script:Contract.branch.generatedBranchIdRecoverableFromHost | Should -BeTrue
        $script:Contract.branch.updatesOnlyOwnBranch | Should -BeTrue
        $script:Contract.common.structuralIndexChangesRequireIntegrationDecision | Should -BeFalse
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

    # Scenario: A branch decision is prepared from exact caller-supplied records and a source result may be pending.
    # Purpose: Keep decision identity exact while leaving persistence and event history to the selected source.
    It 'InterT40_binds_reviewed_branch_identity_and_returns_proposed_changes' {
        @($script:Contract.integration.selectionOrder) | Should -Be @(
            'bind-user-decision-to-exact-reviewed-branch-identity-content-generation-and-outcome',
            'stop-if-supplied-reviewed-identity-content-or-generation-changed',
            'return-proposed-record-and-field-change-intents-to-the-caller',
            'perform-no-source-write-or-automatic-retry-in-the-core',
            'accept-only-a-matching-source-reported-operation-result'
        )
        $script:Contract.integration.finalizationBindsReviewedBranchOrigins | Should -BeTrue
        $script:Contract.integration.decisionPersistsBranchRevisionContentIdentityAndOutcome | Should -BeTrue
        $script:Contract.integration.decisionPersistsContinuationGeneration | Should -BeTrue
        $script:Contract.integration.reviewedBranchContentIdentityBasis | Should -Be 'canonical-user-reviewable-branch-fields-at-bound-source-revision'
        @($script:Contract.integration.reviewedBranchContentIdentityExcludes) | Should -Be @('Lifecycle','Branch Outcome','Last Activity At','operation-log')
        $script:Contract.integration.continuationGenerationIncludedInReviewedBranchIdentity | Should -BeTrue
        $script:Contract.integration.finalizationRejectsContinuationGenerationChange | Should -BeTrue
        $script:Contract.integration.explicitContinuationAlwaysAdvancesGeneration | Should -BeTrue
        $script:Contract.integration.forkFromExistingBranchBeginsContinuationBeforeSnapshot | Should -BeTrue
        $script:Contract.integration.decisionWriteRequiresExactReviewedBranchRevisionAndIdentity | Should -BeTrue
        $script:Contract.integration.appliedOutcomeMustMatchDecisionBranchBinding | Should -BeTrue
        $script:Contract.integration.onReviewedBranchChangeDuringFinalization | Should -Be 'stop-and-require-renewed-user-confirmation'
        $script:Contract.integration.sourceOwnsConflictResolutionMergePersistenceAndRetry | Should -BeTrue
        $script:Contract.integration.corePerformsSourceCompareAndSwap | Should -BeFalse
        $script:Contract.integration.coreRetriesSourceWrites | Should -BeFalse
        $script:Contract.integration.onCommonDecisionIdentityChangeDuringFinalization | Should -Be 'stop-and-require-current-source-and-user-review'
        $script:Contract.integration.archiveOnCommonReadbackFailure | Should -BeFalse
        $script:Contract.changes.proposalOnly | Should -BeTrue
        $script:Contract.changes.perChangedField | Should -BeTrue
        @($script:Contract.changes.requiredFields) | Should -Be @('Authority Scope','Task Key','Branch ID','Operation ID','Field','Previous State','New State','Status')
        $script:Contract.changes.proposedStatus | Should -Be 'proposed'
        $script:Contract.changes.doNotEmitUnchangedFields | Should -BeTrue
        $script:Contract.changes.sourceOwnsPersistenceAndAnyEventHistory | Should -BeTrue
        $script:Contract.changes.corePersistsEvents | Should -BeFalse
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
        $script:Contract.archive.expireAtBoundary | Should -BeTrue
        $script:Contract.archive.readRefreshesActivity | Should -BeFalse
        $script:Contract.archive.noOpRefreshesActivity | Should -BeFalse
        $script:Contract.archive.archiveChangesLifecycleOnly | Should -BeTrue
        $script:Contract.archive.noContentDeletion | Should -BeTrue
        $script:Contract.archive.activeBranchProtectsCommon | Should -BeTrue
        $script:Contract.archive.exactArchivedBranchOnlyRestored | Should -BeTrue
        $script:Contract.archive.otherPeersRemainArchived | Should -BeTrue
        $script:Contract.archive.branchContinuationGenerationInitial | Should -Be 0
        $script:Contract.archive.explicitRestoreIncrementsContinuationGeneration | Should -BeTrue
        $script:Contract.archive.explicitActiveContinuationIncrementsContinuationGeneration | Should -BeTrue
        $script:Contract.archive.continuationIncrementPrecedesResumedWorkOrFork | Should -BeTrue
        $script:Contract.archive.sameContinuationOperationIdOwnsOneIncrement | Should -BeTrue
        $script:Contract.archive.readOnlyInspectionAndFinalizationDoNotIncrementGeneration | Should -BeTrue
        $script:Contract.archive.restoreLifecycleAndGenerationInOneSourceOperation | Should -BeTrue
        $script:Contract.archive.oldDecisionCannotFinalizeRestoredGeneration | Should -BeTrue
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

    # Scenario: A source reports a pending result or a matching readback for one archive operation.
    # Purpose: Keep source persistence and conflict handling outside the core and prevent automatic write replay.
    It 'InterT60_keeps_source_persistence_and_conflict_handling_source_owned' {
        $script:Contract.adapter.fixedAuthorityPlatform | Should -BeNullOrEmpty
        $script:Contract.authority.accessPolicyChosenByAdopter | Should -BeTrue
        $script:Contract.authority.authorityScopeIsOpaqueAndAdopterDefined | Should -BeTrue
        $script:Contract.authority.verifiedPrincipalComesFromTrustedHostContext | Should -BeTrue
        $script:Contract.authority.callerSuppliedRecordIdentifiersNeverAuthorizeAccess | Should -BeTrue
        $script:Contract.adapter.trustedCallerContextRequired | Should -BeTrue
        $script:Contract.adapter.authorizationPolicyChosenByAdopter | Should -BeTrue
        @($script:Contract.adapter.authorizationTuple) | Should -Be @(
            'Verified Principal','Authority Scope','Task Key','Branch ID','Action'
        )
        $script:Contract.adapter.sourceAuthorizesEveryLookupAndMutation | Should -BeTrue
        $script:Contract.adapter.recordIdentityIncludesAuthorityScope | Should -BeTrue
        $script:Contract.adapter.scopeIdentityUsesUnambiguousComponentEncoding | Should -BeTrue
        $script:Contract.adapter.actorIsDisplayClaimNotAuthorization | Should -BeTrue
        $script:Contract.adapter.crossScopeLookupForbidden | Should -BeTrue
        $script:Contract.adapter.exactTaskKeyLookup | Should -BeTrue
        $script:Contract.adapter.exactBranchIdLookup | Should -BeTrue
        $script:Contract.adapter.sourceOwnsPersistence | Should -BeTrue
        $script:Contract.adapter.sourceOwnsConditionalMutationAndOperationIdIdempotency | Should -BeTrue
        $script:Contract.adapter.sourceOwnsConflictResolutionAndMerge | Should -BeTrue
        $script:Contract.adapter.sourceOwnsWriteRetry | Should -BeTrue
        $script:Contract.adapter.sourceReportsItsOwnReadback | Should -BeTrue
        $script:Contract.adapter.coreCallsExternalConnector | Should -BeFalse
        $script:Contract.adapter.corePerformsSourceCompareAndSwap | Should -BeFalse
        $script:Contract.adapter.coreRetriesSourceWrites | Should -BeFalse
        $script:Contract.adapter.coreIndependentlyVerifiesSourceResult | Should -BeFalse
        $script:Contract.adapter.onAuthorizationUnavailableOrDenied | Should -Be 'deny-without-reading-or-writing-record-content'
        $script:Contract.adapter.onRevisionConflict | Should -Be 'source-owned; caller-supplies-a-new-result-for-the-same-operation'
        $script:Contract.adapter.onPartialFailure | Should -Be 'retain-source-reported-pending-state-with-the-original-operation-id'
        $script:Contract.adapter.onAuthorityUnavailable | Should -Be 'do-not-promote-unverified-facts'
        $script:Contract.adapterResultReport.coreExecutesSourceOperations | Should -BeFalse
        $script:Contract.adapterResultReport.pendingActionsAreDescriptiveOnly | Should -BeTrue
        $script:Contract.adapterResultReport.operationIdMustMatchCoreOperation | Should -BeTrue
        $script:Contract.adapterResultReport.matchedReadbackRequiresMatchingRevision | Should -BeTrue
        $script:Contract.adapterResultReport.corePreservesCallerReportWithoutExternalVerification | Should -BeTrue
        @($script:Contract.adapterResultReport.statuses) | Should -Be @('denied','unavailable','partial','unknown','readback-mismatch','readback-matched')
        $script:Contract.adapterResultReport.coreDurable | Should -BeFalse

        $cycle = $script:Contract.archiveCycle
        $cycle.selectionIsPure | Should -BeTrue
        $cycle.freshArchiveActionInvokedOnce | Should -BeTrue
        $cycle.freshCallbackReturnsCallerResultV1 | Should -BeTrue
        $cycle.archiveCallbackRequiredOnlyForFreshActions | Should -BeTrue
        $cycle.callerResultV1SchemaUnchanged | Should -BeTrue
        $cycle.sourceResultsCallerResultRequiresExactFullV1Shape | Should -BeTrue
        $cycle.sourceResultsCallerResultFieldCount | Should -Be 13
        $cycle.sourceResultsRejectStatusOnlyCallerResult | Should -BeTrue
        $cycle.pendingArchiveActionNeverReplayed | Should -BeTrue
        $cycle.sourceResultsOnlyResumeSupported | Should -BeTrue
        $cycle.sourceResultsOnlyResumeDoesNotRequireArchiveCallback | Should -BeTrue
        @($cycle.sourceResultsItemFields) | Should -Be @('Decision','Cursor','OperationId','CallerResult')
        $cycle.sourceResultsOuterOperationIdMustMatchSavedPendingOperationId | Should -BeTrue
        $cycle.sourceResultsCallerResultOperationIdMustMatchSavedPendingOperationId | Should -BeTrue
        $cycle.sourceResultsDecisionAndCursorMustMatchSameRecordRevisionGenerationAndOutcome | Should -BeTrue
        $cycle.malformedDuplicateUnauthorizedOrMismatchedSourceResultsRemainPending | Should -BeTrue
        $cycle.matchingReadbackMatchedIsSourceReportedDurable | Should -BeTrue
        $cycle.onlyReadbackMatchedCanBeReportedCompleted | Should -BeTrue
        $cycle.sourceReportedCompletionCollectionField | Should -Be 'SourceReportedCompleted'
        $cycle.sourceReportedCompletedMirrorsCompleted | Should -BeTrue
        $cycle.sourceReportedDurableField | Should -Be 'SourceReportedDurable'
        $cycle.sourceReportedDurableIsAggregateOverEverySelectedAction | Should -BeTrue
        $cycle.coreDurableField | Should -Be 'Durable'
        $cycle.coreDurableOnSourceReportedCompletion | Should -BeFalse
        @($cycle.nonSuccessStatusesRemainPending) | Should -Be @('denied','unavailable','partial','unknown','readback-mismatch')
        $cycle.noConfiguredSource | Should -Be 'report-unsupported-or-unpersisted-and-preserve-pending'
        $cycle.sourceOwnsPersistenceConflictResolutionMergeAndRetry | Should -BeTrue
        $cycle.noAutomaticFallback | Should -BeTrue
        $script:Contract.PSObject.Properties.Name | Should -Not -Contain 'forkRecovery'
        $script:Contract.PSObject.Properties.Name | Should -Not -Contain 'firstFork'
        $script:Contract.adapter.PSObject.Properties.Name | Should -Not -Contain 'logicalOperationKeys'
    }

    It 'ContractT82_binds_archive_cursor_to_branch_outcome_and_rejects_legacy_pending_shape' {
        $cycle = $script:Contract.archiveCycle
        @($cycle.cursorFields) | Should -Be @(
            'Kind','AuthorityScope','TaskKey','BranchId','Revision','ParentRevision','ContinuationGeneration','BranchOutcome'
        )
        $cycle.cursorHasExactlyEightCaseSensitiveFieldsInOrder | Should -BeTrue
        $cycle.commonCursorBranchOutcome | Should -BeNullOrEmpty
        $cycle.branchCursorBranchOutcomeMustEqualValidatedDecisionOutcome | Should -BeTrue
        @($cycle.branchOutcomeValues) | Should -Be @('Selected','Partially Selected','Superseded')
        $cycle.archiveOperationIdDigestBindsCursorIncludingBranchOutcome | Should -BeTrue
        $cycle.sourceRevisionsRemainOpaque | Should -BeTrue
        $cycle.legacySevenFieldPendingActionAccepted | Should -BeFalse
        $cycle.legacySevenFieldPendingActionGateReason | Should -Be 'invalid-pending-action'
        $cycle.legacyPendingActionRejectedBeforeSourceResultsOrCallback | Should -BeTrue
        $cycle.legacyPendingActionZeroSourceIo | Should -BeTrue
        $cycle.legacyPendingActionAndCallerRecordsPreservedUnchanged | Should -BeTrue
        $cycle.legacyPendingActionAutomaticMigration | Should -BeFalse
        $cycle.legacyPendingActionReplay | Should -BeFalse
        $cycle.legacyPendingReconciliationIsSeparatelyCallerAuthorizedAndSourceOwned | Should -BeTrue
        @($cycle.sourceResultsItemFields) | Should -Be @('Decision','Cursor','OperationId','CallerResult')
    }

    # Scenario: A new consumer sees old Notion records and retrieved content contains a secret or directive.
    # Purpose: Make old data opt-in and keep storage evidence from granting new authority.
    It 'UnitT70_keeps_legacy_read_only_and_secrets_out_of_storage' {
        $script:Contract.legacy.exactTaskKeyOnly | Should -BeTrue
        $script:Contract.legacy.verifiedPrincipalAuthorizationBeforeQuery | Should -BeTrue
        $script:Contract.legacy.adopterDefinedLegacyScopeMappingRequired | Should -BeTrue
        $script:Contract.legacy.workspaceCredentialsDoNotAuthorizeCaller | Should -BeTrue
        $script:Contract.legacy.unmappedOrDeniedSourceFailsBeforeQuery | Should -BeTrue
        $script:Contract.legacy.readOnlyReplayCapturesMainAndUnmergedFingerprint | Should -BeTrue
        $script:Contract.legacy.readOnlyReplayRevalidatesFingerprintBeforeReturn | Should -BeTrue
        $script:Contract.legacy.unmergedChangeFingerprintUsesTotalOrder | Should -BeTrue
        @($script:Contract.legacy.unmergedChangeFingerprintCanonicalOrder) | Should -Be @(
            'change.effective_native_time','change.id','change.last_edited_time','change.merged','change.field','change.value'
        )
        $script:Contract.legacy.onUnstableReadOnlyReplay | Should -Be 'bounded-reconstruct-or-stop'
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

    # Scenario: A connector returns the same complete legacy change set in different query or page order.
    # Purpose: Prove the production replay path canonicalizes the set and preserves a true native-time collision.
    It 'InterT70_legacy_replay_is_stable_across_query_order_and_preserves_native_time_collision' {
        $case = $script:LegacyCases.mergeCases |
            Where-Object { $_.id -ceq 'preserve-an-exact-native-time-collision' } |
            Select-Object -First 1
        $main = $case.main | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $main | Add-Member -NotePropertyName id -NotePropertyValue 'handoff-collision'
        $forward = @($case.changes)
        $reverse = @($case.changes | Sort-Object id -Descending)
        $readerState = @{ mainReads = 0; changeReads = 0 }

        $forwardFingerprint = Get-LegacyNotionUnmergedChangeFingerprint -Changes $forward
        $reverseFingerprint = Get-LegacyNotionUnmergedChangeFingerprint -Changes $reverse
        $forwardFingerprint | Should -BeExactly $reverseFingerprint

        $result = Invoke-LegacyNotionReadOnlyReplay `
            -Contract (Get-Content -Raw (Join-Path $script:Skill 'references/legacy-notion-handoff-contract.json') | ConvertFrom-Json -Depth 30) `
            -ReadMain {
                $readerState.mainReads++
                return $main
            } `
            -ReadUnmergedChanges {
                $readerState.changeReads++
                if (($readerState.changeReads % 2) -eq 1) { return $reverse }
                return $forward
            }

        $result.Status | Should -BeExactly 'Stable'
        $result.ReconstructionAttempts | Should -Be 1
        $readerState.mainReads | Should -Be 2
        $readerState.changeReads | Should -Be 2
        $result.CapturedFingerprint | Should -BeExactly $result.ConfirmedFingerprint
        $result.Replay.Fields.Current | Should -BeExactly 'Original checkpoint'
        @($result.Replay.AppliedChangeIds).Count | Should -Be 0
        @($result.Replay.CollisionFields) | Should -Be @('Current')
        @($result.Replay.Collisions.ChangeId | Sort-Object) | Should -Be @('change-20','change-21')
    }

    # Scenario: A stable legacy result set repeats one immutable change ID across different fields and native times.
    # Purpose: Reject ambiguous identity before any reconstructed view can be returned.
    It 'InterT71_rejects_duplicate_unmerged_legacy_change_ids_without_publishing_a_view' {
        $mainCase = $script:LegacyCases.mergeCases | Select-Object -First 1
        $main = $mainCase.main | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $main | Add-Member -NotePropertyName id -NotePropertyValue 'handoff-duplicate-change-id'
        $changes = @(
            [PSCustomObject]@{
                id = 'duplicate-change-id'
                field = 'Current'
                value = '"First checkpoint"'
                merged = $false
                created_time = '2026-09-01T04:02:00Z'
                last_edited_time = '2026-09-01T04:03:00Z'
            }
            [PSCustomObject]@{
                id = 'duplicate-change-id'
                field = 'Scope'
                value = '"Second scope"'
                merged = $false
                created_time = '2026-09-01T04:04:00Z'
                last_edited_time = '2026-09-01T04:05:00Z'
            }
        )
        $readerState = @{ mainReads = 0; changeReads = 0 }
        $result = $null
        $errorMessage = $null

        try {
            $result = Invoke-LegacyNotionReadOnlyReplay `
                -Contract (Get-Content -Raw (Join-Path $script:Skill 'references/legacy-notion-handoff-contract.json') | ConvertFrom-Json -Depth 30) `
                -ReadMain {
                    $readerState.mainReads++
                    return $main
                } `
                -ReadUnmergedChanges {
                    $readerState.changeReads++
                    return $changes
                }
        }
        catch {
            $errorMessage = $_.Exception.Message
        }

        $errorMessage | Should -BeExactly 'Legacy Notion unmerged change IDs must be non-empty and unique.'
        $result | Should -BeNullOrEmpty
        $readerState.mainReads | Should -Be 1
        $readerState.changeReads | Should -Be 1
    }

    # Scenario: An otherwise stable legacy read returns an unmerged change with a whitespace-only ID.
    # Purpose: Reject a change without durable identity before producing a reconstructed view.
    It 'InterT72_rejects_empty_unmerged_legacy_change_ids' {
        $mainCase = $script:LegacyCases.mergeCases | Select-Object -First 1
        $main = $mainCase.main | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $main | Add-Member -NotePropertyName id -NotePropertyValue 'handoff-empty-change-id'
        $change = [PSCustomObject]@{
            id = '  '
            field = 'Current'
            value = '"Checkpoint"'
            merged = $false
            created_time = '2026-09-01T04:02:00Z'
            last_edited_time = '2026-09-01T04:03:00Z'
        }
        $errorMessage = $null

        try {
            Invoke-LegacyNotionReadOnlyReplay `
                -Contract (Get-Content -Raw (Join-Path $script:Skill 'references/legacy-notion-handoff-contract.json') | ConvertFrom-Json -Depth 30) `
                -ReadMain { return $main } `
                -ReadUnmergedChanges { return @($change) } | Out-Null
        }
        catch {
            $errorMessage = $_.Exception.Message
        }

        $errorMessage | Should -BeExactly 'Legacy Notion unmerged change IDs must be non-empty and unique.'
    }

    # Scenario: Two unmerged changes have IDs that differ only by letter case.
    # Purpose: Keep distinct case-sensitive identities while replaying both changes.
    It 'InterT73_compares_legacy_change_ids_with_ordinal_identity' {
        $mainCase = $script:LegacyCases.mergeCases | Select-Object -First 1
        $main = $mainCase.main | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $main | Add-Member -NotePropertyName id -NotePropertyValue 'handoff-ordinal-change-ids'
        $changes = @(
            [PSCustomObject]@{
                id = 'Change-case'
                field = 'Current'
                value = '"First checkpoint"'
                merged = $false
                created_time = '2026-09-01T04:02:00Z'
                last_edited_time = '2026-09-01T04:03:00Z'
            }
            [PSCustomObject]@{
                id = 'change-case'
                field = 'Scope'
                value = '"Second scope"'
                merged = $false
                created_time = '2026-09-01T04:04:00Z'
                last_edited_time = '2026-09-01T04:05:00Z'
            }
        )

        $result = Invoke-LegacyNotionReadOnlyReplay `
            -Contract (Get-Content -Raw (Join-Path $script:Skill 'references/legacy-notion-handoff-contract.json') | ConvertFrom-Json -Depth 30) `
            -ReadMain { return $main } `
            -ReadUnmergedChanges { return $changes }

        $result.Status | Should -BeExactly 'Stable'
        @($result.Replay.AppliedChangeIds).Count | Should -Be 2
        $result.Replay.Fields.Current | Should -BeExactly 'First checkpoint'
        $result.Replay.Fields.Scope | Should -BeExactly 'Second scope'
    }

    It 'UnitT71_replays_legacy_merge_fixtures_through_the_production_helper' {
        $legacyContract = Get-Content -Raw (Join-Path $script:Skill 'references/legacy-notion-handoff-contract.json') |
            ConvertFrom-Json -Depth 30
        foreach ($case in $script:LegacyCases.mergeCases) {
            $main = $case.main | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
            $main | Add-Member -NotePropertyName id -NotePropertyValue "handoff-$($case.id)"
            $changes = @($case.changes)
            $result = Invoke-LegacyNotionReadOnlyReplay `
                -Contract $legacyContract `
                -ReadMain { return $main } `
                -ReadUnmergedChanges { return $changes }

            $result.Status | Should -BeExactly 'Stable' -Because $case.id
            ($result.Replay.Fields | ConvertTo-Json -Compress) |
                Should -BeExactly ($case.expected.fields | ConvertTo-Json -Compress) -Because $case.id
            @($result.Replay.AppliedChangeIds) | Should -Be @($case.expected.appliedChangeIds) -Because $case.id
            @($result.Replay.CollisionFields) | Should -Be @($case.expected.collisionFields) -Because $case.id
            @($result.Replay.InvalidChangeIds) | Should -Be @($case.expected.invalidChangeIds) -Because $case.id
        }
    }
}
