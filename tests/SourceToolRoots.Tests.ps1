# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Source tool root workflow ownership' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $script:RootModule=Join-Path $repositoryRoot 'scripts/SourceToolRoots.psm1'
        $workflow=Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/validate.yml') -Raw
        $match=[regex]::Match($workflow,"(?s)- name: Clean only this run's temporary files.*?run: \|\r?\n(?<body>.*?)\r?\n  repository-contract:")
        if(-not $match.Success) {throw 'Exact protected cleanup step was not found.'}
        $script:Cleanup=[scriptblock]::Create(($match.Groups['body'].Value -replace '(?m)^          ',''))
        function Invoke-AllocationCleanupFixture {
            param([switch]$WrongSource,[switch]$ReparseChild)
            $case=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $temp=Join-Path $case 'temp'; $runner=Join-Path $case 'runner'; $workspace=Join-Path $case 'workspace'
            $runId=[guid]::NewGuid().ToString('N')
            $owned=Join-Path $runner 'skill-general-123-1'
            $tools=Join-Path $temp "svt-tools-$runId"
            $other=Join-Path $temp ('svt-tools-'+('e'*32))
            [void](New-Item -ItemType Directory -Path (Join-Path $owned 't'),$tools,$other,(Join-Path $workspace 'driver/scripts') -Force)
            Copy-Item -LiteralPath $script:RootModule -Destination (Join-Path $workspace 'driver/scripts/SourceToolRoots.psm1')
            [IO.File]::WriteAllText((Join-Path $other 'unrelated-marker'),'preserve')
            $link=Join-Path $tools 'do-not-follow'
            if($ReparseChild){[void](New-Item -ItemType Junction -Path $link -Target $other -ErrorAction Stop)}
            $allocation=Join-Path $owned 't/source-tools.json.allocation.json'
            @{schemaVersion=1;runId=$runId;sourceRevision=$(if($WrongSource){'b'*40}else{'a'*40});ownedRoot=$tools}|ConvertTo-Json|Set-Content -LiteralPath $allocation
            $values=@{TEMP=$temp;TMP=$temp;LOCALAPPDATA='';RUNNER_TEMP=$runner;RUN_OWNED_ROOT=$owned;GITHUB_RUN_ID='123';GITHUB_RUN_ATTEMPT='1';GITHUB_WORKSPACE=$workspace;SOURCE_TOOLS_RUN_ID=$runId;EXPECTED_SOURCE_SHA=('a'*40)}
            $saved=@{}
            foreach($key in $values.Keys) {$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$values[$key],'Process')}
            $failure=$null
            try { & $script:Cleanup }
            catch {$failure=$_.Exception.Message}
            finally {
                foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
                if($ReparseChild -and (Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link)}
            }
            return [pscustomobject]@{failure=$failure;metadataExists=(Test-Path -LiteralPath $owned);toolsExist=(Test-Path -LiteralPath $tools);unrelatedPreserved=(Test-Path -LiteralPath (Join-Path $other 'unrelated-marker'))}
        }
    }
    # Scenario: a setup allocated a short temp tool root outside its metadata directory.
    # Purpose: clean only both exact owned roots, preserving every other run.
    It 'UnitT10_cleans_the_exact_allocated_root_and_preserves_other_runs' {
        $result=Invoke-AllocationCleanupFixture
        $result.failure | Should -BeNullOrEmpty
        $result.toolsExist | Should -BeFalse
        $result.metadataExists | Should -BeFalse
        $result.unrelatedPreserved | Should -BeTrue
    }
    # Scenario: an allocation sidecar belongs to another candidate revision.
    # Purpose: reject it before removing either metadata or the claimed tool root.
    It 'UnitT20_rejects_wrong_candidate_allocation_without_removing_either_root' {
        $result=Invoke-AllocationCleanupFixture -WrongSource
        $result.failure | Should -Not -BeNullOrEmpty
        $result.toolsExist | Should -BeTrue
        $result.metadataExists | Should -BeTrue
        $result.unrelatedPreserved | Should -BeTrue
    }
    # Scenario: an allocated tool directory contains a junction to another run.
    # Purpose: refuse recursive cleanup before deletion and preserve the junction target.
    It 'UnitT30_rejects_a_reparse_child_and_preserves_its_target' {
        $result=Invoke-AllocationCleanupFixture -ReparseChild
        $result.failure | Should -Match 'reparse point'
        $result.toolsExist | Should -BeTrue
        $result.metadataExists | Should -BeTrue
        $result.unrelatedPreserved | Should -BeTrue
    }
}
