<!-- SPDX-FileCopyrightText: 2026 SyuanTsai; SPDX-License-Identifier: Apache-2.0 -->
# Workflow and v1 wire contract

## Capability boundary

This package has no database driver, login broker or SQL execution CLI. `Test-Contract.ps1` reads a local document and checks shape/consistency; its output is not `SUCCESS` from a database. A future implementation must bind the deployment's protected CLI path, version/hash, local execution IPC and registered connections in trusted host metadata. Do not copy an executable path from database rows or other untrusted content.

The future execution surface comprises `connections` (nonsecret registered target/status discovery), `execute --request-file <path>` and `status --request-id <id>`. These are proposed subcommands, not installed binaries. They accept no server, connection string, Token or management override. Human authorization/login/install entrypoints are separate desktop/management surfaces with different ACLs.

## First connection and later tasks

The human tool identifies the actual host, normalized Azure SQL server, exact database and Entra tenant/object ID plus database principal, then confirms DEV/UAT/PRD and the object, column and row scope. The protected service saves an Active record matching [authorization.schema.json](authorization.schema.json). `host_binding` is an independently established deployment identity; it is not an Agent-selected machine name. The record contains no credentials and is not a portable grant that can be copied to another host unchecked.

`allowed_operations` and every object's operations must fit the environment matrix. `row_scope` is a conjunction of EQ/IN predicates using typed non-null values, not raw SQL. EQ has one value; IN has at least one. The service must bind predicates safely, intersect requested columns and object grants, and enforce those conditions on every relevant table alias/dependency. Unknown or unrepresentable scope is denied. Version 1 deliberately cannot encode arbitrary policy expressions. Disallow writes until keys, permitted write columns, dependency revision and schema fingerprint are verified against the current database. Record validation does not prove that verification occurred.

The confirmed limits bound end-to-end time, result rows/bytes, writes, lock waiting and concurrency. Schema maxima are wire-format ceilings, not user grants or recommended operational limits. Synthetic examples use 30 seconds/1,000 rows/10 writes only to exercise the format. Human first authorization and empirical validation determine operational values.

Each operation rechecks current protected policy/version/status and actual session target/principal. Pools are isolated by target and identity. Revocation, logout, policy change, identity switch, dependency/schema changes or deployment migration invalidates affected sessions/caches. Unknown versions fail closed. Login expiry and reboot preserve the environment decision; re-login to the same confirmed identity resumes it. Entra silent renewal is attempted only through a company-approved client; `AUTH_REQUIRED` leads to human desktop MFA without a password fallback or session-cache extraction.

## Execution envelope

[request.schema.json](request.schema.json) defines `schema_version`, UUID `request_id`, registered `connection_id`, `operation`, `task`, typed `parameters` and exactly one SELECT `sql` or mutation `write` branch. A `verify-test` or `investigate` task cannot send a mutation. `modify` enables the UPDATE contract and `cleanup` the DELETE contract, subject to explicit task intent and service grants. Correlation and purpose are evidence of requested intent, not authorization supplied by the caller; the service must verify the trusted task scope and current Windows peer identity separately.

Supported parameter types: int/bigint JSON integers, decimal invariant strings with precision/scale, bit booleans, bounded nvarchar strings with size, UUIDs, UTC datetime2 strings and hex binary (including expected rowversion). Null is explicit. The future provider must additionally validate representability, calendar/time correctness, decimal precision and SQL type compatibility without coercion. Write bindings name existing parameters; keys are non-null, expected values/rowversion express optimistic concurrency and `set` is UPDATE-only. The service generates parameterized SQL and combines the grant's row condition with keys and expected conditions inside the transaction.

## Response and recovery

[response.schema.json](response.schema.json) defines request ID, actual environment/policy (nullable when no session was established), status, necessary result/affected rows, truncation, elapsed time, audit reference, safe error code/message, commit state and retry safety. A read success has column metadata and positionally aligned rows, no affected count and no commit. A committed write success has a verified affected count and no row result. The byte/row/time limits still require enforcement in the service.

`DENIED`, `AUTH_REQUIRED`, `TARGET_CHANGED` and `ERROR` contain no business result. `UNCERTAIN_COMMIT` requires unknown commit state, null affected rows, no result and `retry_safe=false`; look up the protected request record and reconcile the original operation before any resend. Known committed requests return recorded results without executing again. A local failure before submission may be retried after fixing its cause; after submission, determine whether the service accepted the request. No exactly-once guarantee is claimed.

Audits bind request, authenticated peer/principal, environment/target, policy/program revision, operation/objects, counts, time, outcome and denial reason. They omit Tokens, passwords, full SQL parameter values and sensitive business rows. Audit read/write permissions are separate from Agent execution rights.
