<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Skill-General

General-purpose Agent Skills source repository and the first reference implementation of Agent Skill Repository Standard v1.

Stable source ID: `general`

Normative policy belongs only to [`SyuanTsai-AI-Instructions/docs/standards/`](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions/tree/main/docs/standards). This repository implements that policy; it does not redefine lifecycle, validation-tool, security, approval, profile, compatibility, dependency, or consumer-routing semantics.

## License and contribution boundary

The Apache-2.0 license in [LICENSE](LICENSE) applies to the repository-authored Skill instructions, agent metadata, references, fixtures, scripts, tests, catalog/source inventory, documentation, and workflow configuration in this repository. It does not grant rights to Datadog, Notion, GitHub, or other external services; their product materials, tenant data, credentials, prompts, user inputs, and generated outputs remain outside this repository's license boundary.

Datadog and Notion appear here as integration interfaces and documentation/fixture contracts. This repository does not vendor their SDKs or other third-party source code. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [PROVENANCE.md](PROVENANCE.md) for the dependency and evidence record.

Contributors must have the right to submit their contribution. Unless a separate written agreement says otherwise, an intentional contribution to the repository-authored scope is submitted under Apache-2.0; preserve existing notices and identify material that is not your own.

## Canonical source layout

```text
skills/<skill-id>/
  SKILL.md
  agents/openai.yaml
  scripts/                # optional
  references/             # optional
  assets/                 # optional
catalog/
  source.json
config/
  standard-v1.json
scripts/
  Validate.ps1
  component diagnostic
tests/
```

`catalog/source.json` is the strict schema v2 source inventory. Profiles, compatibility, cross-Skill dependencies, lifecycle tombstones, and consumer projection paths remain centrally owned and are intentionally absent from this source repository.

## Active Skills

| Skill | Purpose |
| --- | --- |
| `plan-production-change` | Evidence-based production change planning |
| `verify-data-access-performance` | Query-count and data-access performance verification |
| `investigate-datadog-logs` | Datadog log and APM investigation |
| `manage-notion-ai-memory` | Durable cross-task Notion memory |
| `manage-task-handoff` | Platform-neutral task Handoff and peer branches |
| `review-agent-skills` | Agent Skill package review |

`manage-task-handoff` is platform-neutral: its core receives, validates and returns caller-supplied records and proposed change intents without selecting storage or making external calls. The caller owns source acquisition, identity, storage and external processing. When the caller separately requests adapter I/O, a selected opaque target is bound by trusted adopter configuration; only that adapter validates its activation and capabilities before content reads or writes. Missing or unverified activation fails closed, and durability requires matching readback. The package retains exact legacy Notion read-only continuation; Git-ref remains an optional configured adapter. No provider or local backend is mandatory for core recording.

## Canonical validation

Run the single local/CI entry point against a clean immutable candidate commit with PowerShell 7, Pester 6, and a clean checkout of the authority commit pinned in `config/standard-v1.json`:

```powershell
pwsh -NoProfile -File ./scripts/Validate.ps1 -AuthorityRepositoryRoot C:\path\to\pinned-authority -BaseCommit HEAD^
```

Ordinary `Run` binds the exact authority Git commit and verified files, inventories only tracked regular files from the candidate commit, and invokes the central Core v2 runner. Its adapter declares two repository checks: the read-only source diagnostic and the complete Pester suite. The JSON report records candidate and authority revisions, check results, test counts, and cleanup status. A Core `PASS` is source validation evidence with `releaseEligible: false`.

The Windows CI workflow obtains Microsoft's latest stable PowerShell ZIP, verifies its published SHA-256 and executable version, installs Pester 6.2.0, and validates the exact PR head or main commit. The three required status contexts project the one canonical report result. The repository component diagnostic is used internally by the canonical validator.

Explicit advanced semantic and legacy development-harness requests remain available through `scripts/Validate.ps1`. They use their separately reviewed legacy authority pin and retain their existing consent and evidence requirements.

## Development and release flow

For an ordinary source change:

1. Commit the candidate and run `scripts/Validate.ps1` locally with the pinned authority checkout.
2. Inspect the Core report and obtain the required Windows CI contexts for the exact commit.
3. Follow the central Standard's separate review, approval, release, installation, and rollback requirements when those actions are requested.

Approval binds one immutable candidate commit; changing candidate bytes invalidates earlier approval and validation evidence. Core `PASS` does not grant Human Release Approval.

## Adding or changing a Skill

1. Keep the stable lowercase kebab-case Skill ID.
2. Add or update `skills/<skill-id>/SKILL.md` and `skills/<skill-id>/agents/openai.yaml`.
3. Add Skill-specific resources and domain regression tests when needed.
4. Update the ordinal `catalog/source.json` Skill inventory.
5. Commit the candidate, run `scripts/Validate.ps1`, review the emitted evidence, and obtain Human Release Approval before release.

Do not add profiles, compatibility, dependency, lifecycle, consumer-routing, validation-tool, or security policy to this repository. Change shared policy through the normative authority and its authority regressions.

## Rollback and installation

Consumers select a Human-Approved immutable release or full commit, perform controlled acquisition, verify integrity, project it to the host-specific consumer location, and verify post-install bytes. Roll back by restoring the prior approved immutable release and its known integrity evidence; never silently repair a mismatch into unknown content.

An installation of the same approved immutable release does not require another release approval, although host permissions, credentials, or external writes retain their own authorization boundaries.
