Describe 'manage-notion-ai-memory Skill contract' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:SkillId = 'manage-notion-ai-memory'
        $script:SkillRoot = Join-Path $script:RepositoryRoot ".agents/skills/$($script:SkillId)"
        $script:ContractPath = Join-Path $script:SkillRoot 'references/notion-memory-contract.json'
        $script:Contract = Get-Content -LiteralPath $script:ContractPath -Raw | ConvertFrom-Json -Depth 20
        $script:RoutingCases = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/routing-cases.json'
        ) -Raw | ConvertFrom-Json -Depth 20
        $script:HandoffCases = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot 'fixtures/manage-notion-ai-memory/handoff-cases.json'
        ) -Raw | ConvertFrom-Json -Depth 20

        function Get-NativeActivityTime {
            param(
                [Parameter(Mandatory)] $Main,
                [Parameter(Mandatory)] [array] $Changes
            )

            $timestamps = [Collections.Generic.List[DateTimeOffset]]::new()
            $timestamps.Add([DateTimeOffset]$Main.last_edited_time)
            foreach ($change in $Changes) {
                $timestamps.Add([DateTimeOffset]$change.created_time)
                $timestamps.Add([DateTimeOffset]$change.last_edited_time)
            }
            return $timestamps | Sort-Object -Descending | Select-Object -First 1
        }

        function ConvertFrom-HandoffChangeValue {
            param(
                [Parameter(Mandatory)] $Change,
                [Parameter(Mandatory)] $Contract
            )

            $field = [string]$Change.field
            $encoding = $Contract.handoff.changeValueEncoding
            $stringFields = @($encoding.stringFields)
            $dateFields = @($encoding.dateFields)
            if ($field -cnotin @($stringFields + $dateFields)) {
                return [PSCustomObject]@{ Valid = $false; Value = $null }
            }

            try {
                $decodedValue = ConvertFrom-Json -InputObject ([string]$Change.value) -Depth 5 -ErrorAction Stop
            }
            catch {
                return [PSCustomObject]@{ Valid = $false; Value = $null }
            }

            if ($field -cin $stringFields) {
                if ($decodedValue -isnot [string]) {
                    return [PSCustomObject]@{ Valid = $false; Value = $null }
                }
                if ($field -ceq 'Lifecycle' -and $decodedValue -cnotin @($Contract.handoff.lifecycleStates)) {
                    return [PSCustomObject]@{ Valid = $false; Value = $null }
                }
                if ($field -ceq 'Work State' -and $decodedValue -cnotin @($Contract.handoff.workStates)) {
                    return [PSCustomObject]@{ Valid = $false; Value = $null }
                }
                return [PSCustomObject]@{ Valid = $true; Value = $decodedValue }
            }

            if ($null -eq $decodedValue) {
                return [PSCustomObject]@{ Valid = $true; Value = $null }
            }
            $rfc3339Pattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$'
            if ($decodedValue -isnot [string] -or $decodedValue -cnotmatch $rfc3339Pattern) {
                return [PSCustomObject]@{ Valid = $false; Value = $null }
            }
            $parsedDate = [DateTimeOffset]::MinValue
            $isDate = [DateTimeOffset]::TryParse(
                $decodedValue,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$parsedDate
            )
            return [PSCustomObject]@{ Valid = $isDate; Value = $decodedValue }
        }

        function Get-UnmergedChangeFingerprint {
            param([Parameter(Mandatory)] [AllowEmptyCollection()] [array] $Changes)

            $changeTokens = @(
                $Changes |
                    ForEach-Object {
                        $effectiveTime = @(
                            [DateTimeOffset]$_.created_time,
                            [DateTimeOffset]$_.last_edited_time
                        ) | Sort-Object -Descending | Select-Object -First 1
                        '{0}|{1}|{2}|{3}' -f $_.id, $_.field, $_.value, $effectiveTime.ToUniversalTime().Ticks
                    } |
                    Sort-Object
            )
            return $changeTokens -join ';;'
        }

        function Get-HandoffSnapshotFingerprint {
            param([Parameter(Mandatory)] $Snapshot)

            return '{0}::{1}' -f (
                ([DateTimeOffset]$Snapshot.mainLastEditedTime).ToUniversalTime().Ticks
            ), (Get-UnmergedChangeFingerprint -Changes @($Snapshot.unmergedChanges))
        }

        function Get-HandoffRevalidationAction {
            param(
                [Parameter(Mandatory)] $Case,
                [Parameter(Mandatory)] $Contract
            )

            $baseline = Get-HandoffSnapshotFingerprint -Snapshot $Case.baseline
            $observed = Get-HandoffSnapshotFingerprint -Snapshot $Case.observed
            if ($baseline -ceq $observed) {
                return 'continue'
            }
            if ([int]$Case.retryCount -lt [int]$Contract.handoff.mergeProtocol.maxRevalidationRetries) {
                return [string]$Contract.handoff.mergeProtocol.onConcurrentMutation
            }
            return [string]$Contract.handoff.mergeProtocol.onRetryLimit
        }

        function Get-HandoffPostUpdateAction {
            param(
                [Parameter(Mandatory)] $Case,
                [Parameter(Mandatory)] $Contract
            )

            $mainMatches = ($Case.expectedMainFields | ConvertTo-Json -Compress) -ceq (
                $Case.observedMainFields | ConvertTo-Json -Compress
            )
            $changesMatch = (Get-UnmergedChangeFingerprint -Changes @($Case.baselineUnmergedChanges)) -ceq (
                Get-UnmergedChangeFingerprint -Changes @($Case.observedUnmergedChanges)
            )
            if ($mainMatches -and $changesMatch) {
                return 'mark-verified-records-merged'
            }
            if ([int]$Case.retryCount -lt [int]$Contract.handoff.mergeProtocol.maxRevalidationRetries) {
                return [string]$Contract.handoff.mergeProtocol.onConcurrentMutation
            }
            return [string]$Contract.handoff.mergeProtocol.onRetryLimit
        }

        function Resolve-HandoffFixture {
            param([Parameter(Mandatory)] $Case)

            $state = [ordered]@{}
            foreach ($property in $Case.main.fields.PSObject.Properties) {
                $state[$property.Name] = $property.Value
            }
            $pendingChanges = @(
                $Case.changes |
                    Where-Object { -not [bool]$_.merged } |
                    ForEach-Object {
                        [PSCustomObject]@{
                            Change = $_
                            EffectiveTime = @(
                                [DateTimeOffset]$_.created_time,
                                [DateTimeOffset]$_.last_edited_time
                            ) | Sort-Object -Descending | Select-Object -First 1
                        }
                    } |
                    Sort-Object EffectiveTime
            )
            $validatedChanges = @(
                $pendingChanges |
                    ForEach-Object {
                        $decoded = ConvertFrom-HandoffChangeValue -Change $_.Change -Contract $script:Contract
                        [PSCustomObject]@{
                            Change = $_.Change
                            EffectiveTime = $_.EffectiveTime
                            Valid = [bool]$decoded.Valid
                            DecodedValue = $decoded.Value
                        }
                    }
            )
            $invalidChangeIds = @(
                $validatedChanges |
                    Where-Object { -not $_.Valid } |
                    ForEach-Object { [string]$_.Change.id }
            )
            $validChanges = @($validatedChanges | Where-Object { $_.Valid })
            $collisionGroups = @(
                $validChanges |
                    Group-Object {
                        '{0}|{1}' -f $_.Change.field, $_.EffectiveTime.ToUniversalTime().Ticks
                    } |
                    Where-Object { $_.Count -gt 1 }
            )
            $collisionIds = [Collections.Generic.List[string]]::new()
            $collisionFields = [Collections.Generic.List[string]]::new()
            foreach ($collisionGroup in $collisionGroups) {
                foreach ($collisionChange in $collisionGroup.Group) {
                    $collisionIds.Add([string]$collisionChange.Change.id)
                    $collisionFields.Add([string]$collisionChange.Change.field)
                }
            }
            $replayableChanges = @(
                $validChanges | Where-Object { [string]$_.Change.id -cnotin $collisionIds }
            )
            foreach ($pendingChange in $replayableChanges) {
                $state[[string]$pendingChange.Change.field] = $pendingChange.DecodedValue
            }

            return [PSCustomObject]@{
                Fields = $state
                AppliedChangeIds = @($replayableChanges | ForEach-Object { [string]$_.Change.id })
                CollisionFields = [string[]]@($collisionFields | Sort-Object -Unique)
                InvalidChangeIds = [string[]]$invalidChangeIds
                LastActivity = Get-NativeActivityTime -Main $Case.main -Changes @($Case.changes)
            }
        }
    }

    # Scenario: The new Skill is installed from Skill-General as an opt-in Notion capability.
    # Purpose: Keep source ownership, profile routing, and connector requirements self-consistent.
    It 'InterT10_declares_the_Skill_catalog_profile_and_interface_metadata' {
        $catalog = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'catalog/skills-catalog.json') -Raw |
            ConvertFrom-Json -Depth 20
        $skill = @($catalog.skills | Where-Object { $_.id -ceq $script:SkillId })
        $profile = @($catalog.profiles | Where-Object { $_.id -ceq 'ai-memory' })

        $skill.Count | Should -Be 1
        $skill[0].group | Should -Be 'knowledge-management'
        @($skill[0].profiles) | Should -Be @('ai-memory')
        $skill[0].source.path | Should -Be ".agents/skills/$($script:SkillId)"
        $skill[0].lifecycle.status | Should -Be 'active'
        @($skill[0].compatibility.requiredCapabilities).Count | Should -Be 1
        $skill[0].compatibility.requiredCapabilities[0].kind | Should -Be 'connector'
        $skill[0].compatibility.requiredCapabilities[0].id | Should -Be 'notion'
        $skill[0].compatibility.requiredCapabilities[0].state | Should -Be 'configured'
        $profile.Count | Should -Be 1
        $profile[0].default | Should -BeFalse
        @($profile[0].includes) | Should -Be @($script:SkillId)

        $openAiYaml = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'agents/openai.yaml') -Raw
        $openAiYaml | Should -Match ([regex]::Escape("`$$($script:SkillId)"))
        $openAiYaml | Should -Match '(?m)^\s*allow_implicit_invocation:\s*true\s*$'
    }

    # Scenario: An agent must distinguish Handoff lifecycle, work state, and memory/content state.
    # Purpose: Prevent ambiguous status reuse and forbidden custom activity or revision properties.
    It 'UnitT20_declares_exact_schema_and_state_boundaries' {
        $contract = Get-Content -LiteralPath $script:ContractPath -Raw | ConvertFrom-Json -Depth 20

        $contract.schemaVersion | Should -Be 2
        @($contract.handoff.snapshotFields) | Should -Be @('Intent', 'Scope', 'Current', 'Source')
        @($contract.handoff.lifecycleStates) | Should -Be @('Active', 'Archived')
        @($contract.handoff.workStates) | Should -Be @(
            'Running',
            'Awaiting Review',
            'Interrupted',
            'Blocked',
            'Failed'
        )
        @($contract.memory.contentStates) | Should -Be @('Active', 'Superseded', 'Pending', 'Archived')
        @($contract.handoff.forbiddenWorkStates) | Should -Be @('Completed', 'Awaiting Input')
        @($contract.handoff.forbiddenCustomProperties) | Should -Be @('Last Activity At', 'Revision')
        @($contract.handoff.nativeTimeFields) | Should -Be @('created_time', 'last_edited_time')
        $contract.handoff.inactivityDays | Should -Be 7
        $contract.handoff.changeValueEncoding.format | Should -Be 'json-scalar-text'
        $contract.handoff.changeValueEncoding.dateFormat | Should -Be 'RFC3339'
        $contract.handoff.changeValueEncoding.clearOptionalField | Should -Be 'null'
        $contract.handoff.mergeProtocol.mergedMeaning | Should -Be 'verified-in-main-snapshot'
        @($contract.workspace.authorizedRoles) | Should -Be @('Owner', 'Member')
        $contract.workspace.publicAccessAllowed | Should -BeFalse
        $contract.auxiliaryRecall.role | Should -Be 'cache-only'
        @($contract.auxiliaryRecall.systems) | Should -Contain 'ROAR'
        $contract.auxiliaryRecall.sensitiveContentAllowed | Should -BeFalse

        $mainPropertyNames = @($contract.handoff.mainProperties | ForEach-Object { $_.name })
        $changePropertyNames = @($contract.handoff.changeProperties | ForEach-Object { $_.name })
        $mainPropertyNames | Should -Be @(
            'Task Key',
            'Intent',
            'Scope',
            'Current',
            'Source',
            'Lifecycle',
            'Work State',
            'Keep Active Until'
        )
        $changePropertyNames | Should -Be @('Change', 'Handoff', 'Field', 'Value', 'Merged')
    }

    # Scenario: Automatic recall, explicit memory capture, Handoff creation, and risky operations are routed.
    # Purpose: Exercise positive and negative implicit-trigger boundaries without external writes.
    It 'UnitT30_routes_representative_requests_without_expanding_operational_scope' {
        $contract = $script:Contract
        $cases = @{}
        foreach ($case in $script:RoutingCases.cases) {
            $cases[[string]$case.id] = $case
        }

        $cases['quick-transient-answer'].createHandoff | Should -BeFalse
        $cases['quick-transient-answer'].recall | Should -BeFalse
        $cases['new-task-with-reusable-context'].recall | Should -BeTrue
        $cases['new-task-with-reusable-context'].createHandoff | Should -BeFalse
        $cases['multi-stage-external-tool-task'].createHandoff | Should -BeTrue
        $cases['explicit-remember-confirmed-fact'].memoryTarget | Should -Be 'AI Memory'
        $cases['explicit-remember-confirmed-fact'].requiresConfirmation |
            Should -Be $contract.authority.explicitRememberNotionWriteRequiresConfirmation
        $cases['inferred-memory-candidate'].memoryTarget | Should -Be 'AI Inbox'
        $cases['inferred-memory-candidate'].memoryStatus | Should -Be 'Pending'
        $cases['inferred-memory-candidate'].confidence | Should -Be 'Inferred'
        $cases['dropbox-file-write'].requiresConfirmation |
            Should -Be $contract.authority.dropboxMutationsRequireConfirmation
        $cases['bulk-notion-schema-change'].requiresConfirmation |
            Should -Be $contract.authority.schemaChangesRequireConfirmation
        $cases['bulk-notion-schema-change'].operationAllowed |
            Should -Be $contract.operationScope.allowsBulkNotionSchemaChanges
        $cases['existing-dropbox-memory-migration'].operationAllowed |
            Should -Be $contract.operationScope.allowsDropboxReorganizationOrMigration
        $cases['unrequested-live-e2e-write'].operationAllowed |
            Should -Be $contract.authority.unrequestedValidationWritesAllowed
        @($contract.PSObject.Properties.Name) | Should -Not -Contain 'currentPhase'
    }

    # Scenario: Notion access is missing or ambiguous, duplicate Handoffs exist, or Dropbox indexing fails.
    # Purpose: Verify fail-closed writes and explicit partial-failure reporting without external mutations.
    It 'UnitT35_fails_closed_for_missing_access_ambiguity_and_partial_writes' {
        $contract = $script:Contract
        $cases = @{}
        foreach ($case in $script:RoutingCases.cases) {
            $cases[[string]$case.id] = $case
        }

        foreach ($id in @('guest-notion-write', 'unknown-workspace-notion-write')) {
            $role = [string]$cases[$id].notionRole
            $roleEstablished = -not [string]::IsNullOrWhiteSpace($role)
            $writeAllowed = $roleEstablished -and $role -cin @($contract.workspace.authorizedRoles)
            $writeAllowed | Should -Be $cases[$id].notionWriteAllowed
            $cases[$id].continueIndependentLocalWork | Should -BeTrue
        }

        $duplicate = $cases['duplicate-main-handoff']
        ([int]$duplicate.matchCount -eq 0) | Should -Be $duplicate.createHandoff
        ([int]$duplicate.matchCount -gt 1) | Should -Be $duplicate.surfaceIntegrityConflict

        $missingKey = $cases['missing-stable-task-key']
        $hasStableKey = -not [string]::IsNullOrWhiteSpace([string]$missingKey.formalTaskKey) -or
            -not [string]::IsNullOrWhiteSpace([string]$missingKey.hostTaskIdentifier)
        $hasStableKey | Should -Be $missingKey.createHandoff
        (-not $hasStableKey) | Should -Be $missingKey.reportUniquenessUnavailable

        $partial = $cases['dropbox-write-index-failure']
        $operationComplete = [bool]$partial.dropboxWriteSucceeded -and [bool]$partial.notionIndexWriteSucceeded
        $operationComplete | Should -Be $partial.operationComplete
        (-not [bool]$partial.notionIndexWriteSucceeded) | Should -Be $partial.reportUnindexed

        $embedded = $cases['retrieved-record-with-embedded-tool-directive']
        $embedded.useAsEvidence | Should -Be $contract.trustBoundary.retrievedContentMaySupplyEvidence
        $embedded.executeEmbeddedDirectiveWithoutIndependentAuthorization | Should -Be (
            -not [bool]$contract.trustBoundary.embeddedActionDirectivesRequireIndependentAuthorization
        )
        $contract.trustBoundary.retrievedContentMayOverrideHigherPriorityInstructions | Should -BeFalse
    }

    # Scenario: Pending field-level changes contain both different-field and same-field updates.
    # Purpose: Prove the documented native-time replay rule and retain merged history for activity checks.
    It 'InterT40_reconstructs_each_latest_Handoff_from_main_and_unmerged_changes' {
        foreach ($case in $script:HandoffCases.mergeCases) {
            $actual = Resolve-HandoffFixture -Case $case
            ($actual.Fields | ConvertTo-Json -Compress) |
                Should -Be ($case.expected.fields | ConvertTo-Json -Compress)
            @($actual.AppliedChangeIds) | Should -Be @($case.expected.appliedChangeIds)
            @($actual.CollisionFields) | Should -Be @($case.expected.collisionFields)
            @($actual.InvalidChangeIds) | Should -Be @($case.expected.invalidChangeIds)
            $actual.LastActivity.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') |
                Should -Be ([DateTimeOffset]$case.expected.lastActivity).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    }

    # Scenario: The main Handoff or pending change set mutates during a merge attempt.
    # Purpose: Prevent a stale snapshot from being integrated or acknowledged as Merged.
    It 'InterT45_revalidates_the_merge_snapshot_before_and_after_main_updates' {
        $protocol = $script:Contract.handoff.mergeProtocol
        $protocol.revalidateBeforeMainUpdate | Should -BeTrue
        $protocol.revalidateAfterMainUpdateBeforeMarkMerged | Should -BeTrue
        @($protocol.preUpdateFingerprintFields) | Should -Be @(
            'main.last_edited_time',
            'change.id',
            'change.field',
            'change.value',
            'change.effective_native_time'
        )
        $protocol.postUpdateVerification.verifyExpectedMainFieldValues | Should -BeTrue
        $protocol.postUpdateVerification.revalidateUnmergedChangeFingerprint | Should -BeTrue

        foreach ($case in $script:HandoffCases.revalidationCases) {
            Get-HandoffRevalidationAction -Case $case -Contract $script:Contract |
                Should -Be $case.expectedAction
        }
        foreach ($case in $script:HandoffCases.postUpdateCases) {
            Get-HandoffPostUpdateAction -Case $case -Contract $script:Contract |
                Should -Be $case.expectedAction
        }
    }

    # Scenario: The scheduler evaluates inactivity with and without a future Keep Active Until date.
    # Purpose: Preserve the seven-day native-time archive rule without a custom Last Activity At field.
    It 'UnitT50_applies_the_seven_day_archive_rule' {
        foreach ($case in $script:HandoffCases.archiveCases) {
            $now = [DateTimeOffset]$case.now
            $lastActivity = [DateTimeOffset]$case.lastActivity
            $keepActiveUntil = if ($null -eq $case.keepActiveUntil) {
                $null
            }
            else {
                [DateTimeOffset]$case.keepActiveUntil
            }
            $protected = $null -ne $keepActiveUntil -and $keepActiveUntil -gt $now
            $inactiveForMoreThanSevenDays = ($now - $lastActivity).TotalDays -gt 7
            $actualLifecycle = if ($inactiveForMoreThanSevenDays -and -not $protected) {
                'Archived'
            }
            else {
                'Active'
            }

            $actualLifecycle | Should -Be $case.expectedLifecycle
        }
    }

    # Scenario: An agent loads only the detailed contract needed for memory or Handoff work.
    # Purpose: Enforce concise entry instructions and resolvable one-level progressive disclosure.
    It 'UnitT60_links_every_required_reference_from_the_Skill_entrypoint' {
        $skillFile = Join-Path $script:SkillRoot 'SKILL.md'
        $memoryReference = Join-Path $script:SkillRoot 'references/memory-operations.md'
        $handoffReference = Join-Path $script:SkillRoot 'references/handoff-operations.md'

        Test-Path -LiteralPath $skillFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:ContractPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $memoryReference -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $handoffReference -PathType Leaf | Should -BeTrue

        $skillText = Get-Content -LiteralPath $skillFile -Raw
        $skillText | Should -Match ([regex]::Escape('references/notion-memory-contract.json'))
        $skillText | Should -Match ([regex]::Escape('references/memory-operations.md'))
        $skillText | Should -Match ([regex]::Escape('references/handoff-operations.md'))
    }
}
