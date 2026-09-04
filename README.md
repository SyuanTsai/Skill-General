<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Skill-General

General-purpose Agent Skills source repository.

Stable source ID: `general`

This repository owns reusable engineering, observability, public-research, and Agent Skill quality-review workflows that are versioned independently from AI Instructions.

## License and contribution boundary

The Apache-2.0 license in [LICENSE](LICENSE) applies to the repository-authored Skill instructions, agent metadata, references, fixtures, scripts, tests, catalog/version metadata, documentation, and workflow configuration in this repository. It does not grant rights to Datadog, Notion, GitHub, or other external services; their product materials, tenant data, credentials, prompts, user inputs, and generated outputs remain outside this repository's license boundary.

Datadog and Notion appear here as integration interfaces and documentation/fixture contracts. This repository does not vendor their SDKs or other third-party source code. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [PROVENANCE.md](PROVENANCE.md) for the dependency and evidence record.

Contributors must have the right to submit their contribution. Unless a separate written agreement says otherwise, an intentional contribution to the repository-authored scope is submitted under Apache-2.0; preserve existing notices and identify material that is not your own.

## Repository layout

```text
.agents/skills/<skill-id>/
  SKILL.md
  agents/openai.yaml
  scripts/                # optional
  references/             # optional
  assets/                 # optional
catalog/
  skills-catalog.json
scripts/
  Test-SkillGeneral.ps1
tests/
```

The physical Skill source layout is always `.agents/skills/<skill-id>/**`. Profiles are metadata only and must not be represented as nested Skill directories.

## Skills

| Skill | Profile | Compatibility |
| --- | --- | --- |
| `plan-production-change` | `core` | Any platform |
| `verify-data-access-performance` | `core` | Any platform |
| `investigate-datadog-logs` | `observability` | Configured Datadog connector |
| `manage-notion-ai-memory` | `ai-memory` | Configured Notion connector |
| `review-agent-skills` | `skill-quality` | Any platform |

The `core` profile is the default profile and contains both core engineering Skills. The `ai-memory` and `skill-quality` profiles are opt-in. Retired stable IDs remain as catalog tombstones without source implementation or profile membership.

## Validate

Run repository structure and catalog validation:

```powershell
pwsh -NoProfile -File ./scripts/Test-SkillGeneral.ps1
```

Run regression tests when Pester is available:

```powershell
Invoke-Pester ./tests -CI
```

Also run:

```bash
git diff --check
```

## Versioning and release

Consumers should pin this repository by an immutable full commit SHA or by a release tag that resolves to a known SHA. Updating a consumer pin is an explicit operation; consumers should not automatically track `main`.

A release is acceptable only when repository validation passes and the selected commit contains a self-consistent catalog and Skill inventory.

## Rollback

Rollback is performed by restoring the previous known-good tag or full commit SHA in the consuming catalog/lock configuration. Do not overwrite customized or unmanaged target files during rollback.

## Adding or changing a Skill

1. Keep the stable Skill ID unless a deliberate rename lifecycle is being introduced.
2. Store the source under `.agents/skills/<skill-id>/**`.
3. Keep `SKILL.md` frontmatter `name` equal to the catalog Skill ID.
4. Keep `agents/openai.yaml` with the Skill.
5. Add scripts, references, assets, and Skill-specific tests when required.
6. Update `catalog/skills-catalog.json` compatibility/profile metadata.
7. Run repository validation, applicable tests, and `git diff --check` before release.

Cross-repository project tracking and rollout decisions are maintained outside this public source and do not change the repository contract.
