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
  Test-SkillGeneral.ps1
tests/
```

`catalog/source.json` is the strict schema v2 source inventory. Profiles, compatibility, cross-Skill dependencies, lifecycle tombstones, and consumer projection paths remain centrally owned and are intentionally absent from this source repository.

## Active Skills

| Skill | Purpose |
| --- | --- |
| `plan-production-change` | Evidence-based production change planning |
| `verify-data-access-performance` | Query-count and data-access performance verification |
| `investigate-datadog-logs` | Datadog log and APM investigation |
| `manage-notion-ai-memory` | Durable Notion memory and task Handoffs |
| `review-agent-skills` | Agent Skill package review |

## Canonical validation

Run the single local/CI entry point against a clean immutable candidate commit:

```powershell
pwsh -NoProfile -File ./scripts/Validate.ps1 -BaseCommit HEAD^
```

The validator imports the verified central gate at `docs/standards/validation-security-gate.json` from the pinned authority snapshot. Local, pre-push, and CI execution use this same entry point and the same pass/block semantics. It:

1. performs Controlled Acquisition and binds one clean immutable candidate;
2. performs Integrity Verification for the candidate, authority archive, and pinned authority files;
3. performs Package Validation with `skill-validator` before any SkillSpector scan;
4. runs SkillSpector Static against every source-inventory Skill;
5. runs Repository Tests, `skill-tools`, Pester, conformance, and domain regressions against the same inventory;
6. deterministically triggers fail-closed SkillSpector Semantic Scan for security-relevant Skill changes or static findings;
7. records the required AI Review and Human Approval boundaries before Publish / Install;
8. records Post-install Verification as required evidence after an approved install;
9. emits machine-readable authority, candidate, tool, inventory, security disposition, stage, deviation, and review-boundary evidence in a temporary artifacts directory.

The canonical security disposition is also central: scanner failure, incomplete analysis, unparsable results, unknown severity, Critical, and High block; Medium requires Human Review and blocks release/install until disposition; Low and Informational findings are recorded and tracked.

`scripts/Test-SkillGeneral.ps1` is a component diagnostic used by the canonical validator. It is not an alternative release gate.

## Development and release flow

The repository follows the Standard v1 ordering defined by the central gate:

```text
Controlled Acquisition
→ Integrity Verification
→ Package Validation
→ SkillSpector Static
→ Repository Tests
→ Conditional SkillSpector Semantic Scan
→ AI Review
→ Human Approval
→ Publish / Install
→ Post-install Verification
```

AI review cannot replace Human Release Approval. Approval binds one immutable candidate commit; changing candidate bytes invalidates earlier approval and validation evidence.

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
