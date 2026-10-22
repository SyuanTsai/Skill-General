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
        $uploadMatch=[regex]::Match($workflow,'(?s)- name: Preserve raw source validation evidence.*?path: \|\r?\n(?<body>.*?)\r?\n      - name: Publish protected validation result')
        if(-not $uploadMatch.Success){throw 'Exact source artifact upload paths were not found.'}
        $script:UploadInputs=@($uploadMatch.Groups['body'].Value -split '\r?\n'|ForEach-Object{$_.Trim()}|Where-Object{$_})
        function Invoke-AllocationCleanupFixture {
            param([switch]$WrongSource,[switch]$ReparseChild,[switch]$TamperedModule,[switch]$RegisterOnly,[switch]$ReplacedDriver,[switch]$CheckoutCrlf,[switch]$WithToolEvidence,[switch]$ReceiptReparse)
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
            $expectedEvidence=@{}
            if($WithToolEvidence){
                foreach($name in @('receipt-skill-validator.json','setup-skill-validator-process.json','toolchain.json')){
                    $file=Join-Path $tools $name
                    [IO.File]::WriteAllText($file,"{`r`n  `"fixture`": `"$name`",`r`n  `"label`": `"Unicode 資料`"`r`n}`r`n",[Text.UTF8Encoding]::new($false))
                    $expectedEvidence[$name]=(Get-FileHash -LiteralPath $file).Hash
                }
                [IO.File]::WriteAllText((Join-Path $tools 'do-not-copy.exe'),'fixture tool binary')
                [IO.File]::WriteAllText((Join-Path $tools 'unregistered.json'),'not part of tool evidence')
            }
            $receiptLink=Join-Path $tools 'receipt-skill-validator.json'
            if($ReceiptReparse){[void](New-Item -ItemType Junction -Path $receiptLink -Target $other -ErrorAction Stop)}
            $link=Join-Path $tools 'do-not-follow'
            if($ReparseChild){[void](New-Item -ItemType Junction -Path $link -Target $other -ErrorAction Stop)}
            $allocation=Join-Path $owned 't/source-tools.json.allocation.json'
            @{schemaVersion=1;runId=$runId;sourceRevision=$(if($WrongSource){'b'*40}else{'a'*40});ownedRoot=$tools}|ConvertTo-Json|Set-Content -LiteralPath $allocation
            $values=@{TEMP=$temp;TMP=$temp;LOCALAPPDATA='';RUNNER_TEMP=$runner;RUN_OWNED_ROOT=$owned;GITHUB_RUN_ID='123';GITHUB_RUN_ATTEMPT='1';GITHUB_WORKSPACE=$workspace;SOURCE_TOOLS_RUN_ID=$runId;EXPECTED_SOURCE_SHA=('a'*40);EXPECTED_DRIVER_SHA=$driverCommit;SOURCE_MODULE_IMPORT_MARKER=$importMarker;GITHUB_ENV=(Join-Path $case 'github-env.txt')}
            $saved=@{}
            foreach($key in $values.Keys) {$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$values[$key],'Process')}
            $failure=$null
            try {
                # Actions starts a fresh shell: other Pester modules must not supply private helper functions.
                $workflowPath=Join-Path $case 'workflow.ps1'
                $failurePath=Join-Path $case 'workflow-failure.txt'
                $body=if($RegisterOnly){$script:Register.ToString()}else{$script:Cleanup.ToString()}
                [IO.File]::WriteAllText($workflowPath,$body,[Text.UTF8Encoding]::new($false))
                $wrapperPath=Join-Path $case 'invoke-workflow.ps1'
                $wrapper=@'
param([string]$WorkflowPath,[string]$FailurePath)
$ErrorActionPreference='Stop'
try { & ([scriptblock]::Create([IO.File]::ReadAllText($WorkflowPath))) }
catch { [IO.File]::WriteAllText($FailurePath,$_.Exception.Message,[Text.UTF8Encoding]::new($false)); exit 1 }
'@
                [IO.File]::WriteAllText($wrapperPath,$wrapper,[Text.UTF8Encoding]::new($false))
                & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -File $wrapperPath -WorkflowPath $workflowPath -FailurePath $failurePath | Out-Null
                $childExit=$LASTEXITCODE
                if(Test-Path -LiteralPath $failurePath){$failure=[IO.File]::ReadAllText($failurePath)}
                elseif($childExit -ne 0){$failure="Workflow fixture child exited $childExit before error capture."}
            }
            catch {$failure=$_.Exception.Message}
            finally {
                foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
                if($ReparseChild -and (Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link)}
                if($ReceiptReparse -and (Test-Path -LiteralPath $receiptLink)){[IO.Directory]::Delete($receiptLink)}
            }
            $registered=if(Test-Path -LiteralPath (Join-Path $case 'github-env.txt')){[IO.File]::ReadAllText((Join-Path $case 'github-env.txt'))}else{''}
            $staged=Join-Path $owned 't/source-tools-evidence'
            $bytesPreserved=$true
            foreach($name in $expectedEvidence.Keys){
                $file=Join-Path $staged $name
                if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file).Hash -cne $expectedEvidence[$name]){$bytesPreserved=$false}
            }
            $indexPath=Join-Path $staged 'evidence-index.json'
            $index=if(Test-Path -LiteralPath $indexPath){Get-Content -LiteralPath $indexPath -Raw|ConvertFrom-Json}else{$null}
            return [pscustomobject]@{failure=$failure;metadataExists=(Test-Path -LiteralPath $owned);toolsExist=(Test-Path -LiteralPath $tools);unrelatedPreserved=(Test-Path -LiteralPath (Join-Path $other 'unrelated-marker'));untrustedModuleExecuted=(Test-Path -LiteralPath $importMarker);registered=$registered;expectedRoot=$tools;stagedBytesPreserved=$bytesPreserved;index=$index;stagedToolBinary=(Test-Path -LiteralPath (Join-Path $staged 'do-not-copy.exe'));stagedUnregisteredJson=(Test-Path -LiteralPath (Join-Path $staged 'unregistered.json'))}
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
    # Scenario: native tools and validation metadata can reside on different Windows drives.
    # Purpose: stage only known JSON evidence under the metadata root while preserving bytes and original-path provenance.
    It 'UnitT80_stages_only_registered_JSON_evidence_without_changing_its_bytes' {
        $result=Invoke-AllocationCleanupFixture -RegisterOnly -WithToolEvidence
        $result.failure | Should -BeNullOrEmpty
        $result.stagedBytesPreserved | Should -BeTrue
        @($result.index.files).Count | Should -Be 3
        $result.index.ownedRoot | Should -Be $result.expectedRoot
        foreach($file in $result.index.files){$file.artifactRelativePath | Should -BeLike 't/source-tools-evidence/*.json'}
        $result.stagedToolBinary | Should -BeFalse
        $result.stagedUnregisteredJson | Should -BeFalse
        $result.toolsExist | Should -BeTrue
    }
    # Scenario: a selected receipt path was replaced by a junction before evidence collection.
    # Purpose: reject it before copying anything from its target.
    It 'UnitT90_rejects_a_reparse_receipt_during_evidence_staging' {
        $result=Invoke-AllocationCleanupFixture -RegisterOnly -ReceiptReparse
        $result.failure | Should -Be 'Source tool evidence must be a regular non-reparse file.'
        $result.unrelatedPreserved | Should -BeTrue
        $result.toolsExist | Should -BeTrue
    }
    # Scenario: upload-artifact needs one common root and cannot combine C: tool paths with D: metadata paths.
    # Purpose: all upload inputs use the one run-owned metadata root after staging.
    It 'UnitT100_keeps_every_upload_input_within_the_single_metadata_root' {
        $script:UploadInputs.Count | Should -BeGreaterThan 0
        foreach($path in $script:UploadInputs){$path.StartsWith('${{ env.RUN_OWNED_ROOT }}/',[StringComparison]::Ordinal) | Should -BeTrue}
    }
}
