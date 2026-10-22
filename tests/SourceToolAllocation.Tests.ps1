# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Source setup caller allocation' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot 'scripts/Validate.ps1'), [ref]$null, [ref]$null)
        $parts = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -cin @(
                'New-SourceToolSetup','Write-Utf8NoBomCreateNew','Get-FileSha256','Assert-NoReparseAncestors','Assert-PathWithinRoot','Test-PathWithinOrEqual'
            )
        } | ForEach-Object { $_.Extent.Text })
        $rootAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot 'scripts/SourceToolRoots.psm1'), [ref]$null, [ref]$null)
        $parts += @($rootAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] } | ForEach-Object { $_.Extent.Text })
        $doubles = @'
$script:SourceRepository = 'https://github.com/example/skills'
function Invoke-StandardValidationProcess {
    param($Command,$Arguments,$WorkingDirectory,$Environment,$TimeoutSeconds,[switch]$CoreLifecycleOnly)
    $script:ObservedArguments = $Arguments
    throw 'TRANSPORT_OBSERVED'
}
'@
        $script:CallerModule = New-Module -ScriptBlock ([scriptblock]::Create(($parts -join "`n") + "`n" + $doubles))
        function Invoke-SourceAllocationFixture {
            param([switch]$ExistingRoot,[switch]$ExistingJournal,[switch]$WrongHash,[switch]$InvalidRun)
            $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $temp = Join-Path $case 'temp'; $metadata = Join-Path $case 'metadata'; $authority = Join-Path $case 'authority'
            [void](New-Item -ItemType Directory -Path $temp,$metadata,(Join-Path $authority 'scripts') -Force)
            $runId = [guid]::NewGuid().ToString('N')
            $owned = Join-Path $temp "svt-tools-$runId"
            $prepared = Join-Path $metadata 'source-tools.json'
            $journal = "$prepared.allocation.json"
            $gate = Join-Path $authority 'scripts/Invoke-StandardAuthorityGate.ps1'
            $gateText = @'
param([switch]$DefineFunctionsOnly)
function New-AuthorityRunOwnedToolRoot {
    param([string]$RunId)
    $root = Join-Path ([IO.Path]::GetTempPath()) "svt-tools-$RunId"
    [void](New-Item -ItemType Directory -Path $root -ErrorAction Stop)
    return $root
}
'@
            [IO.File]::WriteAllText($gate,$gateText)
            [IO.File]::WriteAllText((Join-Path $authority 'scripts/Invoke-StandardValidation.ps1'),'param([switch]$DefineFunctionsOnly,$CandidateRoot,$AdapterPath,$ArtifactsRoot,$SourceRepository,$SourceRevision,$BaseRevision)')
            $gateHash = (Get-FileHash -LiteralPath $gate).Hash.ToLowerInvariant()
            if ($WrongHash) { $gateHash = '0' * 64 }
            if ($ExistingRoot) {
                [void](New-Item -ItemType Directory -Path $owned)
                [IO.File]::WriteAllText((Join-Path $owned 'marker'),'preserve')
            }
            if ($ExistingJournal) { [IO.File]::WriteAllText($journal,'preserve existing journal') }
            $savedTemp = $env:TEMP; $savedTmp = $env:TMP; $savedRun = $env:SOURCE_TOOLS_RUN_ID
            $failure = $null; $observed = @()
            try {
                $env:TEMP = $temp; $env:TMP = $temp
                $env:SOURCE_TOOLS_RUN_ID = if ($InvalidRun) { 'invalid-run' } else { $runId }
                & $script:CallerModule {
                    param($root,$authority,$pin,$prepared)
                    $script:ObservedArguments = @()
                    New-SourceToolSetup -Root $root -AuthorityRoot $authority -AuthorityPin $pin -PowerShell 'fixture-pwsh' `
                        -CandidateRevision ('a' * 40) -Git 'fixture-git' -CandidateRoot $root -PreparedPath $prepared -GoVersion 'go1.26.1' -LimitSeconds 30
                } $metadata $authority @{commit=('c'*40);files=@{'scripts/Invoke-StandardAuthorityGate.ps1'=$gateHash}} $prepared
            }
            catch { $failure = $_.Exception.Message }
            finally {
                $observed = @(& $script:CallerModule { $script:ObservedArguments })
                $env:TEMP = $savedTemp; $env:TMP = $savedTmp; $env:SOURCE_TOOLS_RUN_ID = $savedRun
            }
            $allocation = if (Test-Path -LiteralPath $journal) { [IO.File]::ReadAllText($journal) } else { $null }
            return [pscustomobject]@{
                failure=$failure; arguments=$observed; allocation=$allocation; owned=$owned; ownedExists=(Test-Path -LiteralPath $owned)
                markerPreserved=(Test-Path -LiteralPath (Join-Path $owned 'marker')); runId=$runId
                legacyRoots=@(Get-ChildItem -LiteralPath $metadata -Directory -Filter 'source-tools-*').Count
            }
        }
    }
    # Scenario: the first acquisition is about to run after allocation.
    # Purpose: persist exact ownership first and pass the short root directly to the resolver's path budget.
    It 'UnitT10_records_run_ownership_before_transport_and_passes_the_exact_root' {
        $result = Invoke-SourceAllocationFixture
        $result.failure | Should -Be 'TRANSPORT_OBSERVED'
        $allocation = $result.allocation | ConvertFrom-Json
        $allocation.runId | Should -Be $result.runId
        $allocation.sourceRevision | Should -Be ('a' * 40)
        $allocation.ownedRoot | Should -Be $result.owned
        $result.arguments[[array]::IndexOf($result.arguments,'-InstallRoot') + 1] | Should -Be $result.owned
        $result.legacyRoots | Should -Be 0
    }
    # Scenario: the exact allocator root already belongs to an earlier process.
    # Purpose: stop before acquisition without claiming or removing existing files.
    It 'UnitT20_preserves_an_existing_allocator_root_without_claiming_it' {
        $result = Invoke-SourceAllocationFixture -ExistingRoot
        $result.failure | Should -Not -Be 'TRANSPORT_OBSERVED'
        $result.allocation | Should -BeNullOrEmpty
        $result.markerPreserved | Should -BeTrue
    }
    # Scenario: a workflow supplies an invalid setup run identity.
    # Purpose: fail before allocation rather than silently substituting a new identity.
    It 'UnitT30_rejects_invalid_workflow_run_identity_before_allocation' {
        $result = Invoke-SourceAllocationFixture -InvalidRun
        $result.failure | Should -Match 'run identity'
        $result.ownedExists | Should -BeFalse
        $result.legacyRoots | Should -Be 0
    }
    # Scenario: metadata already contains an allocation record.
    # Purpose: preserve its bytes and avoid allocating an unjournaled second tool root.
    It 'UnitT40_preserves_an_existing_allocation_record_before_creating_a_root' {
        $result = Invoke-SourceAllocationFixture -ExistingJournal
        $result.failure | Should -Not -Be 'TRANSPORT_OBSERVED'
        $result.allocation | Should -Be 'preserve existing journal'
        $result.ownedExists | Should -BeFalse
    }
    # Scenario: the authority helper differs from the pin already validated by the caller.
    # Purpose: reject substitution before executing the helper or allocating its root.
    It 'UnitT50_rejects_a_substituted_authority_helper_before_allocation' {
        $result = Invoke-SourceAllocationFixture -WrongHash
        $result.failure | Should -Match 'helper hash'
        $result.ownedExists | Should -BeFalse
        $result.allocation | Should -BeNullOrEmpty
    }
}
