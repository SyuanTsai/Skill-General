# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 6 } | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pesterModule) { throw 'Core validation requires an installed Pester 6.x module.' }
Import-Module -Name $pesterModule.Path -ErrorAction Stop
$testRoot = Join-Path ([IO.Path]::GetFullPath((Get-Location).Path)) 'tests'
if (-not (Test-Path -LiteralPath $testRoot -PathType Container)) {
    throw "Canonical Pester test root is missing: $testRoot"
}
$previousErrorActionPreference = $ErrorActionPreference
$progressCharacters = 0
$progressLimit = 300000
$completedCases = 0
$activeCaseNames = [Collections.Generic.List[string]]::new()
$progressCapped = $false
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = $testRoot
$pesterConfig.Run.PassThru = $true
$pesterConfig.Output.Verbosity = 'Detailed'
$pesterConfig.Debug.ShowStartMarkers = $true
try {
    # Repository tests exercise non-zero native children; let Pester evaluate their assertions.
    # Keep the machine report on stdout and bounded live test progress on stderr.
    $ErrorActionPreference = 'Continue'
    $result = Invoke-Pester -Configuration $pesterConfig 3>$null 6>&1 |
        ForEach-Object {
            if ($_ -is [Management.Automation.InformationRecord]) {
                foreach ($rawLine in @(([string]$_.MessageData) -split '\r?\n')) {
                    $line = ([string]$rawLine) -replace '\x1b\[[0-9;]*m', ''
                    if ($line -notmatch '^\s*(Running tests from|Describing|Context|\[[+!|\-]\]|Tests completed)') { continue }
                    $phase = 'status'
                    if ($line -match '^\s*\[\|\]\s+(?<caseName>.+)$') {
                        $caseName = [string]$Matches.caseName
                        if ($caseName.EndsWith('...', [StringComparison]::Ordinal)) {
                            $caseName = $caseName.Substring(0, $caseName.Length - 3)
                        }
                        $activeCaseNames.Add($caseName)
                        $phase = 'case-start'
                    }
                    elseif ($line -match '^\s*\[[+!\-]\]\s+(?<caseName>.+)$' -and $activeCaseNames.Count -gt 0) {
                        $last = $activeCaseNames.Count - 1
                        if ($activeCaseNames[$last] -ceq [string]$Matches.caseName) {
                            $activeCaseNames.RemoveAt($last)
                            $completedCases++
                            $phase = 'case-end'
                        }
                    }
                    elseif ($line -match '^\s*Running tests from') { $phase = 'file-start' }
                    if ($line.Length -gt 300) { $line = $line.Substring(0, 300) + '[truncated]' }
                    $entry = "Pester progress utc=$([DateTimeOffset]::UtcNow.ToString('o')) completed=$completedCases phase=$phase $line"
                    if ($progressCharacters + $entry.Length -le $progressLimit) {
                        [Console]::Error.WriteLine($entry)
                        $progressCharacters += $entry.Length
                    }
                    elseif (-not $progressCapped) {
                        [Console]::Error.WriteLine('Pester live progress cap reached.')
                        $progressCapped = $true
                    }
                }
            }
            else { $_ }
        }
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($null -eq $result) { throw 'Pester did not return a result object.' }
# Pester's result objects retain actual start instants and durations even when
# the host buffers live InformationRecord lines. Emit a bounded timing ledger
# on stderr after completion; stdout remains the single machine JSON report.
$script:timingCharacters = 0
$script:timingLimit = 300000
$script:timingCapped = $false
function Write-PesterTiming {
    param([Parameter(Mandatory)] $Timing)
    $line = 'Pester timing ' + ($Timing | ConvertTo-Json -Compress -Depth 3)
    if ($script:timingCharacters + $line.Length -le $script:timingLimit) {
        [Console]::Error.WriteLine($line)
        $script:timingCharacters += $line.Length
    }
    elseif (-not $script:timingCapped) {
        [Console]::Error.WriteLine('Pester timing cap reached.')
        $script:timingCapped = $true
    }
}
foreach ($container in @($result.Containers)) {
    if ($null -eq $container -or $null -eq $container.ExecutedAt -or
        [DateTime]$container.ExecutedAt -eq [DateTime]::MinValue) { continue }
    $startUtc = ([DateTime]$container.ExecutedAt).ToUniversalTime()
    $duration = [TimeSpan]$container.Duration
    $timing = [ordered]@{
        kind = 'file'; name = ([string]$container.Name).Substring(0, [Math]::Min(200, ([string]$container.Name).Length))
        startedUtc = $startUtc.ToString('o'); endedUtc = $startUtc.Add($duration).ToString('o')
        elapsedMilliseconds = [Math]::Round($duration.TotalMilliseconds, 3)
        result = [string]$container.Result
    }
    Write-PesterTiming -Timing $timing
}
foreach ($failedContainer in @($result.FailedContainers)) {
    if ($null -eq $failedContainer -or
        ($null -ne $failedContainer.ExecutedAt -and [DateTime]$failedContainer.ExecutedAt -ne [DateTime]::MinValue)) { continue }
    $name = [string]$failedContainer.Name
    $timing = [ordered]@{
        kind = 'file-failure'; name = $name.Substring(0, [Math]::Min(200, $name.Length))
        observedUtc = [DateTimeOffset]::UtcNow.ToString('o')
        startedUtc = $null; endedUtc = $null; elapsedMilliseconds = $null
        result = 'Failed'; timingAvailable = $false
    }
    Write-PesterTiming -Timing $timing
}
foreach ($test in @($result.Tests)) {
    if ($null -eq $test -or $null -eq $test.ExecutedAt -or
        [DateTime]$test.ExecutedAt -eq [DateTime]::MinValue) { continue }
    $startUtc = ([DateTime]$test.ExecutedAt).ToUniversalTime()
    $duration = [TimeSpan]$test.Duration
    $name = [string]$test.ExpandedPath
    $timing = [ordered]@{
        kind = 'case'; name = $name.Substring(0, [Math]::Min(200, $name.Length))
        startedUtc = $startUtc.ToString('o'); endedUtc = $startUtc.Add($duration).ToString('o')
        elapsedMilliseconds = [Math]::Round($duration.TotalMilliseconds, 3)
        result = [string]$test.Result
    }
    Write-PesterTiming -Timing $timing
}
$total = [int]$result.TotalCount
$passed = [int]$result.PassedCount
$failed = [int]$result.FailedCount
$failedBlocks = [int]$result.FailedBlocksCount
$failedContainers = [int]$result.FailedContainersCount
$skipped = [int]$result.SkippedCount
foreach ($failedContainer in @($result.FailedContainers)) {
    [Console]::Error.WriteLine("Pester container failed: $($failedContainer.Name)")
    foreach ($failure in @($failedContainer.ErrorRecord)) {
        [Console]::Error.WriteLine("Pester container error: $($failure.Exception.Message)")
    }
}
foreach ($failedBlock in @($result.FailedBlocks)) {
    [Console]::Error.WriteLine("Pester block failed: $($failedBlock.Name)")
    foreach ($failure in @($failedBlock.ErrorRecord)) {
        [Console]::Error.WriteLine("Pester block error: $($failure.Exception.Message)")
    }
}
foreach ($failedTest in @($result.Failed)) {
    [Console]::Error.WriteLine("Pester test failed: $($failedTest.ExpandedPath)")
    foreach ($failure in @($failedTest.ErrorRecord)) {
        [Console]::Error.WriteLine("Pester test error: $($failure.Exception.Message)")
    }
}
$summary = [ordered]@{
    schemaVersion = 1
    report = 'standard-core-pester-result-v1'
    total = $total
    passed = $passed
    failed = $failed
    skipped = $skipped
}
$summary | ConvertTo-Json -Compress
if ($total -le 0 -or $passed -le 0 -or $failed -ne 0 -or $failedBlocks -ne 0 -or
    $failedContainers -ne 0 -or ($passed + $skipped) -ne $total) {
    exit 1
}
exit 0
