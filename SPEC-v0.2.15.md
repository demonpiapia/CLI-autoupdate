# CLI 自动升级 —— 项目规格 SPEC v0.2.15

> **版本**：SPEC-v0.2.15（2026-09-17）。
> **变更摘要（v0.2.14 → v0.2.15）**：架构不动。据 GPT 独立审计（对 v0.2.14，`.supervisor/spec-v0.2.14-GPT-review.md`）复核，7 项意见：采纳 5、部分采纳 1、驳回 1——全为契约层补全/消歧，**不改任何判定语义、不涉 §6 锁逻辑**：
> - 🔴 **GPT-P0-1**（采纳）：mise staging 路径"省略号"消歧义——§2 的 `E:\...\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\` 精确化为 `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\`（本轮实测复核 2026-09-17 + legacy 实测 2026-09-16）；§4 Canonical Path 补该行；§7.1 新增"Cherry mise 环境契约"（`Get-MiseInstallsDir`/`Get-MiseExePath`/`Get-NpmPrefix` 精确常量 + `Get-CherryMiseEnv` 七键 + "mise 子进程 MUST 带 MISE_* env / 文件扫描不依赖 env" + ExeRelPath 实测结构 + 失败沿既有标记不新增）；§5.1 补 mise 通道目录缺失/空语义（同 opencode staging 空 → broken → REPAIR 通道）。
> - 🔴 **GPT-P0-2**（采纳）：§8 补"标记行语法"MUST 六条——独占一行/行首即标记名（禁前导时间戳、日志级别）/首个 `|` 切分且标记名 ∈ §8 表枚举/除 `RUN_STATUS` 外 payload MUST NOT 含 `|`/非标记日志行 MUST NOT 以"已知标记名 + `|`"开头/agent 解析规则。消除 Write-Host/日志框架差异导致的误解析。
> - 🟡 **GPT-P0-3**（部分采纳）：current-run.json `name`=任务名语义注记强化——§5.9 补 current-run.name 独立 schema 行（固定 `<cli-autoupdate>`；"与其他文件的 CLI 名语义不同，验收断言 MUST 分开编写"）+ §5.6 注同步；**驳回字段改名 `taskName`**——`name` 在本项目统一表达"文件归属者"（CLI 名/任务名/`sync`），改名引入跨文件 schema 特例，且值本身不可混淆（`<cli-autoupdate>` 字面量），无机械验收收益。
> - 🟡 **GPT-P1-1**（采纳）：时间字段格式契约统一——所有本项目生成的 ISO 时间字段（`runAt`/`startAt`/`setAt`/`lastUpdatedAt`/`mtime`/`beat`）MUST 以 **UTC 'o' round-trip**（恒 7 位小数 + `Z`）序列化；时间比较 MUST 在 DateTime/Ticks 层；MUST NOT 以 DateTimeOffset 序列化（与 §6 锁字段同源实测依据 CH-P1-3）。§5 总则/§5.9 总注/§7.1 助手/§15 断言四处同步。
> - 🟢 **GPT-P1-2**（采纳）：版本格式突变处置模板——§9 SOP 错误场景示例补"版本格式突变（`VERSION_FORMAT_ERROR`）"（fail-closed 持续不升级 + 人工介入路径）；§14 补第 12 项已知风险声明。
> - 🟢 **GPT-P1-3**（驳回）：§8"单页接口总览表"——脚本输入/输出（§7.2）、标记类别（§8）、文件副作用（§8.1）、分支路径（§9）已完备覆盖，信息零新增；并列事实源将放大"表↔正文不同步"风险（历轮审计最高频缺陷类型：v0.2.10 D1/D2/D4/D10、v0.2.12 CB-P2-3、v0.2.13 CB-P2-2 均属多源不一致）。以 §8.1 引言交叉索引句替代（零成本、不增事实源）。
> - 🟢 **GPT-§4**（采纳）：§5.10 补"未来增强（非本版本范围）"——上游真实性若未来纳入保护范围，路线=GitHub release attestations（`gh release verify-asset`，命令存在性 2026-09-17 检索确认）/上游自签名；本版本边界不变。
> **角色定位**：本文件是 **Plan / 契约**（治理路线图 Approved Plan 位）。契约层为硬约束；PowerShell 实现属 Executor 有界自治。
> **关键词约定（RFC2119）**：**MUST / 必须** = 绝对硬约束；**SHOULD / 应** = 强烈推荐（可偏离须记录）；**MAY / 可** = 可选。契约层陈述默认为 MUST。

---

## 0. 项目定位、范围与交付物

本项目是 **monitor + download + CLI 全局维护** 整体过程：从"探测是否有新版本"到"实际升级、切换、对外暴露统一入口"的完整闭环。

**运行形态**：Cherry Studio 定时任务驱动、agent 编排、PowerShell 7 模块化的**个人维护流程**，维护对象是三个固定 CLI（claude/codex/opencode）。**不是**通用 CLI 自动更新软件产品——无 config.json、无 `cli update` 命令、仅 Windows、不面向外部发行/不提供贡献指南；不做 RSA 签名验证（完整性策略见 §5.2，威胁模型见 §5.10）。

> **🟢 v0.2.11 P2（路径硬编码理由）**：权威入口/工作区/staging 路径在 spec 中写死（§3/§4），**这是个人维护流程的有意选择**——减少变量、提高可验收性（固定路径使 §8.1 文件副作用对照表与验收 checklist 可机械断言"哪个文件该落哪"）。不提供 config、不参数化路径，非缺陷。

**关于 LICENSE（修正事实矛盾）**：仓库根含 `LICENSE`（AGPL-3.0），系 initial commit 随归档 legacy 脚本（`.old/`）带入，**适用于 `.old/` 下历史代码**。本项目主体（SPEC + SOP + `*-v0.2.15.ps1` 新脚本）不面向外部发行、无贡献指南、不发布包；AGPL-3.0 不改变本流程的"个人维护"性质。

参照系（批判借鉴设计哲学，不照搬形态）：
- `Software_Update_Monitor_Spec_v0.2.2`（monitor-only）——本项目是其 Executor 下游延伸。
- `cherry-auto-apps-Release-Monitor`（已上线）——借鉴段内一气呵成、数据固化、运行锁、stdout 标记协议、原子写入、agent 不介入计算。不照搬合并脚本形态。

**交付物三层**：
1. **SPEC**（本文件）——设计契约。
2. **执行 SOP**（`cli-autoupdate-sop.md`）——给定时任务执行 agent 逐字读；agent 只读 SOP。**当前状态：待产出**（SPEC 评审通过后产出）。
3. **脚本**（`*-v0.2.15.ps1`）——模块化实现。**当前状态：待产出**（评审通过后产出，穿插 re-probe）。

> 工作区当前含 SPEC 系列文档、验收 checklist 候选稿（`cli-autoupdate-acceptance-checklist-candidate.md`）、LICENSE，及历轮评审/工具目录（`.supervisor/`、`.codebuddy/`、`.backup/` 等，均被 `.gitignore` 排除不跟踪）；`.old/` 归档 legacy 脚本亦在 `.gitignore` 内。SOP 与新脚本尚未产出，属评审阶段正常状态，非交付物定义矛盾。（🟢 v0.2.13 CB-P3-3：修正 v0.2.12"仅含 SPEC 系列文档 + `.old/` + LICENSE"的不实声明）

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
| 11 | 凭证新鲜度（收紧判据） | 新鲜度 = `runId 与 current-run.runId 匹配`（**唯一必要条件**）；仅 runId **字段缺失**（非不匹配）时回退 `runAt ≥ startAt`（兼容无 runId 旧凭证）。runId 存在但不匹配 → 恒不新鲜（runAt 不放行，防时钟回拨放过跨轮旧凭证）。🟡 v0.2.13 CB-P2-4 收紧 |
| 12 | 供应链完整性 | opencode 下载后 MUST 计算 sha256；**GitHub Releases API asset digest（`sha256:<64hex>`）为主路径 MUST**（digest 由 GitHub upload 时算、immutable，优于发布者上传的 checksum asset）；digest 不可用 → checksum asset MUST 校验；二者皆无 → SHOULD 双 hash 比对。mise 通道完整性由 mise 自身保证。 |
| 13 | 异常隔离 | sync 内每 CLI 的 copy 逻辑 MUST 独立捕获异常，单 CLI 失败不得向上冒泡终止整轮（§7.2）。 |

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging** | claude/codex：`E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\`（🟢 v0.2.15 GPT-P0-1：省略号消歧义，精确值/来源/失败语义见 §7.1 Cherry mise 环境契约）；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证落点 | upgrade 脚本（运行锁内） |
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
├── SPEC-v0.2.15.md                   # 本文件（契约）
├── cli-autoupdate-sop.md             # 执行 SOP（给定时 agent，待产出）
├── cli-common-v0.2.15.ps1            # 共享库
├── probe-local-<cli>.ps1             # 每 CLI 一份（3 份）
├── probe-remote-<cli>.ps1            # 每 CLI 一份（3 份）
├── upgrade-<cli>.ps1                 # 每 CLI 一份（3 份）；behind 判定 + zip 安全解压
├── verify-<cli>.ps1                  # 每 CLI 一份（3 份）；装后功能测试 + sha256
├── sync-v0.2.15.ps1                  # 共享单脚本；每 CLI copy 独立 try/catch
├── archive-state.ps1                 # 每轮首步：争锁+归档+生成 runId
├── state\                            # 固定路径，最新覆盖
│   ├── current-run.json              # runId + startAt
│   ├── <cli>-local.json
│   ├── <cli>-remote.json
│   ├── <cli>-upgrade.json
│   ├── <cli>-verified.json           # 含 runId（新鲜度主判据）+ channel（§5.4）
│   ├── sync.json
│   ├── opencode-npm-fallback.json    # opencode npm 全局卸载计数（§10.5）
│   ├── run.lock                     # 争锁文件（JSON；字段 schema §5.9，🟢 v0.2.14 CH-P1-1）
│   ├── fetch_run.log
│   ├── <cli>.pin                     # 可选：锁定目标版本
│   └── archive\<时间戳>\             # 每轮归档，保留最近 30 轮（§10.4）
├── staging\opencode\<ver>\           # opencode 解压落点（ZipSlip 约束 §7.2）
└── TEMP\                             # 交付前必空
```

> **斜杠约定澄清（回应 GPT 4.3）**：spec/示例中 Windows 路径用反斜杠 `\`（Windows 原生、json 内转义）；agent 在 pwsh 命令行调 `-File` 时用正斜杠 `/`（避免 MSYS 路径转换与反斜杠转义问题，见 §9 铁律 3）。两作用域不同，不矛盾。

> **Canonical Path（回应 GPT P1-5"路径展示插空消歧义"）**：GPT 称示例路径现"插空"（如 `D:\A I\p rograms\C LI`）系其渲染/OCR 误读——本 spec 实际路径**无空格**（已逐字核对）。仍补此代码块作低成本保险，供 agent 逐字复制，杜绝歧义：
> ```
> D:\AI\Programs\CLI\claude\claude.exe
> D:\AI\Programs\CLI\codex\codex.exe
> D:\AI\Programs\CLI\opencode\opencode.exe
> D:\AI\Workspace\automatic\CLI-autoupdate\state\
> D:\AI\Workspace\automatic\CLI-autoupdate\staging\opencode\
> E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\
> ```
> 上述路径均无空格。**大小写约定（🟢 v0.2.13 CB-P3-4）**：实机目录为 `D:\AI\Programs\CLI\Codex\`（大写 C，2026-09-16 实测），spec 文本统一小写 `codex` 为书写约定——Windows 文件系统大小写不敏感，任意大小写等价，无功能影响。agent 调 `-File` 时改用正斜杠（如 `D:/AI/Programs/CLI/claude/claude.exe`）。
>
> **🟢 v0.2.15 GPT-P0-1**：末行（mise installs 根）为本轮新增 canonical 行——该行即 claude/codex staging 根（原有末两行 workspace state/staging 为既有内容），精确值来源与失败语义见 §7.1 Cherry mise 环境契约（实测复核 2026-09-17：`installs\{claude,codex}\` 就位；claude=`installs\claude\2.1.273\claude.exe`、codex=`installs\codex\0.154.0\bin\codex.exe`）。

**陈旧数据风险**：`<cli>-remote.json` 在 REMOTE_FAIL 时写 `{latest:null, error:<cause>}`；`<cli>-upgrade.json` 仅实际升级时写，读取前 MUST 校验 `runAt` 是否本轮。

---

## 5. 数据契约（state/*.json）

**时间字段规则（回应 GPT 4.1）**：除 `current-run.json`（用 `startAt`，表示本轮起点）、`*.pin`（用 `setAt`，表示 pin 设置时间）与 `opencode-npm-fallback.json`（用 `lastUpdatedAt`，sync 末步更新时间，非逐轮 state 而是跨轮计数器，§10.5）外，其余 state JSON（local/remote/upgrade/verified/sync）MUST 带 `runAt`（ISO UTC，表示该文件产出时间）。`runId`：`current-run.json`/`verified.json`/`sync.json` MUST 带；`local.json`/`remote.json`/`upgrade.json` SHOULD 带（关联本轮，防同分钟多轮混读）。

**时间字段序列化格式（🟢 v0.2.15 GPT-P1-1，MUST——统一"ISO UTC"写法，消除实现期"无小数/带 offset"漂移）**：所有本项目生成的 ISO 时间字段（`runAt`/`startAt`/`setAt`/`lastUpdatedAt`/`beat`/`mtime`——`mtime` 为外部文件时间、写入 state 时同样归一化）MUST 以 **UTC 'o' round-trip** 序列化——`ToUniversalTime()` 后恒 7 位小数 + `Z` 后缀（如 `2026-09-17T03:21:07.1234567Z`；PS 7.6.4 DateTime `'o'` 实测形态，与 §6 锁 `processStartTimeUtc` 同源契约）。**MUST NOT 以 DateTimeOffset 序列化**：其 `'o'` 输出 offset 形态 `+00:00` 后缀（非 `Z`）、破坏统一形态（§6 锁字段禁令同源；PS 7.6.4 实测 2026-09-16）。**时间比较（如新鲜度回退 `runAt ≥ startAt`）MUST 在 DateTime/Ticks 层**（MUST NOT 字符串比较——形态不一致时 string 比较语义二义，与 §6 CB-P1-2 同源）。

所有 state/*.json 数据文件顶层带 `specVersion`（`"0.2.15"`）、`name`（🟢 v0.2.14 CH-P1-1：`run.lock` 为 §6 锁文件——存储格式亦为 JSON，但不带 specVersion/name、不参与 §11 归档，字段 schema 见 §5.9 run.lock 行）。时间内部 UTC，展示 UTC+08:00。**完整字段级 schema 见 §5.9（与示例一一对应）**。

**更新源固定清单**：
- claude/codex：mise registry（mise 自身校验包完整性）。
- opencode：`anomalyco/opencode` GitHub releases（固定 repo；反代 `https://gh.jasonzeng.dev/`，回退直连，时序 §5.2）。
- **GitHub API 认证**：probe-remote 调 GitHub API SHOULD 用认证 token 提额（未认证 60 次/小时/IP，认证 5000 次/小时）。本环境 `gh` 已认证（demonpiapia 账户）。token MAY 从 `gh auth token` 读取或环境变量注入，**MUST NOT 写入状态文件/日志/推送平台**。
- 超时：mise ls-remote 60s、upgrade 600s、exe --version 30s（§7.1）。
- 日志：`state/fetch_run.log`。
- "自动更新开关" = 定时任务本身。

### 5.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.2.15", "name":"codex", "channel":"mise", "runAt":"...", "runId":"<SHOULD>",
  "version":"0.154.0", "exePath":"...", "bytes":298169136, "mtime":"...",
  "sha256":"<mise SHOULD 计算；opencode 必填>",
  "healthy":true, "healthDetail":"ok", "error":null }
```
- `healthy`：exe > 1MB 且 `--version` 可启动。
- `healthDetail`：`ok` / `broken`（<1MB / stub / 文件缺失） / `probe-error`（`--version` 偶发超时或非零退出）。`broken` → REPAIR；`probe-error` → `PROBE_ERROR|` 不强制重装。
- `sha256`：SHOULD 计算（opencode 必填；mise SHOULD 计算以支撑 §5.5 证据链）。
- opencode staging 空 → `version=null, exePath=null, healthy=false, healthDetail=broken`（标记侧 `LOCAL_EMPTY|<cli>`，§8）。
- **mise 通道同语义（🟢 v0.2.15 GPT-P0-1）**：`installs\<tool>\` 不存在或为空 → 同上形态（`version=null`/`broken`）→ upgrade 走 REPAIR 通道；mise 环境本身不可用（`Get-MiseExePath` 缺失 / mise 子进程非零退出）→ REPAIR 失败或 remote 失败沿既有 `UPGRADE_FAIL|` / `REMOTE_FAIL|` 通道上报，**不新增标记**（§7.1 Cherry mise 环境契约）。

### 5.2 `<name>-remote.json`（probe-remote 产出）+ 下载完整性策略
```json
{ "specVersion":"0.2.15", "name":"opencode", "channel":"github-binary", "runAt":"...", "runId":"<SHOULD>",
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
  - **REMOTE_FAIL 落盘语义**：失败时仍写 remote.json，必填字段取值：`latest:null, sourceUrl:null, directUrl:null, assetName:null, assetDigest:null, expectedSha256:null, checksumAssetUrl:null, fallbackUsed:false, error:<cause>`（§5.9 必填字段全部落盘，null/默认值占位，保持 schema 一致）。
  - **GitHub 限流区分**：遇 403 + `x-ratelimit-remaining: 0` → `RATE_LIMITED|<cli>`（区别于普通 REMOTE_FAIL）。
  - **下载完整性策略（v0.2.7 调整：API digest 主路径，回应 GPT P0-1）**：
    1. 下载 zip 后 MUST 校验大小 > 1MB（防半下载/stub）。
    2. **GitHub Releases API asset digest 存在**（`.assets[].digest`，格式 `sha256:<64hex>`）→ MUST 以 digest 为完整性主路径：剥 `sha256:` 前缀取 64hex 写入 `expectedSha256`，下载 zip 后计算 SHA256 与 `expectedSha256` 比对；不匹配 → `DOWNLOAD_FAIL|<cli> digest-mismatch`。digest 由 GitHub 在 asset upload 时计算、immutable，比发布者上传的 checksum asset 更可信（checksum asset 可连同 zip 一起被替换）。digest 主路径**无需额外下载 checksum 文件**（digest 已在 releases API 响应内），省一跳。
    3. **digest 不可用**（旧 release digest=null，或 API 未返回）→ checksum asset 存在则 MUST 下载 checksum 并校验 SHA256；不匹配 → `DOWNLOAD_FAIL|<cli> checksum-mismatch`。🟢 **v0.2.13 CB-P3-5（期望值落盘）**：checksum 匹配成功时，probe-remote MUST 将该条目 hash 写入 `expectedSha256`（校验期望值落盘，事后可复核，闭合审计证据链）；路径来源可机械区分——`assetDigest==null && expectedSha256!=null` 即 checksum 路径，且 fetch_run.log 记 `checksum-path used`。
    4. **digest 与 checksum asset 均不可用** → SHOULD 双 hash 比对（反代+直连两份独立下载，SHA256 一致才接受）；不一致 → `DOWNLOAD_FAIL|<cli> dual-hash-mismatch`。MAY 偏离（直连不通时仅用反代 + `integrityNote:single-source`），须在 sync.json.entries 记录。
    5. 解压后对目标 exe MUST 计算 SHA256：**upgrade 脚本计算并写入 `upgrade.json.sha256`**（staging exe hash）；**verify 脚本复算并写入 `verified.json.sha256`**（两者数值应一致，同源 exe）。upgrade MUST NOT 越界写 verified.json（§7.2 边界、P0-3）。
  - **API digest 解析规则（MUST）**：取 `releases/latest`（或回退 `releases?per_page=10`）响应 `.assets[]` 中按 `assetName` 精确匹配条目的 `digest` 字段；格式须为 `sha256:<64hex>`，剥 `sha256:` 前缀取 64hex 写入 `expectedSha256`；digest 为 null 或字段缺失 → 视为 digest 不可用，回退 checksum asset（策略 3）。已实测 `anomalyco/opencode` v1.18.31 全 37 asset 均带 digest（opencode-windows-x64.zip → sha256:0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006）。
  - **checksum 文件解析规则（MUST，回应 GPT 4.5）**：
    1. 支持 sha256sum 两格式：`<hash>  <filename>`（双空格）与 `<hash> *<filename>`（` *`，binary 模式标记）。
    2. 单文件 `*.sha256`（仅一行 hash 或 `hash  filename`）亦支持。
    3. 按 `assetName` **精确匹配**条目（大小写不敏感，仅比文件名，忽略路径前缀）；未找到匹配 → 视为无 checksum（fallback 到双 hash SHOULD）。
    4. 忽略空白行与 `#` 注释行；hash 必须为 64 位十六进制，否则视为无效条目跳过。
    5. 多匹配处理（🟢 v0.2.12 P2-4：区分重复/冲突）：同名 asset 多条记录时——若 hash **相同**（重复条目）→ 取第一条 + fetch_run.log 记 warning；若 hash **不同**（同名冲突，checksum 文件本身异常）→ **不取第一条**，判 `DOWNLOAD_FAIL|<cli> checksum-mismatch`（fail-closed，防静默掩盖异常 checksum 文件）。
  - **直连回退时序**：加速 URL 失败 → 直连 GitHub 重试一次 → 仍失败 → `DOWNLOAD_FAIL|<cli> <cause>`。
  - **回退方向不对称说明（回应 GPT 4.3/8）**：普通下载失败走"反代→直连"（反代是主链路，加速优先）；双 hash 缺一方时允许"直连不通→仅反代+standalone 标注"（反代已是唯一可用源，方向反转是降级而非冲突）。两者场景不同、方向相反的合理性在于：前者"主链路失效切备用"，后者"备用不可达时兜底记录"。非矛盾。
  - **关于"自维护受控 manifest"（驳回 GPT#1 方案1）**：不采用。与"自动跟随 latest"矛盾（opencode 发版后无法自动获知官方 sha256，需人工维护 manifest）；manifest 受信任性回归原问题；checksum MUST + 双 hash SHOULD 已检出反代投毒且不引入人工步骤。
  - **已知坑（asset 名已实测闭合，回应 GPT P0-2）**：asset 名实测=`opencode-windows-x64.zip`、tag=v1.18.31、prerelease=false、全 asset 带 digest（§14-1 已闭合）；tag 列表接口曾现异常拼接，probe 仍需防御性处理。

### 5.3 `<name>-upgrade.json`（upgrade 产出，仅实际升级/重装时写）
```json
{ "specVersion":"0.2.15", "name":"codex", "runAt":"...", "runId":"<SHOULD>",
  "fromVersion":"0.152.0", "target":"0.154.0", "exitCode":0, "ok":true,
  "sha256":"<opencode必填，mise SHOULD>", "error":null }
```
不升级分支不写不覆盖本文件。`target` 字段取值（🔴 v0.2.9，回应 anthropic P0-1）：ACTIONABLE 分支 `target=remote.latest`（升级目标）；REPAIR 分支 `target=remote.latest`（重装目标，§7.3 REPAIR target 规则）——两分支 target 来源一致。`fromVersion`：ACTIONABLE=`local.version`；REPAIR=`local.version`（可能 null，opencode staging 空时记 null）。verify `matchesTarget` 对比此 `target`（§5.4）。

### 5.4 `<name>-verified.json`（verify 产出；晋升凭证）
```json
{ "specVersion":"0.2.15", "name":"codex", "channel":"mise", "runAt":"...", "runId":"<本轮uuid, MUST>",
  "version":"0.154.0", "exePath":"...", "bytes":298169136,
  "sha256":"<opencode必填，mise SHOULD>",
  "healthy":true, "matchesTarget":true }
```
- **晋升三重约束**：① 新鲜度（🟡 v0.2.13 CB-P2-4 收紧：`runId == current-run.runId` 为**唯一必要条件**；仅 runId **字段缺失**时回退 `runAt ≥ current-run.startAt`——runId 存在但不匹配则恒不新鲜，runAt 不放行，防时钟回拨放过跨轮旧凭证）② 完整性（opencode：`verified.sha256` 非空，且 sync 复算 `sourceSha256 == verified.sha256`——同一 staging exe 的 hash 一致，凭证链成立；zip 下载完整性已由 upgrade 阶段 §5.2 策略闭合，sync 不再校验 zip hash）③ pin 未冲突（§5.7）。
- `sha256`：verify 阶段 SHOULD 计算（opencode 必填，mise SHOULD——数据源与 §5.5 `sourceSha256` 对齐）。
- verify 即装后功能测试：跑 `exe --version` + 计算 sha256。
- **失败不覆盖（P0-3，回应 GPT）**：verify 失败（`VERIFY_FAIL`）MUST NOT 写新鲜 runId 的 verified.json——防 sync 误判新鲜度而用失败轮凭证覆盖旧有效凭证；失败仅输出标记 + 写 `fetch_run.log`，旧 verified.json（若有）原封不动。同理 upgrade 非升级分支（`UPTODATE_SKIP`/`NO_REMOTE`/`LOCAL_AHEAD` 等）MUST NOT 写/覆盖 upgrade.json（§5.3 已声明，此处强化为 MUST 断言，供验收机械化）。
- **`matchesTarget` 比较基准（🟡 v0.2.8，回应 anthropic）**：`matchesTarget` 表示 verify 时实测版本是否与本轮判定目标一致，比较基准**按 upgrade 决策分支**取定，不统一用某单一来源：
  - `ACTIONABLE`/`REPAIR` 分支（写了 upgrade.json）：对比 `upgrade.json.target`；实测 `version == upgrade.json.target` → `true`，否则 → `false`（触发 `VERIFY_FAIL` version-mismatch）。
  - `UPTODATE_REFRESH` 分支（不写 upgrade.json，P0-3）：本轮无升级目标字段可对比，基准取 `local.version`；UPTODATE 前提即 `local.version == remote.latest`，verify 实测 `version == local.version` → `true`，否则 → `false`（`remote.latest` 与 `local.version` 理论相等，实测不等则 verify 健康但版本漂移，判 `false`）。
  - `matchesTarget==false` 在 verify 一律视 `VERIFY_FAIL`（version-mismatch），不得晋升；这把"升级后实测版本 ≠ 目标"和"刷新轮实测版本 ≠ 本地期望"统一拦在晋升闸外。

### 5.5 `sync.json`（sync 产出）+ 二进制证据链
```json
{ "specVersion":"0.2.15", "name":"sync", "runAt":"...", "runId":"<本轮uuid, MUST>",
  "runStatus":"success",
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
- **runStatus 顶层字段（🟢 v0.2.12 P2-1 引入；🟡 v0.2.13 CB-P2-2 语义收窄）**：`runStatus: "success"|"failed"`——语义为 **sync 本次执行的终态**，与 §8 `RUN_STATUS` 标记对齐。sync 完整执行到末步 → 写 `success`；sync 段内 fatal（骨架级错误）→ 由 sync 异常处理分支**原子写入** `runStatus:"failed"` 版本（`runId`=本轮、entries=fatal 前已处理条目，无则空数组；§5.8 原子写入，不存在"部分写"中间态）。**审计判据（MUST 联判）**："本轮完整成功" = `sync.json.runId == current-run.json.runId && sync.json.runStatus == "success"`；fatal 发生在 sync 之前（archive/probe/upgrade 段，如 `LOCKED|`）时 sync.json 保留旧轮内容，联判自然不通过。runStatus 仅为 sync 单段终态——"整轮是否被 fatal 腰斩"的完整审计仍须 `fetch_run.log`/archive 佐证（v0.2.12"单文件自洽、无 runStatus 字段=腰斩"的过强声明废除）。
- **二进制证据链**：`copy` entries MUST 携 `sourceSha256`（凭证 sha256）/`targetSha256`（copy 后 D 盘实测，须与 source 一致）/`previousSha256`（覆盖前 `.previous`）。opencode MUST 填；mise SHOULD 填（数据源 = verified.sha256）。`integrityNote` 记录 `ok` / `single-source` / `sha256-recomputed` 等。
- `action`：`copy` / `skip` / `target-locked`（🟡 v0.2.13 CB-P2-3：`SYNC_TARGET_LOCKED` 场景钉死 `action="target-locked"` + `reason` 必填，与 §8.1 对齐）。

### 5.6 `current-run.json`（archive-state 首步生成）
```json
{ "specVersion":"0.2.15", "name":"<cli-autoupdate>", "runId":"<uuid>", "startAt":"<UTCISO>", "archivedTo":"archive\\<ts>" }
```
注：`name` 此处为**任务名（非 CLI 名），固定值 `<cli-autoupdate>`**；`startAt` 替代 `runAt`（表本轮起点）。🟢 v0.2.15 GPT-P0-3：本字段与其他文件的 CLI 名语义不同，**验收断言 MUST 分开编写**（schema 独立行见 §5.9）。

### 5.7 `<cli>.pin`（可选，手动锁定目标版本）
```json
{ "specVersion":"0.2.15", "name":"codex", "pinVersion":"0.152.0", "reason":"user manual rollback", "setAt":"..." }
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

**specVersion 不匹配处理（🟡 v0.2.8，回应 anthropic——使 checklist A 节断言有契约依据）**：
- 读入 state 文件时若 `specVersion != 当前实现版本`（如读到 `"0.2.14"` 而本轮跑 `"0.2.15"`），**视为陈旧文件**：MUST NOT 作本轮决策依据消费（即本轮 probe/upgrade/verify/sync 的判定**不以旧 specVersion 文件内容为准**）。
- **行为分级**：
  - probe-local/probe-remote 类：本轮重新探测会自然覆盖旧文件（§5.1/§5.2 产出路径），不 fatal 终止——终止反破坏可用性（本任务目标是"让 CLI 可用"，旧 specVersion 不代表数据损坏，仅版本漂移）。
  - verified.json：旧 specVersion 的 verified.json **不作本轮晋升凭证**——sync 晋升三重约束①新鲜度（runId 唯一必要判据，仅字段缺失回退 runAt≥startAt）天然拦住跨轮旧凭证（旧轮 runId ≠ 本轮），specVersion 检查为第二道保险（防跨 specVersion 陈旧文件被误消费——🟡 v0.2.13 CB-P2-4 收紧后 runId 不匹配即不新鲜，同 specVersion 跨轮旧凭证已被 runId 判据拦住，specVersion 检查为纵深防御）。
  - upgrade.json：旧 specVersion 的 upgrade.json `target` 字段不作为 verify `matchesTarget` 基准（§5.4）——本轮若产生新 upgrade.json 则用新 `target`，若无（UPTODATE_REFRESH）用 `local.version` 兜底。
- **非 fatal、非 PARSE_ERROR**：与 schema 字段缺失/类型错的 `RUNTIME_ERROR_FATAL|schema`（文件损坏）区分——specVersion 不匹配是版本演进正常现象，文件本身完整可解析，仅"内容不再可信"。本轮覆盖写回当前 specVersion 即完成迁移，无需人工干预。
- checklist A 节"旧 specVersion 触发 fail-closed"断言据此修正为：**旧 specVersion → 不作决策依据消费 + 本轮覆盖（非 fail-closed 终止）**；fail-closed 仅针对 schema 损坏（字段缺失/类型错），不针对 specVersion 漂移。

### 5.9 字段级 schema 总表（与示例一一对应）

| 文件 | 字段 | 类型 | 必填 | 枚举/说明 |
|---|---|---|---|---|
| 全部 | specVersion | string | 是 | `"0.2.15"` |
| 全部（除 sync 外） | name | string | 是 | CLI 名或任务名（current-run，语义见其独立行）；sync.json 顶层用 `name:"sync"` 标识文件本身 |
| local/remote/upgrade | error | string\|null | 是 | null=无错；verified/sync/current-run/pin/npm-fallback 不带 error |
| local/remote/upgrade/verified/sync | runAt | ISO | 是 | current-run 用 startAt，pin 用 setAt，npm-fallback 用 lastUpdatedAt |
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
| | expectedSha256 | string\|null | 条件 | github-binary；64hex（剥前缀）；digest 主路径或 checksum 路径（🟢 v0.2.13 CB-P3-5）命中时落值，二者皆无=null |
| | checksumAssetUrl | string\|null | 是 | null=无 checksum（digest 不可用时 fallback） |
| | fallbackUsed | bool | 是 | |
| upgrade.json | fromVersion | string\|null | 是 | REPAIR 时可能 null（opencode staging 空，§5.3） |
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
| sync.json | runStatus | string | 是 | success/failed（🟢 v0.2.12 P2-1 引入；🟡 v0.2.13 CB-P2-2：sync 本次执行终态，"本轮完整成功"须联判 runId，见 §5.5） |
| sync.json | summary.probed/upgraded/synced/failed | int | 是 | |
| | entries[].name | string | 是 | 该条目对应 CLI 名 |
| | entries[].action | string | 是 | copy/skip/target-locked |
| | entries[].source/target/targetVersion | string | 条件 | copy 必填 |
| | entries[].bytes | int | 条件 | copy 必填 |
| | entries[].sourceSha256/targetSha256/previousSha256 | string\|null | 条件 | opencode copy 必填，mise SHOULD |
| | entries[].integrityNote | string\|null | 条件 | ok/single-source/sha256-recomputed |
| | entries[].reason | string\|null | 条件 | skip/target-locked 必填（🟡 v0.2.13 CB-P2-3） |
| | entries[].ok | bool\|null | 条件 | copy 必填 |
| current-run.json | name | string | 是 | 🟢 v0.2.15 GPT-P0-3：**任务名（非 CLI 名），固定 `<cli-autoupdate>`**——与其他文件的 CLI 名语义不同，验收断言 MUST 分开编写 |
| current-run.json | startAt | ISO | 是 | 替代 runAt（格式见 §5 时间字段序列化格式） |
| | archivedTo | string | 是 | |
| pin | pinVersion | string | 是 | |
| | reason | string | 否 | |
| | setAt | ISO | 否 | 替代 runAt |
| opencode-npm-fallback.json | consecutiveSyncSuccess | int | 是 | 0-10；连续 sync 成功轮数（§10.5）；🟡 v0.2.13 CB-P2-1：`uninstalled==true` 后**完全冻结**（成功不增、失败不归零，定格 10） |
| | lastUpdatedAt | ISO | 是 | sync 末步更新时间 |
| | uninstalled | bool | 是 | true=已执行 npm uninstall（幂等防重复） |
| run.lock | runId | string(uuid) | 是 | 与 current-run.runId 同值（§6 ownership 判据）；🟢 v0.2.14 CH-P1-1 |
| | start | ISO | 是 | 本轮起点（与 current-run.startAt 同语义） |
| | beat | ISO | 是 | 最近续锁心跳时间（UTC，'o' 序列化） |
| | pid | int | 是 | 争锁进程 PID（陈锁死亡判据之一，§6） |
| | processStartTimeUtc | string | 是 | UTC 'o' round-trip，恒 7 位小数 + `Z` 后缀（DateTime 序列化实测自洽，🟢 v0.2.14 CH-P1-3）；陈锁接管比对值（§6） |

> **run.lock 格式声明（🟢 v0.2.14 CH-P1-1）**：run.lock 为 §6 运行时锁文件，存储格式 = **JSON**（UTF-8；ConvertTo-Json 序列化 / ConvertFrom-Json 反序列化——§6 伪代码 `$lock.<field>` 访问语义的前提）。作为互斥结构**不带 specVersion/name**（不适用本表"全部"行），不参与 §11 归档。字段见上表 run.lock 行；`processStartTimeUtc` 格式契约（UTC 'o'、7 位小数）自 CB-P1-2 钉死，本表为其 schema 级落点，验收断言不再漏 run.lock。
>
> **时间字段格式总注（🟢 v0.2.15 GPT-P1-1）**：本表所有 ISO 类型时间字段（`runAt`/`startAt`/`setAt`/`lastUpdatedAt`/`beat`/`mtime`）MUST 以 UTC 'o' round-trip（恒 7 位小数 + `Z`）序列化——格式契约与比较规则见 §5 时间字段序列化格式；`run.lock.processStartTimeUtc` 原有契约（CB-P1-2/CH-P1-3）不变，与本注同源。

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

**未来增强（非本版本范围，🟢 v0.2.15 GPT-§4）**：若未来把"上游真实性"纳入保护范围，可行路线 = GitHub release attestations（`gh release verify` / `gh release verify-asset` 校验 release/asset digest 与 attestation subject 一致性——命令存在性经 GitHub CLI manual 检索确认 2026-09-17，**未在本机实测**）或上游自签名（RSA/Ed25519）。本版本仍只做 digest/sha256/双 hash/ZipSlip，不实现 attestation 验证；此节把"不做"升级为"现有路径 + 未来升级路线"，供后续版本评估。

---

## 6. 运行锁模型（runId ownership）+ 恢复手册

- **争锁**（archive-state 首步）：`[IO.File]::Open(run.lock, FileMode::CreateNew, FileAccess::ReadWrite, FileShare::None)` 原子争锁；写 `runId/start/beat/pid/processStartTimeUtc`（🟢 v0.2.14 CH-P1-1：run.lock 存储格式钉死为 **JSON**，字段 schema 见 §5.9 run.lock 行），runId 写入 `current-run.json`。🔴 **v0.2.12 P0-2（升 MUST）**：`processStartTimeUtc` **MUST 写入**（取争锁进程自身的 `Process.StartTime.ToUniversalTime()`）——陈锁接管逻辑 MUST 依赖此字段判进程实例同一性（旧版 v0.2.11 定 SHOULD 但接管段写 MUST 比对，字段缺失则无对象可比，契约断裂）。PID 可能被 OS 重用（短命进程退出后新进程恰好分到同 PID），`processStartTimeUtc` 是进程实例的唯一性副证。🔴 **v0.2.13 CB-P1-2（序列化钉死）**：写入时 MUST 序列化为 **UTC round-trip（`'o'`）格式**（如 `2026-09-16T02:11:03.1234567Z`，保留完整 tick 精度、`Z` 后缀）——读侧 Ticks 比较的前提；格式不合契约的锁值按"字段无效"保守处理（见伪代码格式校验前置）。🟢 **v0.2.14 CH-P1-3（Cherry P1-3 驳回，实测证伪并固化）**：锁值来源 `Process.StartTime` 为 **DateTime** 类型（实测 `System.DateTime`），DateTime 的 `'o'` 格式**恒输出 7 位小数**——整秒对齐输出 `.0000000`（实测：整秒值经 ToUniversalTime + `'o'` → `...03.0000000Z`；Kind=Local 路径 → `...03.0000000+08:00`，小数段 7 位与 Kind 无关），与读侧 `\.\d{7}Z` 校验**自洽**，Cherry 预测的"整秒边界永不 TAKEOVER"断档在实机行为中不存在（其推断"'o' 省略尾随零"系 DateTimeOffset 格式哲学的移植，且实测 PS 7.6.4 上 DateTimeOffset 的 `'o'` 亦恒 7 位）。**MUST NOT 以 DateTimeOffset 序列化锁时间**：其实测 `'o'` 输出后缀为 offset 形态（`.0000000+00:00`），无 `Z`，恒不匹配读侧正则 → 保守 LOCKED（fail-safe 但使陈锁接管失效）。
- **续锁**（后续每段）：open 锁文件独占 → 读 runId → 与 `current-run.json` 比对 → 匹配刷新 beat；不匹配/被独占/锁文件消失 → `LOCKED|`。
- **陈锁接管**：beat 超 30min **且** PID 经下列伪代码确认死亡 → 删锁重争；不确定 → 保守 `LOCKED|`。

**🔴 v0.2.12 P0-1（修正 v0.2.11 回归——锁接管逻辑写反，改伪代码钉死）+ 🔴 v0.2.13 CB-P1-1/CB-P1-2（闭合伪代码两处 fail-open 缺口）**：
> v0.2.11 把"StartTime 匹配→同一实例仍存活"误写成"匹配→确认已死→接管"，会导致误接管**仍存活**进程的锁（两进程同时持锁写 state/D 盘，数据损坏级风险）。按 Windows 进程语义：`Get-Process -Id <pid>` 命中＝该 PID 当前有活跃进程；StartTime 匹配锁内值＝**同一进程实例仍存活**（不可接管）；StartTime 不匹配＝PID 被新进程复用、原进程已退出（可接管）。v0.2.12 以伪代码钉死方向后，CodeBuddy 审计（2026-09-16）指出伪代码仍有两处 fail-open：① catch 吞并**全部**异常——锁内 pid 为 null/非法（锁半写，§14-10 自认崩溃场景）实测抛 `ParameterBinding*` 而非"进程不存在"，被同路径误判"已死→TAKEOVER"；② `-eq` 时间比较未规定序列化/归一化——实测 string 形态比较同一时刻恒 False（`Kind` 语义差异），落入 else→TAKEOVER 误接管。v0.2.13 以**异常分型 + 格式校验前置 + Ticks 层比较**闭合（异常分型/格式/比较行为均 2026-09-16 PS 7.6.4 实测）：

```powershell
# 陈锁接管判定（beat 超 30min 前提下）
# CB-P1-2 前置：锁时间字段格式校验（写侧契约 = UTC 'o' round-trip，tick 精度，'Z' 后缀）
$lockTimeUtc = $null
if ($lock.processStartTimeUtc -is [string] -and
    $lock.processStartTimeUtc -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$') {
    try {
        $t = [datetime]::Parse($lock.processStartTimeUtc,
              [Globalization.CultureInfo]::InvariantCulture,
              [Globalization.DateTimeStyles]::RoundtripKind)
        if ($t.Kind -eq 'Utc') { $lockTimeUtc = $t }   # 归一化为 UTC DateTime
    } catch { }   # 解析失败 → 保持 $null → 走保守分支
}
# 字段缺失 / 非法格式（本地偏移、精度截断、非字符串、解析失败）→ $lockTimeUtc 为 $null

# CB-P1-1：查询异常分型（仅"PID 无活跃进程"证明死亡，其余异常均未证明）
$proc = $null; $lookupUnknown = $false
try { $proc = Get-Process -Id $lock.pid -ErrorAction Stop }
catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
    # PID 无活跃进程 → 唯一"已证明死亡"的异常分型（实测：PID 不存在抛此类型）
}
catch {
    # pid 为 null/非法（ParameterBinding*，锁半写场景）、权限拒绝等 → 未证明死亡
    $lookupUnknown = $true
}

if ($null -eq $lockTimeUtc) {
    # v0.2.12 P0-2 fallback + CB-P1-2 格式校验：字段缺失/格式不合契约 → 不确定，保守不抢
    $verdict = 'LOCKED'   # 等人工清锁（§6 恢复手册）
}
elseif ($lookupUnknown) {
    # CB-P1-1：查询异常（非"进程不存在"）→ 未证明死亡 → 保守不抢
    $verdict = 'LOCKED'
}
elseif ($null -eq $proc) {
    # 查询正常返回且未命中 → PID 当前无活跃进程 → 原锁进程已死 → 允许重争
    $verdict = 'TAKEOVER'  # 删锁重争
}
elseif ($proc.StartTime.ToUniversalTime().Ticks -eq $lockTimeUtc.Ticks) {
    # CB-P1-2：Ticks 层比较（MUST NOT 以 string/DateTime 直接 -eq——存在 Kind/精度二义性）
    # 匹配 → 同一进程实例仍存活（可能卡死/未写心跳）→ 不抢
    $verdict = 'LOCKED'    # 不抢锁，等下一轮或人工
}
else {
    # PID 命中但 tick 不匹配（锁值已通过格式校验，非精度/形态误差）→ PID 被新进程复用
    # → 原进程已退出 → 允许重争
    $verdict = 'TAKEOVER'  # 删锁重争
}
# TAKEOVER → 删 run.lock 重新 CreateNew 争锁；LOCKED → 本轮 blocked，不抢
```

- **不变量（v0.2.13 修订）**：`TAKEOVER` 仅在两个**已证明**死亡的分型发出——"查询正常且 PID 无活跃进程"（`ProcessCommandException` 分型）或"PID 命中但 tick 不匹配（锁值已过格式校验）"。`LOCKED` 涵盖"同一实例仍存活""字段缺失/格式不合契约""查询异常未证明死亡"——均 fail-closed 不抢。异常分型 + 格式校验 + Ticks 比较把误接管（假阳性）压到零：任何"原进程可能仍存活"或"证据形态不可信"的情况都判 LOCKED。
- **释放**：sync 末步或异常分支，确认 runId 匹配后删锁。

> **锁空转处置**：`LOCKED|` 统一涵盖独占/崩溃残留/锁文件消失。fail-closed → blocked，**不人工抢锁**。最坏 30min 停摆窗口。
>
> **锁恢复手册（硬约束）**：SOP MUST 含"人工介入清锁"章节，仅当**全部**满足才允许清 `run.lock`：① 无活跃 `pwsh`/`mise`/下载进程；② D 盘权威入口未写一半（exe 与 `.previous` 字节完整可 `--version`）；③ `archive-state` 未执行（无 `*.tmp` 残留、`archive/<未完成时间戳>/` 不存在或完整）；④ 锁内 beat 超 30min 或 PID 确认死亡。满足后 move_to_trash 清锁，下一轮自然重争。任一不满足 → 等待不抢锁。

---

## 7. 模块清单

### 7.1 共享库 `cli-common-v0.2.15.ps1`
`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`，异步排空 stdout/stderr 再 WaitForExit+Kill；超时 mise ls-remote 60s / upgrade 600s / exe --version 30s）、`Compare-SemVer`、`Get-CherryMiseEnv`/`Get-MiseExePath`/`Get-MiseInstallsDir`/`Get-NpmPrefix`、GitHub 加速/直连 URL 构造器 + `gh auth token` 读取、**zip 安全解压**（§7.2 ZipSlip）、SHA256 计算、checksum 文件解析（§5.2 MUST 规则）、健康检查分型、运行锁原语、状态文件原子写入助手、runId 生成与读取、凭证新鲜度判据（runId 唯一必要；仅字段缺失时 runAt 兜底——🟡 v0.2.13 CB-P2-4）、**时间字段序列化/解析/格式校验助手**（🟢 v0.2.13 CB-P1-2 引入锁字段、🟢 v0.2.15 GPT-P1-1 扩展至全部时间字段：UTC 'o' 序列化、RoundtripKind 解析、格式正则校验）、pin 读取。

**Cherry mise 环境契约（🟢 v0.2.15 GPT-P0-1，消除 staging 路径省略号解释空间）**：
- **常量精确值**（§2/§4 的 `E:\...\CherryStudio\...` 即下列值，省略号写法废除）：`Get-MiseInstallsDir()` = `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs`（claude/codex staging 根）；`Get-MiseExePath()` = `C:\Users\JasonPC\.cherrystudio\bin\mise.exe`；`Get-NpmPrefix()` = `E:\Users\WIN_11\AppData\Roaming\npm`；`Get-CherryMiseEnv()` 返回七键 `[ordered]` 常量：`MISE_DATA_DIR`=`E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise`、`MISE_CONFIG_DIR`=`…\mise\config`、`MISE_SHIMS_DIR`=`…\mise\shims`、`MISE_CACHE_DIR`=`…\mise\cache`、`MISE_STATE_DIR`=`…\mise\state`、`MISE_YES`=`1`、`MISE_NO_ANALYTICS`=`1`。
- **取值来源与形态**：Cherry Studio 注入环境实测（legacy `cli-common.ps1` 注释 verified 2026-09-16；本轮 2026-09-17 实测复核：mise 根/installs/claude 2.1.273/codex 0.154.0/mise.exe/npm prefix 均在盘上存在）。实现为**常量返回（getter 函数）而非运行时推导**——Cherry 的 mise 装在自定义 Toolchain 目录（**非**默认 `%LOCALAPPDATA%\mise`），且 `MISE_*` 不在普通 shell 环境变量内（实测），故不存在"推导算法/推导失败"分支；"失败标记"问题由下方失败语义回答。
- **mise 子进程 MUST 带 MISE_\* env**（`Invoke-Proc -ExtraEnv (Get-CherryMiseEnv)`）——否则 mise 查默认位置、找不到 installs（实测 2026-09-16）。
- **probe-local 文件系统扫描不依赖 MISE_\* env**：直接扫 `Get-MiseInstallsDir()\<tool>\` 目录树（取最高 semver 版本目录，按 ExeRelPath 定位 exe）。ExeRelPath 实测结构（2026-09-17 复核）：claude=`claude.exe`（`installs\claude\<ver>\claude.exe`）；codex=`bin\codex.exe`（`installs\codex\<ver>\bin\codex.exe`）。
- **失败语义（不新增标记）**：staging 目录缺失/为空 → §5.1 语义（`LOCAL_EMPTY|`、broken → REPAIR 通道）；mise 环境不可用（exe 缺失 / 子进程非零退出）→ 沿既有 `UPGRADE_FAIL|` / `REMOTE_FAIL|` 上报，fail-closed 如实汇报。

**Compare-SemVer 正规化与比较规则（🟡 v0.2.11 P0-3，回应 GPT——消除实现期"同输入不同分支"验收争议）**：
- **输入正规化**：① 去 `v`/`V` 前缀（`v1.2.3`→`1.2.3`）；② 前后空白 trim；③ **段数必须恰为 3**（`Major.Minor.Patch`）——缺 patch（`1.2`）或缺 minor（`1`）→ 返回 incomparable；多于 3 段（`1.2.3.4`）→ 返回 incomparable；④ 三段必须全为非负整数（`1.2.x`/`1.2.-3`/`1.2.+4`→incomparable）；⑤ **build 元数据**（`+` 段，如 `1.2.3+build.7`）→ **剥除后比较**（忽略，非 incomparable，与 SemVer 规范一致）；⑥ **prerelease**（`-` 段，如 `1.2.3-rc.1`/`1.2.3-preview`/`1.2.3-beta`）→ 存在 `-` 段即视为 prerelease，prerelease < 同号 stable；两个 prerelease 互相比较时按 **SemVer 2.0.0 §11 precedence 规则**（🟡 v0.2.12 P1-4：原 v0.2.11 "不强制唯一性"与测试表"MUST 照表打"矛盾，改采标准规则使第 8 条 MUST 自洽）：按 `.` 分段比较——数字段按数值比较、非数字段按 ASCII 字典序比较、**数字段恒小于非数字段**、字段数少者小于多者（`rc.1`<`rc.2` 因数值 1<2；`alpha`<`beta` 因 ASCII；`rc.1`<`rc.beta` 因数字段<非数字段）；⑦ `null` 输入由**调用方前置判空**（§7.3 条件2 null 处理），函数本身不接 null，非 null 但不匹配上述正规化的字符串 → incomparable。
- **返回值**：`-1`（左<右）/`0`（相等）/`1`（左>右）/`"incomparable"`（不可解析比较，§7.3 条件2 拦截）。
- **不变量**：相等返回 `0` 仅当三段全等且 prerelease 段一致（build 元数据已忽略）。prerelease 与 stable 间：prerelease 恒 < 同号 stable。

**Compare-SemVer 测试表（MUST，验收照表打）**：

| # | 左 (a) | 右 (b) | 期望返回 | 说明 |
|---|---|---|---|---|
| 1 | `1.2.3` | `1.2.3` | `0` | 完全相等 |
| 2 | `v1.2.3` | `1.2.3` | `0` | `v` 前缀去 |
| 3 | `1.2.3` | `1.2.4` | `-1` | patch 差 |
| 4 | `1.3.0` | `1.2.9` | `1` | minor 差优先 |
| 5 | `2.0.0` | `1.9.9` | `1` | major 差优先 |
| 6 | `1.2.3-rc.1` | `1.2.3` | `-1` | prerelease < stable |
| 7 | `1.2.3` | `1.2.3-rc.1` | `1` | stable > prerelease |
| 8 | `1.2.3-rc.1` | `1.2.3-rc.2` | `-1` | prerelease 间序（实现须稳定，验收固定此例） |
| 9 | `1.2.3+build.7` | `1.2.3` | `0` | build 元数据忽略 |
| 10 | `1.2` | `1.2.3` | `incomparable` | 缺 patch |
| 11 | `1.2.3.4` | `1.2.3` | `incomparable` | 多于 3 段 |
| 12 | `1.2.x` | `1.2.3` | `incomparable` | 非数字段 |

### 7.2 每 CLI 一套（4 拆模块）

| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver → 全字段 + runId(SHOULD) + sha256 SHOULD | 扫 `staging\opencode\<ver>\` → 全字段 + runId(SHOULD) + sha256 |
| `probe-remote-<cli>.ps1` | `mise ls-remote --json`；失败写 `latest:null,error` | `releases/latest` + 失败回退；记录 sourceUrl/directUrl/assetDigest/expectedSha256/checksumAssetUrl；认证 token 提额；403 限流 → `RATE_LIMITED|` |
| `upgrade-<cli>.ps1` | 读 local+remote → 判 behind（§7.3 if-elif）；ACTIONABLE=`mise upgrade <tool>@latest`，REPAIR=`mise install <tool>@<remote.latest> --force`（🔴 v0.2.10 D4：`<ver>` 收敛为 `<remote.latest>`，与 §7.3 条件5/§5.3 对齐） | 读 remote → 下载（§5.2 完整性策略：digest 主路径 + checksum 解析 fallback）→ **ZipSlip 安全解压** → staging exe 计算 sha256 |
| `verify-<cli>.ps1` | 重扫 mise installs → 全字段 + runId(MUST) + sha256 SHOULD | 跑 staging exe `--version` → 全字段 + runId(MUST) + sha256 |
| `sync-v0.2.15.ps1`（共享） | 遍历三 CLI verified.json → 三重约束判定 → copy + 字节/sha256 复核 + `.previous` 备份 + 证据链 + summary 汇总 + opencode npm fallback 计数更新（§10.5） | 同左 |

**ZipSlip 解压安全约束（硬约束）**：opencode zip 解压 MUST 满足：① 目标限定 `staging\opencode\<ver>\` 子树；② 拒绝含 `..\` / 绝对路径 / symlink / junction 的 entry；③ 发现非法 entry → 中止解压、清理已解压文件、`DOWNLOAD_FAIL|<cli> zip-slip`、不写 verified.json；④ 解压后校验目标 exe 存在且 > 1MB。

**sync 异常隔离硬约束**：sync 内**每个 CLI 的 copy 逻辑 MUST 用独立 try/catch 捕获**，单 CLI 的 copy/复核/备份失败 MUST NOT 向上冒泡终止整轮。具体：
- CLI 级 copy 失败（IO 错误/复核不过/`.previous` 备份失败/目标锁定）→ recoverable 标记该 CLI，继续下一个。
- 骨架级失败（锁争取/续取失败/sync.json schema 校验失败/汇总计算异常/summary 无法落盘）→ `RUNTIME_ERROR_FATAL|` 终止整轮。
- 实现 MUST 用 `ForEach ($cli in $clis) { try { <copy> } catch { <recoverable 标记>; continue } }` 粒度，禁止循环外统一 catch。

### 7.3 behind 判定与版本规则（upgrade 内部）
读 `local.json` + `remote.json`（条件7/8 另需读 `verified.json` + `current-run.json` 判凭证新鲜度，🔴 v0.2.10 D3 补全输入清单）→ **按下列顺序 if-elif 评估，命中即止（自上而下优先级）**：

| # | 条件 | 标记 | 动作 |
|---|---|---|---|
| 1 | remote.latest == null | `NO_REMOTE\|<cli> <cause>` | 读不到 target，不执行，跳过 verify |
| 2 | local.version 与 remote.latest 均非 null，但 Compare-SemVer 返回 incomparable（格式坏，非空） | `VERSION_FORMAT_ERROR\|<cli> <raw>` | 不执行，跳过 verify |
| 3 | target 为 prerelease | `TARGET_PRERELEASE\|<cli> <v>` | stable-only 拒绝，跳过 verify |
| 4 | local.healthy == false 且 healthDetail == probe-error | `PROBE_ERROR\|<cli> <reason>` | 不重装，跳过 verify |
| 5 | local.healthy == false 且 healthDetail == broken | `REPAIR\|<cli> <reason>` | 强制重装（mise: `mise install <tool>@<remote.latest> --force`；opencode: 下载 `remote.latest` 解压到 staging）。**REPAIR target = remote.latest**（🔴 v0.2.9，回应 anthropic P0-1） |
| 6 | local < remote 且 target stable | `ACTIONABLE\|<cli> <from>-><to>` | 执行升级 → 进 verify |
| 7 | local == remote 且 **有本轮新鲜凭证** | `UPTODATE_SKIP\|<cli> <v>` | 不执行、不写 upgrade.json、跳过 verify |
| 8 | local == remote 且 **无本轮新鲜凭证**（凭证缺失 / 不新鲜 / `verified.version ≠ local.version`） | `UPTODATE_REFRESH\|<cli> <v>` | 不执行升级，仍运行 verify（刷新凭证） |
| 9 | local > remote（双方可解析） | `LOCAL_AHEAD\|<cli> <local> > <remote>` | 不执行，跳过 verify |
| else | 1–9 均未命中（防御性，正常不可达） | `RUNTIME_ERROR\|<cli> branch-undefined` | recoverable 标记，跳过 verify；写 fetch_run.log warning |

**顺序说明**：1-3（远端/格式/策略前提）优先于本地健康检查（4-5），本地健康检查优先于版本比较（6-9）。同一条件多分支同时满足，按表号小者优先。

**条件7/8 互补与可达性（🔴 v0.2.10 D3，回应 CodeBuddy——闭合"无分支命中"空洞）**：
- **时序前提**：§9 状态机每轮 `upgrade → verify` 顺序执行一次。upgrade 执行时点，**本轮 verify 尚未运行**——故 upgrade 读到的 `verified.json` 必然来自上一轮（runId/runAt 均为上轮），按 §5.4 新鲜度判据（🟡 v0.2.13 CB-P2-4：runId 唯一必要条件，仅字段缺失回退 runAt）**跨轮首次调用恒不新鲜**（旧轮 runId ≠ 本轮）。
- **由此原条件7"有本轮新鲜凭证"在跨轮首次调用中恒不成立（死分支）**；原条件8"凭证缺失或 `verified.version≠local.version`"在"上一轮凭证存在且 `verified.version==local.version`"（连续两轮 UPTODATE 常态）时亦不成立——1–9 全不命中，无 else 兜底，行为未定义（违反 §1 原则3 固定状态机 + §15 九分支全覆盖验收前提）。
- **修订（条件7/8 改为互补）**：条件7 = `local==remote` 且**有本轮新鲜凭证**→`UPTODATE_SKIP`；条件8 = `local==remote` 且**无本轮新鲜凭证**（缺失 / 不新鲜 / `verified.version≠local.version` 任一）→`UPTODATE_REFRESH`。二者在 `local==remote` 下完备互补，空洞消除。
- **`UPTODATE_SKIP` 的可达范围**：仅**同轮内重复调用 upgrade**（如 §13 穿插 re-probe：本轮 verify 已产出新鲜凭证后再次进入 upgrade）可达——此时本轮新鲜凭证存在，SKIP 跳过冗余 verify，为真幂等。**跨轮稳态 UPTODATE 走 `UPTODATE_REFRESH`**（每轮刷新凭证，跑 `--version` + sha256；成本可接受，与 §13-2 首轮 seed 路径一致——seed 亦依赖 refresh 产凭证）。
- **else 兜底**：追加 `RUNTIME_ERROR|<cli> branch-undefined`（recoverable），保证九分支穷尽，正常流程不可达。

**条件2 的 null 处理（🔴 v0.2.8 消歧，回应 anthropic 阻塞项）**：条件2（版本不可解析）仅在 `local.version` 与 `remote.latest` **均非 null** 时判定。`local.version==null`（opencode staging 空 / `healthDetail=broken` 导致，§5.1）**不计入"不可解析"**——null 是"无版本"非"格式坏"，Compare-SemVer 对 null 输入 MUST NOT 返回 incomparable 拦截，upgrade 须先判 null 跳过条件2，直接下沉至条件4/5（healthy 检查）。否则：staging 空→`version=null`→条件2 命中→`VERSION_FORMAT_ERROR`→永远走不到条件5 `REPAIR`→**首次 seed 卡死**（§13 迁移、§3 实机现状依赖此路径）。Compare-SemVer 实现须：null 输入由调用方（upgrade）前置判空，函数本身仅对非 null 但不可解析的字符串返回 incomparable。

**REPAIR 的 target 取值（🔴 v0.2.9，回应 anthropic P0-1）**：条件5 REPAIR 的重装目标**统一为 `remote.latest`**，两通道对齐——mise `mise install <tool>@<remote.latest> --force`，opencode 下载 `remote.latest` 解压。语义为"既然要重装，顺便修到当前 stable 最新"。此选择覆盖以下边界：
- **broken + local<remote**（ACTIONABLE 同时成立）：REPAIR 优先于 ACTIONABLE（条件5 先于条件6），target=remote.latest 一次性"修+升"，ACTIONABLE 被吸收，不留到下轮。
- **broken + opencode staging 空**：staging 无本地版本可"修回原版本"，必用 remote.latest 下载——opencode 通道的 REPAIR 隐含 target=remote.latest，mise 通道显式对齐。
- **broken + local>remote**（LOCAL_AHEAD 同时成立）：REPAIR 优先（条件5 先于条件9），target=remote.latest 意味着重装到比 broken 本地更旧的 stable——可接受（broken 的较新版本无价值，修到当前最新 stable；healthy+ahead 才走 LOCAL_AHEAD 保留，§7.3 条件9）。
- REPAIR 写 `upgrade.json.target = remote.latest`（§5.3），verify `matchesTarget` 对比该 target（§5.4）——基准闭环。
- **prerelease 边界**：若 `remote.latest` 本身为 prerelease，TARGET_PRERELEASE（条件3）先于 REPAIR 命中，不执行重装——此为 stable-only 策略后果，见 §14-11。

**策略说明**：stable-only 跟随 latest，不强制更新、不自动降级（降级用户手动 `mise use` 或建 pin）。`local > remote` 显式报告不静默跳过。agent 无差别调用。

### 7.4 版本号
共享库与 sync 文件名含 `-v0.2.15`；probe/upgrade/verify 每 CLI 一份，首行 `$ScriptVersion='0.2.15'` + `# SPEC: v0.2.15`。

---

## 8. 机器状态标记协议

每脚本 stdout 输出 ASCII 标记，agent 只读标记判分支，不解析 json、不心算。退出码：`0`=无事可做/已满足；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败；`3`=执行失败或复核不过。

> **🟡 v0.2.11 P0-1（exitCode 非权威 MUST）**：整轮成功/失败判定**各层一律以 `RUN_STATUS|...` stdout 标记为准**，exitCode **MUST NOT** 参与成功判定。理由：外部调度器/监控默认把 `exitCode != 0` 当失败，会误把 `2/3/10/11`（本 spec 的合法 recoverable/dry-run/产物已写码）标红，触发误告警/误重跑。对策：**MUST** 在 SOP/定时任务层明确"只解析 `RUN_STATUS` 标记判终态，exitCode 仅供人工/日志辅助"；spec 不改 exitCode 语义表（`11`=产物已写是验收机械化的判据之一，改 0＝破坏 §8.1 对照表）。agent 遇 `RUN_STATUS|success|` → 整轮成功；遇 `RUN_STATUS|failed|` → 整轮失败；二者均无 → 按保守 fatal 处理。

**标记行语法（🟢 v0.2.15 GPT-P0-2，MUST——agent 解析的可靠性基础）**：
1. 每个标记**独占一行**；标记名 MUST 位于**行首**（MUST NOT 有前导时间戳/日志级别/缩进）。
2. 标记名 = 行首至**首个** `|` 之间的 token；取值 MUST ∈ 本表第一列枚举（ASCII 大写字母 + 下划线）。
3. `|` 之后为 payload（至行尾）；payload 为空格分隔的字段（`<cli>` / `key=value` / 自由文本，逐标记结构见本表）。特例：`RUN_STATUS` 固定两段 `<status>|<summary>`。
4. 除 `RUN_STATUS` 外，payload MUST NOT 含 `|`（保证"首个 `|` 切分"无二义）；payload MUST NOT 含换行；payload MAY 含非 ASCII 字符（如中文路径——可读性优先，不做限制）。
5. 非标记的日志/说明行 MUST NOT 以"本表任一标记名 + `|`"形态开头（防误匹配；脚本如需在日志中引用标记名，须加前缀如 `NOTE:` 或改写措辞）。
6. agent 解析规则：逐行读取 → trim 行尾空白 → 以行首 token 匹配标记枚举；未识别的**普通日志行**忽略；未识别但形态疑似标记（含 `|` 且具失败语义）→ 按本表末注"未列出的 failed 类标记按 fatal 处理"保守兜底。

标记分两类：**fatal**（终止整轮）/ **recoverable**（标记该 CLI 失败后继续下一个）。

| 标记 | 产出脚本 | 类别 | 判定 |
|---|---|---|---|
| `LOCKED\|` | 任何段 | fatal | blocked，本轮终止 |
| `STATE_MISSING\|` | archive/probe-local | fatal | blocked，本轮终止 |
| `PARSE_ERROR\|` | 任何段 | fatal | failed，不写回原文件，本轮终止 |
| `RUNTIME_ERROR_FATAL\|<cause>` | 任何段（骨架级：锁争取/续取失败、state 文件 schema 校验失败、汇总异常） | fatal | 整轮终止。🔴 v0.2.10 D8：upgrade/verify 写 state 文件时回读校验失败（§5.8）亦产 FATAL，非仅 archive/sync |
| `RUNTIME_ERROR\|<cli> <cause>` | probe/upgrade/verify（CLI 级） | recoverable | 该 cli 失败，继续下一个 |
| `ARCHIVE_OK\|<runId>` | archive-state | 成功 | 争锁成功+归档完成（runId 已写 current-run.json）→ 进 probe（🟢 v0.2.14 CH-P1-2：补齐 archive-state 成功标记——此前唯一无 `*_OK\|` 的段，agent 判 OK 依据悬空） |
| `LOCAL_OK\|<cli> ver=<v> healthy=<bool> detail=<d>` | probe-local | 成功 | 阶段成功 |
| `LOCAL_EMPTY\|<cli>` | probe-local | 成功 | staging 空 → 进 upgrade |
| `REMOTE_OK\|<cli> latest=<v> fallback=<bool>` | probe-remote | 成功 | 阶段成功 |
| `REMOTE_FAIL\|<cli> <cause>` | probe-remote | recoverable | 该 cli 远端失败 → upgrade 读 latest:null → NO_REMOTE |
| `RATE_LIMITED\|<cli>` | probe-remote | recoverable | 403 + ratelimit-remaining:0 |
| `ALL_REMOTE_FAIL\|` | agent/SOP 聚合判定（🔴 v0.2.10 D9：非单 CLI 脚本产出） | 整轮级 | 三 CLI 全失败 → 跳 upgrade/verify，直进 sync。**产出者钉死**：probe-remote 为每 CLI 独立脚本，单脚本无法知晓"三 CLI 全失败"；由 agent/SOP 在三 CLI probe-remote 均失败后聚合判定（读三个 `<cli>-remote.json` 的 latest/error 或三个 recoverable 标记 RATE_LIMITED/REMOTE_FAIL），命中即路由直进 sync。**聚合口径（🟢 v0.2.9）**：`RATE_LIMITED` 与 `REMOTE_FAIL` **均计入"remote fail"**——三 CLI 中无论失败标记是 RATE_LIMITED 还是 REMOTE_FAIL，只要三者均失败即触发 ALL_REMOTE_FAIL |
| `UPTODATE_SKIP\|<cli> <v>` | upgrade | 成功 | 有本轮新鲜凭证（仅同轮 re-probe 可达，§7.3 D3），跳 verify |
| `UPTODATE_REFRESH\|<cli> <v>` | upgrade | 成功 | 无本轮新鲜凭证（缺失/过期/`verified.version≠local.version`），进 verify 刷新 |
| `ACTIONABLE\|<cli> <from>-><to>` | upgrade | 成功 | 有升级动作 |
| `REPAIR\|<cli> <reason>` | upgrade | 成功 | broken 触发重装 |
| `PROBE_ERROR\|<cli> <reason>` | upgrade | recoverable | probe-error 不重装，跳 verify |
| `TARGET_PRERELEASE\|<cli> <v>` | upgrade | recoverable | stable-only 拒绝，跳 verify |
| `NO_REMOTE\|<cli> <cause>` | upgrade | recoverable | 远端失败，跳 verify |
| `VERSION_FORMAT_ERROR\|<cli> <raw>` | upgrade | recoverable | 格式不可解析，跳 verify |
| `LOCAL_AHEAD\|<cli> <local> > <remote>` | upgrade | recoverable | 本地超前，跳 verify |
| `EXE_LOCKED\|<cli>` | upgrade | recoverable | 源 exe 在跑，跳过（🟢 v0.2.12 P2-3 SHOULD：检测方式＝试独占打开目标 exe 路径 `OpenExclusive` 失败 或 `Get-Process` 命中该 exe 路径进程） |
| `DISK_FULL\|<cli> <free>MB` | upgrade | recoverable | 盘空间不足，跳过（🟢 v0.2.12 P2-3 SHOULD 默认阈值：可用空间 < 500MB 触发；实现 MAY 调整但须记入 fetch_run.log） |
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

> 🟢 v0.2.15（回应 GPT-P1-3）：脚本输入/输出见 §7.2、分支判定路径见 §7.3/§9 状态机、失败不覆盖规则见 §5.4/§5.3——本节不重复这些信息、不另设"单页总览"（并列事实源信息零新增且易漂移）。

| 脚本 | 关键标记 | exitCode | 文件副作用（写/覆盖/不写） |
|---|---|---|---|
| archive-state | `ARCHIVE_OK\|<runId>`（🟢 v0.2.14 CH-P1-2） | 11 | 写 `current-run.json`（新建 runId）、`run.lock`、`archive/<ts>/` |
| archive-state | `LOCKED\|`/`STATE_MISSING\|`/`PARSE_ERROR\|` | 2 | 不写 current-run.json、不删旧 archive；未持锁不写 run.lock |
| archive-state | `RUNTIME_ERROR_FATAL\|<cause>` | 3 | 释放锁；不写 current-run.json |
| probe-local | `LOCAL_OK\|<cli>` | 11 | 覆盖 `<cli>-local.json`（带本轮 runId SHOULD） |
| probe-local | `LOCAL_EMPTY\|<cli>` | 11 | 写 `<cli>-local.json`（version=null, healthy=false） |
| probe-local | `RUNTIME_ERROR\|<cli>` | 3 | **不覆盖**旧 `<cli>-local.json`（P0-3 失败不覆盖） |
| probe-remote | `REMOTE_OK\|<cli>` | 11 | 覆盖 `<cli>-remote.json`（含 assetDigest/expectedSha256/checksumAssetUrl） |
| probe-remote | `REMOTE_FAIL\|<cli>`/`RATE_LIMITED\|<cli>` | 3 | 写 `<cli>-remote.json`（🔴 v0.2.10 D10：必填字段全落盘——latest/sourceUrl/directUrl/assetName/assetDigest/expectedSha256/checksumAssetUrl=null, fallbackUsed=false, error=<cause>） |
| agent/SOP 聚合 | `ALL_REMOTE_FAIL\|` | 不适用（聚合层无单脚本退出码） | 🟡 v0.2.12 P1-3：产出者=agent/SOP 聚合（§8 D9），非 probe-remote 脚本，无 exitCode；三 CLI probe-remote 均失败后聚合产出，路由直进 sync |
| upgrade | `ACTIONABLE\|`/`REPAIR\|` → `UPGRADE_OK\|` | 11 | 覆盖 `<cli>-upgrade.json`（fromVersion/target/sha256）。**target=remote.latest**（ACTIONABLE 升级目标 / REPAIR 重装目标，🔴 v0.2.9 P0-1）；REPAIR fromVersion 可能 null（opencode staging 空） |
| upgrade | `UPTODATE_SKIP\|`/`NO_REMOTE\|`/`LOCAL_AHEAD\|`/`PROBE_ERROR\|`/`TARGET_PRERELEASE\|`/`VERSION_FORMAT_ERROR\|` | 0 | **MUST NOT 写/覆盖** `<cli>-upgrade.json`（P0-3） |
| upgrade | `DOWNLOAD_FAIL\|`/`UPGRADE_FAIL\|`/`EXE_LOCKED\|`/`DISK_FULL\|` | 3 | **MUST NOT 写** upgrade.json（失败不覆盖） |
| verify | `VERIFY_OK\|<cli>` | 11 | 覆盖 `<cli>-verified.json`（新鲜 runId + sha256） |
| verify | `VERIFY_FAIL\|<cli>` | 3 | **MUST NOT 写新鲜 runId 的** `<cli>-verified.json`（P0-3，旧凭证不动） |
| verify | `RUNTIME_ERROR\|<cli>` | 3 | 不覆盖旧 verified.json |
| probe-local/probe-remote/upgrade/verify | `RUNTIME_ERROR_FATAL\|schema` | 3 | 🔴 v0.2.10 D8：state 文件原子写入回读校验失败（§5.8）→ 释放锁、不写回原文件、整轮终止（非 CLI 级 recoverable） |
| sync | `SYNC_COPY\|`/`SYNC_SKIP\|`（逐 CLI） | 0/11 | 覆盖 `<name>.exe` + `.previous` + 写 `sync.json.entries[]`；sync.json 末步覆盖；末步更新 `opencode-npm-fallback.json` 计数（§10.5） |
| sync | `SYNC_TARGET_LOCKED\|<cli>` | 0 | 该 CLI entry **action=target-locked**（🟡 v0.2.13 CB-P2-3：与 §5.5 枚举同名钉死，不再写 action=skip），sync.json 仍写 entry（reason 必填） |
| sync | `RUN_STATUS\|success\|<summary>` | 0 | 覆盖 `sync.json`（summary + entries + runStatus=success）+ 覆盖 `opencode-npm-fallback.json`（计数/uninstalled 幂等） |
| sync | `RUN_STATUS\|failed\|<cause>` | 2 | 仅 fatal 触发；🟡 v0.2.13 CB-P2-2：fatal 时由 sync 异常处理分支**原子写入** `runStatus:"failed"` 版 sync.json（runId=本轮，entries=fatal 前已处理条目，无则空数组——不存在"部分写"中间态，§5.8）；opencode-npm-fallback.json 计数按已跑的 opencode 条目结果更新（fatal 前已处理则更新，否则不动——§10.5 D5 唯一规则不变；🟢 v0.2.14 CH-P2-2：冻结态 `uninstalled==true` 下"更新"=no-op、保持定格 10 非归零，与 §10.5"完全冻结"一致） |

> exitCode 约定：`0`=无事可做/已满足/整轮成功；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败/整轮失败；`3`=执行失败或复核不过（CLI 级 recoverable）。**agent 以 stdout 标记为准**，exitCode 仅供人工/日志辅助判断。

### dry-run 定位
定时任务 prompt **一律 `-Execute`**。脚本支持 dry-run 供人工预演。

---

## 9. agent 编排契约（定时任务 SOP 状态机）

**状态机图**：
```
段A: archive + probe
  archive-state ──[LOCKED|/STATE_MISSING|/PARSE_ERROR|/RUNTIME_ERROR_FATAL]──→ fatal 终止
        │ OK（ARCHIVE_OK|<runId>，🟢 v0.2.14 CH-P1-2）
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

> **re-probe 可达性说明（🟢 v0.2.14 CH-P2-1）**：`UPTODATE_SKIP`（§7.3 条件7）仅在**同轮内重复调用 upgrade**（穿插 re-probe）时可达——标准单轮状态机中 upgrade 每轮每 CLI 恰调用一次，本轮 verify 未运行前无本轮新鲜凭证，跨轮稳态 UPTODATE 一律走 `UPTODATE_REFRESH`（§7.3 D3）。穿插 re-probe 属 SOP 可选步骤（触发时机由 SOP 定义，如汇报前幂等抽验），非本状态机标准节点。此注闭合 §7.3"可达范围"声明与 §9 状态机的覆盖缺口。

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
6. **pin mismatch 提醒（🟢 v0.2.12 P2-2，SHOULD）**：若某 CLI 存在 `pin` 但本轮 `SYNC_SKIP|pinned-mismatch`（`verified.version ≠ pinVersion`），收尾备注 SHOULD 显式提醒"该 CLI pin 连续未匹配，请确认 pinVersion 是否拼写错误或已超出保留窗口"（连续 N 轮未匹配阈值 N 由实现期定，spec 不硬定。🟢 v0.2.13 CB-P3-1：**"连续"判定数据源**＝回溯 `state/archive/` 最近 N 轮的 `sync.json` entries——该 CLI 条目 action=skip 且 reason 含 `pinned-mismatch` 即计一轮未匹配；不新增计数字段）。

### SOP 错误场景示例（MUST 覆盖）
网络全断、目标 exe 锁定、opencode 下载失败（含 digest-mismatch/checksum-mismatch/dual-hash-mismatch/zip-slip）、verify 失败不晋升、凭证缺失刷新（UPTODATE_REFRESH）、手动回退 pin（pinned-mismatch/修复性晋升）、被锁阻塞（含 §6 恢复手册步骤）、GitHub 限流（RATE_LIMITED）、**版本格式突变（VERSION_FORMAT_ERROR——🟢 v0.2.15 GPT-P1-2：上游发版违反三段 SemVer 致该 CLI fail-closed 持续不升级；agent 如实汇报不自动处置，人工介入路径见 §14-12）**。每例给"输入状态 → 标记序列 → agent 分支 → 汇报文本"。

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

**计数机制（🟡 v0.2.9，回应 anthropic P1-2——原 §10.5 仅定阈值未定义计数，名实不符）**：采用方案(a)轻量持久化计数文件 `state/opencode-npm-fallback.json`：
```json
{ "specVersion":"0.2.15", "name":"opencode", "consecutiveSyncSuccess":<int>,
  "lastUpdatedAt":"<ISO>", "uninstalled":false }
```
- **更新时机**：sync 末步（sync-v0.2.15.ps1 汇总后）更新。
- **成功计数**：本轮 opencode 条目 sync 成功（`SYNC_COPY` 或 `already-current` 幂等 skip）→ `consecutiveSyncSuccess += 1`。🟡 **v0.2.12 P1-5（封顶）+ v0.2.13 CB-P2-1（冻结规则统一）**：`uninstalled==true` 后**完全冻结**——成功不递增、**失败亦不归零**，定格 10（v0.2.12"失败仍归零"与"定格 10"矛盾，废除；归零条款仅适用 `uninstalled==false`）。计数目的已达成（触发卸载），字段此后仅作"已达成并卸载"的历史标记；卸载后的失败语义由 `sync.json` entries `ok=false` 与 `fetch_run.log` 记录。`uninstalled==false` 时正常累加（0→10 触发卸载）。
- **失败归零**：本轮 opencode sync 失败（copy 失败/复核不过/目标锁定/三重约束不满足且非 already-current 的 `SYNC_SKIP`）→ `consecutiveSyncSuccess = 0`。**注**：`ALL_REMOTE_FAIL` 不属"未跑 sync"——§8/§9 明确其直进 sync，opencode 条目走 `SYNC_SKIP`（无新鲜凭证，非 already-current）即归零，已被本条覆盖。**已卸载后失败（🟡 v0.2.13 CB-P2-1 修订）**：`uninstalled==true` 后失败**不归零**（完全冻结的一部分）——失败语义由 `sync.json` entries `ok=false` 与 `fetch_run.log` 记录；`uninstalled` 一旦 true 不回退。
- **🔴 v0.2.10 D5 唯一规则（闭合与 §8.1 冲突）**：计数更新**仅当 sync 完整执行到末步**（opencode 条目已处理）才发生——按上述 +1/归零。**fatal 中断（sync 未完整执行：`LOCKED|`/`STATE_MISSING|`/`PARSE_ERROR|`/`RUNTIME_ERROR_FATAL|` 在 sync 末步前触发）→ 不更新计数**（保持旧值，与 §8.1 `RUN_STATUS|failed` 行"fatal 前已处理则更新，否则不动"一致）。fatal 不归零——避免一次骨架级中断清掉累计进度。
- **卸载触发**：`consecutiveSyncSuccess >= 10` 且 `uninstalled==false` → 执行 `npm uninstall -g opencode`，置 `uninstalled=true`（幂等：已达 10 且 uninstalled=true 后续不再重复卸载）。
- **archive 不足 10 轮不阻断**：计数靠本文件持久化，不依赖 archive 回溯；首轮从 0 起累计。
- **归档**：本文件纳入 archive-state 归档范围（state/*.json）。

---

## 11. 可追溯

- 每轮首步 archive-state 归档 `state/*.json`（不含 run.lock、archive/、current-run.json、pin）到 `archive/<时间戳>/`。
- `fetch_run.log` 累积每轮 `[时间] runId=<id> probed=N upgraded=X synced=Y failed=Z`。
- sync.json.entries 携 sha256 证据链（source/target/previous + integrityNote）。
- spec/脚本/json 全带 specVersion；版本历史见 §16。

---

## 12. 与参照系差异（自检）

| 维度 | Software_Update_Monitor v0.2.2 | Release-Monitor | 本项目 v0.2.15 |
|---|---|---|---|
| 范围 | monitor-only | monitor-only | monitor+download+install+switch+rollback |
| 模块粒度 | — | 合并 monitor.ps1 | 4 拆模块 |
| 状态源 | Manifest+SQLite | md+result.json | state/*.json |
| 锁 ownership | — | PID 匹配 | runId 匹配 |
| 晋升闸 | — | — | 三重约束（新鲜度+完整性+pin） |
| 供应链 | — | — | checksum MUST + 双 hash SHOULD + ZipSlip + 证据链 + 威胁模型声明 |
| 形态 | 通用工具 spec | 个人定时监测 | 个人定时维护流程 |

---

## 13. v0.2.15 迁移项（首次执行）+ checklist

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
7. 现有散脚本（`.old/`）→ 按 §7 模块清单拆分重命名（-v0.2.15 / $ScriptVersion）。`.old/` legacy 脚本受仓库 AGPL-3.0 LICENSE 约束，新脚本沿用同 LICENSE（仓库既有）。
8. 产出 `cli-autoupdate-sop.md`（含 §6 锁恢复手册 + §9 错误场景示例）。

**配置/数据迁移**：无 config.json、无 SQLite/DB、无用户数据。状态 schema 跨版本靠 `specVersion` 标识。

---

## 14. 待确认 / 已知风险（v0.2.15 闭合状态，回应 anthropic v0.2.11 P0-1/P0-2 + GPT v0.2.10 P0-1/P0-2/P0-3 + CodeBuddy D1–D12 + CodeBuddy v0.2.12 审计 CB-P1~CB-P3 + Cherry v0.2.13 审计 CH-P1~CH-P2 + GPT v0.2.14 审计 GPT-P0~GPT-P1）

> **驳回 GPT"全部关闭§14"（过度）**：真未知风险（反代可靠性/PID 沙箱陈锁判定/极端时钟回拨）需实现期实测，伪声明"closed"反误导验收。此处区分**已闭合**（实测/规则已定）与**已知风险声明**（验收口径已定、待实现期实测兜底）。

**已闭合**（以下序号为**历史连续编号**、跨组不连续——历轮审计与正文交叉引用锚点，保留不重排，🟢 v0.2.14 CH-P2-3）：
1. ~~opencode GitHub release asset/tag/checksum 实测~~ → **已闭合（gh api 实测 2026-09-16）**：tag=v1.18.31、assetName=opencode-windows-x64.zip、prerelease=false、全 37 asset 带 digest（§5.2/§14-6 同闭合）。
4. ~~current-run.json 与 run.lock 一致性~~ → **已闭合**：一处损坏 → fail-closed 终止（§5.8/§6 已定验收口径）。
5. ~~opencode npm 全局卸载判据~~ → **已闭合**：N=10（§10.5 定死）。
6. ~~opencode 官方 checksum 覆盖率~~ → **已闭合（实测）**：anomalyco/opencode v1.18.31 全 37 asset 均带 API digest；digest 缺失走 checksum asset→双 hash fallback（§5.2 策略）。
7. ~~GitHub API 限流~~ → **已闭合**：认证提额 5000/h 足够；未认证 60/h 触发 `RATE_LIMITED|` 区分 + §9 铁律8（验收口径已定）。
9. ~~上游真实性不在保护范围~~ → **已闭合**：威胁模型声明（§5.10），API digest 亦不解决上游被攻破（digest 来自同一 release），属信任前提。

**已知风险声明（验收口径已定，待实现期实测兜底，不伪关闭）**：
2. **反代可靠性 + 双 hash 成本**：反代不可用回退直连；digest 主路径下双 hash 仅在 digest+checksum 均不可用时触发（成本上限收窄）。验收口径：反代失效→直连重试一次→仍失败 `DOWNLOAD_FAIL|`。反代长期可靠性待实现期实测。
3. **runId 锁模型实现细节**：续锁独占/消失统一 fail-closed（§6 已闭合到 SOP + 恢复手册）；陈锁接管 PID+startTime 双校验逻辑已用伪代码钉死（§6，🔴 v0.2.12 P0-1 修正 v0.2.11 回归；🔴 v0.2.13 CB-P1-1/CB-P1-2 闭合 catch-all 与时间比较两处 fail-open 缺口——异常分型 + 格式校验前置 + Ticks 比较，行为均 PS 7.6.4 实测）。`processStartTimeUtc` 升 MUST + 序列化钉死（UTC 'o'；🟢 v0.2.14 CH-P1-3：写读两侧 7 位小数自洽性**已实测闭合**——DateTime 'o' 恒 7 位小数、整秒输出 `.0000000`，读侧 `\.\d{7}Z` 正则匹配通过；MUST NOT 以 DateTimeOffset 序列化——其 'o' 输出 offset 后缀非 `Z`，恒触发保守 LOCKED）+ fallback（字段缺失/格式不合契约 → 保守 LOCKED）。Cherry 沙箱下 `Get-Process`/`Process.StartTime` 可靠性待实测，但误判方向恒为安全假阴性（拒接管→`LOCKED`→停一轮，不误删活锁——CB-P1-1/CB-P1-2 闭合后该声明成立）。验收口径：不确定→保守 `LOCKED|` 不抢锁。
8. **时钟回拨**：🟡 v0.2.13 CB-P2-4 判据收紧——`runId` 匹配为唯一必要条件（runId 存在但不匹配→恒不新鲜，runAt 不放行）；仅 runId 字段缺失时回退 `runAt ≥ startAt`（兼容无 runId 旧凭证，此兜底窗口内极端时钟回拨仍可能误判——已知边界）。验收口径：runId 匹配即新鲜；不匹配即不新鲜（无论 runAt）。待实现期模拟时钟回拨测试覆盖。
10. **锁获取与 current-run.json 写入间崩溃（🟢 v0.2.8，回应 anthropic）**：archive-state 先 `CreateNew` 拿锁、再写本轮 `runId` 到 `current-run.json`。若进程在这两步之间崩溃，下一轮续锁时"锁内记录的 runId ≠ current-run.json 的 runId"（current-run.json 仍是上一轮或半写残值），必然触发 `LOCKED|` 进入人工清锁流程。**fail-closed 覆盖**（无安全风险——锁不释放则 sync 不跑，最坏停一轮），**仅人工清锁成本**（需走 §6 恢复手册四条件确认）。行为已定（§6 续锁规则已闭合），非待实测项，列此保持 §14 完整性风格一致。注：锁半写导致的 pid/processStartTimeUtc 字段异常由 §6 伪代码的异常分型与格式校验保守接住（CB-P1-1/CB-P1-2，均判 `LOCKED|`）。
11. **prerelease-vs-REPAIR 优先级边界（🟡 v0.2.9，回应 anthropic P1-1）**：条件3（TARGET_PRERELEASE）排在条件5（REPAIR）之前。若某 CLI 本地 broken 且 `remote.latest` 被判为 prerelease（新项目暂只有 prerelease，或探测边界 bug），TARGET_PRERELEASE 先命中→REPAIR 永远排不上号，本地损坏安装无限期得不到修复，直到出现 stable 版本。此为 v0.2.8 修的"null 下沉卡死"的**同构问题**（都是"remote 端某状态导致 broken 本地走不到 REPAIR"），但当前 spec 只堵了 null 口子。**不重排顺序**：把 4/5（健康修复）提到 1-3（策略前提）前面会与 stable-only 冲突（broken 时强制装 prerelease 违反 stable-only 原则）。三 CLI（claude/codex/opencode）持续有 stable 发布，触发概率极低。**验收口径**：列为已知风险，不伪关闭；若实测出现 prerelease-only 期，需人工介入（手动 pin 到最近 stable 或等待 stable 发布）。
12. **上游版本格式突变（🟢 v0.2.15 GPT-P1-2）**：若某 CLI 上游发版改用非三段 SemVer 格式（如 `1.2` / `2026.09`），Compare-SemVer 恒 incomparable → 条件2 `VERSION_FORMAT_ERROR|` 命中 → 该 CLI 持续不升级（fail-closed 安全方向：不执行动作、D 盘 last-known-good 不受影响；代价=版本长期停滞 + 每轮如实汇报）。触发概率低（三 CLI 上游均长期遵循 `x.y.z`）。**验收口径**：agent 不自动处置、如实汇报；人工介入路径=①核实上游格式变更意图（临时异常 → 等待修复）②必要时流程外手动安装/回退保持该 CLI 可用③若系长期决策 → 评估修订 Compare-SemVer 规则并升 spec 版本后恢复自动跟随。

---

## 15. 测试策略

- **单元**：`Compare-SemVer`（边界 + §7.1 测试表 12 条 + §7.3 if-elif 顺序全覆盖）、`Invoke-Proc`（超时/Kill）、时间字段序列化/解析断言（UTC 'o' 恒 7 位小数 + `Z`；比较走 Ticks 层；负例断言 MUST NOT DateTimeOffset——🟢 v0.2.15 GPT-P1-1）、健康检查分型、SHA256 计算、ZipSlip 解压（构造恶意 entry）、checksum 文件解析（两格式/多资产匹配/空白注释行/同名 hash 冲突→checksum-mismatch）、凭证新鲜度判据（runId 匹配即新鲜 / runId 存在但不匹配→runAt 不放行（时钟回拨模拟）/ runId 字段缺失→runAt 兜底）、pin 规则（修复性晋升 / pinned-mismatch / pin 不阻断 upgrade）、sync 异常隔离（单 CLI copy 失败不冒泡）、**陈锁接管四分支全覆盖 + 异常分型/格式校验断言（🔴 v0.2.13 CB-P1-1/CB-P1-2/CB-P3-2：按 §6 伪代码断言——①查询异常分型：锁内 pid 为 null/非法（实测抛 `ParameterBinding*`）或权限拒绝等 → 未证明死亡→`LOCKED|`；②`Get-Process` 正常未命中（`ProcessCommandException` 分型）→TAKEOVER 允许重争；③命中且 tick 匹配（'o' 格式锁值，Ticks 层比较）→同一实例仍存活→`LOCKED|` 不抢；④命中但 tick 不匹配（锁值已过格式校验）→PID 被复用→TAKEOVER；⑤锁时间字段缺失/格式不合契约（本地偏移/精度截断/非字符串/解析失败）→保守 `LOCKED|`；⑥负例断言：同一时刻的 string 形态 `-eq` 比较（实测恒 False）MUST NOT 出现在实现中）**。
- **集成**：每 CLI probe→upgrade→verify 串；覆盖 §7.3 九分支 + checksum-mismatch/dual-hash-mismatch/zip-slip/RATE_LIMITED。
- **端到端**：archive→三 CLI cycle→sync；archive 段断言成功标记 `ARCHIVE_OK|<runId>`（🟢 v0.2.14 CH-P1-2）；全段 stdout **标记行语法合规断言**（独占一行/行首即标记名/标记名 ∈ §8 枚举/除 `RUN_STATUS` 外单 `|`/日志行不以标记形态开头——🟢 v0.2.15 GPT-P0-2）；覆盖成功/uptodate-refresh/网络全断/exe 锁定/verify 失败/pin 锁定（含修复性晋升）/被锁阻塞（含恢复手册）/限流九场景；穿插 re-probe（含 `UPTODATE_SKIP` 可达断言，CH-P2-1）。
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
| v0.2.7 | 2026-09-16 | GPT frozen-direction 评审复核（对 v0.2.6），朝冻结候选收敛：P0-1 GitHub API asset digest 主路径 MUST（gh api 实测验证）+ expectedSha256 schema 字段（保留 checksumAssetUrl 作 fallback）；P0-2 §14-1/6 实测闭合、§14-5 N=10、真未知风险不伪关闭（驳回"全部关闭"）；P0-3 verify 失败不写新鲜 runId 凭证；P1-4 marker→exitCode→文件副作用表（§8.1）；P1-5 Canonical Path 代码块；Checklist A-N 引为独立验收交付物 | `SPEC-v0.2.7.md` |
| v0.2.8 | 2026-09-16 | anthropic frozen-direction 评审复核（对 v0.2.7），冻结前最后消歧：🔴 §7.3 分支优先级歧义——`local.version==null` 不计入条件2"不可解析"，下沉至条件4/5，Compare-SemVer 对 null 由调用方前置判空（否则首次 seed 卡死）；🟡 §5.4 `matchesTarget` 各分支比较基准（ACTIONABLE/REPAIR 对 `upgrade.json.target`，UPTODATE_REFRESH 对 `local.version`）；🟡 §5.8 specVersion 不匹配处理（不作本轮决策依据消费、非 fatal、本轮覆盖迁移、checklist A 节断言据此修正）；🟢 §14-10 锁获取与 current-run.json 写入间崩溃（fail-closed 覆盖，行为已定）。观察项回应：冻结退出标准属项目治理 meta，不入 spec 主体 | `SPEC-v0.2.8.md` |
| v0.2.9 | 2026-09-16 | anthropic 冻结评审复核（对 v0.2.8），闭合"文本已写但语义未闭合"缺口：🔴 P0-1 REPAIR target 语义——统一 `target=remote.latest`（与 ACTIONABLE 对齐，顺便修到最新），覆盖 broken+opencode-staging-空/broken+local-ahead 边界，§5.3 target 来源闭环；🔴 P0-2 verified.json channel schema 矛盾——§5.4 示例补 `"channel"`（自带通道，sync 无需跨文件判 sha256 MUST/SHOULD）；🟡 P1-1 prerelease-vs-REPAIR 优先级边界列 §14-11 风险（stable-only 后果，不重排）；🟡 P1-2 N=10 计数机制——新增 `opencode-npm-fallback.json`（consecutiveSyncSuccess 计数，sync 末步更新，达 10 卸载置 uninstalled=true 幂等）；🟢 P1-3 ALL_REMOTE_FAIL 聚合——RATE_LIMITED 与 REMOTE_FAIL 均计入 | `SPEC-v0.2.9.md` |
| v0.2.10 | 2026-09-16 | CodeBuddy 独立审计复核（对 v0.2.9），扫清"schema 总表↔示例↔正文"三方一致性 + §7.3 分支完备性（全文字级修订，不涉架构）：🟡 D1 §5.9「全部」行收窄（error→local/remote/upgrade，name 补 sync，表补 entries[].name）；🟡 D2 fromVersion 类型 string→string\|null；🔴 D3 §7.3 条件7/8 改互补（7=有本轮新鲜→SKIP 仅同轮 re-probe 可达，8=无本轮新鲜→REFRESH 覆盖 stale-but-matching 空洞）+ else 兜底 + 输入清单补 verified/current-run；🟡 D4 §7.2 REPAIR `<ver>`→`<remote.latest>`；🟡 D5 §10.5 计数唯一规则（fatal 中断→不动，仅 sync 完整执行才 +1/归零）；🟡 D6 §5.4 三重约束②改 sync 可机械判定（sourceSha256==verified.sha256）；🟡 D7 §5 时间字段规则补 npm-fallback 例外（用 lastUpdatedAt）；🟢 D8 §8 FATAL 产出者补 upgrade/verify（schema 校验失败）；🟢 D9 ALL_REMOTE_FAIL 产出者钉死（agent/SOP 聚合，非单 CLI 脚本）；🟢 D10 REMOTE_FAIL 落盘补 assetName/checksumAssetUrl/fallbackUsed；🟢 D11 §5.2 策略5 拆 upgrade/verify 各写各 sha256；🟢 D12 §5.8 示例改跨版本值。驳回 D13（观察项，gh 定位属 SOP/实现期，§5 已允许 env 注入） | `SPEC-v0.2.10.md` |
| v0.2.11 | 2026-09-16 | GPT 独立审计复核（对 v0.2.10），契约级补充（不涉架构）：🟡 P0-1（降级采纳 option A）§8 钉死"成功判定各层只看 `RUN_STATUS` 标记，exitCode 非权威 MUST"（定时任务/SOP 层不依 exitCode 判成功），驳回 option B（exitCode 表重构＝过度工程）；🟡 P0-2（降 P1 采纳）§6 run.lock 补 `processStartTimeUtc`（SHOULD）+ 陈锁接管加 PID+startTime 双校验（spec 本已 fail-closed 安全，误接管→拒→`LOCKED`＝假阴性方向，故降 P0→P1，非堵安全漏洞）；🟡 P0-3 §7.1 `Compare-SemVer` 正规化规则补全（缺 patch/4+段→incomparable，build→忽略非 incomparable，含 `-`→prerelease）+ 12 条测试表；🟢 P1-1 §5.2/§17 删内部 cite 占位符 + "2025-06-03 起"软化为实测措辞；🟢 P2 §0 补硬编码路径理由（减变量提可验收性）。驳回 P1-2（cause 全枚举＝过度工程，运行时 cause 开放集合不可全枚举，spec 已枚举关键 cause）；§15 补 PID 重用/锁误接管模拟用例（时钟回拨/specVersion 漂移已覆盖） | `SPEC-v0.2.11.md` |
| v0.2.12 | 2026-09-16 | anthropic 独立审计复核（对 v0.2.11），闭合两处此前审计盲区（§6 锁接管 + schema↔更新逻辑文字对不上，全契约级修订）：🔴 P0-1（采纳，**修正 v0.2.11 引入的回归**）§6 陈锁接管 PID+startTime 双校验逻辑写反——原"StartTime 匹配→确认已死→接管"会导致误接管存活进程锁（数据损坏级），改伪代码钉死（未命中→已死可重争；命中且 StartTime 匹配→仍存活 LOCKED；命中但不匹配→PID 被复用可重争）；🔴 P0-2 `processStartTimeUtc` 升 MUST + 字段缺失 fallback（保守 LOCKED）；🟡 P1-3 §8.1 `ALL_REMOTE_FAIL` 行脚本列改"agent/SOP 聚合"、exitCode 标"不适用"（与 §8 D9 对齐）；🟡 P1-4 §7.1 prerelease 排序删"不强制唯一性"矛盾措辞，改采 SemVer 2.0.0 §11 precedence；🟡 P1-5 §10.5/§5.9 `consecutiveSyncSuccess` 卸载后冻结定格 10（闭合"0-10"声明与"+=1 不封顶"矛盾）；🟢 P2-1 sync.json 顶层补 `runStatus`；🟢 P2-2 §9 汇报模板加 pin mismatch SHOULD 提醒；🟢 P2-3 DISK_FULL/EXE_LOCKED 给 SHOULD 默认阈值/检测方式；🟢 P2-4 §5.2 checksum 同名 hash 冲突判 `checksum-mismatch` fail-closed；🟢 P2-5 §16 加同日多轮说明；🟢 P2-6 §6 锁接管以伪代码落 spec，流程建议本轮后冻结进实现 | `SPEC-v0.2.12.md` |
| v0.2.13 | 2026-09-16 | CodeBuddy 独立审计复核（对 v0.2.12），闭合 §6 伪代码两处 fail-open 缺口 + 判据/枚举/表述对齐（全契约级修订，11 项意见全部采纳）：🔴 CB-P1-1 §6 catch 异常分型——仅 `ProcessCommandException`（PID 无活跃进程）判死→TAKEOVER，`ParameterBinding*`（锁内 pid null/非法，锁半写场景）/权限拒绝→未证明死亡→LOCKED（实测复现三类异常分型）；🔴 CB-P1-2 §6 时间比较钉死——写侧 UTC 'o' round-trip（tick 精度）MUST + 读侧 Parse(RoundtripKind)+归一+Ticks 比较 MUST + 锁值格式校验前置（本地偏移/精度截断/解析失败→LOCKED；实测 string 形态 -eq 同一时刻恒 False）；🟡 CB-P2-1 §10.5/§5.9 uninstalled=true 后完全冻结（失败不归零，定格 10，选审计方案 b）；🟡 CB-P2-2 §5.5 runStatus 语义收窄（sync 本次执行终态）+"本轮完整成功"须联判 runId + fatal 落盘形态定义（sync 异常分支原子写入 failed 版）+ 废除"单文件自洽/无字段=腰斩"过强声明；🟡 CB-P2-3 SYNC_TARGET_LOCKED 落盘钉死 action=target-locked + reason 必填（§8.1/§5.9 对齐）；🟡 CB-P2-4 凭证新鲜度收紧（runId 唯一必要条件，仅字段缺失回退 runAt；§1-11/§5.4/§5.8/§7.3/§14-8/§17 六处对齐）；🟢 CB-P3-1 pin 连续 mismatch 数据源=archive 回溯最近 N 轮 sync.json entries；🟢 CB-P3-2 分支计数统一四分支+扩充断言集；🟢 CB-P3-3 §0 仓库内容声明按实修正；🟢 CB-P3-4 Codex 大小写注（实机大写 C，Windows 不敏感等价）；🟢 CB-P3-5 checksum 路径期望 hash 落 expectedSha256 + 来源可机械区分（assetDigest==null && expectedSha256!=null） | `SPEC-v0.2.13.md` |
| v0.2.14 | 2026-09-16 | Cherry 独立审计复核（对 v0.2.13），契约层补全与措辞澄清（6 项意见：采纳 3、部分采纳 1、驳回 1[实测证伪]、固化其验证要求 1，无 §6 判定方向变更）：🔴 CH-P1-1 run.lock 存储格式钉死 JSON + 纳入 §5.9 schema 总表（runId/start/beat/pid/processStartTimeUtc 五字段；§4/§5/§6 三处同步），CB-P1-2 格式契约获 schema 级落点；🔴 CH-P1-2 archive-state 补成功标记 `ARCHIVE_OK\|<runId>`（§8 表/§8.1/§9 状态机三处同步，闭合"唯 archive 成功无 `*_OK\|`"不对称——agent 判 OK 依据此前悬空：exitCode 非权威 + 沉默与崩溃不可区分）；🟢 CH-P1-3 驳回（PS 7.6.4 实测证伪）——DateTime 'o' 恒 7 位小数（整秒输出 `.0000000`，与 Kind 无关）、DateTimeOffset 亦然，写读两侧自洽，Cherry 所虑"整秒永不 TAKEOVER"断档不存在；§6 固化实测结论 + MUST NOT 以 DateTimeOffset 序列化锁时间（offset 后缀非 Z，恒触发保守 LOCKED）；🟢 CH-P2-1 §9 注明 re-probe 可达性（UPTODATE_SKIP 仅同轮穿插可达，标准单轮不可达，re-probe 属 SOP 可选步骤）；🟢 CH-P2-2 §8.1 failed 行计数措辞澄清（冻结态"更新"=no-op 保持定格 10）；🟢 CH-P2-3 §14 注明历史连续编号跨组不连续（驳回重编号方案：§14-N 为历轮审计与正文交叉引用锚点） | `SPEC-v0.2.14.md` |
| v0.2.15 | 2026-09-17 | GPT 独立审计复核（对 v0.2.14），7 项意见：采纳 5、部分采纳 1、驳回 1（全契约层补全/消歧，不改判定语义、不涉 §6 锁逻辑）：🔴 GPT-P0-1 mise staging 路径省略号消歧义（§2 精确化为 `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\`——实测复核 2026-09-17〔mise 根/installs/claude 2.1.273/codex 0.154.0/mise.exe/npm prefix 均在盘〕+ legacy verified 2026-09-16；§4 Canonical Path 补行；§7.1 新增 Cherry mise 环境契约〔getter 常量精确值 + MISE_* 七键 + "mise 子进程 MUST 带 env / 文件扫描不依赖 env" + ExeRelPath 实测结构〔claude=`claude.exe`、codex=`bin\codex.exe`〕+ 失败沿既有 `UPGRADE_FAIL|`/`REMOTE_FAIL|` 上报不新增标记〕；§5.1 补 mise 空目录语义同 opencode staging 空 → REPAIR）；🔴 GPT-P0-2 §8 标记行语法 MUST 六条（独占行/行首/首个 `|` 切分/枚举约束/除 RUN_STATUS 外单 `|`/日志行禁标记形态 + agent 解析规则）；🟡 GPT-P0-3 current-run.name 任务名语义注记强化（§5.6 注 + §5.9 独立 schema 行〔固定 `<cli-autoupdate>`、验收断言 MUST 分开〕；**驳回改名 `taskName`**——name 跨文件统一表达"文件归属者"，改名引入 schema 特例、值本身不可混淆、无机械验收收益）；🟡 GPT-P1-1 时间字段格式契约统一（全部 ISO 时间字段 UTC 'o' round-trip = 恒 7 位小数 + `Z`；比较 MUST DateTime/Ticks 层；MUST NOT DateTimeOffset——与 §6 锁字段同源实测 CH-P1-3；§5 总则 + §5.9 表注 + §7.1 助手 + §15 断言四处同步）；🟢 GPT-P1-2 版本格式突变处置模板（§9 SOP 错误场景示例 + §14-12 已知风险声明：fail-closed 持续不升级 + 人工介入路径）；🟢 GPT-P1-3 驳回（§8 单页接口总览表——信息零新增、并列事实源易漂移，以 §8.1 交叉索引句替代）；🟢 GPT-§4 采纳（§5.10"未来增强"入口：release attestations/`gh release verify-asset` 路线，非本版本范围） | `SPEC-v0.2.15.md`（本文件） |

> **🟢 v0.2.12 P2-5（版本历史日期说明）**：v0.1–v0.2.14 标注 2026-09-16、v0.2.15 标注 2026-09-17——v0.1–v0.2.14 系同日跨模型审计密集收敛（设计日），v0.2.15 为次日复核轮。日期列精度为"日"，外部审计者如需迭代节奏，可按版本号顺序（每轮一行）追溯；后续进入实现期的 SOP/脚本版本将带时分。

---

## 17. 术语表

| 术语 | 定义 |
|---|---|
| CLI | claude/codex/opencode 三个命令行工具 |
| mise | 版本管理器，管 claude/codex |
| staging | 升级场层，下载/验证落点 |
| promotion | 权威入口层，`D:\AI\Programs\CLI\<name>\<name>.exe` |
| 晋升闸 | sync 只复制通过**三重约束**的 CLI：①本轮新鲜（runId，缺失回退 runAt——CB-P2-4 收紧）②完整性通过（sha256）③pin 未冲突 |
| 凭证 | verified.json，含 runId；三重约束全过才可晋升 |
| 凭证新鲜度 | `runId == current-run.runId`（唯一必要条件）；仅 runId 字段缺失时回退 `runAt ≥ startAt`（🟡 v0.2.13 CB-P2-4 收紧：runId 不匹配则恒不新鲜，防时钟回拨放过跨轮旧凭证） |
| pin | state/<cli>.pin，锁定目标版本=pinVersion，只作用于 sync |
| sha256 证据链 | sync.json.entries 的 source/target/previous sha256 + integrityNote |
| ZipSlip | zip 路径穿越攻击，MUST 拒绝 `..\`/绝对路径/symlink |
| 双 hash 比对 | 无 checksum asset 时，反代+直连两份独立下载 SHA256 一致才接受 |
| API asset digest | GitHub Releases API `.assets[].digest`（`sha256:<64hex>`），upload-time 计算、immutable；opencode 完整性主路径 MUST（已实测 anomalyco/opencode 全 asset 均带 digest，§5.2） |
| expectedSha256 | remote.json 字段，完整性校验期望值：digest 主路径（从 API digest 剥 `sha256:` 前缀取 64hex）或 checksum 路径（🟢 v0.2.13 CB-P3-5：checksum 条目 hash 亦落此字段，来源由 assetDigest 是否为 null 区分） |
| RATE_LIMITED | 403 + ratelimit-remaining:0，区别于普通 REMOTE_FAIL |
| 威胁模型 | §5.10 声明：防下载损坏/反代投毒/ZipSlip/落盘偏差/陈旧凭证；不防上游账号被攻破（需签名，本项目不做） |
| SemVer | `Major.Minor.Patch[-prerelease]`，限制版；prerelease precedence 采 SemVer 2.0.0 §11（§7.1） |
| 原子写入 | tmp → 回读校验 → Move-Item 同卷替换 |
| runId | archive 首步生成的 uuid，锁 ownership + 凭证新鲜度主判据 + state 文件关联 |
| run.lock | §6 运行时锁文件（JSON）：runId/start/beat/pid/processStartTimeUtc；schema 见 §5.9 run.lock 行（🟢 v0.2.14 CH-P1-1） |
| fatal / recoverable | 错误分层：fatal 终止整轮；recoverable 单 CLI 失败继续 |
| 异常隔离 | sync 内每 CLI copy 独立 try/catch，单 CLI 失败不冒泡终止整轮 |
| 反代前缀 | `https://gh.jasonzeng.dev/`，失效直连回退 |
| dry-run | 无 -Execute 模式，预演 |
| fail-closed | 失败 → 终止不降级不静默跳过 |
| LICENSE | 仓库根 AGPL-3.0，适用于 `.old/` legacy 脚本；本项目主体不面向外部发行 |
| 标记行语法 | §8 契约：标记独占一行、行首即标记名（禁前导时间戳/级别）、首个 `|` 切分且标记名 ∈ §8 表枚举、除 `RUN_STATUS` 外 payload MUST NOT 含 `|`、非标记日志行禁以标记形态开头（🟢 v0.2.15 GPT-P0-2） |
| Cherry mise 环境 | `Get-CherryMiseEnv`（MISE_* 七键常量）+ `Get-MiseInstallsDir`/`Get-MiseExePath`/`Get-NpmPrefix` 精确常量（§7.1）；mise 子进程 MUST 带 MISE_* env，文件扫描不依赖 env（🟢 v0.2.15 GPT-P0-1） |
| MUST/SHOULD/MAY | RFC2119：必须/应/可 |
