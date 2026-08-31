# Skill-General

General-purpose Agent Skills source repository.

Stable source ID: `general`

This repository owns reusable engineering, observability, public-research, and Agent Skill quality-review workflows that are versioned independently from AI Instructions.

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
| `review-agent-skills` | `skill-quality` | Any platform |

The `core` profile is the default profile and contains both core engineering Skills. The `skill-quality` profile is opt-in. Retired stable IDs remain as catalog tombstones without source implementation or profile membership.

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

Migration work is tracked by Jira `SYP-84` and the broader Skills Catalog initiative.
