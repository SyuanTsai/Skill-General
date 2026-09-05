# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Skill-General repository contract' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Test-SkillGeneral.ps1'
        $script:GitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
    }

    BeforeEach {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'catalog') -Destination $fixtureRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'config') -Destination $fixtureRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'skills') -Destination $fixtureRoot -Recurse
        & $script:GitPath -C $fixtureRoot init --quiet
        & $script:GitPath -C $fixtureRoot add -- catalog/source.json skills
        if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the repository contract fixture.' }
    }

    It 'accepts the current schema v2 inventory and canonical Skill packages' {
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'produces deterministic per-Skill content hashes' {
        $first = & $script:ValidatorPath -RepositoryRoot $fixtureRoot | Select-Object -Last 1 | ConvertFrom-Json
        $second = & $script:ValidatorPath -RepositoryRoot $fixtureRoot | Select-Object -Last 1 | ConvertFrom-Json

        @($first.skills.skillId) | Should -Be @($second.skills.skillId)
        @($first.skills.contentSha256) | Should -Be @($second.skills.contentSha256)
        @($first.skills | Where-Object { $_.contentSha256 -notmatch '^[0-9a-f]{64}$' }).Count | Should -Be 0
    }

    It 'rejects an unlisted Skill directory' {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'skills/unlisted-skill') | Out-Null

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*inventory does not exactly match*'
    }

    It 'rejects non-package content at the canonical source root' {
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'skills/ignored.ps1') -Value 'Write-Output unsafe'

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*non-package or reparse entry*'
    }

    It 'rejects coexistence with the legacy Skill source root' {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot '.agents/skills') -Force | Out-Null

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*Legacy .agents/skills source root*'
    }

    It 'rejects an ambiguous or noncanonical source inventory shape' {
        $sourcePath = Join-Path $fixtureRoot 'catalog/source.json'
        $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
        $source.schemaVersion = 1
        $source | Add-Member -NotePropertyName profiles -NotePropertyValue @()
        $source | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath -Encoding utf8NoBOM

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*invalid property set*'
    }

    It 'rejects duplicate JSON properties before object materialization' {
        $sourcePath = Join-Path $fixtureRoot 'catalog/source.json'
        $text = Get-Content -LiteralPath $sourcePath -Raw
        $text = $text -replace '"sourceId": "general",', '"sourceId": "general", "sourceId": "other",'
        Set-Content -LiteralPath $sourcePath -Value $text -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*duplicate JSON property*'
    }

    It 'rejects a repository-local security policy fork' {
        $adapterPath = Join-Path $fixtureRoot 'config/standard-v1.json'
        $adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
        $adapter | Add-Member -NotePropertyName security -NotePropertyValue ([pscustomobject]@{
            blockSeverities = @('critical', 'high', 'medium')
        })
        $adapter | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $adapterPath -Encoding utf8NoBOM

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*config/standard-v1.json has an invalid property set*'
    }

    It 'rejects unsorted source inventory entries' {
        $sourcePath = Join-Path $fixtureRoot 'catalog/source.json'
        $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
        [array]::Reverse($source.skills)
        $source | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath -Encoding utf8NoBOM

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*ordinal ascending order*'
    }

    It 'rejects untracked package content from the integrity inventory' {
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'skills/plan-production-change/untracked.txt') -Value 'not indexed'

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*filesystem inventory does not match the Git index*'
    }

    It 'rejects unstaged package bytes that are not bound to the Git index' {
        $skillPath = Join-Path $fixtureRoot 'skills/plan-production-change/SKILL.md'
        Add-Content -LiteralPath $skillPath -Value "`nAdditional valid body text."

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*working-tree content is not bound*'
    }

    It 'rejects malformed OpenAI metadata lexical style' {
        $metadataPath = Join-Path $fixtureRoot 'skills/plan-production-change/agents/openai.yaml'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        $metadata = $metadata -replace 'display_name: "Plan Production Change"', '"display_name": "Plan Production Change"'
        Set-Content -LiteralPath $metadataPath -Value $metadata -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*quoted mapping key*'
    }

    It 'rejects an implicitly typed YAML description instead of accepting it as text' {
        $skillPath = Join-Path $fixtureRoot 'skills/plan-production-change/SKILL.md'
        $skill = Get-Content -LiteralPath $skillPath -Raw
        $skill = $skill -replace '(?m)^description:.*$', 'description: true'
        Set-Content -LiteralPath $skillPath -Value $skill -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must be a YAML string scalar*'
    }

    It 'rejects an OpenAI metadata prompt bound to another Skill identity' {
        $metadataPath = Join-Path $fixtureRoot 'skills/plan-production-change/agents/openai.yaml'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        $metadata = $metadata -replace '\$plan-production-change', '$review-agent-skills'
        Set-Content -LiteralPath $metadataPath -Value $metadata -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must reference exact token*'
    }

    It 'rejects a default prompt whose apparent Skill token has a suffix' {
        $metadataPath = Join-Path $fixtureRoot 'skills/plan-production-change/agents/openai.yaml'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        $metadata = $metadata -replace '\$plan-production-change', '$plan-production-changeX'
        Set-Content -LiteralPath $metadataPath -Value $metadata -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must reference exact token*'
    }

    It 'rejects undeclared OpenAI policy keys' {
        $metadataPath = Join-Path $fixtureRoot 'skills/manage-notion-ai-memory/agents/openai.yaml'
        Add-Content -LiteralPath $metadataPath -Value '  unsafe_override: true'

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*policy*allow_implicit_invocation*'
    }

    It 'rejects comments outside the SPDX license header' {
        $metadataPath = Join-Path $fixtureRoot 'skills/plan-production-change/agents/openai.yaml'
        Add-Content -LiteralPath $metadataPath -Value '# unsupported comment'

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*unsupported or malformed syntax*'
    }

    It 'validates the final dependency before a following policy section' {
        $metadataPath = Join-Path $fixtureRoot 'skills/manage-notion-ai-memory/agents/openai.yaml'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        $metadata = $metadata -replace '(?m)^      value:.*\r?\n', ''
        Set-Content -LiteralPath $metadataPath -Value $metadata -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*dependency*non-empty value*'
    }
}
