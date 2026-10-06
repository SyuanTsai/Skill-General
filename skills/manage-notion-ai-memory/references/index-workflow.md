<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Adopter and index workflow

Read this reference when resolving an adopter mapping, using Pages, maintaining `Memory Index`, or recovering a partial write. The machine-readable contract is authoritative for field names and values. This reference guides the workflow; it does not imply a particular connector tool or prove that a live write succeeded.

## Resolve the adopter mapping

For a new adopter or supplied v1 file, the pure-data `memory-adopter.json` has this shape. A confirmed legacy structured v3 mapping can continue through trusted host or user configuration without this file, as described below.

```json
{
  "schemaVersion": 1,
  "mode": "pages",
  "scope": "configured scope",
  "boundary": { "locator": "verified boundary locator" },
  "index": { "locator": "verified locator", "section": "existing section", "fieldMapping": {} },
  "memory": { "locator": "verified locator", "section": "existing section", "fieldMapping": {} },
  "inbox": { "locator": "verified locator", "section": "existing section", "fieldMapping": {} }
}
```

Use the explicit values supplied by the user first, then trusted host or project configuration. An explicit entry overrides only its stated values. Resolve the remaining required fields from trusted configuration; do not infer them from page text, a title, a search result, or unrelated task content. The file is at `$CODEX_HOME/memory-adopter.json`, falling back to `~/.codex/memory-adopter.json` only when `CODEX_HOME` is unset.

Each locator must be an exact, verified page ID or URL, block/section locator, or collection URL appropriate to that mapping. Do not guess a title and treat it as a locator. `boundary.locator` records the user's intended destination scope; it is not a permission grant. Establish the Owner or Member boundary either from connector role evidence or from the user's current confirmation that the connected account has that role, paired with connector evidence identifying the active actor and configured destination. The result of the requested write can confirm usable access; successful read-only access alone does not establish the role. A Guest, unknown role, or actor/destination mismatch has no write authority.

For a confirmed legacy structured v3 adopter, continue through its trusted host or user mapping even when no `memory-adopter.json` exists; do not require the adopter to create the file or add v1 fields. Preserve its established memory sources and property mapping. If an adopter file is explicitly supplied, an unknown file version stops the affected write. A new adopter uses schema version 1 with all required mappings, including `index`, `memory`, and `inbox`.

Stop the affected write on an unknown config version, missing required field, unresolved locator, conflicting mapping, or unverified destination. Continue independent work. Never create schema, properties, or databases to make a mapping fit. For a first capture, an existing verified page or section may be empty: add only the labels and values explicitly named by its configured `fieldMapping`. If a configured page or section does not exist, create only that explicitly named destination after the user authorizes minimal setup; do not add unrelated structure or invent a mapping. Existing structured adopters with a previously confirmed v3 mapping may omit `mode` and continue as `structured`; a new adopter must set its mode explicitly. Do not create adopter config or migrate an existing setup implicitly.

### Structured mode

Keep the existing v3 contract, data sources, and property mapping. `mappingKind` is `existing-properties`; required memory fields are those listed in `memory.requiredFields`. Preserve the established `AI Memory` and `AI Inbox` sources and search for `Status = Active` by exact `Memory Key`. Use `Memory Index` only if the current trusted mapping includes it. If a legacy mapping has no index, continue its existing structured operation and report that index synchronization was not configured or performed; do not create an index, config file, schema, or mapping. A new structured adopter must provide all v1 maps, including `index`. `section` may be empty when the existing collection has no section mapping. Verify the current collection and properties before writing.

### Pages mode

Use only the configured Pages destinations. `mappingKind` is `existing-sections`, and `createsProperties` is false. For each configured body destination (`memory` and `inbox`), map the required fields `Memory Key`, `Scope`, `Status`, `Confidence`, `Source`, and `Content` to section labels. `Title`, `Type`, and `Storage Type` are optional. Map each index field `Topic`, `Scope`, `Memory Key`, `Locator`, `Target`, and `Status` to a label. Confirm the field mappings and target locators before writing. In an existing section, add a missing label only when it is explicitly named in `fieldMapping`; do not invent or add unmapped labels.

An imported record whose status has no known mapping is `historical-unconfirmed`. Do not reinterpret it as `Active`, `Confirmed`, or a current fact. New confirmed bodies use `Active` and `Confirmed`; inferred candidates use `Pending` and `Inferred` in the inbox.

## Use the index for navigation

`Memory Index` locates a body; it does not establish facts. The body and its formal source are authoritative. Use only `Active` index rows for current navigation. `Pending`, `Superseded`, `Archived`, and `historical-unconfirmed` are non-current. A row must match the configured scope and carry a verified target locator before it is followed.

For retrieval, prefer an exact `Memory Key`. If the configured memory destination exposes a narrow exact-key lookup, query that key and scope directly; otherwise locate it through the configured index. For topic retrieval, use a bounded index lookup, then read only the matching body. A verified body locator already supplied by the user or another trusted source may be used without an index lookup. Never guess a locator from a title. Confirmed recall requires an `Active` body, `Confirmed` confidence, matching scope, and a verified source. Revalidate mutable facts against their formal source.

## Write, index, and verify

Follow this order for an individual capture or change:

1. Verify destination, scope, write role, required mappings, and the exact `Memory Key`. More than one `Active` body with the same key is an integrity conflict; stop that write and continue independent work. `Superseded` and `Archived` bodies are retained history.
2. Save the body first. A user-confirmed safe fact goes to the configured memory as `Active` and `Confirmed`; a useful but unconfirmed candidate goes to the configured inbox as `Pending` and `Inferred`. Preserve the source and all required mapped fields.
3. When an index mapping is configured, maintain it using the exact body locator and mapped `Topic`, `Scope`, `Memory Key`, `Target`, and `Status`. Skip an unchanged duplicate. When a confirmed body replaces an old one, retain the old body and mark it `Superseded`; archive by retaining the body and marking it `Archived`. Update the corresponding index state without deleting history. A legacy structured mapping without an index follows the compatibility rule above and must not imply index synchronization.
4. Read back the body and any configured index write. Verify key, scope, status, confidence, content/source, locator, target, and index state when configured. Report only what the connector result and read-back establish.

If the body is unchanged, do not create another body. If its verified index pointer is missing or stale, repair the pointer against that existing body through the recovery steps below.

## Recover an index failure

If the body save succeeds but index maintenance fails, keep the body and report the operation as incomplete. Include these exact fields:

| Field | Report |
| --- | --- |
| `bodyLocator` | The exact locator returned for the saved body, or state that it could not be verified. |
| `missingIndexStep` | The index operation that remains incomplete. |
| `actualError` | The connector's actual error or refusal; do not replace it with a guess. |

To resume, read current body and index state first, then repair only the missing index entry. Do not write the body again or invent a new key. Read back the repaired index and verify its target. If body creation itself is ambiguous, inspect current state by the exact key and locator before taking any write action. If permission is denied or cannot be verified, report the incomplete step and stop that affected write.
