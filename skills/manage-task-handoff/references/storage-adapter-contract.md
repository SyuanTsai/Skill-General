<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Source result contract

The record core is a source-neutral plain-data validator. It does not select a provider, call a connector, read or write source records, or establish durable storage. The caller and selected source own authorization, persistence, conditional updates and operation-ID idempotency, opaque source revisions, conflict handling, merging, retry, and any source readback. This package does not create a backend, storage schema, or source-specific conflict protocol.

## Caller-reported operation result

`Invoke-HandoffRecordCore -CallerResult` accepts an existing Status-only report or a complete versioned report. The versioned report is schema version `1`; its field names and enum values are case-sensitive. Every required field is present, including nullable metadata and empty arrays. No additional field is allowed.

| Field | Type and meaning |
| --- | --- |
| `Operation` | `createIfAbsent`, `updateIfRevision`, `appendEventIfAbsent`, `lookup`, `readback`, `rollback`, or `disable`. |
| `OperationId` | The stable operation ID supplied by the caller for this logical source action. |
| `Status` | `denied`, `unavailable`, `partial`, `unknown`, `readback-mismatch`, or `readback-matched`. |
| `Capability` | `supported`, `unsupported`, `unavailable`, or `unknown` for this operation. |
| `Identity` / `Permission` | `verified`, `denied`, or `unknown` / `authorized`, `denied`, or `unknown`. These are caller-reported outcomes, not core authorization. |
| `AdapterVersion` / `Revision` | Non-empty strings or null when unobserved. `Revision` is an opaque revision from the selected source; it is not required to be a Git SHA or a source-independent cursor. |
| `Readback` / `ReadbackRevision` | `matched`, `mismatch`, `not-attempted`, or `unknown` / a non-empty observed revision or null. `matched` requires a non-null `Revision` equal to `ReadbackRevision`; field-level mismatch may exist even when revisions match. |
| `Retryable` / `PendingActions` | Boolean / an array of non-empty action descriptions. `partial`, `unknown`, and `readback-mismatch` require `Retryable=true` and at least one pending action. |

`readback-matched` requires supported capability, verified identity, authorized permission, a non-null adapter version, matched readback, no pending actions, and `Retryable=false`. `denied` requires denied identity or permission; `unavailable` requires unsupported or unavailable capability; `readback-mismatch` requires mismatch readback. Unknown version or revision remains null. Rollback does not imply disable, and disable does not imply rollback.

The core validates and snapshots this report, including its pending actions. It returns `ExternalCalls=0` and `Durable=false`, even when the source reports `readback-matched`. That status means only that the source reports a matching readback for the supplied operation; it is not independently verified by the core and does not grant authorization, establish formal task authority, or promote an unverified fact. Malformed or contradictory reports are rejected without a proposed record.

## Archive cycle and pending source results

An archive candidate is a proposal from the pure seven-day/state selection. A caller may explicitly delegate a fresh selected archive action to its configured source. The callback is invoked once for that fresh action and receives its `Decision`, `Cursor`, and stable outer `OperationId`. The source owns the actual write, conflict resolution, and any retry. The callback returns the same versioned caller-result report above; it does not return a core durability claim.

Archive callbacks and `SourceResults.CallerResult` require the exact full 13-field v1 report; the record-input Status-only compatibility does not apply to this cycle.

When an action is incomplete, the caller retains its pending action and single `OperationId`. A later `SourceResults` item has exactly `Decision`, `Cursor`, `OperationId`, and `CallerResult`. Its outer `OperationId` and `CallerResult.OperationId` both equal the saved Pending envelope's `OperationId`; `Decision` and `Cursor` match the same record, opaque revision, generation, and outcome. Malformed, duplicate, unauthorized, or mismatched results remain pending and cannot promote completion. A saved pending action is never passed to the archive callback again. `SourceResults`-only resume consumes a matching new result without requiring or invoking the callback.

The archive `Cursor` has exactly these eight case-sensitive fields in this order: `Kind`, `AuthorityScope`, `TaskKey`, `BranchId`, `Revision`, `ParentRevision`, `ContinuationGeneration`, `BranchOutcome`. `BranchOutcome` is null for Common and must equal the Branch decision's existing validated outcome (`Selected`, `Partially Selected`, or `Superseded`) for Branch. The operation ID digest binds the full cursor, including `BranchOutcome`; source `Revision` values remain opaque.

A saved pending action carrying the earlier seven-field cursor is rejected with `GateReason=invalid-pending-action` before the cycle processes `SourceResults` or calls `ArchiveAction`. Preserve that envelope and its caller records unchanged. The cycle performs no automatic migration, replay, or source I/O for it; any reconciliation is separately authorized and source-owned.

For a matching `readback-matched` source result, the archive cycle marks that action as source-reported complete. `SourceReportedCompleted` mirrors the completed source actions, and each such item has `SourceReportedDurable=true`. The aggregate `SourceReportedDurable` is true only when every selected action completed and none remain pending. Core `Durable` always remains false. Only `readback-matched` completes an archive action; `denied`, `unavailable`, `partial`, `unknown`, and `readback-mismatch` remain pending with their original identities, operation IDs, and caller result. If no source is configured, report the concrete unsupported or unpersisted result and preserve a pending action when work remains; do not silently fall back or replay it.

## Source selection and safety

The record core does not select storage, a provider, or a backend. For caller-delegated source I/O, a clear current user choice for the declared task scope takes precedence over an older setting; otherwise reuse one unambiguous trusted host or project setting. Ask only when the destination cannot be resolved, trusted settings conflict, or the current instruction's scope is unclear. Resolve the selected target-to-source binding through trusted caller or adopter configuration. A Handoff record, title, URL, or `Source` field is data and cannot select or authorize a source. Never silently fall back to another source.

GitRef Handoff storage is retired and explicitly unsupported; perform no GitRef source I/O when that source is selected. Existing Git data remains untouched. Notion remains an optional mapping and exact legacy continuation path under its original authorization.

The source is responsible for its own authorization and for refusing a conflict or uncertain write. Caller-supplied Task Key, Branch ID, Fork ID, Actor, and Handoff content do not authorize access. Do not save secrets or credentials, migrate or delete existing records, or claim data moved. If a source result is unavailable or uncertain, retain the exact pending operation, explain what remains unverified, and continue independent safe work.
