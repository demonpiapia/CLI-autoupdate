# CLI 自动升级 —— 项目规格 SPEC v0.2.2

> **版本**：SPEC-v0.2.2（2026-09-16）。
> **变更摘要（v0.2.1 → v0.2.2）**：架构不动。据 Zoo 审计报告独立复核后修订——采纳少数合理内核（补术语表、版本历史、测试策略、版本格式验证说明、SOP 错误场景要求、格式一致性），并针对审计基于误读/范围误解的多数意见在相关章节补"已覆盖"显式说明（更新源固定清单、Move-Item 同卷原子前提、verify 即功能测试、异常标记覆盖面、目录与锁与迁移已存在），使审计者下次能对上实际文档。逐条采纳/驳回理由见交付汇报。
> **角色定位**：本文件是 **Plan / 契约**（治理路线图的 Approved Plan 位）。契约层为硬约束；PowerShell 实现属 Executor 有界自治。

---

## 0. 项目定位、范围与交付物

本项目是 **monitor + download + CLI 全局维护** 整体过程：从"探测是否有新版本"到"实际升级、切换、对外暴露统一入口"的完整闭环。

**运行形态（澄清，防范围误读）**：本项目是 Cherry Studio 定时任务驱动、agent 编排、PowerShell 7 模块化的**个人维护流程**，维护对象是三个固定 CLI（claude/codex/opencode）。**不是**通用 CLI 自动更新软件产品——无 config.json 配置文件、无 `cli update` 用户命令、无跨平台（仅 Windows）、无许可证/贡献指南、不做 RSA 签名验证（更新源固定且由 mise/GitHub 自身保证完整性）。审计若按"通用产品"提要求，需先核对此范围。

参照系（批判借鉴设计哲学，不照搬形态）：
- `Software_Update_Monitor_Spec_v0.2.2`（monitor-only）——本项目是其 Executor 下游延伸。
- `cherry-auto-apps-Release-Monitor`（已上线）——借鉴段内一气呵成、数据固化、运行锁、stdout 标记协议、原子写入、agent 不介入计算的工程哲学。不照搬其合并脚本形态（本项目含下载/切换/回退/晋升闸，复杂度更高，需 4 拆模块）。

**交付物三层**：
1. **SPEC**（本文件）——设计契约，给 audit / 维护者。
2. **执行 SOP**（`cli-autoupdate-sop.md`，待产出）——给定时任务执行 agent 逐字读的标准化流程；agent 只读 SOP，不读本 spec。SOP 须含成功与错误场景示例（见 §9）。
3. **脚本**（`*-v0.2.2.ps1`）——模块化实现。

---

## 1. 设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | 模块化 | 每 CLI 拆 probe-local / probe-remote / upgrade / verify 四独立脚本，可单独改、单独测。共享 sync 单脚本。 |
| 2 | 数据固化 | 每步结果落 `state/*.json`；下一步读上一步文件取数据。状态走文件，不走 agent 记忆、不走 agent 手填。 |
| 3 | 流程化 | 定时 agent = 执行固定状态机 + 读标记判段间分支 + 报告异常。不写脚本、不手算版本、不改程序事实。 |
| 4 | 晋升闸 | sync 只消费"verified-success"（`<cli>-verified.json` 且 `matchesTarget && healthy`）。未过验证的 CLI，D 盘权威入口原封不动。 |
| 5 | fail-closed | schema 校验失败 → 整轮终止，不写回、不降级、不静默跳过。 |
| 6 | 原子写入 | 状态文件与权威入口经「临时文件 → 回读校验 → Move-Item 原子替换」；Move-Item 在**同卷**内为原子（Windows 同卷 rename 原子），staging 与 promotion 跨卷时先 Copy 到目标卷临时文件再同卷 Move。失败回滚不污染原文件。 |
| 7 | 运行锁 | 多段 pwsh 调用经运行锁互斥。ownership 靠 runId 匹配（不靠 PID），PID 仅作陈锁死亡判据。 |
| 8 | 可追溯 | 每轮归档 `state/archive/<时间戳>/`；fetch_run.log 累积；spec/脚本/json 带 specVersion。任何修改迭代版本号。 |
| 9 | 隔离 | staging（E 盘 mise / 工作区 staging）与 promotion（D 盘 `D:\AI\Programs\CLI\`）物理分离。 |
| 10 | 机器事实/叙事分层 | `state/*.json` 机器事实，agent 只读不写；agent 可写的是汇报叙事层。 |

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging** | claude/codex：`E:\...\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\`；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证的新版本落点 | upgrade 脚本（运行锁内） |
| **Promotion** | `D:\AI\Programs\CLI\<name>\<name>.exe` | 全局唯一"正确版本"，所有 harness 从此调用；last-known-good 回退源 | **仅 sync，且仅 verified-success 的 CLI，运行锁内** |

两层架构本身就是"先在 staging 部署验证，通过后才原子交换到 promotion"——审计 C1 建议的"先部署临时目录、验证通过后原子交换"策略，本项目已由 staging/promotion 分层 + 晋升闸 + verify 脚本原生实现，无需另造。

所有 harness 固定调用 `D:\AI\Programs\CLI\<name>\<name>.exe`，不依赖 mise shim / `MISE_*` / PATH（已实测三 exe 为独立二进制）。

---

## 3. 统一入口布局

```
D:\AI\Programs\CLI\claude\claude.exe
D:\AI\Programs\CLI\codex\codex.exe
D:\AI\Programs\CLI\opencode\opencode.exe
```

未来新增 CLI 同理。旧散路径（`Claude-Code-CLI\` / `Codex\CLI\` / `opencode\CLI\`）首次 sync v0.2.2 时迁移（§13）。

---

## 4. 目录与状态文件布局

```
D:\AI\Workspace\automatic\CLI-autoupdate\
├── SPEC-v0.2.2.md                    # 本文件（契约）
├── cli-autoupdate-sop.md             # 执行 SOP（给定时 agent，待产出）
├── cli-common-v0.2.2.ps1             # 共享库
├── probe-local-<cli>.ps1             # 每 CLI 一份（3 份）
├── probe-remote-<cli>.ps1            # 每 CLI 一份（3 份）
├── upgrade-<cli>.ps1                 # 每 CLI 一份（3 份）；内含 behind 判定
├── verify-<cli>.ps1                  # 每 CLI 一份（3 份）；即装后功能测试
├── sync-v0.2.2.ps1                   # 共享单脚本
├── archive-state.ps1                 # 每轮首步：争锁+归档+生成 runId
├── state\                            # 固定路径，最新覆盖
│   ├── current-run.json              # 本轮 runId + 起始时间
│   ├── <cli>-local.json
│   ├── <cli>-remote.json
│   ├── <cli>-upgrade.json
│   ├── <cli>-verified.json
│   ├── sync.json
│   ├── run.lock                      # 运行锁（runId 模型）——回应审计 M3"缺锁文件"：已存在
│   ├── fetch_run.log                 # 累积日志——回应审计 M3"缺日志"：已存在
│   └── archive\<时间戳>\             # 每轮归档
├── staging\opencode\<ver>\           # opencode 解压落点（含下载/解压临时产物，清理见 §10.4）
└── TEMP\                             # 交付前必空——回应审计 M3"缺临时目录"：已存在
```

状态目录决策：**固定 `state/` 最新覆盖 + 每轮 archive**（Cherry 每段 Bash 是新 shell，固定路径让段间脚本能直接定位，无需 agent 跨段传目录名）。

---

## 5. 数据契约（state/*.json）

所有 JSON 顶层带 `specVersion`（`"0.2.2"`）、`runAt`（ISO UTC）。时间内部 UTC，展示 UTC+08:00。

**更新源固定清单（澄清，回应审计 C3"缺更新源白名单"）**：本项目更新源是固定且硬编码的，不是用户可配置的任意源，故无需白名单/trustedHosts 配置：
- claude/codex：mise registry（`mise ls-remote` + `mise upgrade`，mise 自身校验包完整性）。
- opencode：`anomalyco/opencode` GitHub releases（固定 repo；下载经反代 `https://gh.jasonzeng.dev/`，反代失效回退直连）。
- 超时已内置：Invoke-Proc 对 mise ls-remote 60s、upgrade 600s、exe --version 30s（§7.1）。
- 日志已有：`state/fetch_run.log`（§4/§11）。
- "是否启用自动更新"开关 = 定时任务本身（不配 cron 即不跑），无需配置项。

### 5.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.2.2", "name":"codex", "channel":"mise",
  "version":"0.154.0", "exePath":"...", "bytes":298169136, "mtime":"...",
  "healthy":true, "error":null, "runAt":"..." }
```
- `healthy`：exe > 1MB 且 `--version` 可启动（防 opencode 479B stub）。
- opencode staging 空 → `version=null, exePath=null, healthy=false`（触发首次 upgrade）。

### 5.2 `<name>-remote.json`（probe-remote 产出）
```json
{ "specVersion":"0.2.2", "name":"opencode", "channel":"github-binary",
  "latest":"1.18.31", "count":null, "sourceUrl":"https://gh.jasonzeng.dev/https://...",
  "assetName":"opencode-windows-x64.zip", "fallbackUsed":false, "error":null, "runAt":"..." }
```
- **mise 通道**：`mise ls-remote <tool> --json` 最高 stable。
- **github-binary 通道**：`releases/latest` → tag_name（去 `v`）+ assets 筛 `windows-x64.zip`；`sourceUrl` 存加速后地址。
  - **回退**：`releases/latest` 失败 → `releases?per_page=10` 取最高 stable、prerelease=false；`fallbackUsed=true`。
  - **下载校验（回应审计 M4"缺 checksum"）**：upgrade 下载 zip 后校验大小 > 1MB（防半下载/stub），失败 → `DOWNLOAD_FAIL|`。若 release 附 checksum asset（如 `*.sha256` / `checksums.txt`）则校验 SHA256（probe 阶段实测确认是否存在）。mise 通道完整性由 mise 自身保证。
  - **已知坑（probe 实测确认）**：`anomalyco/opencode` 的 tag 在列表接口曾现异常拼接（Release-Monitor 观测）；asset 名 `opencode-windows-x64.zip` 为起点假设，probe 核实。

### 5.3 `<name>-upgrade.json`（upgrade 产出，仅实际升级时写）
```json
{ "specVersion":"0.2.2", "name":"codex", "fromVersion":"0.152.0", "target":"0.154.0",
  "exitCode":0, "ok":true, "error":null, "runAt":"..." }
```

### 5.4 `<name>-verified.json`（verify 产出；晋升凭证）
```json
{ "specVersion":"0.2.2", "name":"codex", "version":"0.154.0",
  "exePath":"...", "bytes":298169136, "healthy":true, "matchesTarget":true, "runAt":"..." }
```
- **晋升条件**：`matchesTarget==true && healthy==true`。缺/不满足 → sync 跳过该 CLI。
- verify 脚本即"装后功能测试"（回应审计 M4"缺安装后功能测试"）：verify 跑 `exe --version` 验证可启动 + 版本号匹配 target，落 verified.json。

### 5.5 `sync.json`（sync 产出）
```json
{ "specVersion":"0.2.2", "runAt":"...",
  "entries":[
    {"name":"codex","source":"...","target":"D:\\AI\\Programs\\CLI\\codex\\codex.exe",
     "action":"copy","bytes":298169136,"ok":true},
    {"name":"opencode","action":"skip","reason":"exe locked / no verified-success"}
  ] }
```

### 5.6 `current-run.json`（archive-state 首步生成）
```json
{ "specVersion":"0.2.2", "runId":"<uuid>", "startAt":"<UTCISO>", "archivedTo":"archive\\<ts>" }
```

### 5.7 校验与原子写入（fail-closed）
每状态文件落盘走「写 `*.tmp` → `ConvertFrom-Json` 回读校验关键字段 → `Move-Item` 原子替换」。Move-Item 同卷原子（Windows 同卷 rename）；跨卷场景先 Copy 到目标卷临时文件再同卷 Move。校验失败 → 不替换、输出 `RUNTIME_ERROR|<cause>`、释放锁、终止。

---

## 6. 运行锁模型（runId ownership）

跨 Bash 段 PID 必变（Cherry 每段新 shell），故 ownership **不靠 PID 匹配**，靠 runId：

- **争锁**（archive-state 首步）：`[IO.File]::Open(run.lock, FileMode::CreateNew, FileAccess::ReadWrite, FileShare::None)` 原子争锁；成功后写 `runId=<uuid>;start=<iso>;beat=<iso>;pid=<PID>`，runId 写入 `current-run.json`。
- **续锁**（后续每段脚本进入）：open 锁文件独占 → 读 runId → 与 `current-run.json` 比对 → 匹配则刷新 beat；不匹配或被独占 → `LOCKED|` 退出。
- **陈锁接管**：beat 超 30 分钟 **且** 锁内 PID 经 `Get-Process -Id` 确认死亡 → 删锁重争；任何不确定 → 保守 `LOCKED|`。
- **释放**：sync 末步或异常分支，确认 runId 匹配后删锁。
- runId 经 `current-run.json` 传递，agent 不碰（脚本自读）→ agent 零状态。

> 回应审计 M1"缺并发控制"：本项目已有完整运行锁（争锁 + heartbeat + 陈锁接管），且 ownership 靠 runId 解跨段 PID 失配——比审计给的 `Test-Path lockFile`（有 TOCTOU 竞态）更完善。

---

## 7. 模块清单

### 7.1 共享库 `cli-common-v0.2.2.ps1`
`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`，异步排空 stdout/stderr 再 WaitForExit+Kill，防管道死锁；超时：mise ls-remote 60s、upgrade 600s、exe --version 30s）、semver（`Compare-SemVer`：去 `v` 前缀，比较 Major.Minor.Patch，prerelease 低于 stable，不支持 build 元数据参与比较——与 Release-Monitor `Compare-Ver` 同口径）、`Get-CherryMiseEnv`/`Get-MiseExePath`/`Get-MiseInstallsDir`/`Get-NpmPrefix`、GitHub 加速 URL 构造器、zip 解压、健康检查（>1MB + `--version`）、运行锁原语（争锁/续锁 runId/释放/陈锁接管）、状态文件原子写入助手、runId 生成与读取。

### 7.2 每 CLI 一套（4 拆模块，数据靠 json 衔接）

| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver 目录 → version+exePath+healthy | 扫 `staging\opencode\<ver>\` → version+exePath+healthy |
| `probe-remote-<cli>.ps1` | `mise ls-remote --json` 最高 stable | `releases/latest` + 失败回退列表（§5.2） |
| `upgrade-<cli>.ps1` | 读 local+remote json → **内部 Compare-SemVer 判 behind** → UPTODATE 或 `mise upgrade <tool>@latest` | 读 remote.sourceUrl → 下载 zip（加速）→ 大小/checksum 校验 → 解压 staging |
| `verify-<cli>.ps1` | 重扫 mise installs → version+exePath+healthy+matchesTarget | 跑 staging exe `--version` → 同字段 |
| `sync-v0.2.2.ps1`（共享） | 遍历三 CLI `verified.json`，仅 `matchesTarget && healthy` → copy 到 `D:\AI\Programs\CLI\<name>\<name>.exe`，字节复核，覆盖前备份 `.previous` | 同左 |

### 7.3 behind 判定与版本规则（upgrade 内部）
**behind 判定在 `upgrade-<cli>.ps1` 内部完成**：读 `local.json` + `remote.json` → `Compare-SemVer` →
- local == remote 且 healthy → `UPTODATE|<cli> <v>`，不执行、不写 upgrade.json，agent 跳过 verify。
- local < remote 且 target stable → `ACTIONABLE|<cli> <from>-><to>`，执行升级。
- local.healthy==false → `REPAIR|<cli>`，强制重装（即使版本号相同；opencode stub 场景）。
- target prerelease → 不执行（stable-only 策略），输出标记报告。
- local > remote 或 incomparable → 输出标记报告，**不执行**（回应审计 C2"local>remote 跳过可能是错误安装"：不静默跳过，而是显式报告异常，agent 汇报，不自动降级/不自动升级）。

**版本格式验证（回应审计 C2"缺版本格式验证"）**：`Compare-SemVer` 解析失败（非 `\d+\.\d+\.\d+` 核心段）→ 返回 incomparable → upgrade 输出 `VERSION_FORMAT_ERROR|<cli> <raw>` 标记、不执行、报告。不"用默认版本号"（那会掩盖问题，违反 fail-closed）。

**关于强制更新/降级（驳回审计 C2 建议）**：本项目策略明确 stable-only 跟随 latest，不做强制更新（无 force 标记）、不做自动降级（降级由用户手动 `mise use`，§10.1）。这是项目策略决定，非缺陷。

agent **无差别**对每 CLI 调 probe-local→probe-remote→upgrade→verify，upgrade 自判跳过；agent 不维护"待升级清单"。

### 7.4 版本号
共享库与 sync 文件名含 `-v0.2.2`；probe/upgrade/verify 每 CLI 一份，内部首行 `$ScriptVersion='0.2.2'` + `# SPEC: v0.2.2`。各 CLI 各一套（渠道差异大，彻底模块化）。

---

## 8. 机器状态标记协议（整轮终态唯一依据）

每脚本 stdout 输出 ASCII 标记（`|` 分隔），agent 只读标记判段间分支，不解析 json、不心算。退出码并行约定：`0`=无事可做/已满足；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败；`3`=执行失败或复核不过。**agent 以 stdout 标记为准**。

| 标记 | 产出脚本 | 判定 |
|---|---|---|
| `LOCKED\|` | 任何段 | blocked，本轮终止 |
| `STATE_MISSING\|` | archive/probe-local | blocked |
| `PARSE_ERROR\|` | 任何段 | failed，不写回原文件 |
| `RUNTIME_ERROR\|<cause>` | 任何段 | failed |
| `LOCAL_OK\|<cli> ver=<v> healthy=<bool>` | probe-local | 阶段成功 |
| `LOCAL_EMPTY\|<cli>` | probe-local | staging 空（opencode 首次）→ 仍进 upgrade |
| `REMOTE_OK\|<cli> latest=<v> fallback=<bool>` | probe-remote | 阶段成功 |
| `REMOTE_FAIL\|<cli> <cause>` | probe-remote | 该 cli 远端失败，仍进 upgrade（读 local 旧值自判） |
| `ALL_REMOTE_FAIL\|` | probe-remote 末 | 三 CLI 全 REMOTE_FAIL（网络全断）→ 跳过 upgrade/verify，直进 sync，RUN_STATUS\|success\| |
| `UPTODATE\|<cli> <v>` | upgrade | 无需升级，跳过 verify |
| `ACTIONABLE\|<cli> <from>-><to>` | upgrade | 有升级动作 |
| `REPAIR\|<cli> <reason>` | upgrade | healthy=false 触发重装 |
| `VERSION_FORMAT_ERROR\|<cli> <raw>` | upgrade | 版本格式不可解析（fail-closed，不执行） |
| `EXE_LOCKED\|<cli>` | upgrade | 源 exe 在跑，跳过该 cli |
| `DISK_FULL\|<cli> <free>MB` | upgrade | 盘空间不足，跳过该 cli |
| `DOWNLOAD_FAIL\|<cli> <cause>` | upgrade(opencode) | zip 下载/校验失败，跳过该 cli |
| `UPGRADE_OK\|<cli> <v>` | upgrade | 进 verify |
| `UPGRADE_FAIL\|<cli> <cause>` | upgrade | 该 cli 失败，继续下一个 |
| `VERIFY_OK\|<cli> <v> matches=true healthy=true` | verify | **晋升凭证**，sync-eligible |
| `VERIFY_FAIL\|<cli> <cause>` | verify | 不晋升，D 盘入口不动 |
| `SYNC_COPY\|<cli> <bytes>` | sync | 已复制并字节复核 |
| `SYNC_SKIP\|<cli> <reason>` | sync | 跳过（无凭证/unhealthy） |
| `SYNC_TARGET_LOCKED\|<cli>` | sync | 目标 exe 在跑 → 跳过该 cli，不阻其他 |
| `RUN_STATUS\|success\|<summary>` | sync（末步） | 整轮成功 |
| `RUN_STATUS\|failed\|<cause>` | 任何段 | 整轮失败 |
| `HOUSEKEEPING_WARNING\|<cause>` | archive | 辅助观察，不改变终态 |

> 回应审计 M2"错误处理不全"：上表已覆盖网络（REMOTE_FAIL/ALL_REMOTE_FAIL）、超时（Invoke-Proc 超时→RUNTIME_ERROR/UPGRADE_FAIL）、磁盘（DISK_FULL）、权限（沙箱写 D 盘已实测不需管理员；若遇权限错误→RUNTIME_ERROR）、版本格式（VERSION_FORMAT_ERROR）、并发冲突（LOCKED）。权限错误不单列标记——归入 RUNTIME_ERROR，agent 汇报 cause。

**异常覆盖说明**：
- 单 CLI 失败（REMOTE_FAIL/UPGRADE_FAIL/VERIFY_FAIL/EXE_LOCKED/DISK_FULL/DOWNLOAD_FAIL/VERSION_FORMAT_ERROR）→ 标记、跳过该 CLI、继续下一个，不阻断整轮。
- 整轮网络全断（ALL_REMOTE_FAIL）→ 不升级、sync 全 skip、RUN_STATUS|success（如实汇报网断）。
- sync 目标锁定 → SYNC_TARGET_LOCKED → 跳过该 CLI 不阻其他。

### dry-run 定位
定时任务 prompt **一律 `-Execute`**。脚本支持无 `-Execute` 的 dry-run 供人工预演。agent 不主动用 dry-run，除非用户明确要求。

---

## 9. agent 编排契约（定时任务 SOP 状态机）

SOP 文档（`cli-autoupdate-sop.md`）里写死分段 + 标记判定表，agent 逐字执行。**全绝对路径正斜杠**，不 `cd /d`、不 `.\`。

```
段A · 归档 + 探测（agent 无差别调，不判版本）
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/archive-state.ps1
    → 争锁+生成 runId+归档；LOCKED|/RUNTIME_ERROR| → blocked 终止
  对每 cli ∈ [claude, codex, opencode]（顺序固定）:
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/probe-local-<cli>.ps1
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/probe-remote-<cli>.ps1
    读标记：LOCAL_OK|/REMOTE_OK| → 进段B该 cli
            ALL_REMOTE_FAIL| → 跳过 upgrade/verify，直进段C
            RUNTIME_ERROR| → 标记该 cli 失败，继续下一个

段B · 升级 + 验证（agent 无差别调，upgrade 内部自判跳过）
  对每 cli（无差别，不预先筛"待升级"）:
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/upgrade-<cli>.ps1 -Execute
      → UPTODATE| → 跳过 verify，进下一 cli
         ACTIONABLE|/REPAIR| → UPGRADE_OK| 进 verify / UPGRADE_FAIL| 标记失败进下一 cli
         EXE_LOCKED|/DISK_FULL|/DOWNLOAD_FAIL|/VERSION_FORMAT_ERROR| → 标记跳过，进下一 cli
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/verify-<cli>.ps1
      → VERIFY_OK| → 标记 sync-eligible；VERIFY_FAIL| → 不晋升，进下一 cli

段C · 同步 + 汇报
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/sync-v0.2.2.ps1 -Execute
    → SYNC_COPY|/SYNC_SKIP|/SYNC_TARGET_LOCKED| 逐项；RUN_STATUS|success| → 整轮成功
  基于 sync.json 生成汇报（数字取 sync.json，禁止自行统计）
  report_artifacts 声明 state/sync.json 作本轮审计产物
```

**agent 铁律**：
1. 不现场写脚本、不临时造脚本补救，异常走标记表分支。
2. 不手算版本、不读 json 判 behind、不改 json 程序事实。
3. 不 `cd /d`、不 `.\`，全绝对路径正斜杠。
4. 不降级 PS 5.1、不去锁、不去原子写入。
5. 如实回报终态，不夸大不掩盖；数字取 sync.json。
6. 每次（无论有无变更）必输出状态行汇报，让用户确认任务在跑。

### 固定汇报模板（段C 必输出，数字取 sync.json）
1. 状态行：本轮 3 CLI 探测，升级 X / 同步 Y / 失败 Z；终态 success/failed；网络全断时如实标。
2. 逐 CLI：`<cli>: <installed>→<target>`（UPTODATE 标 `已是最新`；未升级标原因）。
3. 同步：`<cli> copied <bytes>` / `<cli> skipped <reason>`。
4. 异常项：失败的 CLI 逐项列原因（exe locked / disk full / download fail / verify fail / version format error）。
5. 一句收尾备注（opencode fallback / 网络全断 / 其他需提的）。

无变化时第 2–4 填"无"，**状态行必输出**。

### SOP 错误场景示例（回应审计 m2）
SOP 文档须含错误场景示例章节，覆盖：网络全断（ALL_REMOTE_FAIL → sync 全 skip → 汇报网断）、目标 exe 锁定（SYNC_TARGET_LOCKED → 跳过不阻其他）、opencode 下载失败（DOWNLOAD_FAIL）、verify 失败不晋升（VERIFY_FAIL → D 盘入口不动）。每例给"输入状态 → 标记序列 → agent 应走分支 → 汇报文本"。

### 推送策略
推送与否由定时任务 `channel_ids` 配置决定：
- 配了 channel_ids → 每次执行后必推送（有变更详列、无变更简述"本轮 3 CLI 探测，无变化"）。
- 未配 → 不推送，只输出汇报。
凭证不写入 prompt/状态文件/推送平台。

### report_artifacts 交付物
声明 `state/sync.json`（绝对路径）作本轮审计产物。CLI 升级项目无面向用户的 md 产物。

---

## 10. 回退与清理

### 10.1 mise（claude/codex）
- `upgrade.auto_prune=false`（保留旧版本目录）。
- 回退：`mise use <tool>@<旧版>`（手动降级途径，回应审计 C2"缺降级支持"：降级是用户主动操作，非自动流程）。
- prune：v0.2.2 先手动复核不自动 prune；保留最近 2 个 stable。

### 10.2 opencode（github-binary）
- staging 保留多版本目录；清到最近 2 个。
- 回退：升级失败 → 不写 verified-success → sync 不动 D 盘 → 调用照常走旧版；显式回退则重跑 upgrade 指定旧 tag。
- 479B stub 不复现（不走 npm）；zip 解压异常 → verify unhealthy → sync 跳过。

### 10.3 权威入口（D 盘）
仅 sync 写。覆盖前备份 `D:\AI\Programs\CLI\<name>\<name>.exe.previous`（一步回退）。目标 exe 锁定（CLI 在跑）→ SYNC_TARGET_LOCKED 跳过，不强替换（Windows 锁定中的 .exe 无法替换）。

### 10.4 流程产物
- `state/archive/<时间戳>/` 每轮归档；`staging/` 保留最近 2 版；`TEMP/` 交付前空。
- `run.lock` 残留且锁内 PID 已死亡 → move_to_trash 清锁；PID 仍存活 → 不强 kill，报告等超时。
- `*.tmp` 中间文件异常中断由 archive-state 首步清理。

### 10.5 opencode npm 全局
npm 全局 `opencode-ai` **暂保留**作 fallback，待本套方案落地稳定运作（全局调用已指向 D 盘唯一正确版本，连续 N 轮 sync 成功）后卸载。

---

## 11. 可追溯

- 每轮首步 archive-state 归档 `state/*.json`（不含 run.lock、archive/、current-run.json）到 `state/archive/<时间戳>/`，生成 runId。
- `state/fetch_run.log` 累积每轮 `[时间] runId=<id> probed=N upgraded=X synced=Y failed=Z`。
- spec/脚本/json 全带 specVersion；版本历史见 §16。

---

## 12. 与参照系差异（自检）

| 维度 | Software_Update_Monitor v0.2.2 | Release-Monitor | 本项目 v0.2.2 |
|---|---|---|---|
| 范围 | monitor-only | monitor-only | **monitor+download+install+switch+rollback** |
| 模块粒度 | — | 合并 monitor.ps1 | **4 拆模块**（含下载/切换/回退） |
| 状态源 | Manifest+SQLite | md+result.json | state/*.json（CLI 维度小，无需 DB） |
| 锁 ownership | — | PID 匹配（跨段失配） | **runId 匹配** |
| 晋升闸 | — | — | D 盘 verified-success 才 sync（特有） |
| 通道 | GitHub | GitHub | mise + GitHub binary |
| 形态 | 通用工具 spec | 个人定时监测 | **个人定时维护流程**（非通用产品） |

---

## 13. v0.2.2 迁移项（首次执行，回应审计 M5"缺迁移指南"）

1. 新建 `D:\AI\Programs\CLI\{claude,codex,opencode}\`。
2. 首次 sync：从当前 mise/npm 已验证 exe 拷到新布局（claude 2.1.273 / codex 0.154.0 / opencode 1.18.31，三 exe 已健康）。
3. 旧散路径 `D:\AI\Programs\{Claude-Code-CLI, Codex\CLI, opencode\CLI}\` → 确认无引用后清空（opencode\CLI 现存 479B stub 必清；含 .git 段走 R43 手动）。
4. opencode 安装源切换：npm → GitHub binary staging；首次 probe-local 扫 staging（空 → 触发首次 upgrade 从 GitHub 拉 1.18.31）。
5. mise 配置加 `upgrade.auto_prune=false`。
6. 现有散脚本（cli-common.ps1 / update-*.ps1 / sync-clis.ps1 / probe-clis-with-mistake.ps1）→ 按 §7 模块清单拆分重命名（带 -v0.2.2 / $ScriptVersion），旧文件归档 `archive/scripts-pre-v0.2.2/` 不删。
7. 产出 `cli-autoupdate-sop.md`（执行 SOP，给定时 agent）。

**配置/数据迁移**：本项目无 config.json（参数在脚本/prompt），无 SQLite/DB，无用户数据——迁移即上述脚本与入口目录的物理迁移，无需"迁移脚本"或"向后兼容层"。状态文件 schema 跨版本靠 `specVersion` 字段标识，旧 archive 可读不可混用。

---

## 14. 待确认 / 已知风险

1. **opencode GitHub release asset/tag 实测**：asset 名 `opencode-windows-x64.zip` + repo `anomalyco/opencode` 为起点假设；probe 核实 tag 格式（已知拼接异常）、latest 端点稳定性、是否有 checksum asset。
2. **反代前缀可靠性**：`https://gh.jasonzeng.dev/` 不可用时回退直连 GitHub（probe 实测）。
3. **runId 锁模型实现细节**：续锁时锁文件被独占（异常并发）vs 锁文件消失（前段异常释放）的区分；陈锁接管 PID 死亡判定在 Cherry 沙箱下是否可靠。audit 重点审此处。
4. **current-run.json 与 run.lock 一致性**：两处存 runId，一处损坏 → fail-closed 终止（不降级）。
5. **opencode npm 全局卸载判据**：方案落地稳定后（连续 N 轮 sync 成功），N 待定。

---

## 15. 测试策略（回应审计 m3）

本项目为个人维护流程，测试分三层：
- **单元**：`Compare-SemVer`（边界：prerelease、build 元数据、不可解析格式）、`Invoke-Proc`（超时/Kill、.cmd 路由）、健康检查（stub <1MB 判定）。目标覆盖核心判定函数。
- **集成**：每 CLI 的 probe-local→probe-remote→upgrade→verify 串（dry-run 验证标记序列、-Execute 验证产物落盘 + 原子写入 + fail-closed）。
- **端到端**：archive→三 CLI cycle→sync 全流程跑一轮，覆盖成功/uptodate/网络全断/exe 锁定/verify 失败五场景；穿插 re-probe（治理路线图方法论：写脚本穿插 re-probe 修订 spec）。
- **环境**：仅 Windows 11 + PowerShell 7.6.4 + Cherry 沙箱；不跨平台（项目范围）。

测试在脚本实现阶段做，非 spec 阶段。

---

## 16. 版本历史

| 版本 | 日期 | 摘要 | 文件 |
|---|---|---|---|
| v0.1 | 2026-09-16 | 初版：混合架构确立（mise+GitHub binary+晋升闸） | `SPEC-v0.1.md` |
| v0.2 | 2026-09-16 | 运行锁、标记协议、原子写入、fail-closed、opencode 回退 | `SPEC-v0.2.md` |
| v0.2.1 | 2026-09-16 | behind 判定下移 upgrade、runId 锁、无差别调用、SOP 层、汇报模板 | `SPEC-v0.2.1.md` |
| v0.2.2 | 2026-09-16 | Zoo 审计复核：补术语表/版本历史/测试策略/版本格式验证/SOP 错误场景；驳回基于误读的意见并补"已覆盖"显式说明 | `SPEC-v0.2.2.md`（本文件） |

---

## 17. 术语表（回应审计 m1）

| 术语 | 定义 |
|---|---|
| CLI | Command Line Interface，本项目指 claude/codex/opencode 三个命令行工具 |
| mise | 版本管理器，本项目用它管 claude/codex（Cherry 自定义 Toolchain 安装） |
| staging | 升级场层，新版本下载/验证的落点，不对外暴露 |
| promotion | 权威入口层，`D:\AI\Programs\CLI\<name>\<name>.exe`，全局唯一调用入口 |
| 晋升闸 | sync 只复制 verified-success 的 CLI 到 promotion，失败不污染已知好版本 |
| SemVer | Semantic Versioning，`Major.Minor.Patch[-prerelease]`；本项目 Compare-SemVer 限制版（不支持 build 元数据参与比较） |
| 原子写入 | 临时文件 → 回读校验 → Move-Item 同卷替换，失败回滚不污染原文件 |
| runId | archive 首步生成的 uuid，作运行锁 ownership 凭证，跨 Bash 段传递 |
| verified-success | `<cli>-verified.json` 中 `matchesTarget && healthy` 为真，sync 晋升凭证 |
| 反代前缀 | `https://gh.jasonzeng.dev/`，拼在 GitHub release URL 前加速下载 |
| dry-run | 无 `-Execute` 模式，输出会做什么不改盘，人工预演用 |
| fail-closed | 校验/判定失败 → 终止不降级不静默跳过 |
