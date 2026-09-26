# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Skill-General Standard v1 reference implementation' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:SourceInventoryPath = Join-Path $script:RepositoryRoot 'catalog/source.json'
        $script:AdapterPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
        $script:CanonicalValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
    }

    It 'uses the canonical skills source root and schema v2 inventory' {
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'skills') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.agents/skills') | Should -BeFalse
        Test-Path -LiteralPath $script:SourceInventoryPath -PathType Leaf | Should -BeTrue

        $inventory = Get-Content -LiteralPath $script:SourceInventoryPath -Raw | ConvertFrom-Json
        @($inventory.PSObject.Properties.Name) | Should -Be @(
            'schemaVersion', 'sourceId', 'repository', 'skillsRoot', 'skills'
        )
        $inventory.schemaVersion | Should -Be 2
        $inventory.sourceId | Should -Be 'general'
        $inventory.repository | Should -Be 'https://github.com/SyuanTsai/Skill-General.git'
        $inventory.skillsRoot | Should -Be 'skills'
        @($inventory.skills) | Should -Be @(
            'investigate-datadog-logs'
            'manage-notion-ai-memory'
            'manage-task-handoff'
            'plan-production-change'
            'review-agent-skills'
            'verify-data-access-performance'
        )
    }

    It 'pins one immutable authority snapshot and required file inventory' {
        Test-Path -LiteralPath $script:AdapterPath -PathType Leaf | Should -BeTrue
        $adapter = Get-Content -LiteralPath $script:AdapterPath -Raw | ConvertFrom-Json

        $adapter.schemaVersion | Should -Be 1
        $adapter.standardVersion | Should -Be 'v1'
        $adapter.authority.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $adapter.authority.commit | Should -Be 'cb5673ba2fd4a68ccaf917db43673937bec0677a'
        $adapter.authority.archiveSha256 | Should -Be 'caf931ed55ad1ae923022eaf3137ae53eefce7b5e2c80a5708511d623a3a860b'
        @($adapter.PSObject.Properties.Name) | Should -Not -Contain 'security'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/README.md'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/managed-skill-lifecycle.md'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/skill-repository-standard.md'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/skill-repository-review-matrix.md'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/upstream-interoperability.md'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/validation-security-gate.json'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/validation-toolchain.json'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/schemas/source-inventory-v2.schema.json'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/schemas/openai-agent-metadata.schema.json'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/schemas/validation-security-gate-v1.schema.json'
        @($adapter.authority.files.path) | Should -Contain 'scripts/Invoke-StandardAuthorityGate.ps1'
        @($adapter.authority.files.path) | Should -Contain 'scripts/Resolve-StandardValidationTool.ps1'
        @($adapter.authority.files.path) | Should -Contain 'scripts/Resolve-PythonWheelClosure.py'
        @($adapter.authority.files.path) | Should -Contain 'scripts/Invoke-StandardValidation.ps1'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json'
        @($adapter.authority.files.path) | Should -Contain 'scripts/StandardSemanticBridge.psm1'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/standard-validation-contract-v1.json'
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/schemas/standard-validation-adapter-v1.schema.json'
        @($adapter.authority.files | Where-Object { $_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count | Should -Be 0
        $adapter.PSObject.Properties.Name | Should -Not -Contain 'deviations'
    }

    It 'exposes one canonical validator for local and CI execution' {
        Test-Path -LiteralPath $script:CanonicalValidatorPath -PathType Leaf | Should -BeTrue
        $validator = Get-Content -LiteralPath $script:CanonicalValidatorPath -Raw
        $validator | Should -Match 'Invoke-StandardValidation\.ps1'
        $validator | Should -Match '-DevelopmentHarness'
        $validator | Should -Match 'standard-validation-adapter\.json'
        $validator | Should -Match 'repository-test-general'
        $validator | Should -Match 'repository-test-pester'
        $validator | Should -Match "id = 'repository-test-general'; kind = 'general'"
        $validator | Should -Match "id = 'repository-test-pester'; kind = 'pester'"
        $validator | Should -Not -Match 'deviations\s*='
    }

    It 'keeps semantic v1 and development-harness forwarding while exposing v2 paths and key identity' {
        $validator = Get-Content -LiteralPath $script:CanonicalValidatorPath -Raw
        $validator | Should -Match '-DevelopmentHarness'
        $validator | Should -Match 'if \(\$SemanticConsent\) \{ \$centralRunnerArgs \+= ''-SemanticConsent'' \}'
        foreach ($parameter in @(
            'SemanticProvider',
            'SemanticPurpose',
            'SemanticScope',
            'SemanticEvidencePath',
            'SemanticConsentRequestPath',
            'SemanticConsentDecisionPath',
            'SemanticPublicKeyPath',
            'SemanticPublicKeyId'
        )) {
            $pair = '@(' + "'" + '-' + $parameter + "', " + '$' + $parameter + ')'
            $validator | Should -Match ([regex]::Escape($pair))
        }
    }

    It 'routes CI through the canonical validator without a second installer policy' {
        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $workflow | Should -Match 'scripts/Validate\.ps1'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $workflow | Should -Match 'uses:\s*\*checkout-action-reference'
        $workflow | Should -Match 'actions/setup-go@[0-9a-f]{40}'
        $workflow | Should -Match 'id: source-conformance'
        $workflow | Should -Match 'if: \$\{\{ always\(\) \}\}'
        $workflow | Should -Match 'source_conformance: \$\{\{ steps\.source-conformance\.outputs\.status \}\}'
        $workflow | Should -Match '\$source\.sourceRevision -ceq \$env:EXPECTED_SOURCE_SHA'
        $workflow | Should -Match '\$source\.status -ceq ''passed'''
        $workflow | Should -Match '\$report\.contract -ceq ''standard-validation-contract-v1'''
        $workflow | Should -Match 'if \[\[ "\$result" != ''passed'' \]\]; then'
        $workflow | Should -Not -Match '(?m)^\s*(Install-Module|npm install|go install|pip install)\b'
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/skill-validator.yml') | Should -BeFalse

        foreach ($context in @('repository-contract', 'skill-validator', 'skill-tools')) {
            $pattern = "(?ms)^\s+{0}:\s+name:\s+{0}.*?needs:\s+- canonical-validation.*?{1}" -f `
                [regex]::Escape($context),
                [regex]::Escape("needs['canonical-validation'].outputs.source_conformance")
            $workflow | Should -Match $pattern
        }
        $workflow | Should -Not -Match '(?ms)repository-contract:.*?Run .*skill-validator|skill-validator:.*?Run .*skill-tools'
    }

    # Scenario: a protected base workflow evaluates the exact PR12 head while the source branch keeps its approved SHA.
    # Purpose: bind any merge-only check to trusted workflow code and the event's immutable source revision.
    It 'InterT20_binds_protected_source_check_to_base_driver_and_exact_pr_head' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'EXPECTED_SOURCE_SHA:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'git -C \$candidate merge-base \$env:PULL_REQUEST_BASE_SHA HEAD'
        $workflow | Should -Match "working-directory: driver"
        $workflow | Should -Match '\$driverArgs = @\{'
        $workflow | Should -Not -Match '\$driverArgs = @\('
        $workflow | Should -Match '& \./scripts/Validate\.ps1 @driverArgs'
        $workflow | Should -Match '66c466540480306c7f5346338d70d036bddb4930'
        $workflow | Should -Match 'sourceMergeDecision'
        $workflow | Should -Match 'releaseEligible -eq \$false'
        $workflow | Should -Match 'persist-credentials:\s*false'
    }

    It 'keeps public validation documentation on the canonical entry point' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Raw
        $readme | Should -Match 'scripts/Validate\.ps1'
        $readme | Should -Not -Match 'scripts/(?:Invoke-StandardValidation|Test-SkillGeneral)\.ps1'
        $readme | Should -Not -Match '(?i)\b(?:Invoke-Pester|pytest|skill-validator|skill-tools|skillspector)\b'
    }
}
