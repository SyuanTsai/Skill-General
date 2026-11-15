# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Skill-General repository contract' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:ValidatorPath = Join-Path $script:RepositoryRoot 'scripts/Test-SkillGeneral.ps1'
        $script:GitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
        $tokens = $null
        $parseErrors = $null
        $script:ValidatorAst = [Management.Automation.Language.Parser]::ParseFile($script:ValidatorPath, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -ne 0) { throw 'Could not parse the Skill-General validator.' }
        $script:ValidatorConstants = @{}
        foreach ($constantName in @(
            'MarkdownReferenceExtensions',
            'ProgramReferenceExtensions',
            'OtherTextReferenceExtensions',
            'BinaryReferenceExtensions',
            'JsonSchemaReservedKeys',
            'UnscannedFenceLanguages',
            'VariableScopePrefixes',
            'SkillInvocationTokenPattern'
        )) {
            $leftText = '$script:' + $constantName
            $assignments = @($script:ValidatorAst.FindAll({ param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq $leftText
            }, $true))
            if ($assignments.Count -ne 1) { throw "Expected one validator assignment for $leftText." }
            $script:ValidatorConstants[$constantName] = & ([scriptblock]::Create($assignments[0].Right.Extent.Text))
        }
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

    It 'keeps Datadog investigation restricted to a verified work environment' {
        $skillText = Get-Content -Raw (Join-Path $script:RepositoryRoot 'skills/investigate-datadog-logs/SKILL.md')
        $skillText | Should -Match 'applies only to a work environment'
        $skillText | Should -Match 'selected site belongs to that environment'
        $skillText | Should -Match 'private environment or if environment signals conflict'
        $skillText | Should -Match 'connection method configured for the work environment'
        $skillText | Should -Match 'configuration explicitly permits Browser access'
        $skillText | Should -Match "fresh check confirms that the Browser session's site belongs to that same environment"
        $skillText | Should -Match 'does not waive either check'
        $skillText | Should -Match 'stop and report the connector limitation or missing authorization without switching connection methods'
        $skillText | Should -Match 'opaque non-widget short link or session-only UI state'
        $opaqueBranch = [regex]::Match($skillText, '(?m)^- For an opaque non-widget[^\r\n]+').Value
        $opaqueBranch | Should -Match 'try no invented translation\. Follow \[Fallback and Report\]\(#fallback-and-report\)'
        $opaqueBranch | Should -Not -Match 'Browser|fresh check|Otherwise stop'
        $fallback = [regex]::Match($skillText, '(?s)## Fallback and Report\s+(?<body>.*)\z').Groups['body'].Value
        $fallback | Should -Match 'configuration explicitly permits Browser access'
        $fallback | Should -Match "fresh check confirms that the Browser session's site belongs to that same environment"
        $fallback | Should -Match 'When either check cannot be completed, stop and report the connector limitation or missing authorization without switching connection methods'
        $fallback | Should -Match 'When both checks pass, state the connector limitation before using the authorized Browser session and preserve the original scope'
        foreach ($singleRule in @(
            'configuration explicitly permits Browser access',
            "fresh check confirms that the Browser session's site belongs to that same environment",
            'does not waive either check',
            'When either check cannot be completed, stop and report the connector limitation or missing authorization without switching connection methods'
        )) {
            ([regex]::Matches($skillText, [regex]::Escape($singleRule))).Count | Should -Be 1
        }
        $skillText | Should -Not -Match 'Fall back to a Browser only if the connector'
        $skillText | Should -Not -Match '(?i)https?://[^\s)`]+|[a-z0-9-]+\.atlassian\.net'
    }

    It 'accepts an immutable source snapshot without Git metadata' {
        $snapshotRoot = Join-Path $TestDrive "snapshot-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $snapshotRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'catalog') -Destination $snapshotRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'skills') -Destination $snapshotRoot -Recurse

        { & $script:ValidatorPath -RepositoryRoot $snapshotRoot -ReadOnlySnapshot } | Should -Not -Throw
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

    It 'keeps authority and security policy outside the domain inventory diagnostic' {
        $validator = Get-Content -LiteralPath $script:ValidatorPath -Raw
        $validator | Should -Not -Match 'standard-v1\.json'
        $validator | Should -Not -Match 'deviations'
        $validator | Should -Not -Match 'security\.blockSeverities|Get-ValidationSecurityAction'
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

    It 'accepts the allowed optional license frontmatter field' {
        $skillPath = Join-Path $fixtureRoot 'skills/plan-production-change/SKILL.md'
        $skill = Get-Content -LiteralPath $skillPath -Raw
        $lines = [Collections.Generic.List[string]]::new()
        $lines.AddRange([string[]]($skill.Replace("`r`n", "`n").Split("`n")))
        $descriptionIndex = 0
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index].StartsWith('description:', [StringComparison]::Ordinal)) {
                $descriptionIndex = $index
                break
            }
        }
        $lines.Insert($descriptionIndex + 1, 'license: Apache-2.0')
        $skill = $lines -join "`n"
        Set-Content -LiteralPath $skillPath -Value $skill -Encoding utf8NoBOM -NoNewline
        & $script:GitPath -C $fixtureRoot add -- skills/plan-production-change/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the optional license fixture.' }

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    # Scenario: a SKILL.md description opens with a host restriction.
    # Purpose: Standard section 1 forbids platform-limited declarations at the start of a description.
    It 'rejects a description that begins with a platform-restricted declaration: <Prefix>' -ForEach @(
        @{ Prefix = 'Windows-only Skill. ' }
        @{ Prefix = 'Linux-only Skill. ' }
        @{ Prefix = 'macOS only. ' }
        @{ Prefix = 'Only on Windows. ' }
        @{ Prefix = 'Supported on Windows only. ' }
        @{ Prefix = 'Requires Windows. ' }
        @{ Prefix = 'Windows hosts only. Test. ' }
        @{ Prefix = 'Only Windows is supported. Test. ' }
        @{ Prefix = 'Linux only. ' }
        @{ Prefix = 'Only Windows hosts are supported. ' }
        @{ Prefix = 'Supported only on Windows. ' }
        @{ Prefix = 'For Windows hosts only. ' }
        @{ Prefix = 'Linux hosts only. ' }
        @{ Prefix = 'Only macOS is supported. ' }
        @{ Prefix = 'Only Unix hosts are supported. ' }
        @{ Prefix = 'Supported only on WSL. ' }
        @{ Prefix = 'For OS X hosts only. ' }
        @{ Prefix = 'Requires a Windows host. ' }
        @{ Prefix = 'Requires Linux to run. ' }
        @{ Prefix = 'Requires an OS X execution host. ' }
    ) {
        $skillPath = Join-Path $fixtureRoot 'skills/plan-production-change/SKILL.md'
        $skill = Get-Content -LiteralPath $skillPath -Raw
        $skill = $skill -replace '(?m)^description: ', ('description: ' + $Prefix)
        Set-Content -LiteralPath $skillPath -Value $skill -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must not begin with a platform-restricted declaration*'
    }

    # Scenario: a description mentions platform-specific subject matter without limiting the host.
    # Purpose: the restriction check must not reject legitimate domain wording.
    It 'accepts a description that names a platform without restricting the host: <Prefix>' -ForEach @(
        @{ Prefix = 'Windows Event Log and Linux service changes are in scope. ' }
        @{ Prefix = 'Requires Windows Event Log access from a remote source. ' }
        @{ Prefix = 'Requires a Linux kernel crash dump to analyze offline. ' }
    ) {
        $skillPath = Join-Path $fixtureRoot 'skills/plan-production-change/SKILL.md'
        $skill = Get-Content -LiteralPath $skillPath -Raw
        $skill = $skill -replace '(?m)^description: ', ('description: ' + $Prefix)
        Set-Content -LiteralPath $skillPath -Value $skill -Encoding utf8NoBOM -NoNewline
        & $script:GitPath -C $fixtureRoot add -- skills/plan-production-change/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the platform-neutral description fixture.' }

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'locks the fence, reference, JSON, and invocation constants to the reviewed contract' {
        (@($script:ValidatorConstants['UnscannedFenceLanguages']) -join "`n") | Should -BeExactly (@(
            'powershell', 'pwsh', 'ps1', 'bash', 'sh', 'zsh', 'shell', 'python',
            'py', 'sql', 'csharp', 'cs', 'javascript', 'js', 'typescript', 'ts'
        ) -join "`n")
        (@($script:ValidatorConstants['MarkdownReferenceExtensions']) -join "`n") | Should -BeExactly (@('.md', '.markdown') -join "`n")
        (@($script:ValidatorConstants['ProgramReferenceExtensions']) -join "`n") | Should -BeExactly (@('.ps1', '.psm1', '.psd1', '.py', '.sh') -join "`n")
        (@($script:ValidatorConstants['OtherTextReferenceExtensions']) -join "`n") | Should -BeExactly (@(
            '.txt', '.rst', '.adoc', '.json', '.yaml', '.yml', '.toml', '.xml',
            '.csv', '.html', '.htm', '.svg'
        ) -join "`n")
        (@($script:ValidatorConstants['BinaryReferenceExtensions']) -join "`n") | Should -BeExactly (@('.pdf', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico') -join "`n")
        (@($script:ValidatorConstants['JsonSchemaReservedKeys']) -join "`n") | Should -BeExactly (@(
            '$schema', '$id', '$ref', '$defs', '$comment', '$anchor', '$vocabulary'
        ) -join "`n")
        (@($script:ValidatorConstants['VariableScopePrefixes']) -join "`n") | Should -BeExactly (@(
            'env', 'script', 'global', 'local', 'private', 'using', 'variable', 'function', 'alias'
        ) -join "`n")
        ([string]$script:ValidatorConstants['SkillInvocationTokenPattern']) |
            Should -BeExactly '(?<![A-Za-z0-9_$\x5C])\$[a-z0-9]+(?:-[a-z0-9]+)*(?![A-Za-z0-9_]|-[a-z0-9])'
    }

    It 'enforces the reviewed invocation-token grammar boundaries' {
        $pattern = [regex]::new(
            [string]$script:ValidatorConstants['SkillInvocationTokenPattern'],
            [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        foreach ($case in @(
            @{ Text = 'Use $pdf.'; Match = '$pdf' }
            @{ Text = 'Use `$visualize`.'; Match = '$visualize' }
            @{ Text = 'Use $work-with-jira.'; Match = '$work-with-jira' }
            @{ Text = 'Use $work-with-jira: then continue.'; Match = '$work-with-jira' }
            @{ Text = 'Use $work-with-jira(next).'; Match = '$work-with-jira' }
            @{ Text = 'Use {$work-with-jira} now.'; Match = '$work-with-jira' }
            @{ Text = 'Use $env:PATH.'; Match = '$env' }
        )) {
            $match = $pattern.Match($case.Text)
            $match.Success | Should -BeTrue -Because $case.Text
            $match.Value | Should -BeExactly $case.Match
        }
        foreach ($text in @(
            'alpha$pdf', '_$pdf', '$$pdf', '\$pdf', '$value_x', '${name}'
        )) {
            $pattern.IsMatch($text) | Should -BeFalse -Because $text
        }
    }

    # Scenario: a shared SKILL.md uses one AI host's invocation syntax.
    # Purpose: Standard section 4.5 keeps the exact $<skill-id> token inside agents/openai.yaml only.
    It 'rejects a host-specific Skill invocation token in SKILL.md: <Token>' -ForEach @(
        @{ Token = '$manage-task-handoff' }
        @{ Token = '$work-with-jira' }
        @{ Token = '$configure-jira-api-access' }
        @{ Token = '$pdf' }
        @{ Token = '$value' }
    ) {
        $skillPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/SKILL.md'
        Add-Content -LiteralPath $skillPath -Value ([Environment]::NewLine + 'Use ' + $Token + ' for task state.')
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the invocation token fixture.' }

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ("*'SKILL.md' contains host-specific invocation token '{0}'*" -f $Token)
    }

    # Scenario: a Skill reference uses one AI host's invocation syntax.
    # Purpose: references are shared instructions and follow the same AI-neutral rule.
    It 'rejects a host-specific Skill invocation token in a reference' {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-task-handoff/references/handoff-operations.md'
        Add-Content -LiteralPath $referencePath -Value "`nRun `$manage-task-handoff again."
        & $script:GitPath -C $fixtureRoot add -- skills/manage-task-handoff/references/handoff-operations.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the reference token fixture.' }

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/handoff-operations.md' contains host-specific invocation token*"
    }

    It 'rejects an inline-code invocation token in SKILL.md' {
        $skillPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/SKILL.md'
        Add-Content -LiteralPath $skillPath -Value ([Environment]::NewLine + 'Use `$manage-task-handoff` for task state.')
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the inline-code SKILL.md fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'SKILL.md' contains host-specific invocation token '`$manage-task-handoff'*"
    }

    It 'rejects an inline-code invocation token in a Markdown reference' {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-task-handoff/references/handoff-operations.md'
        Add-Content -LiteralPath $referencePath -Value ([Environment]::NewLine + 'Use `$manage-task-handoff` for task state.')
        & $script:GitPath -C $fixtureRoot add -- skills/manage-task-handoff/references/handoff-operations.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the inline-code reference fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/handoff-operations.md' contains host-specific invocation token '`$manage-task-handoff'*"
    }

    It 'rejects a variable-like hyphen token in Markdown prose' {
        $skillPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/SKILL.md'
        Add-Content -LiteralPath $skillPath -Value ([Environment]::NewLine + 'Write-Output "$value-suffix"')
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the Markdown prose token fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'SKILL.md' contains host-specific invocation token '`$value-suffix'*"
    }

    It 'rejects invocation punctuation and invalid scope syntax: <Label>' -ForEach @(
        @{ Label = 'colon punctuation'; Text = 'Use $work-with-jira: then continue.'; Token = '$work-with-jira' }
        @{ Label = 'opening parenthesis punctuation'; Text = 'Use $work-with-jira(next).'; Token = '$work-with-jira' }
        @{ Label = 'opening brace punctuation'; Text = 'Use {$work-with-jira} now.'; Token = '$work-with-jira' }
        @{ Label = 'non-scope prefix'; Text = 'Use $work-with-jira:x now.'; Token = '$work-with-jira' }
        @{ Label = 'scope prefix without variable name'; Text = 'Use $env: now.'; Token = '$env' }
        @{ Label = 'scope exception followed by invocation'; Text = 'Read $env:PATH, then use $work-with-jira.'; Token = '$work-with-jira' }
    ) {
        $skillPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/SKILL.md'
        Add-Content -LiteralPath $skillPath -Value ([Environment]::NewLine + $Text)
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the invocation-boundary fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ("*'SKILL.md' contains host-specific invocation token '{0}'*" -f $Token)
    }

    # Scenario: a SKILL.md names another Skill in prose.
    # Purpose: names without a sigil remain AI-neutral across inventories.
    It 'accepts a Skill referenced by name without the invocation sigil' {
        $skillPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/SKILL.md'
        Add-Content -LiteralPath $skillPath -Value ([Environment]::NewLine + 'Use the manage-task-handoff Skill for task state; work-with-jira and configure-jira-api-access are plain Skill names.')
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the Skill name fixture.' }

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'accepts exact variable scopes and non-token forms in Markdown prose' {
        $skillPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/SKILL.md'
        $example = '$env:PATH $script:Value ${name} value$work-with-jira $$work-with-jira \$work-with-jira'
        Add-Content -LiteralPath $skillPath -Value ([Environment]::NewLine + $example)
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/SKILL.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the ordinary variable fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'accepts variable interpolation in program references' {
        $powershellPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/example.ps1'
        $shellPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/example.sh'
        [IO.File]::WriteAllText($powershellPath, 'Write-Output "$value-suffix"', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($shellPath, 'printf "%s\n" "$output-file"', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/references/example.ps1 skills/manage-ai-memory/references/example.sh
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the program reference fixtures.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'accepts variable interpolation in a recognized program-language fence' {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/nested/instructions.md'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $referencePath) -Force)
        $example = @('```PoWeRsHeLl title=example', 'Write-Output "$value-suffix"', '$env:PATH', '${name}', '```') -join [Environment]::NewLine
        [IO.File]::WriteAllText($referencePath, $example, [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/references/nested/instructions.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the program fence fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'rejects an invocation token in a scanned Markdown fence: <Label>' -ForEach @(
        @{ Label = 'unlabeled'; Opening = '```'; Token = '$work-with-jira' }
        @{ Label = 'markdown'; Opening = '```markdown'; Token = '$work-with-jira' }
        @{ Label = 'text'; Opening = '```text'; Token = '$configure-jira-api-access' }
        @{ Label = 'unlisted-language'; Opening = '```ruby'; Token = '$work-with-jira' }
    ) {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/fenced.md'
        $example = @($Opening, $Token, '```') -join [Environment]::NewLine
        [IO.File]::WriteAllText($referencePath, $example, [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/references/fenced.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the scanned fence fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ("*'references/fenced.md' contains host-specific invocation token '{0}'*" -f $Token)
    }

    It 'rejects an unclosed recognized program-language fence' {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/unclosed.md'
        $example = @('~~~powershell', 'Write-Output "$value-suffix"') -join [Environment]::NewLine
        [IO.File]::WriteAllText($referencePath, $example, [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/references/unclosed.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the unclosed fence fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/unclosed.md'*unclosed code fence*"
    }

    It 'masks fenced code only by original source line numbers' {
        $maskingTokens = $null
        $maskingParseErrors = $null
        $maskingAst = [Management.Automation.Language.Parser]::ParseFile(
            $script:ValidatorPath,
            [ref]$maskingTokens,
            [ref]$maskingParseErrors
        )
        @($maskingParseErrors).Count | Should -Be 0
        $maskingFunctions = @($maskingAst.FindAll({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'ConvertTo-MarkdownInvocationScanText'
        }, $true))
        $maskingFunctions.Count | Should -Be 1 -Because 'the masking function must exist exactly once'
        $maskingFunction = $maskingFunctions[0]
        $excludedTokenKinds = @(
            [Management.Automation.Language.TokenKind]::LineContinuation
            [Management.Automation.Language.TokenKind]::Comment
            [Management.Automation.Language.TokenKind]::EndOfInput
        )
        $functionTokens = @($maskingTokens | Where-Object {
            $_.Extent.StartOffset -ge $maskingFunction.Extent.StartOffset -and
            $_.Extent.EndOffset -le $maskingFunction.Extent.EndOffset -and
            $_.Kind -notin $excludedTokenKinds
        })
        $serializedTokenLines = [Collections.Generic.List[string]]::new()
        foreach ($token in $functionTokens) {
            if ($token.Kind -eq [Management.Automation.Language.TokenKind]::NewLine) {
                if ($serializedTokenLines.Count -eq 0 -or $serializedTokenLines[$serializedTokenLines.Count - 1] -cne 'NewLine:') {
                    $serializedTokenLines.Add('NewLine:')
                }
                continue
            }
            $serializedTokenLines.Add(('{0}:{1}' -f $token.Kind, $token.Text))
        }
        $serializedTokens = $serializedTokenLines -join "`n"
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $fingerprintBytes = $sha256.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($serializedTokens))
        }
        finally {
            $sha256.Dispose()
        }
        $actualFingerprint = [BitConverter]::ToString($fingerprintBytes).Replace('-', '').ToLowerInvariant()
        # This fingerprint is a change warning, not a semantic guarantee: it blocks substantive edits for review,
        # while the production-path 43-case matrix verifies semantics; an unchanged fingerprint does not prove correctness.
        $expectedFingerprint = '925d873cea114d5bd432d1a0b7c66580727ea75afbb15c65c777bf6a577fff9d'
        $fingerprintReason = 'Actual: {0}; expected: {1}. 函式有變更時，請重新審查遮蔽規則（只以原文行號遮蔽，並保留一致性斷言），再更新指紋。' -f $actualFingerprint, $expectedFingerprint
        $actualFingerprint | Should -BeExactly $expectedFingerprint -Because $fingerprintReason
    }

    It 'follows Markdig CommonMark fenced-code decisions: <Label>' -ForEach @(
        @{
            Label = 'backtick delimiter'; Lines = @('```powershell', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark recognizes a closed backtick fence and the reviewed language is program code.'
        }
        @{
            Label = 'tilde delimiter'; Lines = @('~~~powershell', 'Use $work-with-jira.', '~~~'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark recognizes a closed tilde fence and the reviewed language is program code.'
        }
        @{
            Label = 'closing shorter than opening'; Lines = @('````powershell', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'unclosed'
            Reason = 'CommonMark requires a closing fence at least as long as its opening fence.'
        }
        @{
            Label = 'closing equal to opening'; Lines = @('````powershell', 'Use $work-with-jira.', '````'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark accepts a closing fence equal in length to its opening fence.'
        }
        @{
            Label = 'closing longer than opening'; Lines = @('```powershell', 'Use $work-with-jira.', '````'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark accepts a closing fence longer than its opening fence.'
        }
        @{
            Label = 'zero-space opening indent'; Lines = @('```powershell', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark permits zero spaces before an opening fence.'
        }
        @{
            Label = 'one-space opening indent'; Lines = @(' ```powershell', ' Use $work-with-jira.', ' ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark permits one space before an opening fence.'
        }
        @{
            Label = 'two-space opening indent'; Lines = @('  ```powershell', '  Use $work-with-jira.', '  ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark permits two spaces before an opening fence.'
        }
        @{
            Label = 'three-space opening indent'; Lines = @('   ```powershell', '   Use $work-with-jira.', '   ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark permits three spaces before an opening fence.'
        }
        @{
            Label = 'four-space indented code'; Lines = @('    ```powershell', '    Use $work-with-jira.', '    ```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'CommonMark parses four-space indentation as an indented code block, whose source remains scanned.'
        }
        @{
            Label = 'backtick in backtick info string'; Lines = @('```powershell `', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'CommonMark forbids a backtick in a backtick fence info string, so the first line does not open a fence.'
        }
        @{
            Label = 'other delimiter inside fence'; Lines = @('```powershell', '~~~', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'A tilde sequence cannot close a backtick fence, so all content stays in program code.'
        }
        @{
            Label = 'closing line with trailing text'; Lines = @('```powershell', 'Use $work-with-jira.', '``` trailing'); NewLine = "`n"; Outcome = 'unclosed'
            Reason = 'CommonMark does not accept non-whitespace text after a closing fence.'
        }
        @{
            Label = 'closing line with spaces and tab'; Lines = @('```powershell', 'Use $work-with-jira.', ('```  ' + "`t")); NewLine = "`n"; Outcome = 'pass'
            Reason = 'CommonMark accepts spaces and tabs after a closing fence.'
        }
        @{
            Label = 'LF newlines'; Lines = @('```powershell', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'Markdig recognizes the CommonMark fence with LF newlines.'
        }
        @{
            Label = 'CRLF newlines'; Lines = @('```powershell', 'Use $work-with-jira.', '```'); NewLine = "`r`n"; Outcome = 'pass'
            Reason = 'Markdig recognizes the CommonMark fence with CRLF newlines.'
        }
        @{
            Label = 'list-item powershell fence'; Lines = @('- ```powershell', '  Use $work-with-jira.', '  ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'Descendants includes a program fence nested in a list item, so its content is masked.'
        }
        @{
            Label = 'block-quote powershell fence'; Lines = @('> ```powershell', '> Use $work-with-jira.', '> ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'Descendants includes a program fence nested in a block quote, so its content is masked.'
        }
        @{
            Label = 'list-item markdown fence'; Lines = @('- ```markdown', '  Use $work-with-jira.', '  ```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'A nested markdown fence is not a reviewed program language and remains scanned.'
        }
        @{
            Label = 'block-quote markdown fence'; Lines = @('> ```markdown', '> Use $work-with-jira.', '> ```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'A nested markdown fence is not a reviewed program language and remains scanned.'
        }
        @{
            Label = 'empty info string'; Lines = @('```', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'An empty-info fence is not a reviewed program language and remains scanned.'
        }
        @{
            Label = 'text info string'; Lines = @('```text', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'A text fence is not a reviewed program language and remains scanned.'
        }
        @{
            Label = 'unlisted info string'; Lines = @('```ruby', 'Use $work-with-jira.', '```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'An unlisted language fence is not a reviewed program language and remains scanned.'
        }
        @{
            Label = 'unclosed powershell fence'; Lines = @('```powershell', 'Use $work-with-jira.'); NewLine = "`n"; Outcome = 'unclosed'
            Reason = 'A reviewed program-language fence must close or validation fails closed.'
        }
        @{
            Label = 'unclosed text fence'; Lines = @('```text', 'Use $work-with-jira.'); NewLine = "`n"; Outcome = 'token'
            Reason = 'An unclosed text fence is still scanned and its invocation token is rejected.'
        }
        @{
            Label = 'quote-tab prose token with CRLF'; Lines = @('Use $work-with-jira.', '> ```powershell', ('>' + "`t" + 'Write-Output safe'), '> ```'); NewLine = "`r`n"; Outcome = 'token'
            Reason = 'A normalized quote-tab code line must not mask preceding prose, including with CRLF input.'
        }
        @{
            Label = 'quote-tab code token without final newline'; Lines = @('Neutral prose.', '> ```powershell', ('>' + "`t" + 'Use $work-with-jira.'), '> ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'A quote followed immediately by a tab is a valid container prefix whose program content is masked through EOF without a final newline.'
        }
        @{
            Label = 'quote-space-tab prose token without final newline'; Lines = @('Use $work-with-jira.', '> ```powershell', ('> ' + "`t" + 'Write-Output safe'), '> ```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'A quote-space-tab code line must not mask preceding prose when the file has no final newline.'
        }
        @{
            Label = 'quote-space-tab code token with CRLF'; Lines = @('Neutral prose.', '> ```powershell', ('> ' + "`t" + 'Use $work-with-jira.'), '> ```'); NewLine = "`r`n"; Outcome = 'pass'
            Reason = 'A quote, space, and tab prefix retains CRLF while the program content line is masked.'
        }
        @{
            Label = 'double-quote-tab prose token with CRLF'; Lines = @('Use $work-with-jira.', '>> ```powershell', ('>>' + "`t" + 'Write-Output safe'), '>> ```'); NewLine = "`r`n"; Outcome = 'token'
            Reason = 'A normalized double-quote-tab code line must not mask preceding prose, including with CRLF input.'
        }
        @{
            Label = 'double-quote-tab code token without final newline'; Lines = @('Neutral prose.', '>> ```powershell', ('>>' + "`t" + 'Use $work-with-jira.'), '>> ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'A double quote followed by a tab is a valid nested container prefix whose program content is masked through EOF.'
        }
        @{
            Label = 'list-item code token by source line'; Lines = @('Neutral prose.', '- ```powershell', '  Use $work-with-jira.', '  ```'); NewLine = "`n"; Outcome = 'pass'
            Reason = 'A list-item program content line indented by two spaces is masked by its original source line number.'
        }
        @{
            Label = 'list-item preceding prose token'; Lines = @('Use $work-with-jira.', '- ```powershell', '  Write-Output safe', '  ```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'Masking a nested list-item program line must leave preceding prose available to the token scanner.'
        }
        @{
            Label = 'review4 long quote-tab reproduction'; Lines = @('Use $work-with-jira.', '> ```powershell', ('>' + "`t" + ('x' * 80)), '> ```'); NewLine = "`n"; Outcome = 'token'
            Reason = 'The 80-character Review4 reproduction must retain and reject the invocation token before the fence.'
        }
    ) {
        $relativePath = 'skills/manage-ai-memory/references/markdig-matrix.md'
        $referencePath = Join-Path $fixtureRoot $relativePath
        $content = $Lines -join $NewLine
        [IO.File]::WriteAllText($referencePath, $content, [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the Markdig matrix fixture.' }

        $errorRecord = $null
        try { & $script:ValidatorPath -RepositoryRoot $fixtureRoot | Out-Null }
        catch { $errorRecord = $_ }
        if ($Outcome -ceq 'pass') {
            $errorRecord | Should -BeNullOrEmpty -Because $Reason
        }
        else {
            $errorRecord | Should -Not -BeNullOrEmpty -Because $Reason
            if ($Outcome -ceq 'unclosed') {
                $errorRecord.Exception.Message | Should -BeLike "*'references/markdig-matrix.md'*unclosed code fence*" -Because $Reason
            }
            else {
                $errorRecord.Exception.Message | Should -BeLike "*'references/markdig-matrix.md'*host-specific invocation token '`$work-with-jira'*" -Because $Reason
            }
        }
    }

    It 'accepts a binary PDF reference and retains its inventory hash and index binding' {
        $relativePath = 'skills/manage-ai-memory/references/design.pdf'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllBytes($referencePath, [byte[]]@(0x25, 0x50, 0x44, 0x46, 0xFF))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the binary reference fixture.' }
        $result = & $script:ValidatorPath -RepositoryRoot $fixtureRoot | Select-Object -Last 1 | ConvertFrom-Json
        $package = @($result.skills | Where-Object skillId -EQ 'manage-ai-memory')[0]
        $entry = @($package.files | Where-Object path -CEQ 'references/design.pdf')
        $entry.Count | Should -Be 1
        $entry[0].sha256 | Should -BeExactly ((Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash.ToLowerInvariant())
        [IO.File]::WriteAllBytes($referencePath, [byte[]]@(0x25, 0x50, 0x44, 0x46, 0xFE))
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Throw '*working-tree content is not bound*'
    }

    It 'rejects invalid UTF-8 in an instruction Markdown reference' {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/invalid.md'
        [IO.File]::WriteAllBytes($referencePath, [byte[]]@(0x23, 0x20, 0xFF))
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/references/invalid.md
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the invalid UTF-8 reference fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Throw "*'references/invalid.md' must be valid UTF-8*"
    }

    It 'rejects classified text references containing invocation tokens: <Extension>' -ForEach @(
        @{ Extension = '.markdown'; Token = '$work-with-jira' }
        @{ Extension = '.rst'; Token = '$work-with-jira' }
        @{ Extension = '.svg'; Token = '$work-with-jira' }
        @{ Extension = '.MD'; Token = '$pdf' }
    ) {
        $relativePath = 'skills/manage-ai-memory/references/guide' + $Extension
        $referencePath = Join-Path $fixtureRoot $relativePath
        $content = if ($Extension -ceq '.svg') { '<svg><text>' + $Token + '</text></svg>' } else { 'Use ' + $Token + '.' }
        [IO.File]::WriteAllText($referencePath, $content, [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the classified text reference fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ("*contains host-specific invocation token '{0}'*" -f $Token)
    }

    It 'rejects invalid UTF-8 in an RST reference' {
        $referencePath = Join-Path $fixtureRoot 'skills/manage-ai-memory/references/invalid.rst'
        [IO.File]::WriteAllBytes($referencePath, [byte[]]@(0x23, 0x20, 0xFF))
        & $script:GitPath -C $fixtureRoot add -- skills/manage-ai-memory/references/invalid.rst
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the invalid UTF-8 RST fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Throw "*'references/invalid.rst' must be valid UTF-8*"
    }

    It 'rejects an invocation token in a JSON string value' {
        $relativePath = 'skills/manage-ai-memory/references/token-value.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"description":"Use $manage-task-handoff"}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the JSON string value fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/token-value.json' contains host-specific invocation token '`$manage-task-handoff'*"
    }

    It 'rejects a non-reserved invocation token in a JSON property name' {
        $relativePath = 'skills/manage-ai-memory/references/token-key.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"$manage-task-handoff":"plain text"}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the JSON property name fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/token-key.json' contains host-specific invocation token '`$manage-task-handoff'*"
    }

    It 'rejects an escaped invocation token in a JSON string value' {
        $relativePath = 'skills/manage-ai-memory/references/escaped-token-value.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"description":"Use \u0024manage-task-handoff"}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the escaped JSON string value fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/escaped-token-value.json' contains host-specific invocation token '`$manage-task-handoff'*"
    }

    It 'rejects a reserved token in a JSON string value' {
        $relativePath = 'skills/manage-ai-memory/references/reserved-token-value.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"note":"$schema"}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the reserved JSON string value fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/reserved-token-value.json' contains host-specific invocation token '`$schema'*"
    }

    It 'accepts empty strings in JSON reference values' {
        $relativePath = 'skills/manage-ai-memory/references/empty-values.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"default":"","examples":[""]}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the empty JSON value fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'accepts an empty JSON property name' {
        $relativePath = 'skills/manage-ai-memory/references/empty-property-name.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"":"plain"}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the empty JSON property name fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'accepts an empty classified text reference: <Extension>' -ForEach @(
        @{ Extension = '.md' }
        @{ Extension = '.txt' }
    ) {
        $relativePath = 'skills/manage-ai-memory/references/empty' + $Extension
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllBytes($referencePath, [byte[]]@())
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the empty classified text reference fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'still rejects an invocation token beside empty JSON values' {
        $relativePath = 'skills/manage-ai-memory/references/empty-values-with-token.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"default":"","examples":[""],"x":"Use $work-with-jira."}', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the empty JSON values with token fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/empty-values-with-token.json' contains host-specific invocation token '`$work-with-jira'*"
    }

    It 'rejects invalid JSON syntax' {
        $relativePath = 'skills/manage-ai-memory/references/invalid.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, '{"a":', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the invalid JSON fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*Skill 'manage-ai-memory'*'references/invalid.json'*must be valid JSON*"
    }

    It 'rejects invalid UTF-8 in a JSON reference' {
        $relativePath = 'skills/manage-ai-memory/references/invalid-utf8.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllBytes($referencePath, [byte[]]@(0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the invalid UTF-8 JSON fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'references/invalid-utf8.json' must be valid UTF-8*"
    }

    It 'accepts reserved JSON Schema property names' {
        $relativePath = 'skills/manage-ai-memory/references/reserved-keys.json'
        $referencePath = Join-Path $fixtureRoot $relativePath
        $content = '{"$schema":"https://example.invalid/schema","$id":"plain-id","$ref":"#","$defs":{"entry":{"type":"string"}}}'
        [IO.File]::WriteAllText($referencePath, $content, [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the reserved JSON Schema property fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
    }

    It 'rejects an unclassified reference file: <Name>' -ForEach @(
        @{ Name = 'guide.foo' }
        @{ Name = 'NOTES' }
    ) {
        $relativePath = 'skills/manage-ai-memory/references/' + $Name
        $referencePath = Join-Path $fixtureRoot $relativePath
        [IO.File]::WriteAllText($referencePath, 'plain text', [Text.UTF8Encoding]::new($false))
        & $script:GitPath -C $fixtureRoot add -- $relativePath
        if ($LASTEXITCODE -ne 0) { throw 'Could not stage the unclassified reference fixture.' }
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ("*Skill 'manage-ai-memory'*'references/{0}'*reference file classification*" -f $Name)
    }

    # Scenario: Skill content targets three platforms while the current validation toolchain uses Windows.
    # Purpose: reject Skill host restrictions and tokens, and preserve the exact documented validation scope.
    It 'keeps canonical Skill text free of host-restriction declarations and invocation tokens' {
        $restriction = '(?i)windows-only|only (supported )?on windows|only supported host|windows is the only|beyond windows|on windows|host .* is windows'
        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } | Should -Not -Throw
        $platformAssignments = @($script:ValidatorAst.FindAll({ param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -ceq '$script:PlatformRestrictedDescriptionPattern'
        }, $true))
        $platformAssignments.Count | Should -Be 1
        $platformPattern = & ([scriptblock]::Create($platformAssignments[0].Right.Extent.Text))
        $skillsRoot = Join-Path $script:RepositoryRoot 'skills'
        $files = @(Get-ChildItem -LiteralPath $skillsRoot -File -Recurse -Force)
        $files.Count | Should -BeGreaterThan 7
        foreach ($file in $files) {
            [IO.File]::ReadAllText($file.FullName) | Should -Not -Match $restriction -Because $file.FullName
        }
        $readmeText = [IO.File]::ReadAllText((Join-Path $script:RepositoryRoot 'README.md'))
        $readmeText | Should -Match ([regex]::Escape('The Skills are platform-neutral and target Windows, Linux, and macOS hosts.'))
        $readmeText | Should -Match ([regex]::Escape('Skills 內容與平台無關，目標主機為 Windows、Linux 與 macOS。'))
        $readmeText | Should -Match ([regex]::Escape('The Skill content targets Windows, Linux, and macOS hosts.'))
        $validationScope = 'The repository validation toolchain and CI currently run on Windows; cross-platform validation will be introduced by a later change.'
        $driverInstruction = 'Run local development, installation, execution, testing, acceptance, and any local source-validation run on Windows.'
        foreach ($statement in @($validationScope, $driverInstruction)) {
            ([regex]::Matches($readmeText, [regex]::Escape($statement))).Count | Should -Be 1
        }
        $readmeText.Replace($validationScope, '').Replace($driverInstruction, '') | Should -Not -Match $restriction
        $skills = @(Get-ChildItem -LiteralPath $skillsRoot -Directory)
        $skills.Count | Should -Be 7
        foreach ($skill in $skills) {
            $entry = Join-Path $skill.FullName 'SKILL.md'
            $entryText = [IO.File]::ReadAllText($entry)
            $entryText | Should -Not -Match 'SPDX-' -Because $entry
            $entryText | Should -Match '(?m)^description: \S'
            $entryText | Should -Not -Match '(?im)^description: (?:windows|linux|mac\s?os|unix)[\s-]*only'
            $description = [regex]::Match($entryText, '(?m)^description: (?<text>[^\r\n]+)').Groups['text'].Value
            $description | Should -Not -BeNullOrEmpty
            $description | Should -Not -Match $platformPattern -Because $entry
            $metadata = [IO.File]::ReadAllText((Join-Path $skill.FullName 'agents/openai.yaml'))
            $metadata | Should -Match ('(?m)^  default_prompt: "Use \$' + [regex]::Escape($skill.Name) + ' ')
        }
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
        $metadataPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/agents/openai.yaml'
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
        $metadataPath = Join-Path $fixtureRoot 'skills/manage-ai-memory/agents/openai.yaml'
        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        $missingValue = "dependencies:`n  tools:`n    - type: `"mcp`"`n      description: `"Optional target`"`n`npolicy:"
        $metadata = $metadata -replace '(?m)^policy:', $missingValue
        Set-Content -LiteralPath $metadataPath -Value $metadata -Encoding utf8NoBOM -NoNewline

        { & $script:ValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*dependency*non-empty value*'
    }
}
