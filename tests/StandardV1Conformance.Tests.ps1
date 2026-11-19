# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Skill-General consumer layout conformance' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    }

    It 'contains only repository-owned checks and the authority bootstrap under scripts' {
        [string[]]$actual = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'scripts') -File -Force |
                ForEach-Object Name)
        [string[]]$expected = @('Invoke-PinnedAuthority.ps1', 'Sync-SharedReferences.ps1', 'Test-SkillGeneral.ps1')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'contains only consumer configuration files' {
        [string[]]$actual = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'config') -File -Force |
                ForEach-Object Name)
        [string[]]$expected = @('authority-pin.json', 'consumer-gate.json')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'keeps every REUSE annotation matched by at least one present file' {
        $annotations = @(Read-ConsumerReuseAnnotations -LiteralPath (Join-Path $script:RepositoryRoot 'REUSE.toml'))
        $files = @(Get-ConsumerRepositoryFiles -RepositoryRoot $script:RepositoryRoot | ForEach-Object RelativePath)
        foreach ($annotation in $annotations) {
            $pattern = [Management.Automation.WildcardPattern]::new(
                [string]$annotation.path,
                [Management.Automation.WildcardOptions]::CultureInvariant
            )
            @($files | Where-Object { $pattern.IsMatch($_) }).Count | Should -BeGreaterThan 0
        }
    }

    It 'covers each copied template and consumer JSON with one exact annotation' {
        $annotations = @(Read-ConsumerReuseAnnotations -LiteralPath (Join-Path $script:RepositoryRoot 'REUSE.toml'))
        $protected = @(
            'config/authority-pin.json'
            'config/consumer-gate.json'
            'scripts/Invoke-PinnedAuthority.ps1'
            '.github/workflows/consumer-gate.yml'
        )
        $transition = '.github/workflows/consumer-gate-transition.yml'
        if (Test-Path -LiteralPath (Join-Path $script:RepositoryRoot $transition) -PathType Leaf) { $protected += $transition }
        foreach ($path in $protected) {
            $matches = @($annotations | Where-Object {
                    [Management.Automation.WildcardPattern]::new(
                        [string]$_.path,
                        [Management.Automation.WildcardOptions]::CultureInvariant
                    ).IsMatch($path)
                })
            $matches | Should -HaveCount 1
            $matches[0].precedence | Should -BeExactly 'aggregate'
            $matches[0].'SPDX-FileCopyrightText' | Should -BeExactly '2026 SyuanTsai'
            $matches[0].'SPDX-License-Identifier' | Should -BeExactly 'Apache-2.0'
        }
    }

    It 'rejects a malformed REUSE annotation property set' {
        $path = Join-Path $TestDrive 'REUSE.toml'
        $source = Get-Content -Raw -LiteralPath (Join-Path $script:RepositoryRoot 'REUSE.toml')
        $mutated = [regex]::Replace($source, '(?m)^precedence = "aggregate"\r?\n', '', 1)
        $mutated | Should -Not -BeExactly $source
        [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
        { Read-ConsumerReuseAnnotations -LiteralPath $path } | Should -Throw '*exactly the four required keys*'
    }
}
