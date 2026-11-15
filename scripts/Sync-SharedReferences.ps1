# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]
param([switch] $Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$sourceRelativePath = 'shared/references/environment-separation.md'
$targetRelativePaths = @(
    'skills/manage-ai-memory/references/environment-separation.md',
    'skills/manage-task-handoff/references/environment-separation.md'
)

function Test-SharedReferenceBytesEqual {
    param([Parameter(Mandatory)][byte[]] $Left, [Parameter(Mandatory)][byte[]] $Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Assert-SafeSharedReferenceTarget {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath,
        [switch] $RequireFile
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) { throw "Shared reference target must be repository-relative: $RelativePath" }
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, $comparison)) { throw "Shared reference target escaped the repository: $RelativePath" }

    $rootItem = Get-Item -LiteralPath $fullRoot -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Shared reference repository root must be a regular non-reparse directory.'
    }
    $ancestor = [IO.Path]::GetDirectoryName($fullPath)
    while (-not $ancestor.Equals($fullRoot, $comparison)) {
        $ancestorItem = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
        if (-not $ancestorItem.PSIsContainer -or ($ancestorItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Shared reference target has a linked or non-directory ancestor: $RelativePath"
        }
        $parent = [IO.Path]::GetDirectoryName($ancestor)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($ancestor, $comparison)) {
            throw "Shared reference target ancestry escaped the repository: $RelativePath"
        }
        $ancestor = $parent
    }

    $targetItem = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $targetItem) {
        if ($targetItem.PSIsContainer -or ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Shared reference target must be a regular non-reparse file: $RelativePath"
        }
        if ($targetItem.LinkType -eq 'HardLink') {
            throw "Shared reference source or target must not be a hardlink: $RelativePath"
        }
    }
    elseif ($RequireFile) {
        throw "Shared reference source is missing: $RelativePath"
    }
    return $fullPath
}

function Write-SharedReferenceTarget {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][byte[]] $Bytes)
    # Test-only failure seam: normal developer invocations do not define this
    # function. Native Unix tests inject a partial write followed by an error so
    # the generator's no-delete behavior is covered without relying on FileShare.
    if ($null -ne (Get-Command Invoke-SGSharedReferenceWriterTestSeam -CommandType Function -ErrorAction SilentlyContinue)) {
        Invoke-SGSharedReferenceWriterTestSeam -Path $Path -Bytes $Bytes
        return
    }
    # Developer-only generator exception, following the reviewed precedent in
    # Build-AiInstructions.ps1:249-272. The fixed target list and link checks
    # above are the boundary for this one direct WriteAllBytes call.
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

$sourcePath = Assert-SafeSharedReferenceTarget -Root $repositoryRoot -RelativePath $sourceRelativePath -RequireFile
[byte[]]$expectedBytes = [IO.File]::ReadAllBytes($sourcePath)
$drift = [Collections.Generic.List[string]]::new()
foreach ($relativePath in $targetRelativePaths) {
    $targetPath = Assert-SafeSharedReferenceTarget -Root $repositoryRoot -RelativePath $relativePath
    $matches = $false
    if ([IO.File]::Exists($targetPath)) {
        [byte[]]$actualBytes = [IO.File]::ReadAllBytes($targetPath)
        $matches = Test-SharedReferenceBytesEqual -Left $expectedBytes -Right $actualBytes
    }
    if (-not $matches) {
        $drift.Add($relativePath)
        if (-not $Check) { Write-SharedReferenceTarget -Path $targetPath -Bytes $expectedBytes }
    }
}

if ($Check -and $drift.Count -gt 0) {
    foreach ($relativePath in $drift) { Write-Output "Shared reference drift: $relativePath" }
    throw 'Shared references are not generated from the authoritative source.'
}
if ($Check) { Write-Output ('Shared references are current ({0} files).' -f $targetRelativePaths.Count) }
else { Write-Output ('Synchronized {0} shared references; changed {1}.' -f $targetRelativePaths.Count, $drift.Count) }
