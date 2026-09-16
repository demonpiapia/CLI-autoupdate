# CLI 自动升级 —— 项目规格 SPEC v0.2.3

> **版本**：SPEC-v0.2.3（2026-09-16）。
> **变更摘要（v0.2.2 → v0.2.3）**：架构不动。据 CodeBuddy 审计报告独立复核后修订——采纳全部 6 项独立发现 F1–F6（凭证生命周期/标记闭合/错误语义分层/汇报数字源/REPAIR 动作/锁空转处置）。逐条采纳理由见交付汇报。
> **角色定位**：本文件是 **Plan / 契约**（治理路线图的 Approved Plan 位）。契约层为硬约束；PowerShell 实现属 Executor 有界自治。

---

## 0. 项目定位、范围与交付物

本项目是 **monitor + download + CLI 全局维护** 整体过程：从"探测是否有新版本"到"实际升级、切换、对外暴露统一入口"的完整闭环。

**运行形态**：本项目是 Cherry Studio 定时任务驱动、agent 编排、PowerShell 7 模块化的**个人维护流程**，维护对象是三个固定 CLI（claude/codex/opencode）。**不是**通用 CLI 自动更新软件产品——无 config.json、无 `cli update` 命令、无跨平台（仅 Windows）、无许可证/贡献指南、不做 RSA 签名验证（更新源固定且由 mise/GitHub 自身保证完整性）。

参照系（批判借鉴设计哲学，不照搬形态）：
- `Software_Update_Monitor_Spec_v0.2.2`（monitor-only）——本项目是其 Executor 下游延伸。
- `cherry-auto-apps-Release-Monitor`（已上线）——借鉴段内一气呵成、数据固化、运行锁、stdout 标记协议、原子写入、agent 不介入计算的工程哲学。不照搬合并脚本形态（本项目含下载/切换/回退/晋升闸，复杂度更高，需 4 拆模块）。

**交付物三层**：
1. **SPEC**（本文件）——设计契约，给 audit / 维护者。
2. **执行 SOP**（`cli-autoupdate-sop.md`，待产出）——给定时任务执行 agent 逐字读的标准化流程；agent 只读 SOP，不读本 spec。SOP 须含成功与错误场景示例（见 §9）。
3. **脚本**（`*-v0.2.3.ps1`）——模块化实现。

---

## 1. 设计原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | 模块化 | 每 CLI 拆 probe-local / probe-remote / upgrade / verify 四独立脚本。共享 sync 单脚本。 |
| 2 | 数据固化 | 每步结果落 `state/*.json`；下一步读上一步文件取数据。状态走文件，不走 agent 记忆。 |
| 3 | 流程化 | 定时 agent = 执行固定状态机 + 读标记判段间分支 + 报告异常。不写脚本、不手算版本。 |
| 4 | 晋升闸 | sync 只消费"本轮新鲜凭证"（`<cli>-verified.json` 且 `matchesTarget && healthy && runAt ≥ 本轮 startAt`）。未过验证或陈旧凭证，D 盘权威入口原封不动。 |
| 5 | fail-closed（分层） | **fatal 类**（STATE_MISSING / PARSE_ERROR / 锁争失败 / 归档失败 / 状态文件 schema 校验失败 / 骨架级 RUNTIME_ERROR）→ 终止整轮不降级。**recoverable 类**（单 CLI 探测/升级/验证失败）→ 标记后继续下一个 CLI，不阻断整轮。 |
| 6 | 原子写入 | 状态文件与权威入口经「临时文件 → 回读校验 → Move-Item 原子替换」；Move-Item 在**同卷**内为原子（Windows 同卷 rename 原子），跨卷时先 Copy 到目标卷临时文件再同卷 Move。失败回滚不污染原文件。 |
| 7 | 运行锁 | 多段 pwsh 调用经运行锁互斥。ownership 靠 runId 匹配（不靠 PID），PID 仅作陈锁死亡判据。 |
| 8 | 可追溯 | 每轮归档 `state/archive/<时间戳>/`；fetch_run.log 累积；spec/脚本/json 带 specVersion。任何修改迭代版本号。 |
| 9 | 隔离 | staging（E 盘 mise / 工作区 staging）与 promotion（D 盘 `D:\AI\Programs\CLI\`）物理分离。 |
| 10 | 机器事实/叙事分层 | `state/*.json` 机器事实，agent 只读不写；agent 可写的是汇报叙事层。 |
| 11 | 凭证新鲜度 | sync 只信本轮产出的凭证（`runAt ≥ 本轮 startAt`），防陈旧凭证覆盖手动回退；幂等场景（目标已是凭证版本）跳过 copy 不污染 `.previous`。 |

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging** | claude/codex：`E:\...\CherryStudio\Toolchain\mise\installs\<tool>\<ver>\`；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证的新版本落点 | upgrade 脚本（运行锁内） |
| **Promotion** | `D:\AI\Programs\CLI\<name>\<name>.exe` | 全局唯一"正确版本"，所有 harness 从此调用；last-known-good 回退源 | **仅 sync，且仅本轮新鲜凭证的 CLI，运行锁内** |

两层架构本身就是"先在 staging 部署验证，通过后才原子交换到 promotion"——审计建议的"先部署临时目录、验证通过后原子交换"策略，本项目已由 staging/promotion 分层 + 晋升闸 + verify 脚本原生实现。

所有 harness 固定调用 `D:\AI\Programs\CLI\<name>\<name>.exe`，不依赖 mise shim / `MISE_*` / PATH（已实测三 exe 为独立二进制）。

---

## 3. 统一入口布局

```
D:\AI\Programs\CLI\claude\claude.exe
D:\AI\Programs\CLI\codex\codex.exe
D:\AI\Programs\CLI\opencode\opencode.exe
```

未来新增 CLI 同理。旧散路径（`Claude-Code-CLI\` / `Codex\CLI\` / `opencode\CLI\`）首次 sync v0.2.3 时迁移（§13）。

> 实机现状（2026-09-16 核验）：D 盘此前曾缺 `claude\` 子目录（仅 codex/opencode），系手动建立时遗漏，现已补全。这正是 F1 凭证生命周期缺口的现实佐证——UPTODATE 不产凭证则永不 seed，需由 §7.3 的"UPTODATE 按需刷新凭证"机制兜底。

---

## 4. 目录与状态文件布局

```
D:\AI\Workspace\automatic\CLI-autoupdate\
├── SPEC-v0.2.3.md                    # 本文件（契约）
├── cli-autoupdate-sop.md             # 执行 SOP（给定时 agent，待产出）
├── cli-common-v0.2.3.ps1             # 共享库
├── probe-local-<cli>.ps1             # 每 CLI 一份（3 份）
├── probe-remote-<cli>.ps1            # 每 CLI 一份（3 份）
├── upgrade-<cli>.ps1                 # 每 CLI 一份（3 份）；内含 behind 判定
├── verify-<cli>.ps1                  # 每 CLI 一份（3 份）；即装后功能测试
├── sync-v0.2.3.ps1                   # 共享单脚本
├── archive-state.ps1                 # 每轮首步：争锁+归档+生成 runId
├── state\                            # 固定路径，最新覆盖
│   ├── current-run.json              # 本轮 runId + 起始时间（startAt）
│   ├── <cli>-local.json
│   ├── <cli>-remote.json
│   ├── <cli>-upgrade.json
│   ├── <cli>-verified.json
│   ├── sync.json
│   ├── run.lock                      # 运行锁（runId 模型）
│   ├── fetch_run.log                 # 累积日志
│   ├── <cli>.pin                     # 可选：手动锁定版本（防 sync 自动覆盖回退）
│   └── archive\<时间戳>\             # 每轮归档
├── staging\opencode\<ver>\           # opencode 解压落点
└── TEMP\                             # 交付前必空
```

状态目录决策：**固定 `state/` 最新覆盖 + 每轮 archive**（Cherry 每段 Bash 是新 shell，固定路径让段间脚本本能直接定位，无需 agent 跨段传目录名）。

**陈旧数据风险（回应 F2-c）**：固定覆盖策略下，`<cli>-remote.json` / `<cli>-upgrade.json` 跨轮残留有误判风险。落盘语义明确规定：`<cli>-remote.json` 在 REMOTE_FAIL 时写 `{latest:null, error:<cause>}`（不保留上一轮陈旧 latest）；`<cli>-upgrade.json` 仅实际升级时写，UPTODATE/NO_REMOTE/LOCAL_AHEAD 等不升级分支**不写不覆盖**（旧文件随 archive 归档后由本轮覆盖语义自然失效，upgrade 脚本读取前先校验 `runAt` 是否本轮）。

---

## 5. 数据契约（state/*.json）

所有 JSON 顶层带 `specVersion`（`"0.2.3"`）、`runAt`（ISO UTC）。时间内部 UTC，展示 UTC+08:00。

**更新源固定清单**：本项目更新源是固定且硬编码的，不是用户可配置的任意源，故无需白名单/trustedHosts 配置：
- claude/codex：mise registry（`mise ls-remote` + `mise upgrade`，mise 自身校验包完整性）。
- opencode：`anomalyco/opencode` GitHub releases（固定 repo；下载经反代 `https://gh.jasonzeng.dev/`，**反代失效回退直连**——时序见 §5.2/§7.2）。
- 超时已内置：Invoke-Proc 对 mise ls-remote 60s、upgrade 600s、exe --version 30s（§7.1）。
- 日志已有：`state/fetch_run.log`（§4/§11）。
- "是否启用自动更新"开关 = 定时任务本身（不配 cron 即不跑），无需配置项。

### 5.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.2.3", "name":"codex", "channel":"mise",
  "version":"0.154.0", "exePath":"...", "bytes":298169136, "mtime":"...",
  "healthy":true, "healthDetail":"ok", "error":null, "runAt":"..." }
```
- `healthy`：exe > 1MB 且 `--version` 可启动。
- `healthDetail`（**回应 F5-b，病因分型**）：`ok` / `broken`（结构损坏：<1MB / stub / 文件缺失） / `probe-error`（`--version` 偶发超时或非零退出，文件结构正常）。`broken` → 触发 REPAIR；`probe-error` → 不强制重装，输出 `PROBE_ERROR|` 报告（避免瞬态失败触发全量重装）。
- opencode staging 空 → `version=null, exePath=null, healthy=false, healthDetail=broken`（触发首次 upgrade）。

### 5.2 `<name>-remote.json`（probe-remote 产出）
```json
{ "specVersion":"0.2.3", "name":"opencode", "channel":"github-binary",
  "latest":"1.18.31", "sourceUrl":"https://gh.jasonzeng.dev/https://...",
  "assetName":"opencode-windows-x64.zip", "fallbackUsed":false, "error":null, "runAt":"..." }
```
- **mise 通道**：`mise ls-remote <tool> --json` 最高 stable。
- **github-binary 通道**：`releases/latest` → tag_name（去 `v`）+ assets 筛 `windows-x64.zip`；`sourceUrl` 存加速后地址。
  - **回退**：`releases/latest` 失败 → `releases?per_page=10` 取最高 stable、prerelease=false；`fallbackUsed=true`。
  - **REMOTE_FAIL 落盘语义（回应 F2-c）**：远端失败时仍写 remote.json，但 `latest:null, sourceUrl:null, error:<cause>`——**不保留上一轮陈旧 latest**，防 upgrade 读到陈旧值误判。
  - **下载校验**：upgrade 下载 zip 后校验大小 > 1MB（防半下载/stub），失败 → `DOWNLOAD_FAIL|`。若 release 附 checksum asset（如 `*.sha256` / `checksums.txt`）则校验 SHA256（probe 阶段实测确认是否存在）。mise 通道完整性由 mise 自身保证。
  - **直连回退时序（回应 F2-d）**：upgrade 下载时，加速 URL 失败（网络/非 200/校验不过）→ **直连 GitHub 原始 URL 重试一次** → 仍失败 → `DOWNLOAD_FAIL|<cli> <cause>`。不无限重试。
  - **已知坑（probe 实测确认）**：`anomalyco/opencode` 的 tag 在列表接口曾现异常拼接；asset 名 `opencode-windows-x64.zip` 为起点假设，probe 核实。

### 5.3 `<name>-upgrade.json`（upgrade 产出，仅实际升级时写）
```json
{ "specVersion":"0.2.3", "name":"codex", "fromVersion":"0.152.0", "target":"0.154.0",
  "exitCode":0, "ok":true, "error":null, "runAt":"..." }
```
**不升级分支（UPTODATE / NO_REMOTE / LOCAL_AHEAD / TARGET_PRERELEASE / VERSION_FORMAT_ERROR / PROBE_ERROR）不写不覆盖**本文件（回应 F2-c 陈旧数据）。

### 5.4 `<name>-verified.json`（verify 产出；晋升凭证）
```json
{ "specVersion":"0.2.3", "name":"codex", "version":"0.154.0",
  "exePath":"...", "bytes":298169136, "healthy":true, "matchesTarget":true,
  "runAt":"<本轮 startAt 之后>" }
```
- **晋升条件**：`matchesTarget==true && healthy==true && runAt ≥ current-run.json.startAt`（本轮新鲜）。缺/陈旧/不满足 → sync 跳过该 CLI。
- verify 脚本即"装后功能测试"：跑 `exe --version` 验证可启动 + 版本号匹配 target，落 verified.json。

### 5.5 `sync.json`（sync 产出）
```json
{ "specVersion":"0.2.3", "runAt":"...",
  "summary":{ "probed":3, "upgraded":1, "synced":1, "failed":1 },
  "entries":[
    {"name":"codex","source":"...","target":"D:\\AI\\Programs\\CLI\\codex\\codex.exe",
     "targetVersion":"0.154.0","action":"copy","bytes":298169136,"ok":true},
    {"name":"opencode","action":"skip","reason":"no fresh verified-success / pinned / already-current"}
  ] }
```
- **summary（回应 F4）**：sync 脚本汇总本轮 state 计算 `probed/upgraded/synced/failed`，落 sync.json.summary。agent 汇报数字**取 sync.json.summary**，不自行统计、不读零散 json 推断。
- `action`：`copy`（晋升）/ `skip`（无凭证/不新鲜/锁定/已是当前版本）/ `target-locked`。

### 5.6 `current-run.json`（archive-state 首步生成）
```json
{ "specVersion":"0.2.3", "runId":"<uuid>", "startAt":"<UTCISO>", "archivedTo":"archive\\<ts>" }
```

### 5.7 `<cli>.pin`（可选，手动锁定版本，回应 F1-d）
```json
{ "specVersion":"0.2.3", "name":"codex", "pinVersion":"0.152.0", "reason":"user manual rollback", "setAt":"..." }
```
存在且 `pinVersion != verified.version` → sync `SYNC_SKIP|<cli> pinned=<v>`，不自动覆盖用户手动回退的版本。用户解除锁定 → 删除该文件。

### 5.8 校验与原子写入（fail-closed）
每状态文件落盘走「写 `*.tmp` → `ConvertFrom-Json` 回读校验关键字段 → `Move-Item` 原子替换」。Move-Item 同卷原子；跨卷场景先 Copy 到目标卷临时文件再同卷 Move。校验失败 → 不替换、输出 `RUNTIME_ERROR_FATAL|schema`、释放锁、终止整轮（fatal）。

---

## 6. 运行锁模型（runId ownership）

跨 Bash 段 PID 必变（Cherry 每段新 shell），故 ownership **不靠 PID 匹配**，靠 runId：

- **争锁**（archive-state 首步）：`[IO.File]::Open(run.lock, FileMode::CreateNew, FileAccess::ReadWrite, FileShare::None)` 原子争锁；成功后写 `runId=<uuid>;start=<iso>;beat=<iso>;pid=<PID>`，runId 写入 `current-run.json`。
- **续锁**（后续每段脚本进入）：open 锁文件独占 → 读 runId → 与 `current-run.json` 比对 → 匹配则刷新 beat；不匹配或被独占或锁文件消失 → `LOCKED|` 退出。
- **陈锁接管**：beat 超 30 分钟 **且** 锁内 PID 经 `Get-Process -Id` 确认死亡 → 删锁重争；任何不确定 → 保守 `LOCKED|`。
- **释放**：sync 末步或异常分支，确认 runId 匹配后删锁。
- runId 经 `current-run.json` 传递，agent 不碰（脚本自读）→ agent 零状态。

> **锁空转处置（回应 F6）**：`LOCKED|` 统一涵盖三种情形——锁被本轮外进程独占、beat 未超时的崩溃残留、锁文件消失（前段异常释放）。三者一律 fail-closed → blocked，agent 汇报"本轮被锁阻塞"即可，**不人工抢锁**。崩溃后 beat 未超时期间，后续定时轮次会空转 `LOCKED|` 属预期行为（等 30min 后陈锁接管或下次手动清理）。此语义写入 SOP（§9）。

---

## 7. 模块清单

### 7.1 共享库 `cli-common-v0.2.3.ps1`
`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`，异步排空 stdout/stderr 再 WaitForExit+Kill，防管道死锁；超时：mise ls-remote 60s、upgrade 600s、exe --version 30s）、semver（`Compare-SemVer`：去 `v` 前缀，比较 Major.Minor.Patch，prerelease 低于 stable，不支持 build 元数据参与比较；解析失败返回 `$null` 标记 incomparable）、`Get-CherryMiseEnv`/`Get-MiseExePath`/`Get-MiseInstallsDir`/`Get-NpmPrefix`、GitHub 加速 URL 构造器、zip 解压、健康检查（>1MB + `--version`，分型 `broken`/`probe-error`）、运行锁原语（争锁/续锁 runId/释放/陈锁接管）、状态文件原子写入助手、runId 生成与读取、凭证新鲜度判定（`verified.runAt ≥ current-run.startAt`）、pin 读取。

### 7.2 每 CLI 一套（4 拆模块，数据靠 json 衔接）

| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver 目录 → version+exePath+healthy+healthDetail | 扫 `staging\opencode\<ver>\` → 同字段 |
| `probe-remote-<cli>.ps1` | `mise ls-remote --json` 最高 stable；失败写 `latest:null,error` | `releases/latest` + 失败回退列表（§5.2）；失败写 `latest:null,error` |
| `upgrade-<cli>.ps1` | 读 local+remote → **内部 Compare-SemVer 判 behind** → 见 §7.3 分支；mise 通道 ACTIONABLE=`mise upgrade <tool>@latest`，REPAIR=`mise install <tool>@<ver> --force` | 读 remote.sourceUrl → 下载 zip（加速失败直连重试一次）→ 大小/checksum 校验 → 解压 staging |
| `verify-<cli>.ps1` | 重扫 mise installs → version+exePath+healthy+matchesTarget+runAt | 跑 staging exe `--version` → 同字段 |
| `sync-v0.2.3.ps1`（共享） | 遍历三 CLI `verified.json`，仅本轮新鲜 `matchesTarget && healthy` 且未被 pin 锁定且目标版本≠凭证版本才 copy；字节复核；覆盖前备份 `.previous`；汇总 `summary` | 同左 |

### 7.3 behind 判定与版本规则（upgrade 内部）
**behind 判定在 `upgrade-<cli>.ps1` 内部完成**：读 `local.json` + `remote.json` → 分支：

| 条件 | 标记 | 动作 |
|---|---|---|
| local == remote 且 healthy==true 且有本轮凭证 | `UPTODATE_SKIP\|<cli> <v>` | 不执行、不写 upgrade.json、**跳过 verify**（真幂等） |
| local == remote 但**凭证缺失或 verified.version ≠ local.version**（**回应 F1-a**） | `UPTODATE_REFRESH\|<cli> <v>` | 不执行升级，**仍运行 verify**（只读刷新凭证，无副作用）→ 进 verify |
| local.healthy==false 且 healthDetail==`broken` | `REPAIR\|<cli> <reason>` | 强制重装（mise：`mise install <tool>@<ver> --force`；opencode：重新下载解压） |
| local.healthy==false 且 healthDetail==`probe-error`（**回应 F5-b**） | `PROBE_ERROR\|<cli> <reason>` | 不强制重装，报告，跳过 verify |
| local < remote 且 target stable | `ACTIONABLE\|<cli> <from>-><to>` | 执行升级 → 进 verify |
| target prerelease（**回应 F2-a**） | `TARGET_PRERELEASE\|<cli> <v>` | 不执行（stable-only），报告，跳过 verify |
| local > remote（双方可解析，本地超前）（**回应 F2-b**） | `LOCAL_AHEAD\|<cli> <local> > <remote>` | 不执行，报告，跳过 verify |
| 版本格式不可解析（**回应 C2**） | `VERSION_FORMAT_ERROR\|<cli> <raw>` | 不执行，报告，跳过 verify（fail-closed，不用默认版本号） |
| remote.latest==null（远端失败，**回应 F2-c**） | `NO_REMOTE\|<cli> <cause>` | 读不到 target，无法判 behind，不执行，报告，跳过 verify |

**版本格式验证**：`Compare-SemVer` 解析失败（非 `\d+\.\d+\.\d+` 核心段）→ incomparable → `VERSION_FORMAT_ERROR|`，不执行、报告。不"用默认版本号"（掩盖问题违反 fail-closed）。

**策略说明**：本项目 stable-only 跟随 latest，不做强制更新（无 force 标记）、不做自动降级（降级用户手动 `mise use`，§10.1）。`local > remote` 不静默跳过而是显式报告（agent 汇报异常）。

agent **无差别**对每 CLI 调 probe-local→probe-remote→upgrade→verify，upgrade 自判跳过；agent 不维护"待升级清单"。`UPTODATE_REFRESH` 是无差别调用的自然结果——即使 CLI 已最新，凭证缺失也会被刷新，保证 sync 永远有本轮凭证可用（回应 F1 场景 1/2）。

### 7.4 版本号
共享库与 sync 文件名含 `-v0.2.3`；probe/upgrade/verify 每 CLI 一份，内部首行 `$ScriptVersion='0.2.3'` + `# SPEC: v0.2.3`。

---

## 8. 机器状态标记协议（整轮终态唯一依据）

每脚本 stdout 输出 ASCII 标记（`|` 分隔），agent 只读标记判段间分支，不解析 json、不心算。退出码：`0`=无事可做/已满足；`10`=dry-run 有动作；`11`=成功且产物已写；`2`=判定失败；`3`=执行失败或复核不过。**agent 以 stdout 标记为准。**

标记分两类：**fatal**（出现即终止整轮，fail-closed）/ **recoverable**（标记该 CLI 失败后继续下一个）。

| 标记 | 产出脚本 | 类别 | 判定 |
|---|---|---|---|
| `LOCKED\|` | 任何段 | fatal | blocked，本轮终止，汇报（含空转/独占/消失统一，§6） |
| `STATE_MISSING\|` | archive/probe-local | fatal | blocked，本轮终止 |
| `PARSE_ERROR\|` | 任何段 | fatal | failed，不写回原文件，本轮终止 |
| `RUNTIME_ERROR_FATAL\|<cause>` | archive/sync（骨架级） | fatal | 整轮终止（含状态文件 schema 校验失败） |
| `RUNTIME_ERROR\|<cli> <cause>` | probe/upgrade/verify（CLI 级） | recoverable | 该 cli 失败，继续下一个 |
| `LOCAL_OK\|<cli> ver=<v> healthy=<bool> detail=<d>` | probe-local | recoverable(成功) | 阶段成功 |
| `LOCAL_EMPTY\|<cli>` | probe-local | recoverable(成功) | staging 空 → 进 upgrade |
| `REMOTE_OK\|<cli> latest=<v> fallback=<bool>` | probe-remote | recoverable(成功) | 阶段成功 |
| `REMOTE_FAIL\|<cli> <cause>` | probe-remote | recoverable | 该 cli 远端失败，仍进 upgrade（读 latest:null 自判 NO_REMOTE） |
| `ALL_REMOTE_FAIL\|` | probe-remote 末 | recoverable(整轮级) | 三 CLI 全失败 → 跳 upgrade/verify，直进 sync |
| `UPTODATE_SKIP\|<cli> <v>` | upgrade | recoverable(成功) | 有本轮凭证，跳 verify |
| `UPTODATE_REFRESH\|<cli> <v>` | upgrade | recoverable(成功) | 凭证缺失/过期，仍进 verify 刷新 |
| `ACTIONABLE\|<cli> <from>-><to>` | upgrade | recoverable(成功) | 有升级动作 |
| `REPAIR\|<cli> <reason>` | upgrade | recoverable(成功) | broken 触发重装 |
| `PROBE_ERROR\|<cli> <reason>` | upgrade | recoverable | probe-error 不重装，跳 verify |
| `TARGET_PRERELEASE\|<cli> <v>` | upgrade | recoverable | stable-only 拒绝，跳 verify |
| `LOCAL_AHEAD\|<cli> <local> > <remote>` | upgrade | recoverable | 本地超前，不执行，跳 verify |
| `NO_REMOTE\|<cli> <cause>` | upgrade | recoverable | 远端失败读不到 target，跳 verify |
| `VERSION_FORMAT_ERROR\|<cli> <raw>` | upgrade | recoverable | 格式不可解析，跳 verify |
| `EXE_LOCKED\|<cli>` | upgrade | recoverable | 源 exe 在跑，跳过该 cli |
| `DISK_FULL\|<cli> <free>MB` | upgrade | recoverable | 盘空间不足，跳过该 cli |
| `DOWNLOAD_FAIL\|<cli> <cause>` | upgrade(opencode) | recoverable | zip 下载/直连重试/校验失败，跳过该 cli |
| `UPGRADE_OK\|<cli> <v>` | upgrade | recoverable(成功) | 进 verify |
| `UPGRADE_FAIL\|<cli> <cause>` | upgrade | recoverable | 该 cli 失败，继续下一个 |
| `VERIFY_OK\|<cli> <v> matches=true healthy=true` | verify | recoverable(成功) | **晋升凭证**，sync-eligible（仍需新鲜度/pin 判定） |
| `VERIFY_FAIL\|<cli> <cause>` | verify | recoverable | 不晋升，D 盘入口不动 |
| `SYNC_COPY\|<cli> <bytes>` | sync | recoverable(成功) | 已复制并字节复核 |
| `SYNC_SKIP\|<cli> <reason>` | sync | recoverable(成功) | 跳过（无凭证/不新鲜/pinned/already-current） |
| `SYNC_TARGET_LOCKED\|<cli>` | sync | recoverable | 目标 exe 在跑 → 跳过该 cli |
| `RUN_STATUS\|success\|<summary>` | sync（末步） | 终态 | 整轮成功 |
| `RUN_STATUS\|failed\|<cause>` | 任何段 | 终态 | 整轮失败（仅 fatal 触发） |
| `HOUSEKEEPING_WARNING\|<cause>` | archive | 观察 | 辅助观察，不改变终态 |

> **错误处置语义（回应 F3）**：fatal 类（LOCKED/STATE_MISSING/PARSE_ERROR/RUNTIME_ERROR_FATAL）= fail-closed 终止整轮；recoverable 类（单 CLI 探测/升级/验证失败的各标记）= 标记后继续下一个 CLI，不阻断整轮。`RUNTIME_ERROR` 按出处区分：骨架段（archive/sync）→ `RUNTIME_ERROR_FATAL` 终止；CLI 段（probe/upgrade/verify）→ `RUNTIME_ERROR|<cli>` 继续。agent 遇未列出的 failed 类标记 → 按 fatal 处理（终止并汇报），保守优先。

**异常覆盖说明**：
- 单 CLI 失败（REMOTE_FAIL/UPGRADE_FAIL/VERIFY_FAIL/EXE_LOCKED/DISK_FULL/DOWNLOAD_FAIL/VERSION_FORMAT_ERROR/TARGET_PRERELEASE/LOCAL_AHEAD/NO_REMOTE/PROBE_ERROR）→ 标记、跳过该 CLI、继续下一个。
- 整轮网络全断（ALL_REMOTE_FAIL）→ 不升级、sync 全 skip、RUN_STATUS|success（如实汇报网断）。
- sync 目标锁定 → SYNC_TARGET_LOCKED → 跳过该 CLI 不阻其他。
- 骨架级错误（锁/状态/schema）→ fatal 终止整轮。

### dry-run 定位
定时任务 prompt **一律 `-Execute`**。脚本支持无 `-Execute` 的 dry-run 供人工预演。agent 不主动用 dry-run，除非用户明确要求。

---

## 9. agent 编排契约（定时任务 SOP 状态机）

SOP 文档（`cli-autoupdate-sop.md`）里写死分段 + 标记判定表，agent 逐字执行。**全绝对路径正斜杠**，不 `cd /d`、不 `.\`。

```
段A · 归档 + 探测（agent 无差别调，不判版本）
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/archive-state.ps1
    → 争锁+生成 runId+归档；LOCKED|/STATE_MISSING|/RUNTIME_ERROR_FATAL| → fatal 终止
  对每 cli ∈ [claude, codex, opencode]（顺序固定）:
    probe-local-<cli>.ps1 → LOCAL_OK|/LOCAL_EMPTY| 进段B；RUNTIME_ERROR|<cli> 标记失败继续下一个
    probe-remote-<cli>.ps1 → REMOTE_OK|/REMOTE_FAIL| 进段B；ALL_REMOTE_FAIL| 跳 upgrade/verify 直进段C
                                RUNTIME_ERROR|<cli> 标记失败继续下一个
    PARSE_ERROR| → fatal 终止整轮

段B · 升级 + 验证（agent 无差别调，upgrade 内部自判跳过）
  对每 cli（无差别）:
    upgrade-<cli>.ps1 -Execute
      → UPTODATE_SKIP|  → 跳过 verify，进下一 cli（有本轮凭证，幂等）
         UPTODATE_REFRESH| → 进 verify（刷新凭证）
         ACTIONABLE|/REPAIR| → UPGRADE_OK| 进 verify / UPGRADE_FAIL| 标记失败进下一 cli
         PROBE_ERROR|/TARGET_PRERELEASE|/LOCAL_AHEAD|/NO_REMOTE|/VERSION_FORMAT_ERROR|
           → 标记跳过 verify，进下一 cli
         EXE_LOCKED|/DISK_FULL|/DOWNLOAD_FAIL| → 标记跳过，进下一 cli
         RUNTIME_ERROR|<cli> → 标记失败进下一 cli；RUNTIME_ERROR_FATAL| → fatal 终止
    verify-<cli>.ps1
      → VERIFY_OK| → sync-eligible；VERIFY_FAIL| → 不晋升进下一 cli
         RUNTIME_ERROR|<cli> → 标记失败进下一 cli

段C · 同步 + 汇报
  sync-v0.2.3.ps1 -Execute
    → 遍历三 CLI：本轮新鲜凭证(matchesTarget&&healthy&&runAt≥startAt) 且无 pin 锁定
         且目标版本≠凭证版本 → SYNC_COPY|（覆盖前备份 .previous）
       否则 → SYNC_SKIP|（no fresh verified / pinned / already-current）
       目标 exe 锁定 → SYNC_TARGET_LOCKED|
    → 汇总 sync.json.summary；RUN_STATUS|success| → 整轮成功
  基于 sync.json.summary 生成汇报（数字取 summary，禁止自行统计）
  report_artifacts 声明 state/sync.json 作本轮审计产物
```

**agent 铁律**：
1. 不现场写脚本、不临时造脚本补救，异常走标记表分支。
2. 不手算版本、不读 json 判 behind、不改 json 程序事实。
3. 不 `cd /d`、不 `.\`，全绝对路径正斜杠。
4. 不降级 PS 5.1、不去锁、不去原子写入。
5. 如实回报终态，不夸大不掩盖；数字取 sync.json.summary。
6. 每次（无论有无变更）必输出状态行汇报。
7. 遇 `LOCKED|`（含空转/独占/消失）→ 汇报 blocked，**不人工抢锁**（§6）。

### 固定汇报模板（段C 必输出，数字取 sync.json.summary）
1. 状态行：本轮 3 CLI 探测，升级 X / 同步 Y / 失败 Z；终态 success/failed；网络全断时如实标。
2. 逐 CLI：`<cli>: <installed>→<target>`（UPTODATE_SKIP 标 `已是最新`；UPTODATE_REFRESH 标 `已是最新（凭证刷新）`；未升级标原因如 prerelease/local-ahead/no-remote/probe-error）。
3. 同步：`<cli> copied <bytes>` / `<cli> skipped <reason>`（pinned/already-current/no fresh）。
4. 异常项：失败的 CLI 逐项列原因。
5. 一句收尾备注（opencode fallback / 网络全断 / 被锁阻塞 / 其他）。

无变化时第 2–4 填"无"，**状态行必输出**。

### SOP 错误场景示例（回应 m2 + F3）
SOP 文档须含错误场景示例章节，覆盖：
- **网络全断**：ALL_REMOTE_FAIL → sync 全 skip → 汇报网断（RUN_STATUS|success）。
- **目标 exe 锁定**：SYNC_TARGET_LOCKED → 跳过不阻其他。
- **opencode 下载失败**：加速失败→直连重试→DOWNLOAD_FAIL。
- **verify 失败不晋升**：VERIFY_FAIL → D 盘入口不动。
- **凭证缺失刷新**：UPTODATE_REFRESH → verify 产出凭证 → sync copy（回应 F1）。
- **手动回退 pin**：用户 .previous 回退 + 建 pin → 下轮 SYNC_SKIP|pinned。
- **被锁阻塞**：LOCKED → 汇报 blocked，不抢锁（回应 F6）。

每例给"输入状态 → 标记序列 → agent 应走分支 → 汇报文本"。

### 推送策略
推送与否由定时任务 `channel_ids` 配置决定：配了 → 每次执行后必推送（有变更详列、无变化简述）；未配 → 不推送。凭证不写入 prompt/状态文件/推送平台。

### report_artifacts 交付物
声明 `state/sync.json`（绝对路径）作本轮审计产物。

---

## 10. 回退与清理

### 10.1 mise（claude/codex）
- `upgrade.auto_prune=false`（保留旧版本目录）。
- 回退：`mise use <tool>@<旧版>`（手动降级途径）。
- prune：v0.2.3 先手动复核不自动 prune；保留最近 2 个 stable。

### 10.2 opencode（github-binary）
- staging 保留多版本目录；清到最近 2 个。
- 回退：升级失败 → 不写新鲜凭证 → sync 不动 D 盘；显式回退重跑 upgrade 指定旧 tag，或建 pin 锁定旧版。
- 479B stub 不复现（不走 npm）；zip 解压异常 → verify unhealthy → sync 跳过。

### 10.3 权威入口（D 盘）+ 手动回退语义（回应 F1-d）
仅 sync 写。覆盖前备份 `D:\AI\Programs\CLI\<name>\<name>.exe.previous`（一步回退）。目标 exe 锁定 → SYNC_TARGET_LOCKED 跳过。

**手动回退语义（写明）**：用户用 `.previous` 手动回退 D 盘入口后，**若不建 pin**，下一轮 sync 会用本轮新鲜凭证自动覆盖回退版本（凭证指向 latest）。这是"自动跟随 latest"策略的预期行为，非 bug。若需保持回退版本，**必须建 `state/<cli>.pin`**（§5.7）锁定版本，sync 遇 pin 跳过。

### 10.4 流程产物
- `state/archive/<时间戳>/` 每轮归档；`staging/` 保留最近 2 版；`TEMP/` 交付前空。
- `run.lock` 残留且锁内 PID 已死亡 → move_to_trash 清锁；PID 仍存活 → 不强 kill，报告等超时。
- `*.tmp` 中间文件异常中断由 archive-state 首步清理。

### 10.5 opencode npm 全局
npm 全局 `opencode-ai` **暂保留**作 fallback，待本套方案落地稳定运作（连续 N 轮 sync 成功）后卸载。

---

## 11. 可追溯

- 每轮首步 archive-state 归档 `state/*.json`（不含 run.lock、archive/、current-run.json、pin）到 `state/archive/<时间戳>/`，生成 runId。
- `state/fetch_run.log` 累积每轮 `[时间] runId=<id> probed=N upgraded=X synced=Y failed=Z`。
- spec/脚本/json 全带 specVersion；版本历史见 §16。

---

## 12. 与参照系差异（自检）

| 维度 | Software_Update_Monitor v0.2.2 | Release-Monitor | 本项目 v0.2.3 |
|---|---|---|---|
| 范围 | monitor-only | monitor-only | **monitor+download+install+switch+rollback** |
| 模块粒度 | — | 合并 monitor.ps1 | **4 拆模块**（含下载/切换/回退） |
| 状态源 | Manifest+SQLite | md+result.json | state/*.json（CLI 维度小，无需 DB） |
| 锁 ownership | — | PID 匹配（跨段失配） | **runId 匹配** |
| 晋升闸 | — | — | D 盘本轮新鲜凭证才 sync + pin 保护（特有） |
| 通道 | GitHub | GitHub | mise + GitHub binary |
| 形态 | 通用工具 spec | 个人定时监测 | **个人定时维护流程**（非通用产品） |

---

## 13. v0.2.3 迁移项（首次执行）

1. 新建 `D:\AI\Programs\CLI\{claude,codex,opencode}\`（claude 此前缺，已手动补全；新机重装仍需此步）。
2. **首轮 seed 路径（回应 F1-c，明确执行主体）**：首次执行不依赖单独 seed 脚本——archive-state 后，对每 CLI 跑 probe-local→probe-remote→upgrade→verify。即使所有 CLI 当场 UPTODATE，`UPTODATE_REFRESH` 分支（凭证缺失）会触发 verify 产出 seed 凭证 → sync copy 到 D 盘。即**首轮 seed 由 UPTODATE_REFRESH 机制天然完成**，无需人工 copy 或 mission 模式。若 D 盘已有正确版本且本地健康，verify 产出凭证后 sync 按"目标版本≠凭证版本"判 `already-current` 跳过（幂等）。
3. 当前 mise/npm 已验证版本：claude 2.1.273 / codex 0.154.0 / opencode 1.18.31（三 exe 已健康）。
4. 旧散路径 `D:\AI\Programs\{Claude-Code-CLI, opencode\CLI}\` → 确认无引用后清空（opencode\CLI 现存 479B stub 必清；含 .git 段走手动删除）。
5. opencode 安装源切换：npm → GitHub binary staging；首次 probe-local 扫 staging（空 → LOCAL_EMPTY → 触发首次 upgrade 从 GitHub 拉 1.18.31）。
6. mise 配置加 `upgrade.auto_prune=false`。
7. 现有散脚本（`.old/` 下 cli-common.ps1 / update-*.ps1 / sync-clis.ps1 / probe-clis-with-mistake.ps1）→ 按 §7 模块清单拆分重命名（带 -v0.2.3 / $ScriptVersion），旧文件已归档 `.old/` 不删。
8. 产出 `cli-autoupdate-sop.md`（执行 SOP，给定时 agent）。

**配置/数据迁移**：本项目无 config.json（参数在脚本/prompt），无 SQLite/DB，无用户数据——迁移即脚本与入口目录的物理迁移。状态文件 schema 跨版本靠 `specVersion` 字段标识，旧 archive 可读不可混用。

---

## 14. 待确认 / 已知风险

1. **opencode GitHub release asset/tag 实测**：asset 名 `opencode-windows-x64.zip` + repo `anomalyco/opencode` 为起点假设；probe 核实 tag 格式、latest 端点稳定性、是否有 checksum asset。
2. **反代前缀可靠性**：`https://gh.jasonzeng.dev/` 不可用时回退直连 GitHub（时序 §5.2/§7.2 已定义：加速失败→直连重试一次→DOWNLOAD_FAIL）。
3. **runId 锁模型实现细节**：续锁时锁文件被独占 vs 消失统一 fail-closed→LOCKED（§6/F6 已闭合到 SOP）；陈锁接管 PID 死亡判定在 Cherry 沙箱下可靠性待实测。
4. **current-run.json 与 run.lock 一致性**：两处存 runId，一处损坏 → fail-closed 终止。
5. **opencode npm 全局卸载判据**：方案落地稳定后（连续 N 轮 sync 成功），N 待定。

---

## 15. 测试策略

本项目为个人维护流程，测试分三层：
- **单元**：`Compare-SemVer`（边界：prerelease、build 元数据、不可解析格式、local>remote）、`Invoke-Proc`（超时/Kill、.cmd 路由）、健康检查分型（stub<1MB→broken、--version 超时→probe-error）、凭证新鲜度判定、pin 读取。
- **集成**：每 CLI 的 probe-local→probe-remote→upgrade→verify 串（dry-run 验证标记序列、-Execute 验证产物落盘 + 原子写入 + fail-closed）；覆盖 UPTODATE_SKIP/UPTODATE_REFRESH/NO_REMOTE/LOCAL_AHEAD/TARGET_PRERELEASE 各分支。
- **端到端**：archive→三 CLI cycle→sync 全流程跑一轮，覆盖成功/uptodate-refresh/网络全断/exe 锁定/verify 失败/pin 锁定/被锁阻塞七场景；穿插 re-probe。
- **环境**：仅 Windows 11 + PowerShell 7.6.4 + Cherry 沙箱；不跨平台。

测试在脚本实现阶段做，非 spec 阶段。

---

## 16. 版本历史

| 版本 | 日期 | 摘要 | 文件 |
|---|---|---|---|
| v0.1 | 2026-09-16 | 初版：混合架构确立（mise+GitHub binary+晋升闸） | `SPEC-v0.1.md` |
| v0.2 | 2026-09-16 | 运行锁、标记协议、原子写入、fail-closed、opencode 回退 | `SPEC-v0.2.md` |
| v0.2.1 | 2026-09-16 | behind 判定下移 upgrade、runId 锁、无差别调用、SOP 层、汇报模板 | `SPEC-v0.2.1.md` |
| v0.2.2 | 2026-09-16 | Zoo 审计复核：补术语表/版本历史/测试策略/版本格式验证/SOP 错误场景；驳回误读意见并补"已覆盖"说明 | `SPEC-v0.2.2.md` |
| v0.2.3 | 2026-09-16 | CodeBuddy 审计复核：采纳 F1–F6（凭证生命周期 UPTODATE_REFRESH+新鲜度+pin、标记闭合补 TARGET_PRERELEASE/LOCAL_AHEAD/NO_REMOTE+remote 落盘语义+直连回退时序、错误语义 fatal/recoverable 分层+RUNTIME_ERROR 出处区分、汇报数字源 sync.json.summary、REPAIR 动作+healthy 分型、锁空转统一处置） | `SPEC-v0.2.3.md`（本文件） |

---

## 17. 术语表

| 术语 | 定义 |
|---|---|
| CLI | Command Line Interface，本项目指 claude/codex/opencode 三个命令行工具 |
| mise | 版本管理器，本项目用它管 claude/codex（Cherry 自定义 Toolchain 安装） |
| staging | 升级场层，新版本下载/验证的落点，不对外暴露 |
| promotion | 权威入口层，`D:\AI\Programs\CLI\<name>\<name>.exe`，全局唯一调用入口 |
| 晋升闸 | sync 只复制本轮新鲜凭证的 CLI 到 promotion，失败/陈旧/锁定不污染已知好版本 |
| 凭证 | `<cli>-verified.json`，verify 产出，`matchesTarget && healthy && runAt≥本轮startAt` 为有效晋升凭证 |
| 凭证新鲜度 | verified.runAt ≥ current-run.startAt，防陈旧凭证覆盖手动回退 |
| pin | `state/<cli>.pin`，手动锁定版本，sync 遇 pin 不自动覆盖 |
| SemVer | Semantic Versioning，`Major.Minor.Patch[-prerelease]`；本项目 Compare-SemVer 限制版（不支持 build 元数据参与比较） |
| 原子写入 | 临时文件 → 回读校验 → Move-Item 同卷替换，失败回滚不污染原文件 |
| runId | archive 首步生成的 uuid，作运行锁 ownership 凭证，跨 Bash 段传递 |
| fatal / recoverable | 错误分层：fatal 终止整轮（fail-closed）；recoverable 标记单 CLI 失败后继续 |
| 反代前缀 | `https://gh.jasonzeng.dev/`，拼在 GitHub release URL 前加速下载，失效直连回退 |
| dry-run | 无 `-Execute` 模式，输出会做什么不改盘，人工预演用 |
| fail-closed | 校验/判定失败 → 终止不降级不静默跳过 |
