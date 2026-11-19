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

    # Scenario: A user confirms the same words already stored as a Pending inference.
    # Purpose: Preserve the inference as history and verify a separate confirmed body before retirement.
    It 'UnitT25_promotes_same_content_only_after_confirmed_readback' {
        @($script:Contract.workflow.unchangedIdentityRequires) | Should -Be @('content', 'source', 'status', 'confidence')
        $script:Contract.workflow.pendingPromotionAction | Should -Be 'save-confirmed-body-readback-then-supersede-pending'
        $operations = Get-Content -Raw (Join-Path $script:Skill 'references/memory-operations.md')
        $operations | Should -Match 'already held in a Pending body'
        $operations | Should -Match 'read it back, then mark the Pending body Superseded'
        $case = @($script:AgentInputs.scenarios | Where-Object id -EQ 'AC07')[0]
        @($case.fixedToolResponses | ForEach-Object tool) | Should -Be @('records.search','records.read','records.create','records.read','records.update','records.read')
        $pending = $case.fixedToolResponses[1].response
        $confirmed = $case.fixedToolResponses[3].response
        $pending.content | Should -Be $confirmed.content
        $pending.status | Should -Be 'Pending'
        $confirmed.status | Should -Be 'Active'
        $confirmed.confidence | Should -Be 'Confirmed'
        $case.fixedToolResponses[4].arguments.locator | Should -Be $pending.locator
        $case.fixedToolResponses[5].response.status | Should -Be 'Superseded'
        $case.fixedToolResponses[5].response.source | Should -Be $pending.source
        $case.oracle.expected.unrelatedInferenceUnchanged | Should -BeTrue
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
        $ids | Should -Be @((1..18) | ForEach-Object { 'AC{0:d2}' -f $_ })
        foreach ($scenario in @($script:AgentInputs.scenarios)) {
            $scenario.scenario | Should -Match '^Scenario: '
            $scenario.purpose | Should -Match '^Purpose: '
            $scenario.userInput | Should -Not -BeNullOrEmpty
            $scenario.oracle.expected | Should -Not -BeNullOrEmpty
            @($scenario.fixedToolResponses).Count | Should -BeGreaterThan 0
            foreach ($call in @($scenario.fixedToolResponses)) {
                $call.tool | Should -Not -BeNullOrEmpty
                $call.arguments | Should -Not -BeNullOrEmpty
                $call.response | Should -Not -BeNullOrEmpty
            }
        }
    }
}
