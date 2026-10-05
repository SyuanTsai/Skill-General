# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

function Get-VerifiedCandidateAuthorityRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [Parameter(Mandatory = $true)][object] $AuthorityPin,
        [string] $CoreRunId,
        [string] $CoreCheckId,
        [string] $ScopedAuthorityRoot,
        [string] $TempRoot = [IO.Path]::GetTempPath()
    )

    $coreContextPresent = -not [string]::IsNullOrWhiteSpace($CoreRunId) -or
        -not [string]::IsNullOrWhiteSpace($CoreCheckId)
    if ($coreContextPresent) {
        if ($CoreRunId -cnotmatch '^[0-9a-f]{32}$' -or $CoreCheckId -cne 'repository-pester') {
            throw 'Common tool report Core context is incomplete or invalid.'
        }
        if ([string]::IsNullOrWhiteSpace($ScopedAuthorityRoot)) {
            throw 'Common tool report Core run has no scoped verified authority snapshot.'
        }
        $moduleRoot = [IO.Path]::GetFullPath($ScopedAuthorityRoot)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ScopedAuthorityRoot)) {
        # Explicit local setup is accepted only after the same complete immutable-pin verification.
        $moduleRoot = [IO.Path]::GetFullPath($ScopedAuthorityRoot)
    }
    else {
        if ([string]$AuthorityPin.commit -cnotmatch '^[0-9a-f]{40}$') {
            throw 'Legacy authority transport requires a canonical immutable commit pin.'
        }
        $tempRootFull = [IO.Path]::GetFullPath($TempRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $cursor = $tempRootFull
        while (-not [string]::IsNullOrWhiteSpace($cursor)) {
            $entry = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Legacy TEMP authority transport contains a reparse ancestor.'
            }
            $parent = Split-Path -Parent $cursor
            if ($parent -ceq $cursor) { break }
            $cursor = $parent
        }
        $moduleRoot = [IO.Path]::GetFullPath((Join-Path $tempRootFull ('syp154-authority-' + [string]$AuthorityPin.commit)))
        if (-not $moduleRoot.StartsWith($tempRootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Legacy authority snapshot escaped its TEMP transport directory.'
        }
        if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) {
            throw 'Legacy authority snapshot is missing; validation never downloads or creates runtime authority.'
        }
    }

    if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) {
        throw 'Integration authority snapshot is missing.'
    }
    $cursor = $moduleRoot
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $entry = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Integration authority snapshot contains a reparse ancestor.'
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -ceq $cursor) { break }
        $cursor = $parent
    }

    $gitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
    $safeDirectory = 'safe.directory=' + $moduleRoot
    $gitRoot = @(& $gitPath -c $safeDirectory -C $moduleRoot rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0 -or $gitRoot.Count -ne 1 -or
        -not [IO.Path]::GetFullPath([string]$gitRoot[0]).Equals($moduleRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Integration authority root is not the root of a Git checkout.'
    }
    $head = @(& $gitPath -c $safeDirectory -C $moduleRoot rev-parse --verify HEAD)
    if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or [string]$head[0] -cne [string]$AuthorityPin.commit) {
        throw 'Integration authority checkout HEAD differs from the immutable candidate pin.'
    }
    $origins = @(& $gitPath -c $safeDirectory -C $moduleRoot config --local --get-all remote.origin.url)
    $expectedOrigin = ([string]$AuthorityPin.repository).Trim().TrimEnd('/') -replace '\.git$', ''
    $actualOrigin = if ($origins.Count -eq 1) { (([string]$origins[0]).Trim().TrimEnd('/') -replace '\.git$', '') } else { '' }
    if ($LASTEXITCODE -ne 0 -or $origins.Count -ne 1 -or
        -not $actualOrigin.Equals($expectedOrigin, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Integration authority checkout origin differs from the immutable candidate pin.'
    }
    $authorityDirty = @(& $gitPath -c $safeDirectory -C $moduleRoot status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $authorityDirty.Count -ne 0) {
        throw 'Integration authority checkout must be clean and immutable.'
    }
    foreach ($entry in @($AuthorityPin.files)) {
        $relativePath = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relativePath) -or $relativePath.StartsWith('/') -or
            $relativePath -match '(^|/)\.\.?(/|$)' -or $relativePath.Contains('\')) {
            throw 'Integration authority inventory contains an unsafe relative path.'
        }
        $path = [IO.Path]::GetFullPath((Join-Path $moduleRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
        if (-not $path.StartsWith($moduleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Integration authority inventory escaped its pinned checkout.'
        }
        $cursor = $path
        while ($cursor -cne $moduleRoot) {
            $entryInfo = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($entryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Integration authority inventory traverses a reparse point: $relativePath"
            }
            $cursor = Split-Path -Parent $cursor
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.sha256) {
            throw "Integration authority file identity differs from the immutable candidate pin: $relativePath"
        }
    }
    return $moduleRoot
}
