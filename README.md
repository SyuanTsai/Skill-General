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
| `operate-environment-authorized-sql` | Controlled Azure SQL workflows and v1 offline contracts; execution runtime remains separate |
| `review-agent-skills` | Agent Skill package review |

`manage-task-handoff` is platform-neutral: its core receives, validates and returns caller-supplied records and proposed field-change intents without selecting storage, calling a connector, or claiming durable persistence. For explicitly delegated source I/O, a clear current user choice takes precedence over an older setting; otherwise the caller reuses one unambiguous trusted host or project setting, and asks only when the destination or scope is unclear. Trusted caller or adopter configuration binds the target to its source. The selected source owns authorization, persistence, conditional updates and operation-ID idempotency, opaque revisions, conflict handling, merging, retries, and readback; a matching readback is source-reported evidence, while Core `Durable` remains false. Git-ref Handoff storage is retired and explicitly unsupported without source I/O or fallback; existing Git data remains untouched. The package retains exact legacy Notion read-only continuation under its original authorization. No provider or local backend is mandatory for core recording.

## Canonical validation

The protected PR/main workflow validates one clean immutable candidate with the authority pinned in `config/standard-v1.json`. Explicit setup acquires and freezes the approved skill-validator, skill-tools, and SkillSpector tools. One canonical source run then checks every active package with both validators, performs complete Static analysis without an LLM, runs the repository contract and full Pester suite, and verifies the candidate/run/authority/tool/report bindings before projecting the same result to all three required contexts.

For local source validation, first stage the reviewed PowerShell and Pester runtime and a clean checkout of the pinned authority, then explicitly prepare a fresh run-owned toolset and consume it:

```powershell
pwsh -NoProfile -File ./scripts/Validate.ps1 -AuthorityRepositoryRoot C:\path\to\pinned-authority -PrepareSourceTools -SourceToolsPath C:\short\t\source-tools.json -ArtifactsRoot C:\short\t
pwsh -NoProfile -File ./scripts/Validate.ps1 -AuthorityRepositoryRoot C:\path\to\pinned-authority -SourceValidation -SourceToolsPath C:\short\t\source-tools.json -ArtifactsRoot C:\short\artifacts -BaseCommit HEAD^
```

Ordinary `Run` remains a separate Core entry point. It accepts only approved authority tuples and verified runtime paths, rejects legacy resolver or development-harness arguments before tool resolution, and never downloads, installs, or falls back. Its two repository checks are the read-only source diagnostic and complete Pester suite. A Core `PASS` proves those checks; the source required contexts also require the complete real-tool evidence from `-SourceValidation`. Neither path grants release approval; reports retain `releaseEligible: false`.

Source tool setup is explicit and create-only. `-SourceValidation` requires a prepared toolset bound to the exact candidate, authority, runtime and run identity, rechecks its installed tool closure, and fails on missing tools, substituted output, incomplete package or Static coverage, parser errors, tool failure, timeout or cleanup failure. Setup and validation do not add a provider, consent, signer or private-key prerequisite to ordinary Core or Handoff.

The repository Pester check runs one unfiltered invocation over the full `tests` tree; it has no shard selector, so that single invocation is the complete `core-full` shard. Before returning success, the wrapper binds the actual PowerShell executable to its sibling `Modules/Pester/6.2.0` directory, verifies every locked payload path and hash before and after import/run, and rejects ambient or duplicate same-version modules. It compares every discovered case with the union of passed, failed, skipped, inconclusive, and not-run outcomes using the source-relative file, AST offset, and complete expanded case path. It also matches Pester containers to every candidate `*.Tests.ps1` file and records the immutable candidate tree digest. The run-owned sidecar retains the full case/container/shard inventory, tool closure identity, and terminal gate; the child binds its path and SHA-256 on stderr. The six-field stdout JSON remains the machine summary; missing, ambiguous, incomplete, or failed case evidence makes the child exit nonzero.

The Windows CI workflow verifies Microsoft's latest stable PowerShell ZIP and executable version. A separate run-owned setup fetches Pester 6.2.0 from the official PSGallery endpoint, records the observed archive hash without claiming an official published digest, verifies all 17 locked payloads, and stages them under that runtime. Source tool setup uses the approved central resolver with explicit Go and Node runtimes. The exact protected-base driver validates the exact head candidate with the pinned authority; baseline or unprepared drivers and Core-only candidate authorities fail closed. Raw tool receipts, commands, reports, cleanup results and complete Pester case inventory are uploaded before owned cleanup. All three required contexts depend on the single canonical job, including strict source report verification, evidence upload and successful cleanup.

Semantic preparation and continuation remain explicit through `PrepareSemantic` and `ResumeSemantic`. They retain the existing consent, evidence, resolver-receipt, and replay protections; passing a legacy resolver flag to ordinary `Run` no longer selects that path. A prepared plan's create-only consumption claim is derived from its full run identity under the run-owned root, not its filename. Plans created with the earlier per-plan claim path fail closed and must be explicitly prepared again; the consumer never rewrites an old plan in place.

`tests/OfflineSemanticConsumer.Tests.ps1` is a consumer-contract fixture: it uses a temporary copy of `Validate.ps1` with test-owned synthetic authority constants, a minimal local Git candidate, and prebuilt offline consent/evidence signed by an in-memory test key. Its callback runner validates the fixture bindings and signature without acquiring tools or making network calls. It verifies the consumer's inventory binding and replay claim, but it is not a real Semantic analyzer run and does not validate production authority trust anchors.

## Development and release flow

For an ordinary source change:

1. Commit the candidate, explicitly prepare source tools and run `scripts/Validate.ps1 -SourceValidation` locally with the pinned authority checkout.
2. Inspect the complete source report and obtain the required Windows CI contexts for the exact commit.
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
