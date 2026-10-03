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

    # Scenario: the consumer selects its reviewed immutable central authority snapshot.
    # Purpose: keep the archive identity and required member inventory bound to that snapshot.
    It 'UnitT10_pins_one_immutable_authority_snapshot_and_required_file_inventory' {
        Test-Path -LiteralPath $script:AdapterPath -PathType Leaf | Should -BeTrue
        $adapter = Get-Content -LiteralPath $script:AdapterPath -Raw | ConvertFrom-Json

        $adapter.schemaVersion | Should -Be 1
        $adapter.standardVersion | Should -Be 'v1'
        $adapter.authority.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $adapter.authority.commit | Should -Be '51399617ddebe21656fe4265a8d9ad116a943583'
        $adapter.authority.archiveSha256 | Should -Be 'b115762de7d4da6f0f95143e1853bd3822fe224d2e673539ace3f480df6ef50d'
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
        @($adapter.authority.files.path) | Should -Contain 'docs/standards/pr12-source-merge-adoption.json'
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

    # Scenario: a PR or main push enters the sole supported Windows validation workflow.
    # Purpose: retire duplicate Ubuntu status paths while proving the official runtime and exact result.
    It 'UnitT15_RoutesPrAndMainThroughOneWindowsLatestStableCanonicalValidator' {
        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $workflow | Should -Match 'scripts/Validate\.ps1'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $workflow | Should -Match 'uses:\s*\*checkout-action-reference'
        $workflow | Should -Match 'actions/setup-go@[0-9a-f]{40}'
        $workflow | Should -Match 'actions/setup-node@[0-9a-f]{40}'
        $workflow | Should -Match "node-version: '24'"
        $workflow | Should -Match 'Get-Command npm\.cmd -CommandType Application'
        $workflow | Should -Match 'APPROVED_NPM_PATH'
        $workflow | Should -Match 'Expected npm 11 lockfile semantics'
        $workflow | Should -Match '(?m)^  pull_request:\s*$'
        $workflow | Should -Match '(?m)^  push:\s*$'
        $workflow | Should -Match '(?m)^    runs-on: windows-latest\s*$'
        $workflow | Should -Match '(?m)^    timeout-minutes: [1-9][0-9]*\s*$'
        $workflow | Should -Match 'aka\.ms/powershell-release\?tag=stable'
        $workflow | Should -Match 'api\.github\.com/repos/PowerShell/PowerShell/releases/tags/\$tag'
        $workflow | Should -Match '\$asset\.digest'
        $workflow | Should -Match 'Get-FileHash'
        $workflow | Should -Match 'POWERSHELL_RUNTIME'
        $workflow | Should -Match '\$env:PATH = "\$\(Split-Path -Parent \$env:POWERSHELL_RUNTIME\);\$env:PATH"'
        $workflow | Should -Not -Match 'GITHUB_PATH'
        $workflow | Should -Match "NPM_CONFIG_PREFIX.*'Process'"
        $workflow | Should -Match "'C:\\npm\\prefix'"
        $workflow | Should -Match '\$runtimeEvidence\.version -cne \$expectedVersion'
        $workflow | Should -Match 'if \(\$LASTEXITCODE -ne 0\)'
        $workflow | Should -Match 'Remove-Item -LiteralPath \$ownedRoot -Recurse -Force'
        $workflow | Should -Not -Match 'ubuntu-latest|pull_request_target|checks: write'
        $workflow | Should -Not -Match '(?m)^  (?:repository-contract|skill-validator|skill-tools):'
        $workflow | Should -Not -Match 'source_conformance:|SourceMergeExceptionReview|ProtectedSourceMergeCheck'
        $workflow | Should -Not -Match '(?m)^\s*(Install-Module|npm install|go install|pip install)\b'
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/skill-validator.yml') | Should -BeFalse
    }

    # Scenario: the per-run temporary directory already exists before the installer starts.
    # Purpose: ensure the always-run cleanup never deletes files this run did not create.
    It 'UnitT16_PreservesPreexistingDirectoryWhenRunOwnershipWasNotRecorded' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $cleanupStep = ($workflow -split [regex]::Escape('      - name: Clean only this run''s temporary files'), 2)[1]
        $cleanupBody = ($cleanupStep -split '        run: \|\r?\n', 2)[1]
        $cleanupScript = (($cleanupBody -split '\r?\n') | ForEach-Object {
            if ($_.StartsWith('          ')) { $_.Substring(10) } else { $_ }
        }) -join "`n"
        $cleanupScript | Should -Not -BeNullOrEmpty

        $savedEnvironment = @{
            RUNNER_TEMP = $env:RUNNER_TEMP
            GITHUB_RUN_ID = $env:GITHUB_RUN_ID
            GITHUB_RUN_ATTEMPT = $env:GITHUB_RUN_ATTEMPT
            RUN_OWNED_ROOT = $env:RUN_OWNED_ROOT
        }
        try {
            $env:RUNNER_TEMP = $TestDrive
            $env:GITHUB_RUN_ID = '217001'
            $env:GITHUB_RUN_ATTEMPT = '1'
            $collision = Join-Path $TestDrive 'skill-general-217001-1'
            New-Item -ItemType Directory -Path $collision | Out-Null
            $sentinel = Join-Path $collision 'preexisting.txt'
            Set-Content -LiteralPath $sentinel -Value 'keep'

            $env:RUN_OWNED_ROOT = $null
            & ([scriptblock]::Create($cleanupScript))
            Test-Path -LiteralPath $sentinel | Should -BeTrue

            $env:RUN_OWNED_ROOT = $collision
            & ([scriptblock]::Create($cleanupScript))
            Test-Path -LiteralPath $collision | Should -BeFalse
        }
        finally {
            foreach ($name in $savedEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
            }
        }
    }

    # Scenario: the trusted base driver evaluates the immutable PR candidate under the single normal check.
    # Purpose: preserve source binding without a historical PR-specific success exception.
    It 'InterT20_binds_base_driver_and_exact_pr_head_without_status_mirrors' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'EXPECTED_SOURCE_SHA:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'git -C \$candidate merge-base \$env:PULL_REQUEST_BASE_SHA HEAD'
        $workflow | Should -Match "working-directory: driver"
        $workflow | Should -Match '\$driverArgs = @\('
        $workflow | Should -Match '& \$env:POWERSHELL_RUNTIME -NoProfile -NonInteractive -File \./scripts/Validate\.ps1 @driverArgs'
        $workflow | Should -Match 'candidate\.sourceRevision -cne \$env:EXPECTED_SOURCE_SHA'
        $workflow | Should -Match 'report\.state -cne ''PASSED'''
        $workflow | Should -Match 'persist-credentials:\s*false'
    }

    It 'keeps public validation documentation on the canonical entry point' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Raw
        $readme | Should -Match 'scripts/Validate\.ps1'
        $readme | Should -Not -Match 'scripts/(?:Invoke-StandardValidation|Test-SkillGeneral)\.ps1'
        $readme | Should -Not -Match '(?i)\b(?:Invoke-Pester|pytest|skill-validator|skill-tools|skillspector)\b'
    }
}
