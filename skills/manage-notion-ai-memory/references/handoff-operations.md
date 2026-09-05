<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Handoff operations

Use a Handoff when work may lose context across time, tools, stages, environments, or conversations. About five minutes of elapsed work is a fallback for a missed risk signal, not the primary trigger.

## Identify the unique Handoff

1. Derive a stable `Task Key`. Prefer a formal external key such as `jira:ATL-42`; otherwise use the host task or conversation identifier. Do not use a mutable title by itself. If neither stable identifier is available, do not invent a key or create a Handoff; report that uniqueness cannot be established and continue only work that does not depend on durable handoff state.
2. Query `Context Handoffs` by exact `Task Key`.
3. If none exists, create one main Handoff. The AI supplies the four snapshot fields; do not delegate field authorship to the user.
4. If exactly one exists, reuse it. If its lifecycle is `Archived`, submit and integrate a `Lifecycle = Active` change before resuming.
5. If more than one exists, do not create a third or silently delete or merge records. Preserve them and report the integrity conflict.

The initial main Handoff contains:

- `Intent`: the task outcome, not a transcript;
- `Scope`: active clauses and retained superseded clauses;
- `Current`: one or more workstreams, the current focus, last successful check, and next safe action;
- `Source`: formal source locations plus mutable source state that must be revalidated;
- `Lifecycle = Active`;
- `Work State = Running`; and
- optional `Keep Active Until` when the task is intentionally waiting for a future date or external event.

The main and change data-source schemas are defined exactly in `notion-memory-contract.json`. Do not add a custom `Last Activity At`, custom timestamp, or `Revision` property.

## Encode scope, current state, and source

- Give each independent scope or rule clause a stable local label. Keep changed clauses with content state `Superseded` and add the replacement as `Active`; these are content states, not Handoff lifecycle states.
- Represent each `Current` workstream separately. Mark the focus, last verified checkpoint, and next safe action so a new session can resume without guessing.
- In `Source`, distinguish formal authority from mutable working state. When the task is tracked in Jira, Jira is authoritative for its formal requirements, progress, and results; otherwise record the task's actual formal source. Include repository URL, Git commit or revision, worktree, and divergence between the local checkout and its remote when those facts can change the safe resume point.
- A Git revision belongs inside `Source`; the prohibition on `Revision` applies to adding a custom Notion property or counter.
- On every resume, re-read formal sources and revalidate mutable state instead of trusting a stale snapshot.

## Submit field-level changes

After the main Handoff exists:

1. Reconstruct its effective state before proposing another change.
2. Compare the desired state with that effective state.
3. For each field that actually changed, create one record in `Context Handoff Changes` with `Handoff`, `Field`, `Value`, and `Merged = false`. Give the title field `Change` a concise task-key and field label.
4. Encode `Value` as JSON scalar text: a JSON string for rich-text and select values, an RFC 3339 string for `Keep Active Until`, or JSON `null` to clear that optional date. Do not store an untyped raw value.
5. Do not write unchanged fields and do not replace the entire main Handoff page.
6. Keep all change records after integration as an audit trail.

`Merged = false` means the change has not yet been included in a verified main snapshot. Set it to `true` only after the affected main field is verified. `Merged` is an integration acknowledgement, not a lifecycle state, ordering counter, deletion marker, or permission to discard the audit record.

## Reconstruct and merge the latest state

1. Read the one main Handoff and every related change with `Merged = false`.
2. For each change, compute its effective native time as the later of Notion `created_time` and `last_edited_time`.
3. Decode each `Value` according to the contract and its `Field`. Leave invalid or type-mismatched values unmerged and report them.
4. Sort valid changes from oldest to newest by effective native time and apply them over the main snapshot.
5. Apply changes to different fields independently. For repeated changes to the same field, the newest value wins; earlier values remain in the change history.
6. If same-field records have the exact same effective native time and the formal source cannot establish order, preserve both and leave them unmerged while reporting the collision. Do not invent a revision counter.
7. Capture a merge fingerprint containing the main record's native `last_edited_time` and, for every unmerged change, its ID, field, encoded value, and effective native time.
8. Immediately before updating the main record, re-read it and the complete `Merged = false` set. If the fingerprint changed, discard the stale reconstruction and restart from the latest snapshot.
9. Update only main fields whose reconstructed values differ from the stored main values.
10. Re-read the main record and unmerged changes before acknowledging integration. Verify the intended main field values and compare the unmerged-change portion of the pre-update fingerprint. The main `last_edited_time` is expected to change because of this write, so do not compare it with the pre-update timestamp at this stage. If an intended value does not match or the unmerged-change fingerprint changed, reconstruct and retry instead of marking any newly affected records merged.
11. Retry a concurrently changing merge at most twice. If it still changes, leave the affected records unmerged, report the concurrent mutation, and do not claim an atomic or completed merge.
12. Only after successful integration and verification, set the corresponding change records to `Merged = true`. If integration is partial, mark only records for verified fields; invalid values and unresolved collisions remain unmerged.

Archival may occur while unmerged records exist. When the task is accessed again, reactivate the original main Handoff and replay the still-unmerged changes.

## Keep status namespaces separate

| Namespace | Allowed values | Meaning |
| --- | --- | --- |
| Handoff lifecycle | `Active`, `Archived` | Whether the Handoff is live or retained after inactivity. |
| Work state | `Running`, `Awaiting Review`, `Interrupted`, `Blocked`, `Failed` | The execution condition of the task. |
| Memory or rule content | `Active`, `Superseded`, `Pending`, `Archived` | Whether a memory or clause is current, replaced, unconfirmed, or historical. |

Never use `Completed` or `Awaiting Input`. At implementation completion use `Awaiting Review`. For nonmaterial missing information continue with a labeled inference; ask only when the answer would materially change the result.

## Archive after native-time inactivity

Compute last activity as the maximum of:

- the main Handoff's native `last_edited_time`; and
- every related change record's native `created_time` and `last_edited_time`, including already merged records.

If more than seven days have elapsed with no material update, submit and integrate a `Lifecycle = Archived` change. Do not delete content and do not require other pending changes to be merged first. If `Keep Active Until` is later than the evaluation time, remain `Active` until that date. A home-host scheduler may enforce this rule, but the Skill must not create that scheduler or schema implicitly.

## Record interruption and completion

- On interruption, submit and integrate `Work State = Interrupted` plus a `Current` change with focus, last successful check, and the next safe action.
- Submit `Work State = Blocked` only when execution cannot progress safely; explain the blocker outside the Handoff as well.
- Submit `Work State = Failed` when the attempted task execution failed and preserve diagnostic context that is safe to retain.
- When implementation is ready for human review, submit `Work State = Awaiting Review`. Write only confirmed formal progress or results back to Jira when that Jira write is authorized.
