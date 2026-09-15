<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Storage adapter contract

The adopting user chooses storage, a formal authority for each task type, and how the logical common record, branch records, and append-only events map to physical objects. Notion, Jira, GitHub, local files, or a database may be adapters; no one platform is a mandatory authority. The adopter also sets an inactivity period, activity-time representation, and conflict retry limit. This Skill does not create schemas or grant remote write permissions.

## Required capabilities

| Operation | Required behavior |
| --- | --- |
| `getCommon(Task Key)` | Exact-match lookup returning zero or one logical common record and a storage revision; duplicates are an integrity error. |
| `getBranch(Task Key, Branch ID)` | Exact-match lookup with task association, fork point and revision; duplicates or mismatched keys stop writes. |
| `listActiveBranches(Task Key)` | Read only the common record's indexed Active branches. A fresh conversation by itself does not call this operation. |
| `createIfAbsent` | Enforce one common record per key and one branch per Task Key + Branch ID using a uniqueness constraint or equivalent atomic check. |
| `updateIfRevision(expected revision, Operation ID, changed fields)` | Conditional update or ETag compare-and-swap; report a stale revision without overwriting another writer. Persist a stable operation ID so retrying uncertain results cannot double-write. |
| `appendEventIfAbsent(Operation ID)` | Store immutable event identity and provenance; repeated calls return the existing event. Event order and state transitions remain auditable. |
| `readback` | Re-read all intended record fields, association, revision and operation outcome before calling integration or archival successful. |
| `materialActivity` | Return latest semantic state change or explicit restore. Use native last-edit metadata only if reads/no-ops/maintenance do not advance it; otherwise maintain a custom field. |

An adapter without conditional mutation and operation-ID idempotency is not suitable for concurrent peer branches. Fail closed for Handoff writes; local independent work can continue. Do not silently downgrade to last-write-wins. A platform that cannot atomically commit common and branch changes must preserve the fixed selection sequence and a retryable per-record operation log. Branch creation followed by common index update also needs a retryable step: an unindexed branch remains discoverable by its exact Branch ID, is reported as partial, and cannot be considered fully available through Task Key-only lookup until its common index readback succeeds. Partial failure reports every committed, pending, and unverifiable action. A conditional conflict requires re-reading formal authority and the affected records before reapplying the Gate; do not blindly replay old candidate content.

## Mapping and identity

Required common fields are Task Key, Intent, Scope, Current, Source, Lifecycle, Work State. Required branch fields are Task Key, Branch ID, Fork Point, Current, Source, Lifecycle, Work State. Common may also store Active Branches, baselines, Conflict, Keep Active Until, and Last Activity At. Branch may store candidate conclusions, Branch Outcome, Keep Active Until and activity. Event fields and allowed states are in `task-handoff-contract.json`. Branch Outcome remains empty before a user decision; `Conflict` is a common marker, not Lifecycle.

Task Key is a unique stable identifier, not a title. Branch ID is stable host identity or a generated ID. Operation ID is stable for one logical mutation across retries, distinct from the record ID and branch ID. The storage revision is opaque and obtained fresh on every read. A source revision such as a Git commit belongs inside Source and is revalidated separately from storage revision. Record links must round-trip from branch to its one common Task Key.

If exact lookup or activity semantics cannot be implemented on the chosen platform, mark that adapter as unavailable and explain the missing capability. A legacy adapter may support exact read-only mapping while new writes use the v1 logical model; it does not run a bulk migration or scan all history. Never save credentials or unapproved sensitive material in any physical mapping.
