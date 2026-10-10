# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Skill-General Standard v1 reference implementation' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:SourceInventoryPath = Join-Path $script:RepositoryRoot 'catalog/source.json'
        $script:AdapterPath = Join-Path $script:RepositoryRoot 'config/standard-v1.json'
        $script:CanonicalValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:CorePesterWrapperPath = Join-Path $script:RepositoryRoot 'scripts/Invoke-CorePester.ps1'
        $script:ApprovedAuthoritySnapshots = @{
            'ea1d368ac7b36f838ce4c3af363972c90fa12930' = @{
                archiveSha256 = 'c5a43ef70bf9ed813df2b8ae206b7c1b661caa013744e1098df87ccc3d274653'
                filesSha256 = '617fad5eebb05fb27a8fa121aaada1950906cb6ddd45892dfa52102038622f1a'
                fileCount = 26
            }
            '053b80143b5ef48b06a8c448d5ac1abaf9a49df8' = @{
                archiveSha256 = 'cdaa67f38ee595495015d37955082e16ac248afb48fca64f1788d2eab8adfbc9'
                filesSha256 = '818098039a3a4612afef519cb72626da3a5b6176dfebf5ce2a56ec70c76a8b24'
                fileCount = 26
            }
        }
        $script:ApprovedAuthoritySnapshots['d54ef2cc83a19fa58f62fdcc6fa290095355d03e'] = @{
            archiveSha256 = '03a865e164cf4875dc8e6a12ed10c698db9d6e83cf1d0b6adbfe4e53b2396763'
            filesSha256 = '4ce21109fa065ae4a0358bfe697d70a1a2f448a4e422058acbacef366218da7e'
            fileCount = 29
        }
        $script:ApprovedAuthoritySnapshots['ff85d5f80fe795b96354e753074b5ce59ad04ecd'] = @{
            archiveSha256 = '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
            filesSha256 = 'df7b916e02bc19f7c0632ef189db8b4edc206a5ab216a6104654bcd262bdfb7e'
            fileCount = 32
        }
        $script:ApprovedAuthoritySnapshots['ff85d5f80fe795b96354e753074b5ce59ad04ecd'] = @{
            archiveSha256 = '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
            filesSha256 = 'df7b916e02bc19f7c0632ef189db8b4edc206a5ab216a6104654bcd262bdfb7e'
            fileCount = 32
        }
        $script:GetAuthorityInventorySha256 = {
            param([object[]] $Files)

            $records = @(
                foreach ($file in $Files) {
                    "{0}`t{1}" -f [string]$file.path, [string]$file.sha256
                }
            )
            $canonicalInventory = [string]::Join("`n", [string[]]$records) + "`n"
            $bytes = [Text.Encoding]::UTF8.GetBytes($canonicalInventory)
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        }
        function Assert-LegacySkillRuntimeLayout {
            param([Parameter(Mandatory)][string] $RepositoryRoot)

            $legacySkillRoot = Join-Path $RepositoryRoot '.agents/skills'
            if (-not (Test-Path -LiteralPath $legacySkillRoot)) { return }

            $priorExitVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            $hadPriorExitCode = $null -ne $priorExitVariable
            $priorExitCode = if ($hadPriorExitCode) { $priorExitVariable.Value } else { $null }
            try {
                $agentsRootItem = Get-Item -LiteralPath (Join-Path $RepositoryRoot '.agents') -Force -ErrorAction Stop
                if (($agentsRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'The local legacy .agents ancestor cannot be a reparse point.'
                }
                $legacySkillRootItem = Get-Item -LiteralPath $legacySkillRoot -Force -ErrorAction Stop
                if (($legacySkillRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'The local legacy .agents/skills root cannot be a reparse point.'
                }

                $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
                $gitRootLines = @(& $gitCommand.Source -C $RepositoryRoot rev-parse --show-toplevel)
                $gitRootExitCode = $LASTEXITCODE
                if ($gitRootExitCode -ne 0 -or $gitRootLines.Count -ne 1 -or
                    -not [IO.Path]::GetFullPath([string]$gitRootLines[0]).Equals([IO.Path]::GetFullPath($RepositoryRoot), [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'A present legacy skill directory is allowed only as ignored content inside this true Git checkout.'
                }

                $runtimeEntries = @(Get-ChildItem -LiteralPath $legacySkillRoot -Recurse -Force)
                if (@($runtimeEntries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
                    throw 'The local legacy skill directory cannot contain reparse points.'
                }
                $runtimeFiles = @($runtimeEntries | Where-Object { -not $_.PSIsContainer })
                foreach ($file in $runtimeFiles) {
                    $relativePath = [IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName).Replace('\', '/')
                    & $gitCommand.Source -C $RepositoryRoot ls-files --error-unmatch -- $relativePath 2>$null | Out-Null
                    $trackedExitCode = $LASTEXITCODE
                    if ($trackedExitCode -eq 0) { throw "A legacy skill file is tracked in the canonical source checkout: $relativePath" }
                    if ($trackedExitCode -ne 1) { throw "Could not verify tracked status for the local legacy skill file: $relativePath" }
                    & $gitCommand.Source -C $RepositoryRoot check-ignore --quiet -- $relativePath
                    if ($LASTEXITCODE -ne 0) { throw "A local legacy skill file is not ignored: $relativePath" }
                }
            }
            finally {
                if ($hadPriorExitCode) { Set-Variable -Name LASTEXITCODE -Value $priorExitCode -Scope Global }
                else { Remove-Variable -Name LASTEXITCODE -Scope Global -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    # Scenario: The canonical source publishes every active Skill, including the SQL package.
    # Purpose: Bind the exact ordinal source inventory and reject legacy or missing packages.
    It 'UnitT05_uses_the_canonical_skills_source_root_and_exact_schema_v2_inventory' {
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'skills') -PathType Container | Should -BeTrue
        $legacySkillRoot = Join-Path $script:RepositoryRoot '.agents/skills'
        Assert-LegacySkillRuntimeLayout -RepositoryRoot $script:RepositoryRoot
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
            'operate-environment-authorized-sql'
            'plan-production-change'
            'review-agent-skills'
            'verify-data-access-performance'
        )
    }

    # Scenario: the legacy runtime directory or its direct ancestor is a Windows junction.
    # Purpose: reject path escapes before recursive enumeration can hide the link and accept ignored external files.
    It 'UnitT06_rejects_junctioned_legacy_skill_locations_before_enumerating_<Boundary>' -ForEach @(
        @{ Boundary = 'skills-root' }
        @{ Boundary = 'agents-ancestor' }
    ) {
        $fixtureRoot = Join-Path $TestDrive ('legacy-runtime-junction-' + [guid]::NewGuid().ToString('N'))
        $repositoryRoot = Join-Path $fixtureRoot 'repo'
        $targetRoot = Join-Path $fixtureRoot 'external-target'
        [void](New-Item -ItemType Directory -Path $repositoryRoot -Force)
        [void](New-Item -ItemType Directory -Path $targetRoot -Force)
        $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
        & $gitCommand.Source -C $repositoryRoot init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the isolated legacy-runtime fixture repository.' }
        [IO.File]::WriteAllText((Join-Path $repositoryRoot '.gitignore'), ".agents/skills/`n", [Text.UTF8Encoding]::new($false))

        $targetSkillsRoot = if ($Boundary -eq 'skills-root') { $targetRoot } else { Join-Path $targetRoot 'skills' }
        [void](New-Item -ItemType Directory -Path $targetSkillsRoot -Force)
        $targetFile = Join-Path $targetSkillsRoot 'runtime-fixture.txt'
        [IO.File]::WriteAllText($targetFile, 'private fixture runtime bytes', [Text.UTF8Encoding]::new($false))

        if ($Boundary -eq 'skills-root') {
            $agentsPath = Join-Path $repositoryRoot '.agents'
            [void](New-Item -ItemType Directory -Path $agentsPath -Force)
            $junctionPath = Join-Path $agentsPath 'skills'
        }
        else {
            $junctionPath = Join-Path $repositoryRoot '.agents'
        }

        try {
            [void](New-Item -ItemType Junction -Path $junctionPath -Target $targetRoot -ErrorAction Stop)
            $junctionItem = Get-Item -LiteralPath $junctionPath -Force -ErrorAction Stop
            ($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 | Should -BeTrue
            (Test-Path -LiteralPath $targetFile -PathType Leaf) | Should -BeTrue

            $legacySkillRoot = Join-Path $repositoryRoot '.agents/skills'
            $enumeratedFixtureFiles = @(Get-ChildItem -LiteralPath $legacySkillRoot -Recurse -Force)
            $enumeratedFixtureFiles.Count | Should -Be 1
            $relativePath = [IO.Path]::GetRelativePath($repositoryRoot, $enumeratedFixtureFiles[0].FullName).Replace('\', '/')
            $relativePath | Should -BeExactly '.agents/skills/runtime-fixture.txt'
            & $gitCommand.Source -C $repositoryRoot ls-files --error-unmatch -- $relativePath 2>$null | Out-Null
            $LASTEXITCODE | Should -Be 1
            & $gitCommand.Source -C $repositoryRoot check-ignore --quiet -- $relativePath
            $LASTEXITCODE | Should -Be 0

            $priorExitVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            $hadPriorExitCode = $null -ne $priorExitVariable
            $priorExitCode = if ($hadPriorExitCode) { $priorExitVariable.Value } else { $null }
            try {
                Set-Variable -Name LASTEXITCODE -Value 73 -Scope Global
                { Assert-LegacySkillRuntimeLayout -RepositoryRoot $repositoryRoot } | Should -Throw -ExpectedMessage '*reparse point*'
                (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction Stop).Value | Should -Be 73
            }
            finally {
                if ($hadPriorExitCode) { Set-Variable -Name LASTEXITCODE -Value $priorExitCode -Scope Global }
                else { Remove-Variable -Name LASTEXITCODE -Scope Global -Force -ErrorAction SilentlyContinue }
            }
        }
        finally {
            if (Test-Path -LiteralPath $junctionPath) {
                Remove-Item -LiteralPath $junctionPath -Force -ErrorAction Stop
            }
            (Test-Path -LiteralPath $targetFile -PathType Leaf) | Should -BeTrue
        }
    }

    # Scenario: the consumer config selects a complete reviewed immutable authority tuple, including source validation.
    # Purpose: bind the archive identity and every ordered path/hash pair to a fixed approved snapshot.
    It 'UnitT10_pins_one_exact_approved_authority_tuple_and_required_file_inventory' {
        Test-Path -LiteralPath $script:AdapterPath -PathType Leaf | Should -BeTrue
        $adapter = Get-Content -LiteralPath $script:AdapterPath -Raw | ConvertFrom-Json

        $adapter.schemaVersion | Should -Be 1
        $adapter.standardVersion | Should -Be 'v1'
        @($adapter.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'standardVersion', 'authority')
        @($adapter.authority.PSObject.Properties.Name) | Should -Be @('repository', 'commit', 'archiveUrl', 'archiveSha256', 'files')
        $adapter.authority.repository | Should -Be 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'

        $approved = $script:ApprovedAuthoritySnapshots[[string]$adapter.authority.commit]
        $null -ne $approved | Should -BeTrue
        $adapter.authority.archiveUrl | Should -Be (
            'https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/' + [string]$adapter.authority.commit
        )
        $adapter.authority.archiveSha256 | Should -Be $approved.archiveSha256

        $files = @($adapter.authority.files)
        $files.Count | Should -Be $approved.fileCount
        @($files | ForEach-Object { @($_.PSObject.Properties.Name) -join ',' } | Where-Object { $_ -cne 'path,sha256' }).Count | Should -Be 0
        @($files | Where-Object { [string]$_.sha256 -cnotmatch '^[0-9a-f]{64}$' }).Count | Should -Be 0
        @($files.path | Select-Object -Unique).Count | Should -Be $files.Count
        (& $script:GetAuthorityInventorySha256 -Files $files) | Should -Be $approved.filesSha256
        @($adapter.PSObject.Properties.Name) | Should -Not -Contain 'security'
        @($adapter.PSObject.Properties.Name) | Should -Not -Contain 'deviations'
    }

    # Scenario: the protected driver carries a finite reviewed prepared-source snapshot.
    # Purpose: bind the ff85 archive and complete ordered inventory reference for this and later source-pin selection.
    It 'UnitT42_records_the_prepared_ff85_authority_snapshot' {
        $preparedCommit = 'ff85d5f80fe795b96354e753074b5ce59ad04ecd'
        $prepared = $script:ApprovedAuthoritySnapshots[$preparedCommit]
        $null -ne $prepared | Should -BeTrue
        $prepared.archiveSha256 | Should -BeExactly '3dc38613f2e2316ad8fcc79d4bf48d0b03fd8398f8dacc72d156abcbce95ea9d'
        $prepared.filesSha256 | Should -BeExactly 'df7b916e02bc19f7c0632ef189db8b4edc206a5ab216a6104654bcd262bdfb7e'
        $prepared.fileCount | Should -Be 32
    }

    # Scenario: local and CI validation enter through the repository's reviewed adapter.
    # Purpose: keep one public entry point and preserve the Core wrapper's machine-JSON stdout contract.
    It 'UnitT20_exposes_one_canonical_validator_and_machine_json_Pester_output' {
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

        Test-Path -LiteralPath $script:CorePesterWrapperPath -PathType Leaf | Should -BeTrue
        $coreWrapper = Get-Content -LiteralPath $script:CorePesterWrapperPath -Raw
        $validator | Should -Match "'-File', 'scripts/Invoke-CorePester\.ps1'"
        $coreWrapper | Should -Match "Keep the machine report on stdout and bounded live test progress on stderr\."
        $coreWrapper | Should -Match '\$pesterConfig\.Run\.Path = \$testRoot'
        $coreWrapper | Should -Match '\$pesterConfig\.Run\.PassThru = \$true'
        $coreWrapper | Should -Match '\$pesterConfig\.TestRegistry\.Enabled = \$false'
        $coreWrapper | Should -Match 'Test-CorePesterLoadedModuleIdentity -Modules \$loadedPester -ExpectedVersion \(\[string\]\$closureLockRecord\.Value\.source\.version\)'
        $coreWrapper | Should -Match '\$verifiedAuthoritySnapshotRoot = Get-VerifiedCoreAuthoritySnapshotPath -OuterAdapterRunId \$CandidateAuthorityAdapterRunId'
        $coreWrapper | Should -Match '\[Environment\]::SetEnvironmentVariable\(''SYP154_CANDIDATE_AUTHORITY_ROOT'', \$verifiedAuthoritySnapshotRoot, ''Process''\)'
        $coreWrapper | Should -Match 'Core Pester module candidate check failed'
        $coreWrapper | Should -Match 'Get-CorePesterRuntimeModuleRoot'
        $coreWrapper | Should -Match 'Test-CorePesterClosure'
        $coreWrapper | Should -Match '\$entry = "Pester progress utc='
        $coreWrapper | Should -Match '\[Console\]::Error\.WriteLine\(\$entry\)'
        $coreWrapper | Should -Match 'ConvertTo-Json -InputObject \$summary -Compress'
        $coreWrapper | Should -Match '\$failedBlocks = \[int\]\$result\.FailedBlocksCount'
        $coreWrapper | Should -Match '\$failedContainers = \[int\]\$result\.FailedContainersCount'
        $commonToolSource = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tests/CommonToolReportIntegration.Tests.ps1') -Raw
        $commonToolSupport = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tests/CommonToolAuthoritySupport.ps1') -Raw
        $commonToolSupport | Should -Match '\$coreContextPresent = -not \[string\]::IsNullOrWhiteSpace\(\$CoreRunId\) -or'
        $commonToolSupport | Should -Match 'Core run has no scoped verified authority snapshot'
        $commonToolSupport | Should -Match 'syp154-authority-'' \+ \[string\]\$AuthorityPin\.commit'
        $commonToolSupport | Should -Match 'never downloads or creates runtime authority'
        $transportSource = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'tests/CommonToolAuthorityTransport.Tests.ps1') -Raw
        $transportSource | Should -Match 'InterT30_runs_the_real_CommonTool_suite_in_a_sanitized_Pester6_child'
        $transportSource | Should -Match 'one actual preinstalled Pester 6\.2\.0 module'
        $coreWrapper | Should -Match '\$failed -ne 0 -or \$failedBlocks -ne 0 -or'
    }

    # Scenario: v1 semantic inputs are forwarded while the v2 development harness remains explicit.
    # Purpose: preserve the existing semantic and key-identity contract during ordinary Core adoption.
    It 'UnitT30_keeps_semantic_v1_and_development_harness_forwarding_with_v2_key_identity' {
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

    # Scenario: a Windows workflow selects one protected mode and accepts only its exact canonical report.
    # Purpose: keep the stable runtime, true exit/report checks, and all three required contexts bound to the same result.
    It 'UnitT40_routes_Windows_CI_through_the_exact_canonical_report_and_required_contexts' {
        $workflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $workflow | Should -Match 'scripts/Validate\.ps1'
        $workflow | Should -Match '(?m)^    runs-on:\s*windows-latest\s*$'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'actions/checkout@[0-9a-f]{40}'
        $workflow | Should -Match 'uses:\s*\*checkout-action-reference'
        $workflow | Should -Match '(?m)^\s*id:\s*authority-mode\s*$'
        $authorityTransportStep = [regex]::Match($workflow, '(?ms)- name: Verify and bind candidate-pinned authority for integration tests(?<body>.*?)(?=^      - name:|\z)')
        $authorityTransportStep.Success | Should -BeTrue
        $authorityTransportStep.Groups['body'].Value | Should -Match '(?m)^\s+VALIDATION_MODE: \$\{\{ steps\.authority-mode\.outputs\.validation_mode \}\}\r?$'
        $authorityTransportStep.Groups['body'].Value | Should -Match 'Candidate-pinned authority checkout HEAD differs from the immutable candidate config\.'
        $authorityTransportStep.Groups['body'].Value | Should -Match 'Candidate-pinned authority origin differs from the immutable candidate config\.'
        $authorityTransportStep.Groups['body'].Value | Should -Match 'Candidate-pinned authority checkout must be clean\.'
        $authorityTransportStep.Groups['body'].Value | Should -Match '\$fileCursor = \$filePath'
        $authorityTransportStep.Groups['body'].Value | Should -Not -Match 'snapshotRoot|--local --no-hardlinks|SYP154_CANDIDATE_AUTHORITY_ROOT'
        $workflow | Should -Match '(?m)^\s*id:\s*canonical-source-report\s*$'
        $workflow | Should -Match 'actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e'
        $workflow | Should -Match 'actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020'
        $workflow | Should -Match '''-PrepareSourceTools'', ''-SourceToolsPath'', \$preparedPath'
        $workflow | Should -Match '''-SourceValidation'', ''-SourceToolsPath'', \$env:SOURCE_TOOLS_PATH'
        $workflow | Should -Match 'Assert-StandardCoreSourceCheckReport -Report \$SourceReport'
        $workflow | Should -Match '(?ms)- name: Install and verify Microsoft''s latest stable PowerShell\s+shell: pwsh'
        $workflow | Should -Match '\$channel = Invoke-WebRequest -Uri \(''https://aka\.ms/powershell-'' \+ ''release\?tag=stable''\)'
        $workflow | Should -Match '\$channelUrl -cnotmatch \(''\^https://github\\\.com/PowerShell/PowerShell/'' \+ ''releases/tag/'
        $workflow | Should -Match '\$release = Invoke-RestMethod -Uri \("https://api\.github\.com/repos/PowerShell/PowerShell/" \+ "releases/tags/\$tag"\)'
        $workflow | Should -Match '\$expectedUrl = \("https://github\.com/PowerShell/PowerShell/" \+ "releases/download/\$tag/\$assetName"\)'
        $workflow | Should -Match 'PowerShell-\$expectedVersion-win-x64\.zip'
        $workflow | Should -Match '\$asset\.digest -cnotmatch ''\^sha256:'
        $workflow | Should -Match 'Get-FileHash -LiteralPath \$zipPath -Algorithm SHA256'
        $workflow | Should -Match 'Child PowerShell resolution differs from the verified runtime\.'
        $workflow | Should -Match '(?ms)- name: Acquire and bind exact Pester 6\.2\.0 for Core validation\s+shell: pwsh'
        $pesterInstallStepMatch = [regex]::Match($workflow, '(?ms)- name: Acquire and bind exact Pester 6\.2\.0 for Core validation(?<body>.*?)(?=^      - name:|\z)')
        $pesterInstallStepMatch.Success | Should -BeTrue
        $pesterInstallStepMatch.Groups['body'].Value | Should -Not -Match '(?m)^\s+if:'
        $workflow | Should -Match 'scripts/Prepare-PesterRuntime\.ps1'
        $workflow | Should -Match 'setup-receipt\.json'
        $workflow | Should -Not -Match 'Install-PSResource|Install-Module|CurrentUser'
        $setupIndex = $workflow.IndexOf('Acquire and bind exact Pester 6.2.0', [StringComparison]::Ordinal)
        $validateIndex = $workflow.IndexOf('Validate exact candidate with the verified runtime', [StringComparison]::Ordinal)
        ($setupIndex -ge 0 -and $validateIndex -gt $setupIndex) | Should -BeTrue
        $setupScript = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'scripts/Prepare-PesterRuntime.ps1') -Raw
        $setupScript | Should -Match 'https://www\.powershellgallery\.com/api/v2/package/Pester/6\.2\.0'
        $setupScript | Should -Match 'Test-CorePesterPackageArchive'
        $workflow | Should -Match 'source_conformance: \$\{\{ steps\.canonical-source-report\.outputs\.source_conformance \}\}'
        $workflow | Should -Not -Match '(?m)^\s*id:\s*source-conformance\s*$'
        $workflow | Should -Not -Match 'steps\.source-conformance\.outputs\.status'
        $workflow | Should -Not -Match '(?m)^\s*if \[\['
        ([regex]::Matches($workflow, '(?m)^\s*pwsh -NoProfile -NonInteractive -File \./scripts/Validate\.ps1 @driverArgs\s*$')).Count | Should -Be 2 -Because 'one explicit setup invocation precedes one canonical validation invocation'
        $workflow | Should -Match '\$validatorExitCode = \[int\]\$LASTEXITCODE'
        $workflow | Should -Match 'if \(\$validatorExitCode -ne 0\)'
        $workflow | Should -Match 'Assert-CoreSourceCheckReport -Report \$report -ProcessExitCode \$validatorExitCode -ExpectedSourceRevision \$env:EXPECTED_SOURCE_SHA -ExpectedBaseRevision \$baseCommit -ExpectedAuthorityRevision \$env:APPROVED_AUTHORITY_REVISION -ExpectedEventName \$env:GITHUB_EVENT_NAME -ArtifactsRoot \$artifactsRoot -OutputPath \$outputPath'
        $workflow | Should -Match '\$Report\.candidate\.sourceRevision -cne \$ExpectedSourceRevision'
        $workflow | Should -Match '\$Report\.state -cne ''PASS'' -or \$Report\.exitCode -ne 0'
        $workflow | Should -Match 'Write-CorePesterDiagnostics -ReportPath \$outputPath -RunOwnedRoot \$env:RUN_OWNED_ROOT -ArtifactsRoot \$artifactsRoot -ExpectedSourceRevision \$env:EXPECTED_SOURCE_SHA'
        $workflow | Should -Not -Match 'legacySourceAccepted|Assert-LegacySourceCheckProjection'
        $workflow | Should -Match 'Core Pester evidence lacks a complete passing test count\.'
        $workflow | Should -Match '\$report\.evidence -cne ''standard-core-validation-evidence-v2'''
        $workflow | Should -Match '\$report\.releaseEligible -ne \$false'
        $workflow | Should -Match '\$checks\[1\]\.id -cne ''repository-pester'''
        $workflow | Should -Match 'source_conformance=passed'
        $sourceSetup = $workflow.IndexOf('Explicitly acquire and freeze source tools', [StringComparison]::Ordinal)
        $sourceGate = $workflow.IndexOf('Assert-StandardCoreSourceCheckReport -Report $SourceReport', [StringComparison]::Ordinal)
        $publish = $workflow.IndexOf('Publish protected validation result', [StringComparison]::Ordinal)
        $sourceSetup | Should -BeGreaterThan $setupIndex
        $validateIndex | Should -BeGreaterThan $sourceSetup
        $sourceGate | Should -BeGreaterThan $validateIndex
        $publish | Should -BeGreaterThan $sourceGate
        $workflow | Should -Match 'if: \$\{\{ always\(\) \}\}'
        $inventoryStep = [regex]::Match($workflow, '(?ms)- name: Preserve complete Core Pester case inventory(?<body>.*?)(?=^      - name:|\z)')
        $inventoryStep.Success | Should -BeTrue
        $inventoryBody = $inventoryStep.Groups['body'].Value
        $inventoryBody | Should -Match 'if: \$\{\{ always\(\) && steps\.authority-mode\.outputs\.validation_mode == ''core'' \}\}'
        $inventoryBody | Should -Match 'Expected exactly one Core case inventory sidecar'
        $inventoryBody | Should -Match '524288'
        $inventoryBody | Should -Match 'SHA256\]::HashData\(\$sidecarBytes\)'
        $inventoryBody | Should -Match '\[Convert\]::ToBase64String\(\$sidecarBytes\)'
        $inventoryBody | Should -Match 'CORE_PESTER_INVENTORY_CHUNK index='
        $inventoryBody | Should -Match 'CORE_PESTER_INVENTORY_BEGIN'
        $inventoryBody | Should -Match 'CORE_PESTER_INVENTORY_END'
        $inventoryBody | Should -Match '\$summaryLines\.Add\(\$chunkLine\)'
        $inventoryBody | Should -Match '\$summaryLines -join "`n"'
        $inventoryBody | Should -Match 'Add-VerifiedInventoryStatusToSummary -Text \$summary'
        $inventoryBody | Should -Match 'A successful Core validation requires a complete Pester case inventory sidecar\.'
        $cleanupStep = [regex]::Match($workflow, '(?ms)- name: Clean only this run''s temporary files(?<body>.*?)(?=^      - name:|\z)')
        $cleanupStep.Success | Should -BeTrue
        $cleanupBody = $cleanupStep.Groups['body'].Value
        $cleanupBody | Should -Match 'without this run ownership evidence'
        $cleanupBody | Should -Match 'Get-ChildItem -LiteralPath \$directory -Force -ErrorAction Stop'
        $cleanupBody | Should -Match 'owned tree contains a reparse point'
        $cleanupBody | Should -Match 'owned root or an ancestor is a reparse point'
        $cleanupBody | Should -Match 'Remove-Item -LiteralPath \$ownedRoot -Recurse -Force'
        $rootIdentityIndex = $cleanupBody.IndexOf('if (-not [string]::Equals($ownedRoot, $expectedRoot', [StringComparison]::Ordinal)
        $ancestorCheckIndex = $cleanupBody.IndexOf('$pathEntry.Attributes -band [IO.FileAttributes]::ReparsePoint', [StringComparison]::Ordinal)
        $treeScanIndex = $cleanupBody.IndexOf('$directories = [Collections.Generic.Stack[string]]::new()', [StringComparison]::Ordinal)
        $recursiveRemoveIndex = $cleanupBody.IndexOf('Remove-Item -LiteralPath $ownedRoot -Recurse -Force', [StringComparison]::Ordinal)
        ($rootIdentityIndex -ge 0 -and $ancestorCheckIndex -gt $rootIdentityIndex -and
            $treeScanIndex -gt $ancestorCheckIndex -and $recursiveRemoveIndex -gt $treeScanIndex) | Should -BeTrue
        $validateIndex = $workflow.IndexOf('Validate exact candidate with the verified runtime', [StringComparison]::Ordinal)
        $inventoryIndex = $workflow.IndexOf('Preserve complete Core Pester case inventory', [StringComparison]::Ordinal)
        $publishIndex = $workflow.IndexOf('Publish protected validation result', [StringComparison]::Ordinal)
        $cleanupIndex = $workflow.IndexOf('Clean only this run''s temporary files', [StringComparison]::Ordinal)
        ($validateIndex -ge 0 -and $inventoryIndex -gt $validateIndex -and
            $publishIndex -gt $inventoryIndex -and $cleanupIndex -gt $publishIndex) | Should -BeTrue
        $workflow | Should -Not -Match '(?m)^\s*(Install-Module|npm install|go install|pip install)\b'
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/skill-validator.yml') | Should -BeFalse

        foreach ($context in @('repository-contract', 'skill-validator', 'skill-tools')) {
            $jobPattern = '(?ms)^  {0}:\r?\n(?<body>.*?)(?=^  [A-Za-z0-9_-]+:|\z)' -f [regex]::Escape($context)
            $job = [regex]::Match($workflow, $jobPattern)
            $job.Success | Should -BeTrue
            $job.Groups['body'].Value | Should -Match '(?m)^    needs:\s+canonical-validation\s*$'
            $job.Groups['body'].Value | Should -Match '(?m)^    if:\s+\$\{\{\s*always\(\)\s*\}\}\s*$'
            $job.Groups['body'].Value | Should -Match 'CANONICAL_VALIDATION_RESULT:\s+\$\{\{\s*needs\.canonical-validation\.result\s*\}\}'
            $job.Groups['body'].Value | Should -Match 'SOURCE_CONFORMANCE_RESULT:\s+\$\{\{\s*needs\.canonical-validation\.outputs\.source_conformance\s*\}\}'
            $job.Groups['body'].Value | Should -Match '\$env:CANONICAL_VALIDATION_RESULT -cne ''success'''
            $job.Groups['body'].Value | Should -Match '\$env:SOURCE_CONFORMANCE_RESULT -cne ''passed'''
        }
        $workflow | Should -Not -Match '(?ms)repository-contract:.*?Run .*skill-validator|skill-validator:.*?Run .*skill-tools'
    }

    # Scenario: the event supplies immutable source and protected-driver commits for one exact PR run.
    # Purpose: bind the selected Core archive, base revision, report, and cleanup to those commits without allowing downgrade.
    It 'InterT20_binds_protected_source_check_to_base_driver_and_exact_pr_head' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'EXPECTED_SOURCE_SHA:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'EXPECTED_DRIVER_SHA:\s*\$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'ref:\s*\$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}'
        $workflow | Should -Match 'path: driver'
        $workflow | Should -Match 'path: candidate'
        $workflow | Should -Match 'git -C \$candidate merge-base \$env:PULL_REQUEST_BASE_SHA HEAD'
        $workflow | Should -Match '\$checkoutHead -cne \$env:EXPECTED_SOURCE_SHA'
        $workflow | Should -Match '\$commonBase\.Count -ne 1'
        $workflow | Should -Match '\$driverHead -cne \$env:EXPECTED_DRIVER_SHA'
        $workflow | Should -Match '\$sourceAuthority = ''d54ef2cc83a19fa58f62fdcc6fa290095355d03e'''
        $workflow | Should -Match '\$preparedSourceAuthority = ''ff85d5f80fe795b96354e753074b5ce59ad04ecd'''
        $workflow | Should -Match '\$coreAuthorities = @\(''ea1d368ac7b36f838ce4c3af363972c90fa12930'', ''053b80143b5ef48b06a8c448d5ac1abaf9a49df8'', \$sourceAuthority, \$preparedSourceAuthority\)'
        $workflow | Should -Match '\$candidateSourceAuthority -cnotin @\(\$sourceAuthority, \$preparedSourceAuthority\)'
        $workflow | Should -Match 'Source validation cannot accept a Core-only candidate authority\.'
        $workflow | Should -Match '\$sourceDefinitions\.Count -ne 1'
        $workflow | Should -Match '\$sourcePins\.Count -ne 1'
        $workflow | Should -Match '\$sourcePins\[0\]\.Groups\[''sha''\]\.Value -cne \$sourceAuthority'
        $workflow | Should -Match '\$preparedSourceDefinitions = \[regex\]::Matches'
        $workflow | Should -Match '\$preparedSourcePins = \[regex\]::Matches'
        $workflow | Should -Match '\$preparedSourceRequired = \$candidateSourceAuthority -ceq \$preparedSourceAuthority -or \$driverAuthority -ceq \$preparedSourceAuthority'
        $workflow | Should -Match '\$preparedSourceDefinitions\.Count -eq 1 -and \$preparedSourcePins\.Count -eq 1'
        $workflow | Should -Match '\$preparedSourcePins\[0\]\.Groups\[''sha''\]\.Value -ceq \$preparedSourceAuthority'

        $workflow | Should -Not -Match '\$baselineAuthority|\$mode = ''legacy'''
        $workflow | Should -Match '\$driverAuthority -cnotin \$coreAuthorities'
        $workflow | Should -Match 'scripts/Invoke-Core.*Pester\.ps1'
        $workflow | Should -Match 'authority_revision=\$candidateSourceAuthority'
        $workflow | Should -Match 'ref:\s*\$\{\{ steps\.authority-mode\.outputs\.authority_revision \}\}'
        $workflow | Should -Match 'APPROVED_AUTHORITY_REVISION:\s*\$\{\{ steps\.authority-mode\.outputs\.authority_revision \}\}'
        $workflow | Should -Match '\$baseCommit = if \(\$env:GITHUB_EVENT_NAME -eq ''pull_request''\)'
        $workflow | Should -Match '\$Report\.candidate\.baseRevision -cne \$ExpectedBaseRevision'
        $workflow | Should -Match '\$Report\.authority\.revision -cne \$ExpectedAuthorityRevision'
        $workflow | Should -Match '\$report\.releaseEligible -ne \$false'
        $workflow | Should -Match 'SetEnvironmentVariable\(''GITHUB_TOKEN'', \$null, ''Process''\)'
        $workflow | Should -Match 'SetEnvironmentVariable\(''GH_TOKEN'', \$null, ''Process''\)'
        $workflow | Should -Match 'Clean only this run''s temporary files'
        $workflow | Should -Match 'if: \$\{\{ always\(\) \}\}'
        $workflow | Should -Match 'Refusing to clean a path without this run ownership evidence\.'
        $workflow | Should -Match 'persist-credentials:\s*false'
    }

    # Scenario: public source validation documentation explains the explicit setup and canonical validation entries.
    # Purpose: tool identity descriptions remain useful while executable instructions use the reviewed adapter (V4).
    It 'UnitT50_documents_source_setup_and_validation_on_the_canonical_entry_point' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Raw
        $readme | Should -Match 'scripts/Validate\.ps1'
        $readme | Should -Not -Match 'scripts/(?:Invoke-StandardValidation|Test-SkillGeneral)\.ps1'
        $readme | Should -Match '-PrepareSourceTools'
        $readme | Should -Match '-SourceValidation'
        $readme | Should -Not -Match '(?im)^\s*(?:Invoke-Pester|pytest|skill-validator|skill-tools|skillspector)(?:\s|$)'

    }
}
