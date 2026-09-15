# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'manage-notion-ai-memory durable memory contract' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Skill = Join-Path $script:Root 'skills/manage-notion-ai-memory'
        $script:Contract = Get-Content -Raw (Join-Path $script:Skill 'references/notion-memory-contract.json') | ConvertFrom-Json -Depth 30
        $script:Cases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/routing-cases.json') | ConvertFrom-Json -Depth 20
    }

    # Scenario: Source inventory includes distinct Task Handoff and Notion memory Skills.
    # Purpose: Keep responsibility and runtime connector dependencies separate.
    It 'InterT10_publishes_memory_without_owning_handoffs' {
        $source = Get-Content -Raw (Join-Path $script:Root 'catalog/source.json') | ConvertFrom-Json -Depth 10
        @($source.skills) | Should -Contain 'manage-notion-ai-memory'
        @($source.skills) | Should -Contain 'manage-task-handoff'
        @($script:Contract.PSObject.Properties.Name) | Should -Not -Contain 'handoff'
        $script:Contract.schemaVersion | Should -Be 3
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
}
