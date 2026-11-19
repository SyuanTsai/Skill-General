# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Describe 'Consumer JSON allocation' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'CommonToolAuthoritySupport.ps1')
        $script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

        function Assert-ConsumerPinShape {
            param([Parameter(Mandatory)] $Pin)
            [string[]]$actual = @($Pin.PSObject.Properties.Name)
            [string[]]$expected = @('commit', 'repository', 'schemaVersion')
            [Array]::Sort($actual, [StringComparer]::Ordinal)
            [Array]::Sort($expected, [StringComparer]::Ordinal)
            if (($actual -join "`n") -cne ($expected -join "`n")) { throw 'Pin property set is invalid.' }
            if ($Pin.schemaVersion -ne 1) { throw 'Pin schema version is invalid.' }
            if ([string]$Pin.repository -cne 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git') {
                throw 'Pin repository is invalid.'
            }
            if ([string]$Pin.commit -cnotmatch '^[0-9a-f]{40}$') { throw 'Pin commit is invalid.' }
        }
    }

    It 'stores consumer JSON as UTF-8 without BOM using LF and a final newline' {
        foreach ($name in @('authority-pin.json', 'consumer-gate.json')) {
            $path = Join-Path $script:RepositoryRoot "config/$name"
            [byte[]]$bytes = [IO.File]::ReadAllBytes($path)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) | Should -BeFalse
            $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $text.Contains("`r", [StringComparison]::Ordinal) | Should -BeFalse
            $text.EndsWith("`n", [StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    It 'accepts a routine pin upgrade without binding a specific commit' {
        $pin = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/authority-pin.json')
        $pin.commit = '0123456789abcdef0123456789abcdef01234567'
        { Assert-ConsumerPinShape -Pin $pin } | Should -Not -Throw
    }

    It 'rejects an uppercase or short authority commit' {
        $pin = Read-ConsumerTestJson -LiteralPath (Join-Path $script:RepositoryRoot 'config/authority-pin.json')
        $pin.commit = 'ABCDEF'
        { Assert-ConsumerPinShape -Pin $pin } | Should -Throw '*commit is invalid*'
    }
}
