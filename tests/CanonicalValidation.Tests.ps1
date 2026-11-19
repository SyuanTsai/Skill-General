# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Consumer repository contract' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:CheckPath = Join-Path $script:RepositoryRoot 'scripts/Test-SkillGeneral.ps1'
        $script:Source = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/source.json')
        $script:Gate = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/consumer-gate.json')
        $script:Pin = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/authority-pin.json')
    }

    It 'publishes the snapshot-safe repository check interface' {
        $command = Get-Command -Name $script:CheckPath -CommandType ExternalScript
        @($command.Parameters.Keys) | Should -Contain 'RepositoryRoot'
        @($command.Parameters.Keys) | Should -Contain 'ReadOnlySnapshot'
        $command.Parameters['ReadOnlySnapshot'].ParameterType | Should -Be ([switch])
    }

    It 'declares active Skills exactly as the source inventory' {
        @($script:Gate.activeSkills) | Should -HaveCount @($script:Source.skills).Count
        (@($script:Gate.activeSkills) -join "`n") | Should -BeExactly (@($script:Source.skills) -join "`n")
        [string[]]$ordered = @($script:Gate.activeSkills)
        [Array]::Sort($ordered, [StringComparer]::Ordinal)
        (@($script:Gate.activeSkills) -join "`n") | Should -BeExactly ($ordered -join "`n")
    }

    It 'declares exactly the General and complete Pester checks' {
        @($script:Gate.repositoryChecks) | Should -HaveCount 2
        $general = @($script:Gate.repositoryChecks | Where-Object { [string]$_.kind -ceq 'general' })
        $pester = @($script:Gate.repositoryChecks | Where-Object { [string]$_.kind -ceq 'pester' })
        $general | Should -HaveCount 1
        $general[0].id | Should -BeExactly 'repository-general'
        $general[0].path | Should -BeExactly 'scripts/Test-SkillGeneral.ps1'
        $pester | Should -HaveCount 1
        $pester[0].id | Should -BeExactly 'repository-pester'
        $pester[0].path | Should -BeExactly 'tests'
        foreach ($check in @($script:Gate.repositoryChecks)) {
            Test-Path -LiteralPath (Join-Path $script:RepositoryRoot ([string]$check.path)) | Should -BeTrue
        }
    }

    It 'pins the official authority with an upgrade-compatible immutable commit' {
        [string[]]$actual = @($script:Pin.PSObject.Properties.Name)
        [string[]]$expected = @('commit', 'repository', 'schemaVersion')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
        $script:Pin.schemaVersion | Should -Be 1
        $script:Pin.repository | Should -BeExactly 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
        ([string]$script:Pin.commit -cmatch '^[0-9a-f]{40}$') | Should -BeTrue
    }

    It 'keeps each authority-published template at its reviewed hash' {
        $expected = [ordered]@{
            'scripts/Invoke-PinnedAuthority.ps1' = '2b2941066308b689140bdbd57654b5347f39933e3c91c6097ce4646709a3e76b'
            '.github/workflows/consumer-gate.yml' = 'dffbac5117290e8ca4fd1c1179355a9bae59bcc3496ce3e9413e813f88da19d5'
        }
        $transition = '.github/workflows/consumer-gate-transition.yml'
        if (Test-Path -LiteralPath (Join-Path $script:RepositoryRoot $transition) -PathType Leaf) {
            $expected[$transition] = '6c78b69f413f9878d9dd73ad42b7bbe5b4442b82617649122e8e8c9bc992132f'
        }
        foreach ($entry in $expected.GetEnumerator()) {
            $actualHash = (Get-FileHash -LiteralPath (Join-Path $script:RepositoryRoot $entry.Key) -Algorithm SHA256).Hash.ToLowerInvariant()
            $actualHash | Should -BeExactly $entry.Value
        }
    }
}
