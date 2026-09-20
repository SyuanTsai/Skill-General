# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

Describe 'Semantic Bridge v2 consumer prepare seam' {
    BeforeAll {
function Get-TestEventName {
    switch ([string]$env:GITHUB_EVENT_NAME) {
        'pull_request' { return 'pull_request' }
        'push' { return 'push' }
        'workflow_dispatch' { return 'workflow_dispatch' }
        'pre-push' { return 'pre-push' }
        default { return 'local' }
    }
}

function New-SyntheticResumePlan {
    param(
        [Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [Parameter(Mandatory = $true)][string] $ArtifactsRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $ReceiptTools,
        [string] $RunId = '0123456789abcdef0123456789abcdef',
        [string] $CandidateRevision = ('0' * 40),
        [string] $BaseRevision = ('0' * 40),
        [string] $CandidateTree = ('0' * 40),
        [switch] $WriteReceiptFiles
    )

    $runRoot = Join-Path $ArtifactsRoot "sgv1-$($RunId.Substring(0, 12))"
    [void](New-Item -ItemType Directory -Path $runRoot -Force)
    $receiptBindings = @(
        foreach ($tool in $ReceiptTools) {
            $receiptPath = Join-Path $runRoot "receipt-$tool.json"
            if ($WriteReceiptFiles) {
                $receipt = [ordered]@{
                    schemaVersion = 1
                    resolutionRunId = $RunId
                    toolName = $tool
                    channel = 'latest-stable'
                    resolvedVersion = 'fixture'
                    resolvedIdentity = "fixture-$tool"
                    frozenForRun = $true
                    status = 'verified'
                }
                switch ($tool) {
                    'skillspector' {
                        $receipt.executablePath = Join-Path $runRoot 'skillspector.exe'
                        $receipt.executableSha256 = '1' * 64
                    }
                    'skill-validator' {
                        $receipt.executablePath = Join-Path $runRoot 'skill-validator.exe'
                        $receipt.executableSha256 = '2' * 64
                    }
                    'skill-tools' {
                        $receipt.nodePath = Join-Path $runRoot 'node.exe'
                        $receipt.nodeSha256 = '3' * 64
                        $receipt.entryPointPath = Join-Path $runRoot 'skill-tools.js'
                        $receipt.entryPointSha256 = '4' * 64
                    }
                    'pester' {
                        $receipt.modulePath = Join-Path $runRoot 'Pester.psd1'
                        $receipt.executableSha256 = '5' * 64
                    }
                }
                [IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
            }
            [ordered]@{
                tool = $tool
                path = [IO.Path]::GetFullPath($receiptPath)
                sha256 = if ($WriteReceiptFiles) { (Get-FileHash -Algorithm SHA256 -LiteralPath $receiptPath).Hash.ToLowerInvariant() } else { '0' * 64 }
            }
        }
    )
    $planPath = Join-Path $ArtifactsRoot 'semantic-run-plan.json'
    $plan = [ordered]@{
        schemaVersion = 1
        artifactType = 'standard-validation-consumer-run-plan-v1'
        runId = $RunId
        source = [ordered]@{
            repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
            repository = 'https://github.com/SyuanTsai/Skill-General.git'
            revision = $CandidateRevision
            baseRevision = $BaseRevision
            tree = $CandidateTree
            eventName = Get-TestEventName
        }
        roots = [ordered]@{
            artifacts = [IO.Path]::GetFullPath($ArtifactsRoot)
            run = [IO.Path]::GetFullPath($runRoot)
            trusted = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId"
            candidateExtract = Join-Path ([IO.Path]::GetTempPath()) "sgv1-candidate-$RunId"
            resolvedTools = Join-Path ([IO.Path]::GetTempPath()) "sgv1-resolved-tools-$RunId"
        }
        candidate = [ordered]@{
            archivePath = Join-Path $runRoot 'candidate.zip'
            archiveSha256 = '0' * 64
            snapshotRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-candidate-$RunId\snapshot"
            contentSha256 = '0' * 64
            inventory = @()
            candidateId = '0' * 64
        }
        authority = [ordered]@{
            revision = '8a944f4a74a054cb0353f22ab22c459dc9dc18ef'
            archivePath = Join-Path $runRoot 'authority.zip'
            archiveSha256 = '99ba8cae62c80db9da8876b5a7e49dfdd499ca863c006bfd2a411a5d4e7dbcc0'
            root = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId\authority"
            runnerPath = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId\authority\scripts\Invoke-StandardValidation.ps1"
            runnerSha256 = '0' * 64
        }
        tools = [ordered]@{
            policyReceiptPath = Join-Path $runRoot 'policy.json'
            policyReceiptSha256 = '0' * 64
            receipts = $receiptBindings
            toolchainPath = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId\toolchain.json"
            toolchainSha256 = '0' * 64
            childRunnerPath = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId\child.ps1"
            childRunnerSha256 = '0' * 64
            preparationHelperPath = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId\helper.ps1"
            preparationHelperSha256 = '0' * 64
            preparationPath = Join-Path $runRoot 'semantic-preparation.json'
            preparationSha256 = '0' * 64
            adapterPath = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$RunId\adapter.json"
            adapterSha256 = '0' * 64
        }
        execution = [ordered]@{
            outputPath = Join-Path $ArtifactsRoot 'output.json'
            timeoutSeconds = 1
            semanticTriggered = $true
            consumptionClaimPath = "$planPath.consumed.json"
        }
        semantic = [ordered]@{
            consentRequestPath = Join-Path $ArtifactsRoot 'consent-request.json'
            consentDecisionPath = Join-Path $ArtifactsRoot 'consent-decision.json'
            evidencePath = Join-Path $ArtifactsRoot 'evidence.json'
            publicKeyPath = Join-Path $ArtifactsRoot 'public-key.xml'
            publicKeyId = 'fixture'
        }
    }
    [IO.File]::WriteAllText($planPath, (($plan | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ planPath = $planPath; runRoot = $runRoot; runId = $RunId }
}

function Invoke-SyntheticResume {
    param(
        [Parameter(Mandatory = $true)][string] $ValidatorPath,
        [Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [Parameter(Mandatory = $true)][string] $PlanPath
    )
    $output = @(& pwsh -NoProfile -NonInteractive -File $ValidatorPath `
        -ExecutionMode ResumeSemantic `
        -RepositoryRoot $RepositoryRoot `
        -SemanticRunPlanPath $PlanPath 2>&1)
    $renderedOutput = $output -join [Environment]::NewLine
    $normalizedOutput = (([regex]::Replace($renderedOutput, '\x1B\[[0-9;]*m', ' ')) -replace '\s+', ' ').Trim()
    return [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = $renderedOutput
        normalizedOutput = $normalizedOutput
    }
}

        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
    }

    It 'preserves helper inputs across the dot-sourced central runner parameter scope' {
        $validatorText = Get-Content -LiteralPath $script:ValidatorPath -Raw -Encoding UTF8
        $marker = '$semanticPreparationHelperText = @'''
        $start = $validatorText.IndexOf($marker, [StringComparison]::Ordinal)
        $start | Should -BeGreaterOrEqual 0
        $bodyStart = $validatorText.IndexOf("`n", $start) + 1
        $end = $validatorText.IndexOf("`n'@", $bodyStart, [StringComparison]::Ordinal)
        $end | Should -BeGreaterThan $bodyStart
        $helperText = $validatorText.Substring($bodyStart, $end - $bodyStart).TrimEnd("`r")

        $helperPath = Join-Path $TestDrive 'Get-SkillGeneralSemanticPreparation.ps1'
        $runnerPath = Join-Path $TestDrive 'Invoke-StubStandardValidation.ps1'
        $candidateRoot = Join-Path $TestDrive 'candidate'
        $artifactsRoot = Join-Path $TestDrive 'artifacts'
        $adapterPath = Join-Path $TestDrive 'adapter.json'
        $outputPath = Join-Path $artifactsRoot 'preparation.json'
        [void](New-Item -ItemType Directory -Path $candidateRoot, $artifactsRoot -Force)
        [IO.File]::WriteAllText($helperPath, $helperText, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($adapterPath, "{}`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($runnerPath, @'
param(
    [string] $CandidateRoot,
    [string] $AdapterPath,
    [string] $ArtifactsRoot,
    [string] $SourceRepository,
    [string] $SourceRevision,
    [string] $BaseRevision,
    [string] $EventName,
    [string] $CandidateArchiveSha256,
    [string] $OutputPath,
    [switch] $DefineFunctionsOnly
)
function Get-StandardValidationInventory {
    param([string] $Root, [string] $Context)
    $entries = @(
        [pscustomobject][ordered]@{ path = 'skills/example/SKILL.md'; sha256 = ('3' * 64); length = 1 }
        [pscustomobject][ordered]@{ path = 'skills/second/SKILL.md'; sha256 = ('4' * 64); length = 2 }
    )
    return ,$entries
}
function Get-StandardValidationInventorySha256 { param($Inventory); return ('1' * 64) }
function Get-StandardValidationFileSha256 { param([string] $Path, [string] $Context); return ('2' * 64) }
function Get-StandardValidationTextSha256 {
    param([string] $Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Value))).ToLowerInvariant()
}
'@, [Text.UTF8Encoding]::new($false))

        $archiveSha256 = 'a' * 64
        $sourceRepository = 'https://example.test/consumer.git'
        $sourceRevision = 'b' * 40
        $baseRevision = 'c' * 40
        $eventName = 'local'
        $helperOutput = @(& pwsh -NoProfile -NonInteractive -File $helperPath `
            -RunnerPath $runnerPath `
            -CandidateRoot $candidateRoot `
            -AdapterPath $adapterPath `
            -ArtifactsRoot $artifactsRoot `
            -SourceRepository $sourceRepository `
            -SourceRevision $sourceRevision `
            -BaseRevision $baseRevision `
            -EventName $eventName `
            -CandidateArchiveSha256 $archiveSha256 `
            -OutputPath $outputPath 2>&1)
        $helperExitCode = $LASTEXITCODE

        $helperExitCode | Should -Be 0 -Because ($helperOutput -join [Environment]::NewLine)
        Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue
        $preparation = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        $binding = "$sourceRepository`n$sourceRevision`n$baseRevision`n$eventName`n$('1' * 64)`n$('2' * 64)`n$archiveSha256"
        $expectedCandidateId = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($binding))
        ).ToLowerInvariant()
        $preparation.candidateId | Should -BeExactly $expectedCandidateId
        @($preparation.candidateInventory).Count | Should -Be 2
        @($preparation.candidateInventory.path) | Should -BeExactly @('skills/example/SKILL.md', 'skills/second/SKILL.md')
    }

    It 'rejects empty, duplicate, and wrong-tool resolver receipt lists through ResumeSemantic' {
        $scenarios = @(
            [pscustomobject]@{ name = 'empty'; tools = @(); expectedError = 'must contain exactly four canonical tools' }
            [pscustomobject]@{ name = 'duplicate'; tools = @('skillspector', 'skillspector', 'skill-tools', 'pester'); expectedError = 'must use canonical tools exactly once in fixed order' }
            [pscustomobject]@{ name = 'wrong-tool'; tools = @('skillspector', 'skill-validator', 'unexpected-tool', 'pester'); expectedError = 'must use canonical tools exactly once in fixed order' }
        )
        foreach ($scenario in $scenarios) {
            $fixture = New-SyntheticResumePlan `
                -RepositoryRoot $script:RepositoryRoot `
                -ArtifactsRoot (Join-Path $TestDrive $scenario.name) `
                -ReceiptTools $scenario.tools `
                -WriteReceiptFiles
            $result = Invoke-SyntheticResume -ValidatorPath $script:ValidatorPath -RepositoryRoot $script:RepositoryRoot -PlanPath $fixture.planPath
            $result.exitCode | Should -Not -Be 0 -Because "$($scenario.name) receipt list must fail closed. Output: $($result.output)"
            $result.normalizedOutput | Should -Match $scenario.expectedError -Because "$($scenario.name) failure should come from the canonical receipt-set implementation."
        }
    }

    It 'rejects a reparse-point plan before reading plan JSON when the platform supports links' {
        $artifactsRoot = Join-Path $TestDrive 'reparse-plan'
        [void](New-Item -ItemType Directory -Path $artifactsRoot -Force)
        $targetPath = Join-Path $TestDrive 'reparse-plan-target.json'
        $planPath = Join-Path $artifactsRoot 'semantic-run-plan-link.json'
        [IO.File]::WriteAllText($targetPath, "{}`n", [Text.UTF8Encoding]::new($false))
        try {
            [void](New-Item -ItemType SymbolicLink -Path $planPath -Target $targetPath -ErrorAction Stop)
        }
        catch {
            if (-not $IsWindows) {
                Set-ItResult -Skipped -Because "The test platform cannot create a symbolic link: $($_.Exception.Message)"
                return
            }
            $targetDirectory = Join-Path $TestDrive 'reparse-plan-target-directory'
            $linkedDirectory = Join-Path $artifactsRoot 'linked-plan-directory'
            [void](New-Item -ItemType Directory -Path $targetDirectory -Force)
            $targetPath = Join-Path $targetDirectory 'semantic-run-plan.json'
            [IO.File]::WriteAllText($targetPath, "{}`n", [Text.UTF8Encoding]::new($false))
            [void](New-Item -ItemType Junction -Path $linkedDirectory -Target $targetDirectory -ErrorAction Stop)
            $planPath = Join-Path $linkedDirectory 'semantic-run-plan.json'
        }

        $result = Invoke-SyntheticResume -ValidatorPath $script:ValidatorPath -RepositoryRoot $script:RepositoryRoot -PlanPath $planPath
        $result.exitCode | Should -Not -Be 0 -Because 'A plan reparse point must be rejected before JSON parsing.'
        $result.normalizedOutput | Should -Match 'reparse point'
    }

    It 'rejects a non-ancestor base through ResumeSemantic before consuming the plan' {
        $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $repositoryRoot = Join-Path $TestDrive 'non-ancestor-repository'
        [void](New-Item -ItemType Directory -Path $repositoryRoot -Force)
        & $git -C $repositoryRoot init --initial-branch=main 2>&1 | Out-Null
        & $git -C $repositoryRoot config user.email 'semantic-fixture@example.test'
        & $git -C $repositoryRoot config user.name 'Semantic Fixture'
        [IO.File]::WriteAllText((Join-Path $repositoryRoot 'base.txt'), "base`n", [Text.UTF8Encoding]::new($false))
        & $git -C $repositoryRoot add -- base.txt 2>&1 | Out-Null
        & $git -C $repositoryRoot commit -m 'base' 2>&1 | Out-Null
        & $git -C $repositoryRoot checkout -b other 2>&1 | Out-Null
        [IO.File]::WriteAllText((Join-Path $repositoryRoot 'other.txt'), "other`n", [Text.UTF8Encoding]::new($false))
        & $git -C $repositoryRoot add -- other.txt 2>&1 | Out-Null
        & $git -C $repositoryRoot commit -m 'other' 2>&1 | Out-Null
        $nonAncestorRevision = ([string](& $git -C $repositoryRoot rev-parse HEAD)).Trim()
        & $git -C $repositoryRoot checkout main 2>&1 | Out-Null
        [IO.File]::WriteAllText((Join-Path $repositoryRoot 'candidate.txt'), "candidate`n", [Text.UTF8Encoding]::new($false))
        & $git -C $repositoryRoot add -- candidate.txt 2>&1 | Out-Null
        & $git -C $repositoryRoot commit -m 'candidate' 2>&1 | Out-Null
        $candidateRevision = ([string](& $git -C $repositoryRoot rev-parse HEAD)).Trim()
        $candidateTree = ([string](& $git -C $repositoryRoot rev-parse "$candidateRevision^{tree}")).Trim()

        $fixture = New-SyntheticResumePlan `
            -RepositoryRoot $repositoryRoot `
            -ArtifactsRoot (Join-Path $TestDrive 'non-ancestor-artifacts') `
            -ReceiptTools @('skillspector', 'skill-validator', 'skill-tools', 'pester') `
            -CandidateRevision $candidateRevision `
            -BaseRevision $nonAncestorRevision `
            -CandidateTree $candidateTree `
            -WriteReceiptFiles
        $result = Invoke-SyntheticResume -ValidatorPath $script:ValidatorPath -RepositoryRoot $repositoryRoot -PlanPath $fixture.planPath
        $result.exitCode | Should -Not -Be 0 -Because "A non-ancestor base must fail closed. Output: $($result.output)"
        $result.normalizedOutput | Should -Match 'distinct ancestor'
    }

    It 'prepares, signs, resumes, verifies, and rejects replay through the exact Validate.ps1 entrypoint' -Tag 'SemanticBridgeV2ConsumerE2E' {
        if ($env:STANDARD_VALIDATION_STAGE_ID -ceq 'repository-tests' -and
            $env:STANDARD_VALIDATION_TOOL_ID -ceq 'repository-test-pester') {
            Set-ItResult -Skipped -Because 'Avoid recursive consumer E2E execution inside repository-pester.'
            return
        }

        $artifactsRoot = Join-Path $TestDrive 'artifacts'
        $planPath = Join-Path $artifactsRoot 'semantic-run-plan.json'
        $outputPath = Join-Path $artifactsRoot 'skill-general-conformance-report.json'
        $semanticEvidencePath = Join-Path $TestDrive 'semantic-evidence.json'
        $semanticConsentRequestPath = Join-Path $TestDrive 'semantic-consent-request.json'
        $semanticConsentDecisionPath = Join-Path $TestDrive 'semantic-consent-decision.json'
        $semanticPublicKeyPath = Join-Path $TestDrive 'semantic-test-only-public-key.xml'

        $arguments = @(
            '-ExecutionMode', 'PrepareSemantic',
            '-RepositoryRoot', $script:RepositoryRoot,
            '-ArtifactsRoot', $artifactsRoot,
            '-OutputPath', $outputPath,
            '-SemanticRunPlanPath', $planPath,
            '-SemanticTriggered',
            '-SemanticEvidencePath', $semanticEvidencePath,
            '-SemanticConsentRequestPath', $semanticConsentRequestPath,
            '-SemanticConsentDecisionPath', $semanticConsentDecisionPath,
            '-SemanticPublicKeyPath', $semanticPublicKeyPath,
            '-SemanticPublicKeyId', 'syp212-c4-test-only'
        )
        if (-not [string]::IsNullOrWhiteSpace($env:SYP220_AUTHORITY_ARCHIVE)) {
            $arguments += @('-AuthorityArchivePath', [IO.Path]::GetFullPath($env:SYP220_AUTHORITY_ARCHIVE))
        }

        $invocationOutput = @(& pwsh -NoProfile -NonInteractive -File $script:ValidatorPath @arguments 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0 -Because (
            "PrepareSemantic must complete through the actual scripts/Validate.ps1 entrypoint. Output:`n" +
            ($invocationOutput -join [Environment]::NewLine)
        )
        Test-Path -LiteralPath $planPath -PathType Leaf | Should -BeTrue
        $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        $plan.schemaVersion | Should -Be 1
        $plan.artifactType | Should -BeExactly 'standard-validation-consumer-run-plan-v1'
        $plan.authority.revision | Should -BeExactly '8a944f4a74a054cb0353f22ab22c459dc9dc18ef'
        $plan.execution.semanticTriggered | Should -BeTrue
        $plan.candidate.candidateId | Should -Match '^[0-9a-f]{64}$'
        $plan.candidate.contentSha256 | Should -Match '^[0-9a-f]{64}$'
        $plan.tools.adapterSha256 | Should -Match '^[0-9a-f]{64}$'
        (Get-FileHash -LiteralPath $plan.tools.adapterPath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $plan.tools.adapterSha256
        [IO.Path]::GetFullPath([string]$plan.semantic.consentRequestPath) | Should -BeExactly ([IO.Path]::GetFullPath($semanticConsentRequestPath))
        [IO.Path]::GetFullPath([string]$plan.semantic.consentDecisionPath) | Should -BeExactly ([IO.Path]::GetFullPath($semanticConsentDecisionPath))
        [IO.Path]::GetFullPath([string]$plan.semantic.evidencePath) | Should -BeExactly ([IO.Path]::GetFullPath($semanticEvidencePath))
        [IO.Path]::GetFullPath([string]$plan.semantic.publicKeyPath) | Should -BeExactly ([IO.Path]::GetFullPath($semanticPublicKeyPath))
        $plan.semantic.publicKeyId | Should -BeExactly 'syp212-c4-test-only'

        $semanticModulePath = Join-Path ([string]$plan.authority.root) 'scripts/StandardSemanticBridge.psm1'
        Test-Path -LiteralPath $semanticModulePath -PathType Leaf | Should -BeTrue
        Import-Module -Name $semanticModulePath -Force -ErrorAction Stop
        $inventoryEntry = @(
            $plan.candidate.inventory |
                Where-Object { [string]$_.path -like 'skills/*/SKILL.md' } |
                Sort-Object { [string]$_.path } |
                Select-Object -First 1
        )
        $inventoryEntry.Count | Should -Be 1
        $relativeSkillPath = [string]$inventoryEntry[0].path
        $skillPath = Join-Path ([string]$plan.candidate.snapshotRoot) ($relativeSkillPath -replace '/', [IO.Path]::DirectorySeparatorChar)
        $textItems = @(
            [pscustomobject][ordered]@{
                path = $relativeSkillPath
                contentKind = 'skill-instructions'
                bytes = [byte[]][IO.File]::ReadAllBytes($skillPath)
            }
        )
        $route = [pscustomobject][ordered]@{
            provider = 'syp212-local-mock-provider'
            adapter = 'syp212-local-mock-adapter'
            accountOrTenant = 'isolated-test-account'
            model = 'isolated-test-model'
            endpoint = 'https://example.test/semantic-v2'
            dataRegion = 'isolated-test-region'
            retentionPolicy = 'no-retention-test-fixture'
            trainingPolicy = 'no-training-test-fixture'
        }
        $scope = [pscustomobject][ordered]@{
            description = 'Isolated consumer semantic bridge verification.'
            paths = @($relativeSkillPath)
            contentKinds = @('skill-instructions')
        }
        $analyzers = @(
            [pscustomobject][ordered]@{ id = 'semantic_developer_intent'; version = '1.0.0'; sourceSha256 = [string]$plan.authority.runnerSha256 }
            [pscustomobject][ordered]@{ id = 'semantic_security_discovery'; version = '1.0.0'; sourceSha256 = [string]$plan.tools.adapterSha256 }
        )
        $providerInventory = New-StandardSemanticBridgeProviderTextInventory -TextItems $textItems
        $bindings = [pscustomobject][ordered]@{
            candidate = [pscustomobject][ordered]@{
                candidateId = [string]$plan.candidate.candidateId
                sourceRepository = [string]$plan.source.repository
                sourceRevision = [string]$plan.source.revision
                baseRevision = [string]$plan.source.baseRevision
                sourceTree = [string]$plan.source.tree
                inputInventorySha256 = [string]$plan.candidate.contentSha256
            }
            authority = [pscustomobject][ordered]@{
                repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
                revision = [string]$plan.authority.revision
                tree = [string]$plan.authority.revision
                snapshotInventorySha256 = [string]$plan.authority.archiveSha256
            }
            tool = [pscustomobject][ordered]@{
                toolId = 'skill-general-semantic-consumer'
                version = '1.0.0-test'
                packageSha256 = [string]$plan.tools.adapterSha256
                resolverReceiptSha256 = [string]$plan.tools.policyReceiptSha256
            }
            launch = [pscustomobject][ordered]@{
                resolutionRunId = [string]$plan.runId
                launchReceiptSha256 = [string]$plan.tools.toolchainSha256
                consumptionSha256 = [string]$plan.tools.childRunnerSha256
            }
        }
        $now = [DateTime]::UtcNow.AddMinutes(-2)
        $request = New-StandardSemanticBridgeConsentRequest `
            -Bindings $bindings `
            -ProviderRoute $route `
            -Purpose 'Verify the isolated consumer semantic bridge.' `
            -Scope $scope `
            -ProviderTextInventory $providerInventory `
            -AnalyzerSet (New-StandardSemanticBridgeAnalyzerSet -Analyzers $analyzers) `
            -RequestId ([guid]::NewGuid().ToString()) `
            -RequestedAt $now `
            -ExpiresAt $now.AddHours(3)
        $decision = New-StandardSemanticBridgeConsentDecision `
            -Request $request `
            -Authorizer ([pscustomobject][ordered]@{
                subject = 'syp212-isolated-test-authorizer'
                authorityScope = 'semantic-egress-test-only'
                authenticationContext = 'isolated-test-fixture'
            }) `
            -DecisionId ([guid]::NewGuid().ToString()) `
            -AuthorizedAt $now.AddMinutes(1)
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
        try {
            $providerCalls = [pscustomobject]@{ calls = 0 }
            $provider = {
                param($providerRequest)
                $providerCalls.calls++
                return [pscustomobject][ordered]@{
                    findings = @(
                        [pscustomobject][ordered]@{ severity = 'informational'; fingerprint = 'consumer-v2-intent'; ruleId = 'fixture.intent'; message = 'isolated intent finding'; path = [string]$providerRequest.path; analyzerId = 'semantic_developer_intent' }
                        [pscustomobject][ordered]@{ severity = 'informational'; fingerprint = 'consumer-v2-security'; ruleId = 'fixture.security'; message = 'isolated security finding'; path = [string]$providerRequest.path; analyzerId = 'semantic_security_discovery' }
                    )
                    analyzerCoverage = @('semantic_developer_intent', 'semantic_security_discovery')
                }
            }.GetNewClosure()
            $signer = {
                param($signerRequest)
                return [pscustomobject][ordered]@{
                    keyId = 'syp212-c4-test-only'
                    algorithm = 'RSASSA-PKCS1-v1_5-SHA-256'
                    signature = [Convert]::ToBase64String(
                        $rsa.SignData(
                            [byte[]]$signerRequest.payloadBytes,
                            [Security.Cryptography.HashAlgorithmName]::SHA256,
                            [Security.Cryptography.RSASignaturePadding]::Pkcs1
                        )
                    )
                }
            }.GetNewClosure()
            $semanticRun = Invoke-StandardSemanticBridge `
                -ConsentRequest $request `
                -ConsentDecision $decision `
                -Bindings $bindings `
                -ProviderRoute $route `
                -Purpose 'Verify the isolated consumer semantic bridge.' `
                -Scope $scope `
                -TextItems $textItems `
                -Analyzers $analyzers `
                -ProviderCallback $provider `
                -SignerCallback $signer `
                -Now $now.AddMinutes(2)
            $semanticRun.status | Should -BeExactly 'PASS'
            $providerCalls.calls | Should -Be 1
            $utf8 = [Text.UTF8Encoding]::new($false)
            [IO.File]::WriteAllBytes($semanticConsentRequestPath, $utf8.GetBytes((Get-StandardSemanticBridgeCanonicalJson -Value $request)))
            [IO.File]::WriteAllBytes($semanticConsentDecisionPath, $utf8.GetBytes((Get-StandardSemanticBridgeCanonicalJson -Value $decision)))
            [IO.File]::WriteAllBytes($semanticEvidencePath, [byte[]]$semanticRun.evidenceBytes)
            [IO.File]::WriteAllText($semanticPublicKeyPath, $rsa.ToXmlString($false), $utf8)

            $resumeOutput = @(& pwsh -NoProfile -NonInteractive -File $script:ValidatorPath `
                -ExecutionMode ResumeSemantic `
                -RepositoryRoot $script:RepositoryRoot `
                -ArtifactsRoot $artifactsRoot `
                -SemanticRunPlanPath $planPath 2>&1)
            $resumeExitCode = $LASTEXITCODE
            $resumeExitCode | Should -Be 0 -Because (
                "ResumeSemantic must verify the signed local evidence through the actual consumer and central runner. Output:`n" +
                ($resumeOutput -join [Environment]::NewLine)
            )
            Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath ([string]$plan.execution.consumptionClaimPath) -PathType Leaf | Should -BeTrue
            $report = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
            $report.state | Should -BeExactly 'PASS'
            $report.releaseEligible | Should -BeFalse
            $semanticStage = @($report.stages | Where-Object id -eq 'conditional-semantic-scan')
            $semanticStage.Count | Should -Be 1
            $semanticStage[0].status | Should -BeExactly 'passed'
            $semanticStage[0].semanticBridgeV2Evidence.artifactType | Should -BeExactly 'semantic-evidence-v2'
            $semanticStage[0].semanticBridgeV2Evidence.attestationKeyId | Should -BeExactly 'syp212-c4-test-only'
            $semanticStage[0].semanticBridgeV2Evidence.releaseEligible | Should -BeFalse
            $providerCalls.calls | Should -Be 1

            Remove-Item -LiteralPath $outputPath -Force
            $replayOutput = @(& pwsh -NoProfile -NonInteractive -File $script:ValidatorPath `
                -ExecutionMode ResumeSemantic `
                -RepositoryRoot $script:RepositoryRoot `
                -ArtifactsRoot $artifactsRoot `
                -SemanticRunPlanPath $planPath 2>&1)
            $replayExitCode = $LASTEXITCODE
            $replayExitCode | Should -Not -Be 0
            ($replayOutput -join [Environment]::NewLine) | Should -Match 'already consumed|could not be claimed'
            $providerCalls.calls | Should -Be 1
        }
        finally {
            $rsa.Dispose()
        }
    }
}
