# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Read-only repository check envelope' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:CheckPath = Join-Path $script:RepositoryRoot 'scripts/Test-SkillGeneral.ps1'

        function Get-RepositorySnapshotIdentity {
            param([Parameter(Mandatory)][string] $Root)
            $rows = @(Get-ConsumerRepositoryFiles -RepositoryRoot $Root | ForEach-Object {
                    '{0}`t{1}' -f $_.RelativePath, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                })
            [Array]::Sort($rows, [StringComparer]::Ordinal)
            return $rows -join "`n"
        }
    }

    It 'returns a passing machine report for the complete source inventory' {
        $output = @(& $script:CheckPath -RepositoryRoot $script:RepositoryRoot -ReadOnlySnapshot)
        $text = $output -join "`n"
        $jsonStart = $text.IndexOf('{', [StringComparison]::Ordinal)
        ($jsonStart -ge 0) | Should -BeTrue
        $report = $text.Substring($jsonStart) | ConvertFrom-Json -Depth 50
        $report.result | Should -BeExactly 'passed'
        $report.sourceId | Should -BeExactly 'general'
        $report.activeSkillCount | Should -Be @($report.skills).Count
        $report.activeSkillCount | Should -BeGreaterThan 0
    }

    It 'does not change candidate bytes in read-only snapshot mode' {
        $before = Get-RepositorySnapshotIdentity -Root $script:RepositoryRoot
        $null = @(& $script:CheckPath -RepositoryRoot $script:RepositoryRoot -ReadOnlySnapshot)
        $after = Get-RepositorySnapshotIdentity -Root $script:RepositoryRoot
        $after | Should -BeExactly $before
    }
}
