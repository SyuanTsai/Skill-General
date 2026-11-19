# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Consumer gate and source inventory binding' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

        function Assert-ConsumerGateSourceBinding {
            param(
                [Parameter(Mandatory)] $Gate,
                [Parameter(Mandatory)] $Source,
                [Parameter(Mandatory)][string] $Root
            )
            if ([string]$Gate.sourceRepository -cne [string]$Source.repository) {
                throw 'Consumer source repository identity differs from source metadata.'
            }
            if ((@($Gate.activeSkills) -join "`n") -cne (@($Source.skills) -join "`n")) {
                throw 'Consumer active Skills differ from source metadata.'
            }
            $expected = @(
                [pscustomobject]@{ id = 'repository-general'; kind = 'general'; path = 'scripts/Test-SkillGeneral.ps1' }
                [pscustomobject]@{ id = 'repository-pester'; kind = 'pester'; path = 'tests' }
            )
            if (@($Gate.repositoryChecks).Count -ne $expected.Count) { throw 'Consumer repository check count is invalid.' }
            for ($index = 0; $index -lt $expected.Count; $index++) {
                foreach ($name in @('id', 'kind', 'path')) {
                    if ([string]$Gate.repositoryChecks[$index].$name -cne [string]$expected[$index].$name) {
                        throw 'Consumer repository check identity is invalid.'
                    }
                }
                if (-not (Test-Path -LiteralPath (Join-Path $Root ([string]$expected[$index].path)))) {
                    throw 'Consumer repository check path is missing.'
                }
            }
        }
    }

    It 'accepts the exact source and check binding' {
        $gate = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/consumer-gate.json')
        $source = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/source.json')
        { Assert-ConsumerGateSourceBinding -Gate $gate -Source $source -Root $script:RepositoryRoot } | Should -Not -Throw
    }

    It 'rejects an active Skill order change case-sensitively' {
        $gate = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/consumer-gate.json')
        $source = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/source.json')
        $gate.activeSkills = @($gate.activeSkills)
        $first = $gate.activeSkills[0]
        $gate.activeSkills[0] = $gate.activeSkills[1]
        $gate.activeSkills[1] = $first
        { Assert-ConsumerGateSourceBinding -Gate $gate -Source $source -Root $script:RepositoryRoot } |
            Should -Throw '*active Skills differ*'
    }

    It 'rejects a missing complete-suite check' {
        $gate = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/consumer-gate.json')
        $source = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/source.json')
        $gate.repositoryChecks = @($gate.repositoryChecks | Select-Object -First 1)
        { Assert-ConsumerGateSourceBinding -Gate $gate -Source $source -Root $script:RepositoryRoot } |
            Should -Throw '*check count is invalid*'
    }
}
