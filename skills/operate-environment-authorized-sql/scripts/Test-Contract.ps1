# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Authorization','Request','Response')][string] $Contract,
    [Parameter(Mandatory)][string] $InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Offline diagnostics only. These functions never access a database, credentials, or IPC.
function Assert-UnambiguousJson([System.Text.Json.JsonElement] $Element) {
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'DUPLICATE_PROPERTY' }
            Assert-UnambiguousJson $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-UnambiguousJson $item }
    }
}

function Assert-Parameters($Parameters) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($parameter in $Parameters) {
        if (-not $seen.Add([string]$parameter.name)) { throw 'DUPLICATE_PARAMETER' }
        if ($parameter.type -ceq 'decimal' -and $parameter.scale -gt $parameter.precision) { throw 'INVALID_DECIMAL_SCALE' }
        if ($parameter.type -ceq 'nvarchar' -and $null -ne $parameter.value -and $parameter.value.Length -gt $parameter.size) { throw 'PARAMETER_SIZE_EXCEEDED' }
        $permitted = @('name','type','value')
        if ($parameter.type -ceq 'nvarchar') { $permitted += 'size' }
        if ($parameter.type -ceq 'decimal') { $permitted += @('precision','scale') }
        foreach ($key in $parameter.Keys) {
            if ($key -cnotin $permitted) { throw 'INVALID_PARAMETER_METADATA' }
        }
    }
}

function Assert-Request($Value) {
    Assert-Parameters $Value.parameters
    if ($Value.operation -ceq 'SELECT') { return }
    $parameters = @{}
    foreach ($parameter in $Value.parameters) { $parameters[$parameter.name] = $parameter }
    $bindings = @($Value.write.keys) + @($Value.write.expected)
    if ($Value.operation -ceq 'UPDATE') { $bindings += @($Value.write.set) }
    foreach ($binding in $bindings) {
        if (-not $parameters.ContainsKey($binding.parameter)) { throw 'UNBOUND_WRITE_PARAMETER' }
    }
    foreach ($group in @('keys','expected','set')) {
        if (-not $Value.write.ContainsKey($group)) { continue }
        $columns = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($binding in $Value.write[$group]) {
            if (-not $columns.Add($binding.column)) { throw 'DUPLICATE_WRITE_COLUMN' }
            if ($group -ceq 'keys' -and $null -eq $parameters[$binding.parameter].value) { throw 'NULL_WRITE_KEY' }
        }
    }
}

function Assert-Authorization($Value) {
    $matrix = @{ DEV = @('SELECT','UPDATE','DELETE'); UAT = @('SELECT','UPDATE'); PRD = @('SELECT') }
    foreach ($operation in $Value.allowed_operations) {
        if ($operation -cnotin $matrix[$Value.environment]) { throw 'ENVIRONMENT_OPERATION_DENIED' }
    }
    $objects = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in $Value.objects) {
        if (-not $objects.Add($scope.schema + '.' + $scope.name)) { throw 'DUPLICATE_OBJECT' }
        foreach ($operation in $scope.operations) {
            if ($operation -cnotin $Value.allowed_operations) { throw 'OBJECT_OPERATION_EXCEEDS_GRANT' }
        }
        if (@($scope.operations | Where-Object { $_ -cne 'SELECT' }).Count -gt 0) {
            if ($scope.dependency_state -cne 'confirmed') { throw 'UNVERIFIED_WRITE_DEPENDENCIES' }
            if ('UPDATE' -cin $scope.operations -and $scope.write_columns.Count -eq 0) { throw 'MISSING_WRITE_COLUMNS' }
        }
        foreach ($rule in $scope.row_scope) {
            Assert-Parameters $rule.values
            if ($rule.operator -ceq 'EQ' -and $rule.values.Count -ne 1) { throw 'INVALID_EQUALITY_SCOPE' }
            foreach ($parameter in $rule.values) {
                if ($null -eq $parameter.value) { throw 'NULL_ROW_SCOPE' }
            }
        }
    }
    if ($Value.limits.lock_timeout_ms -gt $Value.limits.operation_timeout_ms) { throw 'LOCK_TIMEOUT_EXCEEDS_OPERATION' }
}

function Assert-Response($Value) {
    if ($Value.status -cne 'SUCCESS') { return }
    if (($null -eq $Value.result) -eq ($null -eq $Value.affected_rows)) { throw 'AMBIGUOUS_SUCCESS_RESULT' }
    if ($null -ne $Value.result) {
        if ($Value.commit_state -cne 'not-applicable') { throw 'READ_COMMIT_STATE' }
        foreach ($row in $Value.result.rows) {
            if ($row.Count -ne $Value.result.columns.Count) { throw 'RESULT_COLUMN_MISMATCH' }
        }
    }
    elseif ($Value.commit_state -cne 'committed' -or $Value.truncated) { throw 'WRITE_COMMIT_STATE' }
}

$valid = $false
$reason = 'INVALID_DOCUMENT'
try {
    $item = Get-Item -LiteralPath $InputPath -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 1048576) { throw 'INVALID_INPUT_FILE' }
    $text = [IO.File]::ReadAllText($item.FullName, [Text.UTF8Encoding]::new($false, $true))
    $document = [System.Text.Json.JsonDocument]::Parse($text)
    try { Assert-UnambiguousJson $document.RootElement } finally { $document.Dispose() }
    $schemaPath = Join-Path (Split-Path -Parent $PSScriptRoot) ('references/' + $Contract.ToLowerInvariant() + '.schema.json')
    if (-not (Test-Json -Json $text -SchemaFile $schemaPath -ErrorAction Ignore)) { throw 'SCHEMA_MISMATCH' }
    $value = ConvertFrom-Json -InputObject $text -AsHashtable -Depth 64
    switch -CaseSensitive ($Contract) {
        'Authorization' { Assert-Authorization $value }
        'Request' { Assert-Request $value }
        'Response' { Assert-Response $value }
        default { throw 'UNKNOWN_CONTRACT' }
    }
    $valid = $true
    $reason = 'CONTRACT_VALID'
}
catch {
    # Never echo input or provider exception messages containing business data.
    if ($_.Exception.Message -cmatch '^[A-Z_]+$') { $reason = $_.Exception.Message }
}
[pscustomobject]@{
    schema_version = 1
    contract = $Contract
    valid = $valid
    code = $reason
    databaseExecuted = $false
    sqlPolicyValidated = $false
}
