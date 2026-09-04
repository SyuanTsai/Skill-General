<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Memory operations

Use these rules for Notion memory recall and capture. Read the machine-readable contract first for exact data-source and property names.

## Recall relevant memory

1. Form a narrow query from the task topic, project or personal scope, stable identifiers, and likely memory type.
2. Search `AI Memory` for `Status = Active`. Prefer exact `Memory Key` matches, then match `Scope`, `Type`, topic, and `Storage Type`.
3. Read only the records needed to decide or act. Treat `Pending`, `Superseded`, and `Archived` records as history, not current truth, unless the task explicitly asks for history.
4. Reconcile conflicts against formal sources. When the task is tracked in Jira, Jira holds its formal requirements, progress, and results; Notion holds durable memory, Handoffs, candidates, and unresolved context. Otherwise use the task's actual formal source. Do not let cached ChatGPT or Codex memory override Notion.
5. For `Storage Type = Dropbox`, use the Notion summary and metadata first. Read the original Dropbox file only when the task needs it and connector permissions allow it.

Skip recall for a quick transient exchange when no stored context could plausibly change the answer. This avoids irrelevant searches while preserving implicit recall for substantive work.

## Capture confirmed memory

Capture only information likely to remain useful:

- confirmed personal background or preferences;
- decisions and their rationale;
- long-term plans, important numbers, and constraints;
- project state, safe next steps, or unresolved material questions;
- reusable knowledge; and
- metadata for a directly related large source file.

When the user explicitly asks to remember safe content, write it directly to `AI Memory` without asking again. Use:

- `Status = Active`;
- `Confidence = Confirmed`;
- `Storage Type = Notion` unless a large-file rule applies; and
- a stable `Memory Key` derived from durable scope, type, and subject identifiers rather than conversational wording.

Before creating a record, search the exact `Memory Key`:

- If the effective content is unchanged, do not duplicate it. Add a materially new source or verification detail only when useful.
- If new confirmed information replaces an old record, preserve the old record and mark it `Superseded`; keep the replacement `Active`.
- If the key is already used for a different subject, refine the key with a stable project or source identifier instead of overwriting the unrelated record.

Use Notion native creation and last-edited metadata for record chronology. Populate optional custom date fields only when they already exist and the operation does not require a schema change.

## Capture inferred candidates

Do not present an inference as confirmed memory. Put potentially useful unconfirmed content in `AI Inbox` with:

- `Status = Pending`;
- `Confidence = Inferred`;
- the evidence and source that support the inference; and
- a clear statement of what remains unconfirmed.

Do not use `Pending` as a Handoff lifecycle or work state. When missing information does not materially change the current task, continue with the smallest reasonable inference and keep the label. Ask the user only when the missing fact would change the result.

## Evaluate task completion

Before closing substantive work, review the result for durable decisions, changed constraints, current project state, verified numbers, reusable knowledge, and safe next steps. Capture only the durable delta. Ordinary dialogue, explanations already available from their source, and temporary command output are not memory.

## Route large files through Dropbox

A file is a Dropbox candidate when it is too large for the current Notion plan, is a large binary or archive, must retain its original format, or is a dataset, build artifact, media file, or extensive log.

1. Search Notion for an existing file record before accessing Dropbox.
2. Ask for confirmation before creating, replacing, moving, or deleting any Dropbox file, even if Notion memory capture itself is automatic.
3. After an authorized file write, create or update the Notion record with a summary, `Dropbox Path`, stable `Dropbox File ID`, size, content hash when available, source, and verification time.
4. Prefer path and stable file ID over a public shared link. Never make public sharing the only access route.
5. If the Notion index write fails, report the file as unindexed and do not claim the memory operation is complete.

This Skill's stable scope covers individual memory and Handoff operations plus indexed large-file routing. It must not bulk-process Notion, alter schema, reorganize Dropbox, or migrate existing Dropbox memory. Repository fixtures and validators never authorize live test writes by themselves.

## Reject unsafe memory

Never store passwords, API keys, verification codes, payment authorization data, unauthorized company or third-party secrets, or irrelevant transient conversation. Ask before a write that may contain sensitive information. Do not create an unindexed Dropbox file within the AI-memory scope.
