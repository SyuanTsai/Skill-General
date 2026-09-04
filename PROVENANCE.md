<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Provenance and licensing boundary

- Repository: [Skill-General](https://github.com/SyuanTsai/Skill-General)
- Audited baseline: [`01ac760cff3e0722849e0705c7af44cfe19835ba`](https://github.com/SyuanTsai/Skill-General/tree/01ac760cff3e0722849e0705c7af44cfe19835ba)
- Review date: 2026-09-04

## Confirmed current-tree facts

The baseline contains five reusable Skills with agent metadata, references, fixtures, scripts, tests, catalog/version metadata, release documentation, and workflow configuration. A current-tree scan found no company Jira URL, private project key, internal schema, proprietary prompt corpus, credential, tenant data, or vendored Datadog/Notion/other third-party source code.

Datadog and Notion are present as integration interfaces, safe-use instructions, references, catalog metadata, and test fixtures. They are not bundled SDKs or copied third-party implementations. The confirmed repository-authored current-tree scope is covered by Apache-2.0.

## Evidence and source timeline

- Baseline tree/blob inventory: [GitHub tree at `01ac760cff3e0722849e0705c7af44cfe19835ba`](https://github.com/SyuanTsai/Skill-General/tree/01ac760cff3e0722849e0705c7af44cfe19835ba).
- Initial repository commit: [`50979e01`](https://github.com/SyuanTsai/Skill-General/commit/50979e01) on 2026-08-18, establishing the repository for the public Skill migration.
- Historical identity evidence: [`da3a953b`](https://github.com/SyuanTsai/Skill-General/commit/da3a953b9df4daf02f13652dd911898cfca1a713) on 2026-08-31, `feat: retire custom FELO skill`, whose author/committer metadata uses a company-domain email. This records Git identity at that commit; it is not, by itself, proof of ownership of every file or authorization to license every resource. Git history was preserved and not rewritten.

## Context and evidence index

Maintainer-provided context records that the work used a personal laptop, self-paid AI, and a private Jira project. Some historical commits show a company-domain email because of Git identity configuration. None of those facts alone establishes ownership or licensing authority for all content.

Evidence available to this audit:
- Current Git tree, blob inventory, and historical commit metadata: checked.
- Private Jira record and issue context: available to the task but intentionally not copied into this public repository; Jira evidence is linked from the private work record.
- AI usage and billing records, device records, and any raw private exports: not independently attached to this public repository; sensitive originals remain in their appropriate private location. Missing raw evidence is recorded rather than inferred.

## Git identity and credential isolation

The effective audited global Git identity is a personal-domain identity and the Skill-General remote is the public HTTPS origin `https://github.com/SyuanTsai/Skill-General.git). The authenticated GitHub connector identity matched the repository owner during this operation. The SSH configuration was checked without reading private-key material: the existing GitLab and GitHub host entries each point to a different present private/public key pair, with distinct public-key fingerprints not reproduced here.

A path-based Git `includeIf` separation rule was not present in the effective global configuration at audit time. A distinct company repository root, approved company Git identity, and company SSH host/key mapping were not available in this workspace, so complete private/company separation is not claimed. This is the remaining SYP-187 closure gap.

## Decision and limits

Decision: apply Apache-2.0 to the confirmed repository-authored current-tree scope, preserve the historical timeline, and do not infer ownership from device, AI payment, Jira tenancy, or email identity alone. External services and future user-supplied content retain their own rights. This document is a public evidence index, not a legal opinion; a new provenance review is required for unreviewed additions or when the missing company-isolation evidence becomes available.