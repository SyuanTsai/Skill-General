# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'manage-ai-memory provider-neutral contract' {
    BeforeAll {
        $script:Root = Split-Path -Parent $PSScriptRoot
        $script:Skill = Join-Path $script:Root 'skills/manage-ai-memory'
        $script:Contract = Get-Content -Raw (Join-Path $script:Skill 'references/memory-contract.json') | ConvertFrom-Json -Depth 40
        $script:Cases = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-ai-memory/routing-cases.json') | ConvertFrom-Json -Depth 40
        $script:AgentInputs = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-ai-memory/fixed-agent-scenarios.json') | ConvertFrom-Json -Depth 40
        $script:LegacyAdopters = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/fixed-agent-scenarios.json') | ConvertFrom-Json -Depth 40
        $script:SharedReferenceGenerator = Join-Path $script:Root 'scripts/Sync-SharedReferences.ps1'
        function New-SharedReferenceRepositoryFixture {
            param([Parameter(Mandatory)][string]$Root)
            foreach($relative in @('scripts','shared/references','skills/manage-ai-memory/references','skills/manage-task-handoff/references','skills/unrelated/references')){
                [void](New-Item -ItemType Directory -Path (Join-Path $Root $relative) -Force)
            }
            Copy-Item -LiteralPath $script:SharedReferenceGenerator -Destination (Join-Path $Root 'scripts/Sync-SharedReferences.ps1')
            [byte[]]$sourceBytes=[Text.UTF8Encoding]::new($false).GetBytes("authoritative shared reference`n")
            $sourcePath=Join-Path $Root 'shared/references/environment-separation.md'
            $memoryPath=Join-Path $Root 'skills/manage-ai-memory/references/environment-separation.md'
            $handoffPath=Join-Path $Root 'skills/manage-task-handoff/references/environment-separation.md'
            $unrelatedPath=Join-Path $Root 'skills/unrelated/references/environment-separation.md'
            [IO.File]::WriteAllBytes($sourcePath,$sourceBytes)
            [IO.File]::WriteAllText($memoryPath,"memory drift`n",[Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($handoffPath,"handoff drift`n",[Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($unrelatedPath,"unrelated sentinel`n",[Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{Root=$Root;Script=Join-Path $Root 'scripts/Sync-SharedReferences.ps1';Source=$sourcePath;SourceBytes=$sourceBytes;Memory=$memoryPath;Handoff=$handoffPath;Unrelated=$unrelatedPath}
        }
        function Get-OptionalProperty {
            param(
                [AllowNull()][object]$InputObject,
                [Parameter(Mandatory)][string]$Name
            )
            if ($null -eq $InputObject) { return $null }
            $property = $InputObject.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }
        function Test-MemoryWriteRule {
            param(
                [AllowNull()][object]$Rule,
                [Parameter(Mandatory)][object]$Contract,
                [AllowNull()][string]$RuleSource
            )
            if (-not [string]::IsNullOrWhiteSpace($RuleSource) -and $RuleSource -in @($Contract.legacyExemptions)) {
                return [pscustomobject]@{
                    Valid = $true
                    MissingFields = @()
                    Action = 'legacy-write-rule-valid'
                }
            }
            $adopterRule = Get-OptionalProperty -InputObject $Rule -Name ([string]$Contract.adopterConfigKey)
            if ($null -ne $adopterRule) { $Rule = $adopterRule }
            $missing = [Collections.Generic.List[string]]::new()
            foreach ($field in @($Contract.requiredFields)) {
                $property = if ($null -eq $Rule) { $null } else { $Rule.PSObject.Properties[$field] }
                if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                    $missing.Add($field)
                }
            }
            if ($missing.Count -eq 0) {
                $granularity = [string]$Rule.granularity
                if ($granularity -notin @($Contract.granularityValues)) {
                    $missing.Add('granularity')
                } else {
                    $requiredPlaceholders = @($Contract.granularityRequiredPlaceholder.$granularity)
                    if (@($requiredPlaceholders | Where-Object { ([string]$Rule.pageNaming).Contains([string]$_) }).Count -eq 0) {
                        $missing.Add('pageNaming')
                    }
                    $usedPlaceholders = @([regex]::Matches([string]$Rule.pageNaming, '\{[^{}]+\}') | ForEach-Object Value)
                    if (@($usedPlaceholders | Where-Object { $_ -notin @($Contract.pageNamingPlaceholders) }).Count -gt 0 -and $missing -notcontains 'pageNaming') {
                        $missing.Add('pageNaming')
                    }
                    $fallback = Get-OptionalProperty -InputObject $Rule -Name 'fallback'
                    if ($null -ne $fallback) {
                        $fallbackInvalid = $granularity -ne [string]$Contract.fallback.primaryGranularity -or
                            (Get-OptionalProperty -InputObject $fallback -Name 'fallback') -ne $null -or
                            [string](Get-OptionalProperty -InputObject $fallback -Name 'granularity') -ne [string]$Contract.fallback.granularity
                        foreach ($field in @($Contract.fallback.requiredFields)) {
                            if ([string]::IsNullOrWhiteSpace([string](Get-OptionalProperty -InputObject $fallback -Name $field))) { $fallbackInvalid = $true }
                        }
                        $fallbackParentProperty = $fallback.PSObject.Properties['parentLocator']
                        if ($null -ne $fallbackParentProperty -and [string]::IsNullOrWhiteSpace([string]$fallbackParentProperty.Value)) { $fallbackInvalid = $true }
                        $fallbackNaming = [string](Get-OptionalProperty -InputObject $fallback -Name 'pageNaming')
                        $fallbackPlaceholders = @([regex]::Matches($fallbackNaming, '\{[^{}]+\}') | ForEach-Object Value)
                        if (@($Contract.granularityRequiredPlaceholder.'per-topic' | Where-Object { $fallbackNaming.Contains([string]$_) }).Count -eq 0 -or
                            @($fallbackPlaceholders | Where-Object { $_ -notin @($Contract.pageNamingPlaceholders) }).Count -gt 0 -or
                            @($fallbackPlaceholders | Where-Object { $_ -in @($Contract.fallbackForbiddenPlaceholders) }).Count -gt 0) {
                            $fallbackInvalid = $true
                        }
                        if ($fallbackInvalid) { $missing.Add('fallback') }
                    }
                }
            }
            $valid = $missing.Count -eq 0
            [pscustomobject]@{
                Valid = $valid
                MissingFields = @($missing)
                Action = if ($valid) { 'write-rule-valid' } else { [string]$Contract.missingOrInvalidAction }
            }
        }
        function Format-MemoryPageName {
            param(
                [Parameter(Mandatory)][object]$Rule,
                [AllowNull()][object]$Context
            )
            $adopterRule = Get-OptionalProperty -InputObject $Rule -Name 'writeRule'
            if ($null -ne $adopterRule) { $Rule = $adopterRule }
            $selectedRule = $Rule
            $ticketKey = Get-OptionalProperty -InputObject $Context -Name 'ticketKey'
            if ([string](Get-OptionalProperty -InputObject $Rule -Name 'granularity') -eq 'per-ticket' -and
                [string]::IsNullOrWhiteSpace([string]$ticketKey)) {
                $fallback = Get-OptionalProperty -InputObject $Rule -Name 'fallback'
                if ($null -ne $fallback) { $selectedRule = $fallback }
            }
            $rendered = [string](Get-OptionalProperty -InputObject $selectedRule -Name 'pageNaming')
            $usedPlaceholders = @([regex]::Matches($rendered, '\{([^{}]+)\}') | ForEach-Object { $_.Groups[1].Value })
            foreach ($placeholder in $usedPlaceholders) {
                $value = Get-OptionalProperty -InputObject $Context -Name ([string]$placeholder)
                if ([string]::IsNullOrWhiteSpace([string]$value)) {
                    throw "Unresolved placeholder: {$placeholder}"
                }
                if ($placeholder -eq 'title' -and
                    [string](Get-OptionalProperty -InputObject $selectedRule -Name 'granularity') -eq 'per-ticket' -and
                    [string](Get-OptionalProperty -InputObject $Context -Name 'titleSource') -notin @('tracker', 'user')) {
                    throw 'Unresolved ticket title authority'
                }
                $rendered = $rendered.Replace('{' + $placeholder + '}', [string]$value)
            }
            return $rendered
        }
        function Resolve-MemoryWriteRule {
            param(
                [AllowNull()][object]$Rule,
                [Parameter(Mandatory)][object]$Contract,
                [AllowNull()][object]$Context
            )
            $validation = Test-MemoryWriteRule -Rule $Rule -Contract $Contract
            if (-not $validation.Valid) { return [pscustomobject]@{ Valid = $false; Action = $validation.Action; Writes = 0; Rule = $null } }
            $adopterRule = Get-OptionalProperty -InputObject $Rule -Name ([string]$Contract.adopterConfigKey)
            if ($null -ne $adopterRule) { $Rule = $adopterRule }
            $selected = $Rule
            $ticketKey = Get-OptionalProperty -InputObject $Context -Name 'ticketKey'
            $hasTicketKey = -not [string]::IsNullOrWhiteSpace([string]$ticketKey)
            if ([string]$Rule.granularity -eq 'per-ticket' -and -not $hasTicketKey) {
                $selected = Get-OptionalProperty -InputObject $Rule -Name 'fallback'
                if ($null -eq $selected) { return [pscustomobject]@{ Valid = $false; Action = [string]$Contract.fallback.missingTicketKeyWithoutFallbackAction; Writes = 0; Rule = $null } }
            }
            $selectedNaming = [string](Get-OptionalProperty -InputObject $selected -Name 'pageNaming')
            $selectedPlaceholders = @([regex]::Matches($selectedNaming, '\{([^{}]+)\}') | ForEach-Object { $_.Groups[1].Value })
            foreach ($placeholder in $selectedPlaceholders) {
                $value = Get-OptionalProperty -InputObject $Context -Name ([string]$placeholder)
                if ([string]::IsNullOrWhiteSpace([string]$value)) {
                    $action = if ($placeholder -eq 'title') { [string]$Contract.title.unresolvedAction } else { [string]$Contract.unresolvedPlaceholderAction }
                    return [pscustomobject]@{ Valid = $false; Action = $action; Writes = 0; Rule = $null }
                }
                if ($placeholder -eq 'title' -and
                    [string](Get-OptionalProperty -InputObject $selected -Name 'granularity') -eq 'per-ticket' -and
                    [string](Get-OptionalProperty -InputObject $Context -Name 'titleSource') -notin @('tracker', 'user')) {
                    return [pscustomobject]@{ Valid = $false; Action = [string]$Contract.title.unresolvedAction; Writes = 0; Rule = $null }
                }
            }
            $parent = Get-OptionalProperty -InputObject $selected -Name 'parentLocator'
            if ($null -eq $parent) { $parent = Get-OptionalProperty -InputObject $Rule -Name 'parentLocator' }
            [pscustomobject]@{ Valid = $true; Action = 'write-rule-resolved'; Writes = 1; Rule = $selected; ParentLocator = [string]$parent }
        }
    }

    # Scenario: The renamed package is discovered as one stable source identity.
    # Purpose: Keep Handoff independent and prevent duplicate old/new Skill discovery.
    It 'InterT05_publishes_one_new_memory_skill_without_handoff_ownership' {
        $source = Get-Content -Raw (Join-Path $script:Root 'catalog/source.json') | ConvertFrom-Json -Depth 10
        @($source.skills) | Should -Contain 'manage-ai-memory'
        @($source.skills) | Should -Not -Contain 'manage-notion-ai-memory'
        @($source.skills) | Should -Contain 'manage-task-handoff'
        $script:Contract.operationScope.allowsHandoffOperations | Should -BeFalse
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Match 'name: manage-ai-memory'
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Match 'the manage-task-handoff Skill'
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Not -Match '\$manage-task-handoff\b'
        (Get-Content -Raw (Join-Path $script:Skill 'agents/openai.yaml')) | Should -Match '\$manage-ai-memory'
    }

    It 'ContractT06_separates_private_and_work_targets_before_any_external_access' {
        $skillText = Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')
        $skillText | Should -Match 'first load \[environment separation\]\(references/environment-separation\.md\)'
        $skillText | Should -Match 'Before any external record or file target or source access, both reads and writes, first load'
        $skillText | Should -Match 'regardless of provider'
        $skillText | Should -Not -Match 'When a Notion or Jira target is involved'
        $skillText | Should -Not -Match 'URL or site, issue-key prefix|write or move data across environments'
        $referencePath=Join-Path $script:Skill 'references/environment-separation.md'
        $handoffReferencePath=Join-Path $script:Root 'skills/manage-task-handoff/references/environment-separation.md'
        $authoritativeReferencePath=Join-Path $script:Root 'shared/references/environment-separation.md'
        [byte[]]$referenceBytes=[IO.File]::ReadAllBytes($referencePath)
        [byte[]]$handoffReferenceBytes=[IO.File]::ReadAllBytes($handoffReferencePath)
        [byte[]]$authoritativeReferenceBytes=[IO.File]::ReadAllBytes($authoritativeReferencePath)
        [Convert]::ToBase64String($referenceBytes) | Should -BeExactly ([Convert]::ToBase64String($handoffReferenceBytes))
        [Convert]::ToBase64String($referenceBytes) | Should -BeExactly ([Convert]::ToBase64String($authoritativeReferenceBytes))
        $referenceText=[Text.UTF8Encoding]::new($false,$true).GetString($referenceBytes)
        $referenceText | Should -Match 'before any external record, file, or source access, both reads and writes, for every provider'
        $referenceText | Should -Match 'includes targets other than Notion or Jira'
        $referenceText | Should -Match 'Notion sites and Jira sites, tenants, projects, and issue-key prefixes'
        $referenceText | Should -Match 'URL or site, issue-key prefix, repository configuration, then the user''s explicit selection'
        $referenceText | Should -Match 'user-local configuration outside the repository'
        $referenceText | Should -Match 'environment remains unknown or any signals conflict, stop and ask'
        $referenceText | Should -Match 'If a work request selects a private target or a private request selects a work target, stop before any access'
        $referenceText | Should -Match 'Before every access, verify that the selected target, its site or tenant when applicable, and every applicable project belong to the resolved environment'
        $referenceText | Should -Match 'If the target, site or tenant, or any applicable project does not match, stop before access'
        $referenceText | Should -Match 'never switch or fall back to another connection method automatically'
        $referenceText | Should -Match 'Never read, write, copy, or move data across environments'
        $referenceText | Should -Match 'write preview must identify both the resolved environment and the selected target, including its site when applicable'
        $referenceText | Should -Not -Match '(?i)https?://[^\s)`]+|[a-z0-9-]+\.atlassian\.net'
        & (Join-Path $script:Root 'scripts/Sync-SharedReferences.ps1') -Check | Should -Match 'Shared references are current \(2 files\)'
        $source=Get-Content -Raw (Join-Path $script:Root 'catalog/source.json')|ConvertFrom-Json
        $source.skillsRoot | Should -BeExactly 'skills'
        @($source.skills) | Should -Not -Contain 'shared'
        (Get-Content -Raw (Join-Path $script:Root '.github/workflows/consumer-gate.yml')) | Should -Not -Match 'Sync-SharedReferences\.ps1'
    }

    It 'UnitT07_runs_the_complete_shared_reference_generator_and_writes_only_changed_fixed_targets' {
        $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-sync')
        {& $fixture.Script -Check}|Should -Throw '*Shared references are not generated from the authoritative source*'

        [IO.File]::WriteAllBytes($fixture.Memory,$fixture.SourceBytes)
        $stableTime=[datetime]::SpecifyKind([datetime]'2020-01-01T00:00:00',[DateTimeKind]::Utc)
        [IO.File]::SetLastWriteTimeUtc($fixture.Memory,$stableTime)
        [IO.File]::SetLastWriteTimeUtc($fixture.Handoff,$stableTime)
        [byte[]]$unrelatedBefore=[IO.File]::ReadAllBytes($fixture.Unrelated)
        $unrelatedTime=(Get-Item -LiteralPath $fixture.Unrelated).LastWriteTimeUtc

        (& $fixture.Script)|Should -Match 'Synchronized 2 shared references; changed 1\.'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Memory))|Should -BeExactly ([Convert]::ToBase64String($fixture.SourceBytes))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Handoff))|Should -BeExactly ([Convert]::ToBase64String($fixture.SourceBytes))
        (Get-Item -LiteralPath $fixture.Memory).LastWriteTimeUtc|Should -Be $stableTime -Because 'matching bytes must not be rewritten'
        (Get-Item -LiteralPath $fixture.Handoff).LastWriteTimeUtc|Should -Not -Be $stableTime -Because 'drifted bytes must be rewritten'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Unrelated))|Should -BeExactly ([Convert]::ToBase64String($unrelatedBefore))
        (Get-Item -LiteralPath $fixture.Unrelated).LastWriteTimeUtc|Should -Be $unrelatedTime

        $memoryTime=(Get-Item -LiteralPath $fixture.Memory).LastWriteTimeUtc;$handoffTime=(Get-Item -LiteralPath $fixture.Handoff).LastWriteTimeUtc
        (& $fixture.Script)|Should -Match 'Synchronized 2 shared references; changed 0\.'
        (Get-Item -LiteralPath $fixture.Memory).LastWriteTimeUtc|Should -Be $memoryTime
        (Get-Item -LiteralPath $fixture.Handoff).LastWriteTimeUtc|Should -Be $handoffTime
        (& $fixture.Script -Check)|Should -Match 'Shared references are current \(2 files\)'
    }

    # Native hardlinks are available on all three supported hosts; failure to
    # create one fails the test rather than silently skipping the boundary.
    It 'UnitT12_rejects_a_native_hardlink_at_a_fixed_shared_reference_target: <Target>' -ForEach @(
        @{ Target = 'Memory' }
        @{ Target = 'Handoff' }
    ) {
        $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive ('shared-reference-hardlink-' + $Target))
        $outside=Join-Path $TestDrive ('outside-hardlink-' + $Target + '.txt')
        [byte[]]$sentinelBytes=[Text.UTF8Encoding]::new($false).GetBytes('outside hardlink sentinel')
        [IO.File]::WriteAllBytes($outside,$sentinelBytes)
        $targetPath=$fixture.$Target
        Remove-Item -LiteralPath $targetPath -Force
        [void](New-Item -ItemType HardLink -Path $targetPath -Target $outside -ErrorAction Stop)
        (Get-Item -LiteralPath $targetPath -Force).LinkType | Should -BeExactly 'HardLink'
        [Convert]::ToBase64String($sentinelBytes) | Should -Not -BeExactly ([Convert]::ToBase64String($fixture.SourceBytes))
        {& $fixture.Script} | Should -Throw '*source or target must not be a hardlink*'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($outside)) | Should -BeExactly ([Convert]::ToBase64String($sentinelBytes))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($targetPath)) | Should -BeExactly ([Convert]::ToBase64String($sentinelBytes))
    }

    It 'UnitT13_rejects_a_native_hardlink_at_the_shared_reference_source' {
        $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-source-hardlink')
        $outside=Join-Path $TestDrive 'outside-source-hardlink.txt'
        [IO.File]::WriteAllBytes($outside,$fixture.SourceBytes)
        Remove-Item -LiteralPath $fixture.Source -Force
        [void](New-Item -ItemType HardLink -Path $fixture.Source -Target $outside -ErrorAction Stop)
        (Get-Item -LiteralPath $fixture.Source -Force).LinkType | Should -BeExactly 'HardLink'
        $memoryBefore=[Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Memory))
        $handoffBefore=[Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Handoff))
        {& $fixture.Script} | Should -Throw '*source or target must not be a hardlink*'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($outside)) | Should -BeExactly ([Convert]::ToBase64String($fixture.SourceBytes))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Memory)) | Should -BeExactly $memoryBefore
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Handoff)) | Should -BeExactly $handoffBefore
    }

    if($IsWindows){
        It 'UnitT08_rejects_a_Windows_file_reparse_fixture_at_a_fixed_shared_reference_target' {
            $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-target-file-reparse')
            $outside=Join-Path $TestDrive 'outside-target-file.txt';[IO.File]::WriteAllText($outside,'outside sentinel')
            [byte[]]$outsideBefore=[IO.File]::ReadAllBytes($outside)
            $tokens=$null;$errors=$null
            $generatorAst=[Management.Automation.Language.Parser]::ParseFile($fixture.Script,[ref]$tokens,[ref]$errors)
            @($errors).Count|Should -Be 0
            $targetGuard=@($generatorAst.EndBlock.Statements|Where-Object{$_-is[Management.Automation.Language.FunctionDefinitionAst]-and$_.Name-ceq'Assert-SafeSharedReferenceTarget'})
            $targetGuard.Count|Should -Be 1
            $fixtureHelpers=@'
$script:LinkedTargetPath=''
$script:OutsideTargetPath=''
function Get-Item {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath,[switch]$Force)
    $fullPath=[IO.Path]::GetFullPath($LiteralPath)
    if([string]::Equals($fullPath,$script:LinkedTargetPath,[StringComparison]::OrdinalIgnoreCase)){
        return [pscustomobject]@{PSIsContainer=$false;Attributes=[IO.FileAttributes]::ReparsePoint;Target=$script:OutsideTargetPath}
    }
    $parameters=@{LiteralPath=$LiteralPath}
    if($PSBoundParameters.ContainsKey('Force')){$parameters.Force=$Force}
    if($PSBoundParameters.ContainsKey('ErrorAction')){$parameters.ErrorAction=$PSBoundParameters.ErrorAction}
    return Microsoft.PowerShell.Management\Get-Item @parameters
}
Export-ModuleMember -Function @()
'@
            $guardModule=New-Module -Name 'ManageAiMemoryUnitT08Guard' -ScriptBlock ([scriptblock]::Create($fixtureHelpers+[Environment]::NewLine+$targetGuard[0].Extent.Text))
            try{
                {
                    & $guardModule {
                        param($root,$relativePath,$linkedTargetPath,$outsideTargetPath)
                        $script:LinkedTargetPath=[IO.Path]::GetFullPath($linkedTargetPath)
                        $script:OutsideTargetPath=[IO.Path]::GetFullPath($outsideTargetPath)
                        Assert-SafeSharedReferenceTarget -Root $root -RelativePath $relativePath
                    } $fixture.Root 'skills/manage-ai-memory/references/environment-separation.md' $fixture.Memory $outside
                }|Should -Throw '*must be a regular non-reparse file*'
            }finally{
                Remove-Module -ModuleInfo $guardModule -Force -ErrorAction SilentlyContinue
            }
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($outside))|Should -BeExactly ([Convert]::ToBase64String($outsideBefore))
            (Get-Command Get-Item).CommandType|Should -BeExactly 'Cmdlet'
            Get-Module -Name 'ManageAiMemoryUnitT08Guard'|Should -BeNullOrEmpty
        }

        It 'UnitT08_cleanup_does_not_leak_the_Get_Item_shim_or_dynamic_module' {
            (Get-Command Get-Item).CommandType|Should -BeExactly 'Cmdlet'
            (Get-Command Get-Item).ModuleName|Should -BeExactly 'Microsoft.PowerShell.Management'
            Get-Module -Name 'ManageAiMemoryUnitT08Guard'|Should -BeNullOrEmpty
        }

        It 'UnitT09_rejects_a_Windows_Junction_in_a_shared_reference_target_ancestor' {
            $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-ancestor-junction')
            $linkedAncestor=Join-Path $fixture.Root 'skills/manage-ai-memory';$outside=Join-Path $TestDrive 'outside-ancestor-junction'
            [void](New-Item -ItemType Directory -Path (Join-Path $outside 'references') -Force)
            Remove-Item -LiteralPath $linkedAncestor -Recurse -Force
            [void](New-Item -ItemType Junction -Path $linkedAncestor -Target $outside -ErrorAction Stop)
            {& $fixture.Script}|Should -Throw '*linked or non-directory ancestor*'
        }
    }else{
        It 'UnitT08_rejects_a_Unix_symlink_at_a_fixed_shared_reference_target' {
            $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-target-symlink')
            $outside=Join-Path $TestDrive 'outside-target-symlink';[IO.File]::WriteAllText($outside,'outside')
            [byte[]]$outsideBefore=[IO.File]::ReadAllBytes($outside)
            Remove-Item -LiteralPath $fixture.Memory -Force
            [void](New-Item -ItemType SymbolicLink -Path $fixture.Memory -Target $outside -ErrorAction Stop)
            {& $fixture.Script}|Should -Throw '*must be a regular non-reparse file*'
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($outside))|Should -BeExactly ([Convert]::ToBase64String($outsideBefore))
        }

        It 'UnitT09_rejects_a_Unix_symlink_in_a_shared_reference_target_ancestor' {
            $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-ancestor-symlink')
            $linkedAncestor=Join-Path $fixture.Root 'skills/manage-ai-memory';$outside=Join-Path $TestDrive 'outside-ancestor-symlink'
            [void](New-Item -ItemType Directory -Path (Join-Path $outside 'references') -Force)
            Remove-Item -LiteralPath $linkedAncestor -Recurse -Force
            [void](New-Item -ItemType SymbolicLink -Path $linkedAncestor -Target $outside -ErrorAction Stop)
            {& $fixture.Script}|Should -Throw '*linked or non-directory ancestor*'
        }
    }

    if($IsWindows){
        It 'UnitT11_does_not_delete_existing_files_when_Windows_FileShare_blocks_a_shared_reference_write' {
            $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-Windows-write-failure')
            $before=@{}
            foreach($file in Get-ChildItem -LiteralPath $fixture.Root -Recurse -File){$before[[IO.Path]::GetRelativePath($fixture.Root,$file.FullName)]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))}
            $writeBlocker=[IO.File]::Open($fixture.Memory,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try{{& $fixture.Script}|Should -Throw}finally{$writeBlocker.Dispose()}
            $afterFiles=@(Get-ChildItem -LiteralPath $fixture.Root -Recurse -File)
            @($afterFiles|ForEach-Object{[IO.Path]::GetRelativePath($fixture.Root,$_.FullName)}|Sort-Object)|Should -Be @($before.Keys|Sort-Object)
            foreach($file in $afterFiles){[Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))|Should -BeExactly $before[[IO.Path]::GetRelativePath($fixture.Root,$file.FullName)]}
        }
    }else{
        It 'UnitT11_does_not_delete_existing_files_when_the_Unix_writer_seam_injects_a_partial_failure' {
            $fixture=New-SharedReferenceRepositoryFixture -Root (Join-Path $TestDrive 'shared-reference-Unix-write-failure')
            $before=@{}
            foreach($file in Get-ChildItem -LiteralPath $fixture.Root -Recurse -File){$before[[IO.Path]::GetRelativePath($fixture.Root,$file.FullName)]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))}
            Get-Command Invoke-SGSharedReferenceWriterTestSeam -CommandType Function -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
            $global:SGSharedReferenceWriterFailurePath=[IO.Path]::GetFullPath($fixture.Memory)
            function global:Invoke-SGSharedReferenceWriterTestSeam {
                param([string]$Path,[byte[]]$Bytes)
                if([IO.Path]::GetFullPath($Path)-cne$global:SGSharedReferenceWriterFailurePath){throw 'Unexpected shared-reference writer seam path.'}
                $partialLength=[Math]::Max(1,[Math]::Floor($Bytes.Length/2))
                [IO.File]::WriteAllBytes($Path,$Bytes[0..($partialLength-1)])
                throw 'Injected Unix shared-reference writer failure.'
            }
            try{{& $fixture.Script}|Should -Throw '*Injected Unix shared-reference writer failure*'}finally{
                Remove-Item -LiteralPath Function:\Invoke-SGSharedReferenceWriterTestSeam -Force
                Remove-Variable SGSharedReferenceWriterFailurePath -Scope Global -Force
            }
            Get-Command Invoke-SGSharedReferenceWriterTestSeam -CommandType Function -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Variable SGSharedReferenceWriterFailurePath -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            $afterFiles=@(Get-ChildItem -LiteralPath $fixture.Root -Recurse -File)
            @($afterFiles|ForEach-Object{[IO.Path]::GetRelativePath($fixture.Root,$_.FullName)}|Sort-Object)|Should -Be @($before.Keys|Sort-Object)
            [IO.File]::ReadAllBytes($fixture.Memory).Length|Should -BeLessThan $fixture.SourceBytes.Length
            foreach($file in @($afterFiles|Where-Object{$_.FullName-cne$fixture.Memory})){
                [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))|Should -BeExactly $before[[IO.Path]::GetRelativePath($fixture.Root,$file.FullName)]
            }
        }
    }

    # Scenario: One connected record target is available and an ordinary remember request is authorized.
    # Purpose: Prevent an unnecessary role probe or repeated permission question.
    It 'UnitT10_uses_one_connected_record_target_without_role_or_repeat_authorization' {
        $script:Contract.schemaVersion | Should -Be 5
        $script:Contract.targetResolution.uniqueConnectedPurposeMatchIsDefault | Should -BeTrue
        $script:Contract.authority.ordinaryAuthorizedOperationNeedsRoleProbe | Should -BeFalse
        $script:Contract.authority.ordinaryAuthorizedOperationNeedsRepeatedConfirmation | Should -BeFalse
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC01')[0]
        $case.expected.roleProbeCount | Should -Be 0
        $case.expected.repeatAuthorizationQuestionCount | Should -Be 0
    }

    # Scenario: An inference is repeated or assigned high confidence without direct evidence.
    # Purpose: Preserve the distinction between a candidate and a confirmed proposition.
    It 'UnitT20_keeps_inference_pending_until_explicit_or_direct_confirmation' {
        @($script:Contract.confirmation.confirmedBy) | Should -Be @('explicit-user-confirmation', 'direct-authoritative-evidence')
        @($script:Contract.confirmation.insufficientByThemselves) | Should -Contain 'repeated-citation'
        @($script:Contract.confirmation.insufficientByThemselves) | Should -Contain 'high-confidence-score'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC06')[0]
        $case.expected.status | Should -Be 'Pending'
        $case.expected.confidence | Should -Be 'Inferred'
        $agentCase = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC06')[0]
        $created = @($agentCase.fixedToolResponses | Where-Object tool -EQ 'records.create')[0].arguments
        $readback = @($agentCase.fixedToolResponses | Where-Object tool -EQ 'records.read')[0].response
        foreach ($field in @('key', 'scope', 'content', 'source', 'status', 'confidence')) {
            $readback.$field | Should -Be $created.$field
        }
    }

    # Scenario: Without a v5 rule, a user confirms the same words already stored as a Pending inference.
    # Purpose: Preserve the established legacy promotion workflow while v5 candidates promote in place.
    It 'UnitT25_preserves_legacy_same_content_promotion_after_confirmed_readback' {
        @($script:Contract.workflow.unchangedIdentityRequires) | Should -Be @('content', 'source', 'status', 'confidence')
        $script:Contract.workflow.legacyPendingPromotionAction | Should -Be 'save-confirmed-body-readback-then-supersede-pending'
        $operations = Get-Content -Raw (Join-Path $script:Skill 'references/memory-operations.md')
        $operations | Should -Match 'Without a v5 rule, retain the established legacy candidate workflow'
        $case = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC07')[0]
        (Get-OptionalProperty -InputObject $case -Name 'writeRule') | Should -BeNullOrEmpty
        (Get-OptionalProperty -InputObject $case.legacyPlacement -Name 'source') | Should -BeExactly 'configured-v4-memory-area'
        @($case.fixedToolResponses | ForEach-Object tool) | Should -Be @('records.search','records.read','records.search','records.create','records.read','records.update','records.read')
        $pending = $case.fixedToolResponses[1].response
        $confirmed = $case.fixedToolResponses[4].response
        $pending.content | Should -Be $confirmed.content
        $pending.status | Should -Be 'Pending'
        $confirmed.status | Should -Be 'Active'
        $confirmed.confidence | Should -Be 'Confirmed'
        $case.fixedToolResponses[5].arguments.locator | Should -Be $pending.locator
        $case.fixedToolResponses[6].response.status | Should -Be 'Superseded'
        $case.fixedToolResponses[6].response.source | Should -Be $pending.source
        $oracle = Get-OptionalProperty -InputObject $case -Name 'oracle'
        $expected = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $oracle -Name 'expected') -Name 'unrelatedInferenceUnchanged'
        $expected | Should -BeTrue
    }

    # Scenario: The index has no row for a key whose body is already present.
    # Purpose: Preserve the SYP-257 same-key body check and index-only repair.
    It 'UnitT30_checks_body_after_index_miss_and_repairs_only_index' {
        $script:Contract.workflow.sameKeyAbsenceRequires | Should -Be 'verified-body-destination-result'
        $script:Contract.workflow.unchangedAction | Should -Be 'skip-duplicate'
        $script:Contract.workflow.indexMissAction | Should -Be 'check-body-destination'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC10')[0]
        $case.expected.bodyCreateCount | Should -Be 0
        $case.expected.indexRepairCount | Should -Be 1
    }

    # Scenario: A verified Pending body is added to an index that treats Pending as non-current.
    # Purpose: Prevent an inferred candidate from superseding current memory or becoming current navigation.
    It 'UnitT35_uses_verified_body_status_for_the_new_index_row' {
        $script:Contract.index.nonCurrentStates | Should -Contain 'Pending'
        $script:Contract.workflow.pendingCandidateAction.existingActiveBody | Should -Be 'retain'
        $script:Contract.workflow.pendingCandidateAction.existingActiveIndexRow | Should -Be 'retain'
        $script:Contract.workflow.pendingCandidateAction.candidateIndexStatus | Should -Be 'Pending'
        $script:Contract.workflow.replacementReadiness | Should -Be 'confirmed-new-body-readback-before-retiring-old'
        $script:Contract.workflow.replacementAction | Should -Be 'preserve-old-as-Superseded-after-confirmed-replacement'
        $script:Contract.workflow.indexReplacementAction | Should -Be 'retain-old-row-as-Superseded-add-new-row-with-verified-body-status'
        $indexWorkflow = Get-Content -Raw (Join-Path $script:Skill 'references/index-workflow.md')
        $indexWorkflow | Should -Match 'Pending candidate'
        $indexWorkflow | Should -Match 'preserve the existing Active body and index row'
        $indexWorkflow | Should -Match 'new pointer whose Status matches the verified body'
        $indexWorkflow | Should -Not -Match 'new Active pointer'
    }

    # Scenario: Body save succeeds and index update fails.
    # Purpose: Preserve the body locator and resume without duplicating the body.
    It 'UnitT40_reports_partial_index_failure_and_resumes_index_only' {
        $script:Contract.workflow.partialIndexFailure.retainBody | Should -BeTrue
        $script:Contract.workflow.partialIndexFailure.resumeAction | Should -Be 'read-current-state-repair-index-only'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC12')[0]
        # The routing oracle stops at the failed write; the fixed transcript includes recovery.
        $case.expected.operationComplete | Should -BeFalse
        $case.expected.resumeBodyCreateCount | Should -Be 0
        $case.expected.resumeIndexRepairCount | Should -Be 1
        $transcript = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC12')[0]
        $transcript.oracle.expected.operationComplete | Should -BeTrue
    }

    # Scenario: Fixed write transcripts have an available target for each named destination.
    # Purpose: Keep acceptance fixtures executable under the target-resolution contract.
    It 'UnitT45_binds_each_fixed_write_destination_to_a_connected_target' {
        foreach ($id in @('AC05', 'AC11', 'AC13', 'AC14')) {
            $case = @($script:AgentInputs.scenarios | Where-Object id -EQ $id)[0]
            foreach ($call in @($case.fixedToolResponses | Where-Object { $_.tool -in @('files.save', 'records.create') })) {
                $expectedPurpose = if ($call.tool -eq 'files.save') { 'files' } else { 'records' }
                $targetProperty = $call.arguments.PSObject.Properties['target']
                if ($null -ne $targetProperty) {
                    $targetName = [string]$targetProperty.Value
                    $targetName | Should -Not -BeNullOrEmpty
                    $target = @($case.connectedTargets | Where-Object { $_.id -eq $targetName -and $_.purpose -eq $expectedPurpose -and $_.connected })
                    $target.Count | Should -Be 1
                } else {
                    @($case.connectedTargets | Where-Object { $_.purpose -eq $expectedPurpose -and $_.connected }).Count | Should -Be 1
                }
            }
        }
    }

    # Scenario: User requests a file and record in one authorized action while the source lacks hash metadata.
    # Purpose: Avoid a brand-specific permission gate and invented file evidence.
    It 'UnitT50_routes_records_and_files_by_purpose_without_inventing_metadata' {
        $script:Contract.targetResolution.differentPurposeTargetsAreNotAmbiguous | Should -BeTrue
        $script:Contract.files.inventMissingMetadata | Should -BeFalse
        $script:Contract.files.buildHistoryService | Should -BeFalse
        $both = @($script:Cases.cases | Where-Object id -EQ 'AC13')[0]
        $both.expected.brandPermissionQuestionCount | Should -Be 0
        $noHash = @($script:Cases.cases | Where-Object id -EQ 'AC14')[0]
        $noHash.expected.inventedHash | Should -BeFalse
        $noHash.expected.inventedVersion | Should -BeFalse
    }

    # Scenario: Old structured and pages data and embedded source instructions are encountered.
    # Purpose: Preserve legacy history without allowing retrieved data to expand authorization.
    It 'UnitT60_preserves_legacy_formats_and_content_trust_boundary' {
        @($script:Contract.legacy.recognizedContractVersions) | Should -Be @(3, 4)
        @($script:Contract.legacy.recognizedFormats) | Should -Be @('structured', 'pages')
        $script:Contract.legacy.unknownFormatAction | Should -Be 'stop-affected-write'
        $script:Contract.trustBoundary.embeddedActionDirectivesRequireIndependentAuthorization | Should -BeTrue
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC16')[0]
        $case.expected.executeEmbeddedDirective | Should -BeFalse
        $case.expected.publicShareCount | Should -Be 0
    }

    # Scenario: An installed agent encounters an existing v4 adopter file or trusted v3 mapping.
    # Purpose: Verify that runtime references, rather than test-only history, can resolve the old destination shape.
    It 'InterT65_resolves_existing_adopter_mappings_from_installed_references' {
        $legacyReference = Join-Path $script:Skill 'references/legacy-mappings.md'
        Test-Path -LiteralPath $legacyReference -PathType Leaf | Should -BeTrue
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Match 'references/legacy-mappings\.md'
        (Get-Content -Raw $legacyReference) | Should -Match 'CODEX_HOME'
        (Get-Content -Raw $legacyReference) | Should -Match 'legacy Codex mapping; it exists only for earlier Codex adopters'
        (Get-Content -Raw $legacyReference) | Should -Match 'Other AI hosts use an explicit configuration or trusted binding'
        (Get-Content -Raw $legacyReference) | Should -Match 'without an adopter file or `mode`'

        $legacy = $script:Contract.legacy
        $legacy.adopterConfig.codexFile | Should -Be 'memory-adopter.json'
        $legacy.adopterConfig.codexHomeEnvironment | Should -Be 'CODEX_HOME'
        $legacy.adopterConfig.codexHomeFallback | Should -Be '~/.codex'
        $legacy.structuredV3WithoutMode | Should -Be 'continue-trusted-established-mapping'
        foreach ($profileName in @('pages', 'structured')) {
            $profile = $script:LegacyAdopters.adopterProfiles.$profileName
            $profile.schemaVersion | Should -Be $legacy.v4AdopterConfigSchemaVersion
            $profile.mode | Should -Be $profileName
            foreach ($field in @($legacy.adopterConfig.requiredFields)) {
                @($profile.PSObject.Properties.Name) | Should -Contain $field
            }
            foreach ($field in @($legacy.adopterConfig.boundaryRequiredFields)) {
                [string]$profile.boundary.$field | Should -Not -BeNullOrEmpty
            }
            foreach ($areaName in @($legacy.adopterConfig.requiredAreas)) {
                $area = $profile.$areaName
                foreach ($field in @($legacy.adopterConfig.areaRequiredFields)) {
                    @($area.PSObject.Properties.Name) | Should -Contain $field
                }
                [string]$area.locator | Should -Not -BeNullOrEmpty
                if ($profileName -eq 'pages') { [string]$area.section | Should -Not -BeNullOrEmpty }
                $requiredMapping = if ($areaName -eq 'index') { @($legacy.indexRequiredFields) }
                    elseif ($profileName -eq 'structured') { @($legacy.structuredRequiredFields) }
                    else { @($legacy.pagesRequiredFields) }
                foreach ($field in $requiredMapping) {
                    [string]$area.fieldMapping.PSObject.Properties[$field].Value | Should -Not -BeNullOrEmpty
                }
            }
        }
    }

    # Scenario: Controlled evaluation inputs cover each agreed acceptance condition.
    # Purpose: Keep prompts, fixed tool responses, and decision oracles available for fresh-agent runs.
    It 'InterT70_provides_all_acceptance_scenarios_without_live_write_authority' {
        $script:Cases.schemaVersion | Should -Be 1
        $script:AgentInputs.fixtureVersion | Should -Be 2
        $script:AgentInputs.fixtureAuthorizesLiveWrites | Should -BeFalse
        $ids = @($script:AgentInputs.scenarios | ForEach-Object id)
        $ids | Should -Be @((1..30) | ForEach-Object { 'AC{0:d2}' -f $_ })
        foreach ($scenario in @($script:AgentInputs.scenarios)) {
            (Get-OptionalProperty -InputObject $scenario -Name 'scenario') | Should -Match '^Scenario: '
            (Get-OptionalProperty -InputObject $scenario -Name 'purpose') | Should -Match '^Purpose: '
            (Get-OptionalProperty -InputObject $scenario -Name 'userInput') | Should -Not -BeNullOrEmpty
            $writeRule = Get-OptionalProperty -InputObject $scenario -Name 'writeRule'
            if ($null -eq $writeRule) {
                $adopterConfiguration = Get-OptionalProperty -InputObject $scenario -Name 'adopterConfiguration'
                $writeRule = Get-OptionalProperty -InputObject $adopterConfiguration -Name 'writeRule'
            }
            if ($null -ne $writeRule) {
                $allowedRuleFields = @('source', 'granularity', 'parentLocator', 'pageNaming', 'fallback')
                @($writeRule.PSObject.Properties.Name | Where-Object { $_ -notin $allowedRuleFields }).Count | Should -Be 0 -Because "$($scenario.id) rule contains only placement policy"
                $fallback = Get-OptionalProperty -InputObject $writeRule -Name 'fallback'
                if ($null -ne $fallback) {
                    @($fallback.PSObject.Properties.Name | Where-Object { $_ -notin $allowedRuleFields }).Count | Should -Be 0 -Because "$($scenario.id) fallback contains only placement policy"
                }
            }
            $oracle = Get-OptionalProperty -InputObject $scenario -Name 'oracle'
            (Get-OptionalProperty -InputObject $oracle -Name 'expected') | Should -Not -BeNullOrEmpty
            $fixedToolResponses = @(Get-OptionalProperty -InputObject $scenario -Name 'fixedToolResponses')
            $fixedToolResponses.Count | Should -BeGreaterThan 0
            foreach ($call in $fixedToolResponses) {
                (Get-OptionalProperty -InputObject $call -Name 'tool') | Should -Not -BeNullOrEmpty
                (Get-OptionalProperty -InputObject $call -Name 'arguments') | Should -Not -BeNullOrEmpty
                (Get-OptionalProperty -InputObject $call -Name 'response') | Should -Not -BeNullOrEmpty
            }
        }
    }

    # Scenario: A workspace-wide target has no trusted or explicit placement rule and all index locators share one page.
    # Purpose: Stop the affected new-body write without treating index conventions or one connection as placement authority.
    It 'UnitT75_requires_a_complete_write_rule_before_creating_a_new_body' {
        $rules = $script:Contract.writeRules
        @($rules.requiredFields) | Should -Be @('granularity', 'parentLocator', 'pageNaming')
        @($rules.granularityValues) | Should -Be @('per-ticket', 'per-topic')
        $rules.missingOrInvalidAction | Should -BeExactly 'stop-affected-write-and-ask-user'
        $rules.writesWhenMissing | Should -Be 0
        $rules.uniqueConnectedTargetSuppliesPlacement | Should -BeFalse
        @($rules.forbiddenInferenceSources) | Should -Contain 'index-locator-convention'
        $case = @($script:Cases.cases | Where-Object id -EQ 'AC19')[0]
        $case.expected.writeCount | Should -Be 0
        $case.expected.appendToExistingPage | Should -BeFalse
        $case.expected.askUserForWriteRule | Should -BeTrue
        @($case.expected.missingFields) | Should -Be @('granularity', 'parentLocator', 'pageNaming')
        $case.expected.inferredFromIndexLocator | Should -BeFalse
        $scenario = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC19')[0]
        @($scenario.fixedToolResponses | Where-Object tool -In @('records.create', 'records.update')).Count | Should -Be 0
        $oracle = Get-OptionalProperty -InputObject $scenario -Name 'oracle'
        $expected = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $oracle -Name 'expected') -Name 'askUserForWriteRule'
        $expected | Should -BeTrue
    }

    # Scenario: Candidate rules include valid granularities and each specified invalid shape.
    # Purpose: Derive write-rule validation and the stop action only from the installed contract.
    It 'UnitT76_validates_write_rule_inputs_with_the_contract: <Name>' -ForEach @(
        @{ Name = 'valid per-ticket with title'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-memory-pages'; pageNaming = '{ticketKey} - {title}' }; Valid = $true; Missing = @() }
        @{ Name = 'valid per-topic'; Rule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-memory-pages'; pageNaming = 'Memory - {topic}' }; Valid = $true; Missing = @() }
        @{ Name = 'valid per-topic title only'; Rule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-memory-pages'; pageNaming = '{title}' }; Valid = $true; Missing = @() }
        @{ Name = 'valid ticket topic fallback'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-memory-pages'; pageNaming = '{ticketKey} - {title}'; fallback = [pscustomobject]@{ granularity = 'per-topic'; pageNaming = '{topic}' } }; Valid = $true; Missing = @() }
        @{ Name = 'valid adopter writeRule'; Rule = [pscustomobject]@{ schemaVersion = 1; writeRule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-memory-pages'; pageNaming = '{topic}' } }; Valid = $true; Missing = @() }
        @{ Name = 'missing parentLocator'; Rule = [pscustomobject]@{ granularity = 'per-topic'; pageNaming = 'Memory - {topic}' }; Valid = $false; Missing = @('parentLocator') }
        @{ Name = 'missing granularity'; Rule = [pscustomobject]@{ parentLocator = 'parent-memory-pages'; pageNaming = 'Memory - {topic}' }; Valid = $false; Missing = @('granularity') }
        @{ Name = 'unknown granularity'; Rule = [pscustomobject]@{ granularity = 'per-day'; parentLocator = 'parent-memory-pages'; pageNaming = 'Memory - {topic}' }; Valid = $false; Missing = @('granularity') }
        @{ Name = 'ticket placeholder missing'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-memory-pages'; pageNaming = 'Memory - {topic}' }; Valid = $false; Missing = @('pageNaming') }
        @{ Name = 'fallback on per-topic'; Rule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-memory-pages'; pageNaming = '{topic}'; fallback = [pscustomobject]@{ granularity = 'per-topic'; pageNaming = '{topic}' } }; Valid = $false; Missing = @('fallback') }
        @{ Name = 'nested fallback'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-memory-pages'; pageNaming = '{ticketKey}'; fallback = [pscustomobject]@{ granularity = 'per-topic'; pageNaming = '{topic}'; fallback = [pscustomobject]@{} } }; Valid = $false; Missing = @('fallback') }
        @{ Name = 'fallback per-ticket'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-memory-pages'; pageNaming = '{ticketKey}'; fallback = [pscustomobject]@{ granularity = 'per-ticket'; pageNaming = '{ticketKey}' } }; Valid = $false; Missing = @('fallback') }
        @{ Name = 'fallback uses ticketKey'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-memory-pages'; pageNaming = '{ticketKey}'; fallback = [pscustomobject]@{ granularity = 'per-topic'; pageNaming = '{topic} - {ticketKey}' } }; Valid = $false; Missing = @('fallback') }
        @{ Name = 'unknown placeholder'; Rule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-memory-pages'; pageNaming = '{topic} - {unknown}' }; Valid = $false; Missing = @('pageNaming') }
        @{ Name = 'null rule'; Rule = $null; Valid = $false; Missing = @('granularity', 'parentLocator', 'pageNaming') }
    ) {
        $result = Test-MemoryWriteRule -Rule $Rule -Contract $script:Contract.writeRules
        $result.Valid | Should -Be $Valid
        @($result.MissingFields) | Should -Be $Missing
        if ($Valid) {
            $result.Action | Should -BeExactly 'write-rule-valid'
        } else {
            $result.Action | Should -BeExactly 'stop-affected-write-and-ask-user'
        }
    }

    # Scenario: A per-ticket rule selects the ticket branch or its per-topic fallback from memory context.
    # Purpose: Resolve the permitted fallback without inventing a ticket key.
    It 'UnitT76a_resolves_ticket_and_topic_fallback_paths: <Name>' -ForEach @(
        @{ Name = 'ticket uses primary'; Context = [pscustomobject]@{ ticketKey = 'SYP-507'; title = 'Resolved title'; titleSource = 'tracker' }; ExpectedGranularity = 'per-ticket'; ExpectedParent = 'parent-ticket'; ExpectedValid = $true; ExpectedWrites = 1 }
        @{ Name = 'no ticket uses fallback'; Context = [pscustomobject]@{ topic = 'resolved-topic' }; ExpectedGranularity = 'per-topic'; ExpectedParent = 'parent-topic'; ExpectedValid = $true; ExpectedWrites = 1 }
    ) {
        $rule = [pscustomobject]@{
            granularity = 'per-ticket'; parentLocator = 'parent-ticket'; pageNaming = '{ticketKey} - {title}'
            fallback = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-topic'; pageNaming = '{topic}' }
        }
        $result = Resolve-MemoryWriteRule -Rule $rule -Contract $script:Contract.writeRules -Context $Context
        $result.Valid | Should -Be $ExpectedValid
        $result.Writes | Should -Be $ExpectedWrites
        $result.Rule.granularity | Should -BeExactly $ExpectedGranularity
        $result.ParentLocator | Should -BeExactly $ExpectedParent
    }

    # Scenario: A permitted per-topic fallback omits its optional parent locator.
    # Purpose: Inherit the primary parent exactly as the contract specifies.
    It 'UnitT76aa_defaults_the_fallback_parent_to_the_primary_parent' {
        $rule = [pscustomobject]@{
            granularity = 'per-ticket'; parentLocator = 'parent-shared'; pageNaming = '{ticketKey}'
            fallback = [pscustomobject]@{ granularity = 'per-topic'; pageNaming = '{topic}' }
        }
        $result = Resolve-MemoryWriteRule -Rule $rule -Contract $script:Contract.writeRules -Context ([pscustomobject]@{ topic = 'resolved-topic' })
        $result.Valid | Should -BeTrue
        $result.Rule.granularity | Should -BeExactly 'per-topic'
        $result.ParentLocator | Should -BeExactly 'parent-shared'
    }

    # Scenario: Required placement context is unavailable for an otherwise valid rule.
    # Purpose: Stop and ask with zero writes instead of guessing a ticket key or title.
    It 'UnitT76b_stops_resolution_when_required_context_is_unavailable: <Name>' -ForEach @(
        @{ Name = 'ticket missing without fallback'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-ticket'; pageNaming = '{ticketKey}' }; Context = $null; ExpectedAction = 'stop-affected-write-and-ask-user' }
        @{ Name = 'title unresolved'; Rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-ticket'; pageNaming = '{ticketKey} - {title}' }; Context = [pscustomobject]@{ ticketKey = 'SYP-507' }; ExpectedAction = 'stop-affected-write-and-ask-user' }
        @{ Name = 'topic title unresolved'; Rule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-topic'; pageNaming = '{title}' }; Context = $null; ExpectedAction = 'stop-affected-write-and-ask-user' }
        @{ Name = 'topic unresolved'; Rule = [pscustomobject]@{ granularity = 'per-topic'; parentLocator = 'parent-topic'; pageNaming = '{topic}' }; Context = $null; ExpectedAction = 'stop-affected-write-and-ask-user' }
    ) {
        $result = Resolve-MemoryWriteRule -Rule $Rule -Contract $script:Contract.writeRules -Context $Context
        $result.Valid | Should -BeFalse
        $result.Writes | Should -Be 0
        $result.Action | Should -BeExactly $ExpectedAction
        if ($Name -eq 'topic unresolved') {
            { Format-MemoryPageName -Rule $Rule -Context $Context } | Should -Throw
        }
    }

    # Scenario: A rule attempts to supply an authoritative ticket title or its provenance is untrusted.
    # Purpose: Resolve dynamic placement only from trusted memory context and stop with zero writes otherwise.
    It 'UnitT76bb_rejects_untrusted_or_missing_ticket_title_context: <Name>' -ForEach @(
        @{ Name = 'title missing from context'; RuleTitle = $null; Context = [pscustomobject]@{ ticketKey = 'SYP-507'; titleSource = 'tracker' } }
        @{ Name = 'title only in rule'; RuleTitle = 'Rule supplied title'; Context = [pscustomobject]@{ ticketKey = 'SYP-507'; titleSource = 'tracker' } }
        @{ Name = 'ticket title has untrusted source'; RuleTitle = $null; Context = [pscustomobject]@{ ticketKey = 'SYP-507'; title = 'Untrusted title'; titleSource = 'adopter' } }
    ) {
        $rule = [pscustomobject]@{ granularity = 'per-ticket'; parentLocator = 'parent-ticket'; pageNaming = '{ticketKey} - {title}' }
        if ($null -ne $RuleTitle) { $rule | Add-Member -NotePropertyName title -NotePropertyValue $RuleTitle }
        $result = Resolve-MemoryWriteRule -Rule $rule -Contract $script:Contract.writeRules -Context $Context
        $result.Valid | Should -BeFalse
        $result.Writes | Should -Be 0
        $result.Action | Should -BeExactly 'stop-affected-write-and-ask-user'
        { Format-MemoryPageName -Rule $rule -Context $Context } | Should -Throw
    }

    # Scenario: A v4 adopter contains both its legacy memory area and a top-level v5 writeRule.
    # Purpose: Give the v5 rule exclusive new-body placement authority and define conflicts fail closed.
    It 'ContractT76c_records_v5_precedence_fallback_title_and_conflicts' {
        $rules = $script:Contract.writeRules
        $rules.adopterConfigKey | Should -BeExactly 'writeRule'
        $rules.precedence | Should -BeExactly 'v5-write-rule-over-legacy-area-for-new-bodies'
        $rules.legacyAreaRoleWhenV5Present | Should -BeExactly 'read-and-existing-body-maintenance-only'
        $rules.conflictAction | Should -BeExactly 'stop-affected-write-and-ask-user'
        $rules.writesOnConflict | Should -Be 0
        $rules.invalidV5RuleFallsBackToLegacy | Should -BeFalse
        @($rules.sources) | Should -Be @('explicit-user-entry', 'trusted-adopter-configuration')
        @($rules.conflictKinds) | Should -Be @('incomplete-or-invalid-v5-rule', 'parent-outside-configured-boundary', 'parent-is-handoff-location', 'explicit-and-trusted-placement-disagree')
        @($rules.pageNamingPlaceholders) | Should -Contain '{title}'
        @($rules.granularityRequiredPlaceholder.'per-topic') | Should -Be @('{topic}', '{title}')
        $rules.fallback.primaryGranularity | Should -BeExactly 'per-ticket'
        $rules.fallback.granularity | Should -BeExactly 'per-topic'
        $rules.fallback.parentLocatorDefault | Should -BeExactly 'primary-rule-parentLocator'
        $rules.fallback.nestedFallbackAllowed | Should -BeFalse
        $rules.fallback.inventTicketKey | Should -BeFalse
        $rules.title.perTicketSource | Should -BeExactly 'authoritative-tracker-or-user'
        $rules.title.perTopicSource | Should -BeExactly 'topic-display-title'
        $rules.title.unresolvedAction | Should -BeExactly 'stop-affected-write-and-ask-user'
        $rules.unresolvedPlaceholderAction | Should -BeExactly 'stop-affected-write-and-ask-user'
        @($rules.fallbackForbiddenPlaceholders) | Should -Be @('{ticketKey}')
        $rules.existingPageWriteMode | Should -BeExactly 'append-separate-entry-preserve-others'
        @($script:Contract.legacy.adopterConfig.optionalFields) | Should -Contain 'writeRule'
    }

    # Scenario: A v5 rule governs inferred candidates as well as confirmed bodies.
    # Purpose: Keep candidates on the selected ticket or topic page and promote them in place.
    It 'ContractT76d_records_v5_candidate_placement_and_promotion' {
        $rules = $script:Contract.writeRules
        $rules.candidatePlacement | Should -BeExactly 'same-page-as-body'
        $rules.candidatePromotion | Should -BeExactly 'update-status-in-place-then-readback-before-index-update'
        @($rules.candidatePromotionReadbackRequires) | Should -Be @('Status: Active', 'Confidence: Confirmed', 'verified-confirmation-source')
        $rules.candidatePromotionReadbackFailureAction | Should -BeExactly 'stop-and-report-leave-index-pending'
        $rules.legacyInboxRoleWhenV5Present | Should -BeExactly 'read-and-existing-candidate-maintenance-only'
    }

    # Scenario: A trusted per-ticket rule has no existing ticket page under its configured parent.
    # Purpose: Create and verify the named page, then bind the index to that exact new locator.
    It 'UnitT77_creates_a_new_page_under_the_configured_parent_and_indexes_it' {
        $case = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC20')[0]
        @($case.PSObject.Properties.Name) | Should -Contain 'writeRule'
        @($case.writeRule.PSObject.Properties.Name) | Should -Contain 'parentLocator'
        $script:Contract.writeRules.indexMaintenanceRequiresConfiguredIndex | Should -BeTrue
        $configuredIndex = Get-OptionalProperty -InputObject $case -Name 'configuredIndex'
        $configuredIndexLocator = Get-OptionalProperty -InputObject $configuredIndex -Name 'locator'
        $configuredIndexLocator | Should -BeExactly 'memory-index'
        $calls = @($case.fixedToolResponses)
        $sameKeyIndex = -1
        $placementIndex = -1
        $createIndex = -1
        for ($indexOfCall = 0; $indexOfCall -lt $calls.Count; $indexOfCall++) {
            $call = $calls[$indexOfCall]
            $arguments = Get-OptionalProperty -InputObject $call -Name 'arguments'
            if ($call.tool -EQ 'records.search' -and (Get-OptionalProperty -InputObject $arguments -Name 'key') -EQ 'project:example.project:write-placement' -and (Get-OptionalProperty -InputObject $arguments -Name 'scope') -EQ 'example.project') {
                $sameKeyIndex = $indexOfCall
            }
            if ($call.tool -EQ 'records.search' -and (Get-OptionalProperty -InputObject $arguments -Name 'parent') -EQ $case.writeRule.parentLocator -and (Get-OptionalProperty -InputObject $arguments -Name 'title') -EQ 'Memory - SYP-507') {
                $placementIndex = $indexOfCall
            }
            if ($call.tool -EQ 'records.create') {
                $createIndex = $indexOfCall
            }
        }
        ($sameKeyIndex -ge 0) | Should -BeTrue
        $sameKeyResponse = Get-OptionalProperty -InputObject $calls[$sameKeyIndex] -Name 'response'
        @((Get-OptionalProperty -InputObject $sameKeyResponse -Name 'matches')).Count | Should -Be 0
        $sameKeyIndex | Should -BeLessThan $placementIndex
        $sameKeyIndex | Should -BeLessThan $createIndex
        $created = @($case.fixedToolResponses | Where-Object tool -EQ 'records.create')[0]
        @($created.arguments.PSObject.Properties.Name) | Should -Contain 'parent'
        @($created.arguments.PSObject.Properties.Name) | Should -Contain 'title'
        @($created.response.PSObject.Properties.Name) | Should -Contain 'locator'
        $created.arguments.parent | Should -BeExactly $case.writeRule.parentLocator
        $created.arguments.title | Should -BeExactly 'Memory - SYP-507'
        $readback = @($case.fixedToolResponses | Where-Object tool -EQ 'records.read')[0]
        @($readback.arguments.PSObject.Properties.Name) | Should -Contain 'locator'
        @($readback.response.PSObject.Properties.Name) | Should -Contain 'locator'
        $readback.arguments.locator | Should -BeExactly $created.response.locator
        $readback.response.locator | Should -BeExactly $created.response.locator
        foreach ($field in @('key', 'scope', 'content', 'source', 'status', 'confidence')) {
            @($created.arguments.PSObject.Properties.Name) | Should -Contain $field
            @($readback.response.PSObject.Properties.Name) | Should -Contain $field
            $readback.response.$field | Should -BeExactly $created.arguments.$field -Because "AC20 must read back $field before indexing"
        }
        $index = @($case.fixedToolResponses | Where-Object tool -EQ 'index.upsert')[0]
        (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $index -Name 'arguments') -Name 'index') | Should -BeExactly $configuredIndexLocator
        $indexArgumentFields = @('index', 'Topic', 'Scope', 'Memory Key', 'Locator', 'Target', 'Status')
        $indexResponseFields = @('Topic', 'Scope', 'Memory Key', 'Locator', 'Target', 'Status')
        @($index.arguments.PSObject.Properties.Name) | Should -Be $indexArgumentFields
        $index.arguments.Status | Should -BeExactly $readback.response.status
        $index.arguments.Locator | Should -BeExactly $created.response.locator
        $index.arguments.Target | Should -BeExactly $created.response.locator
        $indexReadback = @($case.fixedToolResponses | Where-Object tool -EQ 'index.read')[0]
        (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $indexReadback -Name 'arguments') -Name 'index') | Should -BeExactly $configuredIndexLocator
        @($indexReadback.response.PSObject.Properties.Name) | Should -Be $indexResponseFields
        foreach ($field in $indexResponseFields) {
            $indexReadback.response.$field | Should -BeExactly $index.arguments.$field -Because "AC20 index readback must match $field"
        }
        $oracle = Get-OptionalProperty -InputObject $case -Name 'oracle'
        $expectedReadback = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $oracle -Name 'expected') -Name 'readback'
        $expectedReadback | Should -BeTrue
        foreach ($scenario in @($script:AgentInputs.scenarios)) {
            $calls = @($scenario.fixedToolResponses)
            $createCalls = @($calls | Where-Object tool -EQ 'records.create')
            if ($createCalls.Count -eq 0) { continue }
            $rule = Get-OptionalProperty -InputObject $scenario -Name 'writeRule'
            if ($null -eq $rule) {
                $adopterConfiguration = Get-OptionalProperty -InputObject $scenario -Name 'adopterConfiguration'
                $rule = Get-OptionalProperty -InputObject $adopterConfiguration -Name 'writeRule'
            }
            $ruleSource = Get-OptionalProperty -InputObject $rule -Name 'source'
            if ($null -eq $rule -or $ruleSource -in @($script:Contract.writeRules.legacyExemptions)) { continue }
            $validation = Test-MemoryWriteRule -Rule $rule -Contract $script:Contract.writeRules -RuleSource $ruleSource
            $validation.Valid | Should -BeTrue -Because $scenario.id
            if (-not $validation.Valid) { continue }
            $memoryContext = Get-OptionalProperty -InputObject $scenario -Name 'memoryContext'
            $renderedName = Format-MemoryPageName -Rule $rule -Context $memoryContext
            $resolvedRule = Resolve-MemoryWriteRule -Rule $rule -Contract $script:Contract.writeRules -Context $memoryContext
            for ($indexOfCall = 0; $indexOfCall -lt $calls.Count; $indexOfCall++) {
                $call = $calls[$indexOfCall]
                if ($call.tool -ne 'records.create') { continue }
                @($call.arguments.PSObject.Properties.Name) | Should -Contain 'parent'
                @($call.arguments.PSObject.Properties.Name) | Should -Contain 'title'
                $call.arguments.parent | Should -BeExactly $resolvedRule.ParentLocator -Because $scenario.id
                $call.arguments.title | Should -BeExactly $renderedName -Because $scenario.id
                $indexOfCall | Should -BeGreaterThan 0 -Because "$($scenario.id) needs a placement lookup before creation"
                $placementLookup = $calls[$indexOfCall - 1]
                $placementLookup.tool | Should -BeExactly 'records.search' -Because $scenario.id
                @($placementLookup.arguments.PSObject.Properties.Name) | Should -Contain 'parent'
                @($placementLookup.arguments.PSObject.Properties.Name) | Should -Contain 'title'
                $placementLookup.arguments.parent | Should -BeExactly $resolvedRule.ParentLocator -Because $scenario.id
                $placementLookup.arguments.title | Should -BeExactly $renderedName -Because $scenario.id
                @((Get-OptionalProperty -InputObject $placementLookup.response -Name 'matches')).Count | Should -Be 0 -Because $scenario.id
            }
        }
    }

    # Scenario: New bodies exercise precedence, invalid-rule, fallback, and boundary decisions in fixed transcripts.
    # Purpose: Keep every new placement branch executable and fail closed before writes on conflict.
    It 'UnitT77a_enforces_v5_precedence_and_conflict_scenarios: <Id>' -ForEach @(
        @{ Id = 'AC23'; ExpectedWrites = 2; ExpectedAsk = $false }
        @{ Id = 'AC24'; ExpectedWrites = 0; ExpectedAsk = $true }
        @{ Id = 'AC25'; ExpectedWrites = 2; ExpectedAsk = $false }
        @{ Id = 'AC26'; ExpectedWrites = 0; ExpectedAsk = $true }
    ) {
        $matchingScenarios = @($script:AgentInputs.scenarios | Where-Object id -EQ $Id)
        $matchingScenarios.Count | Should -Be 1
        if ($matchingScenarios.Count -ne 1) { return }
        $scenario = $matchingScenarios[0]
        $writeCalls = @($scenario.fixedToolResponses | Where-Object tool -In @('records.create', 'records.update', 'index.upsert'))
        $writeCalls.Count | Should -Be $ExpectedWrites
        [bool](Get-OptionalProperty -InputObject $scenario.oracle.expected -Name 'askUser') | Should -Be $ExpectedAsk
        if ($Id -eq 'AC23') {
            $legacyLocator = [string]$scenario.adopterConfiguration.memory.locator
            $rule = $scenario.adopterConfiguration.writeRule
            $memoryContext = Get-OptionalProperty -InputObject $scenario -Name 'memoryContext'
            $created = @($scenario.fixedToolResponses | Where-Object tool -EQ 'records.create')[0]
            $created.arguments.parent | Should -BeExactly $rule.parentLocator
            $created.arguments.title | Should -BeExactly (Format-MemoryPageName -Rule $rule -Context $memoryContext)
            @($scenario.fixedToolResponses | Where-Object { @($_.arguments.PSObject.Properties.Value) -contains $legacyLocator }).Count | Should -Be 0
            $scenario.oracle.expected.legacyMemoryWriteCount | Should -Be 0
        }
        if ($Id -eq 'AC25') {
            $created = @($scenario.fixedToolResponses | Where-Object tool -EQ 'records.create')[0]
            $created.arguments.parent | Should -BeExactly $scenario.writeRule.fallback.parentLocator
            $created.arguments.title | Should -BeExactly 'release-language'
        }
        if ($ExpectedWrites -gt 0) {
            $created = @($scenario.fixedToolResponses | Where-Object tool -EQ 'records.create')[0]
            $readback = @($scenario.fixedToolResponses | Where-Object tool -EQ 'records.read')[0]
            foreach ($field in @('key', 'scope', 'content', 'source', 'status', 'confidence')) {
                $readback.response.$field | Should -BeExactly $created.arguments.$field -Because "$Id must read back $field before indexing"
            }
            $index = @($scenario.fixedToolResponses | Where-Object tool -EQ 'index.upsert')[0]
            $writtenLocator = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $created -Name 'response') -Name 'locator'
            (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $index -Name 'arguments') -Name 'Locator') | Should -BeExactly $writtenLocator -Because "$Id must index the locator returned by records.create"
            (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $index -Name 'arguments') -Name 'Target') | Should -BeExactly $writtenLocator -Because "$Id must target the locator returned by records.create"
            $indexReadback = @($scenario.fixedToolResponses | Where-Object tool -EQ 'index.read')[0]
            foreach ($field in @('Topic', 'Scope', 'Memory Key', 'Locator', 'Target', 'Status')) {
                $indexReadback.response.$field | Should -BeExactly $index.arguments.$field -Because "$Id must read back index field $field"
            }
        }
    }

    # Scenario: A configured parent is a Handoff location, and a legacy pages target lacks adopter placement.
    # Purpose: Keep memory writes out of Handoffs and stop legacy pages writes without configuration.
    It 'UnitT78_keeps_memory_writes_out_of_handoff_locations_and_legacy_pages_without_config' {
        foreach ($id in @('AC21', 'AC22')) {
            $case = @($script:Cases.cases | Where-Object id -EQ $id)[0]
            $case.expected.writeCount | Should -Be 0
            $case.expected.askUser | Should -BeTrue
            $scenario = @($script:AgentInputs.scenarios | Where-Object id -EQ $id)[0]
            @($scenario.fixedToolResponses | Where-Object tool -In @('records.create', 'records.update')).Count | Should -Be 0
        }
        $script:Contract.writeRules.handoffBoundary.parentMayBeHandoffLocation | Should -BeFalse
        $script:Contract.writeRules.handoffBoundary.handoffLocationParentAction | Should -BeExactly 'stop-affected-write-and-ask-user'
        $script:Contract.writeRules.pagesFormatWithoutAdopterConfigAction | Should -BeExactly 'stop-affected-write-and-ask-user'
        $handoffScenario = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC21')[0]
        @($handoffScenario.PSObject.Properties.Name) | Should -Contain 'writeRule'
        @($handoffScenario.writeRule.PSObject.Properties.Name) | Should -Contain 'parentLocator'
        $handoffLocator = [string]$handoffScenario.writeRule.parentLocator
        foreach ($call in @($handoffScenario.fixedToolResponses)) {
            @($call.arguments.PSObject.Properties.Value) | Should -Not -Contain $handoffLocator
        }
        @($handoffScenario.fixedToolResponses | Where-Object tool -Like 'records.*').Count | Should -Be 0
        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) | Should -Match 'index Locator'
    }

    # Scenario: An installed agent needs operational write-placement guidance without test-only context.
    # Purpose: Keep the rule discoverable in every installed reference used for target and legacy resolution.
    It 'UnitT79_documents_write_placement_in_installed_references' {
        foreach ($relativePath in @('SKILL.md', 'references/memory-operations.md', 'references/index-workflow.md', 'references/legacy-mappings.md')) {
            $text = Get-Content -Raw (Join-Path $script:Skill $relativePath)
            $text | Should -Match 'per-ticket'
            $text | Should -Match '`writeRule`'
            $text | Should -Match '`\{title\}`'
            $text | Should -Match '(?i)fallback'
            $text | Should -Match '(?i)legacy'
            $text | Should -Match '(?i)new bod'
            $text | Should -Match '(?i)parent locator'
            $text | Should -Match '(?i)stop'
            $text | Should -Match '(?i)ask'
        }
    }

    # Scenario: Trusted v3 structured and configured v4 memory mappings predate v5 placement fields.
    # Purpose: Keep established adopters writable while unconfigured pages targets still stop and ask.
    It 'UnitT80_lets_trusted_legacy_mappings_create_without_v5_write_fields' {
        $rules = $script:Contract.writeRules
        @($rules.legacyExemptions) | Should -Be @('trusted-v3-structured-mapping', 'configured-v4-memory-area')
        $rules.indexMaintenanceRequiresConfiguredIndex | Should -BeTrue
        foreach ($source in @($rules.legacyExemptions)) {
            $result = Test-MemoryWriteRule -Rule $null -Contract $rules -RuleSource $source
            $result.Valid | Should -BeTrue -Because $source
            @($result.MissingFields).Count | Should -Be 0
            $result.Action | Should -BeExactly 'legacy-write-rule-valid'
        }
        $pagesWithoutAdopter = Test-MemoryWriteRule -Rule $null -Contract $rules
        $pagesWithoutAdopter.Valid | Should -BeFalse
        @($pagesWithoutAdopter.MissingFields) | Should -Be @('granularity', 'parentLocator', 'pageNaming')
        $pagesWithoutAdopter.Action | Should -BeExactly 'stop-affected-write-and-ask-user'
        $rules.pagesFormatWithoutAdopterConfigAction | Should -BeExactly $pagesWithoutAdopter.Action

        $operations = Get-Content -Raw (Join-Path $script:Skill 'references/memory-operations.md')
        $operations | Should -Match 'trusted v3 structured mapping'
        $operations | Should -Match 'index maintenance applies only when an index is configured'

        (Get-Content -Raw (Join-Path $script:Skill 'SKILL.md')) |
            Should -Match 'configured v4 `memory` area'
        (Get-Content -Raw (Join-Path $script:Skill 'references/index-workflow.md')) |
            Should -Match 'configured v4 `memory` area'
        (Get-Content -Raw (Join-Path $script:Skill 'references/legacy-mappings.md')) |
            Should -Match 'v4 adopter''s configured `memory` area'
    }

    # Scenario: A v4 adopter has legacy memory and inbox areas plus a v5 rule, and an inference needs placement.
    # Purpose: Write Pending candidates on the same selected page as bodies without calling legacy locators.
    It 'UnitT81_places_v5_candidates_on_the_selected_page: <Name>' -ForEach @(
        @{ Name = 'ticket page'; Id = 'AC27'; ExpectedPage = 'record://workspace/ticket-memory/SYP-507'; ExpectedTitle = 'SYP-507 - Candidate placement' }
        @{ Name = 'fallback topic page'; Id = 'AC28'; ExpectedPage = 'record://workspace/topic-memory/release-language'; ExpectedTitle = 'release-language' }
    ) {
        $scenario = @($script:AgentInputs.scenarios | Where-Object id -EQ $Id)[0]
        $calls = @($scenario.fixedToolResponses)
        $legacyLocators = @(
            [string](Get-OptionalProperty -InputObject $scenario.adopterConfiguration.memory -Name 'locator')
            [string](Get-OptionalProperty -InputObject $scenario.adopterConfiguration.inbox -Name 'locator')
        )
        foreach ($call in $calls) {
            $arguments = Get-OptionalProperty -InputObject $call -Name 'arguments'
            foreach ($legacyLocator in $legacyLocators) {
                @($arguments.PSObject.Properties.Value) | Should -Not -Contain $legacyLocator -Because "$Id must not call a legacy locator"
            }
        }

        $placement = @($calls | Where-Object {
            $_.tool -EQ 'records.search' -and
            (Get-OptionalProperty -InputObject $_.arguments -Name 'title') -EQ $ExpectedTitle
        })[0]
        @((Get-OptionalProperty -InputObject $placement.response -Name 'matches')).Count | Should -Be 1
        (Get-OptionalProperty -InputObject $placement.response.matches[0] -Name 'locator') | Should -BeExactly $ExpectedPage

        $append = @($calls | Where-Object tool -EQ 'records.update')[0]
        (Get-OptionalProperty -InputObject $append.arguments -Name 'locator') | Should -BeExactly $ExpectedPage
        (Get-OptionalProperty -InputObject $append.arguments -Name 'operation') | Should -BeExactly 'append-entry'
        foreach ($field in @('key', 'scope', 'content', 'source', 'status', 'confidence')) {
            @($append.arguments.PSObject.Properties.Name) | Should -Contain $field
        }
        $append.arguments.status | Should -BeExactly 'Pending'
        $append.arguments.confidence | Should -BeExactly 'Inferred'

        $readback = @($calls | Where-Object tool -EQ 'records.read')[0]
        $readback.arguments.locator | Should -BeExactly $append.response.locator
        foreach ($field in @('key', 'scope', 'content', 'source', 'status', 'confidence')) {
            $readback.response.$field | Should -BeExactly $append.arguments.$field -Because "$Id must read back $field"
        }

        $index = @($calls | Where-Object tool -EQ 'index.upsert')[0]
        $index.arguments.Status | Should -BeExactly 'Pending'
        $writtenLocator = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $append -Name 'response') -Name 'locator'
        (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $index -Name 'arguments') -Name 'Locator') | Should -BeExactly $writtenLocator -Because "$Id must index the locator returned by records.update"
        (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $index -Name 'arguments') -Name 'Target') | Should -BeExactly $writtenLocator -Because "$Id must target the locator returned by records.update"
        $indexReadback = @($calls | Where-Object tool -EQ 'index.read')[0]
        $indexReadback.response.Status | Should -BeExactly 'Pending'
        $indexReadback.response.Locator | Should -BeExactly $index.arguments.Locator
        $indexReadback.response.Target | Should -BeExactly $index.arguments.Target
    }

    # Scenario: The user confirms a Pending candidate already stored under a v5-selected ticket page.
    # Purpose: Update that entry and its index status in place without creating or moving a copy.
    It 'UnitT82_promotes_a_v5_candidate_in_place_before_updating_its_index' {
        $matchingScenarios = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC29')
        $matchingScenarios.Count | Should -Be 1
        if ($matchingScenarios.Count -ne 1) { return }
        $scenario = $matchingScenarios[0]
        $calls = @($scenario.fixedToolResponses)
        @($calls | Where-Object tool -EQ 'records.create').Count | Should -Be 0
        $legacyLocators = @(
            [string](Get-OptionalProperty -InputObject $scenario.adopterConfiguration.memory -Name 'locator')
            [string](Get-OptionalProperty -InputObject $scenario.adopterConfiguration.inbox -Name 'locator')
        )
        foreach ($call in $calls) {
            $arguments = Get-OptionalProperty -InputObject $call -Name 'arguments'
            foreach ($legacyLocator in $legacyLocators) {
                @($arguments.PSObject.Properties.Value) | Should -Not -Contain $legacyLocator
            }
        }

        @($calls | ForEach-Object tool) | Should -Be @('records.read', 'records.update', 'records.read', 'index.upsert', 'index.read')
        $calls.Count | Should -Be 5
        if ($calls.Count -ne 5) { return }
        $before = $calls[0]
        $update = $calls[1]
        $after = $calls[2]
        $trustedCandidate = Get-OptionalProperty -InputObject $scenario -Name 'trustedCandidateContext'
        $trustedCandidate | Should -Not -BeNullOrEmpty
        $beforeArguments = Get-OptionalProperty -InputObject $before -Name 'arguments'
        $beforeResponse = Get-OptionalProperty -InputObject $before -Name 'response'
        (Get-OptionalProperty -InputObject $beforeArguments -Name 'locator') | Should -BeExactly (Get-OptionalProperty -InputObject $trustedCandidate -Name 'locator')
        (Get-OptionalProperty -InputObject $beforeResponse -Name 'key') | Should -BeExactly (Get-OptionalProperty -InputObject $trustedCandidate -Name 'memoryKey')
        (Get-OptionalProperty -InputObject $beforeResponse -Name 'scope') | Should -BeExactly (Get-OptionalProperty -InputObject $trustedCandidate -Name 'scope')
        $update.arguments.locator | Should -BeExactly $before.arguments.locator
        $after.arguments.locator | Should -BeExactly $before.arguments.locator
        $before.response.status | Should -BeExactly 'Pending'
        $before.response.confidence | Should -BeExactly 'Inferred'
        $update.arguments.status | Should -BeExactly 'Active'
        $update.arguments.confidence | Should -BeExactly 'Confirmed'
        $after.response.status | Should -BeExactly 'Active'
        $after.response.confidence | Should -BeExactly 'Confirmed'
        $after.response.source | Should -BeExactly $update.arguments.source
        $expectedPromotionReadback = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $scenario -Name 'oracle') -Name 'expected') -Name 'promotionReadback'
        $after.response.status | Should -BeExactly (Get-OptionalProperty -InputObject $expectedPromotionReadback -Name 'status')
        $after.response.confidence | Should -BeExactly (Get-OptionalProperty -InputObject $expectedPromotionReadback -Name 'confidence')
        $after.response.source | Should -BeExactly (Get-OptionalProperty -InputObject $expectedPromotionReadback -Name 'source')

        $indexWrite = $calls[3]
        $indexReadback = $calls[4]
        $indexWrite.arguments.Status | Should -BeExactly 'Active'
        $indexWrite.arguments.Locator | Should -BeExactly $before.arguments.locator
        $indexWrite.arguments.Target | Should -BeExactly $before.arguments.locator
        $indexReadback.response.Status | Should -BeExactly 'Active'
        $indexReadback.response.Locator | Should -BeExactly $before.arguments.locator
    }

    # Scenario: A selected ticket page already contains an unrelated entry when a confirmed body is added.
    # Purpose: Append a separate entry, preserve the existing entry, and index only the new entry locator.
    It 'UnitT83_appends_to_an_existing_shared_page_without_overwriting_other_entries' {
        $scenario = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC30')[0]
        $calls = @($scenario.fixedToolResponses)
        @($calls | Where-Object tool -EQ 'records.create').Count | Should -Be 0
        $append = @($calls | Where-Object tool -EQ 'records.update')[0]
        $appendIndex = [array]::IndexOf($calls, $append)
        $sharedPageLocator = 'record://workspace/ticket-memory/SYP-507'
        $pageReads = @(
            for ($callIndex = 0; $callIndex -lt $calls.Count; $callIndex++) {
                $call = $calls[$callIndex]
                if ((Get-OptionalProperty -InputObject $call -Name 'tool') -EQ 'records.read' -and
                    (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $call -Name 'arguments') -Name 'locator') -EQ $sharedPageLocator) {
                    [pscustomobject]@{ Index = $callIndex; Call = $call }
                }
            }
        )
        $pageReads.Count | Should -BeGreaterOrEqual 2
        $preWritePageReads = @($pageReads | Where-Object Index -LT $appendIndex)
        $postWritePageReads = @($pageReads | Where-Object Index -GT $appendIndex)
        $preWritePageReads.Count | Should -BeGreaterThan 0
        $postWritePageReads.Count | Should -BeGreaterThan 0
        $pageBefore = $preWritePageReads[-1]
        $pageAfter = $postWritePageReads[0]
        $pageAfter.Index | Should -BeGreaterThan $appendIndex
        $beforeEntries = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $pageBefore.Call -Name 'response') -Name 'entries'
        $afterEntries = Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $pageAfter.Call -Name 'response') -Name 'entries'
        $unrelatedEntryLocator = 'record://workspace/ticket-memory/SYP-507#unrelated'
        $otherBefore = @($beforeEntries | Where-Object {
            (Get-OptionalProperty -InputObject $_ -Name 'locator') -EQ $unrelatedEntryLocator
        })[0]
        $appendArguments = Get-OptionalProperty -InputObject $append -Name 'arguments'
        $appendResponse = Get-OptionalProperty -InputObject $append -Name 'response'
        (Get-OptionalProperty -InputObject $appendArguments -Name 'operation') | Should -BeExactly 'append-entry'
        (Get-OptionalProperty -InputObject $appendArguments -Name 'locator') | Should -BeExactly $sharedPageLocator
        $newEntryLocator = Get-OptionalProperty -InputObject $appendResponse -Name 'locator'
        $newEntryLocator | Should -BeExactly 'record://workspace/ticket-memory/SYP-507#release-language'
        $entryRead = @($calls | Where-Object {
            (Get-OptionalProperty -InputObject $_ -Name 'tool') -EQ 'records.read' -and
            (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $_ -Name 'arguments') -Name 'locator') -EQ $newEntryLocator
        })[0]
        (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $entryRead -Name 'response') -Name 'locator') | Should -BeExactly $newEntryLocator
        $otherLocator = Get-OptionalProperty -InputObject $otherBefore -Name 'locator'
        $otherAfter = @($afterEntries | Where-Object {
            (Get-OptionalProperty -InputObject $_ -Name 'locator') -EQ $otherLocator
        })[0]
        $otherBefore | Should -Not -BeNullOrEmpty
        $otherAfter | Should -Not -BeNullOrEmpty
        $otherAfter | ConvertTo-Json -Compress | Should -BeExactly ($otherBefore | ConvertTo-Json -Compress)
        @($beforeEntries | Where-Object {
            (Get-OptionalProperty -InputObject $_ -Name 'locator') -EQ $newEntryLocator
        }).Count | Should -Be 0
        @($afterEntries | Where-Object {
            (Get-OptionalProperty -InputObject $_ -Name 'locator') -EQ $newEntryLocator
        }).Count | Should -Be 1
        $index = @($calls | Where-Object tool -EQ 'index.upsert')[0]
        $indexArguments = Get-OptionalProperty -InputObject $index -Name 'arguments'
        $configuredIndex = Get-OptionalProperty -InputObject $scenario -Name 'configuredIndex'
        (Get-OptionalProperty -InputObject $indexArguments -Name 'index') | Should -BeExactly (Get-OptionalProperty -InputObject $configuredIndex -Name 'locator')
        (Get-OptionalProperty -InputObject $indexArguments -Name 'Locator') | Should -BeExactly $newEntryLocator
        (Get-OptionalProperty -InputObject $indexArguments -Name 'Target') | Should -BeExactly $newEntryLocator
        $indexReadback = @($calls | Where-Object tool -EQ 'index.read')[0]
        $indexReadbackArguments = Get-OptionalProperty -InputObject $indexReadback -Name 'arguments'
        (Get-OptionalProperty -InputObject $indexReadbackArguments -Name 'index') | Should -BeExactly (Get-OptionalProperty -InputObject $configuredIndex -Name 'locator')
        foreach ($field in @('Topic', 'Scope', 'Memory Key', 'Locator', 'Target', 'Status')) {
            (Get-OptionalProperty -InputObject (Get-OptionalProperty -InputObject $indexReadback -Name 'response') -Name $field) | Should -BeExactly (Get-OptionalProperty -InputObject $indexArguments -Name $field)
        }
        $script:Contract.writeRules.existingPageWriteMode | Should -BeExactly 'append-separate-entry-preserve-others'
    }
}
