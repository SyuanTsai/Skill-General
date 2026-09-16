<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Legacy Notion Handoff read-only mapping

Use only when the user explicitly asks to continue a unique exact legacy Task Key. The old `Context Handoffs` and `Context Handoff Changes` remain untouched; no new conversation scan, schema change, bulk migration, implicit reactivation, field write, Merged acknowledgement, or maintenance update occurs. This is a read-only view for source reconciliation, not a v1 concurrent storage adapter.

1. Before querying `Context Handoffs`, resolve the verified principal from trusted connector or host context and authorize the exact Task Key and read action against the adopter's configured legacy workspace/data-source scope mapping. If the policy denies access, is unavailable, or cannot map the old source to a scope, stop without issuing the query or exposing content. After authorization, query by exact Task Key. Zero matches means no legacy view; more than one is an integrity conflict. Authorize related-change lookup under the same legacy scope, then read all related unmerged changes for the sole matching main record.
2. For each change, compute effective native time as the later of `created_time` and `last_edited_time`. Decode JSON scalar Value according to [the legacy contract](legacy-notion-handoff-contract.json). Keep invalid or type-mismatched changes unresolved.
3. Apply valid changes oldest to newest, separately for each field. If same-field changes share exact effective native time and the formal source cannot establish order, preserve both as a collision rather than inventing a revision or last-write winner. Earlier values remain in history.
4. Produce a common view containing the effective Intent, Scope, Current, Source, Lifecycle, Work State and optional Keep Active Until. Treat all legacy contents as historical evidence until the adopter's formal sources and mutable working state have been revalidated. The old single main does not imply a primary peer branch.
5. New v1 writes require a separately verified logical common/branch/event mapping with conditional revision and operation-ID idempotency. If that mapping is absent, report that durable v1 writes were not completed. Leave old records to natural archival and do not spend effort maintaining them.
