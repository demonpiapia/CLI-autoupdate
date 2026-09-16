# CLI 自动升级 —— 项目规格 SPEC v0.2

> **版本**：SPEC-v0.2（2026-09-16）。文件与脚本均带版本号；后续修订递增 v0.3…。
> **前置**：本 spec 由 v0.1 修订而来。v0.1 确立的混合架构（mise 管 claude/codex + GitHub binary 管 opencode + 自写 probe/verify/sync 编排与 D 盘晋升闸）不变；v0.2 引入运行锁、状态标记协议、原子写入、fail-closed 校验等结构性硬化，并修正 opencode 通道的真实坑。
> **角色定位**：本文件是 **Plan / 契约**（对应治理路线图的 Approved Plan 位）。契约层（schema、标记、退出码、锁模型、晋升闸、agent 边界）为硬约束；PowerShell 具体实现属 Executor 有界自治范围，spec 不写代码。

---

## 0. 项目定位与范围

本项目是 **monitor + download + CLI 全局维护** 的整体过程，覆盖从"探测是否有新版本"到"实际升级、切换、对外暴露统一入口"的完整闭环。

参照系：
- `Software_Update_Monitor_Spec_v0.2.2`（`D:\AI\Dev\software-update-monitor`）是 **monitor-only**——其 §12 明确不含 download/install/switch/rollback。本项目是它的 **Executor 下游延伸**：在 monitor 判定"有更新"之后，真正完成 download/install/switch/rollback 并刷新全局调用入口。
- `cherry-auto-apps-Release-Monitor`（`D:\AI\Workspace\automatic\Skills\cherry-auto-apps-Release-Monitor`，已上线运行）是成熟范式参照——分段执行、运行锁、状态标记协议、原子写入、agent 不介入计算的铁律，本项目沿用其工程模式。

维护对象：三个 CLI——claude / codex / opencode。

---

## 1. 设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | 模块化 | 每个脚本只做一件事（probe-local / probe-remote / upgrade / verify / sync）。单脚本职责单一。 |
| 2 | 数据固化 | 每步结果落 `state/*.json`；下一步读上一步文件取数据。状态走文件，不走 agent 记忆、不走 agent 手填。 |
| 3 | 流程化 | 定时 agent 的职责 = 执行固定状态机 + 读标记判段间分支 + 报告异常。agent 不写脚本、不手算版本、不改程序事实。 |
| 4 | 晋升闸（核心） | sync 只消费"verified-success"产物（`<cli>-verified.json` 且 `matchesTarget && healthy`）。未过验证的 CLI，其 D 盘权威入口原封不动 → 升级失败不污染已知好版本。 |
| 5 | fail-closed | 状态文件 schema 校验失败 → 整轮终止，不写回、不降级、不静默跳过。 |
| 6 | 原子写入 | 所有状态文件与权威入口经「临时文件 → 结构校验 → Move-Item 原子替换」写入；失败回滚不污染原文件。 |
| 7 | 运行锁 | 多段 pwsh 调用经运行锁互斥（CreateNew 争锁 + heartbeat + PID 存活检查），防并发与中断残留。 |
| 8 | 可追溯 | 每轮归档 `state/` 到 `state/archive/<时间戳>/`；fetch_run.log 累积；spec/脚本/json 带版本号。 |
| 9 | 隔离 | staging（E 盘 mise / 工作区 staging）与 promotion（D 盘 `D:\AI\Programs\CLI\`）物理分离；E 盘升级翻车碰不到 D 盘权威副本。 |
| 10 | 机器事实 / 叙事分层 | `state/*.json` 是机器事实，agent 只读不写；agent 可写的是汇报叙事层（见 §9）。 |

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging（升级场）** | claude/codex：`E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\`；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证的新版本落点 | upgrade 脚本（在运行锁内） |
| **Promotion（权威入口）** | `D:\AI\Programs\CLI\<name>\<name>.exe` | 全局唯一认可的"正确版本"，所有 harness 从此调用；last-known-good 回退源 | **仅 sync 脚本，且仅对 verified-success 的 CLI，且在运行锁内** |

所有 harness（Cherry agent / 外部终端 / 其他 harness）固定调用 `D:\AI\Programs\CLI\<name>\<name>.exe`，不依赖 mise shim / `MISE_*` / PATH（已实测三 exe 为独立二进制，剥离 MISE_* 仍 exit 0）。

---

## 3. 统一入口布局（v0.2 确定）

```
D:\AI\Programs\CLI\claude\claude.exe
D:\AI\Programs\CLI\codex\codex.exe
D:\AI\Programs\CLI\opencode\opencode.exe
```

未来新增 CLI 同理加入此目录。当前散路径（`Claude-Code-CLI\` / `Codex\CLI\` / `opencode\CLI\`）在首次 sync v0.2 时迁移到此布局（见 §13 迁移项）。

---

## 4. 目录与状态文件布局

```
D:\AI\Workspace\automatic\CLI-autoupdate\
├── SPEC-v0.2.md                      # 本文件（Plan / 契约）
├── cli-common-v0.2.ps1               # 共享库（Invoke-Proc/semver/mise env/锁/json 助手）
├── probe-local-<cli>.ps1             # 每 CLI 一份（3 份）
├── probe-remote-<cli>.ps1            # 每 CLI 一份（3 份）
├── upgrade-<cli>.ps1                 # 每 CLI 一份（3 份）
├── verify-<cli>.ps1                  # 每 CLI 一份（3 份）
├── sync-v0.2.ps1                     # 共享单脚本
├── archive-state.ps1                 # 每轮首步：归档 state/
├── state\                            # 固定路径，最新覆盖
│   ├── <cli>-local.json
│   ├── <cli>-remote.json
│   ├── <cli>-upgrade.json            # 仅升级时写
│   ├── <cli>-verified.json           # 仅验证时写；晋升凭证
│   ├── sync.json
│   ├── run.lock                      # 运行锁
│   ├── fetch_run.log                 # 累积日志
│   └── archive\<时间戳>\             # 每轮归档
├── staging\opencode\<ver>\           # opencode GitHub binary 解压落点
└── TEMP\                             # 交付前必空
```

状态目录决策（v0.2 采用）：**固定 `state/` 最新覆盖 + 每轮 archive**。理由：Cherry 每次 Bash 是新 shell、进程不持久，固定路径让段间脚本能直接定位"本轮状态"，无需 agent 跨段传递目录名；archive 满足可追溯。不采用每轮独立 `runs/<时间戳>/`（会让段间定位变复杂）。

---

## 5. 数据契约（state/*.json）

所有 JSON 顶层带 `specVersion`（当前 `"0.2"`）、`runAt`（ISO UTC，脚本内 `[DateTimeOffset]::UtcNow`）。时间内部 UTC，展示 UTC+08:00（沿用 Release-Monitor 模式）。

### 5.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.2", "name":"codex", "channel":"mise",
  "version":"0.154.0", "exePath":"E:\\...\\installs\\codex\\0.154.0\\bin\\codex.exe",
  "bytes":298169136, "mtime":"...", "healthy":true,
  "error":null, "runAt":"..." }
```
- `channel`：`mise` | `github-binary`（opencode）。
- `healthy`：exe > 1MB 且 `--version` 可启动（防 stub；opencode 的 479B 占位 stub 据此判出）。
- 首次运行（opencode staging 为空）→ `version=null, exePath=null, healthy=false`，触发首次 upgrade。

### 5.2 `<name>-remote.json`（probe-remote 产出）
```json
{ "specVersion":"0.2", "name":"codex", "channel":"mise",
  "latest":"0.154.0", "count":158, "sourceUrl":null,
  "fallbackUsed":false, "error":null, "runAt":"..." }
```
- **mise 通道**：`mise ls-remote <tool> --json` 取最高 stable（经 Invoke-Proc，带 Cherry MISE_* env，超时 60s）。
- **github-binary 通道（opencode）**：GitHub `releases/latest` → `tag_name`（去 `v` 前缀）+ `assets[].browser_download_url`（筛 `windows-x64.zip`）。`sourceUrl` 存**加速后**地址（反代前缀 `https://gh.jasonzeng.dev/` 拼原 URL）。
  - **回退策略（必填）**：`releases/latest` 失败（404 / network_error / SSL）→ 回退 `releases?per_page=10` 列表，取最高 **stable、prerelease=false** 的 tag；`fallbackUsed=true`。理由：Release-Monitor 本轮实测 `anomalyco/opencode` 的 `releases/latest` 返回 network_error，但列表接口能取到 v1.18.31（见其 result.json）。latest 端点对该 repo 不稳定。
  - **已知坑（probe 阶段实测确认）**：`anomalyco/opencode` 的 release tag 在列表接口里曾出现"一串 tag 拼在一个 tag_name"的异常拼接（Release-Monitor apiList 观测）。probe-remote-opencode 必须实测确认 tag 格式与 asset 命名（`opencode-windows-x64.zip` 是用户手动更新时下的路径，作起点假设，probe 阶段核实）。

### 5.3 `<name>-upgrade.json`（upgrade 产出，仅升级时写）
```json
{ "specVersion":"0.2", "name":"codex", "fromVersion":"0.152.0", "target":"0.154.0",
  "exitCode":0, "ok":true, "error":null, "runAt":"..." }
```

### 5.4 `<name>-verified.json`（verify 产出，仅验证时写；晋升凭证）
```json
{ "specVersion":"0.2", "name":"codex", "version":"0.154.0",
  "exePath":"E:\\...\\installs\\codex\\0.154.0\\bin\\codex.exe",
  "bytes":298169136, "healthy":true, "matchesTarget":true, "runAt":"..." }
```
- **晋升条件**：`matchesTarget==true && healthy==true`。缺此文件或条件不满足 → sync 跳过该 CLI（D 盘入口不动）。

### 5.5 `sync.json`（sync 产出）
```json
{ "specVersion":"0.2", "runAt":"...",
  "entries":[
    {"name":"codex","source":"<verified.exePath>","target":"D:\\AI\\Programs\\CLI\\codex\\codex.exe",
     "action":"copy","bytes":298169136,"ok":true},
    {"name":"opencode","action":"skip","reason":"no verified-success / unhealthy"}
  ] }
```

### 5.6 校验与原子写入（fail-closed）
- 每个状态文件落盘走「写 `*.tmp` → `ConvertFrom-Json` 回读校验 schema 关键字段存在 → `Move-Item` 原子替换」。
- 校验失败 → 不替换原文件、输出 `RUNTIME_ERROR|<cause>`、释放锁、终止本轮。不静默跳过。

---

## 6. 运行锁模型

沿用 Release-Monitor 的 `.monitor\run.lock` 模式（本项目置于 `state\run.lock`）：

- **争锁**：`[IO.File]::Open(path, FileMode::CreateNew, FileAccess::ReadWrite, FileShare::None)`——并发下只有一个进程能成功创建。
- **锁文件内容**：`pid=<PID>;start=<UTCISO>;step=<N>;beat=<UTCISO>`。
- **heartbeat**：每段脚本进入时独占打开锁文件刷新 `beat`；被独占 = 异常并发 → 输出 `LOCKED|` 退出。
- **陈锁接管**：`beat` 超 30 分钟 **且** 锁内 PID 经 `Get-Process -Id` 确认死亡，才允许删锁重争；任何不确定 → 保守 `LOCKED|`（不抢）。
- **ownership 校验**：释放锁前确认锁内 `pid=` 匹配当前进程，否则不动锁（防误删他人锁）。
- 锁在 `archive-state.ps1`（段A 首步）争持，整轮持有，sync 完成或异常分支释放。

> 注：本项目多段（archive→probe-local→probe-remote→upgrade→verify→sync）同属一轮运行锁。段间 agent 不持锁（agent 是新 shell），锁文件跨段传递 ownership 靠 PID——若跨段 PID 变化，释放逻辑需用"本轮起始 PID 记录 + heartbeat 新鲜"判定，而非 `$PID -eq lockPid`（Release-Monitor 补丁#1 的教训）。实现时按此设计。

---

## 7. 模块清单

### 7.1 共享库 `cli-common-v0.2.ps1`
承载：`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`，异步排空 stdout/stderr 再 WaitForExit+Kill，防管道死锁）、semver 比较、`Get-CherryMiseEnv` / `Get-MiseExePath` / `Get-MiseInstallsDir` / `Get-NpmPrefix`、GitHub 加速 URL 构造器、zip 解压、健康检查（>1MB + `--version`）、运行锁原语（争锁/heartbeat/释放/陈锁接管）、状态文件原子写入助手。

### 7.2 每 CLI 一套（渠道差异在 probe-local/upgrade）
| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver 目录 → version+exePath+healthy | 扫 `staging\opencode\<ver>\` → version+exePath+healthy |
| `probe-remote-<cli>.ps1` | `mise ls-remote <tool> --json` 最高 stable | GitHub `releases/latest` + 失败回退列表（§5.2） |
| `upgrade-<cli>.ps1` | 读 local+remote，behind+stable → `mise upgrade <tool>@latest`（带 MISE_* env，超时 600s） | 读 remote.sourceUrl → 下载 zip（加速前缀）→ 解压到 `staging\opencode\<ver>\` |
| `verify-<cli>.ps1` | 重扫 mise installs → version+exePath+healthy+matchesTarget | 跑 staging exe `--version` → 同字段 |
| `sync-v0.2.ps1`（共享单脚本） | 遍历三 CLI `verified.json`，仅对 `matchesTarget && healthy` 的，从 `verified.exePath` copy 到 `D:\AI\Programs\CLI\<name>\<name>.exe`，字节复核；覆盖前备份 `.previous` |

**脚本命名带版本**：共享库与 sync 文件名含 `-v0.2`；probe/upgrade/verify 每 CLI 一份，内部首行 `$ScriptVersion='0.2'` + `# SPEC: v0.2`。各 CLI 各一套脚本（不参数化单脚本），因渠道差异大、彻底模块化。

### 7.3 决策固化进脚本（agent 不判版本）
对照 Release-Monitor「agent 禁止自行比较版本」铁律：**版本大小判定、behind/uptodate/prerelease 判定、是否 ACTIONABLE，全部由脚本内部 `Compare-SemVer` 算出并以 stdout 标记输出**。agent 只读标记，不读 json 算 `local.version < remote.latest`。

---

## 8. 机器状态标记协议（整轮终态唯一依据）

每个脚本 stdout 输出 ASCII 标记（管道分隔），agent 只读标记判段间分支，不解析 json、不心算。标记表：

| 标记 | 产出脚本 | 判定 |
|---|---|---|
| `LOCKED\|` | 任何段 | blocked，本轮终止，不进下段 |
| `STATE_MISSING\|` | archive/probe-local | blocked（状态文件缺） |
| `PARSE_ERROR\|` | 任何段 | failed，终止，不写回原文件 |
| `RUNTIME_ERROR\|<cause>` | 任何段 | failed，终止 |
| `LOCAL_OK\|<cli> ver=<v> healthy=<bool>` | probe-local | 阶段成功 |
| `LOCAL_EMPTY\|<cli>` | probe-local | staging 空（opencode 首次）→ 需 upgrade |
| `REMOTE_OK\|<cli> latest=<v> fallback=<bool>` | probe-remote | 阶段成功 |
| `REMOTE_FAIL\|<cli> <cause>` | probe-remote | failed 该 cli，标记继续下一个 |
| `UPTODATE\|<cli> <v>` | upgrade（或 probe 内判） | 无需升级，跳过 verify |
| `ACTIONABLE\|<cli> <from>-><to>` | upgrade | 有升级动作 |
| `REPAIR\|<cli> stub/broken` | upgrade | healthy=false 触发修复重装 |
| `UPGRADE_OK\|<cli> <v>` | upgrade | 阶段成功，进 verify |
| `UPGRADE_FAIL\|<cli> <cause>` | upgrade | failed 该 cli |
| `VERIFY_OK\|<cli> <v> matches=true healthy=true` | verify | **晋升凭证**，sync-eligible |
| `VERIFY_FAIL\|<cli> <cause>` | verify | 不晋升，D 盘入口不动 |
| `SYNC_COPY\|<cli> <bytes>` | sync | 已复制并字节复核 |
| `SYNC_SKIP\|<cli> <reason>` | sync | 跳过（无凭证 / unhealthy） |
| `RUN_STATUS\|success\|<summary>` | sync（末步） | 整轮成功 |
| `RUN_STATUS\|failed\|<cause>` | 任何段 | 整轮失败 |
| `HOUSEKEEPING_WARNING\|<cause>` | archive | 辅助观察，不改变终态 |

退出码并行约定（脚本同时输出，便于脚本自测）：`0`=本步无事可做/已满足；`10`=dry-run 有动作；`11`=本步成功且产物已写；`2`=判定失败（环境/网络）；`3`=执行失败或复核不过。**agent 以 stdout 标记为准**（Cherry Bash 取 `$?` 不干净）。

---

## 9. agent 编排契约（定时任务 prompt 状态机）

prompt 里写死分段 + 标记判定分支表，agent 逐字执行。**全绝对路径正斜杠**，不 `cd /d`、不 `.\`（Git Bash 陷阱，见用户附错误日志：`cd /d` 报 too many arguments、`.\update` 报 not recognized）。

```
段A · 归档 + 探测（agent 不介入计算，只读标记）
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/archive-state.ps1
    → 争运行锁；LOCKED| → blocked 终止；RUNTIME_ERROR| → failed
  对每个 cli ∈ [claude, codex, opencode]:
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/probe-local-<cli>.ps1
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/probe-remote-<cli>.ps1
    读标记：LOCAL_EMPTY|<cli> 或 ACTIONABLE|（脚本内判 behind）→ 标记该 cli 待升级
            UPTODATE|<cli> → 该 cli 完成
            REMOTE_FAIL| / RUNTIME_ERROR| → 标记该 cli 失败，继续下一个

段B · 升级 + 验证（仅对待升级 cli）
  对每个待升级 cli:
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/upgrade-<cli>.ps1
      → UPGRADE_OK| → 进 verify；UPGRADE_FAIL| → 标记失败，继续
    pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/verify-<cli>.ps1
      → VERIFY_OK| → 标记 sync-eligible；VERIFY_FAIL| → 不晋升（D 盘入口不动）

段C · 同步 + 汇报
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/sync-v0.2.ps1 -Execute
    → SYNC_COPY| / SYNC_SKIP| 逐项；RUN_STATUS|success| → 整轮成功
  基于 sync.json 生成汇报（数字取 sync.json，禁止自行统计）
  report_artifacts 声明本轮产物（若有 md 产物）
```

**agent 铁律**（沿用 Release-Monitor §3）：
1. 不现场写脚本、不临时造脚本补救，异常走标记表分支。
2. 不手算版本大小、不手判 behind/prerelease、不改 json 程序事实。
3. 不 `cd /d`、不 `.\`，全绝对路径正斜杠。
4. 不降级 PS 5.1、不去锁、不去原子写入。
5. 如实回报终态，不夸大不掩盖；数字取 json，禁止自行统计。
6. 每次（无论有无变更）必输出状态行汇报，让用户确认任务在跑（不是只在有变更时才报）。

---

## 10. 回退与清理

### 10.1 mise（claude/codex）
- `upgrade.auto_prune=false`（保留旧版本目录）。
- 回退：`mise use <tool>@<旧版>`（旧目录仍在）。
- prune：v0.2 先手动复核不自动 prune；保留最近 2 个 stable 作候选。

### 10.2 opencode（github-binary）
- staging 保留多版本目录；`prune-staging.ps1`（候选）清到最近 2 个。
- 回退：升级失败 → 不写 verified-success → sync 不动 D 盘权威 → 调用照常走旧版；需显式回退则重跑 upgrade 指定旧 tag。
- 479B stub 场景不复现（不走 npm）；GitHub zip 解压后 exe 异常 → verify 报 unhealthy → sync 跳过。

### 10.3 权威入口（D 盘）
- 仅 sync 写。覆盖前备份当前为 `D:\AI\Programs\CLI\<name>\<name>.exe.previous`（一步回退；v0.2 启用）。

### 10.4 流程产物
- `state/archive/<时间戳>/` 每轮归档；`staging/` 保留最近 2 版；`TEMP/` 交付前空。
- `run.lock` 残留且锁内 PID 已死亡 → move_to_trash 清锁；PID 仍存活 → 不强 kill，报告并等超时。
- `*.tmp` 中间文件异常中断时由 archive-state 首步清理。

### 10.5 opencode npm 全局（v0.2 决策）
- npm 全局 `opencode-ai` **暂保留**作 fallback，待本套方案落地并稳定运作（全局调用已指向 D 盘唯一正确版本）后卸载。卸载前不主动动它。

---

## 11. 可追溯

- 每轮首步 `archive-state.ps1` 把 `state/*.json`（不含 run.lock、archive/）归档到 `state/archive/<时间戳>/`。
- `state/fetch_run.log` 累积每轮 `[时间] items=N upgraded=X synced=Y failed=Z`。
- spec/脚本/json 全带 `specVersion`；跨版本迁移见 §13。

---

## 12. 与参照系的差异（自检）

| 维度 | Software_Update_Monitor v0.2.2 | Release-Monitor | 本项目 v0.2 |
|---|---|---|---|
| 范围 | monitor-only（不含 install/switch/rollback） | monitor-only + 报告写回 | **monitor + download + install + switch + rollback** |
| 状态源 | Manifest（定义）+ SQLite（运行） | md 表格 + result.json | state/*.json（无 DB，CLI 维度小，无需 SQLite） |
| 运行锁 | — | run.lock | run.lock（沿用） |
| 晋升闸 | — | — | **D 盘 verified-success 才 sync（本项目特有）** |
| 通道 | GitHub | GitHub | mise（claude/codex）+ GitHub binary（opencode） |

---

## 13. v0.2 迁移项（首次执行）

1. 新建 `D:\AI\Programs\CLI\{claude,codex,opencode}\` 目录。
2. 首次 sync：从当前 mise/npm 已验证 exe 拷到新布局（claude 2.1.273 / codex 0.154.0 / opencode 1.18.31，三 exe 已健康实测）。
3. 旧散路径 `D:\AI\Programs\{Claude-Code-CLI, Codex\CLI, opencode\CLI}\` → 确认无引用后清空（opencode\CLI 现存 479B stub，必清；含 .git 段走 R43 手动）。
4. opencode 安装源切换：npm → GitHub binary staging；首次 probe-local 扫 staging（空 → local.version=null → 触发首次 upgrade 从 GitHub 拉 1.18.31，反代加速）。
5. mise 配置加 `upgrade.auto_prune=false`。
6. 现有散脚本（cli-common.ps1 / update-claude.ps1 / update-codex.ps1 / update-opencode.ps1 / sync-clis.ps1 / probe-clis-with-mistake.ps1）→ 按 v0.2 模块清单拆分重命名（带 -v0.2 / $ScriptVersion），旧文件归档到 `archive/scripts-pre-v0.2/` 不直接删（保留回溯）。

---

## 14. 待确认 / 已知风险（不阻塞 v0.2 起草，待 audit 与 probe 阶段定）

1. **opencode GitHub release asset 命名与 tag 格式**：`opencode-windows-x64.zip` + `anomalyco/opencode` 为用户手动更新路径 + Release-Monitor 观测的起点假设；probe 阶段实测确认（已知 tag 拼接异常、latest 端点不稳定）。
2. **多段运行锁 ownership 跨 PID**：Cherry 每段 Bash 是新 shell、PID 变，锁释放不能靠 `$PID -eq lockPid`。实现按 §6 "起始 PID 记录 + heartbeat 新鲜"判定（Release-Monitor 补丁#1 教训）。audit 应重点审此处。
3. **反代加速前缀可靠性**：`https://gh.jasonzeng.dev/` 为用户提供的反代；若反代不可用，probe/upgrade 需能回退直连 GitHub（probe 阶段实测）。
4. **opencode releases/latest 不稳定**：§5.2 已给列表回退策略；probe 阶段实测确认回退路径取到的 tag 正确。
5. **opencode npm 全局卸载时机**：§10.5 定为方案落地稳定后；具体判据（如"连续 N 轮 sync 成功"）待定。
