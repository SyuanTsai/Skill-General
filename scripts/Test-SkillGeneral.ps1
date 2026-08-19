#requires -Version 7.0

[CmdletBinding()]
param(
    [string] $RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    Split-Path -Parent $PSScriptRoot
}
else {
    [IO.Path]::GetFullPath($RepositoryRoot)
}
$catalogPath = Join-Path $repoRoot 'catalog/skills-catalog.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20
$skillsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.agents/skills'))
$pathSeparators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$skillsRootPrefix = $skillsRoot.TrimEnd($pathSeparators) + [IO.Path]::DirectorySeparatorChar

if ($catalog.schemaVersion -ne 1) {
    throw "Unsupported catalog schemaVersion: $($catalog.schemaVersion)"
}

if ($catalog.catalogId -cne 'skill-general') {
    throw 'Skill-General must expose the stable catalog id: skill-general.'
}

if (@($catalog.sources).Count -ne 1 -or $catalog.sources[0].id -cne 'general') {
    throw 'Skill-General must expose exactly one stable source id: general.'
}

if ($catalog.sources[0].repository -cne 'https://github.com/SyuanTsai/Skill-General.git') {
    throw 'Skill-General source repository URL is invalid.'
}

$skills = @($catalog.skills)
$skillIds = @($skills | ForEach-Object { [string]$_.id })
foreach ($skillId in $skillIds) {
    if ($skillId -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$') {
        throw "Invalid skill id '$skillId'."
    }
}
if (@($skillIds | Sort-Object -Unique).Count -ne $skillIds.Count) {
    throw 'Duplicate skill id detected in catalog.'
}

$actualSkillIds = @(
    Get-ChildItem -LiteralPath $skillsRoot -Directory |
        Select-Object -ExpandProperty Name |
        Sort-Object -CaseSensitive
)
$declaredSkillIds = @($skillIds | Sort-Object -CaseSensitive)
if (($actualSkillIds -join "`n") -cne ($declaredSkillIds -join "`n")) {
    throw 'Catalog Skill inventory does not match .agents/skills directories.'
}

foreach ($skill in $skills) {
    if ($skill.source.sourceId -cne 'general') {
        throw "Skill '$($skill.id)' references unexpected source '$($skill.source.sourceId)'."
    }

    $relativePath = [string]$skill.source.path
    $expectedRelativePath = ".agents/skills/$($skill.id)"
    if ($relativePath -cne $expectedRelativePath) {
        throw "Skill '$($skill.id)' path must be '$expectedRelativePath'."
    }

    $skillRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $skillRoot.StartsWith($skillsRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe Skill path '$relativePath'."
    }

    $skillFile = Join-Path $skillRoot 'SKILL.md'
    $openAiFile = Join-Path $skillRoot 'agents/openai.yaml'

    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        throw "Missing SKILL.md for '$($skill.id)'."
    }
    if (-not (Test-Path -LiteralPath $openAiFile -PathType Leaf)) {
        throw "Missing agents/openai.yaml for '$($skill.id)'."
    }

    $skillText = Get-Content -LiteralPath $skillFile -Raw
    if ($skillText -notmatch "(?m)^name:\s*$([regex]::Escape([string]$skill.id))\s*$") {
        throw "SKILL.md name does not match catalog id '$($skill.id)'."
    }

    $openAiText = Get-Content -LiteralPath $openAiFile -Raw
    if ($openAiText -notmatch [regex]::Escape("`$$($skill.id)")) {
        throw "agents/openai.yaml default prompt does not reference `$$($skill.id)."
    }
}

$requiredProfiles = @('core', 'observability', 'external-research')
$profiles = @($catalog.profiles)
$profileIds = @($profiles | ForEach-Object { [string]$_.id })
if (@($profileIds | Sort-Object -Unique).Count -ne $profileIds.Count) {
    throw 'Duplicate profile id detected in catalog.'
}

if ((@($profileIds | Sort-Object -CaseSensitive) -join "`n") -cne (@($requiredProfiles | Sort-Object -CaseSensitive) -join "`n")) {
    throw 'Catalog must expose exactly the core, observability, and external-research profiles.'
}

$defaultProfiles = @($profiles | Where-Object { [bool]$_.default })
if ($defaultProfiles.Count -ne 1 -or $defaultProfiles[0].id -cne 'core') {
    throw 'The core profile must be the only default profile.'
}

foreach ($profile in $profiles) {
    $includes = @($profile.includes | ForEach-Object { [string]$_ })
    $excludes = @($profile.excludes | ForEach-Object { [string]$_ })
    if (@($includes | Sort-Object -Unique).Count -ne $includes.Count) {
        throw "Profile '$($profile.id)' contains duplicate includes."
    }
    if (@($excludes | Sort-Object -Unique).Count -ne $excludes.Count) {
        throw "Profile '$($profile.id)' contains duplicate excludes."
    }

    foreach ($referencedSkillId in @($includes + $excludes)) {
        if ($referencedSkillId -cnotin $skillIds) {
            throw "Profile '$($profile.id)' references unknown Skill '$referencedSkillId'."
        }
    }

    foreach ($includedSkillId in $includes) {
        if ($includedSkillId -cin $excludes) {
            throw "Profile '$($profile.id)' both includes and excludes Skill '$includedSkillId'."
        }
    }

    foreach ($skill in $skills) {
        $declaredProfiles = @($skill.profiles | ForEach-Object { [string]$_ })
        $profileIncludesSkill = [string]$skill.id -cin $includes
        $skillDeclaresProfile = [string]$profile.id -cin $declaredProfiles
        if ($profileIncludesSkill -ne $skillDeclaresProfile) {
            throw "Profile membership mismatch for Skill '$($skill.id)' and profile '$($profile.id)'."
        }
    }
}

foreach ($skill in $skills) {
    $declaredProfiles = @($skill.profiles | ForEach-Object { [string]$_ })
    if ($declaredProfiles.Count -eq 0) {
        throw "Skill '$($skill.id)' must belong to at least one profile."
    }
    if (@($declaredProfiles | Sort-Object -Unique).Count -ne $declaredProfiles.Count) {
        throw "Skill '$($skill.id)' declares duplicate profiles."
    }
    foreach ($profileId in $declaredProfiles) {
        if ($profileId -cnotin $profileIds) {
            throw "Skill '$($skill.id)' references unknown profile '$profileId'."
        }
    }
}

Write-Host "Skill-General validation passed: $($skillIds.Count) skills, $($profileIds.Count) profiles."
