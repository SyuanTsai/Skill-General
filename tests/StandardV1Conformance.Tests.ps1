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
        $adapter.authority.commit | Should -Be 'ea1d368ac7b36f838ce4c3af363972c90fa12930'
        $adapter.authority.archiveUrl | Should -Be 'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/ea1d368ac7b36f838ce4c3af363972c90fa12930'
        $adapter.authority.archiveSha256 | Should -Be 'c5a43ef70bf9ed813df2b8ae206b7c1b661caa013744e1098df87ccc3d274653'
        @($adapter.authority.files).Count | Should -Be 26
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
    # Purpose: preserve the required context names as projections while proving the official runtime and exact result.
    It 'UnitT15_RoutesPrAndMainThroughOneWindowsLatestStableCanonicalValidator' {
        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $workflow | Should -Match 'scripts/Validate\.ps1'
        $scriptPathPattern = '(?i)(?<![A-Za-z0-9_.-])(?:\.[/\\]|[A-Za-z0-9_.-]+[/\\])+[A-Za-z0-9_.-]+\.(?:ps1|psm1|py|js|sh|cmd|bat|exe)(?![A-Za-z0-9_.-])'
        @([regex]::Matches($workflow, $scriptPathPattern) | Where-Object { $_.Value -notmatch '(?i)(?:^|[/\\])Validate\.ps1$' }).Count | Should -Be 0
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $workflow | Should -Match 'uses:\s*\*checkout-action-reference'
        $workflow | Should -Match 'actions/setup-go@[0-9a-f]{40}'
        $workflow | Should -Match 'actions/setup-node@[0-9a-f]{40}'
        $workflow | Should -Match 'if: \$\{\{ steps\.authority-mode\.outputs\.validation_mode == \x27legacy\x27 \}\}'
        $workflow | Should -Match 'ref: ea1d368ac7b36f838ce4c3af363972c90fa12930'
        $workflow | Should -Match 'if: \$\{\{ steps\.authority-mode\.outputs\.validation_mode == \x27core\x27 \}\}'
        $workflow | Should -Match 'Install-PSResource -Name Pester -Version \x27{1,2}6\.2\.0\x27{1,2}'
        $workflow | Should -Match "node-version: '24'"
        $workflow | Should -Match 'Get-Command npm\.cmd -CommandType Application'
        $workflow | Should -Match 'APPROVED_NPM_PATH'
        $workflow | Should -Match 'Expected npm 11 lockfile semantics'
        $workflow | Should -Match '(?m)^  pull_request:\s*$'
        $workflow | Should -Match '(?m)^  push:\s*$'
        $workflow | Should -Match '(?m)^    runs-on: windows-latest\s*$'
        $workflow | Should -Match '(?m)^    timeout-minutes: [1-9][0-9]*\s*$'
        $workflow | Should -Match "Invoke-WebRequest -Uri \('https://aka\.ms/powershell-' \+ 'release\?tag=stable'\)"
        $workflow | Should -Match 'Invoke-RestMethod -Uri \("https://api\.github\.com/repos/PowerShell/PowerShell/" \+ "releases/tags/\$tag"\)'
        $workflow | Should -Match '\$asset\.digest'
        $workflow | Should -Match 'Get-FileHash'
        $workflow | Should -Match 'POWERSHELL_RUNTIME'
        $workflow | Should -Match '\x27-AuthorityRepositoryRoot\x27, \(Join-Path \$env:GITHUB_WORKSPACE \x27authority\x27\)'
        $workflow | Should -Match '\x27-TrustedToolRoot\x27, \(Split-Path -Parent \$env:POWERSHELL_RUNTIME\)'
        $workflow | Should -Match '\$env:PATH = "\$\(Split-Path -Parent \$env:POWERSHELL_RUNTIME\);\$env:PATH"'
        $workflow | Should -Not -Match 'GITHUB_PATH'
        $workflow | Should -Match "NPM_CONFIG_PREFIX.*'Process'"
        $workflow | Should -Match "'C:\\npm\\prefix'"
        $workflow | Should -Match '\$runtimeEvidence\.version -cne \$expectedVersion'
        $workflow | Should -Match 'if \(\$LASTEXITCODE -ne 0\)'
        $workflow | Should -Match 'Remove-Item -LiteralPath \$ownedRoot -Recurse -Force'
        $workflow | Should -Not -Match 'ubuntu-latest|pull_request_target|checks: write'
        $workflow | Should -Match '(?m)^  repository-contract:\s*$'
        $workflow | Should -Match '(?m)^  skill-validator:\s*$'
        $workflow | Should -Match '(?m)^  skill-tools:\s*$'
        $workflow | Should -Match 'source_conformance:'
        $workflow | Should -Not -Match 'SourceMergeExceptionReview|ProtectedSourceMergeCheck'
        $workflow | Should -Not -Match '(?m)^\s*(Install-Module|npm install|go install|pip install)\b'
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/skill-validator.yml') | Should -BeFalse
    }

    # Scenario: the per-run temporary directory already exists before the installer starts.
    # Purpose: ensure the always-run cleanup never deletes files this run did not create.
    It 'UnitT16_PreservesPreexistingDirectoryWhenRunOwnershipWasNotRecorded' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $cleanupStep = [regex]::Match($workflow, '(?ms)^      - name: Clean only this run''s temporary files\r?\n(?<step>.*?)(?=^  [a-z][a-z0-9-]*:\s*$|\z)')
        $cleanupStep.Success | Should -BeTrue
        $cleanupRun = [regex]::Match($cleanupStep.Groups['step'].Value, '(?m)^        run:\s*\|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$))+)' )
        $cleanupRun.Success | Should -BeTrue
        $cleanupScript = (($cleanupRun.Groups['body'].Value -split '\r?\n') | ForEach-Object {
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

    # Scenario: a canonical Windows job has finished or failed after emitting its source report result.
    # Purpose: keep all three currently required contexts tied to the exact canonical job outcome and report.
    It 'UnitT17_ProjectsRequiredContextsOnlyFromSuccessfulCanonicalSourceEvidence' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $lines = $workflow -split '\r?\n'
        $requiredContexts = @('repository-contract', 'skill-validator', 'skill-tools')
        $projectionScripts = @()

        foreach ($context in $requiredContexts) {
            $start = [Array]::IndexOf($lines, "  ${context}:")
            ($start -ge 0) | Should -BeTrue
            $end = $lines.Count
            for ($index = $start + 1; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -cmatch '^  [a-z][a-z0-9-]*:\s*$') {
                    $end = $index
                    break
                }
            }
            $job = ($lines[($start + 1)..($end - 1)] -join "`n")
            $job | Should -Match "(?m)^    name: $([regex]::Escape($context))\s*$"
            $job | Should -Match '(?m)^    needs: canonical-validation\s*$'
            $job | Should -Match '(?m)^    if: \$\{\{\s*always\(\)\s*\}\}\s*$'
            $job | Should -Match '(?m)^    runs-on: windows-latest\s*$'
            $job | Should -Match '(?m)^          CANONICAL_VALIDATION_RESULT:\s*\$\{\{\s*needs\.canonical-validation\.result\s*\}\}\s*$'
            $job | Should -Match '(?m)^          SOURCE_CONFORMANCE_RESULT:\s*\$\{\{\s*needs\.canonical-validation\.outputs\.source_conformance\s*\}\}\s*$'
            $job | Should -Match '(?m)^        shell: pwsh\s*$'

            $run = [regex]::Match($job, '(?m)^        run:\s*\|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$))+)' )
            $run.Success | Should -BeTrue
            $projectionScripts += (($run.Groups['body'].Value -split '\r?\n' | Where-Object { $_ -ne '' } | ForEach-Object {
                $_.Substring(10)
            }) -join "`n")
        }

        $projectionScripts.Count | Should -Be 3
        $projectionScripts[1] | Should -BeExactly $projectionScripts[0]
        $projectionScripts[2] | Should -BeExactly $projectionScripts[0]
        $workflow | Should -Match '(?m)^      source_conformance:\s*\$\{\{\s*steps\.canonical-source-report\.outputs\.source_conformance\s*\}\}\s*$'
        ([regex]::Matches($workflow, '(?m)^\s*pwsh -NoProfile -NonInteractive -File \./scripts/Validate\.ps1 @driverArgs\s*$')).Count | Should -Be 1
        $reportChecks = @(
            '$report.candidate.sourceRevision -cne $env:EXPECTED_SOURCE_SHA',
            '$report.state -cne ''PASS''',
            '$report.exitCode -ne 0',
            '$report.sourceConformance.status -cne ''passed'''
        )
        $previousCheck = -1
        foreach ($reportCheck in $reportChecks) {
            $checkIndex = $workflow.IndexOf($reportCheck)
            ($checkIndex -gt $previousCheck) | Should -BeTrue
            $previousCheck = $checkIndex
        }
        ($workflow.IndexOf('"source_conformance=passed"') -gt $previousCheck) | Should -BeTrue

        $savedResult = $env:CANONICAL_VALIDATION_RESULT
        $savedSource = $env:SOURCE_CONFORMANCE_RESULT
        try {
            $env:CANONICAL_VALIDATION_RESULT = 'success'
            $env:SOURCE_CONFORMANCE_RESULT = 'passed'
            { & ([scriptblock]::Create($projectionScripts[0])) } | Should -Not -Throw
        }
        finally {
            [Environment]::SetEnvironmentVariable('CANONICAL_VALIDATION_RESULT', $savedResult, 'Process')
            [Environment]::SetEnvironmentVariable('SOURCE_CONFORMANCE_RESULT', $savedSource, 'Process')
        }
    }

    # Scenario: a canonical job failed, was cancelled or skipped, or did not publish a passed source report.
    # Purpose: prevent an always-run status projection from reporting green on incomplete canonical evidence.
    It 'UnitT18_FailsRequiredProjectionsForNonSuccessOrMissingSourceEvidence' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $lines = $workflow -split '\r?\n'
        $start = [Array]::IndexOf($lines, '  repository-contract:')
        ($start -ge 0) | Should -BeTrue
        $end = $lines.Count
        for ($index = $start + 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -cmatch '^  [a-z][a-z0-9-]*:\s*$') {
                $end = $index
                break
            }
        }
        $job = ($lines[($start + 1)..($end - 1)] -join "`n")
        $run = [regex]::Match($job, '(?m)^        run:\s*\|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$))+)' )
        $run.Success | Should -BeTrue
        $projectionScript = (($run.Groups['body'].Value -split '\r?\n' | Where-Object { $_ -ne '' } | ForEach-Object {
            $_.Substring(10)
        }) -join "`n")
        $projectionScript | Should -Not -BeNullOrEmpty
        $projection = [scriptblock]::Create($projectionScript)

        $savedResult = $env:CANONICAL_VALIDATION_RESULT
        $savedSource = $env:SOURCE_CONFORMANCE_RESULT
        try {
            foreach ($case in @(
                @{ result = 'failure'; source = 'passed' }, # Includes a cleanup failure after report publication.
                @{ result = 'cancelled'; source = 'passed' },
                @{ result = 'skipped'; source = 'passed' },
                @{ result = 'success'; source = '' },
                @{ result = 'success'; source = 'failed' }
            )) {
                $env:CANONICAL_VALIDATION_RESULT = $case.result
                $env:SOURCE_CONFORMANCE_RESULT = $case.source
                { & $projection } | Should -Throw
            }
        }
        finally {
            [Environment]::SetEnvironmentVariable('CANONICAL_VALIDATION_RESULT', $savedResult, 'Process')
            [Environment]::SetEnvironmentVariable('SOURCE_CONFORMANCE_RESULT', $savedSource, 'Process')
        }
    }

    # Scenario: the pinned canonical validator emits a successful PASS report for the exact candidate.
    # Purpose: accept the producer's real envelope and reject aliases or incomplete candidate evidence before publishing output.
    It 'UnitT19_AcceptsPinnedProducerPassEnvelopeAndRejectsOtherReportStates' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $step = [regex]::Match($workflow, '(?ms)^      - name: Validate exact candidate with the verified runtime\r?\n(?<step>.*?)(?=^      - name: Clean only this run''s temporary files)')
        $step.Success | Should -BeTrue
        $run = [regex]::Match($step.Groups['step'].Value, '(?m)^        run:\s*\|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$))+)' )
        $run.Success | Should -BeTrue
        $runScript = (($run.Groups['body'].Value -split '\r?\n' | Where-Object { $_ -ne '' } | ForEach-Object {
            $_.Substring(10)
        }) -join "`n")
        $gateStartMarker = 'if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf))'
        $gateEndMarker = '"source_conformance=passed" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append'
        $gateStart = $runScript.IndexOf($gateStartMarker)
        $gateEnd = $runScript.IndexOf($gateEndMarker)
        ($gateStart -ge 0 -and $gateEnd -gt $gateStart) | Should -BeTrue
        $reportGate = [scriptblock]::Create($runScript.Substring($gateStart, $gateEnd + $gateEndMarker.Length - $gateStart))

        $expectedSourceSha = 'a' * 40
        $outputPath = Join-Path $TestDrive 'canonical-report.json'
        $savedExpectedSourceSha = $env:EXPECTED_SOURCE_SHA
        $savedGitHubOutput = $env:GITHUB_OUTPUT
        $savedValidationMode = $env:VALIDATION_MODE
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'github-output.txt'
        $env:EXPECTED_SOURCE_SHA = $expectedSourceSha
        $env:VALIDATION_MODE = 'legacy'
        $validReport = [pscustomobject]@{
            candidate = [pscustomobject]@{ sourceRevision = $expectedSourceSha }
            state = 'PASS'
            exitCode = 0
            sourceConformance = [pscustomobject]@{ status = 'passed' }
        }

        try {
            $validReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding utf8
            { & $reportGate } | Should -Not -Throw
            (Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw).Trim() | Should -BeExactly 'source_conformance=passed'

            foreach ($case in @(
                [pscustomobject]@{ state = 'PASSED'; sourceRevision = $expectedSourceSha; exitCode = 0; sourceStatus = 'passed' },
                [pscustomobject]@{ state = 'FAIL'; sourceRevision = $expectedSourceSha; exitCode = 1; sourceStatus = 'failed' },
                [pscustomobject]@{ state = 'PASS'; sourceRevision = ('b' * 40); exitCode = 0; sourceStatus = 'passed' },
                [pscustomobject]@{ state = 'PASS'; sourceRevision = $expectedSourceSha; exitCode = 1; sourceStatus = 'passed' },
                [pscustomobject]@{ state = 'PASS'; sourceRevision = $expectedSourceSha; exitCode = 0; sourceStatus = 'failed' }
            )) {
                Remove-Item -LiteralPath $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
                $invalidReport = [pscustomobject]@{
                    candidate = [pscustomobject]@{ sourceRevision = $case.sourceRevision }
                    state = $case.state
                    exitCode = $case.exitCode
                    sourceConformance = [pscustomobject]@{ status = $case.sourceStatus }
                }
                $invalidReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding utf8
                { & $reportGate } | Should -Throw
                (Test-Path -LiteralPath $env:GITHUB_OUTPUT) | Should -BeFalse
            }

            Remove-Item -LiteralPath $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $outputPath
            { & $reportGate } | Should -Throw
            (Test-Path -LiteralPath $env:GITHUB_OUTPUT) | Should -BeFalse
        }
        finally {
            [Environment]::SetEnvironmentVariable('EXPECTED_SOURCE_SHA', $savedExpectedSourceSha, 'Process')
            [Environment]::SetEnvironmentVariable('GITHUB_OUTPUT', $savedGitHubOutput, 'Process')
            [Environment]::SetEnvironmentVariable('VALIDATION_MODE', $savedValidationMode, 'Process')
        }
    }

    # Scenario: Core v2 reports a complete immutable-source pass for both repository checks.
    # Purpose: do not publish the required contexts from an incomplete or mismatched Core envelope.
    It 'UnitT19b_AcceptsExactCorePassEnvelopeAndRejectsIncompleteChecks' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $step = [regex]::Match($workflow, '(?ms)^      - name: Validate exact candidate with the verified runtime\r?\n(?<step>.*?)(?=^      - name: Clean only this run''s temporary files)')
        $step.Success | Should -BeTrue
        $run = [regex]::Match($step.Groups['step'].Value, '(?m)^        run:\s*\|\r?\n(?<body>(?:^          [^\r\n]*(?:\r?\n|$))+)' )
        $run.Success | Should -BeTrue
        $runScript = (($run.Groups['body'].Value -split '\r?\n' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Substring(10) }) -join "`n")
        $gateStartMarker = 'if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf))'
        $gateEndMarker = '"source_conformance=passed" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append'
        $gateStart = $runScript.IndexOf($gateStartMarker)
        $gateEnd = $runScript.IndexOf($gateEndMarker)
        ($gateStart -ge 0 -and $gateEnd -gt $gateStart) | Should -BeTrue
        $reportGate = [scriptblock]::Create($runScript.Substring($gateStart, $gateEnd + $gateEndMarker.Length - $gateStart))

        $expectedSourceSha = 'a' * 40
        $baseCommit = 'b' * 40
        $artifactsRoot = Join-Path $TestDrive 'core-artifacts'
        New-Item -ItemType Directory -Path $artifactsRoot | Out-Null
        $outputPath = Join-Path $artifactsRoot 'core-report.json'
        $saved = @{
            EXPECTED_SOURCE_SHA = $env:EXPECTED_SOURCE_SHA
            GITHUB_OUTPUT = $env:GITHUB_OUTPUT
            GITHUB_EVENT_NAME = $env:GITHUB_EVENT_NAME
            VALIDATION_MODE = $env:VALIDATION_MODE
        }
        $env:EXPECTED_SOURCE_SHA = $expectedSourceSha
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'core-github-output.txt'
        $env:GITHUB_EVENT_NAME = 'pull_request'
        $env:VALIDATION_MODE = 'core'
        $valid = [pscustomobject]@{
            schemaVersion = 2
            evidence = 'standard-core-validation-evidence-v2'
            state = 'PASS'
            exitCode = 0
            releaseEligible = $false
            contentMode = 'immutable-source'
            candidate = [pscustomobject]@{
                repository = 'https://github.com/SyuanTsai/Skill-General.git'
                sourceRevision = $expectedSourceSha
                baseRevision = $baseCommit
                eventName = 'pull_request'
                contentMode = 'immutable-source'
            }
            authority = [pscustomobject]@{ revision = 'ea1d368ac7b36f838ce4c3af363972c90fa12930'; contentMode = 'source' }
            adapter = [pscustomobject]@{ identity = 'standard-core-adapter-v2' }
            checks = @(
                [pscustomobject]@{ id = 'repository-general'; kind = 'general'; status = 'passed'; exitCode = 0; cleanedUp = $true },
                [pscustomobject]@{ id = 'repository-pester'; kind = 'pester'; status = 'passed'; exitCode = 0; cleanedUp = $true;
                    testCounts = [pscustomobject]@{ total = 4; passed = 3; failed = 0; skipped = 1 } }
            )
            artifacts = [pscustomobject]@{ root = $artifactsRoot; outputPath = $outputPath }
            failure = $null
        }
        try {
            $valid | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding utf8
            { & $reportGate } | Should -Not -Throw
            (Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw).Trim() | Should -BeExactly 'source_conformance=passed'

            foreach ($mutation in @(
                { param($report) $report.candidate.sourceRevision = 'c' * 40 },
                { param($report) $report.authority.revision = 'd' * 40 },
                { param($report) $report.checks[1].cleanedUp = $false },
                { param($report) $report.checks[1].testCounts.failed = 1 },
                { param($report) $report.checks[1].testCounts.total = 5 },
                { param($report) $report.releaseEligible = $true }
            )) {
                Remove-Item -LiteralPath $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
                $invalid = $valid | ConvertTo-Json -Depth 12 | ConvertFrom-Json -Depth 12
                & $mutation $invalid
                $invalid | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding utf8
                { & $reportGate } | Should -Throw
                (Test-Path -LiteralPath $env:GITHUB_OUTPUT) | Should -BeFalse
            }
        }
        finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
    }

    # Scenario: the trusted base driver evaluates an immutable PR candidate once on the canonical Windows job.
    # Purpose: retain exact source binding while the required checks consume only the canonical job result.
    It 'InterT20_BindsBaseDriverAndExactPrHeadForTheSingleCanonicalValidator' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'EXPECTED_SOURCE_SHA:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'git -C \$candidate merge-base \$env:PULL_REQUEST_BASE_SHA HEAD'
        $workflow | Should -Match "working-directory: driver"
        $workflow | Should -Match '\$driverArgs = @\('
        $workflow | Should -Match 'pwsh -NoProfile -NonInteractive -File \./scripts/Validate\.ps1 @driverArgs'
        $workflow | Should -Match 'candidate\.sourceRevision -cne \$env:EXPECTED_SOURCE_SHA'
        $workflow | Should -Match 'report\.state -cne ''PASS'''
        $workflow | Should -Match 'persist-credentials:\s*false'
    }

    It 'keeps public validation documentation on the canonical entry point' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Raw
        $readme | Should -Match 'scripts/Validate\.ps1'
        $readme | Should -Not -Match 'scripts/(?:Invoke-StandardValidation|Test-SkillGeneral)\.ps1'
        $readme | Should -Not -Match '(?i)\b(?:Invoke-Pester|pytest|skill-validator|skill-tools|skillspector)\b'
    }
}
