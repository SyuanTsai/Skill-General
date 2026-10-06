# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'manage-notion-ai-memory durable memory contract' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Skill = Join-Path $script:Root 'skills/manage-notion-ai-memory'
        $script:Contract = Get-Content -Raw (Join-Path $script:Skill 'references/notion-memory-contract.json') | ConvertFrom-Json -Depth 30
        $script:Cases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/routing-cases.json') | ConvertFrom-Json -Depth 20
        $script:AgentEvaluation = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/fixed-agent-scenarios.json') | ConvertFrom-Json -Depth 50
    }

    # Scenario: Source inventory includes distinct Task Handoff and Notion memory Skills.
    # Purpose: Keep responsibility and runtime connector dependencies separate.
    It 'InterT10_publishes_memory_without_owning_handoffs' {
        $source = Get-Content -Raw (Join-Path $script:Root 'catalog/source.json') | ConvertFrom-Json -Depth 10
        @($source.skills) | Should -Contain 'manage-notion-ai-memory'
        @($source.skills) | Should -Contain 'manage-task-handoff'
        @($script:Contract.PSObject.Properties.Name) | Should -Not -Contain 'handoff'
        $script:Contract.schemaVersion | Should -Be 4
        $script:Contract.operationScope.allowsFieldLevelHandoffOperations | Should -BeFalse
        $skillText = Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')
        $skillText | Should -Not -Match 'references/handoff-operations.md'
        $skillText | Should -Match 'references/memory-operations.md'
        $yaml = Get-Content -Raw (Join-Path $script:Skill 'agents/openai.yaml')
        $yaml | Should -Match '\$manage-notion-ai-memory'
        $yaml | Should -Match '(?m)^\s*value:\s*"notion"\s*$'
    }

    # Scenario: A confirmed explicit remember request competes with a mere inferred candidate.
    # Purpose: Distinguish safe confirmed memory from an Inbox candidate.
    It 'UnitT20_routes_confirmed_and_inferred_memory_to_distinct_records' {
        $remember = @($script:Cases.cases | Where-Object id -EQ 'explicit-remember-confirmed-fact')[0]
        $inferred = @($script:Cases.cases | Where-Object id -EQ 'inferred-memory-candidate')[0]
        $remember.memoryTarget | Should -Be $script:Contract.memory.dataSources.primary
        $remember.confidence | Should -Be 'Confirmed'
        $remember.requiresConfirmation | Should -Be $script:Contract.authority.explicitRememberNotionWriteRequiresConfirmation
        $inferred.memoryTarget | Should -Be $script:Contract.memory.dataSources.inbox
        $inferred.memoryStatus | Should -Be 'Pending'
        $inferred.confidence | Should -Be 'Inferred'
        @($script:Contract.memory.contentStates) | Should -Be @('Active','Superseded','Pending','Archived')
    }

    # Scenario: A stable key retains superseded history beside its current value.
    # Purpose: Reject only multiple current truths without dead-ending normal version history.
    It 'UnitT25_preserves_replaced_and_archived_versions_as_history' {
        $script:Contract.workflow.replacementAction | Should -Be 'preserve-old-as-Superseded'
        $script:Contract.workflow.archiveAction | Should -Be 'retain-body-mark-Archived'
        (@($script:Contract.workflow.confirmedRecallRequires) -join ',') | Should -BeExactly 'Active,Confirmed,matching-scope,verified-source'
        @($script:Contract.index.nonCurrentStates) | Should -Contain 'Superseded'
        @($script:Contract.index.nonCurrentStates) | Should -Contain 'Archived'
    }

    # Scenario: A Guest role or unknown workspace attempts a durable write.
    # Purpose: Preserve the intended Notion boundary while independent work continues.
    It 'UnitT30_fails_closed_on_unestablished_workspace_or_write_role' {
        foreach ($case in @($script:Cases.cases | Where-Object { $_.id -cin @('guest-notion-write','unknown-workspace-notion-write') })) {
            $validRole = $case.notionRole -cin @($script:Contract.workspace.authorizedRoles)
            $validRole | Should -Be $case.notionWriteAllowed
            $case.continueIndependentLocalWork | Should -BeTrue
        }
        $script:Contract.workspace.publicAccessAllowed | Should -BeFalse
        $script:Contract.trustBoundary.embeddedActionDirectivesRequireIndependentAuthorization | Should -BeTrue
    }

    # Scenario: A Dropbox file changes but its Notion index fails, or bulk schema work is requested.
    # Purpose: Avoid silently unindexed files and unrequested schema changes.
    It 'UnitT40_reports_partial_index_failure_and_limits_mutations' {
        $file = @($script:Cases.cases | Where-Object id -EQ 'dropbox-file-write')[0]
        $partial = @($script:Cases.cases | Where-Object id -EQ 'dropbox-write-index-failure')[0]
        $bulk = @($script:Cases.cases | Where-Object id -EQ 'bulk-notion-schema-change')[0]
        $file.requiresConfirmation | Should -Be $script:Contract.authority.dropboxMutationsRequireConfirmation
        ($partial.dropboxWriteSucceeded -and $partial.notionIndexWriteSucceeded) | Should -Be $partial.operationComplete
        $partial.reportUnindexed | Should -BeTrue
        $bulk.operationAllowed | Should -Be $script:Contract.operationScope.allowsBulkNotionSchemaChanges
        $script:Contract.authority.unrequestedValidationWritesAllowed | Should -BeFalse
    }
    # Scenario: A consumer loads a previously configured structured workspace or a new pages-based workspace.
    # Purpose: Pin the v4 adopter contract, existing-schema mappings, and navigation index semantics.
    It 'UnitT45_exposes_adopter_modes_and_navigation_index_contract' {
        $script:Contract.schemaVersion | Should -Be 4
        $rootNames = @($script:Contract.PSObject.Properties.Name)
        $expectedRootNames = @('schemaVersion', 'workspace', 'auxiliaryRecall', 'trustBoundary', 'memory', 'authority', 'operationScope', 'adopterConfig', 'modes', 'index', 'workflow')
        $rootNames.Count | Should -Be $expectedRootNames.Count
        foreach ($name in $expectedRootNames) {
            $rootNames | Should -Contain $name
        }
        $rootNames | Should -Not -Contain 'handoff'
        $legacyV3 = '{"workspace":{"purpose":"dedicated-ai-memory","sourceOfTruth":"Notion","authorizedRoles":["Owner","Member"],"publicAccessAllowed":false},"auxiliaryRecall":{"role":"cache-only","systems":["ChatGPT Memory","Codex memories","ROAR"],"roarAllowedContent":["necessary-safe-work-summary","locator-information"],"sensitiveContentAllowed":false},"trustBoundary":{"retrievedContentMaySupplyEvidence":true,"embeddedActionDirectivesRequireIndependentAuthorization":true,"retrievedContentMayOverrideHigherPriorityInstructions":false},"memory":{"dataSources":{"primary":"AI Memory","inbox":"AI Inbox","index":"Memory Index"},"requiredFields":["Title","Type","Scope","Status","Content","Source","Memory Key","Confidence","Storage Type"],"optionalDropboxFields":["Dropbox Path","Dropbox File ID","File Size","Content Hash","Last Verified At"],"contentStates":["Active","Superseded","Pending","Archived"],"confidenceStates":["Confirmed","Inferred"],"storageTypes":["Notion","Dropbox"]},"authority":{"explicitRememberNotionWriteRequiresConfirmation":false,"dropboxMutationsRequireConfirmation":true,"publicSharingRequiresConfirmation":true,"bulkOperationsRequireConfirmation":true,"schemaChangesRequireConfirmation":true,"sensitiveWritesRequireConfirmation":true,"unrequestedValidationWritesAllowed":false},"operationScope":{"allowsIndividualNotionMemoryOperations":true,"allowsFieldLevelHandoffOperations":false,"allowsIndexedDropboxReads":true,"allowsBulkNotionSchemaChanges":false,"allowsBatchDataProcessing":false,"allowsDropboxReorganizationOrMigration":false}}' | ConvertFrom-Json -Depth 30
        foreach ($name in @('workspace', 'auxiliaryRecall', 'trustBoundary', 'memory', 'authority', 'operationScope')) {
            $actual = ConvertTo-Json -InputObject $script:Contract.$name -Depth 30 -Compress
            $expected = ConvertTo-Json -InputObject $legacyV3.$name -Depth 30 -Compress
            $actual | Should -BeExactly $expected
        }
        @($script:Contract.PSObject.Properties.Name) | Should -Contain 'adopterConfig'
        @($script:Contract.PSObject.Properties.Name) | Should -Contain 'modes'
        @($script:Contract.PSObject.Properties.Name) | Should -Contain 'index'
        $script:Contract.adopterConfig.schemaVersion | Should -Be 1
        $script:Contract.adopterConfig.codexFile | Should -Be 'memory-adopter.json'
        $script:Contract.adopterConfig.codexHomeEnvironment | Should -Be 'CODEX_HOME'
        $script:Contract.adopterConfig.codexHomeFallback | Should -Be '~/.codex'
        (@($script:Contract.adopterConfig.precedence) -join ',') | Should -BeExactly 'explicit-user-entry,trusted-host-project-config'
        (@($script:Contract.adopterConfig.requiredFields) -join ',') | Should -BeExactly 'schemaVersion,mode,scope,boundary,index,memory,inbox'
        $script:Contract.adopterConfig.unknownVersionAction | Should -Be 'stop-affected-write'
        $script:Contract.adopterConfig.conflictAction | Should -Be 'stop-affected-write-continue-independent-work'
        $script:Contract.adopterConfig.noTitleGuessing | Should -BeTrue
        $script:Contract.modes.structured.preservesContractVersion | Should -Be 3
        $script:Contract.modes.structured.mappingKind | Should -Be 'existing-properties'
        $script:Contract.modes.structured.defaultWhenModeOmitted | Should -BeTrue
        $script:Contract.modes.structured.exactKeyField | Should -Be 'Memory Key'
        (@($script:Contract.modes.structured.requiredFields) -join ',') | Should -BeExactly 'Title,Type,Scope,Status,Content,Source,Memory Key,Confidence,Storage Type'
        (@($script:Contract.memory.requiredFields) -join ',') | Should -BeExactly 'Title,Type,Scope,Status,Content,Source,Memory Key,Confidence,Storage Type'
        (@($script:Contract.modes.structured.queryStates) -join ',') | Should -BeExactly 'Active'
        $script:Contract.modes.pages.mappingKind | Should -Be 'existing-sections'
        (@($script:Contract.modes.pages.requiredFields) -join ',') | Should -BeExactly 'Memory Key,Scope,Status,Confidence,Source,Content'
        (@($script:Contract.modes.pages.optionalFields) -join ',') | Should -BeExactly 'Title,Type,Storage Type'
        $script:Contract.modes.pages.unmappedImportedState | Should -Be 'historical-unconfirmed'
        $script:Contract.modes.pages.createsProperties | Should -BeFalse
        $script:Contract.index.role | Should -Be 'navigation-only'
        (@($script:Contract.index.requiredFields) -join ',') | Should -BeExactly 'Topic,Scope,Memory Key,Locator,Target,Status'
        (@($script:Contract.index.currentStates) -join ',') | Should -BeExactly 'Active'
        (@($script:Contract.index.nonCurrentStates) -join ',') | Should -BeExactly 'Pending,Superseded,Archived,historical-unconfirmed'
        $script:Contract.index.factsAuthority | Should -Be 'target-body-and-formal-source'
        $script:Contract.index.repairRequiresVerifiedTarget | Should -BeTrue
    }

    # Scenario: A confirmed memory is created, replaced, archived, retrieved, or only partially indexed.
    # Purpose: Keep write order, history, read-back, and index-only repair decisions stable.
    It 'UnitT50_pins_v4_write_retrieval_and_partial_index_recovery_contract' {
        (@($script:Contract.workflow.writeOrder) -join ',') | Should -BeExactly 'verify-authority-and-same-key,save-body,maintain-index,read-back'
        $script:Contract.workflow.unchangedAction | Should -Be 'skip-duplicate'
        $script:Contract.workflow.replacementAction | Should -Be 'preserve-old-as-Superseded'
        $script:Contract.workflow.archiveAction | Should -Be 'retain-body-mark-Archived'
        (@($script:Contract.workflow.confirmedRecallRequires) -join ',') | Should -BeExactly 'Active,Confirmed,matching-scope,verified-source'
        $script:Contract.workflow.partialIndexFailure.retainBody | Should -BeTrue
        (@($script:Contract.workflow.partialIndexFailure.reportFields) -join ',') | Should -BeExactly 'bodyLocator,missingIndexStep,actualError'
        $script:Contract.workflow.partialIndexFailure.resumeAction | Should -Be 'read-current-state-repair-index-only'
        $script:Contract.workflow.retrieval.exactLocatorMayBypassIndex | Should -BeTrue
        $script:Contract.workflow.retrieval.transientRecallOptional | Should -BeTrue
        $script:Contract.workflow.retrieval.boundedTopicLookup | Should -BeTrue
        $script:Contract.workflow.retrieval.mutableFactsRevalidateFormalSource | Should -BeTrue
    }
    # Scenario: An independent evaluator loads fixed connector transcripts and expected decision oracles.
    # Purpose: Protect scenario coverage and adopter fixture shape without claiming that a fixture proves Agent behavior.
    It 'UnitT55_keeps_agent_evaluation_inputs_and_oracles_complete' {
        $script:AgentEvaluation.fixtureVersion | Should -Be 1
        $script:AgentEvaluation.fixtureAuthorizesLiveWrites | Should -BeFalse
        $script:AgentEvaluation.connectorProfile | Should -Match 'Environment-specific'

        $pages = $script:AgentEvaluation.adopterProfiles.pages
        $pages.schemaVersion | Should -Be 1
        $pages.mode | Should -Be 'pages'
        $pages.scope | Should -Not -BeNullOrEmpty
        $pages.boundary.locator | Should -Not -BeNullOrEmpty
        $pages.index.section | Should -Be $script:Contract.memory.dataSources.index
        $pages.memory.section | Should -Be $script:Contract.memory.dataSources.primary
        $pages.inbox.section | Should -Be $script:Contract.memory.dataSources.inbox
        foreach ($areaName in @('index', 'memory', 'inbox')) {
            $area = $pages.$areaName
            $area.locator | Should -Not -BeNullOrEmpty
            $area.section | Should -Not -BeNullOrEmpty
            @($area.fieldMapping.PSObject.Properties.Name).Count | Should -BeGreaterThan 0
            foreach ($field in $area.fieldMapping.PSObject.Properties) {
                $field.Value | Should -Not -BeNullOrEmpty
            }
        }
        foreach ($field in @($script:Contract.index.requiredFields)) {
            @($pages.index.fieldMapping.PSObject.Properties.Name) | Should -Contain $field
        }
        foreach ($field in @($script:Contract.modes.pages.requiredFields)) {
            @($pages.memory.fieldMapping.PSObject.Properties.Name) | Should -Contain $field
            @($pages.inbox.fieldMapping.PSObject.Properties.Name) | Should -Contain $field
        }

        $pageIndexFields = @($pages.index.fieldMapping.PSObject.Properties.Name) -join ','
        $pageIndexFields | Should -BeExactly 'Topic,Scope,Memory Key,Locator,Target,Status'
        $pageInboxFields = @($pages.inbox.fieldMapping.PSObject.Properties.Name) -join ','
        $pageInboxFields | Should -BeExactly 'Memory Key,Scope,Status,Confidence,Source,Content'
        $pageMemoryExpected = @($script:Contract.modes.pages.requiredFields) + @($script:Contract.modes.pages.optionalFields)
        (@($pages.memory.fieldMapping.PSObject.Properties.Name) -join ',') | Should -BeExactly ($pageMemoryExpected -join ',')

        $structured = $script:AgentEvaluation.adopterProfiles.structured
        $structured.schemaVersion | Should -Be 1
        $structured.mode | Should -Be 'structured'
        $structured.scope | Should -Not -BeNullOrEmpty
        $structured.boundary.locator | Should -Not -BeNullOrEmpty
        foreach ($areaName in @('index', 'memory', 'inbox')) {
            $area = $structured.$areaName
            $area.locator | Should -Match '^collection://'
            $area.section | Should -Be ''
            @($area.fieldMapping.PSObject.Properties.Name).Count | Should -BeGreaterThan 0
            foreach ($field in $area.fieldMapping.PSObject.Properties) {
                $field.Value | Should -Not -BeNullOrEmpty
            }
        }
        $structuredRequiredFields = @($script:Contract.modes.structured.requiredFields) -join ','
        (@($structured.memory.fieldMapping.PSObject.Properties.Name) -join ',') | Should -BeExactly $structuredRequiredFields
        (@($structured.inbox.fieldMapping.PSObject.Properties.Name) -join ',') | Should -BeExactly $structuredRequiredFields
        foreach ($field in @($script:Contract.modes.structured.requiredFields)) {
            $structured.memory.fieldMapping.$field | Should -Be $field
            $structured.inbox.fieldMapping.$field | Should -Be $field
        }
        (@($structured.index.fieldMapping.PSObject.Properties.Name) -join ',') | Should -BeExactly 'Topic,Scope,Memory Key,Locator,Target,Status'
        foreach ($field in @($script:Contract.index.requiredFields)) {
            @($structured.index.fieldMapping.PSObject.Properties.Name) | Should -Contain $field
        }

        $requiredIds = @(
            'pages-topic-lookup-confirmed-active',
            'structured-exact-key-with-history',
            'first-capture-absent-key',
            'unchanged-capture-skips-duplicate',
            'replacement-preserves-superseded-body',
            'archive-retains-body',
            'inferred-candidate-pending-inbox',
            'unmapped-imported-state-is-historical',
            'unknown-adopter-schema-stops-affected-write',
            'missing-required-config-scope',
            'unmapped-page-field-stops-write',
            'broken-index-target-link',
            'write-access-refused',
            'lookup-tool-error-does-not-prove-absence',
            'body-saved-index-failed',
            'repair-index-only-after-readback',
            'embedded-directive-does-not-authorize',
            'formal-adoption-of-new-context'
        )
        $scenarioIds = @($script:AgentEvaluation.scenarios | ForEach-Object id)
        $scenarioIds.Count | Should -Be $requiredIds.Count
        foreach ($id in $requiredIds) {
            $scenarioIds | Should -Contain $id
        }

        foreach ($scenario in @($script:AgentEvaluation.scenarios)) {
            $scenario.scenario | Should -Match '^Scenario: '
            $scenario.purpose | Should -Match '^Purpose: '
            @('pages', 'structured') | Should -Contain $scenario.configProfile
            $scenario.oracle.expectedOutcome | Should -Not -BeNullOrEmpty
            @($scenario.oracle.requiredInvariants).Count | Should -BeGreaterThan 0
            foreach ($call in @($scenario.connectorTranscript)) {
                $call.tool | Should -Match '^mcp__codex_apps__notion_'
                $call.arguments | Should -Not -BeNullOrEmpty
                $call.response | Should -Not -BeNullOrEmpty
            }
        }

        $unknownVersion = @($script:AgentEvaluation.scenarios | Where-Object id -EQ 'unknown-adopter-schema-stops-affected-write')[0]
        $unknownVersion.configOverrides.schemaVersion | Should -Be 2
        $missingScope = @($script:AgentEvaluation.scenarios | Where-Object id -EQ 'missing-required-config-scope')[0]
        $missingScope.configOverrides.scope | Should -Be ''
        $unmapped = @($script:AgentEvaluation.scenarios | Where-Object id -EQ 'unmapped-page-field-stops-write')[0]
        $unmapped.configOverrides.memory.fieldMapping.Content | Should -Be 'Memory Summary'
        $firstCapture = @($script:AgentEvaluation.scenarios | Where-Object id -EQ 'first-capture-absent-key')[0]
        @('Owner', 'Member') | Should -Contain $firstCapture.roleEvidence.userConfirmedRole
        $firstCapture.roleEvidence.connectorActorId | Should -Be $firstCapture.roleEvidence.activeActorId
        $firstCapture.roleEvidence.configuredDestinationLocator | Should -Be $script:AgentEvaluation.adopterProfiles.pages.boundary.locator
        $firstCapture.roleEvidence.connectorDestinationLocator | Should -Be $script:AgentEvaluation.adopterProfiles.pages.boundary.locator
        $firstCapture.roleEvidence.actorAndDestinationMatch | Should -BeTrue
        $actorCall = @($firstCapture.connectorTranscript | Where-Object tool -EQ 'mcp__codex_apps__notion_notion_get_users')[0]
        $actorCall.arguments.user_id | Should -Be 'self'
        $actorCall.response.structuredContent.results[0].id | Should -Be $firstCapture.roleEvidence.connectorActorId
        $boundaryCall = @($firstCapture.connectorTranscript | Where-Object { $_.tool -EQ 'mcp__codex_apps__notion_fetch' -and $_.arguments.id -EQ $script:AgentEvaluation.adopterProfiles.pages.boundary.locator })[0]
        $boundaryCall.response.structuredContent.page_id | Should -Be '00000000-0000-4000-8000-000000000001'
        $denied = @($script:AgentEvaluation.scenarios | Where-Object id -EQ 'write-access-refused')[0]
        $denied.roleEvidence | Should -BeNullOrEmpty
        $firstCapture.userInput | Should -Match 'I confirm I am a Member'
    }
}
