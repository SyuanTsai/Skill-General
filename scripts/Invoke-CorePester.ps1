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
try {
    # Repository tests exercise non-zero native children; let Pester evaluate their assertions.
    $ErrorActionPreference = 'Continue'
    $result = Invoke-Pester -Path $testRoot -Output None -PassThru 3>$null 6>$null
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($null -eq $result) { throw 'Pester did not return a result object.' }
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
