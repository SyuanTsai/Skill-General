# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

Set-StrictMode -Version Latest

function ConvertTo-LegacyNotionUtcTicks {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Timestamp
    )

    $parsed = [DateTimeOffset]::MinValue
    $valid = [DateTimeOffset]::TryParse(
        $Timestamp,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
    if (-not $valid) {
        throw "Legacy Notion native timestamp is invalid: '$Timestamp'."
    }
    return $parsed.UtcDateTime.Ticks
}

function Get-LegacyNotionCanonicalChanges {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array] $Changes
    )

    $normalized = @(
        foreach ($change in $Changes) {
            if ([bool]$change.merged) {
                continue
            }

            $createdTicks = ConvertTo-LegacyNotionUtcTicks -Timestamp ([string]$change.created_time)
            $lastEditedTicks = ConvertTo-LegacyNotionUtcTicks -Timestamp ([string]$change.last_edited_time)
            [PSCustomObject]@{
                Change = $change
                EffectiveTicks = [Math]::Max($createdTicks, $lastEditedTicks)
                ChangeId = [string]$change.id
                LastEditedTicks = $lastEditedTicks
                MergedOrdinal = if ([bool]$change.merged) { 1 } else { 0 }
                Field = [string]$change.field
                Value = [string]$change.value
            }
        }
    )

    return @(
        $normalized | Sort-Object -CaseSensitive -Property @(
            @{ Expression = 'EffectiveTicks'; Ascending = $true },
            @{ Expression = 'ChangeId'; Ascending = $true },
            @{ Expression = 'LastEditedTicks'; Ascending = $true },
            @{ Expression = 'MergedOrdinal'; Ascending = $true },
            @{ Expression = 'Field'; Ascending = $true },
            @{ Expression = 'Value'; Ascending = $true }
        )
    )
}

function Get-LegacyNotionUnmergedChangeFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array] $Changes
    )

    $canonical = @(Get-LegacyNotionCanonicalChanges -Changes $Changes)
    $builder = [Text.StringBuilder]::new()
    foreach ($item in $canonical) {
        $components = @(
            [string]$item.EffectiveTicks,
            [string]$item.ChangeId,
            [string]$item.LastEditedTicks,
            [string]$item.MergedOrdinal,
            [string]$item.Field,
            [string]$item.Value
        )
        foreach ($component in $components) {
            $byteCount = [Text.Encoding]::UTF8.GetByteCount($component)
            [void]$builder.Append($byteCount).Append(':').Append($component)
        }
        [void]$builder.Append("`n")
    }

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return [Convert]::ToHexString($hasher.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

function ConvertFrom-LegacyNotionChangeValue {
    param(
        [Parameter(Mandatory)] $Change,
        [Parameter(Mandatory)] $Contract
    )

    $field = [string]$Change.field
    $encoding = $Contract.handoff.changeValueEncoding
    $stringFields = @($encoding.stringFields)
    $dateFields = @($encoding.dateFields)
    if ($field -cnotin @($stringFields + $dateFields)) {
        return [PSCustomObject]@{ Valid = $false; Value = $null }
    }

    try {
        $decoded = ConvertFrom-Json -InputObject ([string]$Change.value) -Depth 5 -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{ Valid = $false; Value = $null }
    }

    if ($field -cin $stringFields) {
        if ($decoded -isnot [string]) {
            return [PSCustomObject]@{ Valid = $false; Value = $null }
        }
        if ($field -ceq 'Lifecycle' -and $decoded -cnotin @($Contract.handoff.lifecycleStates)) {
            return [PSCustomObject]@{ Valid = $false; Value = $null }
        }
        if ($field -ceq 'Work State' -and $decoded -cnotin @($Contract.handoff.workStates)) {
            return [PSCustomObject]@{ Valid = $false; Value = $null }
        }
        return [PSCustomObject]@{ Valid = $true; Value = $decoded }
    }

    if ($null -eq $decoded) {
        return [PSCustomObject]@{ Valid = $true; Value = $null }
    }
    $rfc3339 = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$'
    if ($decoded -isnot [string] -or $decoded -cnotmatch $rfc3339) {
        return [PSCustomObject]@{ Valid = $false; Value = $null }
    }
    $parsedDate = [DateTimeOffset]::MinValue
    $validDate = [DateTimeOffset]::TryParse(
        $decoded,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsedDate
    )
    return [PSCustomObject]@{ Valid = $validDate; Value = $decoded }
}

function Resolve-LegacyNotionHandoffReplay {
    param(
        [Parameter(Mandatory)] $Main,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array] $Changes,
        [Parameter(Mandatory)] $Contract
    )

    $state = [ordered]@{}
    foreach ($property in $Main.fields.PSObject.Properties) {
        $state[$property.Name] = $property.Value
    }

    $validated = @(
        foreach ($item in @(Get-LegacyNotionCanonicalChanges -Changes $Changes)) {
            $decoded = ConvertFrom-LegacyNotionChangeValue -Change $item.Change -Contract $Contract
            [PSCustomObject]@{
                Change = $item.Change
                ChangeId = $item.ChangeId
                Field = $item.Field
                EffectiveTicks = $item.EffectiveTicks
                Valid = [bool]$decoded.Valid
                DecodedValue = $decoded.Value
                CollisionKey = '{0}:{1}:{2}' -f (
                    [Text.Encoding]::UTF8.GetByteCount($item.Field)
                ), $item.Field, $item.EffectiveTicks
            }
        }
    )

    $collisionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $collisions = [Collections.Generic.List[object]]::new()
    foreach ($group in @($validated | Where-Object Valid | Group-Object CollisionKey -CaseSensitive)) {
        if ($group.Count -le 1) {
            continue
        }
        foreach ($entry in $group.Group) {
            [void]$collisionIds.Add([string]$entry.ChangeId)
            $collisions.Add([PSCustomObject]@{
                ChangeId = [string]$entry.ChangeId
                Field = [string]$entry.Field
                EffectiveNativeTime = [DateTimeOffset]::new([long]$entry.EffectiveTicks, [TimeSpan]::Zero).ToString('o')
                Value = [string]$entry.Change.value
            })
        }
    }

    $applied = [Collections.Generic.List[string]]::new()
    foreach ($entry in $validated) {
        if (-not $entry.Valid -or $collisionIds.Contains([string]$entry.ChangeId)) {
            continue
        }
        $state[[string]$entry.Field] = $entry.DecodedValue
        $applied.Add([string]$entry.ChangeId)
    }

    return [PSCustomObject]@{
        Fields = [PSCustomObject]$state
        AppliedChangeIds = [string[]]$applied
        CollisionFields = [string[]]@(
            $collisions |
                ForEach-Object { [string]$_.Field } |
                Sort-Object -CaseSensitive -Unique
        )
        Collisions = [object[]]$collisions
        InvalidChangeIds = [string[]]@(
            $validated |
                Where-Object { -not $_.Valid } |
                ForEach-Object { [string]$_.ChangeId }
        )
    }
}

function Get-LegacyNotionSnapshotIdentity {
    param(
        [Parameter(Mandatory)] $Main,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array] $Changes
    )

    $mainId = [string]$Main.id
    if ([string]::IsNullOrWhiteSpace($mainId)) {
        throw 'Legacy Notion main record must have an immutable id.'
    }
    return [PSCustomObject]@{
        MainId = $mainId
        MainLastEditedTicks = ConvertTo-LegacyNotionUtcTicks -Timestamp ([string]$Main.last_edited_time)
        ChangeFingerprint = Get-LegacyNotionUnmergedChangeFingerprint -Changes $Changes
    }
}

function Invoke-LegacyNotionReadOnlyReplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Contract,
        [Parameter(Mandatory)] [scriptblock] $ReadMain,
        [Parameter(Mandatory)] [scriptblock] $ReadUnmergedChanges
    )

    $maximumRetries = [int]$Contract.handoff.readOnlyReplay.maxReconstructionRetries
    for ($attempt = 0; $attempt -le $maximumRetries; $attempt++) {
        $capturedMain = & $ReadMain
        $capturedChanges = @(& $ReadUnmergedChanges)
        $captured = Get-LegacyNotionSnapshotIdentity -Main $capturedMain -Changes $capturedChanges
        $replay = Resolve-LegacyNotionHandoffReplay -Main $capturedMain -Changes $capturedChanges -Contract $Contract

        $confirmedMain = & $ReadMain
        $confirmedChanges = @(& $ReadUnmergedChanges)
        $confirmed = Get-LegacyNotionSnapshotIdentity -Main $confirmedMain -Changes $confirmedChanges
        $stable = (
            $captured.MainId -ceq $confirmed.MainId -and
            $captured.MainLastEditedTicks -eq $confirmed.MainLastEditedTicks -and
            $captured.ChangeFingerprint -ceq $confirmed.ChangeFingerprint
        )
        if ($stable) {
            return [PSCustomObject]@{
                Status = 'Stable'
                ReconstructionAttempts = $attempt + 1
                CapturedFingerprint = $captured.ChangeFingerprint
                ConfirmedFingerprint = $confirmed.ChangeFingerprint
                Replay = $replay
            }
        }
        if ($attempt -eq $maximumRetries) {
            return [PSCustomObject]@{
                Status = 'Unstable'
                ReconstructionAttempts = $attempt + 1
                CapturedFingerprint = $captured.ChangeFingerprint
                ConfirmedFingerprint = $confirmed.ChangeFingerprint
                Replay = $null
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LegacyNotionUnmergedChangeFingerprint',
    'Invoke-LegacyNotionReadOnlyReplay'
)
