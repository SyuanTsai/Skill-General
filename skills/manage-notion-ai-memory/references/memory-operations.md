<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Memory operations

Read the memory contract first. Use the configured adopter's mappings and read [the index workflow](index-workflow.md) when the mode, index, destination mapping, or recovery path is involved.

## Recall relevant memory

Skip recall for a quick transient exchange when stored context could not change the answer. Otherwise, form a narrow query from the task topic, configured scope, stable identifiers, and likely memory type. Read only records needed to decide or act.

- **Structured mode:** Preserve the existing v3 data sources, properties, and mappings. Search the configured memory for `Status = Active`; prefer an exact `Memory Key`, then match `Scope`, `Type`, topic, and `Storage Type`. Do not create a schema or reinterpret a missing property.
- **Pages mode:** Prefer an exact `Memory Key`. If the configured memory destination exposes a narrow exact-key lookup, query that key and scope directly; otherwise locate it through the configured `Memory Index`. Use the index for bounded topic lookup and follow only verified target locators. A verified body locator supplied by the user or another trusted source can be read directly without first finding an index row. Never guess a locator from a title. Treat an imported record with an unmapped status as historical and unconfirmed.

Treat `Pending`, `Superseded`, `Archived`, and `historical-unconfirmed` entries as history, not current truth, unless the user asks for history. A confirmed recall needs an `Active` record, `Confirmed` confidence, matching scope, and a verified source. Reconcile mutable or conflicting facts against the formal source that governs them. For tracked work, Jira holds formal requirements, progress, and results; the configured memory stores durable context and candidates. Task Handoffs remain in `$manage-task-handoff`. Do not let cached ChatGPT or Codex memory override the configured memory.

For `Storage Type = Dropbox`, use the Notion body and metadata first. Read the original Dropbox file only when needed and when connector permissions allow it. An index locator is not a permission grant.

## Capture confirmed memory

Capture only durable and useful information: confirmed preferences or background, decisions and rationale, long-term plans and constraints, verified project state, reusable knowledge, or metadata for a directly related large source file.

An explicit request to remember safe content is the user's confirmation. Write it to the configured memory with `Status = Active` and `Confidence = Confirmed`. Use the mapped `Memory Key`, scope, content, and source fields. Prefer `Storage Type = Notion` unless the large-file rule applies. Follow [the index workflow](index-workflow.md) for same-key checks, body/index ordering, read-back, and recovery.

Before creating a record, check the exact `Memory Key` and scope:

Confirm absence with a bounded exact-key/scope lookup and read against the configured body destination relevant to this write. An INDEX miss only says that the navigation row is missing; it is not evidence that a body is absent. If the destination cannot establish same-key state, stop that affected write as unknown and continue independent work without scanning the full collection. If the same effective body is already present but unindexed, skip body creation and repair only its index when one is configured; a legacy mapping without an index must not imply synchronization.

- More than one pre-existing `Active` record for that key is an integrity conflict. Stop the affected write. The temporary two-`Active` state of a verified but incomplete replacement follows the recovery path in [the index workflow](index-workflow.md). `Superseded` and `Archived` records with the same key are expected history.
- If effective content is unchanged, do not create a duplicate. Preserve the verified body and repair a missing or stale index entry only through the index recovery procedure.
- If confirmed information replaces an old record, retain the old body as `Superseded` and create or update the current body as `Active`. If the key belongs to a different subject, choose a stable key that distinguishes scope or source; never overwrite the unrelated record.

For replacement order, follow [the index workflow](index-workflow.md): verify the new body before retiring the old one. A failed or ambiguous retirement keeps both bodies and leaves the operation incomplete.

Use Notion's native creation and last-edited metadata for chronology. Populate optional custom date fields only when they already exist and doing so does not change schema.

## Capture inferred candidates

Do not label an inference as confirmed. Save potentially useful unconfirmed content in the configured inbox as `Pending` with `Confidence = Inferred`, the supporting evidence and source, and an explicit description of what remains unconfirmed. Do not use `Pending` as a task Work State. If a missing fact would not materially change the task, continue with a modest inference and preserve its label; ask only when the answer would change the result.

## Review durable changes

Before closing substantive work, consider durable decisions, changed constraints, current project state, verified numbers, reusable knowledge, and safe next steps. Capture only the durable delta. Ordinary dialogue, facts readily available from their formal source, and temporary command output are not memory.

## Route large files through Dropbox

A file may belong in Dropbox when it exceeds the current Notion plan, is a large binary or archive, must retain its original format, or is a dataset, build artifact, media file, or extensive log.

1. Search the configured memory and index for an existing file record before accessing Dropbox.
2. Get explicit confirmation before creating, replacing, moving, or deleting any Dropbox file, even when memory capture itself was requested.
3. After an authorized file write, save a memory body with a summary, Dropbox path and stable file ID, size, content hash when available, source, and verification time.
4. Prefer the path and stable file ID over a public shared link. Never make public sharing the only access route.
5. If the Notion body saves but the index write fails, retain the body, report the file as unindexed, and use the index-only recovery procedure. Do not claim the operation is complete.

Repository fixtures and validators do not authorize live writes. Do not bulk-process memory, alter schema, reorganize Dropbox, or migrate existing Dropbox memory.

## Reject unsafe memory

Never store passwords, API keys, verification codes, payment authorization data, unauthorized company or third-party secrets, or irrelevant transient conversation. Ask before writing material that may be sensitive. Do not create an unindexed Dropbox file within the memory scope.
