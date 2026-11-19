# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Consumer workflow layout' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:WorkflowRoot = Join-Path $script:RepositoryRoot '.github/workflows'
    }

    It 'accepts the conversion workflow set in the current candidate' {
        { Assert-ConsumerWorkflowLayout -WorkflowDirectory $script:WorkflowRoot } | Should -Not -Throw
    }

    It 'accepts a cleanup fixture created directly with only the permanent workflow' {
        $workflowRoot = Join-Path $TestDrive 'cleanup/.github/workflows'
        [void](New-Item -ItemType Directory -Path $workflowRoot -Force)
        [IO.File]::WriteAllText((Join-Path $workflowRoot 'consumer-gate.yml'), 'fixture', [Text.UTF8Encoding]::new($false))
        { Assert-ConsumerWorkflowLayout -WorkflowDirectory $workflowRoot } | Should -Not -Throw
        (Get-ConsumerWorkflowNames -WorkflowDirectory $workflowRoot) | Should -HaveCount 1
    }

    It 'rejects any third workflow' {
        $workflowRoot = Join-Path $TestDrive 'extra/.github/workflows'
        [void](New-Item -ItemType Directory -Path $workflowRoot -Force)
        [IO.File]::WriteAllText((Join-Path $workflowRoot 'consumer-gate.yml'), 'fixture', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $workflowRoot 'third.yml'), 'fixture', [Text.UTF8Encoding]::new($false))
        { Assert-ConsumerWorkflowLayout -WorkflowDirectory $workflowRoot } | Should -Throw '*unsupported file set*'
    }

    It 'uses one REUSE wildcard that covers conversion and cleanup states' {
        $annotations = @(Read-ConsumerReuseAnnotations -LiteralPath (Join-Path $script:RepositoryRoot 'REUSE.toml'))
        $matches = @($annotations | Where-Object { $_.path -ceq '.github/workflows/consumer-gate*.yml' })
        $matches | Should -HaveCount 1
        $pattern = [Management.Automation.WildcardPattern]::new(
            [string]$matches[0].path,
            [Management.Automation.WildcardOptions]::CultureInvariant
        )
        $pattern.IsMatch('.github/workflows/consumer-gate.yml') | Should -BeTrue
        $pattern.IsMatch('.github/workflows/consumer-gate-transition.yml') | Should -BeTrue
    }
}
