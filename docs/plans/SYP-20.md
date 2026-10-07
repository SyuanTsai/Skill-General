# SYP-20 第一階段實作計畫

## 1. 目標與範圍

依 Jira 2026-10-07-v2 完成 P0–P2：`operate-environment-authorized-sql` Skill、授權與 CLI v1 契約、必要離線驗證、來源固定與導入證據。這次不實作 Windows 服務、SQL parser、Entra 登入或資料庫操作；離線通過不代表安全 SQL 或實機隔離通過。

基準：Skill-General `96dd761fc73e555966be44a52ea10a4959a70c45`；中央 authority `d54ef2cc83a19fa58f62fdcc6fa290095355d03e`。現有來源為 `skills/<id>`，來源只更新 ordinal `catalog/source.json`；profiles、dependencies、consumer routing 與發布規則由中央維護。

## 2. 變更

- `skills/operate-environment-authorized-sql/SKILL.md` 和 `agents/openai.yaml`：任務路由、探索受信任固定 CLI、一次環境授權、登入恢復、結果處理和 P3–P5 依賴。
- `references/*.schema.json`：嚴格 v1 authorization/request/response，unknown fields、版本、Token/target/override injection、任務目的與寫入內容不符均拒絕。
- `scripts/Test-Contract.ps1`：只讀、無網路的契約診斷；輸出 contract-valid 和 databaseExecuted=false，絕不產生 SQL 執行授權。
- `references/workflow.md`、`sql-policy.md`、`installation.md`、`acceptance.md`：完整授權/登入流程、ScriptDom/依賴/資料條件強制要求、中央安裝與回復、後續實機驗收。
- `tests/EnvironmentAuthorizedSql.Tests.ps1` 和 fixtures：正向契約、未知/重複欄位、任務操作矩陣、raw write 拒絕、unknown commit 重試拒絕；後續 SQL/runtime 情境明標未執行。

## 3. 測試

採 Pester 單元測試 Red→Green：先測不存在的契約檢查器，確認真實失敗；完成最小 JSON Schema + 語意一致性檢查，再執行正負案例。SQL 拒絕案例是後續服務 acceptance specification，不能將 fixture 預期值算作實機 pass。

文件與 metadata 使用既有 repository diagnostic 和 canonical package validators。安全/安裝/資料恢復條件保留於正文和測試契約，不因工具尚未完成而降級。

## 4. 交付與驗證

完成 targeted Pester 和 repository diagnostic 後固定 clean candidate commit，使用 `scripts/Validate.ps1 -PrepareSourceTools`、`-SourceValidation`，保存原始 receipts/report/完整 Pester inventory。依中央標準進行 AI Review，Human Release Approval 綁定該 immutable candidate 後才能 publish/install。

以中央既有安裝入口及 manifest 驗證精確檔案集合/hash、冪等導入、移除/回復、customized/unmanaged 保留與 Agent discovery/load；不可另建競爭 installer 或修改個人 routing 規則。真實版本、命令、來源/authority revision 和未執行項保存至交付 evidence，回寫 Jira/Notion。

## 5. 風險與未完成依賴

P3–P5：受保護授權存放、Agent OS 身份隔離、管理/執行 IPC、SqlClient/ScriptDom、Entra/WAM、實際 DB session target/principal、交易/併發/trigger/級聯及 UNCERTAIN_COMMIT。工程初始限制僅為建議，必須由首次授權確定。公司 DB 禁止 MCP；不得提取既有登入快取、建立 DB 帳號/Role/GRANT/REVOKE、或修改 PRD。

模型：本 chat 原生 turn_context 已核對為 gpt-6.1-sol/xhigh，與本機設定一致。沒有代為切換模型或新增委派。

## 6. 完整來源回歸修正

- 目標與範圍：保留完整 canonical gates，讓新增的第七個 Skill 納入精確來源測試，並提供足夠的 Windows CI 整體執行時間。
- 證據與位置：精確候選 b4bc7adc 的全部 17 個測試檔共 290 案，286 passed、4 failed；其中 `tests/StandardV1Conformance.Tests.ps1` 的固定六個 Skill 清單缺少新 Skill。其餘為獨立 harness 路徑格式與兩個 5 秒假 Git child 啟動 timeout，另行保存並核對。前版 CI raw events 顯示每個 native package check 間隔約 5–6 分鐘；七個套件加 Static、repository checks 與 setup 有超出 `.github/workflows/validate.yml` 原 105 分鐘整體時限的風險。
- 變更：精確 inventory assertion 加入 SQL Skill，為該既有測試補 `UnitT05_` 與 Scenario/Purpose；canonical job 整體時限改為 180 分鐘。各工具 900 秒時限、完整套件／Static／Pester、severity、scope 與 integrity gate 保持。
- 驗證與 TDD：inventory 已有真實 Red；更新清單後在 clean 新候選跑全部 repository Pester 與 canonical SourceValidation。CI YAML 是 configuration-only，依 Testing 規則豁免新增 test-first 測試，以解析 YAML、核對唯一 job timeout 差異及真實 CI 結果驗證。獨立 harness 使用 Windows 正規化 authority 路徑；假 Git timeout 先於低負載環境以原測試核對，不先放寬時限。
- 風險與回復：新 commit 使舊候選的 approval/canonical 證據失效，重新固定來源、archive 與中央導入提案；舊原始結果保留。若需回復，回復本次 inventory/CI 設定 commit；不改 normative authority 或降低任何 release/install 要求。
