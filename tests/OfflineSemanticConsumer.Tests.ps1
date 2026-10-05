# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

Describe 'Offline Semantic consumer contract fixture' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:SourceValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:PowerShellPath = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $script:GitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $sourceTokens = $null
        $sourceErrors = $null
        $sourceAst = [Management.Automation.Language.Parser]::ParseFile($script:SourceValidatorPath, [ref]$sourceTokens, [ref]$sourceErrors)
        @($sourceErrors).Count | Should -Be 0
        $claimPathFunction = @($sourceAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-SemanticRunClaimPath'
        }, $true))
        $claimPathFunction.Count | Should -Be 1
        $script:ClaimPathModule = New-Module -ScriptBlock ([scriptblock]::Create($claimPathFunction[0].Extent.Text))
        $script:SourceValidatorText = [IO.File]::ReadAllText($script:SourceValidatorPath, [Text.Encoding]::UTF8)

        function Get-FixtureHash {
            param([Parameter(Mandatory = $true)][string] $Path)
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }

        function Get-FixtureEventName {
            switch ([string]$env:GITHUB_EVENT_NAME) {
                'pull_request' { return 'pull_request' }
                'push' { return 'push' }
                'workflow_dispatch' { return 'workflow_dispatch' }
                'pre-push' { return 'pre-push' }
                default { return 'local' }
            }
        }

        function Invoke-FixtureGit {
            param([Parameter(Mandatory = $true)][string] $Root, [Parameter(Mandatory = $true)][string[]] $Arguments)
            $output = @(& $script:GitPath -C $Root @Arguments 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "Fixture git command failed: git -C '$Root' $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)" }
            return $output
        }

        function New-OfflineResumeFixture {
            $runId = [guid]::NewGuid().ToString('N')
            $fixtureRoot = Join-Path $TestDrive "offline-consumer-$runId"
            $repositoryRoot = Join-Path $fixtureRoot 'candidate-repository'
            $artifactsRoot = Join-Path $fixtureRoot 'artifacts'
            $semanticRoot = Join-Path $fixtureRoot 'semantic-artifacts'
            $runRoot = Join-Path $artifactsRoot "sgv1-$($runId.Substring(0, 12))"
            $trustedRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$runId"
            $candidateExtractRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-candidate-$runId"
            $resolvedToolsRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-resolved-tools-$runId"
            foreach ($root in @($trustedRoot, $candidateExtractRoot, $resolvedToolsRoot)) {
                if (Test-Path -LiteralPath $root) { throw "Fixture run-owned root already exists: $root" }
            }
            [void](New-Item -ItemType Directory -Path $repositoryRoot, $runRoot, $trustedRoot, $candidateExtractRoot, $resolvedToolsRoot, $semanticRoot -Force)

            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('init', '--initial-branch=main'))
            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('config', 'user.email', 'offline-fixture@example.test'))
            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('config', 'user.name', 'Offline Fixture'))
            $baseFile = Join-Path $repositoryRoot 'base.txt'
            [IO.File]::WriteAllText($baseFile, "base`n", [Text.UTF8Encoding]::new($false))
            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('add', '--', 'base.txt'))
            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('commit', '-m', 'fixture base'))
            $baseRevisionOutput = @(Invoke-FixtureGit -Root $repositoryRoot -Arguments @('rev-parse', 'HEAD'))
            $baseRevision = ([string]$baseRevisionOutput[0]).Trim()
            $skillRelativePath = 'skills/fixture/SKILL.md'
            $skillPath = Join-Path $repositoryRoot ($skillRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $skillPath) -Force)
            $skillText = "# Offline fixture`n`nMinimal candidate content.`n"
            [IO.File]::WriteAllText($skillPath, $skillText, [Text.UTF8Encoding]::new($false))
            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('add', '--', $skillRelativePath))
            [void](Invoke-FixtureGit -Root $repositoryRoot -Arguments @('commit', '-m', 'fixture candidate'))
            $candidateRevisionOutput = @(Invoke-FixtureGit -Root $repositoryRoot -Arguments @('rev-parse', 'HEAD'))
            $candidateRevision = ([string]$candidateRevisionOutput[0]).Trim()
            $candidateTreeOutput = @(Invoke-FixtureGit -Root $repositoryRoot -Arguments @('rev-parse', "$candidateRevision^{tree}"))
            $candidateTree = ([string]$candidateTreeOutput[0]).Trim()

            $candidateRoot = Join-Path $candidateExtractRoot 'snapshot'
            [void](New-Item -ItemType Directory -Path $candidateRoot -Force)
            [IO.File]::WriteAllText((Join-Path $candidateRoot 'base.txt'), "base`n", [Text.UTF8Encoding]::new($false))
            $snapshotSkillPath = Join-Path $candidateRoot ($skillRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotSkillPath) -Force)
            [IO.File]::WriteAllText($snapshotSkillPath, $skillText, [Text.UTF8Encoding]::new($false))

            $candidateArchivePath = Join-Path $runRoot 'candidate.zip'
            [IO.File]::WriteAllBytes($candidateArchivePath, [Text.Encoding]::UTF8.GetBytes('offline candidate archive fixture'))
            $candidateArchiveSha256 = Get-FixtureHash -Path $candidateArchivePath
            $authorityArchivePath = Join-Path $runRoot 'authority.zip'
            [IO.File]::WriteAllBytes($authorityArchivePath, [Text.Encoding]::UTF8.GetBytes('offline synthetic authority fixture'))
            $authorityArchiveSha256 = Get-FixtureHash -Path $authorityArchivePath

            $authorityRevision = 'a' * 40
            $authorityRoot = Join-Path $trustedRoot 'authority'
            $runnerPath = Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $runnerPath) -Force)
            $runnerText = @'
param(
    [string] $CandidateRoot, [string] $AdapterPath, [string] $ArtifactsRoot, [string] $SourceRepository,
    [string] $SourceRevision, [string] $BaseRevision, [string] $EventName, [string] $CandidateArchiveSha256,
    [string] $OutputPath, [int] $TimeoutSeconds, [string] $TrustedToolRoot, [switch] $DevelopmentHarness,
    [switch] $SemanticTriggered, [string] $SemanticEvidencePath, [string] $SemanticConsentRequestPath,
    [string] $SemanticConsentDecisionPath, [string] $SemanticPublicKeyPath, [string] $SemanticPublicKeyId,
    [switch] $DefineFunctionsOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Get-StandardValidationFileSha256 {
    param([string] $Path, [string] $Context)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-StandardValidationTextSha256 {
    param([string] $Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Value))).ToLowerInvariant()
}
function Get-StandardValidationInventory {
    param([string] $Root, [string] $Context)
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $entries = @(
        Get-ChildItem -LiteralPath $fullRoot -File -Recurse -Force |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    path = [IO.Path]::GetRelativePath($fullRoot, $_.FullName).Replace('\', '/')
                    sha256 = (Get-StandardValidationFileSha256 -Path $_.FullName -Context $Context)
                    length = [long]$_.Length
                }
            } |
            Sort-Object -Property path
    )
    return ,$entries
}
function Get-StandardValidationInventorySha256 {
    param($Inventory)
    $lines = @($Inventory | ForEach-Object { "{0}`t{1}`t{2}" -f $_.path, $_.sha256, $_.length })
    return Get-StandardValidationTextSha256 -Value ([string]::Join("`n", $lines))
}
if ($DefineFunctionsOnly) { return }

$request = Get-Content -LiteralPath $SemanticConsentRequestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
$decision = Get-Content -LiteralPath $SemanticConsentDecisionPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
$evidence = Get-Content -LiteralPath $SemanticEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
if ($SemanticPublicKeyId -cne 'offline-fixture-key' -or $evidence.keyId -cne $SemanticPublicKeyId -or
    $evidence.algorithm -cne 'RSASSA-PKCS1-v1_5-SHA-256' -or $decision.allowed -ne $true -or
    $request.requestId -cne $decision.requestId -or $evidence.payload.requestId -cne $request.requestId -or
    $evidence.payload.decisionId -cne $decision.decisionId -or $evidence.payload.runId -cne $request.runId -or
    $decision.runId -cne $request.runId) { throw 'Offline fixture consent/evidence binding is invalid.' }
$payloadJson = $evidence.payload | ConvertTo-Json -Depth 40 -Compress
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
try {
    $rsa.FromXmlString((Get-Content -LiteralPath $SemanticPublicKeyPath -Raw -Encoding UTF8))
    $signatureBytes = [Convert]::FromBase64String([string]$evidence.signature)
    $payloadBytes = [Text.UTF8Encoding]::new($false).GetBytes($payloadJson)
    if (-not $rsa.VerifyData($payloadBytes, 'SHA256', $signatureBytes)) {
        throw 'Offline fixture evidence signature is invalid.'
    }
}
finally { $rsa.Dispose() }

$inventory = Get-StandardValidationInventory -Root $CandidateRoot -Context 'offline fixture candidate'
$contentSha256 = Get-StandardValidationInventorySha256 -Inventory $inventory
$adapterSha256 = Get-StandardValidationFileSha256 -Path $AdapterPath -Context 'offline fixture adapter'
$candidateBinding = "$SourceRepository`n$SourceRevision`n$BaseRevision`n$EventName`n$contentSha256`n$adapterSha256`n$CandidateArchiveSha256"
$candidateId = Get-StandardValidationTextSha256 -Value $candidateBinding
if ($evidence.payload.repository -cne $SourceRepository -or $evidence.payload.revision -cne $SourceRevision -or
    $evidence.payload.baseRevision -cne $BaseRevision -or $evidence.payload.tree -cne $request.tree -or
    $evidence.payload.archiveSha256 -cne $CandidateArchiveSha256 -or
    $evidence.payload.inventorySha256 -cne $contentSha256 -or $evidence.payload.candidateId -cne $candidateId) {
    throw 'Offline fixture signed source/inventory binding is invalid.'
}
$report = [ordered]@{ state = 'PASS'; releaseEligible = $false; fixture = 'offline-consumer-contract'; candidateId = $candidateId }
[IO.File]::WriteAllText($OutputPath, (($report | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
exit 0
'@
            [IO.File]::WriteAllText($runnerPath, $runnerText, [Text.UTF8Encoding]::new($false))
            $runnerSha256 = Get-FixtureHash -Path $runnerPath

            $validatorText = [IO.File]::ReadAllText($script:SourceValidatorPath, [Text.Encoding]::UTF8)
            $commitPattern = '(?m)^\$script:AuthorityCommit = ''[0-9a-f]{40}''\r?$'
            $archivePattern = '(?m)^\$script:AuthorityArchiveSha256 = ''[0-9a-f]{64}''\r?$'
            if ([regex]::Matches($validatorText, $commitPattern).Count -ne 1 -or [regex]::Matches($validatorText, $archivePattern).Count -ne 1) {
                throw 'Fixture copy expected one baseline authority revision and archive binding.'
            }
            $validatorText = [regex]::Replace($validatorText, $commitPattern, ('$script:AuthorityCommit = ''{0}''' -f $authorityRevision), 1)
            $validatorText = [regex]::Replace($validatorText, $archivePattern, ('$script:AuthorityArchiveSha256 = ''{0}''' -f $authorityArchiveSha256), 1)
            $authorityFilesPattern = '(?ms)^\$script:AuthorityFiles = \[ordered\]@\{\r?\n.*?^\}'
            $authorityFilesMatches = [regex]::Matches($validatorText, $authorityFilesPattern)
            if ($authorityFilesMatches.Count -ne 1) { throw 'Fixture copy expected one baseline authority file inventory.' }
            $authorityFilesText = [string]::Join([Environment]::NewLine, @(
                '$script:AuthorityFiles = [ordered]@{',
                "    'scripts/Invoke-StandardValidation.ps1' = '$runnerSha256'",
                '}'
            ))
            $authorityFilesMatch = $authorityFilesMatches[0]
            $validatorText = $validatorText.Remove($authorityFilesMatch.Index, $authorityFilesMatch.Length).Insert($authorityFilesMatch.Index, $authorityFilesText)
            $validatorPath = Join-Path $fixtureRoot 'Validate.ps1'
            [IO.File]::WriteAllText($validatorPath, $validatorText, [Text.UTF8Encoding]::new($false))

            $helperMarker = '$semanticPreparationHelperText = @'''
            $helperStart = $validatorText.IndexOf($helperMarker, [StringComparison]::Ordinal)
            if ($helperStart -lt 0) { throw 'Fixture copy could not locate the actual semantic preparation helper.' }
            $helperBodyStart = $validatorText.IndexOf("`n", $helperStart, [StringComparison]::Ordinal) + 1
            $helperEnd = $validatorText.IndexOf("`n'@", $helperBodyStart, [StringComparison]::Ordinal)
            if ($helperEnd -le $helperBodyStart) { throw 'Fixture copy has an incomplete semantic preparation helper.' }
            $helperText = $validatorText.Substring($helperBodyStart, $helperEnd - $helperBodyStart).TrimEnd("`r")
            $helperPath = Join-Path $trustedRoot 'Get-SkillGeneralSemanticPreparation.ps1'
            [IO.File]::WriteAllText($helperPath, $helperText, [Text.UTF8Encoding]::new($false))

            $adapterPath = Join-Path $trustedRoot 'adapter.json'
            [IO.File]::WriteAllText($adapterPath, "{`"adapterType`":`"offline-fixture`"}`n", [Text.UTF8Encoding]::new($false))
            $adapterSha256 = Get-FixtureHash -Path $adapterPath
            $childRunnerPath = Join-Path $trustedRoot 'Invoke-SkillGeneralValidationChild.ps1'
            [IO.File]::WriteAllText($childRunnerPath, "# offline fixture child runner`n", [Text.UTF8Encoding]::new($false))
            $preparationPath = Join-Path $runRoot 'semantic-preparation.json'
            $sourceRepository = 'https://github.com/SyuanTsai/Skill-General.git'
            $eventName = Get-FixtureEventName
            $helperOutput = @(& $script:PowerShellPath -NoProfile -NonInteractive -File $helperPath `
                -RunnerPath $runnerPath -CandidateRoot $candidateRoot -AdapterPath $adapterPath `
                -ArtifactsRoot $artifactsRoot -SourceRepository $sourceRepository -SourceRevision $candidateRevision `
                -BaseRevision $baseRevision -EventName $eventName -CandidateArchiveSha256 $candidateArchiveSha256 `
                -OutputPath $preparationPath 2>&1)
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $preparationPath -PathType Leaf)) {
                throw "Actual consumer preparation helper fixture failed: $($helperOutput -join [Environment]::NewLine)"
            }
            $preparationSha256 = Get-FixtureHash -Path $preparationPath
            $preparation = Get-Content -LiteralPath $preparationPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

            $receiptDefinitions = @(
                [pscustomobject]@{ tool = 'skillspector'; properties = [ordered]@{ executablePath = (Join-Path $runRoot 'skillspector.exe'); executableSha256 = ('1' * 64) } },
                [pscustomobject]@{ tool = 'skill-validator'; properties = [ordered]@{ executablePath = (Join-Path $runRoot 'skill-validator.exe'); executableSha256 = ('2' * 64) } },
                [pscustomobject]@{ tool = 'skill-tools'; properties = [ordered]@{ nodePath = (Join-Path $runRoot 'node.exe'); nodeSha256 = ('3' * 64); entryPointPath = (Join-Path $runRoot 'skill-tools.js'); entryPointSha256 = ('4' * 64) } },
                [pscustomobject]@{ tool = 'pester'; properties = [ordered]@{ modulePath = (Join-Path $runRoot 'Pester.psd1'); executableSha256 = ('5' * 64) } }
            )
            $receiptBindings = @(
                foreach ($definition in $receiptDefinitions) {
                    $receiptPath = Join-Path $runRoot "receipt-$($definition.tool).json"
                    $resolvedVersion = if ($definition.tool -ceq 'pester') { '6.2.0' } else { 'fixture' }
                    $receipt = [ordered]@{
                        schemaVersion = 1; resolutionRunId = $runId; toolName = $definition.tool
                        channel = 'latest-stable'; resolvedVersion = $resolvedVersion; resolvedIdentity = "offline-$($definition.tool)"
                        frozenForRun = $true; status = 'verified'
                    }
                    foreach ($name in $definition.properties.Keys) { $receipt[$name] = $definition.properties[$name] }
                    [IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
                    [ordered]@{ tool = $definition.tool; path = [IO.Path]::GetFullPath($receiptPath); sha256 = Get-FixtureHash -Path $receiptPath }
                }
            )
            $toolchainPath = Join-Path $trustedRoot 'toolchain.json'
            $toolchain = [ordered]@{
                upstreamAdapterValidatorPath = Join-Path $trustedRoot 'Validate-UpstreamAdapter.ps1'; upstreamAdapterValidatorSha256 = ('6' * 64)
                upstreamPolicyPath = Join-Path $trustedRoot 'upstream-adapter.json'; upstreamPolicySha256 = ('7' * 64)
                skillValidatorPath = [string]$receiptDefinitions[1].properties.executablePath; skillValidatorSha256 = [string]$receiptDefinitions[1].properties.executableSha256
                skillToolsNodePath = [string]$receiptDefinitions[2].properties.nodePath; skillToolsNodeSha256 = [string]$receiptDefinitions[2].properties.nodeSha256
                skillToolsEntryPointPath = [string]$receiptDefinitions[2].properties.entryPointPath; skillToolsEntryPointSha256 = [string]$receiptDefinitions[2].properties.entryPointSha256
                skillSpectorPath = [string]$receiptDefinitions[0].properties.executablePath; skillSpectorSha256 = [string]$receiptDefinitions[0].properties.executableSha256
                pesterModulePath = [string]$receiptDefinitions[3].properties.modulePath; pesterModuleSha256 = [string]$receiptDefinitions[3].properties.executableSha256
                pesterVersion = '6.2.0'
            }
            [IO.File]::WriteAllText($toolchainPath, (($toolchain | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
            $toolchainSha256 = Get-FixtureHash -Path $toolchainPath
            $policyReceiptPath = Join-Path $runRoot 'policy.json'
            [IO.File]::WriteAllText($policyReceiptPath, (([ordered]@{ schemaVersion = 1; resolutionRunId = $runId } | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

            $requestId = [guid]::NewGuid().ToString()
            $decisionId = [guid]::NewGuid().ToString()
            $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
            $semanticRequestPath = Join-Path $semanticRoot 'consent-request.json'
            $semanticDecisionPath = Join-Path $semanticRoot 'consent-decision.json'
            $semanticEvidencePath = Join-Path $semanticRoot 'evidence.json'
            $semanticPublicKeyPath = Join-Path $semanticRoot 'public-key.xml'
            $payload = [ordered]@{
                schemaVersion = 1; artifactType = 'offline-semantic-consumer-fixture-v1'; runId = $runId
                candidateId = [string]$preparation.candidateId; repository = $sourceRepository
                revision = $candidateRevision; baseRevision = $baseRevision; tree = $candidateTree
                inventorySha256 = [string]$preparation.candidateContentSha256; adapterSha256 = [string]$preparation.adapterSha256
                archiveSha256 = $candidateArchiveSha256; requestId = $requestId; decisionId = $decisionId
            }
            $request = [ordered]@{
                schemaVersion = 1; artifactType = 'offline-semantic-consent-request-fixture-v1'; requestId = $requestId
                runId = $runId; candidateId = [string]$preparation.candidateId; tree = $candidateTree
                provider = 'offline-callback-fixture'; networkUsed = $false
            }
            $decision = [ordered]@{
                schemaVersion = 1; artifactType = 'offline-semantic-consent-decision-fixture-v1'; decisionId = $decisionId
                requestId = $requestId; runId = $runId; allowed = $true; authorizer = 'test-only in-memory signer'
            }
            $payloadBytes = [Text.UTF8Encoding]::new($false).GetBytes(($payload | ConvertTo-Json -Depth 40 -Compress))
            $signature = [Convert]::ToBase64String($rsa.SignData($payloadBytes, 'SHA256'))
            $evidence = [ordered]@{
                schemaVersion = 1; artifactType = 'offline-semantic-evidence-fixture-v1'; keyId = 'offline-fixture-key'
                algorithm = 'RSASSA-PKCS1-v1_5-SHA-256'; payload = $payload; signature = $signature
            }
            $utf8 = [Text.UTF8Encoding]::new($false)
            [IO.File]::WriteAllText($semanticRequestPath, (($request | ConvertTo-Json -Depth 40) + [Environment]::NewLine), $utf8)
            [IO.File]::WriteAllText($semanticDecisionPath, (($decision | ConvertTo-Json -Depth 40) + [Environment]::NewLine), $utf8)
            [IO.File]::WriteAllText($semanticEvidencePath, (($evidence | ConvertTo-Json -Depth 40) + [Environment]::NewLine), $utf8)
            [IO.File]::WriteAllText($semanticPublicKeyPath, $rsa.ToXmlString($false), $utf8)

            $planPath = Join-Path $artifactsRoot 'semantic-run-plan.json'
            $productionClaimPath = & $script:ClaimPathModule {
                param($root, $identity)
                Get-SemanticRunClaimPath -RunRoot $root -RunId $identity
            } $runRoot $runId
            $plan = [ordered]@{
                schemaVersion = 1; artifactType = 'standard-validation-consumer-run-plan-v1'; runId = $runId
                source = [ordered]@{
                    repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot); repository = $sourceRepository
                    revision = $candidateRevision; baseRevision = $baseRevision; tree = $candidateTree; eventName = $eventName
                }
                roots = [ordered]@{
                    artifacts = [IO.Path]::GetFullPath($artifactsRoot); run = [IO.Path]::GetFullPath($runRoot)
                    trusted = [IO.Path]::GetFullPath($trustedRoot); candidateExtract = [IO.Path]::GetFullPath($candidateExtractRoot)
                    resolvedTools = [IO.Path]::GetFullPath($resolvedToolsRoot)
                }
                candidate = [ordered]@{
                    archivePath = [IO.Path]::GetFullPath($candidateArchivePath); archiveSha256 = $candidateArchiveSha256
                    snapshotRoot = [IO.Path]::GetFullPath($candidateRoot); contentSha256 = [string]$preparation.candidateContentSha256
                    inventory = @($preparation.candidateInventory); candidateId = [string]$preparation.candidateId
                }
                authority = [ordered]@{
                    revision = $authorityRevision; archivePath = [IO.Path]::GetFullPath($authorityArchivePath)
                    archiveSha256 = $authorityArchiveSha256; root = [IO.Path]::GetFullPath($authorityRoot)
                    runnerPath = [IO.Path]::GetFullPath($runnerPath); runnerSha256 = $runnerSha256
                }
                tools = [ordered]@{
                    policyReceiptPath = [IO.Path]::GetFullPath($policyReceiptPath); policyReceiptSha256 = Get-FixtureHash -Path $policyReceiptPath
                    receipts = $receiptBindings; toolchainPath = [IO.Path]::GetFullPath($toolchainPath); toolchainSha256 = $toolchainSha256
                    childRunnerPath = [IO.Path]::GetFullPath($childRunnerPath); childRunnerSha256 = Get-FixtureHash -Path $childRunnerPath
                    preparationHelperPath = [IO.Path]::GetFullPath($helperPath); preparationHelperSha256 = Get-FixtureHash -Path $helperPath
                    preparationPath = [IO.Path]::GetFullPath($preparationPath); preparationSha256 = $preparationSha256
                    adapterPath = [IO.Path]::GetFullPath($adapterPath); adapterSha256 = $adapterSha256
                }
                execution = [ordered]@{
                    outputPath = [IO.Path]::GetFullPath((Join-Path $artifactsRoot 'consumer-output.json')); timeoutSeconds = 30
                    semanticTriggered = $true; consumptionClaimPath = $productionClaimPath
                }
                semantic = [ordered]@{
                    consentRequestPath = [IO.Path]::GetFullPath($semanticRequestPath); consentDecisionPath = [IO.Path]::GetFullPath($semanticDecisionPath)
                    evidencePath = [IO.Path]::GetFullPath($semanticEvidencePath); publicKeyPath = [IO.Path]::GetFullPath($semanticPublicKeyPath)
                    publicKeyId = 'offline-fixture-key'
                }
            }
            [IO.File]::WriteAllText($planPath, (($plan | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{
                fixtureRoot = $fixtureRoot; repositoryRoot = $repositoryRoot; artifactsRoot = $artifactsRoot
                candidateRoot = $candidateRoot; candidateSkillPath = $snapshotSkillPath; originalSkillText = $skillText
                planPath = $planPath; validatorPath = $validatorPath; outputPath = [string]$plan.execution.outputPath
                runId = $runId; rsa = $rsa; externalRoots = @($trustedRoot, $candidateExtractRoot, $resolvedToolsRoot)
            }
        }

        function Invoke-OfflineResume {
            param([Parameter(Mandatory = $true)] $Fixture, [Parameter(Mandatory = $true)][string] $PlanPath)
            $output = @(& $script:PowerShellPath -NoProfile -NonInteractive -File $Fixture.validatorPath `
                -ExecutionMode ResumeSemantic -RepositoryRoot $Fixture.repositoryRoot -SemanticRunPlanPath $PlanPath 2>&1)
            return [pscustomobject]@{ exitCode = $LASTEXITCODE; output = ($output -join [Environment]::NewLine) }
        }
    }

    # Scenario: A prepared local run has signed offline evidence, then candidate bytes or a copied run plan are changed.
    # Purpose: Protect ResumeSemantic source binding and run-identity replay claims without invoking a real analyzer or network provider.
    It 'UnitT10_derives_the_producer_claim_from_the_shared_production_run_identity_function' {
        $runId = 'a' * 32
        $runRoot = Join-Path $TestDrive 'producer-claim-path'
        $claimPath = & $script:ClaimPathModule {
            param($root, $identity)
            Get-SemanticRunClaimPath -RunRoot $root -RunId $identity
        } $runRoot $runId
        $claimPath | Should -BeExactly (Join-Path ([IO.Path]::GetFullPath($runRoot)) "semantic-run-$runId.consumed.json")
        $producerCalls = [regex]::Matches($script:SourceValidatorText, '(?m)^\s*consumptionClaimPath = Get-SemanticRunClaimPath -RunRoot \$runRoot -RunId \$runId\s*$')
        $producerCalls.Count | Should -Be 1 -Because 'PrepareSemantic must construct its plan claim using the same production function that ResumeSemantic validates.'
        { & $script:ClaimPathModule { param($root, $identity) Get-SemanticRunClaimPath -RunRoot $root -RunId $identity } $runRoot 'copied' } | Should -Throw
    }

    It 'InterT10_resumes the offline consumer fixture and rejects inventory drift and copied-plan replay' {
        $fixture = New-OfflineResumeFixture
        try {
            $canonicalClaimPath = Join-Path (Join-Path $fixture.artifactsRoot "sgv1-$($fixture.runId.Substring(0, 12))") "semantic-run-$($fixture.runId).consumed.json"
            [IO.File]::WriteAllText($fixture.candidateSkillPath, ($fixture.originalSkillText + "tampered`n"), [Text.UTF8Encoding]::new($false))
            $tampered = Invoke-OfflineResume -Fixture $fixture -PlanPath $fixture.planPath
            $tampered.exitCode | Should -Not -Be 0 -Because "ResumeSemantic must reject source inventory drift before consuming the plan. Output: $($tampered.output)"
            $tampered.output | Should -Match 'candidate, inventory, or adapter binding drifted'
            Test-Path -LiteralPath $canonicalClaimPath | Should -BeFalse

            [IO.File]::WriteAllText($fixture.candidateSkillPath, $fixture.originalSkillText, [Text.UTF8Encoding]::new($false))
            $resumed = Invoke-OfflineResume -Fixture $fixture -PlanPath $fixture.planPath
            $resumed.exitCode | Should -Be 0 -Because "The real ResumeSemantic consumer entrypoint must validate and dispatch the offline signed fixture. Output: $($resumed.output)"
            Test-Path -LiteralPath $fixture.outputPath -PathType Leaf | Should -BeTrue
            $report = Get-Content -LiteralPath $fixture.outputPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
            $report.state | Should -BeExactly 'PASS'
            $report.releaseEligible | Should -BeFalse
            $report.fixture | Should -BeExactly 'offline-consumer-contract'
            Test-Path -LiteralPath $canonicalClaimPath -PathType Leaf | Should -BeTrue

            Remove-Item -LiteralPath $fixture.outputPath -Force
            $copyPath = Join-Path $fixture.artifactsRoot 'copied-semantic-run-plan.json'
            $copiedPlan = Get-Content -LiteralPath $fixture.planPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
            $copiedPlan.execution.consumptionClaimPath = "$copyPath.consumed.json"
            [IO.File]::WriteAllText($copyPath, (($copiedPlan | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
            $replay = Invoke-OfflineResume -Fixture $fixture -PlanPath $copyPath
            $replay.exitCode | Should -Not -Be 0 -Because "A copied same-runId plan must not get a second CreateNew claim. Output: $($replay.output)"
            $replay.output | Should -Match 'consumption claim path is not derived from the run identity|already consumed|could not be claimed'
            Test-Path -LiteralPath "$copyPath.consumed.json" | Should -BeFalse
        }
        finally {
            $fixture.rsa.Dispose()
            foreach ($root in $fixture.externalRoots) {
                $resolvedRoot = [IO.Path]::GetFullPath($root)
                $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
                if (-not $resolvedRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clean fixture path outside the temp root: $resolvedRoot" }
                if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
            }
        }
    }
}
