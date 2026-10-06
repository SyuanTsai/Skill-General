# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Pinned authority Git blob process boundary' {
    BeforeAll {
        $validatorPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Validate.ps1'
        $source = [IO.File]::ReadAllText($validatorPath)
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -ne 0) { throw 'Validator source does not parse.' }
        $functionAst = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq 'Get-GitBlobSha256'
        })
        if ($functionAst.Count -ne 1) { throw 'Git blob helper must be unique.' }
        $script:BlobReaderModule = New-Module -ScriptBlock ([scriptblock]::Create($functionAst[0].Extent.Text))
        $script:FakeGitPath = Join-Path $PSHOME 'pwsh.exe'
        $script:FakeGitScript = Join-Path $TestDrive 'fake-git.ps1'
        [IO.File]::WriteAllText($script:FakeGitScript, @'
if (-not (Test-Path -LiteralPath $env:TEST_FAKE_GIT_SENTINEL)) {
    [IO.File]::WriteAllText($env:TEST_FAKE_GIT_SENTINEL, 'ready')
    if ($env:TEST_FAKE_GIT_MODE -eq 'hang-tree') {
        [IO.File]::AppendAllText($env:TEST_FAKE_GIT_PID_FILE, "$PID`n")
        $info = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30')) {
            [void]$info.ArgumentList.Add($argument)
        }
        $child = [Diagnostics.Process]::Start($info)
        [IO.File]::AppendAllText($env:TEST_FAKE_GIT_PID_FILE, "$($child.Id)`n")
        $child.Dispose()
        Start-Sleep -Seconds 30
        exit 0
    }
    [Console]::Out.WriteLine("100644 blob aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`tfile.txt")
    exit 0
}
switch ($env:TEST_FAKE_GIT_MODE) {
    'failed' {
        [Console]::Error.Write('expected fake Git failure')
        [Environment]::Exit(23)
    }
    'flood' {
        [Console]::Error.Write(('e' * 131072))
        [Console]::Out.Write(('a' * 131072))
        exit 0
    }
    'hang' {
        [IO.File]::AppendAllText($env:TEST_FAKE_GIT_PID_FILE, "$PID`n")
        $info = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30')) {
            [void]$info.ArgumentList.Add($argument)
        }
        $child = [Diagnostics.Process]::Start($info)
        [IO.File]::AppendAllText($env:TEST_FAKE_GIT_PID_FILE, "$($child.Id)`n")
        $child.Dispose()
        Start-Sleep -Seconds 30
        exit 0
    }
    default {
        [Console]::Out.Write('hello')
        exit 0
    }
}
'@, [Text.UTF8Encoding]::new($false))

        function Invoke-FakeBlobReader {
            param([string] $Mode, [int] $TimeoutSeconds, [string] $PidFile)
            $previousMode = $env:TEST_FAKE_GIT_MODE
            $previousPidFile = $env:TEST_FAKE_GIT_PID_FILE
            $previousSentinel = $env:TEST_FAKE_GIT_SENTINEL
            try {
                $env:TEST_FAKE_GIT_MODE = $Mode
                $env:TEST_FAKE_GIT_PID_FILE = $PidFile
                $env:TEST_FAKE_GIT_SENTINEL = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.sentinel')
                $fakeCommand = "& '$($script:FakeGitScript.Replace("'", "''"))' #"
                & $script:BlobReaderModule {
                    param($gitPath, $root, $timeout)
                    Get-GitBlobSha256 -GitPath $gitPath -RepositoryRoot $root -Revision ('b' * 40) `
                        -RelativePath 'file.txt' -ProcessTimeoutSeconds $timeout
                } $script:FakeGitPath $fakeCommand $TimeoutSeconds
            }
            finally {
                $env:TEST_FAKE_GIT_MODE = $previousMode
                $env:TEST_FAKE_GIT_PID_FILE = $previousPidFile
                $env:TEST_FAKE_GIT_SENTINEL = $previousSentinel
            }
        }
    }

    # Scenario: A pinned regular blob is read through a well-behaved Git child.
    # Purpose: Preserve exact byte hashing and successful true-exit semantics.
    It 'InterT05_returns_exact_hash_for_successful_blob' {
        Invoke-FakeBlobReader -Mode 'normal' -TimeoutSeconds 5 |
            Should -Be '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
    }

    # Scenario: Git writes more than a pipe buffer to stderr before writing a large blob.
    # Purpose: Drain both redirected streams concurrently without an unbounded capture or deadlock.
    It 'InterT10_drains_large_stderr_while_hashing_stdout' {
        $expected = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes(('a' * 131072)))).ToLowerInvariant()
        Invoke-FakeBlobReader -Mode 'flood' -TimeoutSeconds 5 | Should -Be $expected
    }

    # Scenario: The Git child fails after writing a diagnostic to stderr.
    # Purpose: Preserve its actual nonzero exit and a bounded diagnostic tail.
    It 'InterT20_reports_the_true_nonzero_exit' {
        { Invoke-FakeBlobReader -Mode 'failed' -TimeoutSeconds 5 } |
            Should -Throw '*exit 23*expected fake Git failure*'
    }

    # Scenario: Git and an owned child stay alive past the per-blob deadline.
    # Purpose: Fail within a fixed bound and terminate the entire owned process tree.
    It 'InterT30_kills_a_stalled_git_process_tree' {
        $pidFile = Join-Path $TestDrive 'owned-pids.txt'
        $clock = [Diagnostics.Stopwatch]::StartNew()
        { Invoke-FakeBlobReader -Mode 'hang' -TimeoutSeconds 3 -PidFile $pidFile } |
            Should -Throw '*timed out*'
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 10
        $pids = @(Get-Content -LiteralPath $pidFile | ForEach-Object { [int]$_ })
        $pids.Count | Should -Be 2
        foreach ($ownedPid in $pids) {
            (Get-Process -Id $ownedPid -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }

    # Scenario: Git stalls before identifying the pinned path and owns a child.
    # Purpose: Bound the complete blob lookup and clean up the preceding ls-tree process tree.
    It 'InterT40_kills_a_stalled_tree_lookup' {
        $pidFile = Join-Path $TestDrive 'tree-owned-pids.txt'
        $clock = [Diagnostics.Stopwatch]::StartNew()
        { Invoke-FakeBlobReader -Mode 'hang-tree' -TimeoutSeconds 3 -PidFile $pidFile } |
            Should -Throw '*tree lookup timed out*'
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 10
        $pids = @(Get-Content -LiteralPath $pidFile | ForEach-Object { [int]$_ })
        $pids.Count | Should -Be 2
        foreach ($ownedPid in $pids) {
            (Get-Process -Id $ownedPid -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }
}
