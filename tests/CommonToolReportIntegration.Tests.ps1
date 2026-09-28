# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'General child uses central package tool report rules' {
    BeforeAll {
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
        if ([string]::IsNullOrWhiteSpace($env:SYP154_CANDIDATE_AUTHORITY_ROOT)) {
            # Run the actual candidate driver against its immutable authority,
            # including when the protected CI driver still uses an older pin.
            $repositoryRoot = Split-Path -Parent $PSScriptRoot
            $authority = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'config/standard-v1.json') -Raw | ConvertFrom-Json).authority
            $archive = Join-Path $script:testRoot 'authority.zip'
            Invoke-WebRequest -Uri ([string]$authority.archiveUrl) -OutFile $archive -TimeoutSec 60
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$authority.archiveSha256) {
                throw 'Integration authority archive identity differs from the candidate pin.'
            }
            $extract = Join-Path $script:testRoot 'authority'
            Expand-Archive -LiteralPath $archive -DestinationPath $extract
            $roots = @(Get-ChildItem -LiteralPath $extract -Directory)
            if ($roots.Count -ne 1) { throw 'Integration authority archive must contain one root.' }
            $moduleRoot = $roots[0].FullName
            foreach ($entry in @($authority.files)) {
                $path = Join-Path $moduleRoot ([string]$entry.path)
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.sha256) {
                    throw "Integration authority file identity differs: $($entry.path)"
                }
            }
        }
        else { $moduleRoot = [string]$env:SYP154_CANDIDATE_AUTHORITY_ROOT }
        $script:runnerPath = Join-Path $moduleRoot 'scripts/Invoke-StandardValidation.ps1'
        $script:pwshPath = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        $script:priorEnv = @{}
        foreach ($name in @('STANDARD_VALIDATION_ACTIVE_SKILLS', 'STANDARD_VALIDATION_SKILLS_ROOT', 'STANDARD_VALIDATION_SKILL_ID', 'STANDARD_VALIDATION_CANDIDATE_ID', 'STANDARD_VALIDATION_CANDIDATE_ROOT', 'STANDARD_VALIDATION_SKILL_INVENTORY_SHA256', 'SYP154_TEST_TOOL_REPORT', 'SYP154_CANDIDATE_AUTHORITY_ROOT')) {
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
