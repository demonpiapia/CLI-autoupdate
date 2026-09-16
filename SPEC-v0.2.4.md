# CLI 自动升级 —— 项目规格 SPEC v0.2.4

> **版本**：SPEC-v0.2.4（2026-09-16）。
> **变更摘要（v0.2.3 → v0.2.4）**：架构不动。据 GPT supervisor-governance 评审复核后修订——采纳供应链完整性强化（verified.json 加 sha256 + checksum asset 存在则 MUST 校验 + 反代/直连双 hash SHOULD 比对）、ZipSlip 解压安全约束、pin 语义重写（锁定目标版本=pinVersion，可修复性晋升，只作用于 sync）、sync.json 二进制证据链（source/target/previous sha256）、锁恢复手册、RFC2119 关键词约定、state schema 总表、状态机图。驳回"自维护受控 manifest"方案（附理由）。
> **角色定位**：本文件是 **Plan / 契约**（治理路线图 Approved Plan 位）。契约层为硬约束；PowerShell 实现属 Executor 有界自治。
> **关键词约定（RFC2119）**：本 spec 中 **MUST / 必须** = 绝对硬约束；**SHOULD / 应** = 强烈推荐（有合理理由可偏离但须记录）；**MAY / 可** = 可选。契约层陈述默认为 MUST。

---

## 0. 项目定位、范围与交付物

本项目是 **monitor + download + CLI 全局维护** 整体过程：从"探测是否有新版本"到"实际升级、切换、对外暴露统一入口"的完整闭环。

**运行形态**：本项目是 Cherry Studio 定时任务驱动、agent 编排、PowerShell 7 模块化的**个人维护流程**，维护对象是三个固定 CLI（claude/codex/opencode）。**不是**通用 CLI 自动更新软件产品——无 config.json、无 `cli update` 命令、无跨平台（仅 Windows）、无许可证/贡献指南、不做 RSA 签名验证（更新源固定；完整性由 mise 自校验 + GitHub checksum + 反代/直连双 hash 比对保证，见 §5.2）。

参照系（批判借鉴设计哲学，不照搬形态）：
- `Software_Update_Monitor_Spec_v0.2.2`（monitor-only）——本项目是其 Executor 下游延伸。
- `cherry-auto-apps-Release-Monitor`（已上线）——借鉴段内一气呵成、数据固化、运行锁、stdout 标记协议、原子写入、agent 不介入计算的工程哲学。不照搬合并脚本形态（本项目含下载/切换/回退/晋升闸，复杂度更高，需 4 拆模块）。

**交付物三层**：
1. **SPEC**（本文件）——设计契约，给 audit / 维护者。
2. **执行 SOP**（`cli-autoupdate-sop.md`，待产出）——给定时任务执行 agent 逐字读的标准化流程；agent 只读 SOP，不读本 spec。SOP 须含成功与错误场景示例（见 §9）。
3. **脚本**（`*-v0.2.4.ps1`）——模块化实现。

---

## 1. 设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | 模块化 | 每 CLI 拆 probe-local / probe-remote / upgrade / verify 四独立脚本。共享 sync 单脚本。 |
| 2 | 数据固化 | 每步结果落 `state/*.json`；下一步读上一步文件取数据。状态走文件，不走 agent 记忆。 |
| 3 | 流程化 | 定时 agent = 执行固定状态机 + 读标记判段间分支 + 报告异常。不写脚本、不手算版本。 |
| 4 | 晋升闸 | sync 只消费"本轮新鲜凭证"且通过完整性校验。未过验证/陈旧/锁定/完整性不符，D 盘权威入口原封不动。 |
| 5 | fail-closed（分层） | **fatal 类**（STATE_MISSING / PARSE_ERROR / 锁争失败 / 归档失败 / 状态文件 schema 校验失败 / 骨架级 RUNTIME_ERROR）→ MUST 终止整轮。**recoverable 类**（单 CLI 探测/升级/验证失败）→ SHOULD 标记后继续下一个 CLI。 |
| 6 | 原子写入 | 状态文件与权威入口经「临时文件 → 回读校验 → Move-Item 原子替换」；Move-Item 同卷原子，跨卷先 Copy 到目标卷临时文件再同卷 Move。失败回滚不污染原文件。 |
| 7 | 运行锁 | 多段 pwsh 调用经运行锁互斥。ownership 靠 runId 匹配（不靠 PID），PID 仅作陈锁死亡判据。 |
| 8 | 可追溯 + 二进制证据链 | 每轮归档 `state/archive/<时间戳>/`；fetch_run.log 累积；spec/脚本/json 带 specVersion；sync.json.entries 携带 source/target/previous sha256 作晋升可审计证据（§5.5）。 |
| 9 | 隔离 | staging（E 盘 mise / 工作区 staging）与 promotion（D 盘 `D:\AI\Programs\CLI\`）物理分离。 |
| 10 | 机器事实/叙事分层 | `state/*.json` 机器事实，agent 只读不写；agent 可写的是汇报叙事层。 |
| 11 | 凭证新鲜度 | sync 只信本轮产出的凭证（`runAt ≥ 本轮 startAt`）；幂等场景跳过 copy 不污染 `.previous`。 |
| 12 | 供应链完整性 | opencode（github-binary 通道）下载后 MUST 计算 sha256；release 附 checksum asset 则 MUST 校验；无 checksum asset 时 SHOULD 反代下载与直连下载双 hash 比对。详见 §5.2。mise 通道完整性由 mise 自身保证。 |

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging** | claude/codex：`E:\...\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\`；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证的新版本落点 | upgrade 脚本（运行锁内） |
| **Promotion** | `D:\AI\Programs\CLI\<name>\<name>.exe` | 全局唯一"正确版本"，所有 harness 从此调用；last-known-good 回退源 | **仅 sync，且仅本轮新鲜凭证+完整性通过的 CLI，运行锁内** |

两层架构本身就是"先在 staging 部署验证，通过后才原子交换到 promotion"——审计建议的"先部署临时目录、验证通过后原子交换"策略，本项目已由 staging/promotion 分层 + 晋升闸 + verify 脚本原生实现。

所有 harness 固定调用 `D:\AI\Programs\CLI\<name>\<name>.exe`，不依赖 mise shim / `MISE_*` / PATH（已实测三 exe 为独立二进制）。

---

## 3. 统一入口布局

```
D:\AI\Programs\CLI\claude\claude.exe
D:\AI\Programs\CLI\codex\codex.exe
D:\AI\Programs\CLI\opencode\opencode.exe
```

未来新增 CLI 同理。旧散路径首次 sync v0.2.4 时迁移（§13）。

> 实机现状（2026-09-16 核验）：D 盘此前曾缺 `claude\` 子目录（仅 codex/opencode），系手动建立时遗漏，现已补全。这正是 F1 凭证生命周期缺口的现实佐证——UPTODATE 不产凭证则永不 seed，需由 §7.3 的"UPTODATE 按需刷新凭证"机制兜底。

---

## 4. 目录与状态文件布局

```
D:\AI\Workspace\automatic\CLI-autoupdate\
├── SPEC-v0.2.4.md                    # 本文件（契约）
├── cli-autoupdate-sop.md             # 执行 SOP（给定时 agent，待产出）
├── cli-common-v0.2.4.ps1             # 共享库
├── probe-local-<cli>.ps1             # 每 CLI 一份（3 份）
├── probe-remote-<cli>.ps1            # 每 CLI 一份（3 份）
├── upgrade-<cli>.ps1                 # 每 CLI 一份（3 份）；内含 behind 判定 + zip 解压安全约束
├── verify-<cli>.ps1                  # 每 CLI 一份（3 份）；即装后功能测试 + sha256 计算
├── sync-v0.2.4.ps1                   # 共享单脚本
├── archive-state.ps1                 # 每轮首步：争锁+归档+生成 runId
├── state\                            # 固定路径，最新覆盖
│   ├── current-run.json              # 本轮 runId + startAt
│   ├── <cli>-local.json
│   ├── <cli>-remote.json
│   ├── <cli>-upgrade.json
│   ├── <cli>-verified.json
│   ├── sync.json
│   ├── run.lock                      # 运行锁（runId 模型）
│   ├── fetch_run.log                 # 累积日志
│   ├── <cli>.pin                     # 可选：手动锁定版本（防 sync 自动覆盖回退）
│   └── archive\<时间戳>\             # 每轮归档
├── staging\opencode\<ver>\           # opencode 解压落点（zip 解压 MUST 只落此子树，§7.2）
└── TEMP\                             # 交付前必空
```

状态目录决策：**固定 `state/` 最新覆盖 + 每轮 archive**（Cherry 每段 Bash 是新 shell，固定路径让段间脚本能直接定位）。

**陈旧数据风险**：`<cli>-remote.json` 在 REMOTE_FAIL 时写 `{latest:null, error:<cause>}`（不保留陈旧 latest）；`<cli>-upgrade.json` 仅实际升级时写，不升级分支不写不覆盖，读取前 MUST 校验 `runAt` 是否本轮。

---

## 5. 数据契约（state/*.json）

所有 JSON 顶层带 `specVersion`（`"0.2.4"`）、`runAt`（ISO UTC）。时间内部 UTC，展示 UTC+08:00。字段级 schema 总表见 §5.9。

**更新源固定清单**：更新源固定硬编码，无白名单/trustedHosts 配置需求：
- claude/codex：mise registry（mise 自身校验包完整性）。
- opencode：`anomalyco/opencode` GitHub releases（固定 repo；下载经反代 `https://gh.jasonzeng.dev/`，反代失效回退直连，时序 §5.2/§7.2）。
- 超时已内置：Invoke-Proc 对 mise ls-remote 60s、upgrade 600s、exe --version 30s（§7.1）。
- 日志已有：`state/fetch_run.log`。
- "自动更新开关" = 定时任务本身（不配 cron 即不跑）。

### 5.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.2.4", "name":"codex", "channel":"mise",
  "version":"0.154.0", "exePath":"...", "bytes":298169136, "mtime":"...",
  "sha256":"<mise通道可空；opencode staging exe必填>",
  "healthy":true, "healthDetail":"ok", "error":null, "runAt":"..." }
```
- `healthy`：exe > 1MB 且 `--version` 可启动。
- `healthDetail`（病因分型）：`ok` / `broken`（<1MB / stub / 文件缺失） / `probe-error`（`--version` 偶发超时或非零退出，文件结构正常）。`broken` → REPAIR；`probe-error` → `PROBE_ERROR|` 不强制重装。
- `sha256`：opencode 通道 probe-local 对 staging exe 计算（用于与凭证/目标比对）；mise 通道可空（mise 自证完整性）。
- opencode staging 空 → `version=null, exePath=null, healthy=false, healthDetail=broken`。

### 5.2 `<name>-remote.json`（probe-remote 产出）+ 下载完整性策略
```json
{ "specVersion":"0.2.4", "name":"opencode", "channel":"github-binary",
  "latest":"1.18.31", "sourceUrl":"https://gh.jasonzeng.dev/https://...",
  "directUrl":"https://github.com/anomalyco/opencode/releases/download/v1.18.31/opencode-windows-x64.zip",
  "assetName":"opencode-windows-x64.zip", "checksumAssetUrl":"<或null>",
  "fallbackUsed":false, "error":null, "runAt":"..." }
```
- **mise 通道**：`mise ls-remote <tool> --json` 最高 stable。
- **github-binary 通道**：`releases/latest` → tag_name（去 `v`）+ assets 筛 `windows-x64.zip`；`sourceUrl`=加速地址、`directUrl`=直连地址、`checksumAssetUrl`=`*.sha256`/`checksums.txt`（存在则记录，null 则无）。
  - **回退**：`releases/latest` 失败 → `releases?per_page=10` 取最高 stable、prerelease=false；`fallbackUsed=true`。
  - **REMOTE_FAIL 落盘语义**：远端失败时仍写 remote.json，但 `latest:null, sourceUrl:null, directUrl:null, error:<cause>`——不保留陈旧 latest。
  - **下载完整性策略（回应 GPT#1，强化供应链）**：
    1. upgrade 下载 zip 后 MUST 校验大小 > 1MB（防半下载/stub）。
    2. **checksum asset 存在**（`checksumAssetUrl != null`）→ MUST 下载 checksum 并校验 SHA256；不匹配 → `DOWNLOAD_FAIL|<cli> checksum-mismatch`。
    3. **checksum asset 不存在** → SHOULD 执行"反代下载 + 直连下载双 hash 比对"：两份独立下载，SHA256 一致才接受；不一致 → `DOWNLOAD_FAIL|<cli> dual-hash-mismatch`（疑似反代投毒）。MAY 偏离（如直连不通时仅用反代 + 记录 `integrityNote:single-source`），但须在 sync.json.entries 标注。
    4. 解压后对目标 exe MUST 计算 SHA256，写入 verified.json.sha256。
  - **直连回退时序**：加速 URL 失败（网络/非 200）→ 直连 GitHub 重试一次 → 仍失败 → `DOWNLOAD_FAIL|<cli> <cause>`。
  - **关于"自维护受控 manifest"（驳回 GPT#1 方案1）**：本项目不采用"在自有仓库维护 version→sha256 manifest"方案。理由：①与"自动跟随 latest"目标矛盾——opencode 发版后无法自动获知官方 sha256，需人工更新 manifest，违背定时任务"一气呵成"原则；②manifest 本身的受信任性回归原问题（谁校验 manifest）；③checksum asset 存在时已能 MUST 校验，不存在时双 hash 比对已检出反代投毒，强度足够且不引入人工步骤。
  - **已知坑（probe 实测确认）**：`anomalyco/opencode` tag 列表接口曾现异常拼接；asset 名 `opencode-windows-x64.zip` 为起点假设，probe 核实。

### 5.3 `<name>-upgrade.json`（upgrade 产出，仅实际升级时写）
```json
{ "specVersion":"0.2.4", "name":"codex", "fromVersion":"0.152.0", "target":"0.154.0",
  "exitCode":0, "ok":true, "sha256":"<opencode必填，mise可空>", "error":null, "runAt":"..." }
```
不升级分支不写不覆盖本文件。

### 5.4 `<name>-verified.json`（verify 产出；晋升凭证）
```json
{ "specVersion":"0.2.4", "name":"codex", "version":"0.154.0",
  "exePath":"...", "bytes":298169136, "sha256":"<opencode必填，mise可空>",
  "healthy":true, "matchesTarget":true, "runAt":"<本轮 startAt 之后>" }
```
- **晋升条件**：`matchesTarget==true && healthy==true && runAt ≥ current-run.startAt && sha256 通过（opencode 通道 sha256 非空且与下载校验值一致）`。
- `sha256`（回应 GPT#1）：opencode 通道 MUST 非空（晋升凭证一部分，bytes 太弱）；mise 通道 MAY 空（mise 自证）。verify 脚本即装后功能测试：跑 `exe --version` + 计算 sha256。

### 5.5 `sync.json`（sync 产出）+ 二进制证据链
```json
{ "specVersion":"0.2.4", "runAt":"...",
  "summary":{ "probed":3, "upgraded":1, "synced":1, "failed":1 },
  "entries":[
    {"name":"codex","source":"...","target":"D:\\AI\\Programs\\CLI\\codex\\codex.exe",
     "targetVersion":"0.154.0","action":"copy","bytes":298169136,
     "sourceSha256":"...","targetSha256":"...","previousSha256":"...",
     "ok":true},
    {"name":"opencode","action":"skip","reason":"no fresh verified-success / pinned / already-current"}
  ] }
```
- **summary**：sync 汇总本轮 state 计算 `probed/upgraded/synced/failed`。agent 汇报数字取 summary。
- **二进制证据链（回应 GPT#4）**：`copy` 动作 entries MUST 携带 `sourceSha256`（凭证 sha256）、`targetSha256`（copy 后 D 盘实测 sha256，须与 source 一致）、`previousSha256`（覆盖前 `.previous` 的 sha256）。opencode 通道必填；mise 通道可空但 SHOULD 填。这让"verify_ok 但 promotion 仍不对"的争议可审计。
- `action`：`copy` / `skip` / `target-locked`。

### 5.6 `current-run.json`（archive-state 首步生成）
```json
{ "specVersion":"0.2.4", "runId":"<uuid>", "startAt":"<UTCISO>", "archivedTo":"archive\\<ts>" }
```

### 5.7 `<cli>.pin`（可选，手动锁定目标版本，回应 GPT#3 语义重写）
```json
{ "specVersion":"0.2.4", "name":"codex", "pinVersion":"0.152.0", "reason":"user manual rollback", "setAt":"..." }
```
**pin 语义（显式可推导）**：
- pin 存在时，sync 的**目标版本 = pinVersion**（不是"冻结 D 盘不动"，而是"锁定 D 盘应停留在 pinVersion"）。
- `verified.version == pinVersion` 且新鲜且 healthy 且完整性通过 → sync MUST 晋升到 pinVersion：
  - D 盘当前 == pinVersion → `SYNC_SKIP|already-current`（幂等）。
  - D 盘当前 ≠ pinVersion（被外部改动/损坏/曾回退到更旧版） → `SYNC_COPY|修复性晋升`（把 D 盘拉回 pinVersion）。这解决了"D 盘偏离 pinVersion 时是否允许修复"的边界——允许。
- `verified.version != pinVersion`（verified 是 latest，pin 锁旧版） → `SYNC_SKIP|pinned-mismatch`（不晋升 latest）。
- **pin 只作用于 sync，不阻断 upgrade**：upgrade 仍 MUST 探测+升级 staging（staging 可备最新版供将来解锁后晋升）。pin 不阻断 probe/upgrade/verify。
- 用户"解锁跟随 latest" → 删除 pin 文件，或把 pinVersion 改为 latest 版本。下一轮 sync 自动跟随。

### 5.8 校验与原子写入（fail-closed）
每状态文件落盘走「写 `*.tmp` → `ConvertFrom-Json` 回读校验关键字段 → `Move-Item` 原子替换」。Move-Item 同卷原子；跨卷先 Copy 到目标卷临时文件再同卷 Move。校验失败 → 不替换、输出 `RUNTIME_ERROR_FATAL|schema`、释放锁、终止整轮（fatal）。

### 5.9 字段级 schema 总表（回应 GPT#文本2）

| 文件 | 字段 | 类型 | 必填 | 枚举/说明 |
|---|---|---|---|---|
| local.json | version | string\|null | 是 | SemVer 或 null（staging 空） |
| | exePath | string\|null | 是 | |
| | bytes | int\|null | 是 | |
| | sha256 | string\|null | 条件 | opencode 必填，mise 可空 |
| | healthy | bool | 是 | |
| | healthDetail | string | 是 | ok/broken/probe-error |
| remote.json | latest | string\|null | 是 | null=远端失败 |
| | sourceUrl | string\|null | 是 | 加速地址 |
| | directUrl | string\|null | 是 | 直连地址（github-binary） |
| | checksumAssetUrl | string\|null | 是 | null=无 checksum asset |
| | fallbackUsed | bool | 是 | |
| upgrade.json | fromVersion | string | 是 | |
| | target | string | 是 | |
| | sha256 | string\|null | 条件 | opencode 必填 |
| | ok | bool | 是 | |
| verified.json | version | string | 是 | |
| | sha256 | string\|null | 条件 | opencode 必填（晋升凭证） |
| | matchesTarget | bool | 是 | |
| | healthy | bool | 是 | |
| | runAt | ISO | 是 | 须 ≥ startAt |
| sync.json | summary.{probed,upgraded,synced,failed} | int | 是 | |
| | entries[].action | string | 是 | copy/skip/target-locked |
| | entries[].sourceSha256/targetSha256/previousSha256 | string\|null | 条件 | copy 动作 opencode 必填 |
| pin | pinVersion | string | 是 | |
| current-run.json | runId | string(uuid) | 是 | |
| | startAt | ISO | 是 | 凭证新鲜度基准 |

---

## 6. 运行锁模型（runId ownership）+ 恢复手册

跨 Bash 段 PID 必变，故 ownership 靠 runId（不靠 PID）：

- **争锁**（archive-state 首步）：`[IO.File]::Open(run.lock, FileMode::CreateNew, FileAccess::ReadWrite, FileShare::None)` 原子争锁；写 `runId/start/beat/pid`，runId 写入 `current-run.json`。
- **续锁**（后续每段）：open 锁文件独占 → 读 runId → 与 `current-run.json` 比对 → 匹配刷新 beat；不匹配/被独占/锁文件消失 → `LOCKED|` 退出。
- **陈锁接管**：beat 超 30 分钟 **且** 锁内 PID 经 `Get-Process -Id` 确认死亡 → 删锁重争；不确定 → 保守 `LOCKED|`。
- **释放**：sync 末步或异常分支，确认 runId 匹配后删锁。

> **锁空转处置（F6）**：`LOCKED|` 统一涵盖三种情形——锁被本轮外进程独占、beat 未超时崩溃残留、锁文件消失。一律 fail-closed → blocked，agent 汇报"本轮被锁阻塞"即可，**不人工抢锁**。崩溃后 beat 未超时期间，后续定时轮次空转 `LOCKED|` 属预期（等 30min 陈锁接管或人工清理）。最坏 30min 停摆窗口。

> **锁恢复手册（回应 GPT#5，硬约束）**：SOP MUST 含"人工介入清锁"章节，仅当**全部**条件满足才允许人工清 `run.lock`：
> 1. 确认无活跃 `pwsh`/`mise`/下载进程在跑本任务（任务管理器或 `Get-Process` 核对 PID）；
> 2. 确认 D 盘权威入口未被写一半（`<name>.exe` 与 `<name>.exe.previous` 字节完整、可 `--version`）；
> 3. 确认 `archive-state` 首步未在执行（无 `*.tmp` 残留、`state/archive/<未完成时间戳>/` 不存在或完整）；
> 4. 锁文件内 `beat` 已超 30min 或 PID 确认死亡。
>
> 满足后 move_to_trash 清 `run.lock`（**不手动改 .git/不 rm**），下一轮定时自然重争。不满足任意一条 → 等待，不抢锁。此手册写入 SOP（§9）。

---

## 7. 模块清单

### 7.1 共享库 `cli-common-v0.2.4.ps1`
`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`，异步排空 stdout/stderr 再 WaitForExit+Kill；超时：mise ls-remote 60s、upgrade 600s、exe --version 30s）、`Compare-SemVer`（去 `v`，比较 Major.Minor.Patch，prerelease 低于 stable，不支持 build 元数据参与比较；解析失败返回 incomparable）、`Get-CherryMiseEnv`/`Get-MiseExePath`/`Get-MiseInstallsDir`/`Get-NpmPrefix`、GitHub 加速/直连 URL 构造器、**zip 安全解压**（§7.2 ZipSlip 约束）、SHA256 计算、健康检查（>1MB + `--version`，分型 broken/probe-error）、运行锁原语、状态文件原子写入助手、runId 生成与读取、凭证新鲜度判定、pin 读取。

### 7.2 每 CLI 一套（4 拆模块）

| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver → version+exePath+healthy+healthDetail（sha256 可空） | 扫 `staging\opencode\<ver>\` → 同字段 + sha256 |
| `probe-remote-<cli>.ps1` | `mise ls-remote --json` 最高 stable；失败写 `latest:null,error` | `releases/latest` + 失败回退列表；记录 sourceUrl/directUrl/checksumAssetUrl；失败写 `latest:null,error` |
| `upgrade-<cli>.ps1` | 读 local+remote → 内部判 behind（§7.3）；ACTIONABLE=`mise upgrade <tool>@latest`，REPAIR=`mise install <tool>@<ver> --force` | 读 remote → 下载 zip（§5.2 完整性策略：大小/checksum MUST/双 hash SHOULD）→ **安全解压（ZipSlip 约束，见下）** → staging exe 计算 sha256 |
| `verify-<cli>.ps1` | 重扫 mise installs → version+exePath+healthy+matchesTarget+runAt（sha256 可空） | 跑 staging exe `--version` → 同字段 + sha256 |
| `sync-v0.2.4.ps1`（共享） | 遍历三 CLI verified.json，本轮新鲜+完整性通过+未被 pin 锁定（pin 语义 §5.7）+目标版本≠凭证版本才 copy；字节复核 + sha256 复核；覆盖前备份 `.previous`；entries 携带 sha256 证据链；汇总 summary | 同左 |

**ZipSlip 解压安全约束（回应 GPT#2，硬约束）**：opencode zip 解压 MUST 满足：
1. 解压目标 MUST 限定 `staging\opencode\<ver>\` 子树，不允许落到子树外。
2. 每个entry MUST 拒绝：含 `..\` / 绝对路径（如 `C:\`、`\`） / 符号链接 / junction 条目。
3. 发现非法 entry → 立即中止解压、清理已解压文件、输出 `DOWNLOAD_FAIL|<cli> zip-slip`（recoverable，跳过该 CLI）、不写 verified.json。
4. 解压后校验目标 exe 存在且 > 1MB。

### 7.3 behind 判定与版本规则（upgrade 内部）
读 `local.json` + `remote.json` → 分支：

| 条件 | 标记 | 动作 |
|---|---|---|
| local == remote 且 healthy==true 且有本轮凭证 | `UPTODATE_SKIP\|<cli> <v>` | 不执行、不写 upgrade.json、跳过 verify（真幂等） |
| local == remote 但凭证缺失或 verified.version ≠ local.version | `UPTODATE_REFRESH\|<cli> <v>` | 不执行升级，仍运行 verify（刷新凭证） |
| local.healthy==false 且 healthDetail==broken | `REPAIR\|<cli> <reason>` | 强制重装（mise：`mise install <tool>@<ver> --force`；opencode：重下载解压） |
| local.healthy==false 且 healthDetail==probe-error | `PROBE_ERROR\|<cli> <reason>` | 不重装，报告，跳过 verify |
| local < remote 且 target stable | `ACTIONABLE\|<cli> <from>-><to>` | 执行升级 → 进 verify |
| target prerelease | `TARGET_PRERELEASE\|<cli> <v>` | 不执行（stable-only），跳过 verify |
| local > remote（双方可解析） | `LOCAL_AHEAD\|<cli> <local> > <remote>` | 不执行，跳过 verify |
| 版本格式不可解析 | `VERSION_FORMAT_ERROR\|<cli> <raw>` | 不执行，跳过 verify（不用默认版本号） |
| remote.latest==null | `NO_REMOTE\|<cli> <cause>` | 读不到 target，不执行，跳过 verify |

**策略说明**：stable-only 跟随 latest，不强制更新、不自动降级（降级用户手动 `mise use` 或建 pin）。`local > remote` 显式报告不静默跳过。agent 无差别调用，upgrade 自判跳过。

### 7.4 版本号
共享库与 sync 文件名含 `-v0.2.4`；probe/upgrade/verify 每 CLI 一份，首行 `$ScriptVersion='0.2.4'` + `# SPEC: v0.2.4`。

---

## 8. 机器状态标记协议

每脚本 stdout 输出 ASCII 标记，agent 只读标记判分支，不解析 json、不心算。退出码：`0`=无事可做/已满足；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败；`3`=执行失败或复核不过。**agent 以 stdout 标记为准。**

标记分两类：**fatal**（终止整轮）/ **recoverable**（标记该 CLI 失败后继续下一个）。

| 标记 | 产出脚本 | 类别 | 判定 |
|---|---|---|---|
| `LOCKED\|` | 任何段 | fatal | blocked，本轮终止（含空转/独占/消失统一） |
| `STATE_MISSING\|` | archive/probe-local | fatal | blocked，本轮终止 |
| `PARSE_ERROR\|` | 任何段 | fatal | failed，不写回原文件，本轮终止 |
| `RUNTIME_ERROR_FATAL\|<cause>` | archive/sync（骨架级） | fatal | 整轮终止（含 schema 校验失败） |
| `RUNTIME_ERROR\|<cli> <cause>` | probe/upgrade/verify（CLI 级） | recoverable | 该 cli 失败，继续下一个 |
| `LOCAL_OK\|<cli> ver=<v> healthy=<bool> detail=<d>` | probe-local | 成功 | 阶段成功 |
| `LOCAL_EMPTY\|<cli>` | probe-local | 成功 | staging 空 → 进 upgrade |
| `REMOTE_OK\|<cli> latest=<v> fallback=<bool>` | probe-remote | 成功 | 阶段成功 |
| `REMOTE_FAIL\|<cli> <cause>` | probe-remote | recoverable | 该 cli 远端失败，仍进 upgrade（读 latest:null → NO_REMOTE） |
| `ALL_REMOTE_FAIL\|` | probe-remote 末 | 整轮级 | 三 CLI 全失败 → 跳 upgrade/verify，直进 sync |
| `UPTODATE_SKIP\|<cli> <v>` | upgrade | 成功 | 有本轮凭证，跳 verify |
| `UPTODATE_REFRESH\|<cli> <v>` | upgrade | 成功 | 凭证缺失/过期，进 verify 刷新 |
| `ACTIONABLE\|<cli> <from>-><to>` | upgrade | 成功 | 有升级动作 |
| `REPAIR\|<cli> <reason>` | upgrade | 成功 | broken 触发重装 |
| `PROBE_ERROR\|<cli> <reason>` | upgrade | recoverable | probe-error 不重装，跳 verify |
| `TARGET_PRERELEASE\|<cli> <v>` | upgrade | recoverable | stable-only 拒绝，跳 verify |
| `LOCAL_AHEAD\|<cli> <local> > <remote>` | upgrade | recoverable | 本地超前，跳 verify |
| `NO_REMOTE\|<cli> <cause>` | upgrade | recoverable | 远端失败，跳 verify |
| `VERSION_FORMAT_ERROR\|<cli> <raw>` | upgrade | recoverable | 格式不可解析，跳 verify |
| `EXE_LOCKED\|<cli>` | upgrade | recoverable | 源 exe 在跑，跳过 |
| `DISK_FULL\|<cli> <free>MB` | upgrade | recoverable | 盘空间不足，跳过 |
| `DOWNLOAD_FAIL\|<cli> <cause>` | upgrade(opencode) | recoverable | 下载/checksum-mismatch/dual-hash-mismatch/zip-slip/直连重试失败，跳过 |
| `UPGRADE_OK\|<cli> <v>` | upgrade | 成功 | 进 verify |
| `UPGRADE_FAIL\|<cli> <cause>` | upgrade | recoverable | 该 cli 失败，继续下一个 |
| `VERIFY_OK\|<cli> <v> matches=true healthy=true sha256=<或空>` | verify | 成功 | 晋升凭证（仍需新鲜度/完整性/pin 判定） |
| `VERIFY_FAIL\|<cli> <cause>` | verify | recoverable | 不晋升，D 盘入口不动 |
| `SYNC_COPY\|<cli> <bytes>` | sync | 成功 | 已复制+字节复核+sha256 复核 |
| `SYNC_SKIP\|<cli> <reason>` | sync | 成功 | 跳过（无凭证/不新鲜/pinned-mismatch/already-current） |
| `SYNC_TARGET_LOCKED\|<cli>` | sync | recoverable | 目标 exe 在跑 → 跳过 |
| `RUN_STATUS\|success\|<summary>` | sync（末步） | 终态 | 整轮成功 |
| `RUN_STATUS\|failed\|<cause>` | 任何段 | 终态 | 整轮失败（仅 fatal 触发） |
| `HOUSEKEEPING_WARNING\|<cause>` | archive | 观察 | 不改变终态 |

> **错误处置语义**：fatal 类 → fail-closed 终止整轮；recoverable 类 → 标记后继续下一个。`RUNTIME_ERROR` 按出处区分：骨架段（archive/sync）→ `RUNTIME_ERROR_FATAL`；CLI 段 → `RUNTIME_ERROR|<cli>` 继续。agent 遇未列出的 failed 类标记 → 按 fatal 处理（保守优先）。

**异常覆盖说明**：
- 单 CLI 失败（REMOTE_FAIL/UPGRADE_FAIL/VERIFY_FAIL/EXE_LOCKED/DISK_FULL/DOWNLOAD_FAIL/VERSION_FORMAT_ERROR/TARGET_PRERELEASE/LOCAL_AHEAD/NO_REMOTE/PROBE_ERROR）→ 标记、跳过、继续下一个。
- 整轮网络全断（ALL_REMOTE_FAIL）→ 不升级、sync 全 skip、RUN_STATUS|success（如实汇报网断）。
- sync 目标锁定 → SYNC_TARGET_LOCKED → 跳过不阻其他。
- 骨架级错误 → fatal 终止。

### dry-run 定位
定时任务 prompt **一律 `-Execute`**。脚本支持 dry-run 供人工预演。

---

## 9. agent 编排契约（定时任务 SOP 状态机）

**状态机图（回应 GPT#文本3）**：
```
段A: archive + probe
  archive-state ──[LOCKED|/STATE_MISSING|/PARSE_ERROR|/RUNTIME_ERROR_FATAL]──→ fatal 终止
        │ OK
        ▼
  ∀cli: probe-local → probe-remote
        │  [ALL_REMOTE_FAIL] ─────────────────────┐
        │  [RUNTIME_ERROR|<cli>] recoverable 继续 │
        │  [PARSE_ERROR] fatal 终止               │
        ▼                                          │
段B: upgrade + verify（无差别，upgrade 自判）       │
  ∀cli: upgrade -Execute                            │
        │  [UPTODATE_SKIP]  → 跳 verify            │
        │  [UPTODATE_REFRESH/ACTIONABLE/REPAIR/UPGRADE_OK] → verify
        │  [PROBE_ERROR/TARGET_PRERELEASE/LOCAL_AHEAD/NO_REMOTE/VERSION_FORMAT_ERROR
        │   /EXE_LOCKED/DISK_FULL/DOWNLOAD_FAIL/UPGRADE_FAIL] recoverable → 下一 cli
        │  [RUNTIME_ERROR_FATAL] → fatal 终止       │
        ▼                                          │
  verify-<cli>                                      │
        │  [VERIFY_OK] → sync-eligible             │
        │  [VERIFY_FAIL/RUNTIME_ERROR|<cli>] → 下一 cli │
        ▼                                          │
段C: sync + 汇报  ◄────────────────────────────────┘
  sync -Execute
        │  [SYNC_COPY/SYNC_SKIP/SYNC_TARGET_LOCKED] 逐项
        │  [RUNTIME_ERROR_FATAL] → fatal 终止
        ▼
  RUN_STATUS|success|<summary> → 汇报（数字取 sync.json.summary）
```

SOP 文档写死分段 + 标记判定表，agent 逐字执行。**全绝对路径正斜杠**，不 `cd /d`、不 `.\`。

**agent 铁律**：
1. 不现场写脚本、不临时造脚本补救，异常走标记表分支。
2. 不手算版本、不读 json 判 behind、不改 json 程序事实。
3. 不 `cd /d`、不 `.\`，全绝对路径正斜杠。
4. 不降级 PS 5.1、不去锁、不去原子写入、不做完整性校验计算（脚本算）。
5. 如实回报终态，不夸大不掩盖；数字取 sync.json.summary。
6. 每次（无论有无变更）必输出状态行汇报。
7. 遇 `LOCKED|` → 汇报 blocked，**不人工抢锁**；清锁走 §6 恢复手册全部条件。

### 固定汇报模板（段C 必输出，数字取 sync.json.summary）
1. 状态行：本轮 3 CLI 探测，升级 X / 同步 Y / 失败 Z；终态 success/failed；网络全断如实标。
2. 逐 CLI：`<cli>: <installed>→<target>`（UPTODATE_SKIP 标 `已是最新`；UPTODATE_REFRESH 标 `已是最新（凭证刷新）`；未升级标原因）。
3. 同步：`<cli> copied <bytes> sha256=<前12位>` / `<cli> skipped <reason>`（pinned-mismatch/already-current/no fresh）。
4. 异常项：失败的 CLI 逐项列原因（含 checksum-mismatch/dual-hash-mismatch/zip-slip 等完整性失败）。
5. 一句收尾备注。

无变化时第 2–4 填"无"，**状态行必输出**。

### SOP 错误场景示例（MUST 覆盖）
- 网络全断、目标 exe 锁定、opencode 下载失败（含 checksum-mismatch/dual-hash-mismatch/zip-slip）、verify 失败不晋升、凭证缺失刷新（UPTODATE_REFRESH）、手动回退 pin（pinned-mismatch/修复性晋升）、被锁阻塞（含 §6 恢复手册步骤）。
每例给"输入状态 → 标记序列 → agent 分支 → 汇报文本"。

### 推送策略
配 channel_ids → 每次执行后必推送；未配 → 不推送。凭证/sha256 不写入 prompt/推送平台。

### report_artifacts
声明 `state/sync.json` 作本轮审计产物。

---

## 10. 回退与清理

### 10.1 mise（claude/codex）
`upgrade.auto_prune=false`；回退 `mise use <tool>@<旧版>`；保留最近 2 stable。

### 10.2 opencode（github-binary）
staging 保留最近 2 版；升级失败 → 不写新鲜凭证 → sync 不动 D 盘；显式回退重跑 upgrade 指定旧 tag 或建 pin。stub 不复现（不走 npm + ZipSlip 约束 + 完整性校验）。

### 10.3 权威入口（D 盘）+ 手动回退语义
仅 sync 写。覆盖前备份 `.previous`。目标 exe 锁定 → SYNC_TARGET_LOCKED 跳过。

**手动回退语义**：用户用 `.previous` 回退 D 盘后，**若不建 pin**，下一轮 sync 用本轮新鲜凭证自动覆盖回退版本（自动跟随 latest 的预期行为）。需保持回退版本 → MUST 建 `state/<cli>.pin` 锁定 pinVersion（§5.7），sync 遇 verified==pinVersion 修复性晋升、遇 verified≠pinVersion skip pinned-mismatch。

### 10.4 流程产物
`state/archive/<时间戳>/` 每轮归档；`staging/` 保留最近 2 版；`TEMP/` 交付前空；`run.lock` 残留按 §6 恢复手册清；`*.tmp` 由 archive-state 首步清理。

### 10.5 opencode npm 全局
暂保留作 fallback，待方案稳定（连续 N 轮 sync 成功）后卸载。

---

## 11. 可追溯

- 每轮首步 archive-state 归档 `state/*.json`（不含 run.lock、archive/、current-run.json、pin）到 `archive/<时间戳>/`。
- `fetch_run.log` 累积每轮 `[时间] runId=<id> probed=N upgraded=X synced=Y failed=Z`。
- sync.json.entries 携 sha256 证据链（source/target/previous）。
- spec/脚本/json 全带 specVersion；版本历史见 §16。

---

## 12. 与参照系差异（自检）

| 维度 | Software_Update_Monitor v0.2.2 | Release-Monitor | 本项目 v0.2.4 |
|---|---|---|---|
| 范围 | monitor-only | monitor-only | monitor+download+install+switch+rollback |
| 模块粒度 | — | 合并 monitor.ps1 | 4 拆模块 |
| 状态源 | Manifest+SQLite | md+result.json | state/*.json |
| 锁 ownership | — | PID 匹配 | runId 匹配 |
| 晋升闸 | — | — | 本轮新鲜凭证+sha256 完整性+pin 保护 |
| 供应链完整性 | — | — | checksum MUST + 双 hash SHOULD + ZipSlip 约束 |
| 形态 | 通用工具 spec | 个人定时监测 | 个人定时维护流程 |

---

## 13. v0.2.4 迁移项（首次执行）

1. 新建 `D:\AI\Programs\CLI\{claude,codex,opencode}\`（claude 已手动补全；新机重装仍需此步）。
2. **首轮 seed 路径**：由 `UPTODATE_REFRESH` 机制天然完成——首轮即使所有 CLI UPTODATE，凭证缺失触发 verify 产出 seed 凭证 → sync copy。D 盘已有正确版本则 `already-current` 幂等跳过。
3. 当前已验证版本：claude 2.1.273 / codex 0.154.0 / opencode 1.18.31。
4. 旧散路径 `D:\AI\Programs\{Claude-Code-CLI, opencode\CLI}\` → 确认无引用后清空（含 .git 段手动删除）。
5. opencode 安装源切换：npm → GitHub binary staging；首次 probe-local 扫 staging（空 → LOCAL_EMPTY → 触发首次 upgrade）。
6. mise 配置加 `upgrade.auto_prune=false`。
7. 现有散脚本（`.old/`）→ 按 §7 模块清单拆分重命名（-v0.2.4 / $ScriptVersion）。
8. 产出 `cli-autoupdate-sop.md`（含 §6 锁恢复手册 + §9 错误场景示例）。

**配置/数据迁移**：无 config.json、无 SQLite/DB、无用户数据。迁移即脚本与入口目录物理迁移。状态 schema 跨版本靠 `specVersion` 标识。

---

## 14. 待确认 / 已知风险

1. **opencode GitHub release asset/tag/checksum 实测**：asset 名 + repo + 是否有 checksum asset 为起点假设；probe 核实。
2. **反代可靠性 + 双 hash 成本**：反代不可用回退直连；双 hash 比对（无 checksum asset 时）代价是双下载，MAY 偏离但须标注。
3. **runId 锁模型实现细节**：续锁独占/消失统一 fail-closed（§6 已闭合到 SOP + 恢复手册）；陈锁接管 PID 死亡判定在 Cherry 沙箱下可靠性待实测。
4. **current-run.json 与 run.lock 一致性**：一处损坏 → fail-closed 终止。
5. **opencode npm 全局卸载判据**：连续 N 轮 sync 成功，N 待定。
6. **opencode 官方 checksum 覆盖率**：若多数 release 无 checksum asset，双 hash 比对成常态（成本），probe 实测后定 SHOULD 强度是否升级为 MUST。

---

## 15. 测试策略

- **单元**：`Compare-SemVer`（边界）、`Invoke-Proc`（超时/Kill）、健康检查分型、SHA256 计算、ZipSlip 解压（构造恶意 entry：`..\`、绝对路径、symlink → 必拒）、凭证新鲜度判定、pin 规则（verified==pin 修复性晋升 / verified≠pin skip / pin 不阻断 upgrade）。
- **集成**：每 CLI probe→upgrade→verify 串；覆盖 UPTODATE_SKIP/REFRESH/NO_REMOTE/LOCAL_AHEAD/TARGET_PRERELEASE/checksum-mismatch/dual-hash-mismatch/zip-slip 各分支。
- **端到端**：archive→三 CLI cycle→sync 全流程；覆盖成功/uptodate-refresh/网络全断/exe 锁定/verify 失败/pin 锁定（含修复性晋升）/被锁阻塞（含恢复手册）八场景；穿插 re-probe。
- **环境**：仅 Windows 11 + PowerShell 7.6.4 + Cherry 沙箱。

测试在脚本实现阶段做。

---

## 16. 版本历史

| 版本 | 日期 | 摘要 | 文件 |
|---|---|---|---|
| v0.1 | 2026-09-16 | 初版：混合架构（mise+GitHub binary+晋升闸） | `SPEC-v0.1.md` |
| v0.2 | 2026-09-16 | 运行锁、标记协议、原子写入、fail-closed、opencode 回退 | `SPEC-v0.2.md` |
| v0.2.1 | 2026-09-16 | behind 下移 upgrade、runId 锁、无差别调用、SOP 层 | `SPEC-v0.2.1.md` |
| v0.2.2 | 2026-09-16 | Zoo 审计复核：术语表/版本历史/测试策略/版本格式验证/SOP 错误场景；驳回误读意见 | `SPEC-v0.2.2.md` |
| v0.2.3 | 2026-09-16 | CodeBuddy 审计复核：F1–F6（凭证生命周期/标记闭合/错误语义分层/数字源/REPAIR/锁空转） | `SPEC-v0.2.3.md` |
| v0.2.4 | 2026-09-16 | GPT 治理评审复核：供应链完整性强化（sha256 凭证+checksum MUST+双 hash SHOULD，驳回自维护 manifest）+ ZipSlip 约束 + pin 语义重写 + sync 二进制证据链 + 锁恢复手册 + RFC2119 关键词 + schema 总表 + 状态机图 | `SPEC-v0.2.4.md`（本文件） |

---

## 17. 术语表

| 术语 | 定义 |
|---|---|
| CLI | claude/codex/opencode 三个命令行工具 |
| mise | 版本管理器，管 claude/codex |
| staging | 升级场层，下载/验证落点 |
| promotion | 权威入口层，`D:\AI\Programs\CLI\<name>\<name>.exe` |
| 晋升闸 | sync 只复制本轮新鲜凭证+完整性通过的 CLI |
| 凭证 | verified.json，`matchesTarget && healthy && runAt≥startAt && sha256通过` |
| 凭证新鲜度 | verified.runAt ≥ current-run.startAt |
| pin | state/<cli>.pin，锁定目标版本=pinVersion，只作用于 sync |
| sha256 证据链 | sync.json.entries 的 source/target/previous sha256 |
| ZipSlip | zip 路径穿越攻击，本项目 MUST 拒绝 `..\`/绝对路径/symlink entry |
| 双 hash 比对 | 无 checksum asset 时，反代下载与直连下载 SHA256 一致才接受 |
| SemVer | `Major.Minor.Patch[-prerelease]`，限制版 |
| 原子写入 | tmp → 回读校验 → Move-Item 同卷替换 |
| runId | archive 首步生成的 uuid，锁 ownership 凭证 |
| fatal / recoverable | 错误分层：fatal 终止整轮；recoverable 单 CLI 失败继续 |
| 反代前缀 | `https://gh.jasonzeng.dev/`，失效直连回退 |
| dry-run | 无 -Execute 模式，预演 |
| fail-closed | 失败 → 终止不降级不静默跳过 |
| MUST/SHOULD/MAY | RFC2119：必须/应/可 |
