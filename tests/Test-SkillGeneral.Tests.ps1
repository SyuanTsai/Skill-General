# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Skill-General repository contract' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Test-SkillGeneral.ps1'
    }

    BeforeEach {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'catalog') -Destination $fixtureRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot '.agents') -Destination $fixtureRoot -Recurse
    }

    It 'accepts the current self-consistent catalog and Skill inventory' {
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    # Scenario: A stable Skill ID is retired after consumers migrate to an official replacement outside this catalog.
    # Purpose: Preserve lifecycle history without requiring retired implementation files or active profile membership.
    It 'InterT15_accepts_a_removed_Skill_tombstone_without_source_files_or_profile_membership' {
        $catalogPath = Join-Path $fixtureRoot 'catalog/skills-catalog.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20
        $removedSkill = @($catalog.skills | Where-Object { $_.id -eq 'review-agent-skills' })[0]
        $skillQuality = @($catalog.profiles | Where-Object { $_.id -eq 'skill-quality' })[0]
        $removedSkill.profiles = @()
        $removedSkill.lifecycle.status = 'removed'
        $skillQuality.includes = @()
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM
        Remove-Item -LiteralPath (Join-Path $fixtureRoot '.agents/skills/review-agent-skills') -Recurse -Force

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    # Scenario: The retired custom FELO Skill is inspected in the publishable Repository state.
    # Purpose: Prevent its wrapper, retry layer, tests, or profile route from being accidentally republished.
    It 'InterT20_keeps_only_the_removed_FELO_tombstone_and_no_custom_implementation' {
        $catalog = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/skills-catalog.json') -Raw |
            ConvertFrom-Json -Depth 20
        $removedSkill = @($catalog.skills | Where-Object { $_.id -eq 'search-with-felo' })
        $externalResearch = @($catalog.profiles | Where-Object { $_.id -eq 'external-research' })

        $removedSkill.Count | Should -Be 1
        $removedSkill[0].lifecycle.status | Should -Be 'removed'
        @($removedSkill[0].lifecycle.aliases).Count | Should -Be 0
        @($removedSkill[0].lifecycle.PSObject.Properties.Name | Where-Object { $_ -eq 'replacementId' }).Count | Should -Be 0
        @($removedSkill[0].profiles).Count | Should -Be 0
        $externalResearch.Count | Should -Be 1
        @($externalResearch[0].includes | Where-Object { $_ -eq 'search-with-felo' }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.agents/skills/search-with-felo') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'tests/search-with-felo.Tests.ps1') | Should -Be $false
    }

    It 'rejects an unlisted Skill directory' {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot '.agents/skills/unlisted-skill') | Out-Null

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*inventory does not match*'
    }

    It 'rejects a noncanonical or escaping Skill path' {
        $catalogPath = Join-Path $fixtureRoot 'catalog/skills-catalog.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20
        $catalog.skills[0].source.path = '.agents/skills/../../plan-production-change'
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*path must be*'
    }

    It 'rejects mismatched profile and Skill membership metadata' {
        $catalogPath = Join-Path $fixtureRoot 'catalog/skills-catalog.json'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20
        $catalog.profiles[0].includes = @('plan-production-change')
        $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*Profile membership mismatch*'
    }
}
