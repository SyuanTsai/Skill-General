# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Canonical Standard v1 validation adapter' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Validate.ps1'
        $script:Validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
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
    It 'runs the next candidate pin through Core and maps explicit legacy work to the baseline tuple' {
        $script:Validator | Should -Match '\$candidateAuthority\.commit -ceq \$script:NextAuthorityCommit -and -not \$legacyRunRequested'
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
        $adapter = & $adapterModule {
            param($executable)
            New-StandardCoreAdapterV2 -PowerShellPath $executable -TrustedToolRoot (Split-Path -Parent $executable) -ActiveSkillIds @('Fixture.Skill')
        } $powerShellExecutable
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
        @($pesterCheck.arguments) | Should -Be @('-NoProfile', '-NonInteractive', '-File', 'scripts/Invoke-CorePester.ps1')
        { & $adapterModule { param($executable, $root) New-StandardCoreAdapterV2 -PowerShellPath $executable -TrustedToolRoot $root -ActiveSkillIds @('Fixture.Skill') } $script:ValidatorPath (Split-Path -Parent $powerShellExecutable) } | Should -Throw
    }

    It 'keeps Core Pester output typed and preserves real test counts' {
        $wrapperPath = Join-Path $script:RepositoryRoot 'scripts/Invoke-CorePester.ps1'
        $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($wrapper, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $wrapper | Should -Match 'Invoke-Pester -Path \$testRoot -Output None -PassThru'
        $wrapper | Should -Match "report = 'standard-core-pester-result-v1'"
        $wrapper | Should -Match '\$failed = \[int\]\$result\.FailedCount'
        $wrapper | Should -Match '\$skipped = \[int\]\$result\.SkippedCount'
        $wrapper | Should -Match '\$ErrorActionPreference = ''Continue'''
        $wrapper | Should -Match '\(\$passed \+ \$skipped\) -ne \$total'
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

    It 'dispatches the selected ordinary Run through Core v2 without semantic or acquisition inputs' {
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
        $script:Validator | Should -Match '(?s)\$coreRunSelected = \$ExecutionMode -eq ''Run'' -and.*?\-not \$legacyRunRequested'
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
        $script:Validator | Should -Match '\$result = Invoke-Pester -Path \$testRoot -Output None -PassThru 3>\$null 6>\$null'
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
