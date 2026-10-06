# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Canonical Standard v1 validation adapter' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:Validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $script:WorkflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw -Encoding utf8
        $script:Adapter = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'config/standard-v1.json') -Raw |
            ConvertFrom-Json -Depth 20
        $script:ExpectedAuthorityCommit = '51399617ddebe21656fe4265a8d9ad116a943583'
        $script:ExpectedAuthorityArchiveSha256 = 'b115762de7d4da6f0f95143e1853bd3822fe224d2e673539ace3f480df6ef50d'
        $script:ExpectedAuthorityFiles = [ordered]@{
            'docs/standards/README.md' = '5e1ddd737d26a5ec1ff1ebd08e158376ddaf1ea21008bb987fc7f51376923f7c'
            'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
            'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
            'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
            'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
            'docs/standards/schemas/validation-security-gate-v1.schema.json' = '32aee32858cdb0f8fa7b01462af05ad2300cb247cd2e3ca769fa36ed1ac205a9'
            'docs/standards/skill-repository-review-matrix.md' = '315204afe428bb51cab5e815b2c40f6d0cbd55c81a3532ad59b686ae5e4c166c'
            'docs/standards/skill-repository-standard.md' = 'c85562f017a09b4f4daa8dd3a1fcbd1d34714eb711ed9c011642247c8d3be61e'
            'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
            'docs/standards/validation-security-gate.json' = '2d4ac30449981083d3f3eab850789e7115684f9dfecad48234bc91ffb678e674'
            'docs/standards/validation-toolchain.json' = '1dddbf4c5736e22e56f6ecb298542f41d39e116ab00ca24ad18beb7a3eab40ed'
            'scripts/Invoke-StandardAuthorityGate.ps1' = 'b12a79e371146957f16bb77491cae274cb94e9af62908026201366fb38f440be'
            'scripts/Resolve-PythonWheelClosure.py' = 'd209c973f331fdbb82a4d546bda18b1d485bcd1e446dd446b6d8bc4360b5ce35'
            'scripts/Resolve-StandardValidationTool.ps1' = '86540ff07e1b73177d179ae6a9ee2f0fef8029e27286604d68a9a98d0d205ec2'
            'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
            'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '8ed4a9d7158273d7a1e9d898acf07f57e9170822cb7cbb70f1e2eec7195867ee'
            'docs/standards/standard-validation-contract-v1.json' = '6fa3233e86ec7918aebf1413d41a6d1712f55eb2d1b09262fe18e53ddfbcb8cf'
            'docs/standards/pr12-source-merge-adoption.json' = '4c5262f2a11d228195230c15fa4faaf9614af6b59f110e5d9c08f242ce809175'
            'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
            'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
            'scripts/Invoke-StandardValidation.ps1' = 'c127309958226417291b512d633caa2120bbd12a663c98fff1d63106cf5a2677'
            'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
            'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
            'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
            'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
            'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
        }
        $script:ExpectedNextAuthorityCommit = 'ea1d368ac7b36f838ce4c3af363972c90fa12930'
        $script:ExpectedNextAuthorityArchiveSha256 = 'c5a43ef70bf9ed813df2b8ae206b7c1b661caa013744e1098df87ccc3d274653'
        $script:ExpectedNextAuthorityFiles = [ordered]@{
            'docs/standards/README.md' = '43c1526ac55302f62b706688905be160d9805cc3a6a800189d689e66fa727b71'
            'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
            'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
            'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
            'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
            'docs/standards/schemas/validation-security-gate-v1.schema.json' = 'ac58302e0e350c1ab4ba4dad8a33cd3abce12d592537fbdb23dfb1936d064e91'
            'docs/standards/skill-repository-review-matrix.md' = '299925aabe3cab360827baad9bdeb1f0f56fc320dad967e49fe0b6bf9cdf8f8a'
            'docs/standards/skill-repository-standard.md' = 'bba519d01efc8d6d8508427c39a8cb3cd7e430f170febba507471bb4b8531294'
            'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
            'docs/standards/validation-security-gate.json' = '657122dde340f1f7f4442780cc27ffcb00b60c0d2afdcea22d63fbf7dbfdca7d'
            'docs/standards/validation-toolchain.json' = '1dddbf4c5736e22e56f6ecb298542f41d39e116ab00ca24ad18beb7a3eab40ed'
            'scripts/Invoke-StandardAuthorityGate.ps1' = '8e00ee1e48ef8359ab7be3539f8f7585ccde18b41e26d810843715ebc3656a4c'
            'scripts/Resolve-PythonWheelClosure.py' = 'd209c973f331fdbb82a4d546bda18b1d485bcd1e446dd446b6d8bc4360b5ce35'
            'scripts/Resolve-StandardValidationTool.ps1' = '86540ff07e1b73177d179ae6a9ee2f0fef8029e27286604d68a9a98d0d205ec2'
            'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
            'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '8ed4a9d7158273d7a1e9d898acf07f57e9170822cb7cbb70f1e2eec7195867ee'
            'docs/standards/standard-validation-contract-v1.json' = '707edf8945ad9a7097df1dfb22a8f05ce47d0e0a66e2e44381036d630e854da0'
            'docs/standards/pr12-source-merge-adoption.json' = '4c5262f2a11d228195230c15fa4faaf9614af6b59f110e5d9c08f242ce809175'
            'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
            'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
            'scripts/Invoke-StandardValidation.ps1' = '03c7d01ee4e0c659c245dcf9ce8accdd31e3de343836e4bacaafd7f549e6e4f6'
            'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
            'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
            'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
            'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
            'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
        }
        $script:ExpectedMergedAuthorityCommit = '053b80143b5ef48b06a8c448d5ac1abaf9a49df8'
        $script:ExpectedMergedAuthorityArchiveSha256 = 'cdaa67f38ee595495015d37955082e16ac248afb48fca64f1788d2eab8adfbc9'
        $script:ExpectedMergedAuthorityFiles = [ordered]@{
            'docs/standards/README.md' = '43c1526ac55302f62b706688905be160d9805cc3a6a800189d689e66fa727b71'
            'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
            'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
            'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
            'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
            'docs/standards/schemas/validation-security-gate-v1.schema.json' = 'ac58302e0e350c1ab4ba4dad8a33cd3abce12d592537fbdb23dfb1936d064e91'
            'docs/standards/skill-repository-review-matrix.md' = '299925aabe3cab360827baad9bdeb1f0f56fc320dad967e49fe0b6bf9cdf8f8a'
            'docs/standards/skill-repository-standard.md' = '4eaf26afb98bbc42e9d1ddd51cf3d375958a37068998beda5c0f62471e64cbe9'
            'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
            'docs/standards/validation-security-gate.json' = '657122dde340f1f7f4442780cc27ffcb00b60c0d2afdcea22d63fbf7dbfdca7d'
            'docs/standards/validation-toolchain.json' = '1dddbf4c5736e22e56f6ecb298542f41d39e116ab00ca24ad18beb7a3eab40ed'
            'scripts/Invoke-StandardAuthorityGate.ps1' = '8e00ee1e48ef8359ab7be3539f8f7585ccde18b41e26d810843715ebc3656a4c'
            'scripts/Resolve-PythonWheelClosure.py' = 'f9fcd99c408849f98564fbc4c30f3d7e6ad8148b60cb4d8f58fc29b040c4519c'
            'scripts/Resolve-StandardValidationTool.ps1' = '71e6d5b191b74202e96f34a856d3317efb18662e17c8368d112d89b7d6795b15'
            'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
            'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '8ed4a9d7158273d7a1e9d898acf07f57e9170822cb7cbb70f1e2eec7195867ee'
            'docs/standards/standard-validation-contract-v1.json' = '707edf8945ad9a7097df1dfb22a8f05ce47d0e0a66e2e44381036d630e854da0'
            'docs/standards/pr12-source-merge-adoption.json' = '4c5262f2a11d228195230c15fa4faaf9614af6b59f110e5d9c08f242ce809175'
            'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
            'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
            'scripts/Invoke-StandardValidation.ps1' = 'fd60e3f7552d5b4b1fc5837a195fb8f8abff8444e8c1a9ff621ea14cb575b525'
            'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
            'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
            'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
            'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
            'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
        }

        $selectorStepPattern = '(?ms)^      - name: Select protected authority mode\r?\n(?<body>.*?)(?=^      - name: |\z)'
        $selectorStep = [regex]::Match($script:Workflow, $selectorStepPattern)
        if (-not $selectorStep.Success) { throw 'Protected authority selector step is missing.' }
        $selectorBody = $selectorStep.Groups['body'].Value
        $selectorRunHeader = [regex]::Match($selectorBody, '(?m)^        run: \|\r?\n')
        if (-not $selectorRunHeader.Success) { throw 'Protected authority selector run block is missing.' }
        $selectorLines = @($selectorBody.Substring($selectorRunHeader.Index + $selectorRunHeader.Length) -split '\r?\n')
        $script:SelectorScript = (@($selectorLines | ForEach-Object {
            if ($_.Length -eq 0) { '' }
            elseif ($_.StartsWith('          ', [StringComparison]::Ordinal)) { $_.Substring(10) }
            else { throw "Unexpected selector indentation: $_" }
        }) -join "`n")

        function Invoke-WorkflowSelectorFixture {
            param(
                [Parameter(Mandatory)][string] $DriverAuthority,
                [Parameter(Mandatory)][string] $CandidateAuthority,
                [Parameter(Mandatory)][string] $ExpectedDriverSha,
                [Parameter(Mandatory)][string] $ActualDriverSha,
                [bool] $IncludeCoreWrapper = $true,
                [switch] $ReturnSelection
            )
            $workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $driver = Join-Path $workspace 'driver'
            $candidate = Join-Path $workspace 'candidate'
            [void](New-Item -ItemType Directory -Force -Path (Join-Path $driver 'config'), (Join-Path $candidate 'config'), (Join-Path $driver 'scripts'))
            if ($IncludeCoreWrapper) { [IO.File]::WriteAllText((Join-Path $driver 'scripts/Invoke-CorePester.ps1'), '# fixture') }
            @{ authority = @{ commit = $DriverAuthority } } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $driver 'config/standard-v1.json') -Encoding utf8
            @{ authority = @{ commit = $CandidateAuthority } } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $candidate 'config/standard-v1.json') -Encoding utf8

            # The workflow now rejects aliases/functions named git. Exercise the
            # selector with an actual application command that returns fixture data.
            $fixtureBin = Join-Path $workspace 'bin'
            [void](New-Item -ItemType Directory -Path $fixtureBin)
            $gitShim = Join-Path $fixtureBin 'git.cmd'
            [IO.File]::WriteAllText($gitShim, @'
@echo off
if not "%~1"=="-C" exit /b 1
if not "%~3"=="rev-parse" exit /b 1
if not "%~4"=="HEAD" exit /b 1
if not "%~5"=="" exit /b 1
echo %SYP_FIXTURE_DRIVER_SHA%
exit /b 0
'@, [Text.Encoding]::ASCII)

            $names = @('GITHUB_WORKSPACE', 'EXPECTED_DRIVER_SHA', 'GITHUB_OUTPUT', 'SYP_FIXTURE_DRIVER_SHA', 'PATH')
            $previous = @{}
            foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
            $priorLastExitVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            $hadPriorLastExit = $null -ne $priorLastExitVariable
            $priorLastExitValue = if ($hadPriorLastExit) { $priorLastExitVariable.Value } else { $null }
            try {
                [Environment]::SetEnvironmentVariable('GITHUB_WORKSPACE', $workspace, 'Process')
                [Environment]::SetEnvironmentVariable('EXPECTED_DRIVER_SHA', $ExpectedDriverSha, 'Process')
                [Environment]::SetEnvironmentVariable('SYP_FIXTURE_DRIVER_SHA', $ActualDriverSha, 'Process')
                [Environment]::SetEnvironmentVariable('GITHUB_OUTPUT', (Join-Path $workspace 'github-output.txt'), 'Process')
                [Environment]::SetEnvironmentVariable('PATH', "$fixtureBin$([IO.Path]::PathSeparator)$($previous.PATH)", 'Process')
                & ([scriptblock]::Create($script:SelectorScript))
                $outputLines = @([IO.File]::ReadAllLines($env:GITHUB_OUTPUT))
                $modeLines = @($outputLines | Where-Object { $_ -match '^validation_mode=(legacy|core)$' })
                $revisionLines = @($outputLines | Where-Object { $_ -match '^authority_revision=[0-9a-f]{40}$' })
                if ($modeLines.Count -ne 1) { throw "Unexpected selector output: $($outputLines -join "`n")" }
                $mode = $modeLines[0].Substring('validation_mode='.Length)
                if ($revisionLines.Count -gt 1) { throw 'Protected selector emitted multiple authority revisions.' }
                $authorityRevision = if ($revisionLines.Count -eq 1) { $revisionLines[0].Substring('authority_revision='.Length) } else { $null }
                if ($ReturnSelection) {
                    return [pscustomobject]@{ mode = $mode; authorityRevision = $authorityRevision }
                }
                return $mode
            }
            finally {
                foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
                if ($hadPriorLastExit) {
                    Set-Variable -Name LASTEXITCODE -Value $priorLastExitValue -Scope Global
                }
                else {
                    Remove-Variable -Name LASTEXITCODE -Scope Global -Force -ErrorAction SilentlyContinue
                }
            }
        }

        function New-MergedAuthorityConfig {
            [pscustomobject]@{
                schemaVersion = 1
                standardVersion = 'v1'
                authority = [pscustomobject]@{
                    repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
                    commit = $script:ExpectedMergedAuthorityCommit
                    archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedMergedAuthorityCommit)"
                    archiveSha256 = $script:ExpectedMergedAuthorityArchiveSha256
                    files = @(foreach ($entry in $script:ExpectedMergedAuthorityFiles.GetEnumerator()) {
                        [pscustomobject]@{ path = $entry.Key; sha256 = $entry.Value }
                    })
                }
            }
        }

        function New-AuthorityVerifierModule {
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
            if (@($errors).Count -ne 0) { throw 'Validate.ps1 does not parse as PowerShell.' }
            $parts = @($ast.EndBlock.Statements | Where-Object {
                ($_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $_.Left.Extent.Text -in @('$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles',
                        '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles',
                        '$script:MergedAuthorityCommit', '$script:MergedAuthorityArchiveSha256', '$script:MergedAuthorityFiles')) -or
                ($_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                    $_.Name -in @('Assert-ExactPropertySet', 'Assert-Sha256', 'Assert-AuthorityConfig'))
            } | ForEach-Object { $_.Extent.Text })
            return New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        }

        function New-CoreRunSelectorModule {
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
            if (@($errors).Count -ne 0) { throw 'Validate.ps1 does not parse as PowerShell.' }
            $constantNames = @(
                '$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles',
                '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles',
                '$script:MergedAuthorityCommit', '$script:MergedAuthorityArchiveSha256', '$script:MergedAuthorityFiles'
            )
            $constants = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -cin $constantNames
            }, $true) | ForEach-Object { $_.Extent.Text })
            $legacyFunction = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-LegacyAuthorityPin'
            }, $true))
            $selectorAssignment = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$coreRunSelected'
            }, $true))
            if ($legacyFunction.Count -ne 1 -or $selectorAssignment.Count -ne 1) {
                throw 'Validate.ps1 must have one legacy pin mapper and one Core Run selector.'
            }
            $selectorFunction = @'
function Test-CoreRunSelected {
    param([string] $ExecutionMode, $candidateAuthority, [bool] $legacyRunRequested)
    return ($SELECTOR_EXPRESSION)
}
'@.Replace('$SELECTOR_EXPRESSION', $selectorAssignment[0].Right.Extent.Text)
            $parts = $constants + @($legacyFunction[0].Extent.Text, $selectorFunction)
            return New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        }

        function New-OrdinaryRunGuardModule {
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
            if (@($errors).Count -ne 0) { throw 'Validate.ps1 does not parse as PowerShell.' }
            $constantNames = @(
                '$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles',
                '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles',
                '$script:MergedAuthorityCommit', '$script:MergedAuthorityArchiveSha256', '$script:MergedAuthorityFiles'
            )
            $constants = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -cin $constantNames
            }, $true) | ForEach-Object { $_.Extent.Text })
            $guardNames = @('Test-LegacyRunRequested', 'Assert-OrdinaryCoreRunRequest')
            $guards = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -cin $guardNames
            }, $true) | ForEach-Object { $_.Extent.Text })
            if ($guards.Count -ne $guardNames.Count) { throw 'Validate.ps1 must expose the ordinary Run request guard and legacy-input classifier.' }
            return New-Module -ScriptBlock ([scriptblock]::Create(($constants + $guards) -join "`n"))
        }

        function Get-FixtureExceptionMessage {
            param([Parameter(Mandatory = $true)][scriptblock] $Action)
            try { & $Action; return $null }
            catch { return [string]$_.Exception.Message }
        }

        function New-WorkflowLegacySourceProjectionModule {
            $match = [regex]::Match($script:Workflow, '(?ms)^      - name: Validate exact candidate with the verified runtime\r?\n(?<body>.*?)(?=^      - name: |\z)')
            $header = [regex]::Match($match.Groups['body'].Value, '(?m)^        run: \|\r?\n')
            if (-not $match.Success -or -not $header.Success) { throw 'Workflow validation run block is missing.' }
            $lines = $match.Groups['body'].Value.Substring($header.Index + $header.Length) -split '\r?\n'
            $code = (@($lines | ForEach-Object { if ($_.Length -eq 0) { '' } else { $_.Substring(10) } }) -join "`n")
            $tokens=$null; $errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
            if (@($errors).Count) { throw 'Workflow validation run block does not parse.' }
            $functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-LegacySourceCheckProjection'},$true))
            if ($functions.Count -ne 1) { throw 'Actual workflow source-check projection helper is missing.' }
            return New-Module -ScriptBlock ([scriptblock]::Create($functions[0].Extent.Text + "`nExport-ModuleMember -Function Assert-LegacySourceCheckProjection"))
        }

        function New-LegacySourceProjectionFixture {
            $candidate=[pscustomobject]@{sourceRepository='https://github.com/SyuanTsai/Skill-General.git';sourceRevision=('a'*40);baseRevision=('b'*40);candidateId=('c'*64);contentSha256=('d'*64)}
            $ids=@('controlled-acquisition','integrity-verification','package-validation','skillspector-static','repository-tests','conditional-semantic-scan','ai-review','human-approval','publish-or-install','post-install-verification')
            $stages=@(for($i=0;$i -lt $ids.Count;$i++){[pscustomobject]@{order=($i+1);id=$ids[$i];status=$(if($i -lt 5){'passed'}elseif($i -eq 5){'blocked'}else{'not-applicable'});events=@()}})
            $general=[pscustomobject]@{eventId='00000000-0000-4000-8000-000000000001';stageId='repository-tests';toolId='repository-test-general';candidateId=$candidate.candidateId;status='passed';exitCode=0;cleanedUp=$true;outputSha256=('e'*64)}
            $pester=[pscustomobject]@{eventId='00000000-0000-4000-8000-000000000002';stageId='repository-tests';toolId='repository-test-pester';candidateId=$candidate.candidateId;status='passed';exitCode=0;cleanedUp=$true;outputSha256=('f'*64)}
            $stages[2].events=@([pscustomobject]@{candidateId=$candidate.candidateId;status='passed';exitCode=0;cleanedUp=$true})
            $stages[3].events=@([pscustomobject]@{candidateId=$candidate.candidateId;status='passed';exitCode=0;cleanedUp=$true})
            $stages[4].events=@($general,$pester)
            $typed=[pscustomobject]@{eventId=$pester.eventId;toolId=$pester.toolId;outputSha256=$pester.outputSha256;testInventoryCount=2;testInventorySha256=('e'*64);total=7;passed=7;skipped=0;failed=0}
            return [pscustomobject]@{schemaVersion=1;evidence='standard-validation-evidence-v1';contract='standard-validation-contract-v1';state='BLOCKED';exitCode=10;releaseEligible=$false;candidate=$candidate;authority=[pscustomobject]@{repository='https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git';runnerSha256=('e'*64)};failure=[pscustomobject]@{state='BLOCKED';message='Semantic scan was triggered without explicit consent.'};stages=$stages;sourceConformance=[pscustomobject]@{schemaVersion=1;contract='standard-source-conformance-v1';status='passed';scope='source-stages-1-5';sourceRevision=$candidate.sourceRevision;candidateId=$candidate.candidateId;contentSha256=$candidate.contentSha256;checkedStages=@($stages[0..4] | ForEach-Object {[pscustomobject]@{order=$_.order;id=$_.id;status=$_.status}});pester=[pscustomobject]@{eventCount=1;events=@($typed);total=7;passed=7;skipped=0;failed=0};canonicalValidation=[pscustomobject]@{state='BLOCKED';exitCode=10;stage6Status='blocked';releaseEligible=$false};releaseEligible=$false;failureReasons=@()}}
        }

        function Invoke-LegacySourceProjectionFixture {
            param($Report,[int]$ExitCode=10)
            $module=New-WorkflowLegacySourceProjectionModule
            try { & $module {param($r,$exit) Assert-LegacySourceCheckProjection -Report $r -ProcessExitCode $exit -ExpectedSourceRevision ('a'*40) -ExpectedBaseRevision ('b'*40) -ExpectedAuthorityRunnerSha256 ('e'*64)} $Report $ExitCode }
            finally { Remove-Module $module -Force }
        }

        function Invoke-WorkflowCredentialFixture {
            param([Parameter(Mandatory)][ValidateSet('core', 'legacy')][string] $Mode)
            $stepPattern = '(?ms)^      - name: Validate exact candidate with the verified runtime\r?\n(?<body>.*?)(?=^      - name: |\z)'
            $stepMatch = [regex]::Match($script:Workflow, $stepPattern)
            if (-not $stepMatch.Success) { throw 'Canonical workflow validation step is missing.' }
            $body = $stepMatch.Groups['body'].Value
            $runHeader = [regex]::Match($body, '(?m)^        run: \|\r?\n')
            if (-not $runHeader.Success) { throw 'Canonical workflow validation run block is missing.' }
            $runLines = @($body.Substring($runHeader.Index + $runHeader.Length) -split '\r?\n')
            $runScript = (@($runLines | ForEach-Object {
                if ($_.Length -eq 0) { '' }
                elseif ($_.StartsWith('          ', [StringComparison]::Ordinal)) { $_.Substring(10) }
                else { throw "Unexpected indentation in validation run block: $_" }
            }) -join "`n")
            $guardMatch = [regex]::Match($runScript, '(?ms)^if \(\$env:VALIDATION_MODE -ceq ''core''\) \{.*?^\}')
            if (-not $guardMatch.Success) { throw 'Core token-isolation guard is missing from the canonical workflow.' }
            $tokens = $null
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseInput($guardMatch.Value, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -ne 0) { throw 'Core token-isolation guard does not parse as PowerShell.' }

            $guardIndex = $runScript.IndexOf($guardMatch.Value, [StringComparison]::Ordinal)
            $childIndex = $runScript.IndexOf('pwsh -NoProfile -NonInteractive -File ./scripts/Validate.ps1', [StringComparison]::Ordinal)
            $names = @('VALIDATION_MODE', 'GITHUB_TOKEN', 'GH_TOKEN', 'SYP_CREDENTIAL_SENTINEL')
            $previous = @{}
            foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
            try {
                [Environment]::SetEnvironmentVariable('VALIDATION_MODE', $Mode, 'Process')
                [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'fixture-github-token', 'Process')
                [Environment]::SetEnvironmentVariable('GH_TOKEN', 'fixture-gh-token', 'Process')
                [Environment]::SetEnvironmentVariable('SYP_CREDENTIAL_SENTINEL', 'preserve-me', 'Process')
                & ([scriptblock]::Create($guardMatch.Value))
                return [pscustomobject]@{
                    mode = $Mode
                    guardBeforeChild = ($guardIndex -ge 0 -and $childIndex -gt $guardIndex)
                    githubToken = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'Process')
                    ghToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
                    sentinel = [Environment]::GetEnvironmentVariable('SYP_CREDENTIAL_SENTINEL', 'Process')
                }
            }
            finally {
                foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
            }
        }
    }

    # Scenario: this driver selects the reviewed immutable central snapshot.
    # Purpose: enforce the complete approved authority identity without local policy.
    It 'UnitT10_pins_one_exact_reviewed_authority_without_local_deviation_policy' {
        @($script:Adapter.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'standardVersion', 'authority')
        $expectedCommit = $script:ExpectedAuthorityCommit
        $expectedArchiveSha256 = $script:ExpectedAuthorityArchiveSha256
        $expectedFiles = $script:ExpectedAuthorityFiles
        if ($script:Adapter.authority.commit -ceq $script:ExpectedNextAuthorityCommit) {
            $expectedCommit = $script:ExpectedNextAuthorityCommit
            $expectedArchiveSha256 = $script:ExpectedNextAuthorityArchiveSha256
            $expectedFiles = $script:ExpectedNextAuthorityFiles
        }
        elseif ($script:Adapter.authority.commit -ceq $script:ExpectedMergedAuthorityCommit) {
            $expectedCommit = $script:ExpectedMergedAuthorityCommit
            $expectedArchiveSha256 = $script:ExpectedMergedAuthorityArchiveSha256
            $expectedFiles = $script:ExpectedMergedAuthorityFiles
        }
        $script:Adapter.authority.commit | Should -Be $expectedCommit
        $script:Adapter.authority.archiveUrl | Should -Be "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$expectedCommit"
        $script:Adapter.authority.archiveSha256 | Should -Be $expectedArchiveSha256
        $script:Validator | Should -Match 'https://codeload\.github\.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/'
        @($script:Adapter.authority.files).Count | Should -Be $expectedFiles.Count
        foreach ($file in @($script:Adapter.authority.files)) {
            $expectedFiles.Contains($file.path) | Should -BeTrue
            $file.sha256 | Should -Be $expectedFiles[$file.path]
        }
        $script:Adapter.PSObject.Properties.Name | Should -Not -Contain 'deviations'
    }
    # Scenario: a protected workflow runs a reviewed base driver against a newer PR candidate.
    # Purpose: verify the protected driver pin before selecting an exact candidate pin for ordinary Run.
    It 'UnitT15_reads_authority_config_from_the_driver_checkout' {
        $script:Validator | Should -Match '\$configRoot = Split-Path -Parent \$PSScriptRoot'
        $script:Validator | Should -Match 'Read-JsonFile -Path \(Join-Path \$configRoot ''config/standard-v1\.json''\)'
        $script:Validator | Should -Match 'Read-JsonFile -Path \(Join-Path \$repoRoot ''config/standard-v1\.json''\)'
    }

    # Scenario: the approved candidate config is supplied to the actual driver verifier.
    # Purpose: exercise production identity checks without executing tools or network calls.
    It 'UnitT16_accepts_the_complete_approved_config_in_the_actual_driver_verifier' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $parts = @($ast.EndBlock.Statements | Where-Object {
            ($_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                $_.Left.Extent.Text -in @('$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles', '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles')) -or
            ($_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $_.Name -in @('Assert-ExactPropertySet', 'Assert-Sha256', 'Assert-AuthorityConfig'))
        } | ForEach-Object { $_.Extent.Text })
        $verifier = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $approved = [pscustomobject]@{
            schemaVersion = 1; standardVersion = 'v1'
            authority = [pscustomobject]@{
                repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
                commit = $script:ExpectedAuthorityCommit
                archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedAuthorityCommit)"
                archiveSha256 = $script:ExpectedAuthorityArchiveSha256
                files = @(foreach ($entry in $script:ExpectedAuthorityFiles.GetEnumerator()) {
                    [pscustomobject]@{ path = $entry.Key; sha256 = $entry.Value }
                })
            }
        }
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config } $approved } | Should -Not -Throw
    }

    It 'accepts the reviewed next tuple only with the internal opt-in, and keeps default modes old-only' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        $parts = @($ast.EndBlock.Statements | Where-Object {
            ($_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                $_.Left.Extent.Text -in @('$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles',
                    '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles')) -or
            ($_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $_.Name -in @('Assert-ExactPropertySet', 'Assert-Sha256', 'Assert-AuthorityConfig'))
        } | ForEach-Object { $_.Extent.Text })
        $verifier = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $next = [pscustomobject]@{
            schemaVersion = 1; standardVersion = 'v1'
            authority = [pscustomobject]@{
                repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
                commit = $script:ExpectedNextAuthorityCommit
                archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedNextAuthorityCommit)"
                archiveSha256 = $script:ExpectedNextAuthorityArchiveSha256
                files = @(foreach ($entry in $script:ExpectedNextAuthorityFiles.GetEnumerator()) {
                    [pscustomobject]@{ path = $entry.Key; sha256 = $entry.Value }
                })
            }
        }
        $pin = & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $next
        $pin.commit | Should -Be $script:ExpectedNextAuthorityCommit
        $pin.archiveSha256 | Should -Be $script:ExpectedNextAuthorityArchiveSha256
        @($pin.files.Keys) | Should -Be @($script:ExpectedNextAuthorityFiles.Keys)
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config } $next } | Should -Throw

        foreach ($change in @(
            { param($c) $c.authority.archiveSha256 = $script:ExpectedAuthorityArchiveSha256 },
            { param($c) $c.authority.files[0].sha256 = '0' * 64 },
            { param($c) [array]::Reverse($c.authority.files) },
            { param($c) $c.authority.commit = '7c65254d96bd21083ae827e54b9e51afee8ce304' }
        )) {
            $forged = $next | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
            & $change $forged
            { & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $forged } | Should -Throw
        }
        @('Run', 'run') | ForEach-Object { ($_ -eq 'Run') | Should -BeTrue }
        @('PrepareSemantic', 'ResumeSemantic') | ForEach-Object { ($_ -eq 'Run') | Should -BeFalse }
    }

    It 'verifies the protected driver tuple and the immutable Run candidate tuple before dispatch' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $calls = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'Assert-AuthorityConfig'
        }, $true))
        $calls.Count | Should -Be 2
        $baseCall = @($calls | Where-Object { $_.Extent.Text -match '\$config\b' })
        $candidateCall = @($calls | Where-Object { $_.Extent.Text -match '\$candidateConfig\b' })
        $baseCall.Count | Should -Be 1
        $candidateCall.Count | Should -Be 1
        $baseCall[0].Extent.Text | Should -Match 'Assert-AuthorityConfig\s+-Config\s+\$config\s+-AllowNextAuthority'
        $candidateCall[0].Extent.Text | Should -Match 'Assert-AuthorityConfig\s+-Config\s+\$candidateConfig\s+-AllowNextAuthority'
        $ancestor = $candidateCall[0].Parent
        while ($null -ne $ancestor -and $ancestor -isnot [Management.Automation.Language.IfStatementAst]) { $ancestor = $ancestor.Parent }
        $ancestor | Should -Not -BeNullOrEmpty
        $ancestor.Extent.Text | Should -Match '^\s*if\s*\(\$ExecutionMode\s+-eq\s+''Run''\)'

        $candidateRead = $script:Validator.IndexOf('Read-JsonFile -Path (Join-Path $repoRoot ''config/standard-v1.json'')')
        $candidateSelect = $script:Validator.IndexOf('$candidateAuthority = Assert-AuthorityConfig -Config $candidateConfig -AllowNextAuthority')
        $coreDispatch = $script:Validator.IndexOf('if ($coreRunSelected)')
        $candidateRead | Should -BeGreaterThan -1
        $candidateSelect | Should -BeGreaterThan $candidateRead
        $coreDispatch | Should -BeGreaterThan $candidateSelect
        @('Run', 'run') | ForEach-Object { ($_ -eq 'Run') | Should -BeTrue }
        @('PrepareSemantic', 'ResumeSemantic') | ForEach-Object { ($_ -eq 'Run') | Should -BeFalse }
    }
    # Scenario: ordinary Run receives legacy resolver inputs or a non-Core authority candidate.
    # Purpose: fail before Go resolution, archive acquisition, resolver installation, or a legacy fallback can begin.
    It 'UnitT38_rejects_legacy_ordinary_run_inputs_and_noncore_pins_before_tool_resolution' {
        $guard = New-OrdinaryRunGuardModule
        $corePin = (New-MergedAuthorityConfig).authority
        foreach ($legacyInputName in @(
            'AuthorityArchivePath', 'ExpectedGoRuntimeVersion', 'SemanticConsent', 'SemanticProvider',
            'SemanticPurpose', 'SemanticScope', 'SemanticEvidencePath', 'SemanticConsentRequestPath',
            'SemanticConsentDecisionPath', 'SemanticPublicKeyPath', 'SemanticPublicKeyId', 'SemanticRunPlanPath',
            'SemanticTriggered', 'SourceMergeExceptionReview', 'ProtectedSourceMergeCheck', 'ProtectedWorkflowRevision'
        )) {
            $legacyInputs = [ordered]@{ $legacyInputName = 'fixture' }
            foreach ($mode in @('Run', 'run', 'RUN')) {
                (Get-FixtureExceptionMessage -Action {
                    & $guard {
                        param($executionMode, $pin, $bound)
                        Assert-OrdinaryCoreRunRequest -ExecutionMode $executionMode -CandidateAuthority $pin -BoundParameters $bound
                    } $mode $corePin $legacyInputs
                }) | Should -Match 'Ordinary Run does not accept legacy tool-resolution or development-harness inputs'
            }
        }

        $baseline = [pscustomobject]@{
            repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
            commit = $script:ExpectedAuthorityCommit
        }
        foreach ($mode in @('Run', 'run', 'RUN')) {
            (Get-FixtureExceptionMessage -Action {
                & $guard {
                    param($executionMode, $pin)
                    Assert-OrdinaryCoreRunRequest -ExecutionMode $executionMode -CandidateAuthority $pin -BoundParameters @{ AuthorityArchivePath = 'legacy.zip' }
                } $mode $baseline
            }) | Should -Match 'Ordinary Run does not accept legacy tool-resolution or development-harness inputs'
        }

        { & $guard { param($pin) Assert-OrdinaryCoreRunRequest -ExecutionMode 'PrepareSemantic' -CandidateAuthority $pin -BoundParameters @{} } $baseline } |
            Should -Not -Throw

        $guardIndex = $script:Validator.IndexOf('Assert-OrdinaryCoreRunRequest -ExecutionMode $ExecutionMode')
        $goResolutionIndex = $script:Validator.IndexOf('$goRuntimeVersion = Resolve-GoRuntimeVersion')
        $resolverInstallIndex = $script:Validator.IndexOf("'-Install', '-InstallRoot'")
        $guardIndex | Should -BeGreaterOrEqual 0
        $goResolutionIndex | Should -BeGreaterThan $guardIndex
        $resolverInstallIndex | Should -BeGreaterThan $guardIndex
    }

    It 'runs the next candidate pin through Core while explicit Semantic setup remains separate' {
        $script:Validator | Should -Match '\[string\]\$candidateAuthority\.commit -cin @\(\$script:NextAuthorityCommit, \$script:MergedAuthorityCommit\)'
        $script:Validator | Should -Match 'Assert-OrdinaryCoreRunRequest -ExecutionMode \$ExecutionMode -CandidateAuthority \$candidateAuthority -BoundParameters \$PSBoundParameters'
        $script:Validator | Should -Match 'Assert-StandardCoreAuthorityCheckout -GitPath \$gitPath -AuthorityRoot \$AuthorityRepositoryRoot -AuthorityPin \$candidateAuthority'
        $script:Validator | Should -Match '''-AuthorityRevision'', \[string\]\$candidateAuthority\.commit'
        $script:Validator | Should -Match '\$authority = Get-LegacyAuthorityPin -SelectedPin \$candidateAuthority'
        $script:Validator | Should -Match 'Invoke-WebRequest -Uri \(\[string\]\$authority\.archiveUrl\)'
        $script:Validator | Should -Match ([regex]::Escape("'-ProtectedAuthorityArchiveSha256', `$authority.archiveSha256"))
    }
    It 'keeps ResumeSemantic tied to the baseline tuple before the normal Run selector' {
        $resumeIndex = $script:Validator.IndexOf('if ($ExecutionMode -eq ''ResumeSemantic'')')
        $selectorIndex = $script:Validator.IndexOf('$baseAuthority = Assert-AuthorityConfig')
        $resumeBlock = $script:Validator.Substring($resumeIndex, $selectorIndex - $resumeIndex)
        $resumeBlock | Should -Match '\$script:AuthorityCommit'
        $resumeBlock | Should -Match '\$script:AuthorityArchiveSha256'
        $resumeBlock | Should -Not -Match 'AllowNextAuthority|\$baseAuthority'
    }

    # Scenario: the config contains an obsolete revision or a forged helper/runner digest.
    # Purpose: reject every required dependency identity mismatch before tool execution.
    It 'UnitT17_rejects_obsolete_revision_and_forged_dependency_hashes_in_the_actual_driver_verifier' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        $parts = @($ast.EndBlock.Statements | Where-Object {
            ($_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                $_.Left.Extent.Text -in @('$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles', '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles')) -or
            ($_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $_.Name -in @('Assert-ExactPropertySet', 'Assert-Sha256', 'Assert-AuthorityConfig'))
        } | ForEach-Object { $_.Extent.Text })
        $verifier = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $obsolete = $script:Adapter | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $obsolete.authority.commit = '7c65254d96bd21083ae827e54b9e51afee8ce304'
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config } $obsolete } | Should -Throw
        foreach ($path in @('scripts/Resolve-PythonWheelClosure.py', 'scripts/Resolve-StandardValidationTool.ps1',
            'docs/standards/standard-validation-contract-v1.json', 'scripts/Invoke-StandardValidation.ps1')) {
            $forged = $script:Adapter | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            ($forged.authority.files | Where-Object { $_.path -ceq $path }).sha256 = '0' * 64
            { & $verifier { param($config) Assert-AuthorityConfig -Config $config } $forged } | Should -Throw
        }
    }

    # Scenario: the default Run adapter is prepared for an ordinary Core v2 repository check.
    # Purpose: bind a trusted PowerShell executable by hash and keep the dispatch schema minimal.
    It 'UnitT20_builds_the_minimal_core_v2_adapter_for_repository_validation' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $definition = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq 'New-StandardCoreAdapterV2'
        }) | Select-Object -First 1
        $definition | Should -Not -BeNullOrEmpty

        $adapterModule = New-Module -ScriptBlock ([scriptblock]::Create($definition.Extent.Text))
        $powerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
        $adapterRunId = [guid]::NewGuid().ToString('N')
        $adapter = & $adapterModule {
            param($executable, $runId)
            New-StandardCoreAdapterV2 -PowerShellPath $executable -TrustedToolRoot (Split-Path -Parent $executable) `
                -CandidateAuthorityAdapterRunId $runId -ActiveSkillIds @('Fixture.Skill')
        } $powerShellExecutable $adapterRunId
        $adapter.schemaVersion | Should -Be 2
        $adapter.adapter | Should -Be 'standard-core-adapter-v2'
        $adapter.skillsRoot | Should -Be 'skills'
        @($adapter.activeSkills) | Should -Be @('Fixture.Skill')
        @($adapter.checks).Count | Should -Be 2
        $check = $adapter.checks[0]
        $check.id | Should -Be 'repository-general'
        $check.kind | Should -Be 'general'
        $check.executable | Should -Be ([IO.Path]::GetFullPath($powerShellExecutable))
        $check.executableSha256 | Should -Be ((Get-FileHash -LiteralPath $powerShellExecutable -Algorithm SHA256).Hash.ToLowerInvariant())
        @($check.arguments) | Should -Be @('-NoProfile', '-NonInteractive', '-File', 'scripts/Test-SkillGeneral.ps1', '-ReadOnlySnapshot')
        $pesterCheck = $adapter.checks[1]
        $pesterCheck.id | Should -Be 'repository-pester'
        $pesterCheck.kind | Should -Be 'pester'
        $pesterCheck.executable | Should -Be ([IO.Path]::GetFullPath($powerShellExecutable))
        $pesterCheck.executableSha256 | Should -Be $check.executableSha256
        @($pesterCheck.arguments) | Should -Be @('-NoProfile', '-NonInteractive', '-File', 'scripts/Invoke-CorePester.ps1', '-CandidateAuthorityAdapterRunId', $adapterRunId)
        { & $adapterModule { param($executable, $root, $runId) New-StandardCoreAdapterV2 -PowerShellPath $executable -TrustedToolRoot $root -CandidateAuthorityAdapterRunId $runId -ActiveSkillIds @('Fixture.Skill') } $script:ValidatorPath (Split-Path -Parent $powerShellExecutable) $adapterRunId } | Should -Throw
    }

    # Scenario: the ordinary Core Pester wrapper uses Detailed output for live timing while returning a typed result.
    # Purpose: Preserve real pass/fail/skip and block/container failure counts without polluting JSON stdout.
    It 'UnitT20_keeps_core_pester_output_typed_and_real_counts' {
        $wrapperPath = Join-Path $script:RepositoryRoot 'scripts/Invoke-CorePester.ps1'
        $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($wrapper, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $wrapper | Should -Match '\$pesterConfig\.Output\.Verbosity = ''Detailed'''
        $wrapper | Should -Match '\$pesterConfig\.TestRegistry\.Enabled = \$false'
        $wrapper | Should -Match '\$CandidateAuthorityAdapterRunId'
        $wrapper | Should -Match 'Get-VerifiedCoreAuthoritySnapshotPath'
        $wrapper | Should -Match 'STANDARD_VALIDATION_CORE_RUN_ID'
        $wrapper | Should -Match 'SYP154_CANDIDATE_AUTHORITY_ROOT'
        $wrapper | Should -Match 'Test-CorePesterLoadedModuleIdentity -Modules \$loadedPester -ExpectedVersion \(\[string\]\$closureLockRecord\.Value\.source\.version\)'
        $wrapper | Should -Match 'Core Pester module candidate check failed'
        $wrapper | Should -Match 'Core Pester runtime closure check failed before import'
        $wrapper | Should -Match 'Get-CorePesterRuntimeModuleRoot'
        $wrapper | Should -Match 'Invoke-Pester -Configuration \$pesterConfig 3>\$null 6>&1'
        $wrapper | Should -Match '\$pesterConfig\.Run\.Path = \$testRoot'
        $wrapper | Should -Match "runScope = 'complete-unfiltered-tests-tree'"
        $wrapper | Should -Match 'sourceStartOffset'
        $wrapper | Should -Match 'ExpandedPath'
        $integritySource = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'scripts/CorePesterIntegrity.psm1') -Raw
        $integritySource | Should -Match 'duplicate or ambiguous case identity'
        $wrapper | Should -Match 'execution collection union differs from TotalCount'
        $wrapper | Should -Match "-Filter '\*\.Tests\.ps1'"
        $wrapper | Should -Match 'Candidate test-file container'
        $wrapper | Should -Match 'containerFileInventory'
        $wrapper | Should -Match '\[IO\.FileMode\]::CreateNew'
        $wrapper | Should -Match 'case inventory sidecar readback is truncated'
        $wrapper | Should -Match 'repository-pester-case-inventory-v1\.json'
        $wrapper | Should -Match 'Pester case inventory ledger: path='
        $wrapper | Should -Match "report = 'standard-core-pester-result-v1'"
        $wrapper | Should -Match '\$failed = \[int\]\$result\.FailedCount'
        $wrapper | Should -Match '\$skipped = \[int\]\$result\.SkippedCount'
        $wrapper | Should -Match '\$failedBlocks = \[int\]\$result\.FailedBlocksCount'
        $wrapper | Should -Match '\$failedContainers = \[int\]\$result\.FailedContainersCount'
        $wrapper | Should -Match '\$ErrorActionPreference = ''Continue'''
        $wrapper | Should -Match '\(\$passed \+ \$skipped\) -ne \$total'
    }

    It 'rejects a Pester discovery failure even when its other test passes' {
        $fixtureRoot = Join-Path $TestDrive 'core-pester-discovery-failure'
        $driverRunId = [guid]::NewGuid().ToString('N')
        $coreRunId = [guid]::NewGuid().ToString('N')
        $runOwnedRoot = Join-Path $fixtureRoot 'run-owned'
        $candidateRoot = Join-Path $runOwnedRoot "artifacts/runs/$coreRunId/candidate"
        $authorityRoot = Join-Path $runOwnedRoot ".core-v2-adapter-$driverRunId/authority"
        $fixtureTests = Join-Path $candidateRoot 'tests'
        [void](New-Item -ItemType Directory -Path $fixtureTests, $authorityRoot -Force)
        [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $authorityRoot) 'standard-core-adapter-v2.json'), '{}', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $fixtureTests 'Broken.Tests.ps1'), "throw 'synthetic discovery failure'`n")
        [IO.File]::WriteAllText((Join-Path $fixtureTests 'Healthy.Tests.ps1'), "Describe 'healthy' { It 'passes' { 1 | Should -Be 1 } }`n")
        $wrapperPath = Join-Path $script:RepositoryRoot 'scripts/Invoke-CorePester.ps1'
        $pwsh = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $oldPath = $env:PSModulePath
        $runtimeModuleRoot = Join-Path (Split-Path -Parent $pwsh) 'Modules'
        $env:PSModulePath = $runtimeModuleRoot
        $diagnostics = Join-Path $fixtureRoot 'diagnostics.err'
        $oldRunId = $env:STANDARD_VALIDATION_CORE_RUN_ID
        $oldCheckId = $env:STANDARD_VALIDATION_CORE_CHECK_ID
        $env:STANDARD_VALIDATION_CORE_RUN_ID = $coreRunId
        $env:STANDARD_VALIDATION_CORE_CHECK_ID = 'repository-pester'
        Push-Location $candidateRoot
        try {
            $output = @(& $pwsh -NoProfile -NonInteractive -File $wrapperPath -CandidateAuthorityAdapterRunId $driverRunId 2> $diagnostics)
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
            $env:PSModulePath = $oldPath
            $env:STANDARD_VALIDATION_CORE_RUN_ID = $oldRunId
            $env:STANDARD_VALIDATION_CORE_CHECK_ID = $oldCheckId
        }
        $exitCode | Should -Be 1
        $output.Count | Should -Be 0 -Because 'a rejected discovery run must not emit a success-shaped machine report'
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Core Pester acceptance failed; no success report was emitted\.'
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester container failed:.*Broken\.Tests\.ps1'
        (Get-Content -LiteralPath $diagnostics -Raw) | Should -Match 'Pester container error: synthetic discovery failure'
    }

    It 'accepts only the exact reviewed Core authority tuple' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        $parts = @($ast.EndBlock.Statements | Where-Object {
            ($_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                $_.Left.Extent.Text -in @('$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles', '$script:NextAuthorityCommit', '$script:NextAuthorityArchiveSha256', '$script:NextAuthorityFiles')) -or
            ($_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $_.Name -in @('Assert-ExactPropertySet', 'Assert-Sha256', 'Assert-AuthorityConfig'))
        } | ForEach-Object { $_.Extent.Text })
        $verifier = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $approved = [pscustomobject]@{
            schemaVersion = 1; standardVersion = 'v1'
            authority = [pscustomobject]@{
                repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
                commit = $script:ExpectedNextAuthorityCommit
                archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedNextAuthorityCommit)"
                archiveSha256 = $script:ExpectedNextAuthorityArchiveSha256
                files = @(foreach ($entry in $script:ExpectedNextAuthorityFiles.GetEnumerator()) {
                    [pscustomobject]@{ path = $entry.Key; sha256 = $entry.Value }
                })
            }
        }
        $pin = & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $approved
        $pin.commit | Should -Be $script:ExpectedNextAuthorityCommit
        @($pin.files.Keys) | Should -Be @($script:ExpectedNextAuthorityFiles.Keys)
        foreach ($path in $script:ExpectedNextAuthorityFiles.Keys) {
            $pin.files[$path] | Should -Be $script:ExpectedNextAuthorityFiles[$path]
        }
        $mixed = $approved | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $mixed.authority.archiveSha256 = $script:ExpectedAuthorityArchiveSha256
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $mixed } | Should -Throw
        $forged = $approved | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        $forged.authority.files[0].sha256 = '0' * 64
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $forged } | Should -Throw
    }

    It 'routes explicit advanced Run requests through the complete legacy authority tuple' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $parts = @($ast.EndBlock.Statements | Where-Object {
            ($_ -is [Management.Automation.Language.AssignmentStatementAst] -and
                $_.Left.Extent.Text -in @('$script:AuthorityRepository', '$script:AuthorityCommit', '$script:AuthorityArchiveSha256', '$script:AuthorityFiles', '$script:NextAuthorityCommit')) -or
            ($_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $_.Name -in @('Get-LegacyAuthorityPin', 'Test-LegacyRunRequested'))
        } | ForEach-Object { $_.Extent.Text })
        $legacyModule = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $legacy = & $legacyModule {
            $selected = [pscustomobject]@{
                repository = $script:AuthorityRepository
                commit = $script:NextAuthorityCommit
            }
            Get-LegacyAuthorityPin -SelectedPin $selected
        }
        $legacy.commit | Should -Be '51399617ddebe21656fe4265a8d9ad116a943583'
        $legacy.archiveUrl | Should -Be "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($legacy.commit)"
        $legacy.archiveSha256 | Should -Be 'b115762de7d4da6f0f95143e1853bd3822fe224d2e673539ace3f480df6ef50d'
        @($legacy.files.Keys).Count | Should -Be 26

        $legacyRoutingResults = & $legacyModule {
            $ordinary = [ordered]@{}
            $results = [System.Collections.Generic.List[object]]::new()
            $results.Add([pscustomobject]@{ name = 'ordinary'; value = (Test-LegacyRunRequested -BoundParameters $ordinary) })
            foreach ($name in @('AuthorityArchivePath', 'ExpectedGoRuntimeVersion', 'SemanticTriggered', 'SemanticRunPlanPath', 'SourceMergeExceptionReview', 'ProtectedSourceMergeCheck', 'ProtectedWorkflowRevision')) {
                $explicit = [ordered]@{ $name = $true }
                $results.Add([pscustomobject]@{ name = $name; value = (Test-LegacyRunRequested -BoundParameters $explicit) })
            }
            return $results.ToArray()
        }
        ($legacyRoutingResults | Where-Object name -eq 'ordinary').value | Should -BeFalse
        @($legacyRoutingResults | Where-Object name -ne 'ordinary' | Where-Object { -not $_.value }).Count | Should -Be 0
        $script:Validator | Should -Match '\$authority = Get-LegacyAuthorityPin -SelectedPin \$candidateAuthority'
        $script:Validator | Should -Match 'Invoke-WebRequest -Uri \(\[string\]\$authority\.archiveUrl\)'
        $script:Validator | Should -Match 'ProtectedWorkflowRevision requires -ProtectedSourceMergeCheck'
    }

    It 'places the Core adapter beside its artifacts root and keeps output inside the root' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $parts = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $_.Name -in @('Test-PathWithinOrEqual', 'Assert-PathWithinRoot', 'Get-StandardCoreRunPaths')
        } | ForEach-Object { $_.Extent.Text })
        $pathModule = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $parent = Join-Path ([IO.Path]::GetTempPath()) ("core-path-tests-" + [guid]::NewGuid().ToString('N'))
        $explicitRoot = Join-Path $parent 'explicit-artifacts'
        $explicitOutput = Join-Path $explicitRoot 'reports/core.json'
        $explicit = & $pathModule {
            param($root, $output)
            Get-StandardCoreRunPaths -ArtifactsRoot $root -ArtifactsRootWasExplicit $true -OutputPath $output
        } $explicitRoot $explicitOutput
        $explicit.artifactsRoot | Should -Be ([IO.Path]::GetFullPath($explicitRoot))
        $explicit.outputPath | Should -Be ([IO.Path]::GetFullPath($explicitOutput))
        $explicitOutputInside = & $pathModule { param($path, $root) Test-PathWithinOrEqual -Path $path -Root $root } $explicit.outputPath $explicit.artifactsRoot
        $explicitAdapterInside = & $pathModule { param($path, $root) Test-PathWithinOrEqual -Path $path -Root $root } $explicit.adapterRoot $explicit.artifactsRoot
        $explicitOutputInside | Should -BeTrue
        $explicitAdapterInside | Should -BeFalse

        $defaultOne = & $pathModule {
            param($root)
            Get-StandardCoreRunPaths -ArtifactsRoot $root -ArtifactsRootWasExplicit $false
        } $parent
        $defaultTwo = & $pathModule {
            param($root)
            Get-StandardCoreRunPaths -ArtifactsRoot $root -ArtifactsRootWasExplicit $false
        } $parent
        $defaultOne.artifactsRoot | Should -Not -Be $defaultTwo.artifactsRoot
        $defaultOutputInside = & $pathModule { param($path, $root) Test-PathWithinOrEqual -Path $path -Root $root } $defaultOne.outputPath $defaultOne.artifactsRoot
        $defaultAdapterInside = & $pathModule { param($path, $root) Test-PathWithinOrEqual -Path $path -Root $root } $defaultOne.adapterRoot $defaultOne.artifactsRoot
        $defaultOutputInside | Should -BeTrue
        $defaultAdapterInside | Should -BeFalse
        { & $pathModule { param($root, $output) Get-StandardCoreRunPaths -ArtifactsRoot $root -ArtifactsRootWasExplicit $false -OutputPath $output } $parent $explicitOutput } | Should -Throw
    }

    It 'dispatches only preflight-approved ordinary Run requests through Core v2' {
        $branchIndex = $script:Validator.IndexOf('if ($coreRunSelected)')
        $argumentsStart = $script:Validator.IndexOf('$coreRunnerArgs = @(', $branchIndex)
        $invokeIndex = $script:Validator.IndexOf('& $pwshPath -NoProfile -NonInteractive -File $centralRunnerPath @coreRunnerArgs', $argumentsStart)
        $branchIndex | Should -BeGreaterThan -1
        $argumentsStart | Should -BeGreaterThan $branchIndex
        $invokeIndex | Should -BeGreaterThan $argumentsStart
        $coreArguments = $script:Validator.Substring($argumentsStart, $invokeIndex - $argumentsStart)
        $coreArguments | Should -Match '\[string\]\$candidateAuthority\.commit'
        $coreArguments | Should -Match 'TrustedToolRoot.*, \$trustedRoot'
        $coreArguments | Should -Not -Match 'CandidateArchive|DevelopmentHarness|Semantic|Supervisor|Lifecycle|ExpectedPlanSha256'
        $script:Validator | Should -Match '(?s)\$coreRunSelected = \$ExecutionMode -eq ''Run'' -and\s+\[string\]\$candidateAuthority\.repository -ceq \$script:AuthorityRepository -and\s+\[string\]\$candidateAuthority\.commit -cin @\(\$script:NextAuthorityCommit, \$script:MergedAuthorityCommit\)'
        $preflightIndex = $script:Validator.IndexOf('Assert-OrdinaryCoreRunRequest -ExecutionMode $ExecutionMode')
        $preflightIndex | Should -BeGreaterThan -1
        $preflightIndex | Should -BeLessThan $branchIndex
        $script:Validator | Should -Match 'Test-LegacyRunRequested -BoundParameters \$BoundParameters'
        $script:Validator | Should -Match 'Ordinary Run does not accept legacy tool-resolution or development-harness inputs'
        $script:Validator | Should -Match 'Ordinary Run requires one exact approved Core authority pin'
        $script:Validator | Should -Match ([regex]::Escape("'-ArtifactsRoot', `$coreArtifactsRoot"))
        $script:Validator | Should -Match ([regex]::Escape("'-AdapterPath', `$adapterPath"))
        $script:Validator | Should -Match 'Get-StandardCoreRunPaths -ArtifactsRoot \$artifactsRootPath'
        $script:Validator | Should -Match 'Assert-OutsideRoot -Path \$adapterRoot -Root \$coreArtifactsRoot'
        $script:Validator | Should -Match 'Invoke-WebRequest -Uri \(\[string\]\$authority\.archiveUrl\)'
        $script:Validator | Should -Match '\$AuthorityRepositoryRoot'
        $script:Validator | Should -Match 'Assert-StandardCoreAuthorityCheckout'
        $script:Validator | Should -Match 'Assert-AuthorityConfig -Config \$config'
    }
    It 'verifies authority before resolving or executing any validation tool' {
        $archiveIndex = $script:Validator.IndexOf('Expand-Archive')
        $archiveHashIndex = $script:Validator.IndexOf('Authority archive SHA-256 does not match')
        $fileHashIndex = $script:Validator.IndexOf('Authority file identity mismatch')
        $resolverIndex = $script:Validator.LastIndexOf('resolverPath = Join-Path')
        $centralIndex = $script:Validator.LastIndexOf('centralRunnerPath = Join-Path')

        $archiveIndex | Should -BeGreaterThan -1
        $archiveHashIndex | Should -BeGreaterThan $archiveIndex
        $fileHashIndex | Should -BeGreaterThan $archiveHashIndex
        $resolverIndex | Should -BeGreaterThan $fileHashIndex
        $centralIndex | Should -BeGreaterThan $resolverIndex
    }

    It 'rejects hidden authority worktree edits while accepting Windows CRLF checkout text' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script:Validator, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $names = @('Test-PathWithinOrEqual', 'Test-PathEqual', 'Assert-PathWithinRoot',
            'Assert-NoReparseAncestors', 'Resolve-GitRevision', 'Get-GitBlobSha256',
            'Test-AuthorityWorktreeSha256', 'Assert-StandardCoreAuthorityCheckout',
            'New-StandardCoreAuthoritySnapshot')
        $parts = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in $names
        } | ForEach-Object { $_.Extent.Text })
        $parts.Count | Should -Be $names.Count
        $verifier = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n")))
        $gitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $authorityRoot = Join-Path $TestDrive 'authority-worktree'
        $runnerPath = Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1'
        $contractPath = Join-Path $authorityRoot 'docs/standards/standard-core-validation-v2.json'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $runnerPath) -Force)
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $contractPath) -Force)
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($runnerPath, "Write-Output 'trusted'`n", $utf8)
        [IO.File]::WriteAllText($contractPath, "{}`n", $utf8)
        & $gitPath -C $authorityRoot init -q | Out-Null
        & $gitPath -C $authorityRoot config core.autocrlf false
        & $gitPath -C $authorityRoot config user.name 'Example Reviewer'
        & $gitPath -C $authorityRoot config user.email 'reviewer@example.com'
        & $gitPath -C $authorityRoot remote add origin 'https://example.com/authority.git'
        & $gitPath -C $authorityRoot add -- scripts/Invoke-StandardValidation.ps1 docs/standards/standard-core-validation-v2.json
        & $gitPath -C $authorityRoot commit -qm 'Test authority snapshot'
        $head = ([string](& $gitPath -C $authorityRoot rev-parse HEAD)).Trim()
        $runnerSha = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $pin = [pscustomobject]@{
            commit = $head
            repository = 'https://example.com/authority.git'
            files = [ordered]@{'scripts/Invoke-StandardValidation.ps1' = $runnerSha}
        }
        $approved = & $verifier { param($g, $root, $p) Assert-StandardCoreAuthorityCheckout -GitPath $g -AuthorityRoot $root -AuthorityPin $p } $gitPath $authorityRoot $pin
        $approved.revision | Should -Be $head
        $ownedRoot = Join-Path $TestDrive 'snapshot-owner'
        [void](New-Item -ItemType Directory -Path $ownedRoot)
        $snapshot = & $verifier { param($g, $root, $owned, $p) New-StandardCoreAuthoritySnapshot -GitPath $g -SourceRoot $root -OwnedRoot $owned -AuthorityPin $p } $gitPath $authorityRoot $ownedRoot $pin
        $snapshot.revision | Should -Be $head

        [IO.File]::WriteAllText($runnerPath, "Write-Output 'untrusted'`n", $utf8)
        & $gitPath -C $authorityRoot update-index --assume-unchanged -- scripts/Invoke-StandardValidation.ps1
        @(& $gitPath -C $authorityRoot status --porcelain=v1 --untracked-files=all).Count | Should -Be 0
        [IO.File]::ReadAllText($snapshot.runnerPath, $utf8) | Should -Be "Write-Output 'trusted'`n"
        (& $verifier { param($g, $root, $p) Assert-StandardCoreAuthorityCheckout -GitPath $g -AuthorityRoot $root -AuthorityPin $p } $gitPath $snapshot.root $pin).revision |
            Should -Be $head
        (Get-FixtureExceptionMessage -Action {
            & $verifier { param($g, $root, $p) Assert-StandardCoreAuthorityCheckout -GitPath $g -AuthorityRoot $root -AuthorityPin $p } $gitPath $authorityRoot $pin
        }) | Should -Match 'Pinned authority file identity mismatch'

        & $gitPath -C $authorityRoot update-index --no-assume-unchanged -- scripts/Invoke-StandardValidation.ps1
        [IO.File]::WriteAllText($runnerPath, "Write-Output 'trusted'`n", $utf8)
        [IO.File]::WriteAllText($contractPath, "{`"changed`":true}`n", $utf8)
        & $gitPath -C $authorityRoot update-index --assume-unchanged -- docs/standards/standard-core-validation-v2.json
        @(& $gitPath -C $authorityRoot status --porcelain=v1 --untracked-files=all).Count | Should -Be 0
        (Get-FixtureExceptionMessage -Action {
            & $verifier { param($g, $root, $p) Assert-StandardCoreAuthorityCheckout -GitPath $g -AuthorityRoot $root -AuthorityPin $p } $gitPath $authorityRoot $pin
        }) | Should -Match 'Pinned Core v2 contract worktree content differs'

        $crlfPath = Join-Path $TestDrive 'crlf-checkout.ps1'
        [IO.File]::WriteAllText($crlfPath, "Write-Output 'a'`r`nWrite-Output 'b'`r`n", $utf8)
        $lfBytes = $utf8.GetBytes("Write-Output 'a'`nWrite-Output 'b'`n")
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $lfSha = ([BitConverter]::ToString($hasher.ComputeHash($lfBytes)) -replace '-', '').ToLowerInvariant() }
        finally { $hasher.Dispose() }
        (& $verifier { param($path, $sha) Test-AuthorityWorktreeSha256 -Path $path -ExpectedSha256 $sha } $crlfPath $lfSha) |
            Should -BeTrue
    }

    It 'passes resolver named arguments through the trusted PowerShell host' {
        $script:Validator | Should -Match '& \$PowerShellPath -NoProfile -NonInteractive -File \$ResolverPath @Arguments'
        $script:Validator | Should -Match 'Invoke-Resolver -PowerShellPath \$pwshPath'
    }

    It 'expands collection-valued package reports before validating each result' {
        $script:Validator | Should -Match 'return \$Object\.PSObject\.Properties\[\$Name\]\.Value'
        $script:Validator | Should -Not -Match 'return ,\$Object\.PSObject\.Properties\[\$Name\]\.Value'
        $script:Validator | Should -Match 'foreach \(\$result in \$results\)'
    }

    It 'keeps repository Pester child output JSON-only' {
        $script:Validator | Should -Match '\$result = Invoke-Pester -Path \$testRoot -Output Detailed -PassThru 3>\$null 6>&1 \|'
        $script:Validator | Should -Match 'if \(\$_ -is \[Management\.Automation\.InformationRecord\]\)'
        $script:Validator | Should -Match '\[IO\.File\]::WriteAllLines\(\$progressPath, \$progressTail\.ToArray\(\)'
        $script:Validator | Should -Match '\[Console\]::Error\.WriteLine\("Pester progress: \$entry"\)'
        $script:Validator | Should -Match 'Pester counts: total='
        $script:Validator | Should -Match 'Pester progress:'
        $script:Validator | Should -Match '\[Console\]::Error\.WriteLine\("Pester container failed:'
        $script:Validator | Should -Match '\[Console\]::Error\.WriteLine\("Pester block failed:'
        $script:Validator | Should -Match '\[Console\]::Error\.WriteLine\("Pester test failed:'
        $script:Validator | Should -Match '\[int64\]\$result\.FailedContainersCount -ne 0 -or'
    }

    It 'uses the P02 central runner as the only stage and severity orchestrator' {
        $script:Validator | Should -Match 'Invoke-StandardValidation\.ps1'
        $script:Validator | Should -Match '-DevelopmentHarness'
        $script:Validator | Should -Match '& \$pwshPath -NoProfile -NonInteractive -File \$centralRunnerPath @centralRunnerArgs'
        $script:Validator | Should -Match 'standard-validation-adapter\.json'
        $script:Validator | Should -Match 'packageAdapter'
        $script:Validator | Should -Match 'skillValidator'
        $script:Validator | Should -Match 'skillTools'
        $script:Validator | Should -Match 'staticAnalyzer'
        $script:Validator | Should -Match 'repositoryTests'
        $script:Validator | Should -Not -Match 'ConvertTo-ValidationSecurityFinding'
        $script:Validator | Should -Not -Match 'deviations\s*='
        $script:Validator | Should -Not -Match 'Get-ValidationSecurityAction'
    }

    It 'passes semantic bridge v2 inputs through the development harness central runner' {
        $centralRunnerStart = $script:Validator.IndexOf('$centralRunnerArgs = @(')
        $centralRunnerInvoke = $script:Validator.IndexOf('& $pwshPath -NoProfile -NonInteractive -File $centralRunnerPath @centralRunnerArgs')
        $centralRunnerStart | Should -BeGreaterThan -1
        $centralRunnerInvoke | Should -BeGreaterThan $centralRunnerStart
        $centralRunnerBlock = $script:Validator.Substring($centralRunnerStart, $centralRunnerInvoke - $centralRunnerStart)
        foreach ($parameter in @(
            'SemanticEvidencePath',
            'SemanticConsentRequestPath',
            'SemanticConsentDecisionPath',
            'SemanticPublicKeyPath',
            'SemanticPublicKeyId'
        )) {
            $declaration = '[string] $' + $parameter
            $pair = '@(' + "'" + '-' + $parameter + "', " + '$' + $parameter + ')'
            $script:Validator | Should -Match ([regex]::Escape($declaration))
            $centralRunnerBlock | Should -Match ([regex]::Escape($pair))
        }
        $script:Validator | Should -Match '(?s)\$centralRunnerArgs = @\(.*?DevelopmentHarness.*?\)'
        $script:Validator | Should -Match 'if \(\$SemanticConsent\) \{ \$centralRunnerArgs \+= ''-SemanticConsent'' \}'
        foreach ($parameter in @('SemanticProvider', 'SemanticPurpose', 'SemanticScope')) {
            $pair = '@(' + "'" + '-' + $parameter + "', " + '$' + $parameter + ')'
            $script:Validator | Should -Match ([regex]::Escape($pair))
        }
    }

    It 'keeps Test-SkillGeneral and Pester in repository-test dispatch after Static' {
        $script:Validator | Should -Match 'repository-test-general'
        $script:Validator | Should -Match 'repository-test-pester'
        $script:Validator | Should -Match 'Test-SkillGeneral\.ps1'
        $script:Validator | Should -Match 'Invoke-Pester'
        $repositoryTestsIndex = $script:Validator.IndexOf('repositoryTests = @(')
        $centralIndex = $script:Validator.IndexOf('Invoke-StandardValidation.ps1')
        $repositoryTestsIndex | Should -BeGreaterThan -1
        $centralIndex | Should -BeGreaterThan -1
    }

    It 'binds an immutable distinct base ancestor before invoking the central runner' {
        $script:Validator | Should -Match 'rev-parse --verify --end-of-options'
        $script:Validator | Should -Match 'merge-base --is-ancestor'
        $script:Validator | Should -Match 'Base commit must be a distinct ancestor'
        $script:Validator | Should -Match 'BaseRevision'
        $script:Validator | Should -Match '--prefix=candidate-\$candidateCommit/'
    }

    It 'keeps generated adapter and evidence roots outside the candidate' {
        $script:Validator | Should -Match 'Assert-OutsideRoot -Path \$artifactsRootPath -Root \$repoRoot'
        $script:Validator | Should -Match 'trustedRoot'
        $script:Validator | Should -Match 'sgv1-resolved-tools-\$runId'
        $script:Validator | Should -Match 'Assert-NoReparseAncestors -Path \$resolvedToolsRoot'
        $script:Validator | Should -Match 'Assert-PathWithinRoot'
        $script:Validator | Should -Match 'OutputPath'
        $script:Validator | Should -Match '\(\(Test-Path -LiteralPath \$trustedRoot\) -or \(Test-Path -LiteralPath \$candidateExtractRoot\)\)'
    }

    It 'does not execute a candidate domain test before the central runner' {
        $directDomainCall = [regex]::Escape("& (Join-Path `$repoRoot 'scripts/Test-SkillGeneral.ps1')")
        $script:Validator | Should -Not -Match $directDomainCall
        $childRunnerMarker = '$childRunnerText = @' + [char]39
        $entryPoint = $script:Validator.Substring(0, $script:Validator.IndexOf($childRunnerMarker))
        $entryPoint | Should -Not -Match 'Import-Module.*Pester'
    }

    # Scenario: the workflow uses ordinary Core to validate the immutable source snapshot.
    # Purpose: remove the runner's GitHub token from the Core validator process before it launches any child.
    It 'UnitT21_clears_github_tokens_before_launching_the_core_validator_child' {
        $result = Invoke-WorkflowCredentialFixture -Mode 'core'
        $result.guardBeforeChild | Should -BeTrue
        $result.githubToken | Should -BeNullOrEmpty
        $result.ghToken | Should -BeNullOrEmpty
        $result.sentinel | Should -BeExactly 'preserve-me'
    }

    # Scenario: the legacy resolver still needs its explicitly scoped read-only GitHub token.
    # Purpose: keep token isolation limited to ordinary Core while preserving unrelated process environment.
    It 'UnitT22_preserves_legacy_workflow_tokens_and_unrelated_environment' {
        $result = Invoke-WorkflowCredentialFixture -Mode 'legacy'
        $result.guardBeforeChild | Should -BeTrue
        $result.githubToken | Should -BeExactly 'fixture-github-token'
        $result.ghToken | Should -BeExactly 'fixture-gh-token'
        $result.sentinel | Should -BeExactly 'preserve-me'
    }

    # Scenario: a baseline-pinned protected driver evaluates a candidate using either approved Core authority tuple.
    # Purpose: preserve the legacy route until a Core-compatible protected driver is active, without binding a Core checkout revision.
    It 'UnitT23_keeps_baseline_protected_driver_on_legacy_for_approved_Core_candidates' {
        foreach ($candidateCommit in @($script:ExpectedNextAuthorityCommit, $script:ExpectedMergedAuthorityCommit)) {
            $selection = Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedAuthorityCommit -CandidateAuthority $candidateCommit `
                -ExpectedDriverSha ('a' * 40) -ActualDriverSha ('a' * 40) -ReturnSelection
            $selection.mode | Should -BeExactly 'legacy'
            $selection.authorityRevision | Should -BeExactly $candidateCommit
        }
    }

    # Scenario: the protected base has already adopted the exact ea1 Core authority.
    # Purpose: reject a baseline-pinned candidate instead of silently downgrading the protected validation mode.
    It 'UnitT24_rejects_a_baseline_candidate_under_the_protected_core_driver' {
        (Get-FixtureExceptionMessage -Action {
            Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedAuthorityCommit -ExpectedDriverSha ('b' * 40) -ActualDriverSha ('b' * 40)
        }) | Should -Match 'cannot downgrade'
    }

    # Scenario: the protected base claims the ea1 Core pin but lacks its reviewed Pester wrapper.
    # Purpose: fail closed rather than choosing legacy validation when the trusted Core implementation is incomplete.
    It 'UnitT25_rejects_a_protected_core_driver_without_its_trusted_wrapper' {
        (Get-FixtureExceptionMessage -Action {
            Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedNextAuthorityCommit -ExpectedDriverSha ('c' * 40) -ActualDriverSha ('c' * 40) -IncludeCoreWrapper:$false
        }) | Should -Match 'missing the trusted Pester wrapper'
    }

    # Scenario: protected main and immutable candidate both use ea1 with the exact Core wrapper available.
    # Purpose: select ordinary Core only for the fully bound protected tuple.
    It 'UnitT26_selects_core_for_the_exact_protected_ea1_tuple' {
        $mode = Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedNextAuthorityCommit -ExpectedDriverSha ('d' * 40) -ActualDriverSha ('d' * 40)
        $mode | Should -BeExactly 'core'
    }

    # Scenario: a function shadows the application command in protected authority selection.
    # Purpose: prove that the selector fails closed before trusting a substituted Git result.
    It 'UnitT39_rejects_a_shadowed_git_command_in_protected_authority_selection' {
        try {
            function git { return ('d' * 40) }
            (Get-FixtureExceptionMessage -Action {
                Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedNextAuthorityCommit -ExpectedDriverSha ('d' * 40) -ActualDriverSha ('d' * 40)
            }) | Should -Match 'Git command is shadowed in protected authority selection'
        }
        finally {
            Remove-Item Function:\git -ErrorAction SilentlyContinue
        }
    }

    # Scenario: an operator manually starts the canonical workflow on its approved branch.
    # Purpose: retain the baseline workflow_dispatch entry point through the base migration.
    It 'UnitT27_preserves_manual_canonical_validation_dispatch' {
        $script:Workflow | Should -Match '(?m)^  workflow_dispatch:\s*$'
    }

    # Scenario: the selector test uses a fixture application for the driver checkout.
    # Purpose: restore an existing native exit code so the fixture cannot contaminate later Pester cases.
    It 'UnitT28_restores_a_preexisting_native_exit_code_after_selector_fixtures' {
        $prior = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $hadPrior = $null -ne $prior
        $priorValue = if ($hadPrior) { $prior.Value } else { $null }
        try {
            $global:LASTEXITCODE = 239
            $mode = Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedNextAuthorityCommit -ExpectedDriverSha ('e' * 40) -ActualDriverSha ('e' * 40)
            $mode | Should -BeExactly 'core'
            (Get-Variable -Name LASTEXITCODE -Scope Global).Value | Should -Be 239
        }
        finally {
            if ($hadPrior) { Set-Variable -Name LASTEXITCODE -Value $priorValue -Scope Global }
            else { Remove-Variable -Name LASTEXITCODE -Scope Global -Force -ErrorAction SilentlyContinue }
        }
    }

    # Scenario: the selector fixture runs in a process without any prior native command.
    # Purpose: remove the shim's temporary LASTEXITCODE variable when the caller had none.
    It 'UnitT29_removes_the_native_exit_code_variable_when_it_was_previously_unset' {
        $prior = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $hadPrior = $null -ne $prior
        $priorValue = if ($hadPrior) { $prior.Value } else { $null }
        try {
            Remove-Variable -Name LASTEXITCODE -Scope Global -Force -ErrorAction SilentlyContinue
            $mode = Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedNextAuthorityCommit -ExpectedDriverSha ('f' * 40) -ActualDriverSha ('f' * 40)
            $mode | Should -BeExactly 'core'
            (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
        finally {
            if ($hadPrior) { Set-Variable -Name LASTEXITCODE -Value $priorValue -Scope Global }
            else { Remove-Variable -Name LASTEXITCODE -Scope Global -Force -ErrorAction SilentlyContinue }
        }
    }

    # Scenario: the candidate supplies the independently reviewed 053 merged tuple.
    # Purpose: accept only its complete repository, commit, archive digest, and ordered 26-file inventory in Core mode.
    It 'UnitT30_accepts_the_exact_merged_053_tuple_in_core_mode' {
        $verifier = New-AuthorityVerifierModule
        $candidate = New-MergedAuthorityConfig
        $pin = & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $candidate
        $pin.repository | Should -BeExactly 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        $pin.commit | Should -BeExactly $script:ExpectedMergedAuthorityCommit
        $pin.archiveUrl | Should -BeExactly "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedMergedAuthorityCommit)"
        $pin.archiveSha256 | Should -BeExactly $script:ExpectedMergedAuthorityArchiveSha256
        @($pin.files.Keys) | Should -Be @($script:ExpectedMergedAuthorityFiles.Keys)
        @($pin.files.Keys).Count | Should -Be 26
        foreach ($path in $script:ExpectedMergedAuthorityFiles.Keys) {
            $pin.files[$path] | Should -BeExactly $script:ExpectedMergedAuthorityFiles[$path]
        }
    }

    # Scenario: a valid 053 tuple is copied and one authority field is changed at a time.
    # Purpose: prevent mixed pins, altered hashes, reordered or incomplete inventories, and unknown revisions from entering Core.
    It 'UnitT31_rejects_each_forged_or_incomplete_053_tuple_after_a_valid_control' {
        $verifier = New-AuthorityVerifierModule
        $valid = New-MergedAuthorityConfig
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $valid } | Should -Not -Throw

        $mutations = @(
            { param($config) $config.authority.archiveSha256 = '0' * 64 },
            { param($config) $config.authority.files[0].sha256 = '0' * 64 },
            { param($config) [array]::Reverse($config.authority.files) },
            { param($config) $config.authority.files = @($config.authority.files | Select-Object -SkipLast 1) },
            { param($config) $config.authority.commit = '0000000000000000000000000000000000000000'; $config.authority.archiveUrl = "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($config.authority.commit)" }
        )
        foreach ($mutation in $mutations) {
            $forged = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
            & $mutation $forged
            { & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $forged } | Should -Throw
        }
    }

    # Scenario: a caller tries to use the reviewed 053 revision outside the approved Core selector.
    # Purpose: retain legacy-only defaults and require explicit Core opt-in for every non-legacy authority.
    It 'UnitT32_keeps_the_merged_053_tuple_outside_default_legacy_validation' {
        $verifier = New-AuthorityVerifierModule
        $candidate = New-MergedAuthorityConfig
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config -AllowNextAuthority } $candidate } | Should -Not -Throw
        { & $verifier { param($config) Assert-AuthorityConfig -Config $config } $candidate } | Should -Throw
    }

    # Scenario: an ea1 or 053 protected driver validates a candidate pinned to the merged 053 authority.
    # Purpose: select Core and carry the candidate's exact approved revision through the protected selector output.
    It 'UnitT33_selects_053_for_either_supported_protected_core_driver' {
        foreach ($driverCommit in @($script:ExpectedNextAuthorityCommit, $script:ExpectedMergedAuthorityCommit)) {
            $selection = Invoke-WorkflowSelectorFixture -DriverAuthority $driverCommit -CandidateAuthority $script:ExpectedMergedAuthorityCommit `
                -ExpectedDriverSha ('a' * 40) -ActualDriverSha ('a' * 40) -ReturnSelection
            $selection.mode | Should -BeExactly 'core'
            $selection.authorityRevision | Should -BeExactly $script:ExpectedMergedAuthorityCommit
        }
    }

    # Scenario: the 053 driver receives a downgrade, an unapproved candidate, or an unknown driver revision.
    # Purpose: fail closed without widening the workflow into a candidate-controlled or generic revision allowlist.
    It 'UnitT34_rejects_downgrade_and_unknown_authority_revisions' {
        { Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedMergedAuthorityCommit -CandidateAuthority $script:ExpectedAuthorityCommit `
            -ExpectedDriverSha ('b' * 40) -ActualDriverSha ('b' * 40) } | Should -Throw
        { Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedMergedAuthorityCommit -CandidateAuthority ('9' * 40) `
            -ExpectedDriverSha ('c' * 40) -ActualDriverSha ('c' * 40) } | Should -Throw
        { Invoke-WorkflowSelectorFixture -DriverAuthority ('8' * 40) -CandidateAuthority $script:ExpectedMergedAuthorityCommit `
            -ExpectedDriverSha ('d' * 40) -ActualDriverSha ('d' * 40) } | Should -Throw
    }

    # Scenario: the protected selector chooses 053 for an immutable candidate.
    # Purpose: bind the authority checkout and report verifier to the exact same selector output.
    It 'UnitT35_binds_dynamic_core_checkout_and_report_to_one_selected_revision' {
        $selection = Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedNextAuthorityCommit -CandidateAuthority $script:ExpectedMergedAuthorityCommit `
            -ExpectedDriverSha ('e' * 40) -ActualDriverSha ('e' * 40) -ReturnSelection
        $selection.authorityRevision | Should -BeExactly $script:ExpectedMergedAuthorityCommit

        $checkout = [regex]::Match($script:Workflow, '(?ms)^      - name: Checkout candidate-pinned authority for validation tests\r?\n(?<body>.*?)(?=^      - name: |\z)')
        $checkout.Success | Should -BeTrue
        $checkout.Groups['body'].Value | Should -Match '(?m)^          ref: \$\{\{ steps\.authority-mode\.outputs\.authority_revision \}\}\r?$'

        $validateStep = [regex]::Match($script:Workflow, '(?ms)^      - name: Validate exact candidate with the verified runtime\r?\n(?<body>.*?)(?=^      - name: |\z)')
        $validateStep.Success | Should -BeTrue
        $validateStep.Groups['body'].Value | Should -Match '(?m)^          APPROVED_AUTHORITY_REVISION: \$\{\{ steps\.authority-mode\.outputs\.authority_revision \}\}\r?$'
        $validateStep.Groups['body'].Value | Should -Match '\$report\.authority\.revision\s+-cne\s+\$env:APPROVED_AUTHORITY_REVISION'
        $validateStep.Groups['body'].Value | Should -Not -Match '\$report\.authority\.revision\s+-cne\s+''ea1d368ac7b36f838ce4c3af363972c90fa12930'''
    }

    # Scenario: Git checks out a different protected base than the event's declared base SHA.
    # Purpose: refuse the authority selection before trusting driver configuration or candidate pins.
    It 'UnitT36_rejects_a_driver_checkout_that_differs_from_the_exact_event_base' {
        (Get-FixtureExceptionMessage -Action {
            Invoke-WorkflowSelectorFixture -DriverAuthority $script:ExpectedMergedAuthorityCommit -CandidateAuthority $script:ExpectedMergedAuthorityCommit `
                -ExpectedDriverSha ('f' * 40) -ActualDriverSha ('0' * 40) -ReturnSelection
        }) | Should -Match 'exact event base SHA'
    }

    # Scenario: ordinary Run has already passed its legacy-input preflight and carries one exact approved Core pin.
    # Purpose: prove the CLI selector accepts ea1/053 only, while explicit Semantic modes remain outside ordinary dispatch.
    It 'UnitT37_selects_both_approved_Core_pins_and_keeps_explicit_Semantic_modes_separate' {
        $selector = New-CoreRunSelectorModule
        $baseline = [pscustomobject]@{
            repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
            commit = $script:ExpectedAuthorityCommit
        }
        $ea1 = [pscustomobject]@{
            repository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
            commit = $script:ExpectedNextAuthorityCommit
        }
        $merged053 = (New-MergedAuthorityConfig).authority

        foreach ($pin in @($ea1, $merged053)) {
            (& $selector { param($mode, $selectedPin, $legacy) Test-CoreRunSelected -ExecutionMode $mode -candidateAuthority $selectedPin -legacyRunRequested $legacy } 'Run' $pin $false) |
                Should -BeTrue
            (& $selector { param($mode, $selectedPin, $legacy) Test-CoreRunSelected -ExecutionMode $mode -candidateAuthority $selectedPin -legacyRunRequested $legacy } 'Run' $pin $true) |
                Should -BeTrue
            foreach ($mode in @('PrepareSemantic', 'ResumeSemantic')) {
                (& $selector { param($executionMode, $selectedPin) Test-CoreRunSelected -ExecutionMode $executionMode -candidateAuthority $selectedPin -legacyRunRequested $false } $mode $pin) |
                    Should -BeFalse
            }
            $legacyPin = & $selector { param($selectedPin) Get-LegacyAuthorityPin -SelectedPin $selectedPin } $pin
            $legacyPin.commit | Should -BeExactly $script:ExpectedAuthorityCommit
            $legacyPin.archiveSha256 | Should -BeExactly $script:ExpectedAuthorityArchiveSha256
            @($legacyPin.files.Keys) | Should -Be @($script:ExpectedAuthorityFiles.Keys)
        }
        (& $selector { param($selectedPin) Test-CoreRunSelected -ExecutionMode 'Run' -candidateAuthority $selectedPin -legacyRunRequested $false } $baseline) |
            Should -BeFalse
        $guard = New-OrdinaryRunGuardModule
        (Get-FixtureExceptionMessage -Action {
            & $guard { param($selectedPin) Assert-OrdinaryCoreRunRequest -ExecutionMode 'Run' -CandidateAuthority $selectedPin -BoundParameters @{} } $baseline
        }) | Should -Match 'Ordinary Run requires one exact approved Core authority pin'
        { & $selector { param($selectedPin) Get-LegacyAuthorityPin -SelectedPin $selectedPin } ([pscustomobject]@{ repository = $baseline.repository; commit = '8' * 40 }) } |
            Should -Throw
    }

    # Scenario: the protected legacy driver fully validates source stages but retains missing Semantic consent as BLOCKED/10.
    # Purpose: permit only the existing source-check projection without rewriting canonical state or claiming release eligibility.
    It 'UnitT40_accepts_complete_legacy_source_projection_without_masking_canonical_state' {
        $report=New-LegacySourceProjectionFixture
        $before=$report | ConvertTo-Json -Depth 100 -Compress
        Invoke-LegacySourceProjectionFixture -Report $report | Should -BeTrue
        ($report | ConvertTo-Json -Depth 100 -Compress) | Should -BeExactly $before
        $report.state | Should -BeExactly 'BLOCKED'
        $report.exitCode | Should -Be 10
        $report.releaseEligible | Should -BeFalse
        $report.state='PASS';$report.exitCode=0;$report.failure=$null;$report.stages[5].status='not-applicable'
        $report.sourceConformance.canonicalValidation.state='PASS';$report.sourceConformance.canonicalValidation.exitCode=0;$report.sourceConformance.canonicalValidation.stage6Status='not-applicable'
        Invoke-LegacySourceProjectionFixture -Report $report -ExitCode 0 | Should -BeTrue
    }

    # Scenario: report identity, source-stage completion, cleanup, scope or canonical exit disagrees with the protected run.
    # Purpose: fail the source check instead of promoting an unrelated, incomplete or failed report.
    It 'UnitT41_rejects_invalid_legacy_source_projection_and_canonical_failures' {
        $mutations=@(
            {param($r) $r.schemaVersion=2}, {param($r) $r.evidence='unknown'},
            {param($r) $r.candidate.sourceRevision=('9'*40)}, {param($r) $r.candidate.baseRevision=('9'*40)},
            {param($r) $r.authority.runnerSha256=('9'*64)}, {param($r) $r.sourceConformance.sourceRevision=('9'*40)},
            {param($r) $r.sourceConformance.candidateId=('9'*64)}, {param($r) $r.sourceConformance.contentSha256=('9'*64)},
            {param($r) $r.releaseEligible=$true}, {param($r) $r.sourceConformance.releaseEligible=$true},
            {param($r) $r.sourceConformance.scope='release'}, {param($r) $r.sourceConformance.status='failed'},
            {param($r) $r.sourceConformance.failureReasons=@('raw event mismatch')},
            {param($r) $r.stages[3].status='partial'}, {param($r) $r.sourceConformance.checkedStages[3].status='partial'},
            {param($r) $r.stages[4].events[1].exitCode=20}, {param($r) $r.stages[4].events[1].cleanedUp=$false},
            {param($r) $r.stages[4].events[1].candidateId=('9'*64)}, {param($r) $r.stages[5].status='failed'},
            {param($r) $r.stages[6].status='blocked'}, {param($r) $r.failure.message='unrelated failure'},
            {param($r) $r.sourceConformance.canonicalValidation.exitCode=0}
        )
        foreach($mutate in $mutations){$r=New-LegacySourceProjectionFixture;& $mutate $r;{Invoke-LegacySourceProjectionFixture -Report $r}|Should -Throw}
        {Invoke-LegacySourceProjectionFixture -Report (New-LegacySourceProjectionFixture) -ExitCode 20}|Should -Throw
        {Invoke-LegacySourceProjectionFixture -Report (New-LegacySourceProjectionFixture) -ExitCode 0}|Should -Throw
    }

    # Scenario: a source projection asserts passed tests without a matching positive typed Pester inventory and process event.
    # Purpose: reject empty/all-skipped/failed or mismatched test evidence before source-context publication.
    It 'UnitT42_rejects_incomplete_or_mismatched_legacy_pester_projection' {
        $mutations=@(
            {param($r) $r.sourceConformance.pester.total=0}, {param($r) $r.sourceConformance.pester.passed=0},
            {param($r) $r.sourceConformance.pester.failed=1}, {param($r) $r.sourceConformance.pester.skipped=1},
            {param($r) $r.sourceConformance.pester.events=@()}, {param($r) $r.sourceConformance.pester.eventCount=2},
            {param($r) $r.sourceConformance.pester.events[0].eventId='00000000-0000-4000-8000-000000000009'},
            {param($r) $r.sourceConformance.pester.events[0].outputSha256=('9'*64)},
            {param($r) $r.sourceConformance.pester.events[0].testInventoryCount=0},
            {param($r) $r.sourceConformance.pester.events[0].failed=1},
            {param($r) $r.sourceConformance.pester.events[0].total=8}
        )
        foreach($mutate in $mutations){$r=New-LegacySourceProjectionFixture;& $mutate $r;{Invoke-LegacySourceProjectionFixture -Report $r}|Should -Throw}
    }
}
