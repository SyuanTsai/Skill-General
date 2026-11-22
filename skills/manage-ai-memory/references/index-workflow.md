<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Target mapping and index workflow

The [memory contract](memory-contract.json) defines the states and fields. This reference covers target resolution, legacy format recognition, index navigation, and partial recovery. It does not select a connector or prove a live write.

## Resolve targets and mappings

Use an explicit user target first, then a trusted adopter binding, then the unique connected target suitable for the current purpose. Resolve record and file purposes separately. Two connected record targets with no explicit or trusted selection remain ambiguous; ask once before writing. A record target plus a file target is not ambiguous merely because both are connected. Do not ask again for provider or account identity, Owner or Member metadata, or already granted ordinary operation authority.

Use only verified source-returned page, record, section, collection, or file locators. Never turn a search title, page text, or guessed path into an adopter mapping. When the source requires field mapping, resolve it from explicit entries and trusted host or project configuration. Do not create a schema or configuration by inference. A supplied mapping with an unknown version, missing required field, or conflicting locator stops only the affected write.

For a new body, resolve a complete v5 rule from explicit entries or the adopter's optional top-level `writeRule`. A `per-ticket` rule requires `{ticketKey}` and may fall back only to one `per-topic` rule when no ticket key exists; the fallback must not use `{ticketKey}`, and `per-topic` requires `{topic}` or `{title}`. Every placeholder used by the selected primary or fallback template must resolve to a non-empty authoritative value; otherwise stop and ask with zero writes. `{title}` comes only from the authoritative tracker or user for tickets, or the topic display title for topics. Stop and ask rather than inventing a key or unresolved title. Index Locator conventions never decide placement. The selected parent must stay inside the configured boundary and must not be a Handoff location.

Established v3 structured adopters may keep their trusted mapping without a new file or mode field. Existing v4 adopters can use their structured or pages mappings, including a supplied adopter file at schema version 1. With no v5 rule, a trusted v3 structured mapping or a configured v4 `memory` area (with its `inbox` area) is the adopter's legacy write rule and keeps its legacy body and candidate behavior. With a v5 rule, that rule overrides legacy placement for every new body and Pending candidate; legacy locators remain usable for reads and existing-entry maintenance only. An invalid v5 rule never falls back. A primary or fallback parent outside the configured boundary or in Handoffs, or disagreement between explicit and trusted placement, stops the affected write and asks the user. Follow [legacy mappings](legacy-mappings.md) for runtime discovery and exact mapping requirements. Maintain an index only when configured.

## Navigate and verify

An index row contains Topic, Scope, Memory Key, Locator, Target, and Status when an index is configured. Locator and Target must identify the same verified body, with an actual section or block locator when needed. Index rows with Active status are candidates for current navigation; Pending, Superseded, Archived, or historical-unconfirmed rows remain non-current. Follow a locator only after matching scope and reading the body. The body and its formal source decide whether a claim is current and confirmed.

For exact-key recall or capture, query the body destination by Memory Key and Scope when possible. An index miss triggers a bounded body lookup; it never proves absence. A user-supplied verified body locator may bypass the index for reading. If the destination cannot prove absence or identify the body, stop the affected creation as unknown instead of scanning or inventing a new key.

## Write and recover

For a new or changed body, use this order:

1. Resolve target, authorization, exact key, scope, current body state, and, for a new body, its complete primary or fallback rule. Under the selected parent locator, look up the exact rendered ticket/topic page and create it only when absent; never derive placement from index Locator conventions.
2. Save the body or separate Pending candidate, then read it back through its verified entry locator. If the selected ticket or topic page already exists, append a separate entry without replacing its body or changing unrelated entries, and index only the new entry locator. Under v5, the candidate uses the same selected page as bodies and never a legacy inbox. If an Active body already exists for the same key and Scope, preserve the existing Active body and index row.
3. Promote a v5-placed candidate by updating that same entry, then read it back through its verified locator. Update its index row to Active only when readback shows Status Active, Confidence Confirmed, and the verified confirmation source; otherwise stop and report while leaving the index Pending. Do not create or move a copy. For a confirmed replacement of a different Active proposition, only after the new body is verified, retire the prior current body as Superseded. If retirement fails, preserve both and report an incomplete transition.
4. Maintain the index using the verified body's Status. For a newly created page, Locator and Target point to that page (and its section or block when needed), never another shared page. For a confirmed replacement, preserve the old pointer as Superseded and add or update the new pointer whose Status matches the verified body. A Pending pointer remains non-current. Read back the index result.

Content, source, status, and confidence must all be unchanged to skip the body write. Confirming a Pending proposition is a state change even when its wording is unchanged. Under v5, update and read back that same entry before changing its index Status; without v5, keep the legacy candidate workflow. An existing unindexed body needs only a verified index repair. If the body succeeds and the index fails, retain the body and locator, report the exact failed index step and error, and leave the operation incomplete. On resume, re-read the body and index, then repair only the missing index entry; never resave the body just to retry indexing.

If body creation has a refused or ambiguous result, check current state before any retry and keep the old body and index current. If a write times out, distinguish a known failure from an unknown outcome. Do not claim success, blindly resubmit, or retire the old body. The authoritative source owns concurrent writes, history, and conflict handling; this workflow only reports the state it verified.
