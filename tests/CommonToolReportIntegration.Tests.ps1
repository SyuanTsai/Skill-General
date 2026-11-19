# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Consumer configuration integration' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $script:GatePath = Join-Path $script:RepositoryRoot 'config/consumer-gate.json'
        $script:SourcePath = Join-Path $script:RepositoryRoot 'catalog/source.json'
    }

    It 'uses the exact consumer configuration property set' {
        $gate = Read-ConsumerTestJson -LiteralPath $script:GatePath
        [string[]]$actual = @($gate.PSObject.Properties.Name)
        [string[]]$expected = @('activeSkills', 'repositoryChecks', 'repositoryId', 'schemaVersion', 'sourceRepository')
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        [Array]::Sort($expected, [StringComparer]::Ordinal)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
        $gate.schemaVersion | Should -Be 1
        $gate.repositoryId | Should -BeExactly 'skill-general'
        $gate.sourceRepository | Should -BeExactly 'https://github.com/SyuanTsai/Skill-General.git'
    }

    It 'binds every declared check to an existing repository path' {
        $gate = Read-ConsumerTestJson -LiteralPath $script:GatePath
        foreach ($check in @($gate.repositoryChecks)) {
            [string[]]$actual = @($check.PSObject.Properties.Name)
            [string[]]$expected = @('id', 'kind', 'path')
            [Array]::Sort($actual, [StringComparer]::Ordinal)
            [Array]::Sort($expected, [StringComparer]::Ordinal)
            ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
            Test-Path -LiteralPath (Join-Path $script:RepositoryRoot ([string]$check.path)) | Should -BeTrue
        }
    }

    It 'keeps source and gate identities aligned case-sensitively' {
        $gate = Read-ConsumerTestJson -LiteralPath $script:GatePath
        $source = Read-ConsumerTestJson -LiteralPath $script:SourcePath
        $gate.sourceRepository | Should -BeExactly $source.repository
        (@($gate.activeSkills) -join "`n") | Should -BeExactly (@($source.skills) -join "`n")
    }

    It 'rejects duplicate keys and a UTF-8 BOM before materialization' {
        $duplicatePath = Join-Path $TestDrive 'duplicate.json'
        [IO.File]::WriteAllText($duplicatePath, '{"schemaVersion":1,"SchemaVersion":1}', [Text.UTF8Encoding]::new($false))
        { Read-ConsumerTestJson -LiteralPath $duplicatePath } | Should -Throw '*duplicate or case-conflicting keys*'

        $bomPath = Join-Path $TestDrive 'bom.json'
        [IO.File]::WriteAllText($bomPath, '{"schemaVersion":1}', [Text.UTF8Encoding]::new($true))
        { Read-ConsumerTestJson -LiteralPath $bomPath } | Should -Throw '*must not contain a UTF-8 BOM*'
    }
}
