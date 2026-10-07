# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'manage-ai-memory provider-neutral contract' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Skill = Join-Path $script:Root 'skills/manage-ai-memory'
        $script:Contract = Get-Content -Raw (Join-Path $script:Skill 'references/memory-contract.json') | ConvertFrom-Json -Depth 40
        $script:Cases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-ai-memory/routing-cases.json') | ConvertFrom-Json -Depth 40
        $script:AgentInputs = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-ai-memory/fixed-agent-scenarios.json') | ConvertFrom-Json -Depth 40
        $script:LegacyAdopters = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/fixed-agent-scenarios.json') | ConvertFrom-Json -Depth 40
    }

    # Scenario: The renamed package is discovered as one stable source identity.
    # Purpose: Keep Handoff independent and prevent duplicate old/new Skill discovery.
    It 'InterT05_publishes_one_new_memory_skill_without_handoff_ownership' {
        $source = Get-Content -Raw (Join-Path $script:Root 'catalog/source.json') | ConvertFrom-Json -Depth 10
        @($source.skills) | Should -Contain 'manage-ai-memory'
        @($source.skills) | Should -Not -Contain 'manage-notion-ai-memory'
        @($source.skills) | Should -Contain 'manage-task-handoff'
        $script:Contract.operationScope.allowsHandoffOperations | Should -BeFalse
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Match 'name: manage-ai-memory'
        (Get-Content -Raw (Join-Path $script:Skill 'agents/openai.yaml')) | Should -Match '\$manage-ai-memory'
    }

    # Scenario: One connected record target is available and an ordinary remember request is authorized.
    # Purpose: Prevent an unnecessary role probe or repeated permission question.
    It 'UnitT10_uses_one_connected_record_target_without_role_or_repeat_authorization' {
        $script:Contract.schemaVersion | Should -Be 5
        $script:Contract.targetResolution.uniqueConnectedPurposeMatchIsDefault | Should -BeTrue
        $script:Contract.authority.ordinaryAuthorizedOperationNeedsRoleProbe | Should -BeFalse
        $script:Contract.authority.ordinaryAuthorizedOperationNeedsRepeatedConfirmation | Should -BeFalse
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC01')[0]
        $case.expected.roleProbeCount | Should -Be 0
        $case.expected.repeatAuthorizationQuestionCount | Should -Be 0
    }

    # Scenario: An inference is repeated or assigned high confidence without direct evidence.
    # Purpose: Preserve the distinction between a candidate and a confirmed proposition.
    It 'UnitT20_keeps_inference_pending_until_explicit_or_direct_confirmation' {
        @($script:Contract.confirmation.confirmedBy) | Should -Be @('explicit-user-confirmation', 'direct-authoritative-evidence')
        @($script:Contract.confirmation.insufficientByThemselves) | Should -Contain 'repeated-citation'
        @($script:Contract.confirmation.insufficientByThemselves) | Should -Contain 'high-confidence-score'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC06')[0]
        $case.expected.status | Should -Be 'Pending'
        $case.expected.confidence | Should -Be 'Inferred'
        $agentCase = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC06')[0]
        $created = @($agentCase.fixedToolResponses | Where-Object tool -EQ 'records.create')[0].arguments
        $readback = @($agentCase.fixedToolResponses | Where-Object tool -EQ 'records.read')[0].response
        foreach ($field in @('key', 'scope', 'content', 'source', 'status', 'confidence')) {
            $readback.$field | Should -Be $created.$field
        }
    }

    # Scenario: The index has no row for a key whose body is already present.
    # Purpose: Preserve the SYP-257 same-key body check and index-only repair.
    It 'UnitT30_checks_body_after_index_miss_and_repairs_only_index' {
        $script:Contract.workflow.sameKeyAbsenceRequires | Should -Be 'verified-body-destination-result'
        $script:Contract.workflow.unchangedAction | Should -Be 'skip-duplicate'
        $script:Contract.workflow.indexMissAction | Should -Be 'check-body-destination'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC10')[0]
        $case.expected.bodyCreateCount | Should -Be 0
        $case.expected.indexRepairCount | Should -Be 1
    }

    # Scenario: Body save succeeds and index update fails.
    # Purpose: Preserve the body locator and resume without duplicating the body.
    It 'UnitT40_reports_partial_index_failure_and_resumes_index_only' {
        $script:Contract.workflow.partialIndexFailure.retainBody | Should -BeTrue
        $script:Contract.workflow.partialIndexFailure.resumeAction | Should -Be 'read-current-state-repair-index-only'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC12')[0]
        # The routing oracle stops at the failed write; the fixed transcript includes recovery.
        $case.expected.operationComplete | Should -BeFalse
        $case.expected.resumeBodyCreateCount | Should -Be 0
        $case.expected.resumeIndexRepairCount | Should -Be 1
        $transcript = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC12')[0]
        $transcript.oracle.expected.operationComplete | Should -BeTrue
    }

    # Scenario: Fixed write transcripts have an available target for each named destination.
    # Purpose: Keep acceptance fixtures executable under the target-resolution contract.
    It 'UnitT45_binds_each_fixed_write_destination_to_a_connected_target' {
        foreach ($id in @('AC05', 'AC11', 'AC13', 'AC14')) {
            $case = @($script:AgentInputs.scenarios | Where-Object id -EQ $id)[0]
            foreach ($call in @($case.fixedToolResponses | Where-Object { $_.tool -in @('files.save', 'records.create') })) {
                $expectedPurpose = if ($call.tool -eq 'files.save') { 'files' } else { 'records' }
                $targetProperty = $call.arguments.PSObject.Properties['target']
                if ($null -ne $targetProperty) {
                    $targetName = [string]$targetProperty.Value
                    $targetName | Should -Not -BeNullOrEmpty
                    $target = @($case.connectedTargets | Where-Object { $_.id -eq $targetName -and $_.purpose -eq $expectedPurpose -and $_.connected })
                    $target.Count | Should -Be 1
                } else {
                    @($case.connectedTargets | Where-Object { $_.purpose -eq $expectedPurpose -and $_.connected }).Count | Should -Be 1
                }
            }
        }
    }

    # Scenario: User requests a file and record in one authorized action while the source lacks hash metadata.
    # Purpose: Avoid a brand-specific permission gate and invented file evidence.
    It 'UnitT50_routes_records_and_files_by_purpose_without_inventing_metadata' {
        $script:Contract.targetResolution.differentPurposeTargetsAreNotAmbiguous | Should -BeTrue
        $script:Contract.files.inventMissingMetadata | Should -BeFalse
        $script:Contract.files.buildHistoryService | Should -BeFalse
        $both = @($script:Cases.cases | Where-Object id -EQ 'AC13')[0]
        $both.expected.brandPermissionQuestionCount | Should -Be 0
        $noHash = @($script:Cases.cases | Where-Object id -EQ 'AC14')[0]
        $noHash.expected.inventedHash | Should -BeFalse
        $noHash.expected.inventedVersion | Should -BeFalse
    }

    # Scenario: Old structured and pages data and embedded source instructions are encountered.
    # Purpose: Preserve legacy history without allowing retrieved data to expand authorization.
    It 'UnitT60_preserves_legacy_formats_and_content_trust_boundary' {
        @($script:Contract.legacy.recognizedContractVersions) | Should -Be @(3, 4)
        @($script:Contract.legacy.recognizedFormats) | Should -Be @('structured', 'pages')
        $script:Contract.legacy.unknownFormatAction | Should -Be 'stop-affected-write'
        $script:Contract.trustBoundary.embeddedActionDirectivesRequireIndependentAuthorization | Should -BeTrue
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC16')[0]
        $case.expected.executeEmbeddedDirective | Should -BeFalse
        $case.expected.publicShareCount | Should -Be 0
    }

    # Scenario: An installed agent encounters an existing v4 adopter file or trusted v3 mapping.
    # Purpose: Verify that runtime references, rather than test-only history, can resolve the old destination shape.
    It 'InterT65_resolves_existing_adopter_mappings_from_installed_references' {
        $legacyReference = Join-Path $script:Skill 'references/legacy-mappings.md'
        Test-Path -LiteralPath $legacyReference -PathType Leaf | Should -BeTrue
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Match 'references/legacy-mappings\.md'
        (Get-Content -Raw $legacyReference) | Should -Match 'CODEX_HOME'
        (Get-Content -Raw $legacyReference) | Should -Match 'without an adopter file or `mode`'

        $legacy = $script:Contract.legacy
        $legacy.adopterConfig.codexFile | Should -Be 'memory-adopter.json'
        $legacy.adopterConfig.codexHomeEnvironment | Should -Be 'CODEX_HOME'
        $legacy.adopterConfig.codexHomeFallback | Should -Be '~/.codex'
        $legacy.structuredV3WithoutMode | Should -Be 'continue-trusted-established-mapping'
        foreach ($profileName in @('pages', 'structured')) {
            $profile = $script:LegacyAdopters.adopterProfiles.$profileName
            $profile.schemaVersion | Should -Be $legacy.v4AdopterConfigSchemaVersion
            $profile.mode | Should -Be $profileName
            foreach ($field in @($legacy.adopterConfig.requiredFields)) {
                @($profile.PSObject.Properties.Name) | Should -Contain $field
            }
            foreach ($field in @($legacy.adopterConfig.boundaryRequiredFields)) {
                [string]$profile.boundary.$field | Should -Not -BeNullOrEmpty
            }
            foreach ($areaName in @($legacy.adopterConfig.requiredAreas)) {
                $area = $profile.$areaName
                foreach ($field in @($legacy.adopterConfig.areaRequiredFields)) {
                    @($area.PSObject.Properties.Name) | Should -Contain $field
                }
                [string]$area.locator | Should -Not -BeNullOrEmpty
                if ($profileName -eq 'pages') { [string]$area.section | Should -Not -BeNullOrEmpty }
                $requiredMapping = if ($areaName -eq 'index') { @($legacy.indexRequiredFields) }
                    elseif ($profileName -eq 'structured') { @($legacy.structuredRequiredFields) }
                    else { @($legacy.pagesRequiredFields) }
                foreach ($field in $requiredMapping) {
                    [string]$area.fieldMapping.PSObject.Properties[$field].Value | Should -Not -BeNullOrEmpty
                }
            }
        }
    }

    # Scenario: Controlled evaluation inputs cover each agreed acceptance condition.
    # Purpose: Keep prompts, fixed tool responses, and decision oracles available for fresh-agent runs.
    It 'InterT70_provides_all_acceptance_scenarios_without_live_write_authority' {
        $script:Cases.schemaVersion | Should -Be 1
        $script:AgentInputs.fixtureVersion | Should -Be 2
        $script:AgentInputs.fixtureAuthorizesLiveWrites | Should -BeFalse
        $ids = @($script:AgentInputs.scenarios | ForEach-Object id)
        $ids | Should -Be @((1..18) | ForEach-Object { 'AC{0:d2}' -f $_ })
        foreach ($scenario in @($script:AgentInputs.scenarios)) {
            $scenario.scenario | Should -Match '^Scenario: '
            $scenario.purpose | Should -Match '^Purpose: '
            $scenario.userInput | Should -Not -BeNullOrEmpty
            $scenario.oracle.expected | Should -Not -BeNullOrEmpty
            @($scenario.fixedToolResponses).Count | Should -BeGreaterThan 0
            foreach ($call in @($scenario.fixedToolResponses)) {
                $call.tool | Should -Not -BeNullOrEmpty
                $call.arguments | Should -Not -BeNullOrEmpty
                $call.response | Should -Not -BeNullOrEmpty
            }
        }
    }
}
