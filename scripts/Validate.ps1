# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('Run', 'PrepareSemantic', 'ResumeSemantic')]
    [string] $ExecutionMode = 'Run',
    [string] $RepositoryRoot,
    [string] $ArtifactsRoot = $(
        if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { $env:RUNNER_TEMP }
        else { [IO.Path]::GetTempPath() }
    ),
    [string] $AuthorityArchivePath,
    [string] $BaseCommit,
    [string] $ExpectedGoRuntimeVersion = $env:STANDARD_GO_RUNTIME_VERSION,
    [string] $OutputPath,
    [int] $TimeoutSeconds = 900,
    [switch] $SemanticConsent,
    [string] $SemanticProvider,
    [string] $SemanticPurpose,
    [string] $SemanticScope,
    [string] $SemanticEvidencePath,
    [string] $SemanticConsentRequestPath,
    [string] $SemanticConsentDecisionPath,
    [string] $SemanticPublicKeyPath,
    [string] $SemanticPublicKeyId,
    [string] $SemanticRunPlanPath,
    [switch] $SemanticTriggered
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SourceRepository = 'https://github.com/SyuanTsai/Skill-General.git'
$script:AuthorityRepository = 'https://github.com/SyuanTsai/SyuanTsai-AI-Instructions.git'
$script:AuthorityCommit = '8a944f4a74a054cb0353f22ab22c459dc9dc18ef'
$script:AuthorityArchiveSha256 = '99ba8cae62c80db9da8876b5a7e49dfdd499ca863c006bfd2a411a5d4e7dbcc0'
$script:AuthorityFiles = [ordered]@{
    'docs/standards/README.md' = '5e1ddd737d26a5ec1ff1ebd08e158376ddaf1ea21008bb987fc7f51376923f7c'
    'docs/standards/managed-skill-lifecycle.md' = '70950cf8bdd02819efae6f6e06ac5be1da3e70f809c23e3c6f8d3b217797416c'
    'docs/standards/schemas/managed-skill-lifecycle-v1.schema.json' = '9a7f4c02588d2b88194e953a41766a72a9426fa89d4c3781c5750dcc22d35863'
    'docs/standards/schemas/openai-agent-metadata.schema.json' = '23c1aaee28a54fea1946a61d6122a2097906ffa5bdd66c8014fc6b1625c9062a'
    'docs/standards/schemas/source-inventory-v2.schema.json' = '084550944b4141ab5535f58fb6e99730a5c34b56103f6b59fd5a352679caa98e'
    'docs/standards/schemas/validation-security-gate-v1.schema.json' = 'a69e11d41697feae79f8322ce2115352af97cefd2eb0af809b4d47f241b3c3f2'
    'docs/standards/skill-repository-review-matrix.md' = '315204afe428bb51cab5e815b2c40f6d0cbd55c81a3532ad59b686ae5e4c166c'
    'docs/standards/skill-repository-standard.md' = '585d74097cca9413aba8c153be34ff53165c0acc058ef1fdbcf12ba8e954edb7'
    'docs/standards/upstream-interoperability.md' = '9c544fbfb6b77a589514f1926aa1488882e932786a303a42ce6c6c9b2ba80c7e'
    'docs/standards/validation-security-gate.json' = '81d4eadcb38a573f218b49d9c5555d609f89e13c2cf1ad63f0ee6422c9ecc33c'
    'docs/standards/validation-toolchain.json' = '5925dcb1aea1e545b9787a29825e7a0cc03a04c777cd68ab44c9bdd7482ff579'
    'scripts/Invoke-StandardAuthorityGate.ps1' = '22d70074762437daf926a1afe3ff1def2f57efed7c7a6b41f1c390d68cb664d7'
    'scripts/Resolve-PythonWheelClosure.py' = '7fa1511a3e3ba257c6d9e37f929f68e5684184a3a2756a3f9e765ccc6e69d208'
    'scripts/Resolve-StandardValidationTool.ps1' = '07cb7d9bf35aaee1e3d0fc8af1837582e588227cbcb2e29cd4a5e4b610754a15'
    'docs/standards/schemas/standard-validation-adapter-v1.schema.json' = '1b45052712450d40df278937d381018b9ce2ded2cbf42845db65f8028e56df44'
    'docs/standards/schemas/standard-validation-evidence-v1.schema.json' = '7abb4cea105eecc97f0b190930b77297336595ffb4d26cf04b0ea1071a79f483'
    'docs/standards/standard-validation-contract-v1.json' = '503a93a443629eec6572c642fa324e3d5bd4b0b857ca3b1b3ae265e132f05404'
    'docs/standards/trust-anchors/human-approval-public-key.xml' = '1e46153b72d02f3ce2fb26becd449df4f1590d8e5cb441b1954006a5602bbd9b'
    'docs/standards/trust-anchors/trusted-supervisor-public-key.xml' = '4d550851f43405920156f40c9fc648d99a69dd73efc200f6968d8a837e7fbf27'
    'scripts/Invoke-StandardValidation.ps1' = 'a1ff12b3d2127975813df044495aa14763cd2b640fbdb2f0534975f3721eaaa2'
    'docs/standards/schemas/standard-semantic-consent-evidence-v2.schema.json' = '561e9bb167c1c4d5ce1a438eeca13df9d2623b8fe6dbb31973427f462f97eb55'
    'scripts/StandardSemanticBridge.psm1' = 'f61d3a4166b8e312d9f4090cb72e8af37056d88f2936cb22ecdd1fb389b191cc'
    'docs/standards/schemas/upstream-adapter-v1.schema.json' = '3cff6246463188a91cc54c6a46315a949314767a759c6214e5b28e4db95ac8d7'
    'docs/standards/upstream-adapter.json' = 'c4f5133b24841bb9c66182dc3d5a027596f864ec28e410d47249a67b3b97ad31'
    'scripts/Validate-UpstreamAdapter.ps1' = '7fd3c2c34544b21b769ebfa9238c379e094e022381b7ebe11f3e196e623fd376'
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)][string[]] $Expected,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if ($null -eq $Value -or $Value -is [array] -or $Value -is [string] -or $null -eq $Value.PSObject) {
        throw "$Context must be a JSON object."
    }
    $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $missing = @($Expected | Where-Object { $actual -cnotcontains $_ })
    $unexpected = @($actual | Where-Object { $Expected -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0 -or $actual.Count -ne $Expected.Count) {
        throw "$Context has an invalid property set. Missing='$($missing -join ',')' Unexpected='$($unexpected -join ',')'."
    }
}

function Assert-NoDuplicateJsonProperties {
    param(
        [Parameter(Mandatory = $true)][System.Text.Json.JsonElement] $Element,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "$Context contains duplicate JSON property '$($property.Name)'." }
            Assert-NoDuplicateJsonProperties -Element $property.Value -Context "$Context.$($property.Name)"
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-NoDuplicateJsonProperties -Element $item -Context "$Context[$index]"
            $index++
        }
    }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Context
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Context is missing: $Path" }
    try {
        $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        $document = [System.Text.Json.JsonDocument]::Parse($text)
        try { Assert-NoDuplicateJsonProperties -Element $document.RootElement -Context $Context }
        finally { $document.Dispose() }
        return $text | ConvertFrom-Json -Depth 100
    }
    catch { throw "$Context is not valid unambiguous UTF-8 JSON: $($_.Exception.Message)" }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Value, [Parameter(Mandatory = $true)][string] $Context)
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Context must be a lowercase SHA-256 value." }
}

function Test-PathWithinOrEqual {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $fullPath.Equals($fullRoot, $comparison) -or
        $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Test-PathEqual {
    param([Parameter(Mandatory = $true)][string] $Left, [Parameter(Mandatory = $true)][string] $Right)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), $comparison)
}

function Assert-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Context
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinOrEqual -Path $fullPath -Root $Root)) { throw "$Context must stay within '$Root': $Path" }
    return $fullPath
}

function Assert-OutsideRoot {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Context
    )
    if (Test-PathWithinOrEqual -Path $Path -Root $Root) { throw "$Context must be outside '$Root': $Path" }
}

function Assert-NoReparseAncestors {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Context)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Context is backed by a reparse point: $current" }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) { break }
        $current = $parent
    }
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $Text, [Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomCreateNew {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Text)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $stream = $null
    try {
        $stream = [IO.File]::Open($fullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-ResolvedGitPath {
    $command = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return [IO.Path]::GetFullPath([string]$command.Path)
}

function Get-ResolvedPowerShellPath {
    $command = Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return [IO.Path]::GetFullPath([string]$command.Path)
}

function Resolve-GitRevision {
    param(
        [Parameter(Mandatory = $true)][string] $GitPath,
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Revision,
        [Parameter(Mandatory = $true)][string] $Context
    )
    $output = @(& $GitPath -C $Root rev-parse --verify --end-of-options "$Revision^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or ([string]$output[0]).Trim() -cnotmatch '^[0-9a-f]{40}$') {
        throw "$Context '$Revision' does not resolve to one immutable commit."
    }
    return ([string]$output[0]).Trim()
}

function Resolve-GoRuntimeVersion {
    param([string] $Expected)
    if (-not [string]::IsNullOrWhiteSpace($Expected)) {
        if ($Expected -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw 'ExpectedGoRuntimeVersion must be a stable semantic Go version.' }
        return $Expected
    }
    $go = Get-Command go -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $output = @(& $go.Path version)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or [string]$output[0] -notmatch '^go version go(?<version>[0-9]+\.[0-9]+\.[0-9]+)\s') {
        throw 'Could not resolve the current stable Go runtime version.'
    }
    return [string]$Matches.version
}

function Get-EventName {
    $event = [string]$env:GITHUB_EVENT_NAME
    switch ($event) {
        'pull_request' { return 'pull_request' }
        'push' { return 'push' }
        'workflow_dispatch' { return 'workflow_dispatch' }
        'pre-push' { return 'pre-push' }
        default { return 'local' }
    }
}

function Assert-AuthorityConfig {
    param([Parameter(Mandatory = $true)] $Config)

    Assert-ExactPropertySet -Value $Config -Expected @('schemaVersion', 'standardVersion', 'authority') -Context 'config/standard-v1.json'
    Assert-ExactPropertySet -Value $Config.authority -Expected @('repository', 'commit', 'archiveUrl', 'archiveSha256', 'files') -Context 'config/standard-v1.json authority'
    if ($Config.schemaVersion -ne 1 -or $Config.standardVersion -cne 'v1' -or
        $Config.authority.repository -cne $script:AuthorityRepository -or
        $Config.authority.commit -cne $script:AuthorityCommit -or
        $Config.authority.archiveUrl -cne "https://codeload.github.com/SyuanTsai/SyuanTsai-AI-Instructions/zip/$($script:AuthorityCommit)" -or
        $Config.authority.archiveSha256 -cne $script:AuthorityArchiveSha256) {
        throw 'config/standard-v1.json is not bound to the exact approved P02 authority snapshot.'
    }
    Assert-Sha256 -Value ([string]$Config.authority.archiveSha256) -Context 'Authority archive identity'
    if ($Config.authority.files -isnot [array] -or @($Config.authority.files).Count -ne $script:AuthorityFiles.Count) {
        throw 'config/standard-v1.json authority file inventory is incomplete.'
    }
    $expectedPaths = @($script:AuthorityFiles.Keys)
    for ($index = 0; $index -lt $expectedPaths.Count; $index++) {
        $file = @($Config.authority.files)[$index]
        Assert-ExactPropertySet -Value $file -Expected @('path', 'sha256') -Context 'config/standard-v1.json authority file'
        if ([string]$file.path -cne [string]$expectedPaths[$index] -or
            [string]$file.sha256 -cne [string]$script:AuthorityFiles[$expectedPaths[$index]]) {
            throw "config/standard-v1.json authority file identity mismatch at index $index."
        }
    }
}

function Get-ActiveSkillIds {
    param([Parameter(Mandatory = $true)][string] $Root)
    $inventory = Read-JsonFile -Path (Join-Path $Root 'catalog/source.json') -Context 'catalog/source.json'
    Assert-ExactPropertySet -Value $inventory -Expected @('schemaVersion', 'sourceId', 'repository', 'skillsRoot', 'skills') -Context 'catalog/source.json'
    if ($inventory.schemaVersion -ne 2 -or $inventory.sourceId -cne 'general' -or
        $inventory.repository -cne $script:SourceRepository -or $inventory.skillsRoot -cne 'skills' -or
        $inventory.skills -isnot [array] -or @($inventory.skills).Count -eq 0) {
        throw 'catalog/source.json is not the strict General source inventory.'
    }
    if (Test-Path -LiteralPath (Join-Path $Root 'catalog/skills-catalog.json') -PathType Leaf) {
        throw 'Legacy source-owned cross-source catalog must not coexist with catalog/source.json.'
    }
    if (Test-Path -LiteralPath (Join-Path $Root '.agents/skills')) {
        throw 'Legacy .agents/skills source root must not coexist with canonical skills/.'
    }
    [string[]]$declared = @($inventory.skills | ForEach-Object {
        if ($_ -isnot [string] -or [string]$_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Invalid Skill ID in catalog/source.json: '$_'." }
        [string]$_
    })
    [string[]]$sorted = @($declared)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($skillId in $declared) { if (-not $seen.Add($skillId)) { throw "Duplicate Skill ID '$skillId'." } }
    if (($declared -join "`n") -cne ($sorted -join "`n")) { throw 'catalog/source.json skills must use ordinal ascending order.' }
    $skillsRoot = Join-Path $Root 'skills'
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) { throw 'Canonical skills/ source root is missing.' }
    $actual = @(Get-ChildItem -LiteralPath $skillsRoot -Directory -Force | ForEach-Object { [string]$_.Name })
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    if (($actual -join "`n") -cne ($sorted -join "`n")) { throw 'catalog/source.json inventory does not exactly match skills/ directories.' }
    return $sorted
}

function Invoke-Resolver {
    param(
        [Parameter(Mandatory = $true)][string] $PowerShellPath,
        [Parameter(Mandatory = $true)][string] $ResolverPath,
        [Parameter(Mandatory = $true)][string[]] $Arguments
    )
    & $PowerShellPath -NoProfile -NonInteractive -File $ResolverPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Validation tool resolver failed with exit code $LASTEXITCODE." }
}

$childRunnerText = @'
# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('package-adapter', 'skill-validator', 'skill-tools', 'static', 'repository-general', 'repository-pester')][string] $Mode,
    [Parameter(Mandatory = $true)][string] $ToolchainPath,
    [Parameter(Mandatory = $true)][string] $ToolchainSha256,
    [string] $SourceRepository,
    [string] $SourceRevision,
    [string] $ArchiveSha256,
    [string] $SemanticRequired = 'false'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Assert-FileIdentity {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Sha256, [Parameter(Mandatory = $true)][string] $Context)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-FileSha256 -Path $Path) -cne $Sha256) { throw "$Context changed or is missing." }
}
function Get-Property {
    param([Parameter(Mandatory = $true)] $Object, [Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string] $Context)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { throw "$Context is missing '$Name'." }
    return $Object.PSObject.Properties[$Name].Value
}
function Read-Json {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Context)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Context is missing: $Path" }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100) }
    catch { throw "$Context is not valid JSON: $($_.Exception.Message)" }
}
function Test-PathEqual {
    param([Parameter(Mandatory = $true)][string] $Left, [Parameter(Mandatory = $true)][string] $Right)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), $comparison)
}
function Test-PathWithin {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $fullPath.Equals($fullRoot, $comparison) -or $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, $comparison)
}
function Get-ActiveSkills {
    $values = @([string]$env:STANDARD_VALIDATION_ACTIVE_SKILLS -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($values.Count -eq 0) { throw 'Central runner did not provide active Skill identities.' }
    return [string[]]$values
}
function Get-SkillRoot {
    param([Parameter(Mandatory = $true)][string] $SkillId)
    $skillsRoot = [IO.Path]::GetFullPath([string]$env:STANDARD_VALIDATION_SKILLS_ROOT)
    $skillRoot = [IO.Path]::GetFullPath((Join-Path $skillsRoot $SkillId))
    if (-not (Test-PathWithin -Path $skillRoot -Root $skillsRoot) -or -not (Test-Path -LiteralPath $skillRoot -PathType Container)) {
        throw "Central runner supplied an unsafe or missing Skill root: $SkillId"
    }
    return $skillRoot
}
function Get-InventoryPaths {
    param([Parameter(Mandatory = $true)][string] $SkillRoot)
    $root = [IO.Path]::GetFullPath($SkillRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $paths = @(
        Get-ChildItem -LiteralPath $root -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($root.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Replace([IO.Path]::DirectorySeparatorChar, '/') }
    )
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    if ($paths.Count -eq 0) { throw "Skill inventory is empty: $SkillRoot" }
    return [string[]]$paths
}
function Resolve-ReportedFilePath {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)][string] $SkillRoot,
        [Parameter(Mandatory = $true)][string[]] $ExpectedPaths,
        [Parameter(Mandatory = $true)][string] $Context
    )
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) { throw "$Context must identify a file." }
    $candidate = [string]$Value
    if ($candidate -cmatch '^file:') {
        $uri = $null
        if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -or -not $uri.IsFile) { throw "$Context must be a local file." }
        $candidate = $uri.LocalPath
    }
    elseif (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $SkillRoot $candidate }
    $full = [IO.Path]::GetFullPath($candidate)
    if (-not (Test-PathWithin -Path $full -Root $SkillRoot)) { throw "$Context escapes the Skill root." }
    foreach ($relative in $ExpectedPaths) {
        if (Test-PathEqual -Left $full -Right (Join-Path $SkillRoot $relative)) { return $full }
    }
    throw "$Context is outside the candidate-bound inventory."
}
function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string] $Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function New-Finding {
    param([Parameter(Mandatory = $true)] $Issue, [Parameter(Mandatory = $true)][string] $SkillId, [Parameter(Mandatory = $true)][string] $Stage)
    $severity = [string](Get-Property -Object $Issue -Name 'severity' -Context "$Stage issue").ToLowerInvariant()
    $severity = switch ($severity) {
        'critical' { 'critical'; break }
        'high' { 'high'; break }
        'medium' { 'medium'; break }
        'low' { 'low'; break }
        'informational' { 'informational'; break }
        'info' { 'informational'; break }
        default { throw "$Stage returned unsupported severity '$severity' for '$SkillId'." }
    }
    $issueJson = $Issue | ConvertTo-Json -Depth 30 -Compress
    $path = if ($null -ne $Issue.PSObject.Properties['file']) { [string]$Issue.file } elseif ($null -ne $Issue.PSObject.Properties['path']) { [string]$Issue.path } else { '' }
    return [ordered]@{
        severity = $severity
        fingerprint = Get-TextSha256 -Text $issueJson
        ruleId = if ($null -ne $Issue.PSObject.Properties['rule_id']) { [string]$Issue.rule_id } elseif ($null -ne $Issue.PSObject.Properties['ruleId']) { [string]$Issue.ruleId } else { $Stage }
        message = if ($null -ne $Issue.PSObject.Properties['message']) { [string]$Issue.message } else { $issueJson }
        path = $path
        skillId = $SkillId
    }
}
function New-Envelope {
    param(
        [Parameter(Mandatory = $true)][string[]] $ActiveSkills,
        [array] $Findings = @(),
        [hashtable] $Additional
    )
    $value = [ordered]@{
        schemaVersion = 1
        status = 'passed'
        decision = 'PASS'
        candidateIdentity = [string]$env:STANDARD_VALIDATION_CANDIDATE_ID
        activeSkills = @($ActiveSkills)
        findings = @($Findings)
    }
    if ($null -ne $Additional) {
        foreach ($key in $Additional.Keys) { $value[$key] = $Additional[$key] }
    }
    [Console]::Out.WriteLine(($value | ConvertTo-Json -Depth 100 -Compress))
    exit 0
}
function Invoke-NativeJson {
    param([Parameter(Mandatory = $true)][string] $Command, [Parameter(Mandatory = $true)][string[]] $Arguments, [Parameter(Mandatory = $true)][string] $Context)
    $stderrPath = Join-Path (Get-Location) (([guid]::NewGuid().ToString('N')) + '.stderr')
    try {
        $lines = @(& $Command @Arguments 2> $stderrPath)
        $exitCode = $LASTEXITCODE
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        if ($exitCode -ne 0) { throw "$Context returned exit code $exitCode. $stderr" }
        $json = ($lines -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($json)) { throw "$Context produced no JSON output." }
        return ($json | ConvertFrom-Json -Depth 100)
    }
    finally {
        if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    }
}
function Assert-SkillValidatorReport {
    param([Parameter(Mandatory = $true)] $Report, [Parameter(Mandatory = $true)][string] $SkillRoot, [Parameter(Mandatory = $true)][string[]] $Inventory, [Parameter(Mandatory = $true)][string] $SkillId)
    $skillDirectory = [string](Get-Property -Object $Report -Name 'skill_dir' -Context 'skill-validator report')
    $passed = Get-Property -Object $Report -Name 'passed' -Context 'skill-validator report'
    $errors = Get-Property -Object $Report -Name 'errors' -Context 'skill-validator report'
    $warnings = Get-Property -Object $Report -Name 'warnings' -Context 'skill-validator report'
    $results = @(Get-Property -Object $Report -Name 'results' -Context 'skill-validator report')
    if (-not (Test-PathEqual -Left $skillDirectory -Right $SkillRoot) -or $passed -isnot [bool] -or -not $passed -or
        [int64]$errors -ne 0 -or [int64]$warnings -ne 0 -or $results.Count -eq 0) {
        throw "skill-validator did not produce a clean candidate-bound report for '$SkillId'."
    }
    $findings = @()
    foreach ($result in $results) {
        $level = [string](Get-Property -Object $result -Name 'level' -Context 'skill-validator result').ToLowerInvariant()
        if ($level -notin @('pass', 'info')) { throw "skill-validator returned a blocking or malformed result for '$SkillId'." }
        if ($null -ne $result.PSObject.Properties['file']) {
            [void](Resolve-ReportedFilePath -Value $result.file -SkillRoot $SkillRoot -ExpectedPaths $Inventory -Context 'skill-validator result file')
        }
        if ($level -eq 'info') {
            $findings += [ordered]@{ severity = 'informational'; fingerprint = Get-TextSha256 -Text ($result | ConvertTo-Json -Depth 20 -Compress); ruleId = [string]$result.category; message = [string]$result.message; path = if ($null -ne $result.PSObject.Properties['file']) { [string]$result.file } else { '' }; skillId = $SkillId }
        }
    }
    return ,$findings
}
function Assert-SkillToolsReport {
    param([Parameter(Mandatory = $true)] $Report, [Parameter(Mandatory = $true)][string] $SkillRoot, [Parameter(Mandatory = $true)][string[]] $Inventory, [Parameter(Mandatory = $true)][string] $SkillId)
    $version = [string](Get-Property -Object $Report -Name 'version' -Context 'skill-tools SARIF')
    $runs = @(Get-Property -Object $Report -Name 'runs' -Context 'skill-tools SARIF')
    if ($version -cne '2.1.0' -or $runs.Count -ne 1) { throw "skill-tools did not produce SARIF 2.1.0 for '$SkillId'." }
    $run = $runs[0]
    $driver = Get-Property -Object (Get-Property -Object $run -Name 'tool' -Context 'skill-tools SARIF run') -Name 'driver' -Context 'skill-tools SARIF tool'
    $driverName = [string](Get-Property -Object $driver -Name 'name' -Context 'skill-tools SARIF driver')
    $rules = @(Get-Property -Object $driver -Name 'rules' -Context 'skill-tools SARIF driver')
    $results = @(Get-Property -Object $run -Name 'results' -Context 'skill-tools SARIF run')
    if ($driverName -cne 'skill-tools') { throw "skill-tools SARIF driver identity is invalid for '$SkillId'." }
    $ruleById = @{}
    foreach ($rule in $rules) { $ruleById[[string](Get-Property -Object $rule -Name 'id' -Context 'skill-tools SARIF rule')] = $rule }
    $findings = @()
    foreach ($result in $results) {
        $ruleId = [string](Get-Property -Object $result -Name 'ruleId' -Context 'skill-tools SARIF result')
        if (-not $ruleById.ContainsKey($ruleId)) { throw "skill-tools SARIF references an unknown rule for '$SkillId'." }
        $level = if ($null -ne $result.PSObject.Properties['level']) { [string]$result.level } else {
            [string](Get-Property -Object (Get-Property -Object $ruleById[$ruleId] -Name 'defaultConfiguration' -Context 'skill-tools SARIF rule') -Name 'level' -Context 'skill-tools SARIF rule default')
        }
        if ($level -notin @('none', 'note', 'warning', 'error')) { throw "skill-tools SARIF level is malformed for '$SkillId'." }
        if ($level -in @('warning', 'error')) { throw "skill-tools SARIF contains a blocking result for '$SkillId'." }
        $message = Get-Property -Object $result -Name 'message' -Context 'skill-tools SARIF result'
        $locations = @(Get-Property -Object $result -Name 'locations' -Context 'skill-tools SARIF result')
        if ([string]::IsNullOrWhiteSpace([string](Get-Property -Object $message -Name 'text' -Context 'skill-tools SARIF message')) -or $locations.Count -eq 0) { throw "skill-tools SARIF lacks candidate-bound evidence for '$SkillId'." }
        foreach ($location in $locations) {
            $physical = Get-Property -Object $location -Name 'physicalLocation' -Context 'skill-tools SARIF location'
            $artifact = Get-Property -Object $physical -Name 'artifactLocation' -Context 'skill-tools SARIF physical location'
            [void](Resolve-ReportedFilePath -Value (Get-Property -Object $artifact -Name 'uri' -Context 'skill-tools SARIF artifact location') -SkillRoot $SkillRoot -ExpectedPaths $Inventory -Context 'skill-tools SARIF artifact location')
        }
        if ($level -eq 'note') {
            $findings += [ordered]@{ severity = 'informational'; fingerprint = Get-TextSha256 -Text ($result | ConvertTo-Json -Depth 20 -Compress); ruleId = $ruleId; message = [string]$message.text; path = ''; skillId = $SkillId }
        }
    }
    return ,$findings
}
function Assert-SkillSpectorReport {
    param([Parameter(Mandatory = $true)] $Report, [Parameter(Mandatory = $true)][string] $SkillRoot, [Parameter(Mandatory = $true)][string] $SkillId, [Parameter(Mandatory = $true)][string[]] $Inventory)
    $execution = Get-Property -Object $Report -Name 'execution_successful' -Context 'SkillSpector report'
    $completeness = Get-Property -Object $Report -Name 'analysis_completeness' -Context 'SkillSpector report'
    if ($execution -isnot [bool] -or -not $execution -or
        (Get-Property -Object $completeness -Name 'execution_successful' -Context 'SkillSpector completeness') -isnot [bool] -or
        -not (Get-Property -Object $completeness -Name 'execution_successful' -Context 'SkillSpector completeness') -or
        (Get-Property -Object $completeness -Name 'is_complete' -Context 'SkillSpector completeness') -isnot [bool] -or
        -not (Get-Property -Object $completeness -Name 'is_complete' -Context 'SkillSpector completeness') -or
        [string](Get-Property -Object $completeness -Name 'status' -Context 'SkillSpector completeness') -cne 'complete' -or
        [double](Get-Property -Object $completeness -Name 'coverage_percent' -Context 'SkillSpector completeness') -ne 100) {
        throw "SkillSpector did not prove complete static analysis for '$SkillId'."
    }
    foreach ($name in @('ledger_exceptions', 'scope_exclusions', 'limitations')) {
        if (@(Get-Property -Object $completeness -Name $name -Context 'SkillSpector completeness').Count -ne 0) { throw "SkillSpector reported incomplete '$name' evidence for '$SkillId'." }
    }
    $skill = Get-Property -Object $Report -Name 'skill' -Context 'SkillSpector report'
    if ([string](Get-Property -Object $skill -Name 'name' -Context 'SkillSpector skill identity') -cne $SkillId -or
        -not (Test-PathEqual -Left ([string](Get-Property -Object $skill -Name 'source' -Context 'SkillSpector skill identity')) -Right $SkillRoot)) {
        throw "SkillSpector report identity does not match '$SkillId'."
    }
    $components = @(Get-Property -Object $Report -Name 'components' -Context 'SkillSpector report')
    if ($components.Count -ne $Inventory.Count) { throw "SkillSpector did not cover the exact inventory for '$SkillId'." }
    $observed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($component in $components) {
        $path = [string](Get-Property -Object $component -Name 'path' -Context 'SkillSpector component')
        if (-not ($Inventory -ccontains $path) -or -not $observed.Add($path)) { throw "SkillSpector did not cover the exact inventory for '$SkillId'." }
    }
    $issues = @(Get-Property -Object $Report -Name 'issues' -Context 'SkillSpector report')
    $findings = @()
    foreach ($issue in $issues) { $findings += New-Finding -Issue $issue -SkillId $SkillId -Stage 'skillspector-static' }
    return ,$findings
}

try {
    $toolchain = Read-Json -Path $ToolchainPath -Context 'run-owned validation toolchain'
    Assert-FileIdentity -Path $ToolchainPath -Sha256 $ToolchainSha256 -Context 'run-owned validation toolchain'
    $candidateRoot = [IO.Path]::GetFullPath([string]$env:STANDARD_VALIDATION_CANDIDATE_ROOT)
    $activeSkills = Get-ActiveSkills
    $candidateId = [string]$env:STANDARD_VALIDATION_CANDIDATE_ID
    if ([string]::IsNullOrWhiteSpace($candidateId)) { throw 'Central runner did not provide a candidate identity.' }

    switch ($Mode) {
        'package-adapter' {
            Assert-FileIdentity -Path ([string]$toolchain.upstreamAdapterValidatorPath) -Sha256 ([string]$toolchain.upstreamAdapterValidatorSha256) -Context 'upstream adapter validator'
            Assert-FileIdentity -Path ([string]$toolchain.upstreamPolicyPath) -Sha256 ([string]$toolchain.upstreamPolicySha256) -Context 'upstream adapter policy'
            $reportPath = Join-Path (Get-Location) 'upstream-adapter-report.json'
            & ([string]$toolchain.upstreamAdapterValidatorPath) -PackageRoot $candidateRoot -PolicyPath ([string]$toolchain.upstreamPolicyPath) -SourceRepository $SourceRepository -SourceRevision $SourceRevision -ArchiveSha256 $ArchiveSha256 -OutputPath $reportPath | Out-Null
            $report = Read-Json -Path $reportPath -Context 'upstream adapter report'
            $status = [string](Get-Property -Object $report -Name 'status' -Context 'upstream adapter report')
            $decision = [string](Get-Property -Object $report -Name 'decision' -Context 'upstream adapter report')
            if (($status -eq 'passed' -and $decision -ne 'PASS') -or ($status -eq 'not-applicable' -and $decision -ne 'NOT_APPLICABLE') -or $status -notin @('passed', 'not-applicable')) { throw 'Upstream adapter report did not pass or prove not-applicable.' }
            New-Envelope -ActiveSkills $activeSkills -Additional @{ adapterStatus = $status; adapterSurfaces = @($report.surfaces); semanticRequired = $false }
        }
        'skill-validator' {
            $skillId = [string]$env:STANDARD_VALIDATION_SKILL_ID
            $skillRoot = Get-SkillRoot -SkillId $skillId
            $inventory = Get-InventoryPaths -SkillRoot $skillRoot
            Assert-FileIdentity -Path ([string]$toolchain.skillValidatorPath) -Sha256 ([string]$toolchain.skillValidatorSha256) -Context 'skill-validator executable'
            $report = Invoke-NativeJson -Command ([string]$toolchain.skillValidatorPath) -Arguments @('-o', 'json', 'validate', 'structure', '--allow-dirs=agents', $skillRoot) -Context "skill-validator '$skillId'"
            $findings = Assert-SkillValidatorReport -Report $report -SkillRoot $skillRoot -Inventory $inventory -SkillId $skillId
            New-Envelope -ActiveSkills $activeSkills -Findings $findings -Additional @{ skillId = $skillId; skillInventorySha256 = [string]$env:STANDARD_VALIDATION_SKILL_INVENTORY_SHA256; semanticRequired = $false }
        }
        'skill-tools' {
            $skillId = [string]$env:STANDARD_VALIDATION_SKILL_ID
            $skillRoot = Get-SkillRoot -SkillId $skillId
            $inventory = Get-InventoryPaths -SkillRoot $skillRoot
            Assert-FileIdentity -Path ([string]$toolchain.skillToolsNodePath) -Sha256 ([string]$toolchain.skillToolsNodeSha256) -Context 'skill-tools Node runtime'
            Assert-FileIdentity -Path ([string]$toolchain.skillToolsEntryPointPath) -Sha256 ([string]$toolchain.skillToolsEntryPointSha256) -Context 'skill-tools entry point'
            $report = Invoke-NativeJson -Command ([string]$toolchain.skillToolsNodePath) -Arguments @([string]$toolchain.skillToolsEntryPointPath, 'check', $skillRoot, '--format', 'sarif', '--fail-on', 'warning', '--min-score', '91') -Context "skill-tools '$skillId'"
            $findings = Assert-SkillToolsReport -Report $report -SkillRoot $skillRoot -Inventory $inventory -SkillId $skillId
            New-Envelope -ActiveSkills $activeSkills -Findings $findings -Additional @{ skillId = $skillId; skillInventorySha256 = [string]$env:STANDARD_VALIDATION_SKILL_INVENTORY_SHA256; semanticRequired = $false }
        }
        'static' {
            Assert-FileIdentity -Path ([string]$toolchain.skillSpectorPath) -Sha256 ([string]$toolchain.skillSpectorSha256) -Context 'SkillSpector executable'
            $findings = @()
            foreach ($skillId in $activeSkills) {
                $skillRoot = Get-SkillRoot -SkillId $skillId
                $inventory = Get-InventoryPaths -SkillRoot $skillRoot
                $reportPath = Join-Path (Get-Location) ("skillspector-$skillId.json")
                & ([string]$toolchain.skillSpectorPath) scan $skillRoot --no-llm --format json --output $reportPath | Out-Null
                $report = Read-Json -Path $reportPath -Context "SkillSpector report for '$skillId'"
                $findings += Assert-SkillSpectorReport -Report $report -SkillRoot $skillRoot -SkillId $skillId -Inventory $inventory
            }
            $semantic = ($SemanticRequired -ceq 'true') -or $findings.Count -gt 0
            New-Envelope -ActiveSkills $activeSkills -Findings $findings -Additional @{ scannerIdentity = 'SkillSpector'; analyzerCompleteness = 'complete'; semanticRequired = $semantic }
        }
        'repository-general' {
            $validatorPath = Join-Path $candidateRoot 'scripts/Test-SkillGeneral.ps1'
            if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) { throw 'Test-SkillGeneral.ps1 is missing from the candidate snapshot.' }
            $reportPath = Join-Path (Get-Location) 'repository-general-report.json'
            & $validatorPath -RepositoryRoot $candidateRoot -OutputPath $reportPath -ReadOnlySnapshot *> $null
            $report = Read-Json -Path $reportPath -Context 'Test-SkillGeneral report'
            if ([string]$report.result -cne 'passed' -or [int]$report.activeSkillCount -ne $activeSkills.Count) { throw 'Test-SkillGeneral did not pass the complete active Skill inventory.' }
            $reportedSkills = @($report.skills | ForEach-Object { [string]$_.skillId })
            if ((@($reportedSkills | Sort-Object) -join "`n") -cne (@($activeSkills | Sort-Object) -join "`n")) { throw 'Test-SkillGeneral reported a different active Skill inventory.' }
            $testInventory = @($activeSkills | ForEach-Object { "domain-inventory:$($_)" })
            New-Envelope -ActiveSkills $activeSkills -Additional @{ testInventory = $testInventory; testResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Test-SkillGeneral' }; domainAdapterResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Skill-General-domain-contract' } }
        }
        'repository-pester' {
            Assert-FileIdentity -Path ([string]$toolchain.pesterModulePath) -Sha256 ([string]$toolchain.pesterModuleSha256) -Context 'Pester module'
            Import-Module -Name ([string]$toolchain.pesterModulePath) -Force -ErrorAction Stop
            $loaded = Get-Module Pester | Select-Object -First 1
            if ($null -eq $loaded -or [string]$loaded.Version -cne [string]$toolchain.pesterVersion) { throw 'The resolved Pester module identity was not loaded.' }
            $testRoot = Join-Path $candidateRoot 'tests'
            $result = Invoke-Pester -Path $testRoot -Output None -PassThru 6>$null
            if ($null -eq $result -or [int64]$result.TotalCount -le 0 -or [int64]$result.FailedCount -ne 0 -or
                [int64]$result.PassedCount + [int64]$result.SkippedCount -ne [int64]$result.TotalCount) { throw 'Pester repository regression did not complete successfully.' }
            $testInventory = @(
                Get-ChildItem -LiteralPath $testRoot -Recurse -File -Force |
                    ForEach-Object { [IO.Path]::GetRelativePath($candidateRoot, $_.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/') }
            )
            if ($testInventory.Count -eq 0) { throw 'Pester did not receive a non-empty test inventory.' }
            New-Envelope -ActiveSkills $activeSkills -Additional @{ testInventory = $testInventory; testResult = [ordered]@{ status = 'passed'; decision = 'PASS'; total = [int64]$result.TotalCount; passed = [int64]$result.PassedCount; skipped = [int64]$result.SkippedCount }; domainAdapterResult = [ordered]@{ status = 'passed'; decision = 'PASS'; result = 'Pester' } }
        }
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@

$semanticPreparationHelperText = @'
# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $RunnerPath,
    [Parameter(Mandatory = $true)][string] $CandidateRoot,
    [Parameter(Mandatory = $true)][string] $AdapterPath,
    [Parameter(Mandatory = $true)][string] $ArtifactsRoot,
    [Parameter(Mandatory = $true)][string] $SourceRepository,
    [Parameter(Mandatory = $true)][string] $SourceRevision,
    [Parameter(Mandatory = $true)][string] $BaseRevision,
    [Parameter(Mandatory = $true)][string] $EventName,
    [Parameter(Mandatory = $true)][string] $CandidateArchiveSha256,
    [Parameter(Mandatory = $true)][string] $OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$consumerPreparationRunnerPath = [IO.Path]::GetFullPath($RunnerPath)
$consumerPreparationCandidateRoot = [IO.Path]::GetFullPath($CandidateRoot)
$consumerPreparationAdapterPath = [IO.Path]::GetFullPath($AdapterPath)
$consumerPreparationArtifactsRoot = [IO.Path]::GetFullPath($ArtifactsRoot)
$consumerPreparationSourceRepository = [string]$SourceRepository
$consumerPreparationSourceRevision = [string]$SourceRevision
$consumerPreparationBaseRevision = [string]$BaseRevision
$consumerPreparationEventName = [string]$EventName
$consumerPreparationCandidateArchiveSha256 = [string]$CandidateArchiveSha256
$consumerPreparationOutputPath = [IO.Path]::GetFullPath($OutputPath)
. $consumerPreparationRunnerPath `
    -CandidateRoot $consumerPreparationCandidateRoot `
    -AdapterPath $consumerPreparationAdapterPath `
    -ArtifactsRoot $consumerPreparationArtifactsRoot `
    -SourceRepository $consumerPreparationSourceRepository `
    -SourceRevision $consumerPreparationSourceRevision `
    -BaseRevision $consumerPreparationBaseRevision `
    -EventName $consumerPreparationEventName `
    -DefineFunctionsOnly
$inventory = @(Get-StandardValidationInventory -Root $consumerPreparationCandidateRoot -Context 'consumer prepared candidate')
$contentSha256 = Get-StandardValidationInventorySha256 -Inventory $inventory
$adapterSha256 = Get-StandardValidationFileSha256 -Path $consumerPreparationAdapterPath -Context 'consumer prepared adapter'
$candidateId = Get-StandardValidationTextSha256 -Value (
    "$consumerPreparationSourceRepository`n$consumerPreparationSourceRevision`n$consumerPreparationBaseRevision`n$consumerPreparationEventName`n$contentSha256`n$adapterSha256`n$consumerPreparationCandidateArchiveSha256"
)
$value = [ordered]@{
    schemaVersion = 1
    artifactType = 'standard-validation-consumer-preparation-v1'
    candidateId = $candidateId
    candidateContentSha256 = $contentSha256
    adapterSha256 = $adapterSha256
    candidateInventory = @($inventory)
}
[IO.File]::WriteAllText($consumerPreparationOutputPath, (($value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
'@

try {
    $repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    }
    else { [IO.Path]::GetFullPath($RepositoryRoot) }
    if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) { throw "RepositoryRoot does not exist: $repoRoot" }
    if ($ExecutionMode -ne 'Run' -and [string]::IsNullOrWhiteSpace($SemanticRunPlanPath)) {
        throw 'SemanticRunPlanPath is required for PrepareSemantic and ResumeSemantic.'
    }
    if ($ExecutionMode -eq 'ResumeSemantic') {
        foreach ($forbiddenName in @(
            'AuthorityArchivePath', 'ExpectedGoRuntimeVersion', 'SemanticConsent', 'SemanticProvider', 'SemanticPurpose',
            'SemanticScope', 'SemanticEvidencePath', 'SemanticConsentRequestPath', 'SemanticConsentDecisionPath',
            'SemanticPublicKeyPath', 'SemanticPublicKeyId', 'SemanticTriggered'
        )) {
            if ($PSBoundParameters.ContainsKey($forbiddenName)) { throw "ResumeSemantic does not accept caller override '$forbiddenName'." }
        }
        $planFull = [IO.Path]::GetFullPath($SemanticRunPlanPath)
        $plan = Read-JsonFile -Path $planFull -Context 'Semantic run plan'
        Assert-ExactPropertySet -Value $plan -Expected @('schemaVersion', 'artifactType', 'runId', 'source', 'roots', 'candidate', 'authority', 'tools', 'execution', 'semantic') -Context 'Semantic run plan'
        Assert-ExactPropertySet -Value $plan.source -Expected @('repositoryRoot', 'repository', 'revision', 'baseRevision', 'tree', 'eventName') -Context 'Semantic run plan source'
        Assert-ExactPropertySet -Value $plan.roots -Expected @('artifacts', 'run', 'trusted', 'candidateExtract', 'resolvedTools') -Context 'Semantic run plan roots'
        Assert-ExactPropertySet -Value $plan.candidate -Expected @('archivePath', 'archiveSha256', 'snapshotRoot', 'contentSha256', 'inventory', 'candidateId') -Context 'Semantic run plan candidate'
        Assert-ExactPropertySet -Value $plan.authority -Expected @('revision', 'archivePath', 'archiveSha256', 'root', 'runnerPath', 'runnerSha256') -Context 'Semantic run plan authority'
        Assert-ExactPropertySet -Value $plan.tools -Expected @('policyReceiptPath', 'policyReceiptSha256', 'receipts', 'toolchainPath', 'toolchainSha256', 'childRunnerPath', 'childRunnerSha256', 'preparationHelperPath', 'preparationHelperSha256', 'preparationPath', 'preparationSha256', 'adapterPath', 'adapterSha256') -Context 'Semantic run plan tools'
        Assert-ExactPropertySet -Value $plan.execution -Expected @('outputPath', 'timeoutSeconds', 'semanticTriggered', 'consumptionClaimPath') -Context 'Semantic run plan execution'
        Assert-ExactPropertySet -Value $plan.semantic -Expected @('consentRequestPath', 'consentDecisionPath', 'evidencePath', 'publicKeyPath', 'publicKeyId') -Context 'Semantic run plan semantic binding'
        if ([int]$plan.schemaVersion -ne 1 -or [string]$plan.artifactType -cne 'standard-validation-consumer-run-plan-v1' -or
            [string]$plan.source.repository -cne $script:SourceRepository -or [string]$plan.authority.revision -cne $script:AuthorityCommit -or
            [string]$plan.authority.archiveSha256 -cne $script:AuthorityArchiveSha256 -or $plan.execution.semanticTriggered -ne $true) {
            throw 'Semantic run plan identity or pinned authority binding is invalid.'
        }
        if ([string]$plan.runId -cnotmatch '^[0-9a-f]{32}$') { throw 'Semantic run plan runId is invalid.' }
        foreach ($sha in @(
            $plan.candidate.archiveSha256, $plan.candidate.contentSha256, $plan.candidate.candidateId,
            $plan.authority.archiveSha256, $plan.authority.runnerSha256, $plan.tools.policyReceiptSha256,
            $plan.tools.toolchainSha256, $plan.tools.childRunnerSha256, $plan.tools.preparationHelperSha256,
            $plan.tools.preparationSha256, $plan.tools.adapterSha256
        )) { Assert-Sha256 -Value ([string]$sha) -Context 'Semantic run plan SHA-256 binding' }

        $planArtifactsRoot = [IO.Path]::GetFullPath([string]$plan.roots.artifacts)
        Assert-OutsideRoot -Path $planArtifactsRoot -Root $repoRoot -Context 'Prepared artifacts root'
        Assert-NoReparseAncestors -Path $planArtifactsRoot -Context 'Prepared artifacts root'
        if (-not (Test-PathWithinOrEqual -Path $planFull -Root $planArtifactsRoot)) { throw 'Semantic run plan is outside its prepared artifacts root.' }
        if ($PSBoundParameters.ContainsKey('ArtifactsRoot') -and -not (Test-PathEqual -Left $ArtifactsRoot -Right $planArtifactsRoot)) { throw 'ArtifactsRoot conflicts with the prepared run plan.' }
        if ($PSBoundParameters.ContainsKey('OutputPath') -and -not (Test-PathEqual -Left $OutputPath -Right ([string]$plan.execution.outputPath))) { throw 'OutputPath conflicts with the prepared run plan.' }
        if ($PSBoundParameters.ContainsKey('TimeoutSeconds') -and $TimeoutSeconds -ne [int]$plan.execution.timeoutSeconds) { throw 'TimeoutSeconds conflicts with the prepared run plan.' }

        $gitPath = Get-ResolvedGitPath
        $pwshPath = Get-ResolvedPowerShellPath
        if (-not (Test-PathEqual -Left $repoRoot -Right ([string]$plan.source.repositoryRoot))) { throw 'RepositoryRoot conflicts with the prepared run plan.' }
        $candidateCommit = Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision 'HEAD' -Context 'Resume candidate revision'
        $dirty = @(& $gitPath -C $repoRoot status --porcelain=v1 --untracked-files=all)
        if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'ResumeSemantic requires the same clean immutable candidate commit.' }
        $baseRevision = Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision ([string]$plan.source.baseRevision) -Context 'Resume base revision'
        $candidateTree = @(& $gitPath -C $repoRoot rev-parse --verify --end-of-options "$candidateCommit^{tree}")
        if ($candidateCommit -cne [string]$plan.source.revision -or $baseRevision -cne [string]$plan.source.baseRevision -or
            $candidateTree.Count -ne 1 -or [string]$candidateTree[0] -cne [string]$plan.source.tree -or
            (Get-EventName) -cne [string]$plan.source.eventName) { throw 'Prepared source revision, tree, base, or event drifted.' }
        if ($PSBoundParameters.ContainsKey('BaseCommit') -and (Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision $BaseCommit -Context 'Caller base revision') -cne $baseRevision) { throw 'BaseCommit conflicts with the prepared run plan.' }

        $runRoot = Assert-PathWithinRoot -Path ([string]$plan.roots.run) -Root $planArtifactsRoot -Context 'Prepared run root'
        if (-not (Test-PathEqual -Left $runRoot -Right (Join-Path $planArtifactsRoot "sgv1-$(([string]$plan.runId).Substring(0, 12))"))) { throw 'Prepared run root is not derived from the run identity.' }
        $trustedRoot = [IO.Path]::GetFullPath([string]$plan.roots.trusted)
        $candidateExtractRoot = [IO.Path]::GetFullPath([string]$plan.roots.candidateExtract)
        $resolvedToolsRoot = [IO.Path]::GetFullPath([string]$plan.roots.resolvedTools)
        $systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not (Test-PathEqual -Left $trustedRoot -Right (Join-Path $systemTempRoot "sgv1-tools-$($plan.runId)")) -or
            -not (Test-PathEqual -Left $candidateExtractRoot -Right (Join-Path $systemTempRoot "sgv1-candidate-$($plan.runId)")) -or
            -not (Test-PathEqual -Left $resolvedToolsRoot -Right (Join-Path $systemTempRoot "sgv1-resolved-tools-$($plan.runId)"))) {
            throw 'Prepared external roots are not derived from the run identity.'
        }
        foreach ($externalRoot in @($trustedRoot, $candidateExtractRoot, $resolvedToolsRoot)) {
            Assert-OutsideRoot -Path $externalRoot -Root $repoRoot -Context 'Prepared external root'
            Assert-OutsideRoot -Path $externalRoot -Root $planArtifactsRoot -Context 'Prepared external root'
            Assert-NoReparseAncestors -Path $externalRoot -Context 'Prepared external root'
        }
        $candidateArchivePath = Assert-PathWithinRoot -Path ([string]$plan.candidate.archivePath) -Root $runRoot -Context 'Prepared candidate archive'
        if ((Get-FileSha256 -Path $candidateArchivePath) -cne [string]$plan.candidate.archiveSha256) { throw 'Prepared candidate archive drifted.' }
        $candidateRoot = Assert-PathWithinRoot -Path ([string]$plan.candidate.snapshotRoot) -Root $candidateExtractRoot -Context 'Prepared candidate snapshot'
        $authorityArchive = Assert-PathWithinRoot -Path ([string]$plan.authority.archivePath) -Root $runRoot -Context 'Prepared authority archive'
        if ((Get-FileSha256 -Path $authorityArchive) -cne $script:AuthorityArchiveSha256) { throw 'Prepared authority archive drifted.' }
        $authorityRoot = Assert-PathWithinRoot -Path ([string]$plan.authority.root) -Root $trustedRoot -Context 'Prepared authority root'
        foreach ($entry in $script:AuthorityFiles.GetEnumerator()) {
            $authorityPath = Assert-PathWithinRoot -Path (Join-Path $authorityRoot ($entry.Key -replace '/', [IO.Path]::DirectorySeparatorChar)) -Root $authorityRoot -Context 'Prepared authority file'
            if ((Get-FileSha256 -Path $authorityPath) -cne $entry.Value) { throw "Prepared authority file drifted: $($entry.Key)" }
        }
        $centralRunnerPath = Assert-PathWithinRoot -Path ([string]$plan.authority.runnerPath) -Root $authorityRoot -Context 'Prepared central runner'
        if ((Get-FileSha256 -Path $centralRunnerPath) -cne [string]$plan.authority.runnerSha256) { throw 'Prepared central runner drifted.' }

        foreach ($fileBinding in @(
            [pscustomobject]@{ path = $plan.tools.policyReceiptPath; sha = $plan.tools.policyReceiptSha256; root = $runRoot; name = 'policy receipt' },
            [pscustomobject]@{ path = $plan.tools.toolchainPath; sha = $plan.tools.toolchainSha256; root = $trustedRoot; name = 'toolchain' },
            [pscustomobject]@{ path = $plan.tools.childRunnerPath; sha = $plan.tools.childRunnerSha256; root = $trustedRoot; name = 'child runner' },
            [pscustomobject]@{ path = $plan.tools.preparationHelperPath; sha = $plan.tools.preparationHelperSha256; root = $trustedRoot; name = 'preparation helper' },
            [pscustomobject]@{ path = $plan.tools.preparationPath; sha = $plan.tools.preparationSha256; root = $runRoot; name = 'preparation result' },
            [pscustomobject]@{ path = $plan.tools.adapterPath; sha = $plan.tools.adapterSha256; root = $trustedRoot; name = 'adapter' }
        )) {
            $boundPath = Assert-PathWithinRoot -Path ([string]$fileBinding.path) -Root ([string]$fileBinding.root) -Context "Prepared $($fileBinding.name)"
            if ((Get-FileSha256 -Path $boundPath) -cne [string]$fileBinding.sha) { throw "Prepared $($fileBinding.name) drifted." }
        }
        foreach ($receipt in @($plan.tools.receipts)) {
            Assert-ExactPropertySet -Value $receipt -Expected @('tool', 'path', 'sha256') -Context 'Prepared resolver receipt'
            Assert-Sha256 -Value ([string]$receipt.sha256) -Context 'Prepared resolver receipt'
            $receiptPath = Assert-PathWithinRoot -Path ([string]$receipt.path) -Root $runRoot -Context 'Prepared resolver receipt'
            if ((Get-FileSha256 -Path $receiptPath) -cne [string]$receipt.sha256) { throw "Prepared resolver receipt drifted: $($receipt.tool)" }
        }

        $semanticPaths = @($plan.semantic.consentRequestPath, $plan.semantic.consentDecisionPath, $plan.semantic.evidencePath, $plan.semantic.publicKeyPath)
        $seenSemanticPaths = [Collections.Generic.HashSet[string]]::new($(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
        foreach ($semanticPath in $semanticPaths) {
            Assert-OutsideRoot -Path ([string]$semanticPath) -Root $repoRoot -Context 'Prepared semantic artifact'
            Assert-OutsideRoot -Path ([string]$semanticPath) -Root $planArtifactsRoot -Context 'Prepared semantic artifact'
            if (-not (Test-Path -LiteralPath ([string]$semanticPath) -PathType Leaf)) { throw "Prepared semantic artifact is missing: $semanticPath" }
            Assert-NoReparseAncestors -Path ([string]$semanticPath) -Context 'Prepared semantic artifact'
            if (-not $seenSemanticPaths.Add([IO.Path]::GetFullPath([string]$semanticPath))) { throw 'Prepared semantic artifact paths must be distinct.' }
        }
        if ([string]::IsNullOrWhiteSpace([string]$plan.semantic.publicKeyId)) { throw 'Prepared semantic public-key identity is missing.' }

        $resumeVerificationPath = Join-Path $runRoot "semantic-resume-verification-$([guid]::NewGuid().ToString('N')).json"
        & $pwshPath -NoProfile -NonInteractive -File ([string]$plan.tools.preparationHelperPath) `
            -RunnerPath $centralRunnerPath -CandidateRoot $candidateRoot -AdapterPath ([string]$plan.tools.adapterPath) `
            -ArtifactsRoot $planArtifactsRoot -SourceRepository $script:SourceRepository -SourceRevision $candidateCommit `
            -BaseRevision $baseRevision -EventName ([string]$plan.source.eventName) `
            -CandidateArchiveSha256 ([string]$plan.candidate.archiveSha256) -OutputPath $resumeVerificationPath
        if ($LASTEXITCODE -ne 0) { throw 'Prepared semantic identity revalidation failed.' }
        $recomputed = Read-JsonFile -Path $resumeVerificationPath -Context 'Recomputed semantic preparation'
        if ([string]$recomputed.candidateId -cne [string]$plan.candidate.candidateId -or
            [string]$recomputed.candidateContentSha256 -cne [string]$plan.candidate.contentSha256 -or
            [string]$recomputed.adapterSha256 -cne [string]$plan.tools.adapterSha256 -or
            ((@($recomputed.candidateInventory) | ConvertTo-Json -Depth 100 -Compress) -cne (@($plan.candidate.inventory) | ConvertTo-Json -Depth 100 -Compress))) {
            throw 'Prepared candidate, inventory, or adapter binding drifted.'
        }

        $outputFull = Assert-PathWithinRoot -Path ([string]$plan.execution.outputPath) -Root $planArtifactsRoot -Context 'Prepared output path'
        if (Test-Path -LiteralPath $outputFull) { throw 'Prepared output path is no longer create-only.' }
        $claimPath = Assert-PathWithinRoot -Path ([string]$plan.execution.consumptionClaimPath) -Root $planArtifactsRoot -Context 'Prepared consumption claim'
        if (-not (Test-PathEqual -Left $claimPath -Right "$planFull.consumed.json")) { throw 'Prepared consumption claim path is not derived from the run plan.' }
        $claimStream = $null
        try {
            $claimStream = [IO.File]::Open($claimPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $claimBytes = [Text.UTF8Encoding]::new($false).GetBytes((([ordered]@{ schemaVersion = 1; artifactType = 'standard-validation-consumer-run-claim-v1'; planSha256 = Get-FileSha256 -Path $planFull; claimedAt = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress) + [Environment]::NewLine))
            $claimStream.Write($claimBytes, 0, $claimBytes.Length)
            $claimStream.Flush($true)
        }
        catch { throw "Semantic run plan is already consumed or could not be claimed: $($_.Exception.Message)" }
        finally { if ($null -ne $claimStream) { $claimStream.Dispose() } }

        $resumeArgs = @(
            '-CandidateRoot', $candidateRoot, '-AdapterPath', ([string]$plan.tools.adapterPath),
            '-ArtifactsRoot', $planArtifactsRoot, '-OutputPath', $outputFull,
            '-SourceRepository', $script:SourceRepository, '-SourceRevision', $candidateCommit,
            '-BaseRevision', $baseRevision, '-EventName', ([string]$plan.source.eventName),
            '-TimeoutSeconds', ([string][int]$plan.execution.timeoutSeconds), '-TrustedToolRoot', $trustedRoot,
            '-CandidateArchiveSha256', ([string]$plan.candidate.archiveSha256), '-DevelopmentHarness', '-SemanticTriggered',
            '-SemanticEvidencePath', ([string]$plan.semantic.evidencePath),
            '-SemanticConsentRequestPath', ([string]$plan.semantic.consentRequestPath),
            '-SemanticConsentDecisionPath', ([string]$plan.semantic.consentDecisionPath),
            '-SemanticPublicKeyPath', ([string]$plan.semantic.publicKeyPath),
            '-SemanticPublicKeyId', ([string]$plan.semantic.publicKeyId)
        )
        & $pwshPath -NoProfile -NonInteractive -File $centralRunnerPath @resumeArgs
        exit $LASTEXITCODE
    }
    $gitPath = Get-ResolvedGitPath
    $pwshPath = Get-ResolvedPowerShellPath
    $candidateCommit = Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision 'HEAD' -Context 'Candidate revision'
    $dirty = @(& $gitPath -C $repoRoot status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Canonical validation requires a clean immutable candidate commit.' }
    $baseInput = if ([string]::IsNullOrWhiteSpace($BaseCommit)) { 'HEAD^' } else { $BaseCommit }
    $baseRevision = Resolve-GitRevision -GitPath $gitPath -Root $repoRoot -Revision $baseInput -Context 'Base commit'
    & $gitPath -C $repoRoot merge-base --is-ancestor $baseRevision $candidateCommit
    if ($LASTEXITCODE -ne 0 -or $baseRevision -ceq $candidateCommit) { throw 'Base commit must be a distinct ancestor of the immutable candidate.' }

    $config = Read-JsonFile -Path (Join-Path $repoRoot 'config/standard-v1.json') -Context 'config/standard-v1.json'
    Assert-AuthorityConfig -Config $config
    $activeSkillIds = Get-ActiveSkillIds -Root $repoRoot
    $eventName = Get-EventName
    $goRuntimeVersion = Resolve-GoRuntimeVersion -Expected $ExpectedGoRuntimeVersion

    $artifactsRootPath = [IO.Path]::GetFullPath($ArtifactsRoot)
    Assert-OutsideRoot -Path $artifactsRootPath -Root $repoRoot -Context 'Artifacts root'
    [void](New-Item -ItemType Directory -Path $artifactsRootPath -Force)
    Assert-NoReparseAncestors -Path $artifactsRootPath -Context 'Artifacts root'
    $outputFull = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $artifactsRootPath 'skill-general-conformance-report.json' } else { Assert-PathWithinRoot -Path $OutputPath -Root $artifactsRootPath -Context 'OutputPath' }
    if (Test-Path -LiteralPath $outputFull -PathType Leaf) { throw "OutputPath already exists and evidence is create-only: $outputFull" }
    $semanticRunPlanFull = $null
    $semanticArtifactPaths = $null
    if ($ExecutionMode -eq 'PrepareSemantic') {
        if (-not $SemanticTriggered) { throw 'PrepareSemantic requires an explicit SemanticTriggered development-harness request.' }
        if ($SemanticConsent -or -not [string]::IsNullOrWhiteSpace($SemanticProvider) -or
            -not [string]::IsNullOrWhiteSpace($SemanticPurpose) -or -not [string]::IsNullOrWhiteSpace($SemanticScope)) {
            throw 'PrepareSemantic v2 does not accept legacy semantic consent/provider/purpose/scope inputs; those bindings belong in the v2 artifacts.'
        }
        if ([string]::IsNullOrWhiteSpace($SemanticEvidencePath) -or
            [string]::IsNullOrWhiteSpace($SemanticConsentRequestPath) -or
            [string]::IsNullOrWhiteSpace($SemanticConsentDecisionPath) -or
            [string]::IsNullOrWhiteSpace($SemanticPublicKeyPath) -or
            [string]::IsNullOrWhiteSpace($SemanticPublicKeyId)) {
            throw 'PrepareSemantic requires fixed consent request, decision, evidence, public-key paths, and public-key identity.'
        }
        $semanticRunPlanFull = Assert-PathWithinRoot -Path $SemanticRunPlanPath -Root $artifactsRootPath -Context 'SemanticRunPlanPath'
        if (Test-Path -LiteralPath $semanticRunPlanFull) { throw "Semantic run plan already exists and is create-only: $semanticRunPlanFull" }
        $semanticArtifactPaths = [ordered]@{
            consentRequest = [IO.Path]::GetFullPath($SemanticConsentRequestPath)
            consentDecision = [IO.Path]::GetFullPath($SemanticConsentDecisionPath)
            evidence = [IO.Path]::GetFullPath($SemanticEvidencePath)
            publicKey = [IO.Path]::GetFullPath($SemanticPublicKeyPath)
        }
        $seenSemanticPaths = [Collections.Generic.HashSet[string]]::new($(if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }))
        foreach ($semanticPath in $semanticArtifactPaths.Values) {
            Assert-OutsideRoot -Path $semanticPath -Root $repoRoot -Context 'Semantic artifact path'
            Assert-OutsideRoot -Path $semanticPath -Root $artifactsRootPath -Context 'Semantic artifact path'
            if (-not $seenSemanticPaths.Add($semanticPath)) { throw 'Semantic artifact paths must be distinct.' }
        }
    }

    $runId = [guid]::NewGuid().ToString('N')
    $runRoot = Join-Path $artifactsRootPath "sgv1-$($runId.Substring(0, 12))"
    if (Test-Path -LiteralPath $runRoot) { throw 'Run-owned artifact path unexpectedly exists.' }
    [void](New-Item -ItemType Directory -Path $runRoot -Force)
    $trustedRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-tools-$runId"
    $candidateExtractRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-candidate-$runId"
    if ((Test-Path -LiteralPath $trustedRoot) -or (Test-Path -LiteralPath $candidateExtractRoot)) { throw 'Run-owned temporary root unexpectedly exists.' }
    [void](New-Item -ItemType Directory -Path $trustedRoot -Force)
    [void](New-Item -ItemType Directory -Path $candidateExtractRoot -Force)
    $resolvedToolsRoot = Join-Path ([IO.Path]::GetTempPath()) "sgv1-resolved-tools-$runId"
    if (Test-Path -LiteralPath $resolvedToolsRoot) { throw 'Run-owned resolved-tools path unexpectedly exists.' }
    [void](New-Item -ItemType Directory -Path $resolvedToolsRoot -Force)
    Assert-OutsideRoot -Path $trustedRoot -Root $repoRoot -Context 'Trusted tool root'
    Assert-OutsideRoot -Path $trustedRoot -Root $artifactsRootPath -Context 'Trusted tool root'
    Assert-OutsideRoot -Path $candidateExtractRoot -Root $artifactsRootPath -Context 'Candidate snapshot root'
    Assert-OutsideRoot -Path $resolvedToolsRoot -Root $repoRoot -Context 'Resolved tools root'
    Assert-OutsideRoot -Path $resolvedToolsRoot -Root $artifactsRootPath -Context 'Resolved tools root'
    Assert-NoReparseAncestors -Path $trustedRoot -Context 'Trusted tool root'
    Assert-NoReparseAncestors -Path $candidateExtractRoot -Context 'Candidate snapshot root'
    Assert-NoReparseAncestors -Path $resolvedToolsRoot -Context 'Resolved tools root'

    $candidateArchivePath = Join-Path $runRoot 'candidate.zip'
    & $gitPath -C $repoRoot archive --format=zip "--prefix=candidate-$candidateCommit/" "--output=$candidateArchivePath" $candidateCommit
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $candidateArchivePath -PathType Leaf)) { throw 'Could not create the immutable candidate archive.' }
    $candidateArchiveSha256 = Get-FileSha256 -Path $candidateArchivePath
    Expand-Archive -LiteralPath $candidateArchivePath -DestinationPath $candidateExtractRoot -Force
    $candidateRoots = @(Get-ChildItem -LiteralPath $candidateExtractRoot -Directory -Force)
    if ($candidateRoots.Count -ne 1) { throw 'Candidate archive must contain exactly one repository root.' }
    $candidateRoot = [IO.Path]::GetFullPath($candidateRoots[0].FullName)
    Assert-NoReparseAncestors -Path $candidateRoot -Context 'Candidate snapshot root'

    $authorityArchive = Join-Path $runRoot 'authority.zip'
    if ([string]::IsNullOrWhiteSpace($AuthorityArchivePath)) {
        Invoke-WebRequest -Uri ([string]$config.authority.archiveUrl) -OutFile $authorityArchive
    }
    else {
        $supplied = [IO.Path]::GetFullPath($AuthorityArchivePath)
        if (-not (Test-Path -LiteralPath $supplied -PathType Leaf)) { throw "Supplied authority archive does not exist: $supplied" }
        Copy-Item -LiteralPath $supplied -Destination $authorityArchive -Force
    }
    if ((Get-FileSha256 -Path $authorityArchive) -cne $script:AuthorityArchiveSha256) { throw 'Authority archive SHA-256 does not match the exact P02 authority snapshot.' }
    $authorityExtract = Join-Path $trustedRoot 'authority'
    [void](New-Item -ItemType Directory -Path $authorityExtract -Force)
    Expand-Archive -LiteralPath $authorityArchive -DestinationPath $authorityExtract -Force
    $authorityRoots = @(Get-ChildItem -LiteralPath $authorityExtract -Directory -Force)
    if ($authorityRoots.Count -ne 1) { throw 'Authority archive must contain exactly one repository root.' }
    $authorityRoot = [IO.Path]::GetFullPath($authorityRoots[0].FullName)
    foreach ($entry in $script:AuthorityFiles.GetEnumerator()) {
        $authorityPath = Assert-PathWithinRoot -Path (Join-Path $authorityRoot ($entry.Key -replace '/', [IO.Path]::DirectorySeparatorChar)) -Root $authorityRoot -Context 'Authority file'
        if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf)) { throw "Authority file is missing: $($entry.Key)" }
        if ((Get-FileSha256 -Path $authorityPath) -cne $entry.Value) { throw "Authority file identity mismatch: $($entry.Key)" }
    }
    $standardText = Get-Content -LiteralPath (Join-Path $authorityRoot 'docs/standards/skill-repository-standard.md') -Raw -Encoding UTF8
    if ($standardText -cnotmatch '(?m)^# Agent Skill Repository Standard v1$' -or $standardText -cnotmatch '(?m)^Status: \*\*Normative\*\*$') { throw 'Verified P02 authority snapshot is not the normative Standard v1.' }

    $resolverPath = Join-Path $authorityRoot 'scripts/Resolve-StandardValidationTool.ps1'
    $policyPath = Join-Path $authorityRoot 'docs/standards/validation-toolchain.json'
    $centralRunnerPath = Join-Path $authorityRoot 'scripts/Invoke-StandardValidation.ps1'
    $upstreamAdapterPath = Join-Path $authorityRoot 'scripts/Validate-UpstreamAdapter.ps1'
    $upstreamPolicyPath = Join-Path $authorityRoot 'docs/standards/upstream-adapter.json'
    $policyReceiptPath = Join-Path $runRoot 'policy.json'
    Invoke-Resolver -PowerShellPath $pwshPath -ResolverPath $resolverPath -Arguments @('-PolicyPath', $policyPath, '-ValidatePolicyOnly', '-OutputPath', $policyReceiptPath)
    $policyReceipt = Read-JsonFile -Path $policyReceiptPath -Context 'Validation tool policy receipt'
    if ([string]$policyReceipt.policy -cne 'latest-stable-per-validation-run' -or
        [string]$policyReceipt.sourceTrust.enforcement -cne 'exact-approved-source' -or $policyReceipt.recordResolvedIdentityWhenAvailable -ne $true) {
        throw 'Validation tool policy receipt does not preserve the central trust contract.'
    }
    $receipts = [ordered]@{}
    foreach ($toolName in @('skillspector', 'skill-validator', 'skill-tools', 'pester')) {
        $receiptPath = Join-Path $runRoot "receipt-$toolName.json"
        Invoke-Resolver -PowerShellPath $pwshPath -ResolverPath $resolverPath -Arguments @('-PolicyPath', $policyPath, '-ToolName', $toolName, '-Install', '-InstallRoot', $resolvedToolsRoot, '-ExpectedGoRuntimeVersion', $goRuntimeVersion, '-OutputPath', $receiptPath)
        $receipt = Read-JsonFile -Path $receiptPath -Context "$toolName resolver receipt"
        if ([string]$receipt.toolName -cne $toolName -or [string]$receipt.channel -cne 'latest-stable' -or $receipt.frozenForRun -ne $true -or
            [string]::IsNullOrWhiteSpace([string]$receipt.resolvedVersion) -or [string]::IsNullOrWhiteSpace([string]$receipt.resolvedIdentity)) { throw "$toolName resolver receipt is not an exact frozen latest-stable identity." }
        $receipts[$toolName] = $receipt
    }
    Remove-Item -LiteralPath 'Env:GITHUB_TOKEN', 'Env:GH_TOKEN' -Force -ErrorAction SilentlyContinue

    $toolchain = [ordered]@{
        upstreamAdapterValidatorPath = [IO.Path]::GetFullPath($upstreamAdapterPath)
        upstreamAdapterValidatorSha256 = Get-FileSha256 -Path $upstreamAdapterPath
        upstreamPolicyPath = [IO.Path]::GetFullPath($upstreamPolicyPath)
        upstreamPolicySha256 = Get-FileSha256 -Path $upstreamPolicyPath
        skillValidatorPath = [IO.Path]::GetFullPath([string]$receipts.'skill-validator'.executablePath)
        skillValidatorSha256 = [string]$receipts.'skill-validator'.executableSha256
        skillToolsNodePath = [IO.Path]::GetFullPath([string]$receipts.'skill-tools'.nodePath)
        skillToolsNodeSha256 = [string]$receipts.'skill-tools'.nodeSha256
        skillToolsEntryPointPath = [IO.Path]::GetFullPath([string]$receipts.'skill-tools'.entryPointPath)
        skillToolsEntryPointSha256 = [string]$receipts.'skill-tools'.entryPointSha256
        skillSpectorPath = [IO.Path]::GetFullPath([string]$receipts.skillspector.executablePath)
        skillSpectorSha256 = [string]$receipts.skillspector.executableSha256
        pesterModulePath = [IO.Path]::GetFullPath([string]$receipts.pester.modulePath)
        pesterModuleSha256 = [string]$receipts.pester.executableSha256
        pesterVersion = [string]$receipts.pester.resolvedVersion
    }
    foreach ($entry in @(
        [pscustomobject]@{ path = $toolchain.skillValidatorPath; sha = $toolchain.skillValidatorSha256; name = 'skill-validator' },
        [pscustomobject]@{ path = $toolchain.skillToolsNodePath; sha = $toolchain.skillToolsNodeSha256; name = 'skill-tools Node' },
        [pscustomobject]@{ path = $toolchain.skillToolsEntryPointPath; sha = $toolchain.skillToolsEntryPointSha256; name = 'skill-tools entry point' },
        [pscustomobject]@{ path = $toolchain.skillSpectorPath; sha = $toolchain.skillSpectorSha256; name = 'SkillSpector' },
        [pscustomobject]@{ path = $toolchain.pesterModulePath; sha = $toolchain.pesterModuleSha256; name = 'Pester' }
    )) {
        Assert-Sha256 -Value ([string]$entry.sha) -Context "$($entry.name) receipt hash"
        if ((Get-FileSha256 -Path ([string]$entry.path)) -cne [string]$entry.sha) { throw "$($entry.name) changed after resolver completion." }
    }
    $toolchainPath = Join-Path $trustedRoot 'toolchain.json'
    Write-Utf8NoBom -Path $toolchainPath -Text (($toolchain | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    $toolchainSha256 = Get-FileSha256 -Path $toolchainPath
    $childRunnerPath = Join-Path $trustedRoot 'Invoke-SkillGeneralValidationChild.ps1'
    Write-Utf8NoBom -Path $childRunnerPath -Text $childRunnerText
    $semanticPreparationHelperPath = Join-Path $trustedRoot 'Get-SkillGeneralSemanticPreparation.ps1'
    Write-Utf8NoBom -Path $semanticPreparationHelperPath -Text $semanticPreparationHelperText

    $semanticRequired = $false
    $changedPaths = @(& $gitPath -C $repoRoot diff --find-renames=100% --name-only "$baseRevision...$candidateCommit")
    foreach ($changedPath in $changedPaths) {
        if ([string]$changedPath -like 'skills/*') { $semanticRequired = $true; break }
    }
    $commonArguments = @('-NoProfile', '-NonInteractive', '-File', $childRunnerPath, '-ToolchainPath', $toolchainPath, '-ToolchainSha256', $toolchainSha256, '-SourceRepository', $script:SourceRepository, '-SourceRevision', $candidateCommit, '-ArchiveSha256', $candidateArchiveSha256)
    $adapter = [ordered]@{
        schemaVersion = 1
        adapter = 'standard-validation-adapter-v1'
        mode = 'development-harness'
        skillsRoot = 'skills'
        activeSkills = @($activeSkillIds)
        canonicalValidatorPath = 'scripts/Validate.ps1'
        packageAdapter = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'package-adapter')) }
        skillValidator = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'skill-validator')) }
        skillTools = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'skill-tools')) }
        staticAnalyzer = [ordered]@{ command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'static', '-SemanticRequired', $semanticRequired.ToString().ToLowerInvariant())) }
        repositoryTests = @(
            [ordered]@{ id = 'repository-test-general'; command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'repository-general')) }
            [ordered]@{ id = 'repository-test-pester'; command = $pwshPath; arguments = @($commonArguments + @('-Mode', 'repository-pester')) }
        )
    }
    $adapterPath = Join-Path $trustedRoot 'standard-validation-adapter.json'
    Write-Utf8NoBom -Path $adapterPath -Text (($adapter | ConvertTo-Json -Depth 50) + [Environment]::NewLine)
    if ($ExecutionMode -eq 'PrepareSemantic') {
        $preparationPath = Join-Path $runRoot 'semantic-preparation.json'
        & $pwshPath -NoProfile -NonInteractive -File $semanticPreparationHelperPath `
            -RunnerPath $centralRunnerPath `
            -CandidateRoot $candidateRoot `
            -AdapterPath $adapterPath `
            -ArtifactsRoot $artifactsRootPath `
            -SourceRepository $script:SourceRepository `
            -SourceRevision $candidateCommit `
            -BaseRevision $baseRevision `
            -EventName $eventName `
            -CandidateArchiveSha256 $candidateArchiveSha256 `
            -OutputPath $preparationPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $preparationPath -PathType Leaf)) {
            throw "Semantic preparation helper failed with exit code $LASTEXITCODE."
        }
        $preparation = Read-JsonFile -Path $preparationPath -Context 'Semantic preparation result'
        Assert-ExactPropertySet -Value $preparation -Expected @('schemaVersion', 'artifactType', 'candidateId', 'candidateContentSha256', 'adapterSha256', 'candidateInventory') -Context 'Semantic preparation result'
        if ([int]$preparation.schemaVersion -ne 1 -or [string]$preparation.artifactType -cne 'standard-validation-consumer-preparation-v1') {
            throw 'Semantic preparation result has an unsupported contract identity.'
        }
        foreach ($entry in @($preparation.candidateId, $preparation.candidateContentSha256, $preparation.adapterSha256)) {
            Assert-Sha256 -Value ([string]$entry) -Context 'Semantic preparation identity'
        }
        if ([string]$preparation.adapterSha256 -cne (Get-FileSha256 -Path $adapterPath)) {
            throw 'Semantic preparation adapter identity does not match the actual generated adapter.'
        }
        $candidateTree = @(& $gitPath -C $repoRoot rev-parse --verify --end-of-options "$candidateCommit^{tree}")
        if ($LASTEXITCODE -ne 0 -or $candidateTree.Count -ne 1 -or [string]$candidateTree[0] -cnotmatch '^[0-9a-f]{40}$') {
            throw 'Could not resolve the immutable candidate tree.'
        }
        $receiptBindings = @(
            foreach ($toolName in @('skillspector', 'skill-validator', 'skill-tools', 'pester')) {
                $receiptPath = Join-Path $runRoot "receipt-$toolName.json"
                [ordered]@{ tool = $toolName; path = [IO.Path]::GetFullPath($receiptPath); sha256 = Get-FileSha256 -Path $receiptPath }
            }
        )
        $plan = [ordered]@{
            schemaVersion = 1
            artifactType = 'standard-validation-consumer-run-plan-v1'
            runId = $runId
            source = [ordered]@{
                repositoryRoot = $repoRoot
                repository = $script:SourceRepository
                revision = $candidateCommit
                baseRevision = $baseRevision
                tree = [string]$candidateTree[0]
                eventName = $eventName
            }
            roots = [ordered]@{
                artifacts = $artifactsRootPath
                run = [IO.Path]::GetFullPath($runRoot)
                trusted = [IO.Path]::GetFullPath($trustedRoot)
                candidateExtract = [IO.Path]::GetFullPath($candidateExtractRoot)
                resolvedTools = [IO.Path]::GetFullPath($resolvedToolsRoot)
            }
            candidate = [ordered]@{
                archivePath = [IO.Path]::GetFullPath($candidateArchivePath)
                archiveSha256 = $candidateArchiveSha256
                snapshotRoot = $candidateRoot
                contentSha256 = [string]$preparation.candidateContentSha256
                inventory = @($preparation.candidateInventory)
                candidateId = [string]$preparation.candidateId
            }
            authority = [ordered]@{
                revision = $script:AuthorityCommit
                archivePath = [IO.Path]::GetFullPath($authorityArchive)
                archiveSha256 = $script:AuthorityArchiveSha256
                root = $authorityRoot
                runnerPath = [IO.Path]::GetFullPath($centralRunnerPath)
                runnerSha256 = Get-FileSha256 -Path $centralRunnerPath
            }
            tools = [ordered]@{
                policyReceiptPath = [IO.Path]::GetFullPath($policyReceiptPath)
                policyReceiptSha256 = Get-FileSha256 -Path $policyReceiptPath
                receipts = $receiptBindings
                toolchainPath = [IO.Path]::GetFullPath($toolchainPath)
                toolchainSha256 = $toolchainSha256
                childRunnerPath = [IO.Path]::GetFullPath($childRunnerPath)
                childRunnerSha256 = Get-FileSha256 -Path $childRunnerPath
                preparationHelperPath = [IO.Path]::GetFullPath($semanticPreparationHelperPath)
                preparationHelperSha256 = Get-FileSha256 -Path $semanticPreparationHelperPath
                preparationPath = [IO.Path]::GetFullPath($preparationPath)
                preparationSha256 = Get-FileSha256 -Path $preparationPath
                adapterPath = [IO.Path]::GetFullPath($adapterPath)
                adapterSha256 = [string]$preparation.adapterSha256
            }
            execution = [ordered]@{
                outputPath = $outputFull
                timeoutSeconds = $TimeoutSeconds
                semanticTriggered = $true
                consumptionClaimPath = "$semanticRunPlanFull.consumed.json"
            }
            semantic = [ordered]@{
                consentRequestPath = $semanticArtifactPaths.consentRequest
                consentDecisionPath = $semanticArtifactPaths.consentDecision
                evidencePath = $semanticArtifactPaths.evidence
                publicKeyPath = $semanticArtifactPaths.publicKey
                publicKeyId = $SemanticPublicKeyId
            }
        }
        Write-Utf8NoBomCreateNew -Path $semanticRunPlanFull -Text (($plan | ConvertTo-Json -Depth 100) + [Environment]::NewLine)
        [pscustomobject]@{ status = 'prepared'; planPath = $semanticRunPlanFull; candidateId = [string]$preparation.candidateId } | ConvertTo-Json -Compress
        exit 0
    }
    $centralRunnerArgs = @(
        '-CandidateRoot', $candidateRoot,
        '-AdapterPath', $adapterPath,
        '-ArtifactsRoot', $artifactsRootPath,
        '-OutputPath', $outputFull,
        '-SourceRepository', $script:SourceRepository,
        '-SourceRevision', $candidateCommit,
        '-BaseRevision', $baseRevision,
        '-EventName', $eventName,
        '-TimeoutSeconds', [string]$TimeoutSeconds,
        '-TrustedToolRoot', $trustedRoot,
        '-DevelopmentHarness'
    )
    if ($SemanticTriggered) { $centralRunnerArgs += '-SemanticTriggered' }
    if ($SemanticConsent) { $centralRunnerArgs += '-SemanticConsent' }
    foreach ($pair in @(
        @('-SemanticProvider', $SemanticProvider),
        @('-SemanticPurpose', $SemanticPurpose),
        @('-SemanticScope', $SemanticScope),
        @('-SemanticEvidencePath', $SemanticEvidencePath),
        @('-SemanticConsentRequestPath', $SemanticConsentRequestPath),
        @('-SemanticConsentDecisionPath', $SemanticConsentDecisionPath),
        @('-SemanticPublicKeyPath', $SemanticPublicKeyPath),
        @('-SemanticPublicKeyId', $SemanticPublicKeyId)
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pair[1])) { $centralRunnerArgs += @($pair[0],$pair[1]) }
    }
    & $pwshPath -NoProfile -NonInteractive -File $centralRunnerPath @centralRunnerArgs
    $centralExitCode = $LASTEXITCODE
    exit $centralExitCode
}
catch {
    throw
}
