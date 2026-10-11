# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0
Describe 'environment-authorized SQL v1 offline contracts' {
    BeforeAll {
        $script:SkillRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/operate-environment-authorized-sql'
        $script:Validator = Join-Path $script:SkillRoot 'scripts/Test-Contract.ps1'
        $script:Fixtures = Join-Path $PSScriptRoot 'fixtures/environment-authorized-sql'
        function Test-Envelope($Kind, $Value) {
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
            $text = if ($Value -is [string]) { $Value } else { ConvertTo-Json -InputObject $Value -Depth 40 -Compress }
            [IO.File]::WriteAllText($path, $text)
            & $script:Validator -Contract $Kind -InputPath $path
        }
        function Read-Fixture($Name) { Get-Content -LiteralPath (Join-Path $script:Fixtures ($Name + '.json')) -Raw | ConvertFrom-Json -AsHashtable -Depth 40 }
    }

    # Scenario: A bounded SELECT envelope carries typed parameters and a test purpose.
    # Purpose: Accept the public wire contract without pretending a database was reached.
    It 'UnitT10_accepts_a_typed_read_request_without_executing_SQL' {
        $result = Test-Envelope Request (Read-Fixture 'read')
        $result.valid | Should -BeTrue
        $result.databaseExecuted | Should -BeFalse
        $result.sqlPolicyValidated | Should -BeFalse
    }

    # Scenario: A caller adds its own target, token, authorization or policy override.
    # Purpose: Prevent the execution wire format from exposing a management path.
    It 'UnitT20_rejects_unknown_execution_fields_<Field>' -ForEach @(
        @{ Field = 'server' }, @{ Field = 'database' }, @{ Field = 'token' },
        @{ Field = 'authorization' }, @{ Field = 'policy_override' }
    ) {
        $value = Read-Fixture 'read'; $value[$Field] = 'synthetic'
        (Test-Envelope Request $value).valid | Should -BeFalse
    }

    # Scenario: Ambiguous duplicated fields or an unsupported version enters the JSON wire.
    # Purpose: Fail closed before normal JSON materialization loses the ambiguity.
    It 'UnitT25_rejects_duplicate_case_colliding_fields_and_unknown_version' {
        (Test-Envelope Request '{"schema_version":1,"schema_version":1}').valid | Should -BeFalse
        (Test-Envelope Request '{"schema_version":1,"Schema_Version":1}').valid | Should -BeFalse
        $value = Read-Fixture 'read'; $value.schema_version = 2
        (Test-Envelope Request $value).valid | Should -BeFalse
    }

    # Scenario: A read task is repurposed as a raw or structured mutation.
    # Purpose: Keep the current task purpose independent from an environment's potential grants.
    It 'UnitT30_rejects_raw_writes_and_mutations_in_a_check_task' {
        $value = Read-Fixture 'read'; $value.operation = 'UPDATE'
        (Test-Envelope Request $value).valid | Should -BeFalse
        $value = Read-Fixture 'update'; $value.task.purpose = 'verify-test'
        (Test-Envelope Request $value).valid | Should -BeFalse
        (Test-Envelope Request (Read-Fixture 'update')).valid | Should -BeTrue
        (Test-Envelope Request (Read-Fixture 'delete')).valid | Should -BeTrue
    }

    # Scenario: A write omits its keys/concurrency guard or sends SQL through the write branch.
    # Purpose: Require structural prerequisites while reserving semantic safety for the service.
    It 'UnitT35_requires_keys_expected_values_and_parameter_bindings' {
        foreach ($field in @('keys','expected')) {
            $value = Read-Fixture 'update'; $value.write[$field] = @()
            (Test-Envelope Request $value).valid | Should -BeFalse
        }
        $value = Read-Fixture 'update'; $value.sql = 'UPDATE synthetic'
        (Test-Envelope Request $value).valid | Should -BeFalse
        $value = Read-Fixture 'update'; $value.write.set[0].parameter = '@missing'
        (Test-Envelope Request $value).valid | Should -BeFalse
        $value = Read-Fixture 'update'; $value.parameters += $value.parameters[0]
        (Test-Envelope Request $value).valid | Should -BeFalse
    }

    # Scenario: An authorization attempts to grant operations excluded by its environment.
    # Purpose: Keep DEV/UAT/PRD grants consistent and reject unknown environments.
    It 'UnitT40_enforces_the_environment_operation_matrix_in_authorization_records' {
        (Test-Envelope Authorization (Read-Fixture 'authorization')).valid | Should -BeTrue
        $value = Read-Fixture 'authorization'; $value.environment = 'UAT'
        (Test-Envelope Authorization $value).valid | Should -BeFalse
        $value.allowed_operations = @('SELECT','UPDATE'); $value.objects[0].operations = @('SELECT','UPDATE')
        (Test-Envelope Authorization $value).valid | Should -BeTrue
        $value.environment = 'PRD'
        (Test-Envelope Authorization $value).valid | Should -BeFalse
        $value.allowed_operations = @('SELECT'); $value.objects[0].operations = @('SELECT')
        (Test-Envelope Authorization $value).valid | Should -BeTrue
        $value.environment = 'UNKNOWN'
        (Test-Envelope Authorization $value).valid | Should -BeFalse
    }

    # Scenario: A grant enables writes with unverified dependencies or requests an unlisted operation.
    # Purpose: Preserve write dependency evidence and default-deny structural boundaries.
    It 'UnitT45_rejects_unverified_write_dependencies_and_unlisted_operations' {
        $value = Read-Fixture 'authorization'; $value.objects[0].dependency_state = 'unknown'
        (Test-Envelope Authorization $value).valid | Should -BeFalse
        foreach ($operation in @('INSERT','MERGE','DDL','EXEC')) {
            $value = Read-Fixture 'authorization'; $value.allowed_operations = @($operation)
            (Test-Envelope Authorization $value).valid | Should -BeFalse
        }
        $value = Read-Fixture 'authorization'; $value.objects[0].operations = @('SELECT','UPDATE','DELETE'); $value.allowed_operations = @('SELECT')
        (Test-Envelope Authorization $value).valid | Should -BeFalse
    }

    # Scenario: A commit result is uncertain after a timeout or disconnection.
    # Purpose: Make uncertainty explicit and disallow a response that invites blind resend.
    It 'UnitT50_requires_unknown_commit_state_and_no_automatic_retry' {
        $value = Read-Fixture 'uncertain'
        (Test-Envelope Response $value).valid | Should -BeTrue
        $value.retry_safe = $true
        (Test-Envelope Response $value).valid | Should -BeFalse
        $value.retry_safe = $false; $value.affected_rows = 1
        (Test-Envelope Response $value).valid | Should -BeFalse
    }

    # Scenario: Successful read data or a denied response travels across the boundary.
    # Purpose: Require bounded structured output and never confuse denial with results.
    It 'UnitT60_validates_success_and_failure_response_shapes' {
        (Test-Envelope Response (Read-Fixture 'success')).valid | Should -BeTrue
        (Test-Envelope Response (Read-Fixture 'denied')).valid | Should -BeTrue
        $value = Read-Fixture 'denied'; $value.result = (Read-Fixture 'success').result
        (Test-Envelope Response $value).valid | Should -BeFalse
        $value = Read-Fixture 'success'; $value.result.rows[0] += 'extra-column'
        (Test-Envelope Response $value).valid | Should -BeFalse
    }
}
