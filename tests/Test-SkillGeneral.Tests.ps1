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
