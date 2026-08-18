#requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'catalog/skills-catalog.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20

if ($catalog.schemaVersion -ne 1) {
    throw "Unsupported catalog schemaVersion: $($catalog.schemaVersion)"
}

if ($catalog.sources.Count -ne 1 -or $catalog.sources[0].id -ne 'general') {
    throw 'Skill-General must expose exactly one stable source id: general.'
}

$skillIds = @($catalog.skills | ForEach-Object { [string]$_.id })
if (($skillIds | Sort-Object -Unique).Count -ne $skillIds.Count) {
    throw 'Duplicate skill id detected in catalog.'
}

foreach ($skill in $catalog.skills) {
    if ($skill.source.sourceId -ne 'general') {
        throw "Skill '$($skill.id)' references unexpected source '$($skill.source.sourceId)'."
    }

    $relativePath = [string]$skill.source.path
    if (-not $relativePath.StartsWith('.agents/skills/', [StringComparison]::Ordinal)) {
        throw "Unsafe or unsupported skill path '$relativePath'."
    }

    $skillRoot = Join-Path $repoRoot $relativePath
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
}

$requiredProfiles = @('core', 'observability', 'external-research')
$profileIds = @($catalog.profiles | ForEach-Object { [string]$_.id })
foreach ($profile in $requiredProfiles) {
    if ($profile -notin $profileIds) {
        throw "Missing required profile '$profile'."
    }
}

Write-Host "Skill-General validation passed: $($skillIds.Count) skills, $($profileIds.Count) profiles."
