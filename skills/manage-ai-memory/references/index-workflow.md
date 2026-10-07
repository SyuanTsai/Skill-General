<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Target mapping and index workflow

The [memory contract](memory-contract.json) defines the states and fields. This reference covers target resolution, legacy format recognition, index navigation, and partial recovery. It does not select a connector or prove a live write.

## Resolve targets and mappings

Use an explicit user target first, then a trusted adopter binding, then the unique connected target suitable for the current purpose. Resolve record and file purposes separately. Two connected record targets with no explicit or trusted selection remain ambiguous; ask once before writing. A record target plus a file target is not ambiguous merely because both are connected. Do not ask again for provider or account identity, Owner or Member metadata, or already granted ordinary operation authority.

Use only verified source-returned page, record, section, collection, or file locators. Never turn a search title, page text, or guessed path into an adopter mapping. When the source requires field mapping, resolve it from explicit entries and trusted host or project configuration. Do not create a schema or configuration by inference. A supplied mapping with an unknown version, missing required field, or conflicting locator stops only the affected write.

Established v3 structured adopters may keep their trusted mapping without a new file or mode field. Existing v4 adopters can use their structured or pages mappings, including a supplied adopter file at schema version 1. Follow [legacy mappings](legacy-mappings.md) for the existing runtime file discovery and exact mapping requirements. Their existing fields and provider-specific data are read as historical format, not new universal requirements. An older structured mapping without an index keeps its existing operation; report that no index was configured or synchronized. A new target may use any supported record layout that can represent Memory Key, Scope, Content, Source, Status, and Confidence. Unknown formats stop the affected write.

## Navigate and verify

An index row contains Topic, Scope, Memory Key, Locator, Target, and Status when an index is configured. Locator and Target must identify the same verified body, with an actual section or block locator when needed. Index rows with Active status are candidates for current navigation; Pending, Superseded, Archived, or historical-unconfirmed rows remain non-current. Follow a locator only after matching scope and reading the body. The body and its formal source decide whether a claim is current and confirmed.

For exact-key recall or capture, query the body destination by Memory Key and Scope when possible. An index miss triggers a bounded body lookup; it never proves absence. A user-supplied verified body locator may bypass the index for reading. If the destination cannot prove absence or identify the body, stop the affected creation as unknown instead of scanning or inventing a new key.

## Write and recover

For a new or changed body, use this order:

1. Resolve target, authorization, exact key, scope, and current body state.
2. Save the body, then read it back through its verified locator.
3. For replacement, only after the new body is verified, retire the prior current body as Superseded. If retirement fails, preserve both and report an incomplete transition.
4. Maintain the index. Preserve the old pointer as Superseded and add or update the new Active pointer. Read back the index result.

Unchanged content skips the body write. An existing unindexed body needs only a verified index repair. If the body succeeds and the index fails, retain the body and locator, report the exact failed index step and error, and leave the operation incomplete. On resume, re-read the body and index, then repair only the missing index entry; never resave the body just to retry indexing.

If body creation has a refused or ambiguous result, check current state before any retry and keep the old body and index current. If a write times out, distinguish a known failure from an unknown outcome. Do not claim success, blindly resubmit, or retire the old body. The authoritative source owns concurrent writes, history, and conflict handling; this workflow only reports the state it verified.
