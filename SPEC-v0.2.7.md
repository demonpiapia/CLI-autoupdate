# CLI 自动升级 —— 项目规格 SPEC v0.2.7

> **版本**：SPEC-v0.2.7（2026-09-16）。
> **变更摘要（v0.2.6 → v0.2.7）**：架构不动。据 GPT frozen-direction 评审（v0.2.6）复核后修订，朝冻结候选收敛——
> **P0-1 采纳**：GitHub Releases API asset digest（`sha256:<64hex>`）作 opencode 完整性主路径 MUST（gh api 实测 `anomalyco/opencode` v1.18.31 全 37 asset 带 digest，验证通过；web 源确认 GitHub 2025-06-03 起 Releases 暴露 upload-time 计算、immutable 的 SHA256 digest [cite:472d3952-4]，旧 release digest 可能为 null [cite:472d3952-2]）；digest 缺失回退 checksum asset MUST；二者皆无→双 hash SHOULD。remote.json schema 加 `expectedSha256`（从 digest 剥 `sha256:` 前缀取 64hex），**保留 `checksumAssetUrl` 作 fallback 路径**（驳回 GPT"删除 checksumAssetUrl"——旧 release digest 可能为 null，fallback 仍需它；digest 比 checksum asset 更可信：digest 由 GitHub upload 时算且 immutable，checksum asset 是发布者上传、可连同 zip 一起被替换）。
> **P0-2 部分采纳**：§14-1/6 已实测闭合（tag=v1.18.31、assetName=opencode-windows-x64.zip、37 asset 全有 digest、prerelease=false）；§14-5 N=10 定死；§14-2/3/4/7/8/9 真未知风险**不伪关闭**（驳回 GPT"全部关闭§14"为过度——反代可靠性/PID 沙箱陈锁判定/时钟回拨极端需实现期实测，伪声明 closed 反误导），改为"已知风险声明，验收口径已定"。
> **P0-3 采纳**：verify 失败 MUST NOT 写新鲜 runId 的 verified.json（防 sync 误判新鲜度）；upgrade 非升级分支不写 upgrade.json（已写，验收强化为 MUST 断言）。
> **P1-4 采纳**：marker→exitCode→file 副作用表（§8.x）。
> **P1-5 采纳**：Canonical Path 代码块（§4，低成本保险），维持"插空是渲染误读"（spec 实际路径无空格，已验证）。
> **Checklist A-N 采纳为独立交付物** `cli-autoupdate-acceptance-checklist.md`（§15 引用，不塞进 spec 主体，守 Plan/契约层定位）。
> **角色定位**：本文件是 **Plan / 契约**（治理路线图 Approved Plan 位）。契约层为硬约束；PowerShell 实现属 Executor 有界自治。
> **关键词约定（RFC2119）**：**MUST / 必须** = 绝对硬约束；**SHOULD / 应** = 强烈推荐（可偏离须记录）；**MAY / 可** = 可选。契约层陈述默认为 MUST。

---

## 0. 项目定位、范围与交付物

本项目是 **monitor + download + CLI 全局维护** 整体过程：从"探测是否有新版本"到"实际升级、切换、对外暴露统一入口"的完整闭环。

**运行形态**：Cherry Studio 定时任务驱动、agent 编排、PowerShell 7 模块化的**个人维护流程**，维护对象是三个固定 CLI（claude/codex/opencode）。**不是**通用 CLI 自动更新软件产品——无 config.json、无 `cli update` 命令、仅 Windows、不面向外部发行/不提供贡献指南；不做 RSA 签名验证（完整性策略见 §5.2，威胁模型见 §5.10）。

**关于 LICENSE（修正事实矛盾）**：仓库根含 `LICENSE`（AGPL-3.0），系 initial commit 随归档 legacy 脚本（`.old/`）带入，**适用于 `.old/` 下历史代码**。本项目主体（SPEC + SOP + `*-v0.2.7.ps1` 新脚本）不面向外部发行、无贡献指南、不发布包；AGPL-3.0 不改变本流程的"个人维护"性质。

参照系（批判借鉴设计哲学，不照搬形态）：
- `Software_Update_Monitor_Spec_v0.2.2`（monitor-only）——本项目是其 Executor 下游延伸。
- `cherry-auto-apps-Release-Monitor`（已上线）——借鉴段内一气呵成、数据固化、运行锁、stdout 标记协议、原子写入、agent 不介入计算。不照搬合并脚本形态。

**交付物三层**：
1. **SPEC**（本文件）——设计契约。
2. **执行 SOP**（`cli-autoupdate-sop.md`）——给定时任务执行 agent 逐字读；agent 只读 SOP。**当前状态：待产出**（SPEC 评审通过后产出）。
3. **脚本**（`*-v0.2.7.ps1`）——模块化实现。**当前状态：待产出**（评审通过后产出，穿插 re-probe）。

> 仓库当前仅含 SPEC 系列文档 + `.old/` 归档 legacy 脚本 + LICENSE；SOP 与新脚本尚未产出，属评审阶段正常状态，非交付物定义矛盾。

---

## 1. 设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | 模块化 | 每 CLI 拆 probe-local / probe-remote / upgrade / verify。共享 sync 单脚本。 |
| 2 | 数据固化 | 每步结果落 `state/*.json`；下一步读上一步文件。状态走文件，不走 agent 记忆。 |
| 3 | 流程化 | 定时 agent = 执行固定状态机 + 读标记判分支 + 报告。不写脚本、不手算版本。 |
| 4 | 晋升闸 | sync 只消费通过**三重约束**的凭证（本轮新鲜 + 完整性通过 + pin 未冲突）。任一不满足，D 盘原封不动。 |
| 5 | fail-closed（分层） | **fatal 类** → MUST 终止整轮。**recoverable 类** → 标记后继续下一个 CLI。 |
| 6 | 原子写入 | 临时文件 → 回读校验 → Move-Item 原子替换；同卷原子，跨卷先 Copy 到目标卷临时文件再同卷 Move。 |
| 7 | 运行锁 | 运行锁互斥。ownership 靠 runId（不靠 PID），PID 仅作陈锁死亡判据。 |
| 8 | 可追溯 + 二进制证据链 | 每轮归档；fetch_run.log 累积；spec/脚本/json 带 specVersion；sync.json.entries 携 sha256 证据链（§5.5）。 |
| 9 | 隔离 | staging 与 promotion 物理分离。 |
| 10 | 机器事实/叙事分层 | `state/*.json` 机器事实，agent 只读不写；agent 可写汇报叙事层。 |
| 11 | 凭证新鲜度（双判据） | 新鲜度 = `runId 与 current-run.runId 匹配`（主判据）**或** `runAt ≥ startAt`（兜底）。防时钟回拨。 |
| 12 | 供应链完整性 | opencode 下载后 MUST 计算 sha256；**GitHub Releases API asset digest（`sha256:<64hex>`）为主路径 MUST**（digest 由 GitHub upload 时算、immutable，优于发布者上传的 checksum asset）；digest 不可用 → checksum asset MUST 校验；二者皆无 → SHOULD 双 hash 比对。mise 通道完整性由 mise 自身保证。 |
| 13 | 异常隔离 | sync 内每 CLI 的 copy 逻辑 MUST 独立捕获异常，单 CLI 失败不得向上冒泡终止整轮（§7.2）。 |

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging** | claude/codex：`E:\...\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\`；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证落点 | upgrade 脚本（运行锁内） |
| **Promotion** | `D:\AI\Programs\CLI\<name>\<name>.exe` | 全局唯一"正确版本"；last-known-good 回退源 | **仅 sync，且仅通过三重约束的 CLI，运行锁内** |

所有 harness 固定调用 `D:\AI\Programs\CLI\<name>\<name>.exe`，不依赖 mise shim / `MISE_*` / PATH。

---

## 3. 统一入口布局

```
D:\AI\Programs\CLI\claude\claude.exe
D:\AI\Programs\CLI\codex\codex.exe
D:\AI\Programs\CLI\opencode\opencode.exe
```

> 实机现状（2026-09-16 核验）：D 盘此前曾缺 `claude\` 子目录，系手动建立时遗漏，现已补全。这正是 F1 凭证生命周期缺口的现实佐证——UPTODATE 不产凭证则永不 seed，需由 §7.3 `UPTODATE_REFRESH` 兜底。

---

## 4. 目录与状态文件布局

```
D:\AI\Workspace\automatic\CLI-autoupdate\
├── SPEC-v0.2.7.md                    # 本文件（契约）
├── cli-autoupdate-sop.md             # 执行 SOP（给定时 agent，待产出）
├── cli-common-v0.2.7.ps1             # 共享库
├── probe-local-<cli>.ps1             # 每 CLI 一份（3 份）
├── probe-remote-<cli>.ps1            # 每 CLI 一份（3 份）
├── upgrade-<cli>.ps1                 # 每 CLI 一份（3 份）；behind 判定 + zip 安全解压
├── verify-<cli>.ps1                  # 每 CLI 一份（3 份）；装后功能测试 + sha256
├── sync-v0.2.7.ps1                   # 共享单脚本；每 CLI copy 独立 try/catch
├── archive-state.ps1                 # 每轮首步：争锁+归档+生成 runId
├── state\                            # 固定路径，最新覆盖
│   ├── current-run.json              # runId + startAt
│   ├── <cli>-local.json
│   ├── <cli>-remote.json
│   ├── <cli>-upgrade.json
│   ├── <cli>-verified.json           # 含 runId（新鲜度主判据）
│   ├── sync.json
│   ├── run.lock
│   ├── fetch_run.log
│   ├── <cli>.pin                     # 可选：锁定目标版本
│   └── archive\<时间戳>\             # 每轮归档，保留最近 30 轮（§10.4）
├── staging\opencode\<ver>\           # opencode 解压落点（ZipSlip 约束 §7.2）
└── TEMP\                             # 交付前必空
```

> **斜杠约定澄清（回应 GPT 4.3）**：spec/示例中 Windows 路径用反斜杠 `\`（Windows 原生、json 内转义）；agent 在 pwsh 命令行调 `-File` 时用正斜杠 `/`（避免 MSYS 路径转换与反斜杠转义问题，见 §9 铁律 3）。两作用域不同，不矛盾。

> **Canonical Path（回应 GPT P1-5"路径展示插空消歧义"）**：GPT 称示例路径现"插空"（如 `D:\A I\P rograms\C LI`）系其渲染/OCR 误读——本 spec 实际路径**无空格**（已逐字核对）。仍补此代码块作低成本保险，供 agent 逐字复制，杜绝歧义：
> ```
> D:\AI\Programs\CLI\claude\claude.exe
> D:\AI\Programs\CLI\codex\codex.exe
> D:\AI\Programs\CLI\opencode\opencode.exe
> D:\AI\Workspace\automatic\CLI-autoupdate\state\
> D:\AI\Workspace\automatic\CLI-autoupdate\staging\opencode\
> ```
> 三个权威入口路径无空格、无大小写歧义；agent 调 `-File` 时改用正斜杠（如 `D:/AI/Programs/CLI/claude/claude.exe`）。

**陈旧数据风险**：`<cli>-remote.json` 在 REMOTE_FAIL 时写 `{latest:null, error:<cause>}`；`<cli>-upgrade.json` 仅实际升级时写，读取前 MUST 校验 `runAt` 是否本轮。

---

## 5. 数据契约（state/*.json）

**时间字段规则（回应 GPT 4.1）**：除 `current-run.json`（用 `startAt`，表示本轮起点）与 `*.pin`（用 `setAt`，表示 pin 设置时间）外，其余 state JSON（local/remote/upgrade/verified/sync）MUST 带 `runAt`（ISO UTC，表示该文件产出时间）。`runId`：`current-run.json`/`verified.json`/`sync.json` MUST 带；`local.json`/`remote.json`/`upgrade.json` SHOULD 带（关联本轮，防同分钟多轮混读）。

所有 JSON 顶层带 `specVersion`（`"0.2.7"`）、`name`。时间内部 UTC，展示 UTC+08:00。**完整字段级 schema 见 §5.9（与示例一一对应）**。

**更新源固定清单**：
- claude/codex：mise registry（mise 自身校验包完整性）。
- opencode：`anomalyco/opencode` GitHub releases（固定 repo；反代 `https://gh.jasonzeng.dev/`，回退直连，时序 §5.2）。
- **GitHub API 认证**：probe-remote 调 GitHub API SHOULD 用认证 token 提额（未认证 60 次/小时/IP，认证 5000 次/小时）。本环境 `gh` 已认证（demonpiapia 账户）。token MAY 从 `gh auth token` 读取或环境变量注入，**MUST NOT 写入状态文件/日志/推送平台**。
- 超时：mise ls-remote 60s、upgrade 600s、exe --version 30s（§7.1）。
- 日志：`state/fetch_run.log`。
- "自动更新开关" = 定时任务本身。

### 5.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.2.7", "name":"codex", "channel":"mise", "runAt":"...", "runId":"<SHOULD>",
  "version":"0.154.0", "exePath":"...", "bytes":298169136, "mtime":"...",
  "sha256":"<mise SHOULD 计算；opencode 必填>",
  "healthy":true, "healthDetail":"ok", "error":null }
```
- `healthy`：exe > 1MB 且 `--version` 可启动。
- `healthDetail`：`ok` / `broken`（<1MB / stub / 文件缺失） / `probe-error`（`--version` 偶发超时或非零退出）。`broken` → REPAIR；`probe-error` → `PROBE_ERROR|` 不强制重装。
- `sha256`：SHOULD 计算（opencode 必填；mise SHOULD 计算以支撑 §5.5 证据链）。
- opencode staging 空 → `version=null, exePath=null, healthy=false, healthDetail=broken`。

### 5.2 `<name>-remote.json`（probe-remote 产出）+ 下载完整性策略
```json
{ "specVersion":"0.2.7", "name":"opencode", "channel":"github-binary", "runAt":"...", "runId":"<SHOULD>",
  "latest":"1.18.31", "sourceUrl":"https://gh.jasonzeng.dev/https://...",
  "directUrl":"https://github.com/anomalyco/opencode/releases/download/v1.18.31/opencode-windows-x64.zip",
  "assetName":"opencode-windows-x64.zip",
  "assetDigest":"sha256:0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006",
  "expectedSha256":"0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006",
  "checksumAssetUrl":"<或null>", "fallbackUsed":false, "error":null }
```
- **mise 通道**：`mise ls-remote <tool> --json` 最高 stable。
- **github-binary 通道**：`releases/latest` → tag_name（去 `v`）+ assets 筛 `windows-x64.zip` → 取 `asset.digest`（`sha256:<64hex>`）剥前缀写 `expectedSha256`；`sourceUrl`=加速地址、`directUrl`=直连地址、`assetDigest`=原始 digest、`checksumAssetUrl`=`*.sha256`/`checksums.txt`（digest 不可用时 fallback，存在则记录，null 则无）。
  - **回退**：`releases/latest` 失败 → `releases?per_page=10` 取最高 stable、prerelease=false；`fallbackUsed=true`。
  - **REMOTE_FAIL 落盘语义**：失败时仍写 remote.json，但 `latest:null, sourceUrl:null, directUrl:null, error:<cause>`。
  - **GitHub 限流区分**：遇 403 + `x-ratelimit-remaining: 0` → `RATE_LIMITED|<cli>`（区别于普通 REMOTE_FAIL）。
  - **下载完整性策略（v0.2.7 调整：API digest 主路径，回应 GPT P0-1）**：
    1. 下载 zip 后 MUST 校验大小 > 1MB（防半下载/stub）。
    2. **GitHub Releases API asset digest 存在**（`.assets[].digest`，格式 `sha256:<64hex>`）→ MUST 以 digest 为完整性主路径：剥 `sha256:` 前缀取 64hex 写入 `expectedSha256`，下载 zip 后计算 SHA256 与 `expectedSha256` 比对；不匹配 → `DOWNLOAD_FAIL|<cli> digest-mismatch`。digest 由 GitHub 在 asset upload 时计算、immutable（2025-06-03 起 Releases 暴露 [cite:472d3952-4]），比发布者上传的 checksum asset 更可信（checksum asset 可连同 zip 一起被替换）。digest 主路径**无需额外下载 checksum 文件**（digest 已在 releases API 响应内），省一跳。
    3. **digest 不可用**（旧 release digest=null，或 API 未返回）→ checksum asset 存在则 MUST 下载 checksum 并校验 SHA256；不匹配 → `DOWNLOAD_FAIL|<cli> checksum-mismatch`。
    4. **digest 与 checksum asset 均不可用** → SHOULD 双 hash 比对（反代+直连两份独立下载，SHA256 一致才接受）；不一致 → `DOWNLOAD_FAIL|<cli> dual-hash-mismatch`。MAY 偏离（直连不通时仅用反代 + `integrityNote:single-source`），须在 sync.json.entries 记录。
    5. 解压后对目标 exe MUST 计算 SHA256，写入 verified.json.sha256。
  - **API digest 解析规则（MUST）**：取 `releases/latest`（或回退 `releases?per_page=10`）响应 `.assets[]` 中按 `assetName` 精确匹配条目的 `digest` 字段；格式须为 `sha256:<64hex>`，剥 `sha256:` 前缀取 64hex 写入 `expectedSha256`；digest 为 null 或字段缺失 → 视为 digest 不可用，回退 checksum asset（策略 3）。已实测 `anomalyco/opencode` v1.18.31 全 37 asset 均带 digest（opencode-windows-x64.zip → sha256:0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006）。
  - **checksum 文件解析规则（MUST，回应 GPT 4.5）**：
    1. 支持 sha256sum 两格式：`<hash>  <filename>`（双空格）与 `<hash> *<filename>`（` *`，binary 模式标记）。
    2. 单文件 `*.sha256`（仅一行 hash 或 `hash  filename`）亦支持。
    3. 按 `assetName` **精确匹配**条目（大小写不敏感，仅比文件名，忽略路径前缀）；未找到匹配 → 视为无 checksum（fallback 到双 hash SHOULD）。
    4. 忽略空白行与 `#` 注释行；hash 必须为 64 位十六进制，否则视为无效条目跳过。
    5. 多匹配时取第一条（并在 fetch_run.log 记 warning）。
  - **直连回退时序**：加速 URL 失败 → 直连 GitHub 重试一次 → 仍失败 → `DOWNLOAD_FAIL|<cli> <cause>`。
  - **回退方向不对称说明（回应 GPT 4.3/8）**：普通下载失败走"反代→直连"（反代是主链路，加速优先）；双 hash 缺一方时允许"直连不通→仅反代+standalone 标注"（反代已是唯一可用源，方向反转是降级而非冲突）。两者场景不同、方向相反的合理性在于：前者"主链路失效切备用"，后者"备用不可达时兜底记录"。非矛盾。
  - **关于"自维护受控 manifest"（驳回 GPT#1 方案1）**：不采用。与"自动跟随 latest"矛盾（opencode 发版后无法自动获知官方 sha256，需人工维护 manifest）；manifest 受信任性回归原问题；checksum MUST + 双 hash SHOULD 已检出反代投毒且不引入人工步骤。
  - **已知坑（asset 名已实测闭合，回应 GPT P0-2）**：asset 名实测=`opencode-windows-x64.zip`、tag=v1.18.31、prerelease=false、全 asset 带 digest（§14-1 已闭合）；tag 列表接口曾现异常拼接，probe 仍需防御性处理。

### 5.3 `<name>-upgrade.json`（upgrade 产出，仅实际升级时写）
```json
{ "specVersion":"0.2.7", "name":"codex", "runAt":"...", "runId":"<SHOULD>",
  "fromVersion":"0.152.0", "target":"0.154.0", "exitCode":0, "ok":true,
  "sha256":"<opencode必填，mise SHOULD>", "error":null }
```
不升级分支不写不覆盖本文件。

### 5.4 `<name>-verified.json`（verify 产出；晋升凭证）
```json
{ "specVersion":"0.2.7", "name":"codex", "runAt":"...", "runId":"<本轮uuid, MUST>",
  "version":"0.154.0", "exePath":"...", "bytes":298169136,
  "sha256":"<opencode必填，mise SHOULD>",
  "healthy":true, "matchesTarget":true }
```
- **晋升三重约束**：① 新鲜度（`runId == current-run.runId` **或** `runAt ≥ current-run.startAt`）② 完整性（opencode sha256 非空且与下载校验值一致）③ pin 未冲突（§5.7）。
- `sha256`：verify 阶段 SHOULD 计算（opencode 必填，mise SHOULD——数据源与 §5.5 `sourceSha256` 对齐）。
- verify 即装后功能测试：跑 `exe --version` + 计算 sha256。
- **失败不覆盖（P0-3，回应 GPT）**：verify 失败（`VERIFY_FAIL`）MUST NOT 写新鲜 runId 的 verified.json——防 sync 误判新鲜度而用失败轮凭证覆盖旧有效凭证；失败仅输出标记 + 写 `fetch_run.log`，旧 verified.json（若有）原封不动。同理 upgrade 非升级分支（`UPTODATE_SKIP`/`NO_REMOTE`/`LOCAL_AHEAD` 等）MUST NOT 写/覆盖 upgrade.json（§5.3 已声明，此处强化为 MUST 断言，供验收机械化）。

### 5.5 `sync.json`（sync 产出）+ 二进制证据链
```json
{ "specVersion":"0.2.7", "runAt":"...", "runId":"<本轮uuid, MUST>",
  "summary":{ "probed":3, "upgraded":1, "synced":1, "failed":1 },
  "entries":[
    {"name":"codex","source":"...","target":"D:\\AI\\Programs\\CLI\\codex\\codex.exe",
     "targetVersion":"0.154.0","action":"copy","bytes":298169136,
     "sourceSha256":"...","targetSha256":"...","previousSha256":"...",
     "integrityNote":"ok","ok":true},
    {"name":"opencode","action":"skip","reason":"no fresh verified-success / pinned-mismatch / already-current"}
  ] }
```
- **summary**：sync 汇总本轮 state。agent 汇报数字取 summary。
- **二进制证据链**：`copy` entries MUST 携 `sourceSha256`（凭证 sha256）/`targetSha256`（copy 后 D 盘实测，须与 source 一致）/`previousSha256`（覆盖前 `.previous`）。opencode MUST 填；mise SHOULD 填（数据源 = verified.sha256）。`integrityNote` 记录 `ok` / `single-source` / `sha256-recomputed` 等。
- `action`：`copy` / `skip` / `target-locked`。

### 5.6 `current-run.json`（archive-state 首步生成）
```json
{ "specVersion":"0.2.7", "name":"<cli-autoupdate>", "runId":"<uuid>", "startAt":"<UTCISO>", "archivedTo":"archive\\<ts>" }
```
注：`name` 此处为任务名（非 CLI 名），`startAt` 替代 `runAt`（表本轮起点）。

### 5.7 `<cli>.pin`（可选，手动锁定目标版本）
```json
{ "specVersion":"0.2.7", "name":"codex", "pinVersion":"0.152.0", "reason":"user manual rollback", "setAt":"..." }
```
注：`setAt` 替代 `runAt`（表 pin 设置时间）。
**pin 语义**：
- pin 存在时，sync **目标版本 = pinVersion**。
- `verified.version == pinVersion` 且新鲜且完整性通过 → sync MUST 晋升到 pinVersion：D 盘 == pinVersion → `SYNC_SKIP|already-current`（幂等）；D 盘 ≠ pinVersion → `SYNC_COPY|` 修复性晋升（拉回 pinVersion）。
- `verified.version != pinVersion` → `SYNC_SKIP|pinned-mismatch`（不晋升 latest）。
- **pin 只作用于 sync，不阻断 upgrade**（staging 可备最新版供解锁后晋升）。
- 解锁跟随 latest → 删除 pin 或把 pinVersion 改为 latest。

### 5.8 校验与原子写入（fail-closed）
每状态文件落盘走「写 `*.tmp` → 回读校验关键字段 → `Move-Item` 原子替换」。同卷原子；跨卷先 Copy 到目标卷临时文件再同卷 Move。校验失败 → `RUNTIME_ERROR_FATAL|schema`、释放锁、终止整轮。

### 5.9 字段级 schema 总表（与示例一一对应）

| 文件 | 字段 | 类型 | 必填 | 枚举/说明 |
|---|---|---|---|---|
| 全部 | specVersion | string | 是 | `"0.2.7"` |
| 全部 | name | string | 是 | CLI 名或任务名（current-run） |
| 全部 | error | string\|null | 是 | null=无错 |
| local/remote/upgrade/verified/sync | runAt | ISO | 是 | current-run 用 startAt，pin 用 setAt |
| local/remote/upgrade | runId | string(uuid) | SHOULD | 关联本轮 |
| verified/sync/current-run | runId | string(uuid) | 是 | 新鲜度主判据/本轮身份 |
| local.json | channel | string | 是 | mise/github-binary |
| | version | string\|null | 是 | SemVer 或 null |
| | exePath | string\|null | 是 | |
| | bytes | int\|null | 是 | |
| | mtime | ISO\|null | 是 | |
| | sha256 | string\|null | 条件 | opencode 必填，mise SHOULD |
| | healthy | bool | 是 | |
| | healthDetail | string | 是 | ok/broken/probe-error |
| remote.json | channel | string | 是 | mise/github-binary |
| | latest | string\|null | 是 | null=远端失败 |
| | sourceUrl | string\|null | 是 | 加速地址 |
| | directUrl | string\|null | 是 | 直连 |
| | assetName | string\|null | 是 | github-binary |
| | assetDigest | string\|null | 条件 | github-binary；`sha256:<64hex>`，来自 API `.assets[].digest` |
| | expectedSha256 | string\|null | 条件 | github-binary；64hex（剥前缀），digest 不可用时=null |
| | checksumAssetUrl | string\|null | 是 | null=无 checksum（digest 不可用时 fallback） |
| | fallbackUsed | bool | 是 | |
| upgrade.json | fromVersion | string | 是 | |
| | target | string | 是 | |
| | exitCode | int | 是 | 0=成功 |
| | ok | bool | 是 | |
| | sha256 | string\|null | 条件 | opencode 必填，mise SHOULD |
| verified.json | channel | string | 是 | |
| | version | string | 是 | |
| | exePath | string\|null | 是 | |
| | bytes | int\|null | 是 | |
| | sha256 | string\|null | 条件 | opencode 必填，mise SHOULD |
| | matchesTarget | bool | 是 | |
| | healthy | bool | 是 | |
| sync.json | summary.probed/upgraded/synced/failed | int | 是 | |
| | entries[].action | string | 是 | copy/skip/target-locked |
| | entries[].source/target/targetVersion | string | 条件 | copy 必填 |
| | entries[].bytes | int | 条件 | copy 必填 |
| | entries[].sourceSha256/targetSha256/previousSha256 | string\|null | 条件 | opencode copy 必填，mise SHOULD |
| | entries[].integrityNote | string\|null | 条件 | ok/single-source/sha256-recomputed |
| | entries[].reason | string\|null | 条件 | skip 必填 |
| | entries[].ok | bool\|null | 条件 | copy 必填 |
| current-run.json | startAt | ISO | 是 | 替代 runAt |
| | archivedTo | string | 是 | |
| pin | pinVersion | string | 是 | |
| | reason | string | 否 | |
| | setAt | ISO | 否 | 替代 runAt |

### 5.10 威胁模型声明（回应 GPT 4.4）

**本项目完整性策略防什么**：
- 下载损坏/半下载/stub（大小 >1MB + sha256）
- 反代投毒（无 checksum asset 时双 hash 比对，检出反代与直连不一致）
- ZipSlip 路径穿越（解压约束 §7.2）
- 落盘/复制偏差（sync source/target sha256 证据链 + 字节复核）
- 陈旧凭证覆盖手动回退（新鲜度 + pin）

**不防什么（明确边界）**：
- **上游发布账号/Release 被攻破**：攻击者替换 zip 后重新上传 asset，GitHub 对新 asset 计算 digest、digest "正确"对应新恶意 zip；checksum asset 同理可同被替换。**API digest 主路径不解决此威胁**（digest 也来自同一被攻破的 release，仅证明"下载到的=GitHub 当前托管的"，不证明"=发布者应发布的"）——需发布者 RSA/Ed25519 签名（独立于 GitHub 托管层），本项目明确不做。
- 磁盘物理损坏、OS 级恶意软件、本地 sha256 工具被篡改。

**前提信任**：信任 GitHub repo `anomalyco/opencode` 维护者账户、信任 mise registry、信任反代 `gh.jasonzeng.dev`（双 hash 兜底部分缓解反代风险）。这些信任是本方案的前提，不在本项目保护范围内。

此声明使审计意见收敛——"为何不做签名验证"在此有明确答：保护目标不含上游真实性，属用户对上游 repo 的信任前提。

---

## 6. 运行锁模型（runId ownership）+ 恢复手册

- **争锁**（archive-state 首步）：`[IO.File]::Open(run.lock, FileMode::CreateNew, FileAccess::ReadWrite, FileShare::None)` 原子争锁；写 `runId/start/beat/pid`，runId 写入 `current-run.json`。
- **续锁**（后续每段）：open 锁文件独占 → 读 runId → 与 `current-run.json` 比对 → 匹配刷新 beat；不匹配/被独占/锁文件消失 → `LOCKED|`。
- **陈锁接管**：beat 超 30min **且** PID 经 `Get-Process -Id` 确认死亡 → 删锁重争；不确定 → 保守 `LOCKED|`。
- **释放**：sync 末步或异常分支，确认 runId 匹配后删锁。

> **锁空转处置**：`LOCKED|` 统一涵盖独占/崩溃残留/锁文件消失。fail-closed → blocked，**不人工抢锁**。最坏 30min 停摆窗口。
>
> **锁恢复手册（硬约束）**：SOP MUST 含"人工介入清锁"章节，仅当**全部**满足才允许清 `run.lock`：① 无活跃 `pwsh`/`mise`/下载进程；② D 盘权威入口未写一半（exe 与 `.previous` 字节完整可 `--version`）；③ `archive-state` 未执行（无 `*.tmp` 残留、`archive/<未完成时间戳>/` 不存在或完整）；④ 锁内 beat 超 30min 或 PID 确认死亡。满足后 move_to_trash 清锁，下一轮自然重争。任一不满足 → 等待不抢锁。

---

## 7. 模块清单

### 7.1 共享库 `cli-common-v0.2.7.ps1`
`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`，异步排空 stdout/stderr 再 WaitForExit+Kill；超时 mise ls-remote 60s / upgrade 600s / exe --version 30s）、`Compare-SemVer`（去 `v`，比较 Major.Minor.Patch，prerelease 低于 stable，不支持 build 元数据；解析失败返回 incomparable）、`Get-CherryMiseEnv`/`Get-MiseExePath`/`Get-MiseInstallsDir`/`Get-NpmPrefix`、GitHub 加速/直连 URL 构造器 + `gh auth token` 读取、**zip 安全解压**（§7.2 ZipSlip）、SHA256 计算、checksum 文件解析（§5.2 MUST 规则）、健康检查分型、运行锁原语、状态文件原子写入助手、runId 生成与读取、凭证新鲜度双判据（runId 主 / runAt 兜底）、pin 读取。

### 7.2 每 CLI 一套（4 拆模块）

| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver → 全字段 + runId(SHOULD) + sha256 SHOULD | 扫 `staging\opencode\<ver>\` → 全字段 + runId(SHOULD) + sha256 |
| `probe-remote-<cli>.ps1` | `mise ls-remote --json`；失败写 `latest:null,error` | `releases/latest` + 失败回退；记录 sourceUrl/directUrl/assetDigest/expectedSha256/checksumAssetUrl；认证 token 提额；403 限流 → `RATE_LIMITED|` |
| `upgrade-<cli>.ps1` | 读 local+remote → 判 behind（§7.3 if-elif）；ACTIONABLE=`mise upgrade <tool>@latest`，REPAIR=`mise install <tool>@<ver> --force` | 读 remote → 下载（§5.2 完整性策略：digest 主路径 + checksum 解析 fallback）→ **ZipSlip 安全解压** → staging exe 计算 sha256 |
| `verify-<cli>.ps1` | 重扫 mise installs → 全字段 + runId(MUST) + sha256 SHOULD | 跑 staging exe `--version` → 全字段 + runId(MUST) + sha256 |
| `sync-v0.2.7.ps1`（共享） | 遍历三 CLI verified.json → 三重约束判定 → copy + 字节/sha256 复核 + `.previous` 备份 + 证据链 + summary 汇总 | 同左 |

**ZipSlip 解压安全约束（硬约束）**：opencode zip 解压 MUST 满足：① 目标限定 `staging\opencode\<ver>\` 子树；② 拒绝含 `..\` / 绝对路径 / symlink / junction 的 entry；③ 发现非法 entry → 中止解压、清理已解压文件、`DOWNLOAD_FAIL|<cli> zip-slip`、不写 verified.json；④ 解压后校验目标 exe 存在且 > 1MB。

**sync 异常隔离硬约束**：sync 内**每个 CLI 的 copy 逻辑 MUST 用独立 try/catch 捕获**，单 CLI 的 copy/复核/备份失败 MUST NOT 向上冒泡终止整轮。具体：
- CLI 级 copy 失败（IO 错误/复核不过/`.previous` 备份失败/目标锁定）→ recoverable 标记该 CLI，继续下一个。
- 骨架级失败（锁争取/续取失败/sync.json schema 校验失败/汇总计算异常/summary 无法落盘）→ `RUNTIME_ERROR_FATAL|` 终止整轮。
- 实现 MUST 用 `ForEach ($cli in $clis) { try { <copy> } catch { <recoverable 标记>; continue } }` 粒度，禁止循环外统一 catch。

### 7.3 behind 判定与版本规则（upgrade 内部）
读 `local.json` + `remote.json` → **按下列顺序 if-elif 评估，命中即止（自上而下优先级）**：

| # | 条件 | 标记 | 动作 |
|---|---|---|---|
| 1 | remote.latest == null | `NO_REMOTE\|<cli> <cause>` | 读不到 target，不执行，跳过 verify |
| 2 | 版本不可解析（Compare-SemVer incomparable） | `VERSION_FORMAT_ERROR\|<cli> <raw>` | 不执行，跳过 verify |
| 3 | target 为 prerelease | `TARGET_PRERELEASE\|<cli> <v>` | stable-only 拒绝，跳过 verify |
| 4 | local.healthy == false 且 healthDetail == probe-error | `PROBE_ERROR\|<cli> <reason>` | 不重装，跳过 verify |
| 5 | local.healthy == false 且 healthDetail == broken | `REPAIR\|<cli> <reason>` | 强制重装（mise: `mise install <tool>@<ver> --force`；opencode: 重下载解压） |
| 6 | local < remote 且 target stable | `ACTIONABLE\|<cli> <from>-><to>` | 执行升级 → 进 verify |
| 7 | local == remote 且 有本轮新鲜凭证 | `UPTODATE_SKIP\|<cli> <v>` | 不执行、不写 upgrade.json、跳过 verify（真幂等） |
| 8 | local == remote 但 凭证缺失或 verified.version ≠ local.version | `UPTODATE_REFRESH\|<cli> <v>` | 不执行升级，仍运行 verify（刷新凭证） |
| 9 | local > remote（双方可解析） | `LOCAL_AHEAD\|<cli> <local> > <remote>` | 不执行，跳过 verify |

**顺序说明**：1-3（远端/格式/策略前提）优先于本地健康检查（4-5），本地健康检查优先于版本比较（6-9）。同一条件多分支同时满足，按表号小者优先。

**策略说明**：stable-only 跟随 latest，不强制更新、不自动降级（降级用户手动 `mise use` 或建 pin）。`local > remote` 显式报告不静默跳过。agent 无差别调用。

### 7.4 版本号
共享库与 sync 文件名含 `-v0.2.7`；probe/upgrade/verify 每 CLI 一份，首行 `$ScriptVersion='0.2.7'` + `# SPEC: v0.2.7`。

---

## 8. 机器状态标记协议

每脚本 stdout 输出 ASCII 标记，agent 只读标记判分支，不解析 json、不心算。退出码：`0`=无事可做/已满足；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败；`3`=执行失败或复核不过。**agent 以 stdout 标记为准。**

标记分两类：**fatal**（终止整轮）/ **recoverable**（标记该 CLI 失败后继续下一个）。

| 标记 | 产出脚本 | 类别 | 判定 |
|---|---|---|---|
| `LOCKED\|` | 任何段 | fatal | blocked，本轮终止 |
| `STATE_MISSING\|` | archive/probe-local | fatal | blocked，本轮终止 |
| `PARSE_ERROR\|` | 任何段 | fatal | failed，不写回原文件，本轮终止 |
| `RUNTIME_ERROR_FATAL\|<cause>` | archive/sync（骨架级） | fatal | 整轮终止（含 schema 校验/汇总异常） |
| `RUNTIME_ERROR\|<cli> <cause>` | probe/upgrade/verify（CLI 级） | recoverable | 该 cli 失败，继续下一个 |
| `LOCAL_OK\|<cli> ver=<v> healthy=<bool> detail=<d>` | probe-local | 成功 | 阶段成功 |
| `LOCAL_EMPTY\|<cli>` | probe-local | 成功 | staging 空 → 进 upgrade |
| `REMOTE_OK\|<cli> latest=<v> fallback=<bool>` | probe-remote | 成功 | 阶段成功 |
| `REMOTE_FAIL\|<cli> <cause>` | probe-remote | recoverable | 该 cli 远端失败 → upgrade 读 latest:null → NO_REMOTE |
| `RATE_LIMITED\|<cli>` | probe-remote | recoverable | 403 + ratelimit-remaining:0 |
| `ALL_REMOTE_FAIL\|` | probe-remote 末 | 整轮级 | 三 CLI 全失败 → 跳 upgrade/verify，直进 sync |
| `UPTODATE_SKIP\|<cli> <v>` | upgrade | 成功 | 有本轮凭证，跳 verify |
| `UPTODATE_REFRESH\|<cli> <v>` | upgrade | 成功 | 凭证缺失/过期，进 verify 刷新 |
| `ACTIONABLE\|<cli> <from>-><to>` | upgrade | 成功 | 有升级动作 |
| `REPAIR\|<cli> <reason>` | upgrade | 成功 | broken 触发重装 |
| `PROBE_ERROR\|<cli> <reason>` | upgrade | recoverable | probe-error 不重装，跳 verify |
| `TARGET_PRERELEASE\|<cli> <v>` | upgrade | recoverable | stable-only 拒绝，跳 verify |
| `NO_REMOTE\|<cli> <cause>` | upgrade | recoverable | 远端失败，跳 verify |
| `VERSION_FORMAT_ERROR\|<cli> <raw>` | upgrade | recoverable | 格式不可解析，跳 verify |
| `LOCAL_AHEAD\|<cli> <local> > <remote>` | upgrade | recoverable | 本地超前，跳 verify |
| `EXE_LOCKED\|<cli>` | upgrade | recoverable | 源 exe 在跑，跳过 |
| `DISK_FULL\|<cli> <free>MB` | upgrade | recoverable | 盘空间不足，跳过 |
| `DOWNLOAD_FAIL\|<cli> <cause>` | upgrade(opencode) | recoverable | 下载/digest-mismatch/checksum-mismatch/dual-hash-mismatch/zip-slip/直连重试失败，跳过 |
| `UPGRADE_OK\|<cli> <v>` | upgrade | 成功 | 进 verify |
| `UPGRADE_FAIL\|<cli> <cause>` | upgrade | recoverable | 该 cli 失败，继续下一个 |
| `VERIFY_OK\|<cli> <v> matches=true healthy=true sha256=<或空>` | verify | 成功 | 晋升凭证（仍需新鲜度+完整性+pin 判定） |
| `VERIFY_FAIL\|<cli> <cause>` | verify | recoverable | 不晋升，D 盘入口不动 |
| `SYNC_COPY\|<cli> <bytes>` | sync | 成功 | 已复制+字节复核+sha256 复核 |
| `SYNC_SKIP\|<cli> <reason>` | sync | 成功 | 跳过（无凭证/不新鲜/pinned-mismatch/already-current） |
| `SYNC_TARGET_LOCKED\|<cli>` | sync | recoverable | 目标 exe 在跑 → 跳过该 cli |
| `RUN_STATUS\|success\|<summary>` | sync（末步） | 终态 | 整轮成功 |
| `RUN_STATUS\|failed\|<cause>` | 任何段 | 终态 | 整轮失败（仅 fatal 触发） |
| `HOUSEKEEPING_WARNING\|<cause>` | archive | 观察 | 不改变终态 |

> **错误处置语义**：fatal 类 → fail-closed 终止整轮；recoverable 类 → 标记后继续下一个。`RUNTIME_ERROR` 按出处区分：骨架段 → `RUNTIME_ERROR_FATAL`；CLI 段 → `RUNTIME_ERROR|<cli>` 继续。agent 遇未列出的 failed 类标记 → 按 fatal 处理（保守优先）。

**异常覆盖**：
- 单 CLI 失败（REMOTE_FAIL/UPGRADE_FAIL/VERIFY_FAIL/EXE_LOCKED/DISK_FULL/DOWNLOAD_FAIL/VERSION_FORMAT_ERROR/TARGET_PRERELEASE/LOCAL_AHEAD/NO_REMOTE/PROBE_ERROR/RATE_LIMITED）→ 标记、跳过、继续下一个。
- 整轮网络全断（ALL_REMOTE_FAIL）→ 不升级、sync 全 skip、RUN_STATUS|success（如实汇报网断）。
- sync 目标锁定 → SYNC_TARGET_LOCKED → 跳过不阻其他。
- 骨架级错误 → fatal 终止。

### 8.1 marker → exitCode → 文件副作用对照表（P1-4，回应 GPT，供验收机械化）

| 脚本 | 关键标记 | exitCode | 文件副作用（写/覆盖/不写） |
|---|---|---|---|
| archive-state | 争锁成功+归档完成 | 11 | 写 `current-run.json`（新建 runId）、`run.lock`、`archive/<ts>/` |
| archive-state | `LOCKED\|`/`STATE_MISSING\|`/`PARSE_ERROR\|` | 2 | 不写 current-run.json、不删旧 archive；未持锁不写 run.lock |
| archive-state | `RUNTIME_ERROR_FATAL\|<cause>` | 3 | 释放锁；不写 current-run.json |
| probe-local | `LOCAL_OK\|<cli>` | 11 | 覆盖 `<cli>-local.json`（带本轮 runId SHOULD） |
| probe-local | `LOCAL_EMPTY\|<cli>` | 11 | 写 `<cli>-local.json`（version=null, healthy=false） |
| probe-local | `RUNTIME_ERROR\|<cli>` | 3 | **不覆盖**旧 `<cli>-local.json`（P0-3 失败不覆盖） |
| probe-remote | `REMOTE_OK\|<cli>` | 11 | 覆盖 `<cli>-remote.json`（含 assetDigest/expectedSha256/checksumAssetUrl） |
| probe-remote | `REMOTE_FAIL\|<cli>`/`RATE_LIMITED\|<cli>` | 3 | 写 `<cli>-remote.json`（latest=null, error=<cause>，digest/expectedSha256=null） |
| probe-remote | `ALL_REMOTE_FAIL\|` | 2 | 末步汇总标记，不额外写文件 |
| upgrade | `ACTIONABLE\|`/`REPAIR\|` → `UPGRADE_OK\|` | 11 | 覆盖 `<cli>-upgrade.json`（fromVersion/target/sha256） |
| upgrade | `UPTODATE_SKIP\|`/`NO_REMOTE\|`/`LOCAL_AHEAD\|`/`PROBE_ERROR\|`/`TARGET_PRERELEASE\|`/`VERSION_FORMAT_ERROR\|` | 0 | **MUST NOT 写/覆盖** `<cli>-upgrade.json`（P0-3） |
| upgrade | `DOWNLOAD_FAIL\|`/`UPGRADE_FAIL\|`/`EXE_LOCKED\|`/`DISK_FULL\|` | 3 | **MUST NOT 写** upgrade.json（失败不覆盖） |
| verify | `VERIFY_OK\|<cli>` | 11 | 覆盖 `<cli>-verified.json`（新鲜 runId + sha256） |
| verify | `VERIFY_FAIL\|<cli>` | 3 | **MUST NOT 写新鲜 runId 的** `<cli>-verified.json`（P0-3，旧凭证不动） |
| verify | `RUNTIME_ERROR\|<cli>` | 3 | 不覆盖旧 verified.json |
| sync | `SYNC_COPY\|`/`SYNC_SKIP\|`（逐 CLI） | 0/11 | 覆盖 `<name>.exe` + `.previous` + 写 `sync.json.entries[]`；sync.json 末步覆盖 |
| sync | `SYNC_TARGET_LOCKED\|<cli>` | 0 | 该 CLI entry=skip，sync.json 仍写 entry（reason） |
| sync | `RUN_STATUS\|success\|<summary>` | 0 | 覆盖 `sync.json`（summary + entries） |
| sync | `RUN_STATUS\|failed\|<cause>` | 2 | 仅 fatal 触发；sync.json 若已部分写则保留 + 标记失败 |

> exitCode 约定：`0`=无事可做/已满足/整轮成功；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败/整轮失败；`3`=执行失败或复核不过（CLI 级 recoverable）。**agent 以 stdout 标记为准**，exitCode 仅供人工/日志辅助判断。

### dry-run 定位
定时任务 prompt **一律 `-Execute`**。脚本支持 dry-run 供人工预演。

---

## 9. agent 编排契约（定时任务 SOP 状态机）

**状态机图**：
```
段A: archive + probe
  archive-state ──[LOCKED|/STATE_MISSING|/PARSE_ERROR|/RUNTIME_ERROR_FATAL]──→ fatal 终止
        │ OK
        ▼
  ∀cli: probe-local → probe-remote
        │  [RATE_LIMITED|<cli>] recoverable → 下一 cli
        │  [ALL_REMOTE_FAIL] ─────────────────────┐
        │  [RUNTIME_ERROR|<cli>] recoverable 继续  │
        ▼                                          │
段B: upgrade + verify（无差别，upgrade 自判）       │
  ∀cli: upgrade -Execute                            │
        │  [UPTODATE_SKIP] → 跳 verify             │
        │  [UPTODATE_REFRESH/ACTIONABLE/REPAIR/UPGRADE_OK] → verify
        │  [PROBE_ERROR/TARGET_PRERELEASE/NO_REMOTE/VERSION_FORMAT_ERROR/LOCAL_AHEAD
        │   /EXE_LOCKED/DISK_FULL/DOWNLOAD_FAIL/UPGRADE_FAIL] recoverable → 下一 cli
        │  [RUNTIME_ERROR_FATAL] → fatal 终止      │
        ▼                                          │
  verify-<cli>                                     │
        │  [VERIFY_OK] → sync-eligible             │
        │  [VERIFY_FAIL/RUNTIME_ERROR|<cli>] → 下一 cli │
        ▼                                          │
段C: sync + 汇报  ◄────────────────────────────────┘
  sync -Execute
        │  [SYNC_COPY/SYNC_SKIP/SYNC_TARGET_LOCKED] 逐项（每 CLI 独立 try/catch）
        │  [RUNTIME_ERROR_FATAL] → fatal 终止
        ▼
  RUN_STATUS|success|<summary> → 汇报（数字取 sync.json.summary）
```

SOP 写死分段 + 标记判定表，agent 逐字执行。**agent 在 pwsh 命令行调 `-File` 时用正斜杠**（避免 MSYS 路径转换/反斜杠转义）；不 `cd /d`、不 `.\`。

**agent 铁律**：
1. 不现场写脚本、不临时造脚本补救，异常走标记表分支。
2. 不手算版本、不读 json 判 behind、不改 json 程序事实。
3. 不 `cd /d`、不 `.\`，pwsh `-File` 路径用正斜杠。
4. 不降级 PS 5.1、不去锁、不去原子写入、不做完整性校验计算（脚本算）。
5. 如实回报终态；数字取 sync.json.summary。
6. 每次必输出状态行汇报。
7. 遇 `LOCKED|` → 汇报 blocked，不人工抢锁；清锁走 §6 恢复手册全部条件。
8. 遇 `RATE_LIMITED|` → 如实汇报限流（区别于普通网络失败）。

### 固定汇报模板（段C 必输出，数字取 sync.json.summary）
1. 状态行：本轮 3 CLI 探测，升级 X / 同步 Y / 失败 Z；终态 success/failed；网络全断/限流如实标。
2. 逐 CLI：`<cli>: <installed>→<target>`（UPTODATE_SKIP 标 `已是最新`；UPTODATE_REFRESH 标 `已是最新（凭证刷新）`；未升级标原因）。
3. 同步：`<cli> copied <bytes> sha256=<前12位>` / `<cli> skipped <reason>`。
4. 异常项：失败的 CLI 逐项列原因（含 digest-mismatch/checksum-mismatch/dual-hash-mismatch/zip-slip/rate-limited）。
5. 一句收尾备注。

### SOP 错误场景示例（MUST 覆盖）
网络全断、目标 exe 锁定、opencode 下载失败（含 digest-mismatch/checksum-mismatch/dual-hash-mismatch/zip-slip）、verify 失败不晋升、凭证缺失刷新（UPTODATE_REFRESH）、手动回退 pin（pinned-mismatch/修复性晋升）、被锁阻塞（含 §6 恢复手册步骤）、GitHub 限流（RATE_LIMITED）。每例给"输入状态 → 标记序列 → agent 分支 → 汇报文本"。

### 推送策略
配 channel_ids → 每次执行后必推送；未配 → 不推送。凭证/sha256/token 不写入 prompt/状态文件/日志/推送平台。

### report_artifacts
声明 `state/sync.json` 作本轮审计产物。

---

## 10. 回退与清理

### 10.1 mise（claude/codex）
`upgrade.auto_prune=false`；回退 `mise use <tool>@<旧版>`；保留最近 2 stable。

### 10.2 opencode（github-binary）
staging 保留最近 2 版；升级失败 → 不写新鲜凭证 → sync 不动 D 盘；显式回退重跑 upgrade 指定旧 tag 或建 pin。stub 不复现（不走 npm + ZipSlip + 完整性校验）。

### 10.3 权威入口（D 盘）+ 手动回退语义
仅 sync 写。覆盖前备份 `.previous`。目标 exe 锁定 → SYNC_TARGET_LOCKED 跳过。

**手动回退语义**：用户用 `.previous` 回退 D 盘后，**若不建 pin**，下一轮 sync 用本轮新鲜凭证自动覆盖（自动跟随 latest 的预期行为）。需保持回退版本 → MUST 建 `state/<cli>.pin` 锁定 pinVersion（§5.7）。

### 10.4 流程产物 + 归档保留策略
- `state/archive/<时间戳>/`：每轮归档，**保留最近 30 轮**，超出由 archive-state 首步清理（最旧先删）。fetch_run.log 补长追溯。
- `staging/`：保留最近 2 版。
- `TEMP/`：交付前必空。
- `run.lock`：残留按 §6 恢复手册清。
- `*.tmp`：archive-state 首步清理。

### 10.5 opencode npm 全局
暂保留作 fallback，**连续 10 轮 sync 成功后卸载**（N=10 定死，回应 GPT P0-2；10 轮覆盖约 10 天定时窗口，足以暴露稳定期问题）。

---

## 11. 可追溯

- 每轮首步 archive-state 归档 `state/*.json`（不含 run.lock、archive/、current-run.json、pin）到 `archive/<时间戳>/`。
- `fetch_run.log` 累积每轮 `[时间] runId=<id> probed=N upgraded=X synced=Y failed=Z`。
- sync.json.entries 携 sha256 证据链（source/target/previous + integrityNote）。
- spec/脚本/json 全带 specVersion；版本历史见 §16。

---

## 12. 与参照系差异（自检）

| 维度 | Software_Update_Monitor v0.2.2 | Release-Monitor | 本项目 v0.2.7 |
|---|---|---|---|
| 范围 | monitor-only | monitor-only | monitor+download+install+switch+rollback |
| 模块粒度 | — | 合并 monitor.ps1 | 4 拆模块 |
| 状态源 | Manifest+SQLite | md+result.json | state/*.json |
| 锁 ownership | — | PID 匹配 | runId 匹配 |
| 晋升闸 | — | — | 三重约束（新鲜度+完整性+pin） |
| 供应链 | — | — | checksum MUST + 双 hash SHOULD + ZipSlip + 证据链 + 威胁模型声明 |
| 形态 | 通用工具 spec | 个人定时监测 | 个人定时维护流程 |

---

## 13. v0.2.7 迁移项（首次执行）+ checklist

1. 新建 `D:\AI\Programs\CLI\{claude,codex,opencode}\`（claude 已手动补全；新机重装仍需）。
2. **首轮 seed 路径**：由 `UPTODATE_REFRESH` 天然完成——首轮即使所有 CLI UPTODATE，凭证缺失触发 verify 产出 seed 凭证 → sync copy。D 盘已有正确版本则 `already-current` 幂等跳过。
3. 当前已验证版本：claude 2.1.273 / codex 0.154.0 / opencode 1.18.31。
4. **旧散路径清理 checklist（破坏性人工操作，MUST 逐项核对后才清空）**：
   - [ ] Cherry Studio Agent/Provider 配置：确认无 provider/agent 指向旧路径（`Claude-Code-CLI`/`Codex\CLI`/`opencode\CLI`）——查 Cherry 配置与已安装 Agent 定义
   - [ ] 其他脚本引用：全工作区 `rg` 搜旧路径字符串，确认无脚本/定时任务 prompt 引用
   - [ ] 系统 PATH：确认 PATH 不含旧路径
   - [ ] 桌面/开始菜单快捷方式：确认无 `.lnk` 指向旧路径
   - [ ] mise shim：确认 mise shim 不依赖旧散路径
   - [ ] opencode\CLI 的 479B stub 确认无引用后必清
   - [ ] 含 `.git` 段的路径走手动删除（R43 工具保护，禁 rm/mv 规避）
   - 全部勾选后才执行清空。
5. opencode 安装源切换：npm → GitHub binary staging；首次 probe-local 扫 staging（空 → LOCAL_EMPTY → 触发首次 upgrade）。
6. mise 配置加 `upgrade.auto_prune=false`。
7. 现有散脚本（`.old/`）→ 按 §7 模块清单拆分重命名（-v0.2.7 / $ScriptVersion）。`.old/` legacy 脚本受仓库 AGPL-3.0 LICENSE 约束，新脚本沿用同 LICENSE（仓库既有）。
8. 产出 `cli-autoupdate-sop.md`（含 §6 锁恢复手册 + §9 错误场景示例）。

**配置/数据迁移**：无 config.json、无 SQLite/DB、无用户数据。状态 schema 跨版本靠 `specVersion` 标识。

---

## 14. 待确认 / 已知风险（v0.2.7 闭合状态，回应 GPT P0-2）

> **驳回 GPT"全部关闭§14"（过度）**：真未知风险（反代可靠性/PID 沙箱陈锁判定/极端时钟回拨）需实现期实测，伪声明"closed"反误导验收。此处区分**已闭合**（实测/规则已定）与**已知风险声明**（验收口径已定、待实现期实测兜底）。

**已闭合**：
1. ~~opencode GitHub release asset/tag/checksum 实测~~ → **已闭合（gh api 实测 2026-09-16）**：tag=v1.18.31、assetName=opencode-windows-x64.zip、prerelease=false、全 37 asset 带 digest（§5.2/§14-6 同闭合）。
4. ~~current-run.json 与 run.lock 一致性~~ → **已闭合**：一处损坏 → fail-closed 终止（§5.8/§6 已定验收口径）。
5. ~~opencode npm 全局卸载判据~~ → **已闭合**：N=10（§10.5 定死）。
6. ~~opencode 官方 checksum 覆盖率~~ → **已闭合（实测）**：anomalyco/opencode v1.18.31 全 37 asset 均带 API digest；digest 缺失走 checksum asset→双 hash fallback（§5.2 策略）。
7. ~~GitHub API 限流~~ → **已闭合**：认证提额 5000/h 足够；未认证 60/h 触发 `RATE_LIMITED|` 区分 + §9 铁律8（验收口径已定）。
9. ~~上游真实性不在保护范围~~ → **已闭合**：威胁模型声明（§5.10），API digest 亦不解决上游被攻破（digest 来自同一 release），属信任前提。

**已知风险声明（验收口径已定，待实现期实测兜底，不伪关闭）**：
2. **反代可靠性 + 双 hash 成本**：反代不可用回退直连；digest 主路径下双 hash 仅在 digest+checksum 均不可用时触发（成本上限收窄）。验收口径：反代失效→直连重试一次→仍失败 `DOWNLOAD_FAIL|`。反代长期可靠性待实现期实测。
3. **runId 锁模型实现细节**：续锁独占/消失统一 fail-closed（§6 已闭合到 SOP + 恢复手册）；陈锁接管 PID 死亡判定在 Cherry 沙箱下可靠性待实测。验收口径：不确定→保守 `LOCKED|` 不抢锁。
8. **时钟回拨**：凭证新鲜度已加 runId 主判据兜底；runId 缺失时 runAt 兜底，极端时钟异常仍可能误判。验收口径：已知边界，runId 匹配优先。待实现期模拟时钟回拨测试覆盖。

---

## 15. 测试策略

- **单元**：`Compare-SemVer`（边界 + §7.3 if-elif 顺序全覆盖）、`Invoke-Proc`（超时/Kill）、健康检查分型、SHA256 计算、ZipSlip 解压（构造恶意 entry）、checksum 文件解析（两格式/多资产匹配/空白注释行）、凭证新鲜度双判据（runId 匹配 / runAt 兜底 / 时钟回拨模拟）、pin 规则（修复性晋升 / pinned-mismatch / pin 不阻断 upgrade）、sync 异常隔离（单 CLI copy 失败不冒泡）。
- **集成**：每 CLI probe→upgrade→verify 串；覆盖 §7.3 九分支 + checksum-mismatch/dual-hash-mismatch/zip-slip/RATE_LIMITED。
- **端到端**：archive→三 CLI cycle→sync；覆盖成功/uptodate-refresh/网络全断/exe 锁定/verify 失败/pin 锁定（含修复性晋升）/被锁阻塞（含恢复手册）/限流九场景；穿插 re-probe。
- **环境**：仅 Windows 11 + PowerShell 7.6.4 + Cherry 沙箱。
- **验收 checklist（独立交付物，回应 GPT Checklist A-N）**：冻结后产出 `cli-autoupdate-acceptance-checklist.md`——每条 MUST/SHOULD 拆成"条款 → 可观测证据（哪个 json 字段/stdout 标记/文件副作用，见 §8.1 对照表）→ 测试用例"。与 §15 对齐。GPT Checklist A-N（交付物/环境/锁/state 契约/标记/archive/probe-local/probe-remote/upgrade 九分支/verify/sync 三重约束+证据链+异常隔离/ZipSlip/回退/SOP 编排）作为该 checklist 骨架。**不塞进 spec 主体**（守 Plan/契约层定位）。

测试在脚本实现阶段做。

---

## 16. 版本历史

| 版本 | 日期 | 摘要 | 文件 |
|---|---|---|---|
| v0.1 | 2026-09-16 | 初版：混合架构 | `SPEC-v0.1.md` |
| v0.2 | 2026-09-16 | 运行锁、标记协议、原子写入、fail-closed、opencode 回退 | `SPEC-v0.2.md` |
| v0.2.1 | 2026-09-16 | behind 下移 upgrade、runId 锁、无差别调用、SOP 层 | `SPEC-v0.2.1.md` |
| v0.2.2 | 2026-09-16 | Zoo 审计复核：术语表/版本历史/测试策略/版本格式验证/SOP 错误场景；驳回误读意见 | `SPEC-v0.2.2.md` |
| v0.2.3 | 2026-09-16 | CodeBuddy 审计复核：F1–F6（凭证生命周期/标记闭合/错误语义分层/数字源/REPAIR/锁空转） | `SPEC-v0.2.3.md` |
| v0.2.4 | 2026-09-16 | GPT 治理评审复核：供应链强化+ZipSlip+pin 语义重写+证据链+恢复手册+RFC2119+schema 表+状态机图 | `SPEC-v0.2.4.md` |
| v0.2.5 | 2026-09-16 | anthropic 治理评审复核：schema 总表补全、sha256 SHOULD 对齐、sync 异常隔离硬约束、behind if-elif 优先级、archive 保留 30 轮、GitHub 限流缓解+RATE_LIMITED、凭证新鲜度 runId 双判据、回退方向澄清、晋升闸定义补 pin、迁移 checklist | `SPEC-v0.2.5.md` |
| v0.2.6 | 2026-09-16 | GPT 二次评审复核（对 v0.2.4）：时间字段例外说明、LICENSE 事实矛盾修正（仓库实有 AGPL-3.0）、威胁模型声明、checksum 解析 MUST 规则、state 文件 runId 关联（SHOULD）、斜杠约定澄清；驳回"路径插空"（渲染误读）与"交付物三层矛盾"（阶段状态） | `SPEC-v0.2.6.md` |
| v0.2.7 | 2026-09-16 | GPT frozen-direction 评审复核（对 v0.2.6），朝冻结候选收敛：P0-1 GitHub API asset digest 主路径 MUST（gh api 实测验证）+ expectedSha256 schema 字段（保留 checksumAssetUrl 作 fallback）；P0-2 §14-1/6 实测闭合、§14-5 N=10、真未知风险不伪关闭（驳回"全部关闭"）；P0-3 verify 失败不写新鲜 runId 凭证；P1-4 marker→exitCode→文件副作用表（§8.1）；P1-5 Canonical Path 代码块；Checklist A-N 引为独立验收交付物 | `SPEC-v0.2.7.md`（本文件） |

---

## 17. 术语表

| 术语 | 定义 |
|---|---|
| CLI | claude/codex/opencode 三个命令行工具 |
| mise | 版本管理器，管 claude/codex |
| staging | 升级场层，下载/验证落点 |
| promotion | 权威入口层，`D:\AI\Programs\CLI\<name>\<name>.exe` |
| 晋升闸 | sync 只复制通过**三重约束**的 CLI：①本轮新鲜（runId 或 runAt）②完整性通过（sha256）③pin 未冲突 |
| 凭证 | verified.json，含 runId；三重约束全过才可晋升 |
| 凭证新鲜度（双判据） | `runId == current-run.runId`（主判据）或 `runAt ≥ startAt`（兜底防时钟回拨） |
| pin | state/<cli>.pin，锁定目标版本=pinVersion，只作用于 sync |
| sha256 证据链 | sync.json.entries 的 source/target/previous sha256 + integrityNote |
| ZipSlip | zip 路径穿越攻击，MUST 拒绝 `..\`/绝对路径/symlink |
| 双 hash 比对 | 无 checksum asset 时，反代+直连两份独立下载 SHA256 一致才接受 |
| API asset digest | GitHub Releases API `.assets[].digest`（`sha256:<64hex>`），upload-time 计算、immutable；opencode 完整性主路径 MUST（2025-06-03 起 Releases 暴露） |
| expectedSha256 | remote.json 字段，从 API digest 剥 `sha256:` 前缀取 64hex，校验 zip 下载完整性用 |
| RATE_LIMITED | 403 + ratelimit-remaining:0，区别于普通 REMOTE_FAIL |
| 威胁模型 | §5.10 声明：防下载损坏/反代投毒/ZipSlip/落盘偏差/陈旧凭证；不防上游账号被攻破（需签名，本项目不做） |
| SemVer | `Major.Minor.Patch[-prerelease]`，限制版 |
| 原子写入 | tmp → 回读校验 → Move-Item 同卷替换 |
| runId | archive 首步生成的 uuid，锁 ownership + 凭证新鲜度主判据 + state 文件关联 |
| fatal / recoverable | 错误分层：fatal 终止整轮；recoverable 单 CLI 失败继续 |
| 异常隔离 | sync 内每 CLI copy 独立 try/catch，单 CLI 失败不冒泡终止整轮 |
| 反代前缀 | `https://gh.jasonzeng.dev/`，失效直连回退 |
| dry-run | 无 -Execute 模式，预演 |
| fail-closed | 失败 → 终止不降级不静默跳过 |
| LICENSE | 仓库根 AGPL-3.0，适用于 `.old/` legacy 脚本；本项目主体不面向外部发行 |
| MUST/SHOULD/MAY | RFC2119：必须/应/可 |
