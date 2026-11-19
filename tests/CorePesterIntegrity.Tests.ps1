# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Consumer PowerShell and Pester integrity' {
    BeforeAll {
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

        function Get-ConsumerPowerShellAst {
            param([Parameter(Mandatory)][string] $Path)
            $tokens = $null
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
            [pscustomobject]@{ Ast = $ast; Errors = @($errors) }
        }
    }

    It 'parses every repository PowerShell source without an AST error' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'scripts') -Recurse -File -Force |
                Where-Object Extension -In @('.ps1', '.psm1', '.psd1'))
        $files += @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'tests') -Recurse -File -Force |
                Where-Object Extension -In @('.ps1', '.psm1', '.psd1'))
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            $parsed = Get-ConsumerPowerShellAst -Path $file.FullName
            @($parsed.Errors) | Should -HaveCount 0
        }
    }

    It 'contains no skipped or result-overriding Pester command' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'tests') -Filter '*.ps1' -Recurse -File -Force)
        foreach ($file in $files) {
            $parsed = Get-ConsumerPowerShellAst -Path $file.FullName
            $commands = @($parsed.Ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
            @($commands | Where-Object { $_.GetCommandName() -eq 'Set-ItResult' }) | Should -HaveCount 0
            foreach ($command in @($commands | Where-Object { $_.GetCommandName() -eq 'It' })) {
                @($command.CommandElements | Where-Object {
                        $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Skip'
                    }) | Should -HaveCount 0
            }
        }
    }

    It 'keeps literal It names unique within each test file' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'tests') -Filter '*.Tests.ps1' -Recurse -File -Force)
        foreach ($file in $files) {
            $parsed = Get-ConsumerPowerShellAst -Path $file.FullName
            $names = @($parsed.Ast.FindAll({
                        param($node)
                        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'It'
                    }, $true) | ForEach-Object {
                    $literal = @($_.CommandElements | Select-Object -Skip 1 | Where-Object {
                            $_ -is [Management.Automation.Language.StringConstantExpressionAst]
                        } | Select-Object -First 1)
                    if ($literal.Count -eq 1) { [string]$literal[0].Value }
                })
            @($names | Select-Object -Unique).Count | Should -Be $names.Count
        }
    }
}
