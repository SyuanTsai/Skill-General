<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Provenance and licensing boundary

- Repository: [Skill-General](https://github.com/SyuanTsai/Skill-General)
- Audited baseline: [`01ac760cff3e0722849e0705c7af44cfe19835ba`](https://github.com/SyuanTsai/Skill-General/tree/01ac760cff3e0722849e0705c7af44cfe19835ba)
- Review date: 2026-09-04

## Confirmed current-tree facts

The audited tree contains reusable Skills with agent metadata, references, fixtures, scripts, tests, catalog/version metadata, release documentation, and workflow configuration. A current-tree scan found no embedded credentials, tenant data, private operational configuration, or vendored third-party source code.

Datadog and Notion are present as integration interfaces, safe-use instructions, references, catalog metadata, and test fixtures. They are not bundled SDKs or copied third-party implementations. The confirmed repository-authored current-tree scope is covered by Apache-2.0.

## Source timeline

- Baseline tree/blob inventory: [GitHub tree at `01ac760cff3e0722849e0705c7af44cfe19835ba`](https://github.com/SyuanTsai/Skill-General/tree/01ac760cff3e0722849e0705c7af44cfe19835ba).
- Initial repository commit: [`50979e01`](https://github.com/SyuanTsai/Skill-General/commit/50979e01) on 2026-08-18, establishing the repository for the public Skill migration.
- Public Git history was reviewed and preserved; no history rewriting was performed.

## Public evidence boundary

This public document records only the facts needed to explain repository provenance and the licensing boundary. Additional audit material is intentionally kept outside this repository. Evidence that is unavailable or not suitable for publication is not inferred from repository metadata.

## Decision and limits

Decision: apply Apache-2.0 only to the confirmed repository-authored current-tree scope, preserve the historical timeline, and keep external services, user-supplied inputs, extracted material, and generated outputs subject to their own rights. Processing external material with a repository tool does not automatically relicense that material under Apache-2.0.

This document is a public evidence index, not a legal opinion. A new provenance review is required for unreviewed additions, bundled third-party material, or changes to the repository's input/output boundaries.
