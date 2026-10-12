# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Windows-only support boundary for General Skills' {
    BeforeAll {
        function Test-AllowedWindowsOnlyPreamble {
            param([Parameter(Mandatory)][System.Management.Automation.Language.StatementAst] $Statement)

            if ($Statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                $right = $Statement.Right
                if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) {
                    $right = $right.Expression
                }
                $isStopLiteral = $right -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $right.Value -ceq 'Stop'
                return ($Statement.Operator -eq [System.Management.Automation.Language.TokenKind]::Equals -and
                    $Statement.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Statement.Left.VariablePath.UserPath -ceq 'ErrorActionPreference' -and $isStopLiteral)
            }

            if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and
                $Statement.PipelineElements.Count -eq 1 -and
                $Statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
                $command = $Statement.PipelineElements[0]
                $commands = @($command.CommandElements)
                return ($command.GetCommandName() -ceq 'Set-StrictMode' -and $commands.Count -eq 3 -and
                    $commands[1].Extent.Text -ceq '-Version' -and $commands[2].Extent.Text -ceq 'Latest')
            }

            return $false
        }

        function Get-WindowsOnlyEntryGateAssessment {
            param([Parameter(Mandatory)][string] $Source)

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$parseErrors)
            $statements = @($ast.EndBlock.Statements)
            $guard = $null
            $firstWork = $null

            foreach ($statement in $statements) {
                $isWindowsGuard = $false
                if ($statement -is [System.Management.Automation.Language.IfStatementAst]) {
                    foreach ($clause in $statement.Clauses) {
                        if ($clause.Item1.Extent.Text -match '(?i)\$IsWindows|\[(?:System\.)?Environment\]::OSVersion\.Platform') {
                            $isWindowsGuard = $true
                            if ($null -eq $guard) { $guard = $statement }
                            break
                        }
                    }
                }

                if ($isWindowsGuard) {
                    if ($null -eq $firstWork) { $firstWork = $statement }
                    continue
                }
                if (Test-AllowedWindowsOnlyPreamble -Statement $statement) { continue }
                if ($null -eq $firstWork) { $firstWork = $statement }
            }

            [pscustomobject]@{
                Ast = $ast
                ParseErrors = @($parseErrors)
                Guard = $guard
                FirstWork = $firstWork
                GuardBeforeWork = ($null -ne $guard -and $null -ne $firstWork -and
                    $guard.Extent.StartOffset -eq $firstWork.Extent.StartOffset)
            }
        }

        function Get-WorkflowJobRunners {
            param([Parameter(Mandatory)][string] $Text)

            $lines = @($Text -split '\r?\n')
            $jobsSections = @()
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -cmatch '^jobs:\s*(?:#.*)?$') { $jobsSections += $index }
            }
            if ($jobsSections.Count -ne 1) { throw 'Workflow must have one top-level jobs section.' }

            $jobs = [Collections.Generic.List[object]]::new()
            $currentJob = $null
            for ($index = $jobsSections[0] + 1; $index -lt $lines.Count; $index++) {
                $line = $lines[$index]
                if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
                if ($line -cmatch '^\S') { break }
                if ($line -cmatch '^  (?<job>[A-Za-z0-9_-]+):\s*(?:#.*)?$') {
                    $currentJob = [pscustomobject]@{
                        Name = $Matches.job
                        Lines = [Collections.Generic.List[string]]::new()
                    }
                    $jobs.Add($currentJob)
                    continue
                }
                if ($line -cmatch '^  \S') { throw 'Workflow uses unsupported jobs-level YAML syntax.' }
                if ($null -eq $currentJob) { throw 'Workflow has content before its first jobs-level entry.' }
                $currentJob.Lines.Add($line)
            }
            if ($jobs.Count -eq 0) { throw 'Workflow has no supported jobs-level entries.' }

            foreach ($job in $jobs) {
                if (@($job.Lines | Where-Object { $_ -cmatch '^\s*(?:strategy|matrix)\s*:' }).Count -gt 0) {
                    throw ("Workflow job '{0}' must use one explicit Windows runner, without a matrix." -f $job.Name)
                }
                $runnerLines = @($job.Lines | Where-Object { $_ -cmatch '^\s{4}runs-on:\s*' })
                if ($runnerLines.Count -ne 1) {
                    throw ("Workflow job '{0}' must declare exactly one runs-on value." -f $job.Name)
                }
                $runner = $runnerLines[0] -replace '^\s{4}runs-on:\s*', ''
                $runner = ($runner -split '\s+#', 2)[0].Trim()
                if ($runner -cne 'windows-latest') {
                    throw ("Workflow job '{0}' uses an unsupported runner value." -f $job.Name)
                }
                [pscustomobject]@{ Job = $job.Name; Runner = $runner }
            }
        }

        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:CapabilityPatterns = @{
            'investigate-datadog-logs' = 'Datadog|APM'
            'manage-ai-memory' = 'memory|records|file references'
            'manage-task-handoff' = 'Handoff|task progress'
            'operate-environment-authorized-sql' = 'Azure SQL'
            'plan-production-change' = 'production|implementation plans'
            'review-agent-skills' = 'Agent Skill|Skill package'
            'verify-data-access-performance' = 'query|data-access|performance'
        }
        $script:ExpectedSkillIds = @($script:CapabilityPatterns.Keys | Sort-Object -CaseSensitive)
        $script:GuardPaths = @(
            'scripts/Validate.ps1',
            'scripts/Test-SkillGeneral.ps1',
            'scripts/Invoke-CorePester.ps1',
            'scripts/Prepare-PesterRuntime.ps1',
            'skills/operate-environment-authorized-sql/scripts/Test-Contract.ps1',
            'skills/manage-task-handoff/scripts/HandoffRecordCore.psm1',
            'skills/manage-task-handoff/scripts/LegacyNotionHandoffReplay.psm1'
        )
    }

    # Scenario: A consumer discovers each package from its description, UI card, or loaded body.
    # Purpose: Keep capability routing intact while making the supported local and CI host explicit.
    It 'UnitT10_DeclaresWindowsOnlyHostWithoutLosingEachCapabilityRoute' {
        $sourcePath = Join-Path $script:RepoRoot 'catalog/source.json'
        $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json -Depth 20
        $skillIds = @($source.skills)
        $skillIds.Count | Should -Be $script:ExpectedSkillIds.Count
        foreach ($expectedId in $script:ExpectedSkillIds) {
            $skillIds | Should -Contain $expectedId
        }
        foreach ($skillId in $skillIds) {
            $script:CapabilityPatterns.ContainsKey($skillId) | Should -BeTrue -Because ("Add a capability route assertion for {0}." -f $skillId)
            $skillPath = Join-Path $script:RepoRoot ("skills/{0}/SKILL.md" -f $skillId)
            $metadataPath = Join-Path $script:RepoRoot ("skills/{0}/agents/openai.yaml" -f $skillId)
            $skillText = Get-Content -LiteralPath $skillPath -Raw
            $metadataText = Get-Content -LiteralPath $metadataPath -Raw
            $frontmatterMatch = [regex]::Match($skillText, '(?s)\A---\s*(?<frontmatter>.*?)\s*---\s*')
            $frontmatterMatch.Success | Should -BeTrue -Because $skillId
            $descriptionMatch = [regex]::Match($frontmatterMatch.Groups['frontmatter'].Value, '(?m)^description:\s*(?<value>.+)$')
            $descriptionMatch.Success | Should -BeTrue -Because $skillId
            $description = $descriptionMatch.Groups['value'].Value
            $description | Should -Match 'windows-only' -Because $skillId
            $description | Should -Match $script:CapabilityPatterns[$skillId] -Because $skillId

            $body = $skillText.Substring($frontmatterMatch.Length)
            $body | Should -Match '(?i)Windows.{0,80}only supported host' -Because $skillId
            foreach ($localActivity in @('development', 'installation', 'execution', 'testing', 'acceptance')) {
                $body | Should -Match ("(?i)\b{0}\b" -f $localActivity) -Because $skillId
            }
            $body | Should -Match '(?i)(only supported CI host|CI runs only on Windows|Windows is the only supported CI host)' -Because $skillId
            $body | Should -Match '(?is)(external SaaS|remote service).{0,120}(outside|not limited|not constrained)' -Because $skillId

            $shortMatch = [regex]::Match($metadataText, '(?m)^\s*short_description:\s*"(?<value>[^"]*)"')
            $shortMatch.Success | Should -BeTrue -Because $skillId
            $shortDescription = $shortMatch.Groups['value'].Value
            $shortDescription.Length | Should -BeGreaterThan 24 -Because $skillId
            $shortDescription.Length | Should -BeLessThan 65 -Because $skillId
            $shortDescription | Should -Match 'windows-only' -Because $skillId
            $shortDescription | Should -Match $script:CapabilityPatterns[$skillId] -Because $skillId

            $promptMatch = [regex]::Match($metadataText, '(?m)^\s*default_prompt:\s*"(?<value>[^"]*)"')
            $promptMatch.Success | Should -BeTrue -Because $skillId
            $promptMatch.Groups['value'].Value | Should -Match ([regex]::Escape('$' + $skillId)) -Because $skillId
            $promptMatch.Groups['value'].Value | Should -Match '(?i)Windows' -Because $skillId
        }

        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
        $readme | Should -Match '(?i)Windows.{0,80}only supported host'
        foreach ($localActivity in @('development', 'installation', 'execution', 'testing', 'acceptance')) {
            $readme | Should -Match ("(?i)\b{0}\b" -f $localActivity)
        }
        $readme | Should -Match '(?i)(only supported CI host|CI runs only on Windows|Windows is the only supported CI host)'
        $readme | Should -Match '(?is)(external SaaS|remote service).{0,120}(outside|not limited|not constrained)'
        $readme | Should -Match '(?i)provider/storage-neutral.*does not expand local host support beyond Windows'
    }

    # Scenario: A local validation or package script is invoked on an unsupported host.
    # Purpose: Reject execution before the script performs work, and exercise both guard outcomes.
    It 'UnitT20_FailsClosedAtLocalEntrypointsBeforeWorkOnUnsupportedHosts' {
        foreach ($relativePath in $script:GuardPaths) {
            $path = Join-Path $script:RepoRoot $relativePath
            $sourceText = Get-Content -LiteralPath $path -Raw
            $assessment = Get-WindowsOnlyEntryGateAssessment -Source $sourceText
            $assessment.ParseErrors.Count | Should -Be 0 -Because $relativePath
            $assessment.Guard | Should -Not -BeNullOrEmpty -Because $relativePath
            $assessment.GuardBeforeWork | Should -BeTrue -Because $relativePath
            $assessment.Guard.Extent.Text | Should -Match '(?is)throw\s+["''].*Windows hosts only' -Because $relativePath

            $guardText = $assessment.Guard.Extent.Text
            if ($relativePath -like '*HandoffRecordCore.psm1' -or $relativePath -like '*LegacyNotionHandoffReplay.psm1') {
                $guardText | Should -Match '(?i)\[(?:System\.)?Environment\]::OSVersion\.Platform\s*-ne\s*\[(?:System\.)?PlatformID\]::Win32NT' -Because $relativePath
                $guardText = [regex]::Replace(
                    $guardText,
                    '(?i)\[(?:System\.)?Environment\]::OSVersion\.Platform\s*-ne\s*\[(?:System\.)?PlatformID\]::Win32NT',
                    '-not $TestWindowsHost'
                )
            }
            else {
                $guardText | Should -Match '\$IsWindows' -Because $relativePath
                $guardText = [regex]::Replace($guardText, '(?i)\$IsWindows', '$TestWindowsHost')
            }
            $guardSource = 'param([bool]' + [char]36 + 'TestWindowsHost)' + [Environment]::NewLine + $guardText
            $guardScript = [scriptblock]::Create($guardSource)
            $unsupportedWasRejected = $false
            try { & $guardScript $false } catch { $unsupportedWasRejected = $_.Exception.Message -match 'Windows hosts only' }
            $unsupportedWasRejected | Should -BeTrue -Because $relativePath
            { & $guardScript $true } | Should -Not -Throw -Because $relativePath
        }
    }

    # Scenario: A guard is removed or moved below an operation in a test fixture.
    # Purpose: Prove the entrypoint assessment rejects both missing and late guards.
    It 'UnitT25_RejectsMissingOrLateHostGuards' {
        $lateGuard = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Output 'work before guard'
if (-not $IsWindows) { throw 'Windows hosts only.' }
'@
        $missingGuard = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Output 'work without guard'
'@
        (Get-WindowsOnlyEntryGateAssessment -Source $lateGuard).GuardBeforeWork | Should -BeFalse
        (Get-WindowsOnlyEntryGateAssessment -Source $missingGuard).Guard | Should -BeNullOrEmpty
    }

    # Scenario: A workflow is added, or an existing job runner changes.
    # Purpose: Keep every discovered CI job on the sole supported host and fail closed on matrices.
    It 'UnitT30_KeepsEveryWorkflowJobOnOneWindowsRunner' {
        $workflowRoot = Join-Path $script:RepoRoot '.github/workflows'
        $workflowPaths = @(Get-ChildItem -LiteralPath $workflowRoot -File | Where-Object { $_.Extension -in @('.yml', '.yaml') })
        $workflowPaths.Count | Should -BeGreaterThan 0
        foreach ($workflowPath in $workflowPaths) {
            $runners = @(Get-WorkflowJobRunners -Text (Get-Content -LiteralPath $workflowPath.FullName -Raw))
            $runners.Count | Should -BeGreaterThan 0 -Because $workflowPath.Name
            foreach ($runner in $runners) {
                $runner.Runner | Should -Be 'windows-latest' -Because ("{0}/{1}" -f $workflowPath.Name, $runner.Job)
            }
        }

        $validWorkflow = @'
name: sample
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: windows-latest
    steps:
      - run: echo ok
'@
        (Get-WorkflowJobRunners -Text $validWorkflow).Runner | Should -Be 'windows-latest'
        $unsupportedWorkflow = $validWorkflow.Replace('windows-latest', 'ubuntu-latest')
        { Get-WorkflowJobRunners -Text $unsupportedWorkflow } | Should -Throw '*unsupported runner*'
        $matrixWorkflow = $validWorkflow.Replace('windows-latest', ([string][char]36 + '{{ matrix.os }}'))
        { Get-WorkflowJobRunners -Text $matrixWorkflow } | Should -Throw '*unsupported runner*'
        $missingRunnerWorkflow = [regex]::Replace($validWorkflow, '(?m)^    runs-on: windows-latest\r?$', '')
        { Get-WorkflowJobRunners -Text $missingRunnerWorkflow } | Should -Throw '*runs-on*'
    }
}
