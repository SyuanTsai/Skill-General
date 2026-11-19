# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Pinned authority bootstrap transport' {
    BeforeAll {
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:BootstrapPath = Join-Path $script:RepositoryRoot 'scripts/Invoke-PinnedAuthority.ps1'
    }

    It 'publishes the four consumer phases without embedding a pin commit' {
        $command = Get-Command -Name $script:BootstrapPath -CommandType ExternalScript
        @($command.Parameters.Keys) | Should -Contain 'Phase'
        @($command.Parameters.Keys) | Should -Contain 'CandidateRoot'
        @($command.Parameters.Keys) | Should -Contain 'WorkRoot'
        $phase = $command.Parameters['Phase']
        $validateSet = @($phase.Attributes | Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })
        $validateSet | Should -HaveCount 1
        (@($validateSet[0].ValidValues) -join "`n") | Should -BeExactly (@('prepare', 'validate', 'finalize', 'aggregate') -join "`n")
        $source = Get-Content -Raw -LiteralPath $script:BootstrapPath
        $source | Should -Not -Match '[0-9a-f]{40}'
        $source | Should -Match 'config/authority-pin\.json'
    }

    It 'keeps the bootstrap and permanent workflow present after conversion cleanup' {
        Test-Path -LiteralPath $script:BootstrapPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/consumer-gate.yml') -PathType Leaf | Should -BeTrue
    }

    It 'reads the transition template only while it exists' {
        $path = Join-Path $script:RepositoryRoot '.github/workflows/consumer-gate-transition.yml'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $content = Get-Content -Raw -LiteralPath $path
            $content | Should -Match '(?m)^\s*pull_request:'
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly '6c78b69f413f9878d9dd73ad42b7bbe5b4442b82617649122e8e8c9bc992132f'
        }
        else {
            Test-Path -LiteralPath $path | Should -BeFalse
        }
    }
}
