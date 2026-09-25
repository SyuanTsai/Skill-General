# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Canonical Standard v1 validation adapter' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:Validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $script:Adapter = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'config/standard-v1.json') -Raw |
            ConvertFrom-Json -Depth 20
        $script:ExpectedAuthorityCommit = 'e0e2b5047f0dee61419cdd1e3f8e4f2c3f7e5c33'
        $script:ExpectedAuthorityArchiveSha256 = '7331677d2403ec74283b89bbc192cd7c1311d8722687d11bd1a3573658f717a1'
        $script:ExpectedAuthorityFiles = [ordered]@{
            'docs/standards/README.md' = '5e1ddd737d26a5ec1ff1ebd08e158376ddaf1ea21008bb987fc7f51376923f7c'
            'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
            'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
            'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
            'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
            'docs/standards/schemas/validation-security-gate-v1.schema.json' = '32aee32858cdb0f8fa7b01462af05ad2300cb247cd2e3ca769fa36ed1ac205a9'
            'docs/standards/skill-repository-review-matrix.md' = '315204afe428bb51cab5e815b2c40f6d0cbd55c81a3532ad59b686ae5e4c166c'
            'docs/standards/skill-repository-standard.md' = 'da48b1c29000bfc2c80a8f1d5068034b61c63a0c013f270a59bb6ff674415e4e'
            'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
            'docs/standards/validation-security-gate.json' = '2d4ac30449981083d3f3eab850789e7115684f9dfecad48234bc91ffb678e674'
            'docs/standards/validation-toolchain.json' = '5925dcb1aea1e545b9787a29825e7a0cc03a04c777cd68ab44c9bdd7482ff579'
            'scripts/Invoke-StandardAuthorityGate.ps1' = '2ba65c6fcc91b34400044e58398096f242c86302a5a307e6581917bee30decef'
            'scripts/Resolve-PythonWheelClosure.py' = '7fa1511a3e3ba257c6d9e37f929f68e5684184a3a2756a3f9e765ccc6e69d208'
            'scripts/Resolve-StandardValidationTool.ps1' = 'b1b02443e1b752c415634aae4f9ca4770dc7850545f53102267b0645f6dc0bca'
            'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '11aa88fc25716d748bd4f514f1a44f02390ad1745dd5a5c5beee07f642fd5639'
            'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '5482b69c75613a8025be267b5f52b4c47839f8d5a268db9de27414dfd7303121'
            'docs/standards/standard-validation-contract-v1.json' = 'b68849e986153732c65b4b02a1431f22d2f985781fe5c6299d18d97cd188b57d'
            'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
            'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
            'scripts/Invoke-StandardValidation.ps1' = 'c7078b18a8bea240be4710aa6c0080b22bda7756ee120bfa705ef83c3489dbd1'
            'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '109091979d0a47e2035d3d8b20963fcdb85680e5da737bf1f27121608115d430'
            'scripts/StandardSemanticBridge.psm1' = 'daf90f703898cc56fc3310e1eec462bafa6552edcac0de4f08a3cd4b9f63a429'
            'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
            'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
            'scripts/Validate-UpstreamAdapter.ps1' = '3b6e6474690b1ae9f9486544b68f50ca29b96f5dbe6aa8d6c6cd8570afad500b'
        }
    }

    It 'pins the exact merged P02 authority snapshot without local deviation policy' {
        @($script:Adapter.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'standardVersion', 'authority')
        $script:Adapter.authority.commit | Should -Be $script:ExpectedAuthorityCommit
        $script:Adapter.authority.archiveUrl | Should -Be "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:ExpectedAuthorityCommit)"
        $script:Adapter.authority.archiveSha256 | Should -Be $script:ExpectedAuthorityArchiveSha256
        $script:Validator | Should -Match 'https://codeload\.github\.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/'
        @($script:Adapter.authority.files).Count | Should -Be $script:ExpectedAuthorityFiles.Count
        foreach ($file in @($script:Adapter.authority.files)) {
            $script:ExpectedAuthorityFiles.Contains($file.path) | Should -BeTrue
            $file.sha256 | Should -Be $script:ExpectedAuthorityFiles[$file.path]
        }
        $script:Adapter.PSObject.Properties.Name | Should -Not -Contain 'deviations'
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
        $script:Validator | Should -Match '\$result = Invoke-Pester -Path \$testRoot -Output None -PassThru 6>\$null'
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
}
