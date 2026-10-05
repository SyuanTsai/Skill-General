# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
if (-not ('Syp217.TestDerivedOrderedDictionary' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Collections.Specialized;
namespace Syp217 {
    public sealed class TestDerivedOrderedDictionary : OrderedDictionary { }
}
'@
}

Describe 'Handoff seven-day archive selection' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../skills/manage-task-handoff/scripts/HandoffRecordCore.psm1') -Force
        function New-ArchiveCommon {
            param(
                [string]$Scope = 'scope-a',
                [string]$Task = 'task-1',
                [string]$Revision = 'common-rev-1',
                [string]$LastActivity = '2026-09-20T00:00:00Z',
                [string]$WorkState = 'Awaiting Review'
            )
            return [ordered]@{
                'Authority Scope' = $Scope; 'Task Key' = $Task; Intent = 'finish'; Scope = 'fixture'
                Current = 'stable'; Source = 'fixture'; Lifecycle = 'Active'; 'Work State' = $WorkState
                Revision = $Revision; 'Last Activity At' = $LastActivity; 'Active Branches' = @()
            }
        }

        function New-ArchiveBranch {
            param(
                [string]$Scope = 'scope-a',
                [string]$Task = 'task-1',
                [string]$BranchId = 'branch-a',
                [string]$Revision = 'branch-rev-1',
                [long]$Generation = 2,
                [string]$LastActivity = '2026-09-25T00:00:00Z',
                [string]$WorkState = 'Awaiting Review',
                [string]$Outcome = 'Selected'
            )
            return [ordered]@{
                'Authority Scope' = $Scope; 'Task Key' = $Task; 'Branch ID' = $BranchId
                'Fork Point' = 'fork-revision-1'; 'Continuation Generation' = $Generation
                Current = 'reviewed'; Source = 'fixture'; Lifecycle = 'Active'; 'Work State' = $WorkState
                Revision = $Revision; 'Branch Outcome' = $Outcome; 'Last Activity At' = $LastActivity
            }
        }

        function Get-TestReviewedBranchContentSha256 {
            param([System.Collections.IDictionary]$Branch)
            $key = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f `
                [string]$Branch['Authority Scope'], [string]$Branch['Task Key'], [string]$Branch['Branch ID'],
                [string]$Branch['Continuation Generation'], [string]$Branch['Current'],
                [string]$Branch['Source'], [string]$Branch['Work State']
            $knownVectors = @{
                'scope-a|task-1|branch-a|2|reviewed|fixture|Awaiting Review' = '3f52f2321d0092cd83a93b4c1238244b851e8f81aec7768ad331e1e8606d7ec3'
                'scope-a|task-1|branch-a|2|reviewed|fixture|Running' = 'e3db1fc0d5e1ef28aed9b5194f66ee38fcd7fe12268cafb09b269911d085ebcb'
                'scope-a|task-1|branch-a|2|reviewed|fixture|Blocked' = '60da26b5fb5591c9d55f92eabeabf99d9363606afcfec50f918e0e53cb7e675a'
                'scope-a|task-b|branch-b|2|reviewed|fixture|Awaiting Review' = 'e6259936c7bfa40b9d986521020d6832c96515650d0a420f8a2211956449243a'
                'scope-a|task-1|branch-b|2|reviewed|fixture|Awaiting Review' = '91f3e153f9afb086b43f2e76af705235897ac2da93f088961b32ede52f212bea'
            }
            if (-not $knownVectors.ContainsKey($key)) { throw "No independent reviewed-content vector exists for '$key'." }
            return $knownVectors[$key]
        }

        $global:ArchiveCallerResultFactory = {
            param(
                [Parameter(Mandatory)][string]$OperationId,
                [ValidateSet('denied','unavailable','partial','unknown','readback-mismatch','readback-matched')]
                [string]$Status = 'readback-matched',
                [string]$Revision = 'source:opaque-revision-1'
            )
            $result = [ordered]@{
                SchemaVersion = 1; Operation = 'updateIfRevision'; OperationId = $OperationId; Status = $Status
                Capability = 'supported'; Identity = 'verified'; Permission = 'authorized'; AdapterVersion = 'fixture-v1'
                Revision = $Revision; Readback = 'not-attempted'; ReadbackRevision = $null
                Retryable = $false; PendingActions = @()
            }
            switch ($Status) {
                'denied' { $result.Permission = 'denied' }
                'unavailable' {
                    $result.Capability = 'unsupported'; $result.Identity = 'unknown'; $result.Permission = 'unknown'
                    $result.AdapterVersion = $null; $result.Revision = $null
                }
                'partial' {
                    $result.Readback = 'unknown'; $result.Retryable = $true; $result.PendingActions = @('readback')
                }
                'unknown' {
                    $result.Capability = 'unknown'; $result.Identity = 'unknown'; $result.Permission = 'unknown'
                    $result.AdapterVersion = $null; $result.Revision = $null; $result.Readback = 'unknown'
                    $result.Retryable = $true; $result.PendingActions = @('reconcile-same-operation')
                }
                'readback-mismatch' {
                    $result.Readback = 'mismatch'; $result.ReadbackRevision = 'source:opaque-revision-other'
                    $result.Retryable = $true; $result.PendingActions = @('readback')
                }
                'readback-matched' {
                    $result.Readback = 'matched'; $result.ReadbackRevision = $Revision
                }
            }
            return [pscustomobject]$result
        }.GetNewClosure()

        function global:New-ArchiveCallerResult {
            param(
                [Parameter(Mandatory)][string]$OperationId,
                [ValidateSet('denied','unavailable','partial','unknown','readback-mismatch','readback-matched')]
                [string]$Status = 'readback-matched',
                [string]$Revision = 'source:opaque-revision-1'
            )
            return (& $global:ArchiveCallerResultFactory -OperationId $OperationId -Status $Status -Revision $Revision)
        }

        function Add-ArchiveDecisionBinding {
            param([System.Collections.IDictionary]$Common, [System.Collections.IDictionary]$Branch)
            $Common['Decision Branch Bindings'] = @(
                [ordered]@{
                    branchId = [string]$Branch['Branch ID']
                    reviewedRevision = [string]$Branch['Revision']
                    reviewedContentSha256 = Get-TestReviewedBranchContentSha256 $Branch
                    continuationGeneration = [long]$Branch['Continuation Generation']
                    outcome = [string]$Branch['Branch Outcome']
                }
            )
        }

        function New-ArchiveJsonDecisionBinding {
            param([System.Collections.IDictionary]$Branch)
            $binding = [ordered]@{
                branchId = [string]$Branch['Branch ID']
                reviewedRevision = [string]$Branch['Revision']
                reviewedContentSha256 = Get-TestReviewedBranchContentSha256 $Branch
                continuationGeneration = [long]$Branch['Continuation Generation']
                outcome = [string]$Branch['Branch Outcome']
            }
            $json = ConvertTo-Json -InputObject $binding -Compress -Depth 5
            return ConvertFrom-Json -InputObject $json -AsHashtable -Depth 5
        }

        function New-ArchiveFinalizationFixture {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch
            $common['Revision'] = 'source:common@opaque/1'
            $branch['Revision'] = 'source:branch@opaque/1'
            $common['Active Branches'] = @('branch-a')
            $binding = [ordered]@{
                branchId = [string]$branch['Branch ID']
                reviewedRevision = [string]$branch['Revision']
                reviewedContentSha256 = Get-TestReviewedBranchContentSha256 $branch
                continuationGeneration = [long]$branch['Continuation Generation']
                outcome = [string]$branch['Branch Outcome']
            }
            $common['Decision Branch Bindings'] = @($binding)
            return [pscustomobject]@{ Common = $common; Branch = $branch; Binding = $binding }
        }

        function New-PendingArchiveCycleAction {
            param([string]$CycleOperationId = 'cycle-integrity')
            $fixture = New-ArchiveFinalizationFixture
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $pendingAction = { param($decision,$cursor,$operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial' }
            $result = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId $CycleOperationId -ArchiveAction $pendingAction
            return $result.Pending[0]
        }

        function Get-TestArchiveCycleOperationId {
            param([string]$CycleOperationId, $Cursor)
            $identity = [ordered]@{ CycleOperationId = $CycleOperationId; Cursor = $Cursor }
            $json = ConvertTo-Json -InputObject $identity -Compress -Depth 8
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $digest = [Convert]::ToHexString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant() }
            finally { $sha.Dispose() }
            return "${CycleOperationId}:archive:${digest}"
        }

        function Get-TestArchiveSelection {
            param(
                [object[]]$CommonRecords = @(),
                [object[]]$BranchRecords = @(),
                [string]$At = '2026-10-02T00:00:00Z',
                [bool]$InventoryComplete = $true
            )
            $now = [DateTimeOffset]::Parse($At, [Globalization.CultureInfo]::InvariantCulture)
            $clock = { $now }.GetNewClosure()
            $parameters = @{ CommonRecords = $CommonRecords; BranchRecords = $BranchRecords; Clock = $clock; InventoryComplete = $InventoryComplete }
            return Get-HandoffArchiveSelection @parameters
        }
    }

    # Scenario: the Core entrypoint receives a fixed UTC clock at the seven-day cutoff.
    # Purpose: prove the public selector returns a non-durable eligible branch decision and protects its indexed common parent.
    It 'UnitT30_selects_an_explicitly_decided_expired_branch_at_the_exact_seven_day_boundary' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)

        $selection.Durable | Should -BeFalse
        @($selection.Selected).Count | Should -Be 1
        $selection.Selected[0].Kind | Should -Be 'Branch'
        $selection.Selected[0].BranchId | Should -Be 'branch-a'
        $selection.Selected[0].Revision | Should -Be 'branch-rev-1'
        $selection.Selected[0].ContinuationGeneration | Should -Be 2
        @($selection.Protected | Where-Object Kind -eq 'Common').Count | Should -Be 1
        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'active-branch-index'
    }

    It 'UnitT31_accepts_the_exact_OrderedHashtable_map_produced_by_ConvertFrom_Json_AsHashtable_inside_a_Common_record' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        $binding = New-ArchiveJsonDecisionBinding -Branch $branch
        $binding.GetType().FullName | Should -Be 'System.Management.Automation.OrderedHashtable'
        $common['Decision Branch Bindings'] = @($binding)

        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)

        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'active-branch-index'
        @($selection.Selected | Where-Object Kind -eq 'Branch').Count | Should -Be 1
    }

    It 'UnitT32_rejects_an_unknown_OrderedDictionary_derived_map_nested_in_a_Common_record' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        $sourceBinding = New-ArchiveJsonDecisionBinding -Branch $branch
        $derivedBinding = [Syp217.TestDerivedOrderedDictionary]::new()
        foreach ($key in $sourceBinding.Keys) { $derivedBinding.Add($key, $sourceBinding[$key]) }
        $common['Decision Branch Bindings'] = @($derivedBinding)

        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)

        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'invalid-record-shape'
        ($selection.Protected | Where-Object Kind -eq 'Branch').Reason | Should -Be 'invalid-common-parent'
    }

    It 'UnitT33_rejects_a_ScriptBlock_nested_in_an_OrderedHashtable_Common_binding' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        $binding = New-ArchiveJsonDecisionBinding -Branch $branch
        $binding['reviewedRevision'] = { 'branch-rev-1' }
        $common['Decision Branch Bindings'] = @($binding)

        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)

        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'invalid-record-shape'
        ($selection.Protected | Where-Object Kind -eq 'Branch').Reason | Should -Be 'invalid-common-parent'
    }

    It 'UnitT34_selects_a_branch_when_opaque_review_revision_matches_exactly_and_remains_non_durable' {
        $fixture = New-ArchiveFinalizationFixture
        $selection = Get-TestArchiveSelection -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch)

        $selection.Durable | Should -BeFalse
        @($selection.Selected | Where-Object { $_.Kind -eq 'Branch' }).Count | Should -Be 1
        $selection.Selected[0].Revision | Should -BeExactly 'source:branch@opaque/1'
        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'active-branch-index'
    }

    It 'UnitT35_keeps_a_branch_protected_when_its_opaque_review_revision_is_stale' {
        $fixture = New-ArchiveFinalizationFixture
        $fixture.Branch['Revision'] = 'source:branch@opaque/2'
        $selection = Get-TestArchiveSelection -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch)
        ($selection.Protected | Where-Object Kind -eq 'Branch').Reason | Should -Be 'decision-revision-mismatch'
    }

    It 'UnitT36_rejects_branch_bindings_with_stale_content_generation_or_outcome' {
        $cases = @(
            [pscustomobject]@{ Name = 'reviewed content'; Field = 'reviewedContentSha256'; Value = '0' * 64; Expected = 'decision-content-mismatch' },
            [pscustomobject]@{ Name = 'continuation generation'; Field = 'continuationGeneration'; Value = 3L; Expected = 'decision-generation-mismatch' },
            [pscustomobject]@{ Name = 'outcome'; Field = 'outcome'; Value = 'Superseded'; Expected = 'decision-outcome-mismatch' }
        )
        foreach ($case in $cases) {
            $fixture = New-ArchiveFinalizationFixture
            $fixture.Binding[$case.Field] = $case.Value
            $selection = Get-TestArchiveSelection -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch)
            ($selection.Protected | Where-Object Kind -eq 'Branch').Reason | Should -Be $case.Expected -Because $case.Name
            @($selection.Selected | Where-Object Kind -eq 'Branch').Count | Should -Be 0 -Because $case.Name
        }
    }

    It 'UnitT37_does_not_let_a_valid_opaque_revision_binding_override_incomplete_inventory' {
        $fixture = New-ArchiveFinalizationFixture
        $selection = Get-TestArchiveSelection -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
            -InventoryComplete $false

        @($selection.Selected).Count | Should -Be 0
        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'inventory-incomplete'
        ($selection.Protected | Where-Object Kind -eq 'Branch').Reason | Should -Be 'inventory-incomplete'
    }

    # Scenario: a decided branch is one instant younger than seven days.
    # Purpose: make the expiry boundary inclusive without archiving early.
    It 'UnitT38_protects_a_decided_branch_just_before_the_seven_day_boundary' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch -LastActivity '2026-09-25T00:00:01Z'
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
        @($selection.Selected).Count | Should -Be 0
        ($selection.Protected | Where-Object Kind -eq 'Branch').Reason | Should -Be 'inactivity-period-not-reached'
    }

    # Scenario: material activity has aged beyond the configured default.
    # Purpose: prove a valid final decision permits selection after seven days.
    It 'UnitT39_selects_an_explicitly_decided_branch_older_than_seven_days' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch -LastActivity '2026-09-24T00:00:00Z'
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch) -At '2026-10-02T00:00:00Z'
        @($selection.Selected).Count | Should -Be 1
        $selection.Selected[0].Reason | Should -Be 'inactivity-expired'
    }

    # Scenario: the activity timestamp has a non-UTC offset but denotes the exact cutoff instant.
    # Purpose: compare DateTimeOffset instants rather than local clock text.
    It 'UnitT40_compares_timestamp_offsets_at_the_same_UTC_instant' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch -LastActivity '2026-10-01T19:00:00-05:00'
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch) -At '2026-10-09T00:00:00Z'
        @($selection.Selected).Count | Should -Be 1
    }

    # Scenario: timestamps are absent, malformed, or future-dated.
    # Purpose: keep each unverifiable branch protected.
    It 'UnitT41_protects_invalid_and_future_activity_timestamps' {
        foreach ($stamp in @($null, '', 'not-a-time', '2026-10-03T00:00:00Z')) {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch -LastActivity $stamp
            $common['Active Branches'] = @('branch-a')
            Add-ArchiveDecisionBinding -Common $common -Branch $branch
            $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
            @($selection.Selected).Count | Should -Be 0 -Because ([string]$stamp)
            @($selection.Protected | Where-Object Kind -eq 'Branch').Count | Should -Be 1
        }
    }

    # Scenario: a valid Keep Active Until is in the future, while another is malformed.
    # Purpose: fail closed for both an active retention window and unparseable retention metadata.
    It 'UnitT42_protects_future_and_invalid_Keep_Active_Until_values' {
        foreach ($keepUntil in @('2026-10-03T00:00:00Z', 'not-a-time')) {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch
            $branch['Keep Active Until'] = $keepUntil
            $common['Active Branches'] = @('branch-a')
            Add-ArchiveDecisionBinding -Common $common -Branch $branch
            $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
            @($selection.Selected).Count | Should -Be 0 -Because $keepUntil
        }
    }

    # Scenario: old branches are still running, blocked, or have no final bound decision.
    # Purpose: ensure age and stale outcome text cannot override active work or missing decision proof.
    It 'UnitT43_protects_running_blocked_and_undecided_branches' {
        foreach ($state in @('Running', 'Blocked')) {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch -WorkState $state
            $common['Active Branches'] = @('branch-a')
            Add-ArchiveDecisionBinding -Common $common -Branch $branch
            $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
            @($selection.Selected).Count | Should -Be 0 -Because $state
        }
        foreach ($outcome in @($null, '')) {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch -Outcome $outcome
            $common['Active Branches'] = @('branch-a')
            $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
            @($selection.Selected).Count | Should -Be 0 -Because 'outcome missing'
        }
    }

    # Scenario: an old outcome binding predates an explicit branch continuation or content change.
    # Purpose: reject stale decision evidence by branch revision, generation, outcome, and reviewed-content identity.
    It 'UnitT44_protects_stale_branch_revision_generation_outcome_and_content_bindings' {
        foreach ($change in @('revision', 'generation', 'outcome', 'content')) {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch
            $common['Active Branches'] = @('branch-a')
            Add-ArchiveDecisionBinding -Common $common -Branch $branch
            if ($change -eq 'revision') { $branch['Revision'] = 'branch-rev-2' }
            if ($change -eq 'generation') { $branch['Continuation Generation'] = 3 }
            if ($change -eq 'outcome') { $branch['Branch Outcome'] = 'Superseded' }
            if ($change -eq 'content') { $branch.Current = 'new work after decision' }
            $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
            @($selection.Selected).Count | Should -Be 0 -Because $change
        }
    }

    # Scenario: a common record is stale but has active, missing-from-index, or stale-index branches.
    # Purpose: keep common protected for every known active branch and every nonempty index.
    It 'UnitT45_protects_common_on_live_branch_or_any_active_index_residue' {
        $common = New-ArchiveCommon
        $common['Active Branches'] = @('branch-a')
        $selected = Get-TestArchiveSelection -CommonRecords @($common)
        ($selected.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'active-branch-index'

        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch -Outcome ''
        $live = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
        ($live.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'active-branch-missing-from-index'

        $common = New-ArchiveCommon
        $common['Active Branches'] = @('missing-branch')
        $stale = Get-TestArchiveSelection -CommonRecords @($common)
        ($stale.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'active-branch-index'
    }

    # Scenario: a stale common record has no active branch or index entries.
    # Purpose: permit seven-day common archival after its active-branch guard is clear.
    It 'UnitT46_selects_an_expired_common_with_an_empty_branch_index' {
        $common = New-ArchiveCommon -LastActivity '2026-09-24T00:00:00Z'
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -At '2026-10-02T00:00:00Z'
        @($selection.Selected).Count | Should -Be 1
        $selection.Selected[0].Kind | Should -Be 'Common'
        $selection.Selected[0].Reason | Should -Be 'inactivity-expired'
    }

    # Scenario: records have missing or duplicate scoped identity, revision, or continuation generation.
    # Purpose: protect snapshots that cannot support a stable conditional lifecycle update.
    It 'UnitT47_protects_invalid_and_duplicate_identities_revisions_and_generations' {
        foreach ($field in @('Authority Scope', 'Task Key', 'Revision', 'Continuation Generation')) {
            $common = New-ArchiveCommon
            $branch = New-ArchiveBranch
            $common['Active Branches'] = @('branch-a')
            Add-ArchiveDecisionBinding -Common $common -Branch $branch
            if ($field -eq 'Continuation Generation') { $branch[$field] = -1 }
            else { $branch[$field] = '' }
            $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch)
            @($selection.Selected).Count | Should -Be 0 -Because $field
        }

        $common = New-ArchiveCommon
        $branchA = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branchA
        $branchB = New-ArchiveBranch
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branchA, $branchB)
        @($selection.Selected).Count | Should -Be 0 -Because 'duplicate branch identity'

        $commonB = New-ArchiveCommon
        $selection = Get-TestArchiveSelection -CommonRecords @($common, $commonB) -BranchRecords @($branchA)
        @($selection.Selected).Count | Should -Be 0 -Because 'duplicate common identity'
    }

    # Scenario: a caller clock cannot be trusted unless it returns one DateTimeOffset.
    # Purpose: prevent invalid clocks from producing archive decisions.
    It 'UnitT48_protects_all_records_when_the_injected_clock_is_invalid' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $selection = Get-HandoffArchiveSelection -CommonRecords @($common) -BranchRecords @($branch) -Clock { 'not-a-DateTimeOffset' } -InventoryComplete $true
        @($selection.Selected).Count | Should -Be 0
        @($selection.Protected).Count | Should -Be 2
    }

    # Scenario: selection inspects a record but does not write or refresh it.
    # Purpose: keep the A result an injectable-clock, non-durable decision only.
    It 'UnitT49_calls_the_clock_once_and_leaves_records_unchanged' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $before = ConvertTo-Json -InputObject @($common, $branch) -Compress -Depth 50
        $clockState = [pscustomobject]@{
            Calls = 0
            Now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z', [Globalization.CultureInfo]::InvariantCulture)
        }
        $clock = { $clockState.Calls++; $clockState.Now }.GetNewClosure()
        $selection = Get-HandoffArchiveSelection -CommonRecords @($common) -BranchRecords @($branch) -Clock $clock -InventoryComplete $true
        $after = ConvertTo-Json -InputObject @($common, $branch) -Compress -Depth 50
        $clockState.Calls | Should -Be 1
        $after | Should -Be $before
        $selection.Durable | Should -BeFalse
        $selection.Selected[0].PSObject.Properties['Record'] | Should -BeNullOrEmpty
    }

    # Scenario: the caller cannot prove that the common and branch inputs cover the complete record inventory.
    # Purpose: prevent an incomplete source scan from yielding any archive candidate.
    It 'UnitT50_protects_every_record_when_the_source_inventory_is_incomplete' {
        $common = New-ArchiveCommon
        $branch = New-ArchiveBranch
        $common['Active Branches'] = @('branch-a')
        Add-ArchiveDecisionBinding -Common $common -Branch $branch
        $selection = Get-TestArchiveSelection -CommonRecords @($common) -BranchRecords @($branch) -InventoryComplete $false

        @($selection.Selected).Count | Should -Be 0
        @($selection.Protected).Count | Should -Be 2
        @($selection.Protected | Where-Object Reason -ne 'inventory-incomplete').Count | Should -Be 0
    }

    # Scenario: a stale common omits Active Branches or explicitly stores null instead of an empty array.
    # Purpose: require an explicit empty active-branch index before selecting a common record.
    It 'UnitT51_protects_common_records_with_missing_or_null_active_branch_indexes' {
        foreach ($state in @('missing', 'null')) {
            $common = New-ArchiveCommon -LastActivity '2026-09-24T00:00:00Z'
            if ($state -eq 'missing') { $common.Remove('Active Branches') }
            else { $common['Active Branches'] = $null }
            $selection = Get-TestArchiveSelection -CommonRecords @($common)

            @($selection.Selected).Count | Should -Be 0 -Because $state
            ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'invalid-active-branch-index'
        }
    }

    # Scenario: a retention date-only value reaches the maximum representable calendar date.
    # Purpose: protect the record without allowing end-of-day normalization to overflow.
    It 'UnitT52_protects_a_maximum_date_only_retention_boundary_without_throwing' {
        $common = New-ArchiveCommon -LastActivity '2026-09-24T00:00:00Z'
        $common['Keep Active Until'] = '9999-12-31'
        $selection = Get-TestArchiveSelection -CommonRecords @($common)

        @($selection.Selected).Count | Should -Be 0
        ($selection.Protected | Where-Object Kind -eq 'Common').Reason | Should -Be 'future-keep-active-until'
    }
    Context 'Injected archive cycle' {
        # Scenario: the caller lacks candidate-batch authorization or reports an incomplete inventory.
        # Purpose: ensure neither condition invokes the injected archive action.
        It 'UnitT16_requires_explicit_candidate_authorization_and_complete_inventory_before_storage_mutation' {
            $fixture = New-ArchiveFinalizationFixture
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[object]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($decision); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $denied = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $false `
                -OperationId 'cycle-denied' -ArchiveAction $archiveAction
            $denied.Durable | Should -BeFalse
            $denied.GateReason | Should -Be 'candidate-batch-unauthorized'
            $calls.Count | Should -Be 0

            $incomplete = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                -Clock $clock -InventoryComplete $false -CandidateBatchAuthorized $true `
                -OperationId 'cycle-incomplete' -ArchiveAction $archiveAction
            $incomplete.Durable | Should -BeFalse
            $incomplete.GateReason | Should -Be 'inventory-incomplete'
            $calls.Count | Should -Be 0
        }

        # Scenario: an eligible candidate is selected with a caller-supplied cycle identity.
        # Purpose: pass its exact cursor and report source completion only from a validated IntegrationResult.
        It 'UnitT17_passes_the_exact_selected_cursor_and_validates_the_source_result' {
            $fixture = New-ArchiveFinalizationFixture
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[object]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId 'cycle-green' -ArchiveAction $archiveAction

            $result.Durable | Should -BeFalse
            $result.SourceReportedDurable | Should -BeTrue
            @($result.Completed).Count | Should -Be 1
            @($result.Pending).Count | Should -Be 0
            $calls.Count | Should -Be 1
            $calls[0].OperationId | Should -Match '^cycle-green:archive:[0-9a-f]{64}$'
            $calls[0].Decision.Kind | Should -Be 'Branch'
            $calls[0].Decision.AuthorityScope | Should -Be 'scope-a'
            $calls[0].Decision.TaskKey | Should -Be 'task-1'
            $calls[0].Decision.BranchId | Should -Be 'branch-a'
            $calls[0].Cursor.Revision | Should -BeExactly 'source:branch@opaque/1'
            $calls[0].Cursor.ParentRevision | Should -BeExactly 'source:common@opaque/1'
            $calls[0].Cursor.ContinuationGeneration | Should -Be 2
            $fixture.Branch['Lifecycle'] | Should -Be 'Active'
            $fixture.Branch['Last Activity At'] | Should -Be '2026-09-25T00:00:00Z'
        }

        # Scenario: a Common record is eligible while it has no active branches.
        # Purpose: route Common archival through the injected lifecycle boundary without mutating the record in Core.
        It 'UnitT18_sends_an_expired_common_through_the_same_lifecycle_only_adapter_boundary' {
            $common = New-ArchiveCommon -LastActivity '2026-09-24T00:00:00Z'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[object]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($common) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'common-cycle' -ArchiveAction $archiveAction

            $result.Durable | Should -BeFalse
            $result.SourceReportedDurable | Should -BeTrue
            $calls.Count | Should -Be 1
            $calls[0].Decision.Kind | Should -Be 'Common'
            $calls[0].Cursor.Revision | Should -Be 'common-rev-1'
            $calls[0].Cursor.BranchId | Should -BeNullOrEmpty
            $calls[0].Cursor.ParentRevision | Should -BeNullOrEmpty
            $calls[0].OperationId | Should -Match '^common-cycle:archive:[0-9a-f]{64}$'
            $common.Lifecycle | Should -Be 'Active'
            $common['Last Activity At'] | Should -Be '2026-09-24T00:00:00Z'
        }

        # Scenario: an archive action reports a partial source result and returns one pending action.
        # Purpose: accept a later exact source result without replaying the delegated write.
        It 'UnitT19_retains_the_exact_pending_cursor_and_accepts_a_later_source_result_without_replay' {
            $fixture = New-ArchiveFinalizationFixture
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[object]]::new()
            $pendingAction = { param($decision,$cursor,$operationId); $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial' }.GetNewClosure()
            $first = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId 'cycle-recover' -ArchiveAction $pendingAction

            $first.Durable | Should -BeFalse
            @($first.Pending).Count | Should -Be 1
            $first.Pending[0].OperationId | Should -Match '^cycle-recover:archive:[0-9a-f]{64}$'
            $first.Pending[0].Decision.Revision | Should -BeExactly 'source:branch@opaque/1'
            $first.Pending[0].Cursor.ParentRevision | Should -BeExactly 'source:common@opaque/1'
            $first.Pending[0].Cursor.ContinuationGeneration | Should -Be 2

            $saved = $first.Pending[0]
            $sourceResult = [pscustomobject]@{
                Decision = $saved.Decision; Cursor = $saved.Cursor; OperationId = $saved.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $saved.OperationId -Status 'readback-matched' -Revision 'source:branch@opaque/2'
            }
            $resumeAction = { param($decision,$cursor,$operationId); $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions $first.Pending -SourceResults @($sourceResult) -ArchiveAction $resumeAction

            $resumed.Durable | Should -BeFalse
            $resumed.SourceReportedDurable | Should -BeTrue
            @($resumed.Completed).Count | Should -Be 1
            @($resumed.Pending).Count | Should -Be 0
            $calls.Count | Should -Be 1
            $calls[0].OperationId | Should -Be $saved.OperationId
            $resumed.Completed[0].Decision.Revision | Should -Be $saved.Decision.Revision
            $resumed.Completed[0].Cursor.ParentRevision | Should -Be $saved.Cursor.ParentRevision
        }

        # Scenario: a durable pending action's operation-ID digest is changed after the original attempt.
        # Purpose: reject the altered retry identity before invoking the archive callback.
        It 'UnitT20_rejects a pending action with a changed operation ID digest' {
            $pending = New-PendingArchiveCycleAction
            $pending.OperationId = $pending.OperationId.Substring(0, $pending.OperationId.Length - 1) + $(if ($pending.OperationId.EndsWith('0')) { '1' } else { '0' })
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions @($pending) -ArchiveAction $archiveAction

            $calls.Count | Should -Be 0
            $resumed.Durable | Should -BeFalse
            @($resumed.Pending).Count | Should -Be 1
            $resumed.GateReason | Should -Be 'invalid-pending-action'
            [object]::ReferenceEquals($resumed.Pending[0],$pending) | Should -BeTrue
            $resumed.Pending[0].PSObject.Properties['RetryState'] | Should -BeNullOrEmpty
        }

        # Scenario: the cycle prefix changes while the original cursor digest is retained.
        # Purpose: bind each resumed operation ID to the caller's original cycle identity.
        It 'UnitT21_rejects a pending action with a changed cycle prefix' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'cycle-prefix-original'
            $separator = $pending.OperationId.LastIndexOf(':archive:', [StringComparison]::Ordinal)
            $pending.OperationId = 'cycle-prefix-changed' + $pending.OperationId.Substring($separator)
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions @($pending) -ArchiveAction $archiveAction

            $calls.Count | Should -Be 0
            $resumed.Durable | Should -BeFalse
            @($resumed.Pending).Count | Should -Be 1
            $resumed.GateReason | Should -Be 'invalid-pending-action'
            [object]::ReferenceEquals($resumed.Pending[0],$pending) | Should -BeTrue
            $resumed.Pending[0].PSObject.Properties['RetryState'] | Should -BeNullOrEmpty
        }

        # Scenario: Decision and Cursor are consistently changed while the saved operation ID remains untouched.
        # Purpose: bind the saved operation ID to the exact candidate cursor used by the original attempt.
        It 'UnitT22_rejects a pending action whose cursor changed after operation ID creation' {
            $pending = New-PendingArchiveCycleAction
            $changedRevision = 'source:changed@opaque/1'
            $pending.Decision.Revision = $changedRevision
            $pending.Cursor.Revision = $changedRevision
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions @($pending) -ArchiveAction $archiveAction

            $calls.Count | Should -Be 0
            $resumed.Durable | Should -BeFalse
            @($resumed.Pending).Count | Should -Be 1
            $resumed.GateReason | Should -Be 'invalid-pending-action'
            [object]::ReferenceEquals($resumed.Pending[0],$pending) | Should -BeTrue
            $resumed.Pending[0].PSObject.Properties['RetryState'] | Should -BeNullOrEmpty
        }

        # Scenario: the stable cycle identity itself contains an earlier archive delimiter.
        # Purpose: preserve a valid saved operation unchanged while awaiting a source result.
        It 'UnitT23_retains_a_valid_pending_operation_ID_with_an_archive_delimiter_without_replay' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'cycle-prefix:archive:segment'
            $expectedOperationId = $pending.OperationId
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions @($pending) -ArchiveAction $archiveAction

            $resumed.Durable | Should -BeFalse
            $resumed.SourceReportedDurable | Should -BeFalse
            @($resumed.Completed).Count | Should -Be 0
            @($resumed.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($resumed.Pending[0],$pending) | Should -BeTrue
            $calls.Count | Should -Be 0
            $resumed.Pending[0].OperationId | Should -Be $expectedOperationId
        }

        # Scenario: a two-candidate batch completes one source-reported action and leaves the other pending.
        # Purpose: continue the batch, then apply an exact source result without replaying its write.
        It 'UnitT24_continues_after_one_candidate_is_pending_and_resumes_only_its_source_result' {
            $fixture = New-ArchiveFinalizationFixture
            $commonB = New-ArchiveCommon -Task 'task-b' -Revision 'source:common-b@opaque/1'
            $branchB = New-ArchiveBranch -Task 'task-b' -BranchId 'branch-b' -Revision 'source:branch-b@opaque/1'
            $bindingB = [ordered]@{
                branchId = 'branch-b'
                reviewedRevision = [string]$branchB['Revision']
                reviewedContentSha256 = Get-TestReviewedBranchContentSha256 $branchB
                continuationGeneration = [long]$branchB['Continuation Generation']
                outcome = [string]$branchB['Branch Outcome']
            }
            $commonB['Active Branches'] = @('branch-b')
            $commonB['Decision Branch Bindings'] = @($bindingB)
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $attempted = [System.Collections.Generic.List[object]]::new()
            $partialAction = { param($decision,$cursor,$operationId); $attempted.Add([pscustomobject]@{BranchId=[string]$decision.BranchId;OperationId=$operationId}); $verified = $decision.BranchId -ceq 'branch-b'; if ($verified) { & $global:ArchiveCallerResultFactory -OperationId $operationId } else { & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial' } }.GetNewClosure()
            $first = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common,$commonB) -BranchRecords @($fixture.Branch,$branchB) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId 'cycle-partial' -ArchiveAction $partialAction

            $first.Durable | Should -BeFalse
            @($first.Completed).Count | Should -Be 1
            @($first.Pending).Count | Should -Be 1
            $first.Pending[0].Decision.BranchId | Should -Be 'branch-a'
            $first.Pending[0].OperationId | Should -Be $attempted[0].OperationId
            $attempted[0].OperationId | Should -Match '^cycle-partial:archive:[0-9a-f]{64}$'
            $attempted[1].OperationId | Should -Not -Be $attempted[0].OperationId
            $attempted.Count | Should -Be 2

            $retryCalls = [System.Collections.Generic.List[object]]::new()
            $retryAction = { param($decision,$cursor,$operationId); $retryCalls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            $saved = $first.Pending[0]
            $sourceResult = [pscustomobject]@{
                Decision = $saved.Decision; Cursor = $saved.Cursor; OperationId = $saved.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $saved.OperationId -Status 'readback-matched' -Revision 'source:branch-a@opaque/2'
            }
            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions $first.Pending -SourceResults @($sourceResult) -ArchiveAction $retryAction

            $resumed.Durable | Should -BeFalse
            $resumed.SourceReportedDurable | Should -BeTrue
            $retryCalls.Count | Should -Be 0
            @($resumed.Completed).Count | Should -Be 1
            $resumed.Completed[0].Decision.BranchId | Should -Be 'branch-a'
            $resumed.Completed[0].Decision.Revision | Should -Be $saved.Decision.Revision
            $resumed.Completed[0].Cursor.ParentRevision | Should -Be $saved.Cursor.ParentRevision
            $resumed.Completed[0].OperationId | Should -Be $saved.OperationId
        }

        # Scenario: a blocked candidate is followed by repeated deterministic scheduler-style calls.
        # Purpose: keep blocked state protected and show repeated calls reuse storage idempotency identities.
        It 'UnitT25_keeps_blocked_candidates_protected_and_repeated_fake_scheduler_ticks_rely_on_storage_idempotency' {
            $common = New-ArchiveCommon
            $blocked = New-ArchiveBranch -WorkState 'Blocked'
            $common['Active Branches'] = @('branch-a')
            Add-ArchiveDecisionBinding -Common $common -Branch $blocked
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $writeCalls = [System.Collections.Generic.List[string]]::new()
            $transitions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $archiveAction = { param($decision,$cursor,$operationId); $writeCalls.Add($operationId); [void]$transitions.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            $protected = Invoke-HandoffArchiveCycle -CommonRecords @($common) -BranchRecords @($blocked) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'blocked-cycle' -ArchiveAction $archiveAction
            $protected.Durable | Should -BeFalse
            @($protected.Selected).Count | Should -Be 0
            $writeCalls.Count | Should -Be 0

            $fixture = New-ArchiveFinalizationFixture
            $writes = [System.Collections.Generic.List[string]]::new()
            $once = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $idempotentAction = { param($decision,$cursor,$operationId); $writes.Add($operationId); [void]$once.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            for($tick=0;$tick -lt 2;$tick++) {
                $null = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                    -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                    -OperationId 'cycle-repeat' -ArchiveAction $idempotentAction
            }
            $writes.Count | Should -Be 2
            $once.Count | Should -Be 1
        }

        # Scenario: a saved Task A action and fresh eligible Task B arrive in one authorized cycle.
        # Purpose: keep Task A pending without replay while independent fresh work progresses.
        It 'UnitT26_does_not_replay_a_pending_action_while_progressing_an_independent_fresh_task' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'saved-task-a'
            $freshTaskB = New-ArchiveCommon -Task 'task-b' -Revision 'task-b-common-r1'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[object]]::new()
            $archiveAction = {
                param($decision,$cursor,$operationId)
                $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId})
                return (& $global:ArchiveCallerResultFactory -OperationId $operationId)
            }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($freshTaskB) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) `
                -OperationId 'independent-cycle' -ArchiveAction $archiveAction

            $result.GateReason | Should -BeNullOrEmpty
            $calls.Count | Should -Be 1
            $calls[0].Decision.TaskKey | Should -Be 'task-b'
            $calls[0].OperationId | Should -Match '^independent-cycle:archive:[0-9a-f]{64}$'
            $calls[0].OperationId | Should -Not -Be $pending.OperationId
            @($result.Completed).Count | Should -Be 1
            $result.Completed[0].Decision.TaskKey | Should -Be 'task-b'
            @($result.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($result.Pending[0].Decision,$pending.Decision) | Should -BeTrue
            [object]::ReferenceEquals($result.Pending[0].Cursor,$pending.Cursor) | Should -BeTrue
            $result.Pending[0].OperationId | Should -Be $pending.OperationId
            $result.Durable | Should -BeFalse
        }

        # Scenario: a newer scan repeats the pending Task A identity and includes an unrelated expired Task B.
        # Purpose: preserve the saved cursor, defer its newer revision, and continue the unrelated task without replay.
        It 'UnitT27_preserves_an_overlapping_pending_identity_defers_its_newer_revision_and_reselects_later' {
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $originalCommonA = New-ArchiveCommon -Task 'task-a' -Revision 'common-rev-a1'
            $pendingAction = { param($decision,$cursor,$operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial') }
            $initial = Invoke-HandoffArchiveCycle -CommonRecords @($originalCommonA) -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'saved-task-a' -ArchiveAction $pendingAction
            @($initial.Pending).Count | Should -Be 1
            $pending = $initial.Pending[0]
            $newerCommonA = New-ArchiveCommon -Task 'task-a' -Revision 'common-rev-a2'
            $freshCommonB = New-ArchiveCommon -Task 'task-b' -Revision 'task-b-common-r1'
            $calls = [System.Collections.Generic.List[object]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($newerCommonA,$freshCommonB) -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) -OperationId 'independent-cycle' -ArchiveAction $archiveAction

            $result.GateReason | Should -Be 'pending-task-cursor-in-flight'
            $calls.Count | Should -Be 1
            $calls[0].Decision.TaskKey | Should -Be 'task-b'
            $calls[0].OperationId | Should -Match '^independent-cycle:archive:[0-9a-f]{64}$'
            @($result.Selected | Where-Object { $_.TaskKey -ceq 'task-a' -and $_.Revision -ceq 'common-rev-a2' }).Count | Should -Be 1
            @($result.Completed).Count | Should -Be 1
            @($result.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($result.Pending[0],$pending) | Should -BeTrue
            $result.Durable | Should -BeFalse

            $laterCalls = [System.Collections.Generic.List[object]]::new()
            $laterAction = { param($decision,$cursor,$operationId); $laterCalls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            $later = Invoke-HandoffArchiveCycle -CommonRecords @($newerCommonA) -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'later-task-a-cycle' -ArchiveAction $laterAction

            $later.Durable | Should -BeFalse
            $later.SourceReportedDurable | Should -BeTrue
            $laterCalls.Count | Should -Be 1
            $laterCalls[0].Decision.TaskKey | Should -Be 'task-a'
            $laterCalls[0].Decision.Revision | Should -Be 'common-rev-a2'
        }
        # Scenario: malformed, conflicting, and repeated pending entries are supplied with an eligible fresh Task B candidate.
        # Purpose: fail closed without mutation for ambiguous state and coalesce only identical saved actions.
        It 'UnitT28_fails_closed_for_invalid_or_conflicting_pending_entries_and_coalesces_identical_duplicates' {
            foreach ($mutation in @('digest','prefix','cursor')) {
                $bad = New-PendingArchiveCycleAction -CycleOperationId 'saved-task-a'
                if ($mutation -ceq 'digest') {
                    $bad.OperationId = $bad.OperationId.Substring(0,$bad.OperationId.Length - 1) + $(if ($bad.OperationId.EndsWith('0')) { '1' } else { '0' })
                } elseif ($mutation -ceq 'prefix') {
                    $separator = $bad.OperationId.LastIndexOf(':archive:',[StringComparison]::Ordinal)
                    $bad.OperationId = 'changed-prefix' + $bad.OperationId.Substring($separator)
                } else {
                    $bad.Decision.Revision = 'a' * 40
                }
                $freshTaskB = New-ArchiveCommon -Task 'task-b' -Revision 'task-b-common-r1'
                $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
                $clock = { $now }.GetNewClosure()
                $calls = [System.Collections.Generic.List[string]]::new()
                $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
                $result = Invoke-HandoffArchiveCycle -CommonRecords @($freshTaskB) -Clock $clock `
                    -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($bad) `
                    -OperationId 'independent-cycle' -ArchiveAction $archiveAction

                $result.GateReason | Should -Be 'invalid-pending-action'
                $calls.Count | Should -Be 0
                @($result.Selected).Count | Should -Be 0
                @($result.Pending).Count | Should -Be 1
                [object]::ReferenceEquals($result.Pending[0],$bad) | Should -BeTrue
                $result.Pending[0].PSObject.Properties['RetryState'] | Should -BeNullOrEmpty

                $again = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true `
                    -CandidateBatchAuthorized $true -PendingActions $result.Pending -ArchiveAction $archiveAction
                $again.GateReason | Should -Be 'invalid-pending-action'
                $calls.Count | Should -Be 0
                @($again.Pending).Count | Should -Be 1
                [object]::ReferenceEquals($again.Pending[0],$bad) | Should -BeTrue
                $again.Pending[0].PSObject.Properties['RetryState'] | Should -BeNullOrEmpty
            }

            $first = New-PendingArchiveCycleAction -CycleOperationId 'saved-task-a'
            $conflict = New-PendingArchiveCycleAction -CycleOperationId 'other-task-a-cycle'
            $freshTaskB = New-ArchiveCommon -Task 'task-b' -Revision 'task-b-common-r1'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            $conflicting = Invoke-HandoffArchiveCycle -CommonRecords @($freshTaskB) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($first,$conflict) `
                -OperationId 'independent-cycle' -ArchiveAction $archiveAction

            $conflicting.GateReason | Should -Be 'conflicting-pending-actions'
            $calls.Count | Should -Be 0
            @($conflicting.Pending).Count | Should -Be 2
            [object]::ReferenceEquals($conflicting.Pending[0],$first) | Should -BeTrue
            [object]::ReferenceEquals($conflicting.Pending[1],$conflict) | Should -BeTrue

            $duplicate = New-PendingArchiveCycleAction -CycleOperationId 'saved-task-a'
            $duplicateCopy = [pscustomobject]@{
                Decision = [pscustomobject]@{
                    Kind = $duplicate.Decision.Kind; AuthorityScope = $duplicate.Decision.AuthorityScope
                    TaskKey = $duplicate.Decision.TaskKey; BranchId = $duplicate.Decision.BranchId
                    Revision = $duplicate.Decision.Revision; ParentRevision = $duplicate.Decision.ParentRevision
                    ContinuationGeneration = [int]$duplicate.Decision.ContinuationGeneration
                    BranchOutcome = $duplicate.Decision.BranchOutcome; Reason = $duplicate.Decision.Reason
                }
                Cursor = [pscustomobject]@{
                    Kind = $duplicate.Cursor.Kind; AuthorityScope = $duplicate.Cursor.AuthorityScope
                    TaskKey = $duplicate.Cursor.TaskKey; BranchId = $duplicate.Cursor.BranchId
                    Revision = $duplicate.Cursor.Revision; ParentRevision = $duplicate.Cursor.ParentRevision
                    ContinuationGeneration = [int]$duplicate.Cursor.ContinuationGeneration
                    BranchOutcome = $duplicate.Cursor.BranchOutcome
                }
                OperationId = $duplicate.OperationId
            }
            $coalesced = Invoke-HandoffArchiveCycle -CommonRecords @($freshTaskB) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($duplicate,$duplicateCopy) `
                -OperationId 'independent-cycle' -ArchiveAction $archiveAction

            @($calls | Where-Object { $_ -ceq $duplicate.OperationId }).Count | Should -Be 0
            @($calls | Where-Object { $_ -match '^independent-cycle:archive:' }).Count | Should -Be 1
            @($coalesced.Completed).Count | Should -Be 1
            @($coalesced.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($coalesced.Pending[0],$duplicate) | Should -BeTrue
            $coalesced.Durable | Should -BeFalse
        }

        # Scenario: authorization or inventory may be absent, or a cycle may lack an ID while a saved action and fresh candidate coexist.
        # Purpose: preserve gate priority and require an operation ID for fresh work without replaying saved writes.
        It 'UnitT29_keeps_pending_actions_safe_across_gates_and_blank_cycle_identity' {
            foreach ($gate in @('candidate-batch-unauthorized','inventory-incomplete')) {
                $pending = New-PendingArchiveCycleAction -CycleOperationId 'saved-task-a'
                $freshTaskB = New-ArchiveCommon -Task 'task-b' -Revision 'task-b-common-r1'
                $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
                $clock = { $now }.GetNewClosure()
                $calls = [System.Collections.Generic.List[string]]::new()
                $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
                $result = Invoke-HandoffArchiveCycle -CommonRecords @($freshTaskB) -Clock $clock `
                    -InventoryComplete ($gate -cne 'inventory-incomplete') `
                    -CandidateBatchAuthorized ($gate -cne 'candidate-batch-unauthorized') `
                    -PendingActions @($pending) -OperationId 'independent-cycle' -ArchiveAction $archiveAction

                $result.GateReason | Should -Be $gate
                $calls.Count | Should -Be 0
                @($result.Pending).Count | Should -Be 1
                [object]::ReferenceEquals($result.Pending[0],$pending) | Should -BeTrue
            }

            $pending = New-PendingArchiveCycleAction -CycleOperationId 'saved-task-a'
            $freshTaskB = New-ArchiveCommon -Task 'task-b' -Revision 'task-b-common-r1'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[object]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add([pscustomobject]@{Decision=$decision;Cursor=$cursor;OperationId=$operationId}); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()
            $result = Invoke-HandoffArchiveCycle -CommonRecords @($freshTaskB) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) `
                -ArchiveAction $archiveAction

            $result.GateReason | Should -Be 'stable-operation-id-required'
            $calls.Count | Should -Be 0
            @($result.Completed).Count | Should -Be 0
            @($result.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($result.Pending[0],$pending) | Should -BeTrue
            $result.Durable | Should -BeFalse
        }

        # Scenario: two eligible branches share one task's common revision.
        # Purpose: write only one archive action, then reselect its sibling against the advanced common cursor.
        It 'UnitT53_serializes_sibling_archive_actions_by_task_cursor' {
            $fixture = New-ArchiveFinalizationFixture
            $branchB = New-ArchiveBranch -BranchId 'branch-b' -Revision 'source:branch-b@opaque/1'
            $bindingB = [ordered]@{
                branchId = 'branch-b'; reviewedRevision = [string]$branchB['Revision']
                reviewedContentSha256 = Get-TestReviewedBranchContentSha256 $branchB
                continuationGeneration = [long]$branchB['Continuation Generation']
                outcome = [string]$branchB['Branch Outcome']
            }
            $fixture.Common['Active Branches'] = @('branch-a','branch-b')
            $fixture.Common['Decision Branch Bindings'] = @($fixture.Binding,$bindingB)
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $action = {
                param($decision,$cursor,$operationId)
                $calls.Add([string]$decision.BranchId)
                if ([string]$cursor.ParentRevision -cne [string]$fixture.Common['Revision']) {
                    return (& $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial')
                }
                $fixture.Common['Revision'] = 'source:common@opaque/2'
                $fixture.Common['Active Branches'] = @('branch-b')
                return (& $global:ArchiveCallerResultFactory -OperationId $operationId)
            }.GetNewClosure()

            $first = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch,$branchB) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId 'sibling-cycle' -ArchiveAction $action

            $calls.Count | Should -Be 1
            $calls[0] | Should -Be 'branch-a'
            @($first.Selected).Count | Should -Be 2
            @($first.Completed).Count | Should -Be 1
            @($first.Pending).Count | Should -Be 0
            $first.GateReason | Should -Be 'same-task-cursor-in-flight'
            $first.Durable | Should -BeFalse
            $first.SourceReportedDurable | Should -BeFalse

            $second = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($branchB) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId 'sibling-cycle-next' -ArchiveAction $action
            $calls.Count | Should -Be 2
            $calls[1] | Should -Be 'branch-b'
            $second.Durable | Should -BeFalse
            $second.SourceReportedDurable | Should -BeTrue
            @($second.Pending).Count | Should -Be 0
        }

        # Scenario: persisted input from an older cycle contains two different pending actions under one task.
        # Purpose: reject ambiguous shared-cursor retries before either archive callback runs.
        It 'UnitT54_rejects_two_distinct_pending_actions_for_one_task' {
            $branchPending = New-PendingArchiveCycleAction -CycleOperationId 'older-branch-cycle'
            $common = New-ArchiveCommon
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $unverified = { param($decision,$cursor,$operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial') }
            $commonResult = Invoke-HandoffArchiveCycle -CommonRecords @($common) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'older-common-cycle' `
                -ArchiveAction $unverified
            @($commonResult.Pending).Count | Should -Be 1
            $commonPending = $commonResult.Pending[0]
            $calls = [System.Collections.Generic.List[string]]::new()
            $action = { param($decision,$cursor,$operationId); $calls.Add($operationId); (& $global:ArchiveCallerResultFactory -OperationId $operationId) }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true `
                -CandidateBatchAuthorized $true -PendingActions @($branchPending,$commonPending) `
                -ArchiveAction $action

            $result.GateReason | Should -Be 'conflicting-pending-actions'
            $calls.Count | Should -Be 0
            @($result.Pending).Count | Should -Be 2
            [object]::ReferenceEquals($result.Pending[0],$branchPending) | Should -BeTrue
            [object]::ReferenceEquals($result.Pending[1],$commonPending) | Should -BeTrue
        }

        # Scenario: a saved archive action has an unresolved source result and later receives a matching source report.
        # Purpose: resume source reporting on the exact cursor/operation without replaying the delegated write.
        It 'UnitT55_resumes_a_pending_source_result_without_replaying_the_archive_action' {
            $common = New-ArchiveCommon
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = {
                param($decision,$cursor,$operationId)
                $calls.Add($operationId)
                & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial'
            }.GetNewClosure()
            $first = Invoke-HandoffArchiveCycle -CommonRecords @($common) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'source-resume' -ArchiveAction $archiveAction

            $first.Durable | Should -BeFalse
            @($first.Pending).Count | Should -Be 1
            $pending = $first.Pending[0]
            $pending.CallerResult.Status | Should -Be 'partial'
            $sourceResult = [pscustomobject]@{
                Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $pending.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status 'readback-matched' -Revision 'source:revision@opaque/2'
            }

            $resumed = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions @($pending) -SourceResults @($sourceResult)

            $calls.Count | Should -Be 1
            $resumed.Durable | Should -BeFalse
            $resumed.SourceReportedDurable | Should -BeTrue
            @($resumed.Completed).Count | Should -Be 1
            @($resumed.Pending).Count | Should -Be 0
            $resumed.Completed[0].OperationId | Should -Be $pending.OperationId
            $resumed.Completed[0].CallerResult.Revision | Should -BeExactly 'source:revision@opaque/2'
        }

        # Scenario: a source action returns legacy caller booleans without the validated IntegrationResult fields.
        # Purpose: prevent caller claims from becoming Core durability evidence.
        It 'UnitT56_does_not_promote_legacy_durable_booleans_to_source_completion' {
            $common = New-ArchiveCommon
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $archiveAction = { param($decision,$cursor,$operationId); [pscustomobject]@{ Durable=$true; ReadbackVerified=$true; OperationId=$operationId } }

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($common) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'boolean-ack' -ArchiveAction $archiveAction

            $result.Durable | Should -BeFalse
            $result.SourceReportedDurable | Should -BeFalse
            @($result.Completed).Count | Should -Be 0
            @($result.Pending).Count | Should -Be 1
            $result.Pending[0].Reason | Should -Be 'invalid-source-result'
        }

        # Scenario: an eligible record is selected without a configured source action.
        # Purpose: return a concrete unpersisted result while keeping Core free of storage I/O.
        It 'UnitT57_keeps_an_eligible_candidate_pending_when_no_source_is_configured' {
            $common = New-ArchiveCommon
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($common) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -OperationId 'no-source'

            $result.GateReason | Should -Be 'source-not-configured'
            $result.Durable | Should -BeFalse
            $result.SourceReportedDurable | Should -BeFalse
            @($result.Selected).Count | Should -Be 1
            @($result.Completed).Count | Should -Be 0
            @($result.Pending).Count | Should -Be 1
            $result.Pending[0].Reason | Should -Be 'source-not-configured'
        }

        # Scenario: a source result changes the pending decision identity while its saved operation remains intact.
        # Purpose: reject mismatched provenance before calling a source action for any unrelated fresh candidate.
        It 'UnitT58_rejects_a_source_result_for_another_record_before_any_fresh_source_action' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'saved-source-result'
            $sourceResult = [pscustomobject]@{
                Decision = [pscustomobject]@{
                    Kind = 'Common'; AuthorityScope = 'scope-a'; TaskKey = 'other-task'; BranchId = $null
                    Revision = 'common-rev-1'; ParentRevision = $null; ContinuationGeneration = $null
                    BranchOutcome = $null; Reason = 'inactivity-expired'
                }
                Cursor = $pending.Cursor; OperationId = $pending.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status 'readback-matched'
            }
            $fresh = New-ArchiveCommon -Task 'fresh-task'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId }

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($fresh) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) `
                -SourceResults @($sourceResult) -OperationId 'fresh-cycle' -ArchiveAction $archiveAction

            $result.GateReason | Should -Be 'invalid-source-result'
            $calls.Count | Should -Be 0
            $result.Durable | Should -BeFalse
            @($result.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($result.Pending[0],$pending) | Should -BeTrue
        }

        # Scenario: a matched pending action receives partial, unknown, or mismatched readback from its source.
        # Purpose: retain the validated source result and keep the action unresolved without writing again.
        It 'UnitT59_preserves_nonterminal_source_results_without_replaying_the_archive_action' -ForEach @(
            @{ Status='partial' }, @{ Status='unknown' }, @{ Status='readback-mismatch' }, @{ Status='unavailable' }, @{ Status='denied' }
        ) {
            $pending = New-PendingArchiveCycleAction -CycleOperationId "status-$Status"
            $sourceResult = [pscustomobject]@{
                Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $pending.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status $Status
            }
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId }
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -PendingActions @($pending) -SourceResults @($sourceResult) -ArchiveAction $archiveAction

            $calls.Count | Should -Be 0
            $result.Durable | Should -BeFalse
            $result.SourceReportedDurable | Should -BeFalse
            @($result.Completed).Count | Should -Be 0
            @($result.Pending).Count | Should -Be 1
            $result.Pending[0].CallerResult.Status | Should -Be $Status
        }

        # Scenario: saved source reports have duplicate, malformed, operation-mismatched, or stale cursors.
        # Purpose: reject ambiguous reports before allowing any fresh archive action to run.
        It 'UnitT60_rejects_duplicate_malformed_mismatched_and_stale_source_results' {
            foreach ($mutation in @('duplicate','extra-field','decision-extra-field','cursor-extra-field','outer-operation','nested-operation','cursor')) {
                $pending = New-PendingArchiveCycleAction -CycleOperationId "strict-$mutation"
                $sourceResult = [pscustomobject]@{
                    Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $pending.OperationId
                    CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status 'readback-matched'
                }
                $sourceResults = @($sourceResult)
                switch ($mutation) {
                    'duplicate' { $sourceResults = @($sourceResult,$sourceResult) }
                    'extra-field' { $sourceResult | Add-Member -NotePropertyName Extra -NotePropertyValue 'unexpected' }
                    'decision-extra-field' {
                        $sourceResult.Decision = [pscustomobject]@{}
                        foreach ($property in $pending.Decision.PSObject.Properties) {
                            $sourceResult.Decision | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
                        }
                        $sourceResult.Decision | Add-Member -NotePropertyName Extra -NotePropertyValue 'unexpected'
                    }
                    'cursor-extra-field' {
                        $sourceResult.Cursor = [pscustomobject]@{}
                        foreach ($property in $pending.Cursor.PSObject.Properties) {
                            $sourceResult.Cursor | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
                        }
                        $sourceResult.Cursor | Add-Member -NotePropertyName Extra -NotePropertyValue 'unexpected'
                    }
                    'outer-operation' { $sourceResult.OperationId = 'other-operation' }
                    'nested-operation' { $sourceResult.CallerResult.OperationId = 'other-operation' }
                    'cursor' {
                        $sourceResult.Cursor = [pscustomobject]@{
                            Kind = $pending.Cursor.Kind; AuthorityScope = $pending.Cursor.AuthorityScope
                            TaskKey = $pending.Cursor.TaskKey; BranchId = $pending.Cursor.BranchId
                            Revision = 'source:cursor@opaque/other'; ParentRevision = $pending.Cursor.ParentRevision
                            ContinuationGeneration = $pending.Cursor.ContinuationGeneration
                            BranchOutcome = $pending.Cursor.BranchOutcome
                        }
                    }
                }
                $fresh = New-ArchiveCommon -Task 'fresh-task'
                $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
                $clock = { $now }.GetNewClosure()
                $calls = [System.Collections.Generic.List[string]]::new()
                $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId }

                $result = Invoke-HandoffArchiveCycle -CommonRecords @($fresh) -Clock $clock `
                    -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) `
                    -SourceResults $sourceResults -OperationId 'strict-fresh' -ArchiveAction $archiveAction

                $result.GateReason | Should -Be 'invalid-source-result' -Because $mutation
                $calls.Count | Should -Be 0 -Because $mutation
                @($result.Pending).Count | Should -Be 1 -Because $mutation
                [object]::ReferenceEquals($result.Pending[0],$pending) | Should -BeTrue -Because $mutation
            }

            $pending = New-PendingArchiveCycleAction -CycleOperationId 'strict-unauthorized'
            $sourceResult = [pscustomobject]@{
                Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $pending.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status 'readback-matched'
            }
            $fresh = New-ArchiveCommon -Task 'fresh-task'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId }
            $unauthorized = Invoke-HandoffArchiveCycle -CommonRecords @($fresh) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $false -PendingActions @($pending) `
                -SourceResults @($sourceResult) -OperationId 'strict-fresh' -ArchiveAction $archiveAction

            $unauthorized.GateReason | Should -Be 'candidate-batch-unauthorized'
            $unauthorized.SourceReportedDurable | Should -BeFalse
            $calls.Count | Should -Be 0
            [object]::ReferenceEquals($unauthorized.Pending[0],$pending) | Should -BeTrue
        }

        # Scenario: untrusted pending, source-result, or caller-result maps contain executable properties.
        # Purpose: reject them using plain-data shape checks without evaluating any getter.
        It 'UnitT61_rejects_executable_properties_without_evaluating_them' {
            foreach ($mutation in @('pending','source-result','caller-result')) {
                $pending = New-PendingArchiveCycleAction -CycleOperationId "getter-$mutation"
                $sourceResult = [pscustomobject]@{
                    Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $pending.OperationId
                    CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status 'readback-matched'
                }
                $getterState = [pscustomobject]@{ Calls = 0 }
                $getter = { $getterState.Calls++; 'source:getter@opaque/1' }.GetNewClosure()
                if ($mutation -ceq 'pending') {
                    $pending.Decision | Add-Member -MemberType ScriptProperty -Name Revision -Value $getter -Force
                } elseif ($mutation -ceq 'source-result') {
                    $sourceResult | Add-Member -MemberType ScriptProperty -Name OperationId -Value $getter -Force
                } else {
                    $sourceResult.CallerResult | Add-Member -MemberType ScriptProperty -Name Status -Value $getter -Force
                }
                $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
                $clock = { $now }.GetNewClosure()
                $calls = [System.Collections.Generic.List[string]]::new()
                $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId }

                $result = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true `
                    -CandidateBatchAuthorized $true -PendingActions @($pending) -SourceResults @($sourceResult) `
                    -OperationId 'getter-fresh' -ArchiveAction $archiveAction

                $expectedGate = if ($mutation -ceq 'pending') { 'invalid-pending-action' } else { 'invalid-source-result' }
                $result.GateReason | Should -Be $expectedGate -Because $mutation
                $getterState.Calls | Should -Be 0 -Because $mutation
                $calls.Count | Should -Be 0 -Because $mutation
            }
        }

        # Scenario: a cursor revision is a singleton array with an operation digest derived from that malformed shape.
        # Purpose: reject PowerShell's scalar/array coercion before accepting its matching source result.
        It 'UnitT62_rejects_a_singleton_array_cursor_even_when_its_operation_digest_matches' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'array-cursor'
            $pending.Cursor.Revision = @($pending.Cursor.Revision)
            $pending.OperationId = Get-TestArchiveCycleOperationId -CycleOperationId 'array-cursor' -Cursor $pending.Cursor
            $pending.CallerResult.OperationId = $pending.OperationId
            $sourceResult = [pscustomobject]@{
                Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $pending.OperationId
                CallerResult = New-ArchiveCallerResult -OperationId $pending.OperationId -Status 'readback-matched'
            }
            $sourceResult.CallerResult.OperationId = $pending.OperationId
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = { param($decision,$cursor,$operationId); $calls.Add($operationId); & $global:ArchiveCallerResultFactory -OperationId $operationId }

            $result = Invoke-HandoffArchiveCycle -Clock $clock -InventoryComplete $true `
                -CandidateBatchAuthorized $true -PendingActions @($pending) -SourceResults @($sourceResult) `
                -ArchiveAction $archiveAction

            $result.GateReason | Should -Be 'invalid-pending-action'
            $result.SourceReportedDurable | Should -BeFalse
            @($result.Completed).Count | Should -Be 0
            @($result.Pending).Count | Should -Be 1
            [object]::ReferenceEquals($result.Pending[0],$pending) | Should -BeTrue
            $calls.Count | Should -Be 0
        }

        # Scenario: GitRef storage support has been retired from the runtime.
        # Purpose: keep its former public adapter entry point absent from the shipped Skill scripts.
        It 'UnitT63_has_no_retired_GitRef_adapter_entrypoint' {
            $retiredAdapter = Join-Path $PSScriptRoot '../skills/manage-task-handoff/scripts/GitRefHandoffAdapter.psm1'
            Test-Path -LiteralPath $retiredAdapter | Should -BeFalse
        }

        # Scenario: a Common record carries an invalid non-null branch identity.
        # Purpose: prevent invalid records from becoming archive decisions.
        It 'UnitT64_protects_Common_Branch_ID_<Case>_during_selection' -ForEach @(
            @{ Case='empty'; BranchId='' },
            @{ Case='whitespace'; BranchId='   ' }
        ) {
            param($Case,$BranchId)
            $common = New-ArchiveCommon
            $common['Branch ID'] = $BranchId

            $selection = Get-TestArchiveSelection -CommonRecords @($common)

            $issues = [System.Collections.Generic.List[string]]::new()
            if (@($selection.Selected).Count -ne 0) { $issues.Add('selected-invalid-common') }
            if (@($selection.Protected).Count -ne 1) { $issues.Add('missing-protected-common') }
            elseif ($selection.Protected[0].Reason -cne 'invalid-identity') { $issues.Add("unexpected-reason:$($selection.Protected[0].Reason)") }
            @($issues) | Should -BeNullOrEmpty -Because $Case
        }

        # Scenario: an invalid Common decision could otherwise cross the source callback boundary.
        # Purpose: reject it before an archive write is delegated or persisted as pending.
        It 'UnitT65_does_not_delegate_or_save_Common_Branch_ID_<Case>' -ForEach @(
            @{ Case='empty'; BranchId='' },
            @{ Case='whitespace'; BranchId='   ' }
        ) {
            param($Case,$BranchId)
            $common = New-ArchiveCommon
            $common['Branch ID'] = $BranchId
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = {
                param($decision,$cursor,$operationId)
                $calls.Add($operationId)
                & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial'
            }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($common) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId "invalid-common-$Case" -ArchiveAction $archiveAction

            $issues = [System.Collections.Generic.List[string]]::new()
            if ($calls.Count -ne 0) { $issues.Add("archive-callback-count:$($calls.Count)") }
            if (@($result.Selected).Count -ne 0) { $issues.Add('selected-invalid-common') }
            if (@($result.Protected).Count -ne 1 -or $result.Protected[0].Reason -cne 'invalid-identity') {
                $issues.Add('invalid-common-not-protected')
            }
            if (@($result.Pending).Count -ne 0) { $issues.Add("invalid-pending-count:$(@($result.Pending).Count)") }
            if ($result.Durable -ne $false) { $issues.Add('core-claimed-durable') }
            @($issues) | Should -BeNullOrEmpty -Because $Case
        }

        # Scenario: persisted outcome changes while the saved cursor and operation ID remain untouched.
        # Purpose: ensure a source result cannot complete a different branch outcome under the old operation.
        It 'UnitT66_rejects_a_saved_BranchOutcome_change_before_source_completion' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'mutated-outcome'
            $originalOperationId = $pending.OperationId
            $pending.Decision.BranchOutcome = 'Superseded'
            $sourceResult = [pscustomobject]@{
                Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $originalOperationId
                CallerResult = New-ArchiveCallerResult -OperationId $originalOperationId -Status 'readback-matched'
            }
            $fresh = New-ArchiveCommon -Task 'outcome-independent-fresh'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = {
                param($decision,$cursor,$operationId)
                $calls.Add($operationId)
                & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial'
            }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($fresh) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) `
                -SourceResults @($sourceResult) -OperationId 'outcome-independent-cycle' -ArchiveAction $archiveAction

            $issues = [System.Collections.Generic.List[string]]::new()
            if ($pending.Cursor.BranchOutcome -cne 'Selected') { $issues.Add('cursor-does-not-bind-original-outcome') }
            if ($result.GateReason -cne 'invalid-pending-action') { $issues.Add("unexpected-gate:$($result.GateReason)") }
            if (@($result.Completed).Count -ne 0) { $issues.Add("completed-count:$(@($result.Completed).Count)") }
            if ($result.SourceReportedDurable -ne $false) { $issues.Add('source-reported-durable') }
            if (@($result.Pending).Count -ne 1 -or -not [object]::ReferenceEquals($result.Pending[0],$pending)) {
                $issues.Add('original-pending-not-retained')
            }
            if ($calls.Count -ne 0) { $issues.Add("archive-callback-count:$($calls.Count)") }
            @($issues) | Should -BeNullOrEmpty
        }

        # Scenario: a saved envelope uses the retired seven-field branch cursor shape.
        # Purpose: fail closed without migration, source-result consumption, or fresh callback I/O.
        It 'UnitT67_rejects_a_legacy_seven_field_branch_cursor_before_source_io' {
            $pending = New-PendingArchiveCycleAction -CycleOperationId 'legacy-seven-field'
            $pending.Cursor = [pscustomobject]@{
                Kind = $pending.Cursor.Kind; AuthorityScope = $pending.Cursor.AuthorityScope
                TaskKey = $pending.Cursor.TaskKey; BranchId = $pending.Cursor.BranchId
                Revision = $pending.Cursor.Revision; ParentRevision = $pending.Cursor.ParentRevision
                ContinuationGeneration = $pending.Cursor.ContinuationGeneration
            }
            $operationId = Get-TestArchiveCycleOperationId -CycleOperationId 'legacy-seven-field' -Cursor $pending.Cursor
            $pending.OperationId = $operationId
            $pending.CallerResult.OperationId = $operationId
            $sourceResult = [pscustomobject]@{
                Decision = $pending.Decision; Cursor = $pending.Cursor; OperationId = $operationId
                CallerResult = New-ArchiveCallerResult -OperationId $operationId -Status 'readback-matched'
            }
            $fresh = New-ArchiveCommon -Task 'legacy-independent-fresh'
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $calls = [System.Collections.Generic.List[string]]::new()
            $archiveAction = {
                param($decision,$cursor,$operationId)
                $calls.Add($operationId)
                & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'partial'
            }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($fresh) -Clock $clock `
                -InventoryComplete $true -CandidateBatchAuthorized $true -PendingActions @($pending) `
                -SourceResults @($sourceResult) -OperationId 'legacy-independent-cycle' -ArchiveAction $archiveAction

            $issues = [System.Collections.Generic.List[string]]::new()
            if (@($pending.Cursor.PSObject.Properties).Count -ne 7) { $issues.Add('fixture-is-not-legacy-seven-field') }
            if ($result.GateReason -cne 'invalid-pending-action') { $issues.Add("unexpected-gate:$($result.GateReason)") }
            if (@($result.Completed).Count -ne 0) { $issues.Add("completed-count:$(@($result.Completed).Count)") }
            if ($result.SourceReportedDurable -ne $false) { $issues.Add('source-reported-durable') }
            if (@($result.Pending).Count -ne 1 -or -not [object]::ReferenceEquals($result.Pending[0],$pending)) {
                $issues.Add('legacy-pending-not-retained')
            }
            if ($calls.Count -ne 0) { $issues.Add("archive-callback-count:$($calls.Count)") }
            @($issues) | Should -BeNullOrEmpty
        }

        # Scenario: the fresh archive callback mutates the object references it receives.
        # Purpose: keep selected and completed Core snapshots unchanged across caller code.
        It 'UnitT68_passes_plain_copies_to_the_fresh_archive_callback' {
            $fixture = New-ArchiveFinalizationFixture
            $now = [DateTimeOffset]::Parse('2026-10-02T00:00:00Z')
            $clock = { $now }.GetNewClosure()
            $callbackInputs = [System.Collections.Generic.List[object]]::new()
            $archiveAction = {
                param($decision,$cursor,$operationId)
                $callbackInputs.Add([pscustomobject]@{ Decision=$decision; Cursor=$cursor })
                $decision.BranchOutcome = 'Superseded'
                $cursor.BranchOutcome = 'Superseded'
                & $global:ArchiveCallerResultFactory -OperationId $operationId -Status 'readback-matched'
            }.GetNewClosure()

            $result = Invoke-HandoffArchiveCycle -CommonRecords @($fixture.Common) -BranchRecords @($fixture.Branch) `
                -Clock $clock -InventoryComplete $true -CandidateBatchAuthorized $true `
                -OperationId 'callback-mutation' -ArchiveAction $archiveAction

            $issues = [System.Collections.Generic.List[string]]::new()
            if ($callbackInputs.Count -ne 1) { $issues.Add("callback-count:$($callbackInputs.Count)") }
            elseif ([object]::ReferenceEquals($callbackInputs[0].Decision,$result.Selected[0])) { $issues.Add('callback-received-selected-decision-reference') }
            elseif ([object]::ReferenceEquals($callbackInputs[0].Cursor,$result.Completed[0].Cursor)) { $issues.Add('callback-received-completed-cursor-reference') }
            if ($result.Selected[0].BranchOutcome -cne 'Selected') { $issues.Add("selected-outcome:$($result.Selected[0].BranchOutcome)") }
            if ($result.Completed[0].Decision.BranchOutcome -cne 'Selected') { $issues.Add("completed-outcome:$($result.Completed[0].Decision.BranchOutcome)") }
            if ($result.Completed[0].Cursor.BranchOutcome -cne 'Selected') { $issues.Add("completed-cursor-outcome:$($result.Completed[0].Cursor.BranchOutcome)") }
            if (-not [object]::ReferenceEquals($result.Completed[0].Decision,$result.Selected[0])) { $issues.Add('completed-decision-not-original-selection') }
            if (@($result.Pending).Count -ne 0 -or $result.Durable -ne $false -or $result.SourceReportedDurable -ne $true) {
                $issues.Add('unexpected-cycle-result-state')
            }
            @($issues) | Should -BeNullOrEmpty
        }
    }
}
