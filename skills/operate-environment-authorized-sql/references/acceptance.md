<!-- SPDX-FileCopyrightText: 2026 SyuanTsai; SPDX-License-Identifier: Apache-2.0 -->
# Acceptance evidence

## First-stage package acceptance

Record exact source/authority revisions, candidate content inventory/hashes, actual tool versions, real commands, target kind, exit codes and reports. Verify discriminating routing, all required references, canonical source inventory and self-contained resource paths. Run the strict authorization/request/response diagnostics against positive synthetic envelopes and negative override, unknown-version, duplicate/case-colliding field, raw write, purpose mismatch, parameter binding, environment matrix, dependency and uncertainty cases. A valid envelope proves shape/consistency only.

Follow central source validation and review/release requirements. In the explicit installation target, record exact installed inventory/provenance, Agent discovery/load, version confirmation, repeated installation, removal/rollback and preservation of customized/unmanaged files. Missing approval, validation or discovery evidence leaves the relevant DoD item outstanding; no document-only completion claim is allowed.

## Runtime acceptance remains pending

[runtime-acceptance-cases.json](runtime-acceptance-cases.json) is a synthetic executable-test specification for P3–P5, not executed test results. Each case retains `executed=false`. It includes initial authorization, repeated no-prompt operations, reboot/re-login, target/principal drift, revoked/unknown policy, full-AST rejection and positive JOIN/CTE, hidden dependencies, atomic write limit/concurrency, uncertain commit/replay, real OS identity isolation, bounded output and fixed CLI approval behavior.

Additionally exercise every operation/environment combination in the real service: DEV SELECT/UPDATE/DELETE, UAT SELECT/UPDATE and deny DELETE, PRD SELECT and deny all writes, with all unlisted operations denied everywhere. PRD access requires its own explicit read authorization; first prove write denial offline/DEV. Use recoverable DEV data and a verified restoration plan for write scenarios.

Windows identity/ACL and token isolation require actual low-privilege peer tests; mocks or separate working directories under the same user are insufficient. Entra/MFA/token renewal, current DB principal/target, transaction rollback, triggers/cascades, real cancellation/output limits and no per-call approval require deployed-runtime/DB evidence. No DB role/account/GRANT/REVOKE, company Entra policy change or PRD write is authorized by this package.

For each real runtime case retain command, host identity, actual DB target type, program/policy/contract revision, sanitized audit reference, result and remaining uncertainty. Never put Tokens, passwords, sensitive rows or full credential-bearing connection strings in evidence.
