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

The Skills are platform-neutral and target Windows, Linux, and macOS hosts. The pinned consumer gate validates the repository on all three platforms.

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

Skills 內容與平台無關，目標主機為 Windows、Linux 與 macOS。Pinned consumer gate 會在三個平台驗證 Repository。

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
  authority-pin.json
  consumer-gate.json
scripts/
  Invoke-PinnedAuthority.ps1
  Sync-SharedReferences.ps1
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
| `manage-ai-memory` | Durable record and file memory through adopter-selected connected targets |
| `manage-task-handoff` | Task Handoff records and peer branches |
| `operate-environment-authorized-sql` | Controlled Azure SQL workflows and v1 offline contracts; execution runtime remains separate |
| `review-agent-skills` | Agent Skill package review |

The Skill content targets Windows, Linux, and macOS hosts. The repository gate validates all three platforms. A Skill that depends on a platform-specific external tool documents that dependency and its scope in its own instructions or references; for example, the planned execution service behind `operate-environment-authorized-sql` currently has a peer identity design that requires Windows.

`manage-task-handoff` retains a provider/storage-neutral core: it receives, validates and returns caller-supplied records and proposed field-change intents without selecting storage, calling a connector, or claiming durable persistence. For explicitly delegated source I/O, a clear current user choice takes precedence over an older setting; otherwise the caller reuses one unambiguous trusted host or project setting, and asks only when the destination or scope is unclear. Trusted caller or adopter configuration binds the target to its source. The selected source owns authorization, persistence, conditional updates and operation-ID idempotency, opaque revisions, conflict handling, merging, retries, and readback; a matching readback is source-reported evidence, while Core `Durable` remains false. Git-ref Handoff storage is retired and explicitly unsupported without source I/O or fallback; existing Git data remains untouched. The package retains exact legacy Notion read-only continuation under its original authorization. No provider or local backend is mandatory for core recording.

## Canonical validation

The authority-published `consumer-gate` workflow validates the repository on `windows-latest`, `ubuntu-latest`, and `macos-latest` using the immutable authority commit in `config/authority-pin.json`. Routine authority upgrades change only that commit.

Repository-owned validation consists of `scripts/Test-SkillGeneral.ps1`, invoked against the read-only candidate snapshot, and the complete `tests/` tree under Pester 6.2.0. The copied bootstrap and workflows remain authority-published bytes.

## Development and release flow

For an ordinary source change:

1. Review the exact diff and run local checks that directly exercise its changed behavior. To investigate a gate failure, read the consumer-gate evidence artifacts for that run and run the affected repository-owned check (`scripts/Test-SkillGeneral.ps1 -ReadOnlySnapshot` or the relevant `tests/` file) directly.
2. Commit the candidate and open a normal protected pull request. The consumer gate runs the exact candidate on Windows, Linux and macOS and produces all three required contexts. Inspect the complete source report and evidence.
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
