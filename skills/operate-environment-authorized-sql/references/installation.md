<!-- SPDX-FileCopyrightText: 2026 SyuanTsai; SPDX-License-Identifier: Apache-2.0 -->
# Installation, update and rollback

This package is source inventory in Skill-General. Shared release/managed lifecycle/consumer projection remain governed by the exact authority pinned in `config/standard-v1.json`, including [the central Standard](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions/blob/d54ef2cc83a19fa58f62fdcc6fa290095355d03e/docs/standards/skill-repository-standard.md) and its managed lifecycle companion. Do not create a private installer, alternate release gate, custom profile or competing consumer rule inside this Skill.

## Before release

Use the repository's canonical `scripts/Validate.ps1` source path on a clean immutable candidate after explicit tool setup. Preserve real package validators, complete Static coverage, full repository Pester evidence and AI Review for that exact revision. Human Release Approval precedes publish/install. Core diagnostics alone cannot authorize release. Changing candidate bytes invalidates earlier evidence/approval.

## Approved installation

The central catalog owner includes this stable ID and immutable approved source commit, recomputes the lock/content hashes and applies the existing consumer reconciler to the explicit host target. Acquire/verify the source and exact per-file hash inventory before mutation. Keep provenance, transaction recovery evidence and the manifest bound to the same catalog/lock/candidate. Current user-scope consumer projection is `.agents/skills/<skill-id>/`; host-specific discovery must be verified using the target's installed runtime documentation. Do not confuse repository-local ignored bootstrap artifacts with canonical `skills/` source.

For the actual installed central runtime, inspect its current command help/README and its catalog/lock version first, then construct precise plan/apply and selection arguments from that evidence. This package intentionally does not freeze an unrelated central CLI version or hard-code a prior computer path. The exact approved command and output must accompany adoption evidence.

Verify the target's full relative file set, regular/non-reparse file types, raw SHA-256 values and version/manifest binding. Verify Agent metadata discovery and actual loading of SKILL.md and a linked reference, then exercise the offline helper on synthetic files. Report those as Skill/contract evidence. They prove no database authentication or runtime enforcement. Repeating the same approved release should leave the same inventory/bytes; release approval need not be repeated per installation.

## Removal and recovery

Removal uses the central reconciler's exact managed inventory. Preserve unknown/private files and customized or unmanaged Skills; collisions, drift, unsafe paths or integrity mismatches stop the affected mutation. Never sweep the entire Skill directory based only on its name. Verify every removed managed path and retained unrelated path, and retain the audit/recovery record.

Rollback selects the previous approved immutable source and known integrity evidence through the same central lifecycle. Stage and verify bytes before replacing proven managed paths, recheck post-install inventory and preserve concurrent personal changes. Failed mutation enters verified transaction rollback/recovery. A first installation may be removed using its manifest, but it has no invented previous release. Service deployment, registry/token/ACL changes and business data restoration are separate P3–P5 operations.
