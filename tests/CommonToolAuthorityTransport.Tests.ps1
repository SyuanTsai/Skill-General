# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Legacy sanitized child authority transport' {
    # Scenario: the protected legacy runner launches Pester after clearing custom environment.
    # Purpose: prove the real Core-era Pester 6 suite consumes only the verified commit-named TEMP snapshot.
    It 'InterT30_runs_the_real_CommonTool_suite_in_a_sanitized_Pester6_child' {
        $repositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
        $pin = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'config/standard-v1.json') -Raw -Encoding utf8 | ConvertFrom-Json).authority
        $sourceRoot = [Environment]::GetEnvironmentVariable('SYP154_CANDIDATE_AUTHORITY_ROOT', 'Process')
        if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
            $sourceRoot = Join-Path ([IO.Path]::GetTempPath()) ('syp154-authority-' + [string]$pin.commit)
        }
        $sourceRoot = [IO.Path]::GetFullPath($sourceRoot)
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            throw 'The explicit authority setup did not provide a candidate-pinned source snapshot.'
        }

        $gitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $safeSource = 'safe.directory=' + $sourceRoot
        $sourceHead = @(& $gitPath -c $safeSource -C $sourceRoot rev-parse --verify HEAD)
        if ($LASTEXITCODE -ne 0 -or $sourceHead.Count -ne 1 -or [string]$sourceHead[0] -cne [string]$pin.commit) {
            throw 'Sanitized child fixture source is not the exact candidate authority commit.'
        }
        $sourceDirty = @(& $gitPath -c $safeSource -C $sourceRoot status --porcelain=v1 --untracked-files=all)
        if ($LASTEXITCODE -ne 0 -or $sourceDirty.Count -ne 0) { throw 'Sanitized child fixture source must be clean.' }

        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('sc-' + [guid]::NewGuid().ToString('N'))
        $tempRoot = Join-Path $testRoot 'temp'
        [void](New-Item -ItemType Directory -Path $tempRoot -Force)
        $snapshotRoot = Join-Path $tempRoot ('syp154-authority-' + [string]$pin.commit)
        $helperPath = Join-Path $testRoot 'run-common-tool-pester6.ps1'
        $process = $null
        try {
            & $gitPath -c $safeSource -c core.longpaths=true clone --config core.autocrlf=false --local --no-hardlinks $sourceRoot $snapshotRoot 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated local authority transport fixture.' }
            & $gitPath -C $snapshotRoot remote set-url origin ([string]$pin.repository)
            if ($LASTEXITCODE -ne 0) { throw 'Could not bind the transport fixture to the pinned origin.' }
            & $gitPath -c core.longpaths=true -C $snapshotRoot checkout --detach ([string]$pin.commit)
            if ($LASTEXITCODE -ne 0) { throw 'Could not bind the transport fixture to the exact pinned commit.' }
            foreach ($entry in @($pin.files)) {
                $path = [IO.Path]::GetFullPath((Join-Path $snapshotRoot ([string]$entry.path -replace '/', [IO.Path]::DirectorySeparatorChar)))
                if (-not $path.StartsWith($snapshotRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Test-Path -LiteralPath $path -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.sha256) {
                    throw "Isolated authority transport fixture differs from its source pin: $($entry.path)"
                }
            }

            $pesterModules = @(Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [version]'6.2.0' })
            if ($pesterModules.Count -ne 1) {
                throw 'Sanitized child transport requires one actual preinstalled Pester 6.2.0 module; no substitution is permitted.'
            }
            $modulePath = [IO.Path]::GetFullPath([string]$pesterModules[0].Path)
            $moduleSearchRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $modulePath))
            $pwshPath = Join-Path $PSHOME 'pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) { throw 'The current approved PowerShell runtime has no child executable.' }

            $helper = @'
param([Parameter(Mandatory)][string] $PesterModulePath, [Parameter(Mandatory)][string] $TestPath)
$ErrorActionPreference = 'Stop'
foreach ($name in @('SYP154_CANDIDATE_AUTHORITY_ROOT','STANDARD_VALIDATION_CORE_RUN_ID','STANDARD_VALIDATION_CORE_CHECK_ID')) {
    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "Sanitized legacy child inherited forbidden authority context: $name"
    }
}
$modules = @(Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [version]'6.2.0' })
if ($modules.Count -ne 1 -or [IO.Path]::GetFullPath([string]$modules[0].Path) -cne [IO.Path]::GetFullPath($PesterModulePath)) {
    throw 'Sanitized child did not discover the one exact preinstalled Pester 6.2.0 module.'
}
Import-Module -Name $PesterModulePath -ErrorAction Stop
$configuration = New-PesterConfiguration
$configuration.Run.Path = $TestPath
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$configuration.TestRegistry.Enabled = $false
$result = Invoke-Pester -Configuration $configuration 6>$null
$summary = [ordered]@{ version = [string](Get-Module Pester).Version; total = [int]$result.TotalCount; passed = [int]$result.PassedCount; failed = [int]$result.FailedCount; skipped = [int]$result.SkippedCount; coreContextAbsent = $true; scopedRootAbsent = $true }
[Console]::Out.WriteLine('SYP154_TRANSPORT:' + ($summary | ConvertTo-Json -Compress))
if ($summary.total -le 0 -or $summary.failed -ne 0 -or ($summary.passed + $summary.skipped) -ne $summary.total) {
    foreach ($failedCase in @($result.Failed)) {
        [Console]::Error.WriteLine("Sanitized child failed case: $($failedCase.ExpandedPath)")
        foreach ($failure in @($failedCase.ErrorRecord)) { [Console]::Error.WriteLine("Sanitized child test error: $($failure.Exception.Message)") }
    }
    foreach ($failedBlock in @($result.FailedBlocks)) {
        [Console]::Error.WriteLine("Sanitized child failed block: $($failedBlock.Name)")
        foreach ($failure in @($failedBlock.ErrorRecord)) { [Console]::Error.WriteLine("Sanitized child block error: $($failure.Exception.Message)") }
    }
    foreach ($failedContainer in @($result.FailedContainers)) {
        [Console]::Error.WriteLine("Sanitized child failed container: $($failedContainer.Name)")
        foreach ($failure in @($failedContainer.ErrorRecord)) { [Console]::Error.WriteLine("Sanitized child container error: $($failure.Exception.Message)") }
    }
    exit 1
}
'@
            [IO.File]::WriteAllText($helperPath, $helper, [Text.UTF8Encoding]::new($false))

            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $pwshPath
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.WorkingDirectory = $repositoryRoot
            $startInfo.ArgumentList.Add('-NoLogo')
            $startInfo.ArgumentList.Add('-NoProfile')
            $startInfo.ArgumentList.Add('-NonInteractive')
            $startInfo.ArgumentList.Add('-File')
            $startInfo.ArgumentList.Add($helperPath)
            $startInfo.ArgumentList.Add('-PesterModulePath')
            $startInfo.ArgumentList.Add($modulePath)
            $startInfo.ArgumentList.Add('-TestPath')
            $startInfo.ArgumentList.Add((Join-Path $PSScriptRoot 'CommonToolReportIntegration.Tests.ps1'))
            $startInfo.Environment.Clear()
            foreach ($name in @('PATH','SystemRoot','WINDIR','USERPROFILE','LOCALAPPDATA','APPDATA','HOMEDRIVE','HOMEPATH')) {
                $value = [Environment]::GetEnvironmentVariable($name, 'Process')
                if (-not [string]::IsNullOrWhiteSpace($value)) { $startInfo.Environment[$name] = $value }
            }
            $startInfo.Environment['PATH'] = "$PSHOME;$([IO.Path]::GetDirectoryName($gitPath))"
            $startInfo.Environment['PATHEXT'] = '.EXE'
            $startInfo.Environment['TEMP'] = $tempRoot
            $startInfo.Environment['TMP'] = $tempRoot
            $startInfo.Environment['PSModulePath'] = $moduleSearchRoot
            $startInfo.Environment['STANDARD_VALIDATION_ACTIVE_SKILLS'] = 'demo'
            $startInfo.Environment['STANDARD_VALIDATION_SKILLS_ROOT'] = Join-Path $testRoot 'skills'
            $startInfo.Environment['STANDARD_VALIDATION_SKILL_ID'] = 'demo'
            $startInfo.Environment['STANDARD_VALIDATION_CANDIDATE_ID'] = 'a' * 64
            $startInfo.Environment['STANDARD_VALIDATION_CANDIDATE_ROOT'] = $testRoot
            $startInfo.Environment['STANDARD_VALIDATION_SKILL_INVENTORY_SHA256'] = 'b' * 64
            [void](New-Item -ItemType Directory -Path $startInfo.Environment['STANDARD_VALIDATION_SKILLS_ROOT'] -Force)

            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            if (-not $process.Start()) { throw 'Could not start the sanitized Pester 6 validation child.' }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            $process.ExitCode | Should -Be 0 -Because ("child stdout: {0}; child stderr: {1}" -f $stdout, $stderr)
            $summaryLine = @($stdout -split '\r?\n' | Where-Object { $_ -match '^SYP154_TRANSPORT:' })
            $summaryLine.Count | Should -Be 1
            $summary = $summaryLine[0].Substring('SYP154_TRANSPORT:'.Length) | ConvertFrom-Json
            $summary.version | Should -Be '6.2.0'
            $summary.total | Should -BeGreaterThan 0
            $summary.failed | Should -Be 0
            $summary.skipped | Should -Be 0
            $summary.coreContextAbsent | Should -BeTrue
            $summary.scopedRootAbsent | Should -BeTrue
            $stdout | Should -Match 'SYP154_TRANSPORT:'
        }
        finally {
            if ($null -ne $process) { $process.Dispose() }
            $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
            $actualParent = [IO.Path]::GetFullPath((Split-Path -Parent $testRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar)
            if ($actualParent -cne $expectedParent -or (Split-Path -Leaf $testRoot) -cnotmatch '^sc-[0-9a-f]{32}$') {
                throw 'Refusing to clean a path outside the allocated legacy transport test root.'
            }
            if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
        }
    }
}
