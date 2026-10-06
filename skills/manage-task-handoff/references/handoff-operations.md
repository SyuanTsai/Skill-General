<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Handoff operations

Read [the machine-readable task contract](task-handoff-contract.json) first. `HandoffRecordCore.psm1` validates caller-supplied records and produces proposed state and field-change intents; it performs no source I/O. The caller and selected source own reads, writes, authorization, persistence, conditional updates and operation-ID idempotency, opaque revisions, conflict handling, merge policy, retry, and readback.

## Create or resume

1. Obtain the exact Authority Scope and stable Task Key from trusted caller context. A formal task identifier is preferred; otherwise use the origin host task identity. A fork inherits the parent's Task Key and receives its own host identity as Branch ID. Identifiers and Handoff content locate data but never authorize access.
2. The authorized caller loads the exact common record and, when needed, exact branch record. A duplicate, mismatched identity, or invalid parent association is an integrity failure; preserve the source records and report it without disclosing unauthorized content. A new conversation does not trigger a source scan or automatic resume.
3. Revalidate mutable facts against the formal task source. Preserve its revision as an opaque value supplied by that source. Do not parse it as a Git commit or substitute a revision from another source. A mismatch means the source must resolve its own conflict; the core does not compare-and-swap, merge, or retry the write.
4. For explicit continuation, keep the stable Operation ID for that continuation. Advance the selected branch's Continuation Generation before resumed work; an archived branch may be restored only for that exact Task Key and Branch ID. Keep other peer branches archived. The caller/source reports the operation result, and the core records it without independently verifying persistence.

## Checkpoint and integrate

Keep confirmed task intent and global scope in the common record. Keep candidate work, supporting evidence, applicability, and branch-specific next steps on their branch. Integrate a verified, traceable fact into common only when it does not change task direction. Candidate solutions, architecture choices, tradeoffs, authorization, or task-direction changes require the user's decision. Do not use last-write-wins for mutually exclusive evidence.

For a selected, combined, or rejected branch, bind the decision to the exact opaque source revision, branch identity, content, and Continuation Generation the user reviewed. If the supplied revision, content, generation, authorization, or formal facts change, stop using the old decision and ask for renewed confirmation when it would affect the outcome. The source owns how its own writes are serialized and how any conflict or merge is resolved.

When recording a partial, unknown, or mismatched operation result, retain its record identity, opaque cursor, single Operation ID, and pending-action details as source-reported state. Do not substitute a new ID or turn uncertainty into success. A later result can advance the saved action only when it matches that same record, cursor, and operation binding.

## Archive and resume pending source results

Use `Get-HandoffArchiveSelection` for the pure seven-day and state eligibility decision. It does not perform storage work. The caller explicitly delegates a fresh archive action to the configured source, which performs that action once and returns the existing versioned caller-result report. `Invoke-HandoffArchiveCycle` may consume a supplied `SourceResults` entry with the exact fields `Decision`, `Cursor`, `OperationId`, and `CallerResult`. The outer `OperationId` and `CallerResult.OperationId` both match the saved Pending envelope's `OperationId`; `Decision` and `Cursor` match the same record, opaque revision, generation, and outcome. Malformed, duplicate, unauthorized, or mismatched results remain pending and cannot promote completion. The cycle never replays the saved `ArchiveAction`.

The archive `Cursor` has exactly these eight case-sensitive fields in this order: `Kind`, `AuthorityScope`, `TaskKey`, `BranchId`, `Revision`, `ParentRevision`, `ContinuationGeneration`, `BranchOutcome`. `BranchOutcome` is null for a Common decision; for a Branch decision it is the existing validated value `Selected`, `Partially Selected`, or `Superseded`. The cursor binds that outcome, and the stable archive operation ID digest includes the full cursor. `Revision` and `ParentRevision` remain opaque source values.

A saved pending action with the pre-outcome-binding seven-field cursor is rejected as `invalid-pending-action` before any `SourceResults` are consumed or callback can run. Keep the original pending envelope and caller records unchanged; do not migrate or replay it. Any reconciliation is a separate caller-authorized, source-owned action.

The source may report `readback-matched` after its own matching readback. The archive cycle exposes completed source actions through `SourceReportedCompleted`; each item has `SourceReportedDurable=true`. Aggregate `SourceReportedDurable` is true only when every selected action completed and no action remains pending. Core `Durable` always remains false. This is caller-reported source evidence, not an independent Core read. Only `readback-matched` completes an archive action; `denied`, `unavailable`, `partial`, `unknown`, and `readback-mismatch` remain pending with their caller result and operation identity. If no source is configured, return a concrete unpersisted/pending result; a result-only resume may still consume a matching new source result.

Archiving changes Lifecycle only and never deletes Handoff content. A future `Keep Active Until`, invalid or future activity timestamp, incomplete inventory, active branch, or unsafe work state protects a record. Reads, new conversations, no-op updates, and archive-only changes do not refresh material activity. Common state remains protected while an Active branch exists. Record the exact next safe action and continue independent work while a source action is pending.

## Preserve interruption and legacy continuity

On interruption, record current focus, last successful check, changed external state, blocker or failure, any operation that must not be repeated blindly, and the next safe action. Keep `Interrupted`, `Blocked`, `Failed`, and `Awaiting Review` as work states; `Conflict` is a marker and not a lifecycle value.

Notion remains an optional mapping and exact legacy continuation path. Read or replay only the explicitly requested Task Key under its original authorization. The legacy replay is read-only; it does not bulk-migrate or automatically resume work in a new conversation. GitRef Handoff storage is retired and unsupported; see [the retirement note](git-ref-storage-adapter.md).
