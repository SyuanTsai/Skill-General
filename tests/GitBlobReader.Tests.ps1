# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Repository snapshot file reader' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    }

    It 'enumerates hidden repository content without requiring metadata' {
        $fixture = Join-Path $TestDrive 'snapshot'
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture '.hidden') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture '.git') -Force)
        [IO.File]::WriteAllText((Join-Path $fixture '.hidden/file.txt'), 'hidden', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $fixture 'visible.txt'), 'visible', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $fixture '.git/internal'), 'metadata', [Text.UTF8Encoding]::new($false))

        $files = @(Get-ConsumerRepositoryFiles -RepositoryRoot $fixture | ForEach-Object RelativePath)
        $files | Should -Contain '.hidden/file.txt'
        $files | Should -Contain 'visible.txt'
        $files | Should -Not -Contain '.git/internal'
    }

    It 'includes the hidden workflow directory in the real candidate snapshot' {
        $files = @(Get-ConsumerRepositoryFiles -RepositoryRoot $script:RepositoryRoot | ForEach-Object RelativePath)
        $files | Should -Contain '.github/workflows/consumer-gate.yml'
    }

    It 'hashes the exact file bytes without newline normalization' {
        $left = Join-Path $TestDrive 'left.bin'
        $right = Join-Path $TestDrive 'right.bin'
        [IO.File]::WriteAllBytes($left, [byte[]](0, 10, 13, 255))
        [IO.File]::WriteAllBytes($right, [byte[]](0, 10, 13, 254))
        $leftHash = (Get-FileHash -LiteralPath $left -Algorithm SHA256).Hash.ToLowerInvariant()
        $rightHash = (Get-FileHash -LiteralPath $right -Algorithm SHA256).Hash.ToLowerInvariant()
        $leftHash | Should -Not -BeExactly $rightHash
        $leftHash.Length | Should -Be 64
    }
}
