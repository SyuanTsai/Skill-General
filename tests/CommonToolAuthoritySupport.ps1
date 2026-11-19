# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

function Assert-ConsumerJsonNoDuplicateProperties {
    param(
        [Parameter(Mandatory)][Text.Json.JsonElement] $Element,
        [Parameter(Mandatory)][string] $Context
    )

    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { throw "$Context has duplicate or case-conflicting keys." }
            Assert-ConsumerJsonNoDuplicateProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-ConsumerJsonNoDuplicateProperties -Element $item -Context "$Context[$index]"
            $index++
        }
    }
}

function Read-ConsumerTestJson {
    param([Parameter(Mandatory)][string] $LiteralPath)

    [byte[]]$bytes = [IO.File]::ReadAllBytes($LiteralPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw 'Consumer JSON must not contain a UTF-8 BOM.'
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $document = [Text.Json.JsonDocument]::Parse($text)
    try { Assert-ConsumerJsonNoDuplicateProperties -Element $document.RootElement -Context '$' }
    finally { $document.Dispose() }
    $text | ConvertFrom-Json -Depth 50 -ErrorAction Stop
}

function Get-ConsumerWorkflowNames {
    param([Parameter(Mandatory)][string] $WorkflowDirectory)

    [string[]]$names = @(Get-ChildItem -LiteralPath $WorkflowDirectory -File -Force | ForEach-Object Name)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return $names
}

function Assert-ConsumerWorkflowLayout {
    param([Parameter(Mandatory)][string] $WorkflowDirectory)

    $items = @(Get-ChildItem -LiteralPath $WorkflowDirectory -Recurse -Force)
    if (@($items | Where-Object PSIsContainer).Count -ne 0) {
        throw 'The workflow directory contains an unsupported file set.'
    }
    foreach ($file in @($items)) {
        if ([IO.Path]::GetRelativePath($WorkflowDirectory, $file.FullName).Contains([IO.Path]::DirectorySeparatorChar)) {
            throw 'The workflow directory contains an unsupported file set.'
        }
    }
    [string[]]$actual = @(Get-ConsumerWorkflowNames -WorkflowDirectory $WorkflowDirectory)
    [string[]]$permanentOnly = @('consumer-gate.yml')
    [string[]]$conversion = @('consumer-gate-transition.yml', 'consumer-gate.yml')
    [Array]::Sort($conversion, [StringComparer]::Ordinal)
    $actualText = $actual -join "`n"
    if ($actualText -cne ($permanentOnly -join "`n") -and $actualText -cne ($conversion -join "`n")) {
        throw 'The workflow directory contains an unsupported file set.'
    }
}

function Complete-ConsumerReuseAnnotation {
    param(
        [Parameter(Mandatory)][Collections.IDictionary] $Current,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]] $Annotations
    )

    [string[]]$actual = @($Current.Keys)
    [string[]]$expected = @('SPDX-FileCopyrightText', 'SPDX-License-Identifier', 'path', 'precedence')
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    [Array]::Sort($expected, [StringComparer]::Ordinal)
    if (($actual -join "`n") -cne ($expected -join "`n")) {
        throw 'REUSE annotation does not contain exactly the four required keys.'
    }
    $Annotations.Add([pscustomobject]$Current)
}

function Read-ConsumerReuseAnnotations {
    param([Parameter(Mandatory)][string] $LiteralPath)

    $annotations = [Collections.Generic.List[object]]::new()
    $current = $null
    $versionSeen = $false
    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $LiteralPath -Encoding utf8) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#', [StringComparison]::Ordinal)) { continue }
        if ($line -eq 'version = 1') {
            if ($versionSeen -or $null -ne $current -or $annotations.Count -gt 0) {
                throw "Invalid REUSE version declaration at line $lineNumber."
            }
            $versionSeen = $true
            continue
        }
        if ($line -eq '[[annotations]]') {
            if ($null -ne $current) { Complete-ConsumerReuseAnnotation -Current $current -Annotations $annotations }
            $current = [ordered]@{}
            continue
        }
        if ($null -eq $current -or $line -notmatch '^(?<Key>path|precedence|SPDX-FileCopyrightText|SPDX-License-Identifier)\s*=\s*(?<Value>"(?:[^"\\]|\\.)*")$') {
            throw "Unsupported REUSE syntax at line $lineNumber."
        }
        $key = [string]$Matches.Key
        if ($current.Contains($key)) { throw "Duplicate REUSE key at line $lineNumber." }
        $current[$key] = [string](ConvertFrom-Json -InputObject ([string]$Matches.Value) -ErrorAction Stop)
    }
    if (-not $versionSeen) { throw 'REUSE version declaration is missing.' }
    if ($null -ne $current) { Complete-ConsumerReuseAnnotation -Current $current -Annotations $annotations }
    if ($annotations.Count -eq 0) { throw 'REUSE annotations are missing.' }
    return @($annotations)
}

function Get-ConsumerRepositoryFiles {
    param([Parameter(Mandatory)][string] $RepositoryRoot)

    return @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Force | ForEach-Object {
            $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName).Replace('\', '/')
            if ($relative -cne '.git' -and -not $relative.StartsWith('.git/', [StringComparison]::Ordinal)) {
                [pscustomobject]@{ FullName = $_.FullName; RelativePath = $relative }
            }
        })
}
