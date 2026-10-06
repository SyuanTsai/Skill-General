<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Optional Notion legacy continuation

Notion compatibility in this package covers an explicitly requested, exact-key, read-only continuation of legacy Handoff records. This reference does not define or implement a new v1 Notion write adapter. For new or updated Handoff state, the caller and its selected source own persistence, conflict handling, merge, retry, and readback; this package only validates supplied data and source-reported results.

The legacy `Context Handoffs` data source contains an older main record per Task Key, and `Context Handoff Changes` contains field changes with Merged flags. Before querying either source, resolve the principal from trusted connector or host context and authorize the exact Task Key under an adopter-defined legacy scope mapping. A caller-supplied key and workspace-wide connector credentials are not authorization. If the source is unmapped, unavailable, or denied, stop before querying or exposing content.

After the user explicitly requests that exact old key, read the single authorized main record and its complete related unmerged-change set. Replay them with [the legacy contract](legacy-notion-handoff-contract.json) and [read-only algorithm](legacy-notion-handoff-operations.md). Duplicates, invalid changes, or unstable reads remain integrity errors. Return a read-only legacy view and revalidate its formal source before treating it as current task state. A new conversation or similar topic does not enumerate or reactivate old records.

Leave legacy data and schemas untouched. Do not add properties, create databases, migrate records, write merged acknowledgements, or use this mapping as a fallback when another source is unavailable. No GitRef capability is implied by a Notion record or its `Source` field.
