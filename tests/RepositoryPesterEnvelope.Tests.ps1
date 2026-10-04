# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Repository Pester result envelope' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $validator = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Validate.ps1') -Raw
        $runnerMatch = [regex]::Match($validator, '(?ms)^\$childRunnerText = @''\r?\n(?<body>.*?)^''@')
        if (-not $runnerMatch.Success) { throw 'Generated child runner was not found.' }

        $script:fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('sg-pester-envelope-' + [guid]::NewGuid().ToString('N'))
        $candidateRoot = Join-Path $script:fixtureRoot 'candidate'
        $testsRoot = Join-Path $candidateRoot 'tests'
        $moduleRoot = Join-Path $script:fixtureRoot 'Pester'
        [void](New-Item -ItemType Directory -Path $testsRoot, $moduleRoot -Force)
        [IO.File]::WriteAllText((Join-Path $testsRoot 'fixture.Tests.ps1'), "It 'fixture' {}`n", [Text.UTF8Encoding]::new($false))
        $script:runnerPath = Join-Path $script:fixtureRoot 'child-runner.ps1'
        [IO.File]::WriteAllText($script:runnerPath, $runnerMatch.Groups['body'].Value, [Text.UTF8Encoding]::new($false))
        $moduleBody = @'
function Invoke-Pester {
    param($Path, $Output, [switch] $PassThru)
    $result = [ordered]@{
        TotalCount = 0; PassedCount = 0; SkippedCount = 0; FailedCount = 0; NotRunCount = 0
        FailedBlocksCount = 0; FailedContainersCount = 0
        Failed = @(); FailedBlocks = @(); FailedContainers = @()
    }
    switch ($env:TEST_PESTER_SCENARIO) {
        'partial-skip' { $result.TotalCount = 3; $result.PassedCount = 2; $result.SkippedCount = 1 }
        'zero-selected' { }
        'all-skipped' { $result.TotalCount = 2; $result.SkippedCount = 2 }
        'failed' {
            $result.TotalCount = 2; $result.PassedCount = 1; $result.FailedCount = 1
            $result.Failed = @([pscustomobject]@{
                ExpandedPath = 'fixture.fails'
                ErrorRecord = @([pscustomobject]@{ Exception = [Exception]::new('synthetic test failure') })
            })
        }
        'container-failed' {
            $result.TotalCount = 1; $result.PassedCount = 1; $result.FailedContainersCount = 1
            $result.FailedContainers = @([pscustomobject]@{
                Name = 'Broken.Tests.ps1'
                ErrorRecord = @([pscustomobject]@{ Exception = [Exception]::new('synthetic container failure') })
            })
        }
        'block-failed' {
            $result.TotalCount = 1; $result.PassedCount = 1; $result.FailedBlocksCount = 1
            $result.FailedBlocks = @([pscustomobject]@{
                Name = 'broken before all'
                ErrorRecord = @([pscustomobject]@{ Exception = [Exception]::new('synthetic block failure') })
            })
        }
        'incomplete' {
            $result.TotalCount = 3; $result.PassedCount = 2; $result.NotRunCount = 1
            if ($Output -eq 'Detailed') {
                Write-Information '  [+] fixture.last_completed 12ms' -InformationAction Continue
            }
        }
        'slow-pass' {
            Write-Information 'Running tests from fixture.Tests.ps1' -InformationAction Continue
            Start-Sleep -Seconds 4
            $result.TotalCount = 1; $result.PassedCount = 1
        }
        default { throw 'Unknown fake Pester scenario.' }
    }
    return [pscustomobject]$result
}
Export-ModuleMember -Function Invoke-Pester
'@
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'Pester.psm1'), $moduleBody, [Text.UTF8Encoding]::new($false))
        $script:modulePath = Join-Path $moduleRoot 'Pester.psd1'
        New-ModuleManifest -Path $script:modulePath -RootModule 'Pester.psm1' -ModuleVersion '6.2.0' -FunctionsToExport @('Invoke-Pester')
        $toolchainPath = Join-Path $script:fixtureRoot 'toolchain.json'
        [IO.File]::WriteAllText($toolchainPath, (@{ pesterModulePath = $script:modulePath; pesterModuleSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:modulePath).Hash.ToLowerInvariant(); pesterVersion = '6.2.0' } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        $script:toolchainPath = $toolchainPath
        $script:toolchainSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $toolchainPath).Hash.ToLowerInvariant()
        $script:pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $script:oldCandidateRoot = $env:STANDARD_VALIDATION_CANDIDATE_ROOT
        $script:oldCandidateId = $env:STANDARD_VALIDATION_CANDIDATE_ID
        $script:oldActiveSkills = $env:STANDARD_VALIDATION_ACTIVE_SKILLS
        $script:oldScenario = $env:TEST_PESTER_SCENARIO
        $env:STANDARD_VALIDATION_CANDIDATE_ROOT = $candidateRoot
        $env:STANDARD_VALIDATION_CANDIDATE_ID = 'fixture-candidate'
        $env:STANDARD_VALIDATION_ACTIVE_SKILLS = 'fixture-skill'
    }

    AfterAll {
        $env:STANDARD_VALIDATION_CANDIDATE_ROOT = $script:oldCandidateRoot
        $env:STANDARD_VALIDATION_CANDIDATE_ID = $script:oldCandidateId
        $env:STANDARD_VALIDATION_ACTIVE_SKILLS = $script:oldActiveSkills
        $env:TEST_PESTER_SCENARIO = $script:oldScenario
        if (Test-Path -LiteralPath $script:fixtureRoot) { Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force }
    }

    # Scenario: Pester returns two passes and one skip; the child runner emits its actual typed counts.
    # Purpose: Protect the supervisor proposal contract against an omitted failed count.
    It 'InterT10_ emits exact numeric counts in one JSON envelope for a partial skip' {
        $env:TEST_PESTER_SCENARIO = 'partial-skip'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256)
        $LASTEXITCODE | Should -Be 0
        $output.Count | Should -Be 1
        $json = $output[0] | ConvertFrom-Json -Depth 20
        $json.testResult.status | Should -Be 'passed'
        $json.testResult.total | Should -BeOfType ([long])
        $json.testResult.passed | Should -BeOfType ([long])
        $json.testResult.skipped | Should -BeOfType ([long])
        $json.testResult.failed | Should -BeOfType ([long])
        $json.testResult.total | Should -Be 3
        $json.testResult.passed | Should -Be 2
        $json.testResult.skipped | Should -Be 1
        $json.testResult.failed | Should -Be 0
    }

    # Scenario: Pester reports a file start and continues running for several seconds.
    # Purpose: prove progress reaches stderr before completion while stdout remains one typed JSON record.
    It 'InterT15_ streams bounded progress before Pester completes' {
        $env:TEST_PESTER_SCENARIO = 'slow-pass'
        $stdoutPath = Join-Path $script:fixtureRoot 'slow-pass.out'
        $stderrPath = Join-Path $script:fixtureRoot 'slow-pass.err'
        $arguments = @('-NoProfile', '-NonInteractive', '-File', $script:runnerPath,
            '-Mode', 'repository-pester', '-ToolchainPath', $script:toolchainPath,
            '-ToolchainSha256', $script:toolchainSha256)
        $process = Start-Process -FilePath $script:pwsh -ArgumentList $arguments -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden
        try {
            $deadline = (Get-Date).AddSeconds(10)
            $seenBeforeExit = $false
            while ((Get-Date) -lt $deadline -and -not $process.HasExited) {
                if ((Test-Path -LiteralPath $stderrPath -PathType Leaf) -and
                    (Get-Content -LiteralPath $stderrPath -Raw) -match 'Pester progress:.*Running tests from fixture\.Tests\.ps1') {
                    $seenBeforeExit = $true
                    break
                }
                Start-Sleep -Milliseconds 100
            }
            $seenBeforeExit | Should -BeTrue
            $process.WaitForExit(10000) | Should -BeTrue
            $process.ExitCode | Should -Be 0
            $output = @(Get-Content -LiteralPath $stdoutPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $output.Count | Should -Be 1
            ($output[0] | ConvertFrom-Json).testResult.status | Should -BeExactly 'passed'
        }
        finally {
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force
                [void]$process.WaitForExit(5000)
            }
            $process.Dispose()
        }
    }

    # Scenario: Pester selects no tests; the child runner must reject the result.
    # Purpose: Prevent an empty suite from qualifying as repository regression evidence.
    It 'InterT20_ rejects zero selected tests' {
        $env:TEST_PESTER_SCENARIO = 'zero-selected'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256 2>$null)
        $LASTEXITCODE | Should -Not -Be 0
        $output.Count | Should -Be 0
    }

    # Scenario: All discovered tests are skipped; the child runner must reject the result.
    # Purpose: Prevent a pass envelope with no executed assertions.
    It 'InterT30_ rejects an all-skipped suite' {
        $env:TEST_PESTER_SCENARIO = 'all-skipped'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256 2>$null)
        $LASTEXITCODE | Should -Not -Be 0
        $output.Count | Should -Be 0
    }

    # Scenario: Pester reports a failed test; the child runner must reject the result.
    # Purpose: Preserve fail-closed repository regression evidence.
    It 'InterT40_ rejects a failed suite' {
        $env:TEST_PESTER_SCENARIO = 'failed'
        $diagnostics = Join-Path $script:fixtureRoot 'test-failed.err'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256 2> $diagnostics)
        $LASTEXITCODE | Should -Not -Be 0
        $output.Count | Should -Be 0
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester test failed: fixture\.fails'
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester test error: synthetic test failure'
    }

    # A discovery failure can coexist with one passing test and zero failed test cases.
    It 'InterT50_ rejects a failed container and reports its name on stderr' {
        $env:TEST_PESTER_SCENARIO = 'container-failed'
        $diagnostics = Join-Path $script:fixtureRoot 'container-failed.err'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256 2> $diagnostics)
        $LASTEXITCODE | Should -Not -Be 0
        $output.Count | Should -Be 0
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester container failed: Broken\.Tests\.ps1'
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester container error: synthetic container failure'
    }

    It 'InterT60_ rejects a failed block despite a passing test count' {
        $env:TEST_PESTER_SCENARIO = 'block-failed'
        $diagnostics = Join-Path $script:fixtureRoot 'block-failed.err'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256 2> $diagnostics)
        $LASTEXITCODE | Should -Not -Be 0
        $output.Count | Should -Be 0
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester block failed: broken before all'
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester block error: synthetic block failure'
    }

    # Scenario: Pester exits with one discovered test not run and no failed test, block, or container.
    # Purpose: retain fail-closed evidence while locating the last completed case and the exact count gap.
    It 'InterT70_ reports counts and bounded last-case progress for an incomplete suite' {
        $env:TEST_PESTER_SCENARIO = 'incomplete'
        $diagnostics = Join-Path $script:fixtureRoot 'incomplete.err'
        $output = @(& $script:pwsh -NoProfile -NonInteractive -File $script:runnerPath -Mode repository-pester -ToolchainPath $script:toolchainPath -ToolchainSha256 $script:toolchainSha256 2> $diagnostics)
        $LASTEXITCODE | Should -Not -Be 0
        $output.Count | Should -Be 0
        $stderr = Get-Content -LiteralPath $diagnostics -Raw
        $stderr | Should -Match 'Pester counts: total=3 passed=2 skipped=0 failed=0 failedBlocks=0 failedContainers=0 notRun=1'
        $stderr | Should -Match 'Pester progress:.*fixture\.last_completed'
        $stderr | Should -Match 'Pester repository regression did not complete successfully'
    }
}
