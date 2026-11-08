<!--
SPDX-FileCopyrightText: 2026 SyuanTsai
SPDX-License-Identifier: Apache-2.0
-->
# Skill-General

## Overview

**What it is:** general-purpose Agent Skills for everyday backend engineering with AI coding agents. Which Skills each agent receives is defined centrally in [SyuanTsai-AI-Instructions](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions).

**Problem it solves:** turning recurring investigation and verification work into repeatable, reviewable workflows in which any write requires explicit authorization and credentials are never exposed.

**Key Skills**

| Skill | What it helps with |
| --- | --- |
| `investigate-datadog-logs` | Investigate Datadog error logs and APM traces through a configured connector, including correlated patterns and trends |
| `verify-data-access-performance` | Analyze and test query efficiency with repeated measurements, query counts and N+1 checks |
| `plan-production-change` | Create evidence-based implementation plans sized to risk, with TDD sequencing, rollout and rollback when required |
| `operate-environment-authorized-sql` | Prepare controlled Azure SQL requests (check results, analyze evidence, or update/delete explicitly requested scoped data) through a registered, environment-authorized CLI |
| `manage-task-handoff` | Create interruption-safe handoff records from caller-supplied task data; persistence depends on the adopter's configured storage |
| `manage-ai-memory` | Find, create, update and recall AI memory through the adopter's connected record and file targets |
| `review-agent-skills` | Review Agent Skill packages for routing, instruction quality, safety boundaries, testability and maintainability |

All Skills run on a Windows host.

**In practice:** an AI-assisted Datadog log and APM workflow built on these Skills has cut my production issue investigation time by at least half.

Installed and version-pinned through [SyuanTsai-AI-Instructions](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions).

## 概覽

**這是什麼：** 搭配 AI 程式開發代理使用的日常後端工程通用 Agent Skills；各 Agent 可使用哪些 Skills，統一由 [SyuanTsai-AI-Instructions](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions) 定義。

**解決什麼問題：** 把反覆出現的調查與驗證工作，整理成可重複、可審查的工作流程；任何寫入都需要明確授權，且不外露憑證。

**主要 Skills**

| Skill | 用途 |
| --- | --- |
| `investigate-datadog-logs` | 透過已設定的 Connector 調查 Datadog 錯誤日誌與 APM Trace，包含關聯模式與趨勢 |
| `verify-data-access-performance` | 以重複量測、查詢次數與 N+1 檢查，分析並測試查詢效率 |
| `plan-production-change` | 依證據撰寫與風險相稱的實作計畫，需要時包含 TDD 順序、上線與回滾 |
| `operate-environment-authorized-sql` | 透過已登錄、經環境授權的 CLI，準備受控的 Azure SQL 請求（檢查結果、分析證據，或更新／刪除明確指定範圍的資料） |
| `manage-task-handoff` | 依呼叫端提供的任務資料建立可中斷恢復的交接紀錄；是否持久保存取決於採用端設定的儲存位置 |
| `manage-ai-memory` | 透過採用端連接的紀錄與檔案目標，查詢、建立、更新與回想 AI 記憶 |
| `review-agent-skills` | 審查 Agent Skill 套件的路由、指令品質、安全邊界、可測試性與可維護性 |

所有 Skills 都在 Windows 主機上執行。

**實際效果：** 以這些 Skills 建立的 AI 輔助 Datadog 日誌與 APM 調查流程，讓我調查正式環境問題的時間至少減少一半。

透過 [SyuanTsai-AI-Instructions](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions) 安裝並鎖定版本。

---

General-purpose Agent Skills source repository and the first reference implementation of Agent Skill Repository Standard v1.

Stable source ID: `general`

Normative policy belongs only to [`SyuanTsai-AI-Instructions/docs/standards/`](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions/tree/main/docs/standards). This repository implements that policy; it does not redefine lifecycle, validation-tool, security, approval, profile, compatibility, dependency, or consumer-routing semantics.

For source maintenance and review, follow the [central Skill maintenance guidelines](https://github.com/SyuanTsai/SyuanTsai-AI-Instructions/blob/76cee33b5e9b91b8a21f362f2936078c74a68fb7/docs/skill-maintenance-guidelines.md) when deciding scope, supporting resources, dependencies, and replacement cleanup.

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
| `manage-ai-memory` | Durable record and file memory through adopter-selected connected targets |
| `manage-task-handoff` | Task Handoff records and peer branches (Windows-only local host) |
| `operate-environment-authorized-sql` | Controlled Azure SQL workflows and v1 offline contracts; execution runtime remains separate |
| `review-agent-skills` | Agent Skill package review |

Windows is the only supported host for local development, installation, execution, testing, and acceptance. Windows is also the only supported CI host. Operating systems used by external SaaS and remote services are outside this local-host restriction.

`manage-task-handoff` retains a provider/storage-neutral core: it receives, validates and returns caller-supplied records and proposed field-change intents without selecting storage, calling a connector, or claiming durable persistence. Provider/storage neutrality does not expand local host support beyond Windows. For explicitly delegated source I/O, a clear current user choice takes precedence over an older setting; otherwise the caller reuses one unambiguous trusted host or project setting, and asks only when the destination or scope is unclear. Trusted caller or adopter configuration binds the target to its source. The selected source owns authorization, persistence, conditional updates and operation-ID idempotency, opaque revisions, conflict handling, merging, retries, and readback; a matching readback is source-reported evidence, while Core `Durable` remains false. Git-ref Handoff storage is retired and explicitly unsupported without source I/O or fallback; existing Git data remains untouched. The package retains exact legacy Notion read-only continuation under its original authorization. No provider or local backend is mandatory for core recording.

## Canonical validation

The protected PR/main workflow validates one clean immutable candidate with the authority pinned in `config/standard-v1.json`. Explicit setup acquires and freezes the approved skill-validator, skill-tools, and SkillSpector tools. One canonical source run then checks every active package with both validators, performs complete Static analysis without an LLM, runs the repository contract and full Pester suite, and verifies the candidate/run/authority/tool/report bindings before projecting the same result to all three required contexts.

Run local development, installation, execution, testing, acceptance, and any local source-validation run on Windows. When a specific failure needs investigation, a complete local `-SourceValidation` run is available as an optional diagnostic. Use the exact verified PowerShell runtime with its staged Pester 6.2.0 module closure and a clean checkout of the authority pinned in `config/standard-v1.json`. The commands below prepare a fresh run-owned toolset and consume it for that diagnostic:

```powershell
$pwsh = 'C:\path\to\verified\powershell\pwsh.exe'
& $pwsh -NoProfile -File ./scripts/Validate.ps1 -AuthorityRepositoryRoot C:\path\to\pinned-authority -PrepareSourceTools -SourceToolsPath C:\short\t\source-tools.json -ArtifactsRoot C:\short\t
& $pwsh -NoProfile -File ./scripts/Validate.ps1 -AuthorityRepositoryRoot C:\path\to\pinned-authority -SourceValidation -SourceToolsPath C:\short\t\source-tools.json -ArtifactsRoot C:\short\artifacts -BaseCommit HEAD^
```

Ordinary `Run` remains a separate Core entry point. It accepts only approved authority tuples and verified runtime paths, rejects legacy resolver or development-harness arguments before tool resolution, and never downloads, installs, or falls back. Its two repository checks are the read-only source diagnostic and complete Pester suite. A Core `PASS` proves those checks; the source required contexts also require the complete real-tool evidence from `-SourceValidation`. Neither path grants release approval; reports retain `releaseEligible: false`.

Source tool setup is explicit and create-only. `-SourceValidation` requires a prepared toolset bound to the exact candidate, authority, runtime and run identity, rechecks its installed tool closure, and fails on missing tools, substituted output, incomplete package or Static coverage, parser errors, tool failure, timeout or cleanup failure. Setup and validation do not add a provider, consent, signer or private-key prerequisite to ordinary Core or Handoff.

The repository Pester check runs one unfiltered invocation over the full `tests` tree; it has no shard selector, so that single invocation is the complete `core-full` shard. Before returning success, the wrapper binds the actual PowerShell executable to its sibling `Modules/Pester/6.2.0` directory, verifies every locked payload path and hash before and after import/run, and rejects ambient or duplicate same-version modules. It compares every discovered case with the union of passed, failed, skipped, inconclusive, and not-run outcomes using the source-relative file, AST offset, and complete expanded case path. It also matches Pester containers to every candidate `*.Tests.ps1` file and records the immutable candidate tree digest. The run-owned sidecar retains the full case/container/shard inventory, tool closure identity, and terminal gate; the child binds its path and SHA-256 on stderr. The six-field stdout JSON remains the machine summary; missing, ambiguous, incomplete, or failed case evidence makes the child exit nonzero.

The Windows CI workflow verifies Microsoft's latest stable PowerShell ZIP and executable version. A separate run-owned setup fetches Pester 6.2.0 from the official PSGallery endpoint, records the observed archive hash without claiming an official published digest, verifies all 17 locked payloads, and stages them under that runtime. Source tool setup uses the approved central resolver with explicit Go and Node runtimes. The exact protected-base driver validates the exact head candidate with the pinned authority; baseline or unprepared drivers and Core-only candidate authorities fail closed. Raw tool receipts, commands, reports, cleanup results and complete Pester case inventory are uploaded before owned cleanup. All three required contexts depend on the single canonical job, including strict source report verification, evidence upload and successful cleanup.

Semantic preparation and continuation remain explicit through `PrepareSemantic` and `ResumeSemantic`. They retain the existing consent, evidence, resolver-receipt, and replay protections; passing a legacy resolver flag to ordinary `Run` no longer selects that path. A prepared plan's create-only consumption claim is derived from its full run identity under the run-owned root, not its filename. Plans created with the earlier per-plan claim path fail closed and must be explicitly prepared again; the consumer never rewrites an old plan in place.

`tests/OfflineSemanticConsumer.Tests.ps1` is a consumer-contract fixture: it uses a temporary copy of `Validate.ps1` with test-owned synthetic authority constants, a minimal local Git candidate, and prebuilt offline consent/evidence signed by an in-memory test key. Its callback runner validates the fixture bindings and signature without acquiring tools or making network calls. It verifies the consumer's inventory binding and replay claim, but it is not a real Semantic analyzer run and does not validate production authority trust anchors.

## Development and release flow

For an ordinary source change:

1. Review the exact diff and run local checks that directly exercise its changed behavior. Use complete local `-SourceValidation` only when it is needed to investigate a specific failure.
2. Commit the candidate and open a normal protected pull request. Windows CI runs the exact candidate through the complete canonical source validation and produces all three required contexts. Inspect the complete source report and evidence.
3. Follow the central Standard's separate review, approval, release, installation, and rollback requirements when those actions are requested.

Approval binds one immutable candidate commit; changing candidate bytes invalidates earlier approval and validation evidence. Core `PASS` does not grant Human Release Approval.

## Adding or changing a Skill

1. Keep the stable lowercase kebab-case Skill ID.
2. Add or update `skills/<skill-id>/SKILL.md` and `skills/<skill-id>/agents/openai.yaml`.
3. Add Skill-specific resources and domain regression tests when needed.
4. Update the ordinal `catalog/source.json` Skill inventory.
5. Follow the [Development and release flow](#development-and-release-flow), review the required evidence, and obtain Human Release Approval before release.

Do not add profiles, compatibility, dependency, lifecycle, consumer-routing, validation-tool, or security policy to this repository. Change shared policy through the normative authority and its authority regressions.

## Rollback and installation

Consumers select a Human-Approved immutable release or full commit, perform controlled acquisition, verify integrity, project it to the host-specific consumer location, and verify post-install bytes. Roll back by restoring the prior approved immutable release and its known integrity evidence; never silently repair a mismatch into unknown content.

An installation of the same approved immutable release does not require another release approval, although host permissions, credentials, or external writes retain their own authorization boundaries.
