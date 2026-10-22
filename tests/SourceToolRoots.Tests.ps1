# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'Source tool root workflow ownership' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $script:RootModule=Join-Path $repositoryRoot 'scripts/SourceToolRoots.psm1'
        $workflow=Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/validate.yml') -Raw
        $match=[regex]::Match($workflow,"(?s)- name: Clean only this run's temporary files.*?run: \|\r?\n(?<body>.*?)\r?\n  repository-contract:")
        if(-not $match.Success) {throw 'Exact protected cleanup step was not found.'}
        $driverExpression = "'" + '${{ github.event.pull_request.base.sha || github.sha }}' + "'"
        $cleanupText = ($match.Groups['body'].Value -replace '(?m)^          ','').Replace($driverExpression,'$env:EXPECTED_DRIVER_SHA')
        $script:Cleanup=[scriptblock]::Create($cleanupText)
        $registerMatch=[regex]::Match($workflow,'(?s)- name: Register allocated source tool evidence.*?run: \|\r?\n(?<body>.*?)\r?\n      - name: Preserve raw source validation evidence')
        if(-not $registerMatch.Success){throw 'Exact protected registration step was not found.'}
        $script:Register=[scriptblock]::Create(($registerMatch.Groups['body'].Value -replace '(?m)^          ','').Replace($driverExpression,'$env:EXPECTED_DRIVER_SHA'))
        function Invoke-AllocationCleanupFixture {
            param([switch]$WrongSource,[switch]$ReparseChild,[switch]$TamperedModule,[switch]$RegisterOnly,[switch]$ReplacedDriver,[switch]$CheckoutCrlf)
            $case=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $temp=Join-Path $case 'temp'; $runner=Join-Path $case 'runner'; $workspace=Join-Path $case 'workspace'
            $runId=[guid]::NewGuid().ToString('N')
            $owned=Join-Path $runner 'skill-general-123-1'
            $tools=Join-Path $temp "svt-tools-$runId"
            $other=Join-Path $temp ('svt-tools-'+('e'*32))
            [void](New-Item -ItemType Directory -Path (Join-Path $owned 't'),$tools,$other,(Join-Path $workspace 'driver/scripts') -Force)
            Copy-Item -LiteralPath $script:RootModule -Destination (Join-Path $workspace 'driver/scripts/SourceToolRoots.psm1')
            $driver=Join-Path $workspace 'driver'
            & git -C $driver init --quiet
            & git -C $driver -c core.autocrlf=false add -- scripts/SourceToolRoots.psm1
            & git -C $driver -c user.name='Source root fixture' -c user.email='fixture@example.invalid' commit --quiet -m 'immutable driver fixture'
            if($LASTEXITCODE){throw 'Could not commit the protected driver fixture.'}
            $driverCommit=([string](& git -C $driver rev-parse HEAD)).Trim()
            $importMarker=Join-Path $case 'untrusted-module-executed.txt'
            if($TamperedModule){
                $modulePath=Join-Path $driver 'scripts/SourceToolRoots.psm1'
                $prefix='[IO.File]::WriteAllText($env:SOURCE_MODULE_IMPORT_MARKER,''untrusted top-level executed'')'
                [IO.File]::WriteAllText($modulePath,$prefix+"`n"+[IO.File]::ReadAllText($modulePath))
            }
            if($ReplacedDriver){
                & git -C $driver -c core.autocrlf=false add -- scripts/SourceToolRoots.psm1
                & git -C $driver -c user.name='Source root fixture' -c user.email='fixture@example.invalid' commit --quiet -m 'untrusted candidate replacement'
                & git -C $driver replace $driverCommit HEAD
                if($LASTEXITCODE){throw 'Could not prepare the replacement-ref fixture.'}
            }
            if($CheckoutCrlf){
                $modulePath=Join-Path $driver 'scripts/SourceToolRoots.psm1'
                [IO.File]::WriteAllText($modulePath,[IO.File]::ReadAllText($modulePath).Replace("`r`n","`n").Replace("`n","`r`n"))
            }
            [IO.File]::WriteAllText((Join-Path $other 'unrelated-marker'),'preserve')
            $link=Join-Path $tools 'do-not-follow'
            if($ReparseChild){[void](New-Item -ItemType Junction -Path $link -Target $other -ErrorAction Stop)}
            $allocation=Join-Path $owned 't/source-tools.json.allocation.json'
            @{schemaVersion=1;runId=$runId;sourceRevision=$(if($WrongSource){'b'*40}else{'a'*40});ownedRoot=$tools}|ConvertTo-Json|Set-Content -LiteralPath $allocation
            $values=@{TEMP=$temp;TMP=$temp;LOCALAPPDATA='';RUNNER_TEMP=$runner;RUN_OWNED_ROOT=$owned;GITHUB_RUN_ID='123';GITHUB_RUN_ATTEMPT='1';GITHUB_WORKSPACE=$workspace;SOURCE_TOOLS_RUN_ID=$runId;EXPECTED_SOURCE_SHA=('a'*40);EXPECTED_DRIVER_SHA=$driverCommit;SOURCE_MODULE_IMPORT_MARKER=$importMarker;GITHUB_ENV=(Join-Path $case 'github-env.txt')}
            $saved=@{}
            foreach($key in $values.Keys) {$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$values[$key],'Process')}
            $failure=$null
            try { if($RegisterOnly){& $script:Register}else{& $script:Cleanup} }
            catch {$failure=$_.Exception.Message}
            finally {
                foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
                if($ReparseChild -and (Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link)}
            }
            $registered=if(Test-Path -LiteralPath (Join-Path $case 'github-env.txt')){[IO.File]::ReadAllText((Join-Path $case 'github-env.txt'))}else{''}
            return [pscustomobject]@{failure=$failure;metadataExists=(Test-Path -LiteralPath $owned);toolsExist=(Test-Path -LiteralPath $tools);unrelatedPreserved=(Test-Path -LiteralPath (Join-Path $other 'unrelated-marker'));untrustedModuleExecuted=(Test-Path -LiteralPath $importMarker);registered=$registered;expectedRoot=$tools}
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
    # Scenario: candidate execution replaced the driver module before the always cleanup step.
    # Purpose: reject its content before importing any top-level code or deleting either owned root.
    It 'UnitT40_rejects_a_tampered_driver_before_cleanup_module_import' {
        $result=Invoke-AllocationCleanupFixture -TamperedModule
        $result.failure | Should -Match 'Protected.*module'
        $result.untrustedModuleExecuted | Should -BeFalse
        $result.toolsExist | Should -BeTrue
        $result.metadataExists | Should -BeTrue
    }
    # Scenario: candidate execution replaced the same module before artifact registration.
    # Purpose: the registration path enforces the same immutable-base binding before import.
    It 'UnitT50_rejects_a_tampered_driver_before_registration_module_import' {
        $result=Invoke-AllocationCleanupFixture -TamperedModule -RegisterOnly
        $result.failure | Should -Match 'Protected.*module'
        $result.untrustedModuleExecuted | Should -BeFalse
        $result.toolsExist | Should -BeTrue
        $result.metadataExists | Should -BeTrue
    }
    # Scenario: candidate code also installs a Git replacement for the expected base commit.
    # Purpose: replacement refs cannot authorize the substituted module's top-level code.
    It 'UnitT60_ignores_replacement_refs_when_binding_the_driver_module' {
        $result=Invoke-AllocationCleanupFixture -TamperedModule -ReplacedDriver
        $result.failure | Should -Match 'Protected.*module'
        $result.untrustedModuleExecuted | Should -BeFalse
        $result.toolsExist | Should -BeTrue
        $result.metadataExists | Should -BeTrue
    }
    # Scenario: checkout converted only the trusted module's LF endings to CRLF.
    # Purpose: preserve legitimate registration without relaxing any executable content comparison.
    It 'UnitT70_registers_the_verified_module_after_checkout_line_ending_conversion' {
        $result=Invoke-AllocationCleanupFixture -RegisterOnly -CheckoutCrlf
        $result.failure | Should -BeNullOrEmpty
        $result.registered.Trim() | Should -Be ("SOURCE_TOOLS_ROOT="+$result.expectedRoot)
        $result.toolsExist | Should -BeTrue
        $result.metadataExists | Should -BeTrue
    }
}
