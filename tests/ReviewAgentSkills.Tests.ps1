Describe 'Review Agent Skills package contract' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $skillRoot = Join-Path $repoRoot '.agents/skills/review-agent-skills'
        $catalogPath = Join-Path $repoRoot 'catalog/skills-catalog.json'
    }

    # Scenario: A consumer opts into the Skill quality-review capability.
    # Purpose: Keep the stable Skill ID, source path, and profile membership discoverable through the catalog.
    It 'UnitT10_PublishesTheReviewerThroughAnOptInSkillQualityProfile' {
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20
        $skill = @($catalog.skills | Where-Object { $_.id -eq 'review-agent-skills' })
        $profile = @($catalog.profiles | Where-Object { $_.id -eq 'skill-quality' })

        $skill.Count | Should -Be 1
        $skill[0].source.sourceId | Should -Be 'general'
        $skill[0].source.path | Should -Be '.agents/skills/review-agent-skills'
        @($skill[0].profiles) | Should -Contain 'skill-quality'
        $profile.Count | Should -Be 1
        $profile[0].default | Should -Be $false
        @($profile[0].includes) | Should -Contain 'review-agent-skills'
    }

    # Scenario: The reviewer is selected for an Agent Skill review.
    # Purpose: Ensure its entrypoint routes optional detail through valid one-level references instead of loading the full methodology eagerly.
    It 'UnitT20_ProvidesResolvableProgressiveDisclosureResources' {
        $skillPath = Join-Path $skillRoot 'SKILL.md'
        Test-Path -LiteralPath $skillPath -PathType Leaf | Should -Be $true
        $skillText = Get-Content -LiteralPath $skillPath -Raw
        $links = @(
            [regex]::Matches($skillText, '\[[^\]]+\]\((?<path>references/[a-z0-9-]+\.md)\)') |
                ForEach-Object { $_.Groups['path'].Value } |
                Sort-Object -Unique
        )

        $links | Should -Contain 'references/review-methodology.md'
        $links | Should -Contain 'references/forward-testing.md'
        foreach ($link in $links) {
            Test-Path -LiteralPath (Join-Path $skillRoot ($link -replace '/', [IO.Path]::DirectorySeparatorChar)) -PathType Leaf |
                Should -Be $true
        }
    }

    # Scenario: A reviewer reports an actionable defect or a clean result.
    # Purpose: Preserve evidence requirements, stable severity semantics, and the rule that review output prioritizes findings over summaries.
    It 'UnitT30_DefinesEvidenceBackedFindingsAndStableSeverity' {
        $methodologyPath = Join-Path $skillRoot 'references/review-methodology.md'
        $methodology = Get-Content -LiteralPath $methodologyPath -Raw

        foreach ($severity in @('Critical', 'High', 'Medium', 'Low')) {
            $methodology | Should -Match ([regex]::Escape($severity))
        }
        $methodology | Should -Match 'file.*line|line.*file'
        $methodology | Should -Match 'evidence'
        $methodology | Should -Match 'no findings'
    }

    # Scenario: A repository offers deterministic validators but still needs semantic judgment.
    # Purpose: Prevent syntax tools from being treated as sufficient evidence for routing, scope, safety, or instruction quality.
    It 'UnitT40_SeparatesDeterministicChecksFromSemanticReview' {
        $methodology = Get-Content -LiteralPath (Join-Path $skillRoot 'references/review-methodology.md') -Raw

        $methodology | Should -Match 'Deterministic'
        $methodology | Should -Match 'Semantic'
        $methodology | Should -Match 'skill-validator'
        $methodology | Should -Match 'skill-tools'
        $methodology | Should -Match 'does not prove|do not prove|not prove'
    }

    # Scenario: Codex displays or implicitly selects the Skill for a matching review request.
    # Purpose: Keep UI metadata aligned with the stable ID without disabling normal discovery.
    It 'UnitT50_ProvidesConsistentOpenAiMetadata' {
        $metadataPath = Join-Path $skillRoot 'agents/openai.yaml'
        Test-Path -LiteralPath $metadataPath -PathType Leaf | Should -Be $true
        $metadata = Get-Content -LiteralPath $metadataPath -Raw

        $metadata | Should -Match 'display_name: "Review Agent Skills"'
        $metadata | Should -Match '\$review-agent-skills'
        $metadata | Should -Not -Match 'allow_implicit_invocation: false'
    }

    # Scenario: A reviewer needs to understand expected output or encounters unavailable evidence.
    # Purpose: Keep concrete usage and failure handling visible in the concise Skill entrypoint.
    It 'UnitT60_ProvidesConcreteUsageAndErrorHandling' {
        $skillText = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw

        $skillText | Should -Match '(?m)^## Example\s*$'
        $skillText | Should -Match '(?m)^## Error handling\s*$'
        $skillText | Should -Match '(?s)```text.*File:.*Evidence:.*Impact:.*Correction:.*```'
        $skillText | Should -Match 'residual risk'
        $skillText | Should -Match 'stop and ask'
    }
}
