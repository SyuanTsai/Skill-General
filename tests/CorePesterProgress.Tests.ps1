# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Complete consumer Pester discovery' {
    BeforeAll {
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

        function Get-ConsumerTestFileInventory {
            param([Parameter(Mandatory)][string] $Root)
            [string[]]$files = @(Get-ChildItem -LiteralPath $Root -Filter '*.Tests.ps1' -Recurse -File -Force |
                    ForEach-Object { [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') })
            [Array]::Sort($files, [StringComparer]::Ordinal)
            return $files
        }
    }

    It 'discovers every test container in ordinal case-sensitive order' {
        $root = Join-Path $script:RepositoryRoot 'tests'
        [string[]]$actual = @(Get-ConsumerTestFileInventory -Root $root)
        $actual.Count | Should -BeGreaterThan 0
        [string[]]$expected = @(Get-ChildItem -LiteralPath $root -Filter '*.Tests.ps1' -Recurse -File -Force |
                ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') })
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'includes hidden test containers when enumerating a snapshot' {
        $root = Join-Path $TestDrive 'tests'
        [void](New-Item -ItemType Directory -Path $root -Force)
        [IO.File]::WriteAllText((Join-Path $root '.hidden.Tests.ps1'), "It 'hidden' { `$true | Should -BeTrue }", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $root 'visible.Tests.ps1'), "It 'visible' { `$true | Should -BeTrue }", [Text.UTF8Encoding]::new($false))
        [string[]]$actual = @(Get-ConsumerTestFileInventory -Root $root)
        $actual | Should -Contain '.hidden.Tests.ps1'
        $actual | Should -Contain 'visible.Tests.ps1'
    }

    It 'requires each discovered container to register at least one case' {
        foreach ($relative in @(Get-ConsumerTestFileInventory -Root (Join-Path $script:RepositoryRoot 'tests'))) {
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile(
                (Join-Path (Join-Path $script:RepositoryRoot 'tests') $relative),
                [ref]$tokens,
                [ref]$errors
            )
            @($errors) | Should -HaveCount 0
            @($ast.FindAll({
                        param($node)
                        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'It'
                    }, $true)).Count | Should -BeGreaterThan 0
        }
    }
}
