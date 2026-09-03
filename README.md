# Skill-General

General-purpose Agent Skills source repository and the first reference implementation of Agent Skill Repository Standard v1.

Stable source ID: `general`

Normative policy belongs only to [`SyuanTsai-AI-Instructions/docs/standards/`](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions/tree/main/docs/standards). This repository implements that policy; it does not redefine lifecycle, validation-tool, security, approval, profile, compatibility, dependency, or consumer-routing semantics.

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

The validator:

1. verifies the configured immutable Standard v1 authority archive, commit, bundle SHA-256, and authority file inventory before executing authority-derived code;
2. resolves and freezes the complete latest-stable formal toolset through the verified central resolver;
3. runs SkillSpector Static Scan against every source-inventory Skill;
4. runs repository validation, `skill-validator`, and `skill-tools` against the exact same complete inventory;
5. imports the resolved Pester module and runs conformance, repository, and domain regressions;
6. deterministically triggers fail-closed SkillSpector Semantic Scan for security-relevant Skill changes or static findings;
7. emits machine-readable authority, candidate, tool, inventory, stage, deviation, and review-boundary evidence in a temporary artifacts directory.

`scripts/Test-SkillGeneral.ps1` is a component diagnostic used by the canonical validator. It is not an alternative release gate.

## Development and release flow

The repository follows the Standard v1 ordering:

```text
Controlled Candidate Acquisition
→ Integrity Verification
→ SkillSpector Static Security Scan
→ Repository Validation
→ Tests / Regression / Conformance
→ Conditional SkillSpector Semantic Scan
→ AI Review
→ Human Release Approval
→ Publish Approved Immutable Release
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
