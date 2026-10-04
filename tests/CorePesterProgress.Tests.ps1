# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Core Pester progress' {
    # Scenario: Pester displays a parameterized template at case start and its expanded name at completion.
    # Purpose: Keep the live completed count aligned with the authoritative final case count.
    It 'InterT10_counts_parameterized_case_completion_without_changing_the_JSON_result' {
        $fixtureRoot = Join-Path $TestDrive 'parameterized-progress'
        $moduleRoot = Join-Path $fixtureRoot 'modules'
        $pesterRoot = Join-Path $moduleRoot 'Pester/6.99.0'
        $candidateRoot = Join-Path $fixtureRoot 'candidate'
        [void](New-Item -ItemType Directory -Path $pesterRoot, (Join-Path $candidateRoot 'tests') -Force)
        [IO.File]::WriteAllText((Join-Path $candidateRoot 'tests/fixture.Tests.ps1'), "It 'fixture' {}`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $pesterRoot 'Pester.psd1'), @'
@{
    RootModule = 'Pester.psm1'
    ModuleVersion = '6.99.0'
    GUID = '4812fd7a-9960-4bb9-ad55-83d9e136145a'
    FunctionsToExport = @('New-PesterConfiguration', 'Invoke-Pester')
}
'@, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $pesterRoot 'Pester.psm1'), @'
function New-PesterConfiguration {
    [pscustomobject]@{
        Run = [pscustomobject]@{ Path = ''; PassThru = $false }
        Output = [pscustomobject]@{ Verbosity = '' }
        Debug = [pscustomobject]@{ ShowStartMarkers = $false }
    }
}
function Invoke-Pester {
    param($Configuration)
    $started = [DateTime]::UtcNow
    Write-Information 'Running tests from 1 files.' -InformationAction Continue
    Write-Information "Running tests from 'fixture.Tests.ps1'" -InformationAction Continue
    Write-Information '  [|] Case <Value>...' -InformationAction Continue
    Write-Information '  [+] Case alpha' -InformationAction Continue
    Write-Information '  [|] Plain case...' -InformationAction Continue
    Write-Information '  [+] Plain case' -InformationAction Continue
    [pscustomobject]@{
        Containers = @([pscustomobject]@{ Name = 'fixture.Tests.ps1'; ExecutedAt = $started; Duration = [TimeSpan]::FromMilliseconds(2); Result = 'Passed' })
        FailedContainers = @()
        FailedBlocks = @()
        Failed = @()
        Tests = @(
            [pscustomobject]@{ ExpandedPath = 'Case alpha'; ExecutedAt = $started; Duration = [TimeSpan]::FromMilliseconds(1); Result = 'Passed' },
            [pscustomobject]@{ ExpandedPath = 'Plain case'; ExecutedAt = $started; Duration = [TimeSpan]::FromMilliseconds(1); Result = 'Passed' }
        )
        TotalCount = 2
        PassedCount = 2
        FailedCount = 0
        FailedBlocksCount = 0
        FailedContainersCount = 0
        SkippedCount = 0
    }
}
Export-ModuleMember -Function New-PesterConfiguration, Invoke-Pester
'@, [Text.UTF8Encoding]::new($false))

        $pwsh = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Invoke-CorePester.ps1'
        $startInfo = [Diagnostics.ProcessStartInfo]::new($pwsh)
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $runner)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.WorkingDirectory = $candidateRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.Environment['PSModulePath'] = $moduleRoot
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            [void]$process.Start()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(20000)) {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
                throw 'Core Pester fixture exceeded its 20-second bound.'
            }
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            $process.ExitCode | Should -Be 0
            $reportLines = @(($stdout.Trim()) -split '\r?\n')
            $reportLines.Count | Should -Be 1
            $report = $reportLines[0] | ConvertFrom-Json
            $report.total | Should -Be 2
            $report.passed | Should -Be 2
            $report.failed | Should -Be 0
            $stderr | Should -Match 'completed=1 phase=case-end\s+\[\+\] Case alpha'
            $stderr | Should -Match 'completed=2 phase=case-end\s+\[\+\] Plain case'
        }
        finally {
            $process.Dispose()
        }
    }
}
