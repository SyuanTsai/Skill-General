# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0
Set-StrictMode -Version Latest

function Assert-SourceToolRootNoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source tool root has a reparse-point ancestor.' }
        $parent=Split-Path -Parent $cursor
        if($parent -ceq $cursor) { break }
        $cursor=$parent
    }
}

function Get-SourceToolHostRoots {
    param([Parameter(Mandatory)][string]$RunId)
    if($RunId -cnotmatch '^[0-9a-f]{32}$') { throw 'Source tool setup run identity is invalid.' }
    $bases=@([IO.Path]::GetTempPath())
    if(-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $bases+=Join-Path $env:LOCALAPPDATA 'Temp' }
    foreach($base in $bases) { [IO.Path]::GetFullPath((Join-Path $base "svt-tools-$RunId")) }
}

function Assert-SourceToolSetupOwnedRoot {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$PreparedPath,[Parameter(Mandatory)][string]$RunId,[switch]$HostRootOnly)
    $full=[IO.Path]::GetFullPath($Path)
    if($full.IndexOfAny([char[]]"`r`n") -ge 0) { throw 'Source tool root cannot contain a line break.' }
    $allowed=@(Get-SourceToolHostRoots -RunId $RunId)
    if(-not $HostRootOnly) {
        $allowed+=Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($PreparedPath))) "source-tools-$RunId"
    }
    $matches=@($allowed|Where-Object {$full.Equals([IO.Path]::GetFullPath($_),[StringComparison]::OrdinalIgnoreCase)})
    if($matches.Count -eq 0) { throw 'Prepared source setup owned root differs from its exact run-owned location.' }
    if(-not(Test-Path -LiteralPath $full -PathType Container)) { throw 'Prepared source setup owned root is missing.' }
    Assert-SourceToolRootNoReparseAncestors -Path $full
    return $full
}

function Read-SourceToolRootAllocation {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedRunId,[Parameter(Mandatory)][string]$ExpectedSourceRevision)
    if($ExpectedRunId -cnotmatch '^[0-9a-f]{32}$' -or $ExpectedSourceRevision -cnotmatch '^[0-9a-f]{40}$') { throw 'Expected source allocation identity is invalid.' }
    Assert-SourceToolRootNoReparseAncestors -Path $Path
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Source allocation record is not a regular file.' }
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -gt 16384) { throw 'Source allocation record is too large.' }
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $document=[Text.Json.JsonDocument]::Parse($text)
    try {
        $root=$document.RootElement
        if($root.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Source allocation record must be an object.' }
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($property in $root.EnumerateObject()) {
            if(-not $names.Add($property.Name) -or $property.Name -cnotin @('schemaVersion','runId','sourceRevision','ownedRoot')) { throw 'Source allocation record has duplicate or unknown fields.' }
        }
        if($names.Count -ne 4) { throw 'Source allocation record is incomplete.' }
        $version=$root.GetProperty('schemaVersion')
        if($version.ValueKind -ne [Text.Json.JsonValueKind]::Number -or $version.GetInt32() -ne 1) { throw 'Source allocation record schema is invalid.' }
        foreach($name in @('runId','sourceRevision','ownedRoot')) {
            if($root.GetProperty($name).ValueKind -ne [Text.Json.JsonValueKind]::String) { throw 'Source allocation record field type is invalid.' }
        }
        $runId=$root.GetProperty('runId').GetString()
        $source=$root.GetProperty('sourceRevision').GetString()
        if($runId -cne $ExpectedRunId -or $source -cne $ExpectedSourceRevision) { throw 'Source allocation record does not bind this setup run and candidate.' }
        $owned=Assert-SourceToolSetupOwnedRoot -Path $root.GetProperty('ownedRoot').GetString() -PreparedPath $Path -RunId $runId -HostRootOnly
        return [pscustomobject]@{schemaVersion=1;runId=$runId;sourceRevision=$source;ownedRoot=$owned}
    }
    finally { $document.Dispose() }
}

function Remove-SourceToolRootAllocation {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedRunId,[Parameter(Mandatory)][string]$ExpectedSourceRevision)
    $allocation=Read-SourceToolRootAllocation -Path $Path -ExpectedRunId $ExpectedRunId -ExpectedSourceRevision $ExpectedSourceRevision
    $directories=[Collections.Generic.Stack[string]]::new()
    $directories.Push($allocation.ownedRoot)
    while($directories.Count) {
        foreach($entry in @(Get-ChildItem -LiteralPath $directories.Pop() -Force -ErrorAction Stop)) {
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source tool cleanup refuses a reparse point in its owned tree.' }
            if($entry.PSIsContainer) { $directories.Push($entry.FullName) }
        }
    }
    # Recheck the exact root after inspection; remove no parent or sibling path.
    [void](Assert-SourceToolSetupOwnedRoot -Path $allocation.ownedRoot -PreparedPath $Path -RunId $ExpectedRunId -HostRootOnly)
    Remove-Item -LiteralPath $allocation.ownedRoot -Recurse -Force -ErrorAction Stop
    if(Test-Path -LiteralPath $allocation.ownedRoot) { throw 'Source tool cleanup did not remove the exact allocated root.' }
}

Export-ModuleMember -Function Assert-SourceToolSetupOwnedRoot,Read-SourceToolRootAllocation,Remove-SourceToolRootAllocation
