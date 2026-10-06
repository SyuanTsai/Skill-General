# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

# Keep the shared helper in the test-file scope for both independent Describe containers.
. (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')

Describe 'General Static native failure propagation' {
    # Scenario: SkillSpector exits nonzero while a plausible previous JSON report already exists.
    # Purpose: the actual Static dispatch must reject native failure before reading PASS bytes (V3).
    It 'InterT10_rejects_nonzero_Static_exit_before_reading_an_existing_report' {
        $source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Validate.ps1') -Raw
        $child = [regex]::Match($source, '(?ms)^\$childRunnerText = @''\r?\n(?<body>.*?)^''@')
        if (-not $child.Success) { throw 'General child runner source was not found.' }
        $dispatch = [regex]::Match($child.Groups['body'].Value, '(?ms)^        ''static'' \{\r?\n(?<body>.*?)^        \}\r?\n        ''repository-general'' \{')
        if (-not $dispatch.Success) { throw 'General Static dispatch source was not found.' }
        $scanner = Join-Path $TestDrive 'scanner.ps1'
        [IO.File]::WriteAllText($scanner, '$global:LASTEXITCODE = 7')
        [IO.File]::WriteAllText((Join-Path $TestDrive 'skillspector-demo.json'), '{"decision":"PASS"}')
        $fixture = New-Module -ScriptBlock {
            function Assert-FileIdentity { param($Path, $Sha256, $Context) }
            function Get-SkillRoot { param($SkillId) return $script:FixtureRoot }
            function Get-InventoryPaths { param($SkillRoot) return @('SKILL.md') }
            function Add-NativeReport { param($Command, $Arguments, $ExitCode, $Path, $SkillId) }
            function Read-Json { param($Path, $Context) throw 'Static dispatch read stale report after native failure.' }
            function Assert-SkillSpectorReport { param($Report, $SkillRoot, $SkillId, $Inventory) return @() }
            function New-Envelope { param($ActiveSkills, $Findings, $Additional) throw 'Static dispatch published PASS after native failure.' }
        }
        Push-Location $TestDrive
        try {
            { & $fixture { param($body, $path, $root)
                $script:FixtureRoot = $root
                $toolchain = @{ skillSpectorPath = $path; skillSpectorSha256 = ('a' * 64) }
                $activeSkills = @('demo'); $SemanticRequired = 'false'
                & ([scriptblock]::Create($body))
            } $dispatch.Groups['body'].Value $scanner $TestDrive } | Should -Throw -ExpectedMessage '*returned exit code 7*'
        }
        finally { Pop-Location }
    }
}

Describe 'Candidate-pinned Common Tool authority transport' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:transportRepositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
        $script:transportPin = (Get-Content -LiteralPath (Join-Path $script:transportRepositoryRoot 'config/standard-v1.json') -Raw -Encoding utf8 | ConvertFrom-Json).authority
    }

    # Scenario: Core identity is supplied but the wrapper's scoped snapshot is absent.
    # Purpose: Core must fail closed instead of selecting an adjacent legacy TEMP cache.
    It 'InterT00_fails_closed_when_Core_context_lacks_its_scoped_snapshot_even_if_TEMP_has_a_cache' {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('syp154-core-no-fallback-' + [guid]::NewGuid().ToString('N'))
        $candidate = Join-Path $tempRoot ('syp154-authority-' + [string]$script:transportPin.commit)
        [void](New-Item -ItemType Directory -Path $candidate -Force)
        try {
            {
                Get-VerifiedCandidateAuthorityRoot -RepositoryRoot $script:transportRepositoryRoot -AuthorityPin $script:transportPin `
                    -CoreRunId ('a' * 32) -CoreCheckId 'repository-pester' -ScopedAuthorityRoot '' -TempRoot $tempRoot
            } | Should -Throw -ExpectedMessage '*Core run has no scoped verified authority snapshot*'
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    # Scenario: a sanitized legacy child has no custom SYP or Core environment.
    # Purpose: derive only the exact commit-named TEMP transport and fail if setup was omitted.
    It 'InterT10_fails_closed_when_the_exact_legacy_TEMP_snapshot_is_missing' {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('syp154-legacy-missing-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $tempRoot -Force)
        try {
            {
                Get-VerifiedCandidateAuthorityRoot -RepositoryRoot $script:transportRepositoryRoot -AuthorityPin $script:transportPin `
                    -CoreRunId '' -CoreCheckId '' -ScopedAuthorityRoot '' -TempRoot $tempRoot
            } | Should -Throw -ExpectedMessage '*Legacy authority snapshot is missing*'
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    # Scenario: setup provides a named local cache but one of its pinned files changes.
    # Purpose: existing cache content is read-only evidence and must fail closed without repair.
    It 'InterT20_rejects_a_tampered_existing_legacy_TEMP_snapshot_without_repair' {
        $sourceRoot = [Environment]::GetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', 'Process')
        if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
            $sourceRoot = Join-Path ([IO.Path]::GetTempPath()) ('syp154-authority-' + [string]$script:transportPin.commit)
        }
        Get-VerifiedCandidateAuthorityRoot -RepositoryRoot $script:transportRepositoryRoot -AuthorityPin $script:transportPin `
            -ScopedAuthorityRoot $sourceRoot | Should -Be $sourceRoot
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('st-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $tempRoot -Force)
        $snapshotRoot = Join-Path $tempRoot ('syp154-authority-' + [string]$script:transportPin.commit)
        $gitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $safeSource = 'safe.directory=' + [IO.Path]::GetFullPath($sourceRoot)
        try {
            $cloneOutput = @(& $gitPath -c $safeSource -c core.longpaths=true clone --config core.autocrlf=false --local --no-hardlinks $sourceRoot $snapshotRoot 2>&1)
            if ($LASTEXITCODE -ne 0) { throw ('Could not create isolated transport fixture from the already verified pin: ' + ($cloneOutput -join ' ')) }
            & $gitPath -C $snapshotRoot remote set-url origin ([string]$script:transportPin.repository)
            if ($LASTEXITCODE -ne 0) { throw 'Could not bind isolated transport fixture origin.' }
            & $gitPath -c core.longpaths=true -C $snapshotRoot checkout --detach ([string]$script:transportPin.commit)
            if ($LASTEXITCODE -ne 0) { throw 'Could not bind isolated transport fixture commit.' }
            $tamperEntry = @($script:transportPin.files)[0]
            $tamperPath = Join-Path $snapshotRoot ([string]$tamperEntry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
            [IO.File]::AppendAllText($tamperPath, "`n")
            {
                Get-VerifiedCandidateAuthorityRoot -RepositoryRoot $script:transportRepositoryRoot -AuthorityPin $script:transportPin `
                    -ScopedAuthorityRoot '' -TempRoot $tempRoot
            } | Should -Throw -ExpectedMessage '*must be clean and immutable*'
            Test-Path -LiteralPath $tamperPath -PathType Leaf | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

Describe 'General child uses central package tool report rules' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $validationPath = if ([string]::IsNullOrWhiteSpace($env:SYP154_TEST_VALIDATE_SOURCE)) { Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Validate.ps1' } else { [string]$env:SYP154_TEST_VALIDATE_SOURCE }
        $script:validationSource = Get-Content -LiteralPath $validationPath -Raw
        $script:childMatch = [regex]::Match($script:validationSource, '(?ms)^\$childRunnerText = @''\r?\n(?<body>.*?)^''@')
        if (-not $script:childMatch.Success) { throw 'General child runner source was not found.' }
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('syp154-report-' + [guid]::NewGuid().ToString('N'))
        $script:skillRoot = Join-Path $script:testRoot 'skills/demo'
        [void](New-Item -ItemType Directory -Path $script:skillRoot -Force)
        [IO.File]::WriteAllText((Join-Path $script:skillRoot 'SKILL.md'), '# Demo')
        $script:childPath = Join-Path $script:testRoot 'child.ps1'
        [IO.File]::WriteAllText($script:childPath, $script:childMatch.Groups['body'].Value)
        $script:fakeToolPath = Join-Path $script:testRoot 'skill-validator.ps1'
        [IO.File]::WriteAllText($script:fakeToolPath, 'Get-Content -LiteralPath $env:SYP154_TEST_TOOL_REPORT -Raw; $global:LASTEXITCODE = 0')
        $repositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
        $authority = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'config/standard-v1.json') -Raw -Encoding utf8 | ConvertFrom-Json).authority
        $script:moduleRoot = Get-VerifiedCandidateAuthorityRoot -RepositoryRoot $repositoryRoot -AuthorityPin $authority `
            -CoreRunId ([Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_CORE_RUN_ID', 'Process')) `
            -CoreCheckId ([Environment]::GetEnvironmentVariable('STANDARD_VALIDATION_CORE_CHECK_ID', 'Process')) `
            -ScopedAuthorityRoot ([Environment]::GetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', 'Process'))
        $script:runnerPath = Join-Path $moduleRoot 'scripts/Invoke-StandardValidation.ps1'
        $script:pwshPath = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        $script:priorEnv = @{}
        foreach ($name in @('STANDARD_VALIDATION_ACTIVE_SKILLS', 'STANDARD_VALIDATION_SKILLS_ROOT', 'STANDARD_VALIDATION_SKILL_ID', 'STANDARD_VALIDATION_CANDIDATE_ID', 'STANDARD_VALIDATION_CANDIDATE_ROOT', 'STANDARD_VALIDATION_SKILL_INVENTORY_SHA256', 'SYP154_TEST_TOOL_REPORT')) {
            $script:priorEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $env:STANDARD_VALIDATION_ACTIVE_SKILLS = 'demo'
        $env:STANDARD_VALIDATION_SKILLS_ROOT = Join-Path $script:testRoot 'skills'
        $env:STANDARD_VALIDATION_SKILL_ID = 'demo'
        $env:STANDARD_VALIDATION_CANDIDATE_ID = ('a' * 64)
        $env:STANDARD_VALIDATION_CANDIDATE_ROOT = $script:testRoot
        $env:STANDARD_VALIDATION_SKILL_INVENTORY_SHA256 = ('b' * 64)
        $toolchain = [ordered]@{
            centralRunnerPath = $script:runnerPath
            centralRunnerSha256 = if (Test-Path -LiteralPath $script:runnerPath -PathType Leaf) { (Get-FileHash -Algorithm SHA256 -LiteralPath $script:runnerPath).Hash.ToLowerInvariant() } else { '0' * 64 }
            skillValidatorPath = $script:fakeToolPath
            skillValidatorSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:fakeToolPath).Hash.ToLowerInvariant()
        }
        $script:toolchainPath = Join-Path $script:testRoot 'toolchain.json'
        [IO.File]::WriteAllText($script:toolchainPath, ($toolchain | ConvertTo-Json -Compress))
        $script:toolchainHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:toolchainPath).Hash.ToLowerInvariant()
    }

    BeforeEach { Push-Location -LiteralPath $script:testRoot }
    AfterEach { Pop-Location }

    AfterAll {
        foreach ($name in $script:priorEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $script:priorEnv[$name]) }
        $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $actualParent = [IO.Path]::GetFullPath((Split-Path -Parent $script:testRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($actualParent -cne $expectedParent -or (Split-Path -Leaf $script:testRoot) -cnotmatch '^syp154-report-[0-9a-f]{32}$') {
            throw 'Integration test cleanup root is not the allocated temporary directory.'
        }
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force
    }

    # Scenario: a package tool emits a success report with a string error count.
    # Purpose: the General child must reject malformed counts through the shared authority rule.
    It 'InterT10_rejects_string_error_count_from_the_real_General_child' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = '0'; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainHash 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'typed nonnegative integer'
    }

    # Scenario: the same candidate-bound tool returns typed zero counts.
    # Purpose: the shared report rule must allow the normal General envelope path.
    It 'InterT20_accepts_typed_zero_counts_through_the_real_General_child' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainHash 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        $envelope = ($output -join "`n") | ConvertFrom-Json -Depth 10
        $envelope.decision | Should -Be 'PASS'
        $envelope.candidateIdentity | Should -Be ('a' * 64)
        @($envelope.nativeReports).Count | Should -Be 1
        $native = $envelope.nativeReports[0]
        $native.skillId | Should -Be 'demo'
        $native.command | Should -Be $script:fakeToolPath
        $native.exitCode | Should -Be 0
        $native.path | Should -Be (Join-Path $script:testRoot 'native-skill-validator-demo.json')
        $native.sha256 | Should -Be (Get-FileHash -LiteralPath $native.path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    # Scenario: the same report is supplied with a forged central runner digest.
    # Purpose: a candidate cannot substitute an unverified shared validator and still receive PASS.
    It 'InterT30_rejects_a_mismatched_central_runner_before_tool_execution' {
        $reportPath = Join-Path $script:testRoot 'report.json'
        [IO.File]::WriteAllText($reportPath, (@{ skill_dir = $script:skillRoot; passed = $true; errors = 0; warnings = 0; results = @(@{ level = 'pass'; file = 'SKILL.md' }) } | ConvertTo-Json -Depth 10 -Compress))
        $env:SYP154_TEST_TOOL_REPORT = $reportPath
        $toolchain = Get-Content -LiteralPath $script:toolchainPath -Raw | ConvertFrom-Json
        $toolchain.centralRunnerSha256 = '0' * 64
        [IO.File]::WriteAllText($script:toolchainPath, ($toolchain | ConvertTo-Json -Compress))
        $forgedToolchainHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:toolchainPath).Hash.ToLowerInvariant()
        $output = & $script:pwshPath -NoProfile -NonInteractive -File $script:childPath -Mode skill-validator -ToolchainPath $script:toolchainPath -ToolchainSha256 $forgedToolchainHash 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'central validation runner changed or is missing'
    }
}
