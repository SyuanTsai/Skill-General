# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Shared reference generator in a consumer snapshot' {
    BeforeAll {
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:GeneratorPath = Join-Path $script:RepositoryRoot 'scripts/Sync-SharedReferences.ps1'

        function New-SharedReferenceFixture {
            $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
            $directories = @(
                'scripts'
                'shared/references'
                'skills/manage-ai-memory/references'
                'skills/manage-task-handoff/references'
            )
            foreach ($directory in $directories) {
                [void](New-Item -ItemType Directory -Path (Join-Path $root $directory) -Force)
            }
            Copy-Item -LiteralPath $script:GeneratorPath -Destination (Join-Path $root 'scripts/Sync-SharedReferences.ps1')
            Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'shared/references/environment-separation.md') `
                -Destination (Join-Path $root 'shared/references/environment-separation.md')
            foreach ($target in @(
                    'skills/manage-ai-memory/references/environment-separation.md'
                    'skills/manage-task-handoff/references/environment-separation.md'
                )) {
                Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot $target) -Destination (Join-Path $root $target)
            }
            return $root
        }
    }

    It 'passes check mode for the immutable repository snapshot' {
        $output = @(& $script:GeneratorPath -Check)
        $output | Should -HaveCount 1
        $output[0] | Should -BeExactly 'Shared references are current (2 files).'
    }

    It 'detects drift in a fixture without repairing it in check mode' {
        $root = New-SharedReferenceFixture
        $target = Join-Path $root 'skills/manage-ai-memory/references/environment-separation.md'
        [IO.File]::WriteAllText($target, 'drift', [Text.UTF8Encoding]::new($false))
        { & (Join-Path $root 'scripts/Sync-SharedReferences.ps1') -Check } |
            Should -Throw '*Shared references are not generated from the authoritative source*'
        [IO.File]::ReadAllText($target) | Should -BeExactly 'drift'
    }

    It 'repairs only the fixed fixture targets when explicitly invoked' {
        $root = New-SharedReferenceFixture
        $target = Join-Path $root 'skills/manage-task-handoff/references/environment-separation.md'
        [IO.File]::WriteAllText($target, 'drift', [Text.UTF8Encoding]::new($false))
        $output = @(& (Join-Path $root 'scripts/Sync-SharedReferences.ps1'))
        $output | Should -HaveCount 1
        $output[0] | Should -BeExactly 'Synchronized 2 shared references; changed 1.'
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash |
            Should -BeExactly (Get-FileHash -LiteralPath (Join-Path $root 'shared/references/environment-separation.md') -Algorithm SHA256).Hash
    }
}
