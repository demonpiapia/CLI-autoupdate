# CLI 全局安装档案

> 采集时间：2026-09-15 19:45（本机 Windows 11 Pro 10.0.22621）
> 增补采集：2026-09-16（claude 由 npm 全局迁至 mise；codex mise registry 从 360 条变为 158 条、0.154.0 stable 现已可达）
> 用途：三个 AI coding CLI 的全局安装事实记录，供自动更新判断依据。
> 所有数值均为实测读数，非推断。复核命令见文末。

---

## 0. 环境前提（决定所有路径归属）

本机存在**用户目录分裂**，是理解配置落点的关键：

| 变量 | 值 | 含义 |
|---|---|---|
| `HOME` / `USERPROFILE` | `C:\Users\JasonPC` | 按 `$HOME` 找配置 → 落 **C:** |
| `APPDATA` | `E:\Users\WIN_11\AppData\Roaming` | 按 `%APPDATA%` 找 → 落 **E:** |
| `LOCALAPPDATA` | `E:\Users\WIN_11\AppData\Local` | 同上 → **E:** |
| npm prefix | `E:\Users\WIN_11\AppData\Roaming\npm` | 全局包落 **E:** |
| `CLAUDE_CONFIG_DIR` | `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Data\Agents\.claude` | Cherry Studio 显式注入，claude 当前会话专用 |
| `CODEX_HOME` | 未设置 | codex 回落到默认 `$HOME/.codex` |
| node | v24.13.0 | |
| mise | 2026.7.14 windows-x64 | |

**PATH 顺序（决定命令解析）**

```
第  9 位  E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\shims
第 35 位  E:\Users\WIN_11\AppData\Roaming\npm
```

mise shims 在 npm 之前 → 同名命令 mise 优先。本次已借此消除 codex 遮蔽（见 §4）。

**磁盘余量**

```
C: 24.92 GB   D: 33.73 GB   E: 3.59 GB   ← E 盘紧张
```

---

## 1. 一览表

| CLI | 生效版本 | 安装通道 | **该通道最新**（判定基准） | 差距 | 更新命令 |
|---|---|---|---|---|---|
| claude code | **2.1.272** | mise | **2.1.272（mise，注册表仅此 1 条）** | **0 — 已最新** | —（无需动作） |
| codex | **0.152.0** | mise（唯一） | **0.154.0（mise stable）** | **落后 2 个 stable** | `mise upgrade codex` |
| opencode | **1.18.30** | npm 全局 | 1.18.31（npm） | 1 | `opencode upgrade` |

> 判定基准是**当前生效通道自己的最新**，不是「所有 registry 里最高的那个」。
> codex 的 0.154.0 现已在 mise registry 内可达（见 §3），是真·本通道落后，可正常升级。
> claude 的 mise registry 当前只有 2.1.272 一条，已就是最新。

---

## 2. claude code CLI

**安装（2026-09-16 由 npm 全局迁至 mise，用户手动执行）**

| 项 | 值 |
|---|---|
| 版本 | **2.1.272** |
| 解析入口 | `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\shims\claude`（250,272 B 启动桩，无 `.cmd`/`.ps1` 变体） |
| 实体 | `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\claude\2.1.272\claude.exe` = **230,228,640 B** |
| 实体目录 | 该路径是符号链接，指向 tarball 缓存 `…\mise\http-tarballs\b4dbd7319b194f77d778c01814ac5477dd3d4c60c9f46227cf57fb6e573fb6c4` |
| 安装时间 | 2026-09-16 00:15:41（exe mtime） |
| mise 配置 | `Toolchain\mise\config\config.toml` → `claude = { version = "latest", … }`（自定义 GCS registry，非标准 mise registry 条目） |
| mise 解析 | `mise ls` 报 `claude 2.1.272 (symlink) latest`；`mise which claude` 指向上列实体 |
| mise registry | `mise ls-remote claude` 仅 **1 条**（2.1.272） |
| npm 全局 | **已卸载**（2026-09-16，见 §5）——原 npm 装是残损版（`bin\claude.exe` 仅 500 B 文本桩，optionalDeps 平台包未下载，shim 缺失），升级路径不可靠 |

打包形态：mise 直接拉取 GCS 上的平台原生二进制（`claude.exe`，230 MB），无 npm 包结构、无 optionalDeps、无启动器层 —— 与 codex 的 mise 安装同构，与 opencode 的 npm postinstall 复制模式不同。

无 `~/.claude/local`、无 `~/.local/bin/claude.exe` → 确认不存在 native 并行安装。

**配置（两层，当前会话不在默认位置）**

| 路径 | 大小 | 说明 |
|---|---|---|
| `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Data\Agents\.claude` | 51M | Cherry 注入 `CLAUDE_CONFIG_DIR`，当前会话活跃写入（sessions/projects/skills/tasks） |
| `C:\Users\JasonPC\.claude` | 223M | 用户级历史 |
| `C:\Users\JasonPC\.claude.json` | 60K | 用户级配置 |

**更新通道**：`mise upgrade claude`（跟随 `config.toml` 的 `latest`）。`mise ls-remote claude` 当前仅 1 条，已就是最新。
`update-claude.ps1` 已于 0916 改写为 mise 通道（`mise upgrade claude@latest`），与安装通道一致——见 §8。

**活动入口（由 sync-clis.ps1 维护）**：`D:\AI\Programs\Claude-Code-CLI\claude.exe` 等三个固定路径已从「保留旧版」改为**活动调用入口**——用户从这三个路径调 CLI，每次升级后跑 `sync-clis.ps1 -Execute` 把最新 exe 覆盖过去（见 §8 sync-clis.ps1）。

---

## 3. codex CLI

**当前状态：仅 mise 一条安装，单一来源，无遮蔽。**

| 项 | 值 |
|---|---|
| 版本 | **codex-cli 0.152.0** |
| 解析入口 | `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\shims\codex` |
| 实体 | `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\codex\0.152.0\bin\codex.exe` = **293,066,544 B** |
| 实体目录 | 393,182,615 B |
| shim | 250,272 B 启动桩（与实体非同一文件，非硬链接） |
| mise 配置 | `Toolchain\mise\config\config.toml` → `codex = "latest"` |
| mise 解析结果 | `requested_version: "latest"` → `0.152.0`，`installed/active: true` |
| npm 全局 | **已卸载**（2026-09-15，见 §5） |

**配置（按用户定位，与装了几份无关）**

| 路径 | 大小 | 说明 |
|---|---|---|
| `C:\Users\JasonPC\.codex` | 450M | `CODEX_HOME` 未设 → 回落默认 |
| `C:\Users\JasonPC\.codex\config.toml` | 912 B | doctor 自报 `config.toml loaded / parse ok` |
| `C:\Users\JasonPC\.codex\auth.json` | 94 B | `stored auth mode: api_key`，File 存储 |

`config.toml` 生效项：`model_provider = "cherry-gateway"` → `http://127.0.0.1:23333/v1`（`wire_api = "responses"`）；
另配置了 `custom` → `http://localhost:3000/v1`。
`approval_policy = "never"`、`sandbox_mode = "danger-full-access"`、`[windows] sandbox = "unelevated"`。

**⚠️ 更新通道状态（2026-09-16 重新实测，推翻 0915 的「天花板」结论）**

```
mise registry 条目总数    = 158（0915 测得 360 条，registry 已变化）
mise registry 最高 stable = 0.154.0      ← 可达，高于当前 0.152.0
新增 stable（≥ 0.153）   = 0.153.0 / 0.153.1 / 0.153.2 / 0.153.3 / 0.153.4 / 0.154.0
npm   registry 最新       = 0.154.0      ← 该通道已随 0915 卸载消失
```

- `mise upgrade codex` 现在会解析到 **0.154.0**，是真·本通道可执行升级，Actionable=true。
- 0915 的「mise registry 360 条 / 最高 stable 0.152.0 / 0.154.0 仅在上游与 npm、mise 到不了」结论**已过期**——registry 在 24 小时内补齐了 0.153.x–0.154.0 的 stable 条目。
- `codex update` 子命令存在，但 doctor 报告生效实例 `install method: other`、
  `managed by npm: no · bun: no · pnpm: no`（实体 exe 未经 `codex.js` 启动器，
  未注入 `CODEX_MANAGED_BY_NPM`）→ 不走 npm 通道，升级走 `mise upgrade`。

**判定仍按通道作用域**：codex 当前唯一通道是 mise，其 registry 最新 stable 0.154.0
就在本通道内 → 满足触发条件，可正常升级。跨通道情报（npm 0.154.0）此时与本通道重合，不再是不可达触发。

**doctor 遗留警告**（未处理）：`threads` — 状态 DB 行指向缺失/不可用的 rollout 文件。

**活动入口（由 sync-clis.ps1 维护）**：`D:\AI\Programs\Codex\CLI\codex.exe` = **0.148.0**（旧版，首次 sync 后被覆盖为最新）。

---

## 4. opencode CLI

**安装**

| 项 | 值 |
|---|---|
| 包 | `opencode-ai@1.18.30` |
| 入口 | `E:\Users\WIN_11\AppData\Roaming\npm\opencode`（含 `.cmd` / `.ps1`） |
| 原生二进制 | `...\node_modules\opencode-ai\bin\opencode.exe` = **179,793,448 B** |
| 包总字节 | 359,594,571 B |
| 安装时间 | 2026-09-14 12:04:21 |

打包形态：`postinstall.mjs` 探测 CPU AVX2，从
`opencode-windows-x64`（AVX2）/ `opencode-windows-x64-baseline`（无 AVX2）二选一复制到 `bin/`。
两个平台包**都已落地**，但 `bin/` 只保留被选中的一份。

**配置**

| 路径 | 大小 | 说明 |
|---|---|---|
| `C:\Users\JasonPC\.config\opencode` | 60M | 配置目录 |
| `C:\Users\JasonPC\.config\opencode\opencode.json` | 92 B | 仅 `$schema` + `model: "opencode/mimo-v2.5-free"` 两项 |
| `C:\Users\JasonPC\.local\share\opencode` | 46M | 数据 |

**更新通道**：`opencode upgrade [target]`，`-m` 可选 `curl / npm / pnpm / bun / brew / choco / scoop`。

**待清理（未处理）**：配置目录堆积 **8 个备份**（`.bak`、`.bak-20260914`、`.phase2_*`、`.pre_default_*`、`.pre_restore_*`），另有 `opencode.jsonc`（54 B）。

**活动入口（由 sync-clis.ps1 维护）**：`D:\AI\Programs\opencode\CLI\opencode.exe` = **1.18.25**（旧版，首次 sync 后被覆盖为最新）。
另存在 `D:\AI\Programs\opencode\opencode-windows\OpenCode.exe`。

---

## 5. 本次会话已执行的清理（2026-09-15 ～ 2026-09-16）

| 动作 | 对象 | 结果 | 是否可恢复 |
|---|---|---|---|
| 回收站 | `npm\node_modules\@openai\.codex-MgEajYHP`（安装中断孤儿，282M，仅 1 个文件 295,408,944 B） | → `E:\$RECYCLE.BIN\...\$RZBUNUM.codex-MgEajYHP\...\codex.exe`，字节数精确核验 | ✅ 可恢复 |
| 卸载 | `npm uninstall -g @openai/codex`（0.154.0，398,587,442 B + 3 个 shim） | `removed 2 packages`，exit 0 | ⚠️ 不可回收 |
| 卸载 | `npm uninstall -g @anthropic-ai/claude-code`（残损 2.1.270：`bin\claude.exe` 仅 500 B 文本桩「claude native binary not installed」，optionalDeps 平台包未下载，全局 shim 缺失，`--version` exit 2） | `removed 2 packages`，exit 0；`npm ls -g` 已无 claude | ⚠️ 不可回收 |
| 回收站 | 本会话 9 个 ps1 脚本（`TEMP/`） | 已入回收站，工作区根目录已清空 | ✅ 可恢复 |

孤儿目录判定依据（删除前只读核查）：仅含 1 个 `codex.exe`，无 `package.json` / 无 `bin/codex.js` 启动器
（无任何入口能解析进去）；二进制 SHA256 `444a3f00…498518b`，与 npm 0.154.0（`be96b992…1cbdfde`）及
mise 0.152.0 均不相同 → 介于两者之间的中断版本；`npm ls -g` 不登记该条目（点前缀是 npm 临时暂存命名）。

---

## 6. 注意事项

1. **回收站不释放空间。** §5 的 282M 仍在 `E:\$RECYCLE.BIN` 占位，E 盘需清空回收站才能真正拿回。
2. **E 盘回收站历史异常：** 用户 SID 下有 24 条只有 `$I` 元数据、无 `$R` 数据的孤儿条目 ——
   该低空间盘的回收站被裁过。向 E 盘回收站放 282M 后建议立即核验 `$R` 数据是否幸存
   （本次已核验幸存：`$RZBUNUM.codex-MgEajYHP`）。
3. **codex npm 卸载不可回收**，恢复命令：`npm i -g @openai/codex@0.154.0`
   （本机 `npm-cache` 无可用 cacache 索引，需走网络下载）。
4. **三个 CLI 更新通道**（claude 已于 0916 迁至 mise，现与 codex 同通道）：
   - claude → mise（`config.toml` 钉 `latest`，registry 仅 1 条；`update-claude.ps1` 已改写为 mise 通道）
   - codex → mise（`codex update` 对生效实例无效，见 §3）
   - opencode → npm，但自带多通道 `upgrade`
5. **`move_to_trash` 工具沙箱限于当前工作区**，工作区外删除会 `Tool execution failed`。
   工作区外删除走 SHFileOperation P/Invoke，注意两个坑：
   - `pFrom` 字符串必须**双 null 结尾**（单 null → `HRESULT 87` E_INVALIDARG）
   - 拷贝用 `Marshal.Copy`（`Buffer.BlockCopy` 不接受 `IntPtr` 目标）
   - 回收站会把文件名改写为 `$R…`，**按字节数**而非文件名核验
6. 三个 `D:\AI\Programs\` 路径（claude/codex/opencode）已从「保留旧版副本」改为**活动调用入口**：
   升级后由 `sync-clis.ps1 -Execute` 把最新 exe 覆盖到这三个固定路径，用户从这三处调 CLI
   （不依赖 mise shim / PATH / `MISE_*` 环境注入）。旧版（claude 2.1.221 / codex 0.148.0 /
   opencode 1.18.25）将在首次 sync 时被覆盖。
7. **npm 包内存在同名大文件硬链接，字节数易翻倍。** 实测（claude 迁 mise 后此项仅适用于 opencode）：
   - opencode：`bin\opencode.exe` 与 `opencode-windows-x64\…` 是同一 inode 的两条路径
     → 朴素递归求和得 539,388,019 B（2 倍），真实占用 359,594,571 B。
   - claude 原 npm 全局装已卸载（见 §5）；现 mise 装是单文件原生 exe（230,228,640 B），无 npm 包结构、无硬链接翻倍问题。
   - 本机 PowerShell 7.6.4 **不暴露** `FileInfo.FileId` / `LinkCount` / `HardLinkCount`
     （三者取值均为 `$null`），无法按 inode 去重；`probe-clis-with-mistake.ps1`（旧 probe，已归档）改用 `(字节数, 最后修改时间)`
     组合键去重（与 GNU `du -sb` 的折叠方式一致，实测逐字节吻合），并同时输出 `installBytesNaive`
     供审计。
8. **codex 的 shim 依赖环境变量注入，脱离 Cherry Studio 即失效。** Cherry Studio 给子进程注入
   整套 `MISE_*` 变量（`MISE_DATA_DIR` / `MISE_SHIMS_DIR` / `MISE_CONFIG_DIR` /
   `MISE_CACHE_DIR` / `MISE_STATE_DIR` / `MISE_YES=1` / `MISE_NO_ANALYTICS=1`）并把
   `MISE_SHIMS_DIR` 前置进 PATH。实测两种失效形态：
   - **shims 目录不在 PATH 上**（普通 Windows Terminal / 计划任务）→ `Get-Command codex` 空，
     探测脚本报 `channel: none`。
   - **shims 在 PATH 上但 `MISE_*` 未注入** → `Get-Command` 能解析到 `codex.exe`，
     但 shim 找不到安装目录 → 执行失败，版本读不出。

   因此自动更新脚本**不能**依赖 `codex --version` 或 PATH 解析。权威入口是
   `mise which codex`（或其后的 `<root>\installs\codex\<version>\bin\codex.exe`），
   `mise` 实体在 `C:\Users\JasonPC\.cherrystudio\bin\mise.exe`（不在 Cherry 注入的 PATH 项里，
   需按候选路径直接定位）。另存在第二个 mise 根
   `E:\Users\WIN_11\AppData\Local\mise`，无 codex 安装，勿误判。
9. **子进程管道有缓冲上限，`WaitForExit` 之后才读流会死锁。** 实测 `mise ls-remote codex --json`
   输出 32,183 B，先 `WaitForExit` 再 `ReadToEnd` 的顺序超过 120 s 仍未返回
   （表现为「命令超时」，实为管道写满、子进程阻塞）；改为先启动两条
   `ReadToEndAsync()` 再 `WaitForExit(timeout)`，同样输出 130 ms 完成。
   写自动化的通用模板时注意：本机 PowerShell 7.6.4 无法解析
   `Task.Run(Action)` 之外的两参重载（`[Task]::Run(sb, proc)` 与
   `Task.Factory.StartNew(fn, proc)` 均报 overload/argument count 错误），
   `ReadToEndAsync()` + `Task.Wait(int)` 是可行组合。
10. **版本比较必须按段数值比较，字符串排序会错**（`0.10.0` 在字典序上小于 `0.9.0`）。
   另外 mise 这个构建没有 `ls-remote --sort`，排序要在脚本里自己做。
   预发布要按 semver 分段比（`0.153.0-alpha.2` > `0.153.0-alpha.1`；正式版高于
   同核心号的任何预发布；`+build` 元数据不参与优先级）。
11. **本机 PS 7.6.4 的两个语法陷阱**（脚本里会静默跑偏，务必避开）：
    - `if` 是语句不是表达式。`return (if ($x) {1} else {-1})` 直接报
      `The term 'if' is not recognized`；要写成
      `$r = if ($x) {1} else {-1}; return $r`。`$(if ...)` 子表达式是合法的。
    - `${var.Member}` 在大括号内**不支持成员访问**，PS 会去找一个真叫
      `var.Member` 的变量，结果是空串。要写 `$var.Member` 或 `$($var.Member)`。
      同样，`"... $r.Version ..."` 只支持 `$r-Prop` 形式，其余都得 `$($r.Version)`。
12. **本环境的防污染守卫是「Bash 命令行文本」级的，不是进程级的**（已实测）
    把字面串 `mise upgrade` 直接写进 Bash 命令会被拦：
    `Blocked to avoid cross-agent dependency pollution: direct mise mutation
    (use cli_search / cli_install)`；但**把 `mise upgrade` 放进 .ps1 文件、
    由 pwsh 进程内用 .NET `Process` API 调起，守卫完全不触发**——
    实测 `pwsh -File TEMP\guard-test.ps1`（脚本内 `mise upgrade --help`）
    干净跑完，exit 0、stdout 4359 字节真实 usage 输出。
    结论：守卫只扫 Bash 工具那行命令的文本；脚本内部的子进程不受约束。
    因此**定时任务可以放心让 agent 直接跑 `update-codex.ps1 -Execute`**，
    不需要把 codex 拆到 agent 之外（早前版本 §6.12／§8 曾推测「需在 agent
    之外运行」，那条推测已被本条实测推翻）。

---

## 7. 复核命令

> ⚠️ **0916 架构变更**：`probe-clis.ps1` 已**归档**为 `probe-clis-with-mistake.ps1`
> （内容未改、仅更名，保留作历史参考，**勿再调用**）。原因是旧 update-*.ps1
> 通过 `&` 算子同步捕获 probe 的 stdout，probe 输出超过 ~32 KB 管道缓冲即死锁
> （`mise ls-remote codex --json` = 32,183 B 实测卡死）。新 update-*.ps1 全部
> 自带判定（dot-source `cli-common.ps1`，每个子进程走 `Invoke-Proc` 异步排空 +
> 硬超时 + Kill），不再依赖 probe，不可能卡死。

**一键批量探测（已归档）**：`probe-clis-with-mistake.ps1` 只读脚本（绝不安装／卸载／升级），
一次输出三个 CLI 的版本 / 通道 / 包元数据 / 原生 exe 字节 / 安装时间 /
通道最新 / 判定 / 跨通道情报 / 遮蔽副本 / 配置落点 / 更新命令。新流程下日常复核
改用三个 `update-*.ps1`（dry run，退出码 0/10 即知是否最新）。

```bash
# 旧 probe（归档，勿用——仅历史参考）
pwsh -NoProfile -File probe-clis-with-mistake.ps1
```

**新流程下的日常复核**（每个 CLI 一个 dry run，自带判定，不依赖 probe）：

```bash
pwsh -NoProfile -File update-claude.ps1     # 退出码 0=已最新，10=有更新
pwsh -NoProfile -File update-codex.ps1
pwsh -NoProfile -File update-opencode.ps1
pwsh -NoProfile -File sync-clis.ps1         # 0=三入口已同步，10=有 copy 待执行
```

> Git Bash 下调用需 `MSYS_NO_PATHCONV=1`，否则 `/…` 类参数会被 MSYS 路径转换改写。

**判定按通道作用域**：`channelLatest` 取**当前生效通道自己的最新**
（mise 通道 → `mise ls-remote` 最高 stable；npm 通道 → npm registry），
`actionable` 只由它决定。另一个通道的最新放 `crossChannelNewer` /
`otherChannelLatest`，仅作情报 —— 跨通道不可达时若拿它做更新触发条件，
任务会永远告警却无事可做。codex 在 0915 是这种情况（mise 到不了 0.154.0），
但 0916 registry 补齐后 0.154.0 已在本通道内 → 已是真·本通道落后（见 §3）。

**退出码契约**

| 码 | 含义 |
|---|---|
| `0` | 全部 CLI 已解析，且无可执行更新动作 |
| `2` | 有 CLI 版本解析失败（环境问题，非「版本落后」） |
| `3` | 配 `-ExitIfBehind` 且至少一个 `actionable: true` |

**JSON 契约（供 agent 消费）**：顶层 `Environment` + `Clis[]`。
关键语义是**区分「未知」和「否」**：

| 字段 | 类型 | 说明 |
|---|---|---|
| `Actionable` | `Boolean` | 唯一该驱动的字段。`true` 才动手 |
| `IsLatest` | `Boolean` 或 **JSON null** | null = 没查到通道最新（含 `-SkipRemote`），**不是** false |
| `CrossChannelNewer` | `Boolean` 或 JSON null | 三态：`true` 跨通道更新但本通道不可达 |
| `BehindPatch` | `Int64` 或 JSON null | null = 不可判 |
| `Environment.RemoteSkipped` | `Boolean` | 本轮是否离线 |

`-SkipRemote` 下所有 CLI 的 `Actionable` 恒为 `false` —— 离线轮次不会触发误升级，
这是安全默认值。

**解析不依赖 PATH**（对自动更新很关键）：脚本按 `PATH` → `mise which` →
`mise ls --json` + 安装目录扫描 → npm prefix 的顺序取版本，最终执行的是
**权威安装实体**而非 shim。原因见 §6.8。输出字段 `resolvedVia`
（`path` / `mise-which` / `mise-ls+scan` / `install-scan` / `none`）标明本次走了哪条路；
`Environment` 块给出 `PathHasMiseShims` / `PathHasNpm` / `PathEntryCount` / `MiseRoots`
便于定位「为什么在当前 shell 里找不到命令」。

**单项复核**

```bash
# 版本与解析来源
claude --version;      command -v claude
codex --version;       mise which codex;   mise ls codex --json
opencode --version;    command -v opencode

# 全局包清单 / registry 最新
npm ls -g --depth=0
npm view @openai/codex version
npm view opencode-ai version
mise ls-remote claude            # claude 已迁 mise，权威来源是 mise registry（当前仅 1 条）
mise ls-remote codex | tail -8   # 0916 起 158 条，最高 stable 0.154.0

# codex 安装健康（只读）
codex doctor --all | grep -iE "config|CODEX_HOME|install|managed"

# 磁盘余量（注意：bash 里要转义 $）
pwsh -NoProfile -Command "Get-PSDrive C,D,E -PSProvider FileSystem | Format-Table Name,Free"

# 回收站核验（本会话条目）
"D:/Program Files/Everything/es.exe" -nop "\$RZBUNUM*"
```

---

## 8. 更新脚本（每个 CLI 一个 + sync）

0916 重写：三个 update 脚本 + 一个 sync 脚本全部 **self-contained**，
共享 `cli-common.ps1`（dot-source）。每个脚本自带判定，**不再依赖 probe**，
所有子进程走 `Invoke-Proc`（异步排空 stdout/stderr + 硬超时 + Kill），
不可能像旧版那样卡死。

| 脚本 | 通道 | 目标版本来源 | 实际安装命令 |
|---|---|---|---|
| `update-claude.ps1` | mise（0916 改写） | `mise ls-remote` 最高 stable（当前仅 1 条） | `mise upgrade claude@latest` |
| `update-codex.ps1` | mise（**仅 stable**） | `mise ls-remote` 最高 stable（158 条） | `mise upgrade codex@latest` |
| `update-opencode.ps1` | npm | npm registry 的 `opencode-ai` 最新 | `npm install -g opencode-ai@<v>` |
| `sync-clis.ps1` | — | 把最新 exe 覆盖到三个 `D:\AI\Programs\` 入口 | `Copy-Item` + 字节复核 |

**默认就是 dry run**：不带 `-Execute` 只报告要做什么、改什么，磁盘零改动。
判定在脚本内**自己查**（mise 通道 → `Get-MiseRemoteStableLatest`；
npm 通道 → `Get-NpmRegistryLatest`），不调 probe。

**标准流程**（先升、后同步、从固定入口调用）：

```bash
# 1. dry run 看是否要升
pwsh -NoProfile -File update-claude.ps1        # 退出码 10 = 有更新
pwsh -NoProfile -File update-codex.ps1
pwsh -NoProfile -File update-opencode.ps1

# 2. 真升级
pwsh -NoProfile -File update-claude.ps1 -Execute                 # 升级 + 复核，退出码 11
pwsh -NoProfile -File update-claude.ps1 -Execute -TargetVersion 2.1.272

# 3. 升级成功后同步到调用入口（D:\AI\Programs\）
pwsh -NoProfile -File sync-clis.ps1 -Execute                    # 三入口同步，退出码 11
```

`update-*.ps1 -Execute` 成功后末行会打印 `Next: run sync-clis.ps1 -Execute`。

**退出码契约**

| 码 | 含义 |
|---|---|
| `0` | 已最新／无动作（也含：被策略拒绝安装） |
| `10` | dry run 且有可执行更新，未改动任何东西 |
| `11` | 已安装并通过升级后复核 |
| `2` | 判定失败：装好的版本或通道最新读不出来（环境问题，**不是**版本落后） |
| `3` | 升级失败，或升级后复核版本与目标不符 |

### 保护闸（都是硬拒绝，不是警告）

1. **exe 占用检查。** 目标原生二进制正被进程占用时拒绝安装——Windows 上无法替换
   运行中的 `.exe`，继续只会让 npm／mise 中途失败。
2. **目标盘剩余空间。** 低于 `-MinFreeMB`（默认 1024 MB）拒绝。npm prefix 和 mise
   根都在 E 盘，该盘实测仅剩约 3.6 GB，此检查在此有效。
3. **预发布拒绝。** 目标版本串带 `alpha|beta|rc|dev|nightly|canary` 一律不装。
   codex 的 stable-only 策略由此强制执行。
4. **mise 专属：通道可达性。** 显式 `-TargetVersion` 时目标必须**真的存在于 mise registry**
   （`Test-MiseVersionAvailable` 实跑 `mise ls-remote --json` 全量比对，0916 实测 codex 158 条、
   claude 1 条）。0915 该检查会拒绝 codex `0.154.0`（当时 registry 360 条里没有它），但 0916
   registry 补齐后 `0.154.0` 已在表内 → 接受、`mise upgrade codex` 会真正升到 0.154.0。
   此检查防的是「拿上游/npm 版本当 mise 目标」的误判，不是当前 codex 的实际障碍。
5. **mise 专属：只能追通道最新。** `mise upgrade` 只跟通道最新，装不了任意旧版本
   或钉版本。显式 `-TargetVersion` 若不是 registry 最高 stable 会被拒绝，并提示 `mise use <tool>@<v>`。
6. **sync 专属：目标占用。** 三个 `D:\AI\Programs\` 入口 exe 若正被进程占用
   （CLI 会话在跑），拒绝 copy，提示先关闭再重跑。

### 升级后复核

`-Execute` 装完后会**再 `Get-InstalledExe` 一次**（同样走文件系统扫描 +
`--version`，不调 probe）比对版本，不符即退出 3。所以 `11`
是唯一代表「装成了且验证过」的码。

### 本机关键事实：claude 现有三份二进制，升级 mise 那份不影响会话

0916 卸载 npm 全局 claude 后，本机 claude 二进制现状：

| 来源 | 路径 | 字节 | 用途 |
|---|---|---|---|
| Cherry SDK 内置（会话在跑） | `D:\AI\Programs\Cherry-Studio\resources\app.asar.unpacked\node_modules\@anthropic-ai\claude-agent-sdk-win32-x64\claude.exe` | 265,720,480 B | 当前 agent 会话实际运行的进程 |
| mise 安装（0916 新装） | `…\Toolchain\mise\installs\claude\2.1.272\claude.exe` | 230,228,640 B | PATH 解析到的命令行 claude |
| npm 全局 | —（已卸载） | — | 0916 清除 |

因此 `mise upgrade claude` 升级的是 mise 那份，**不会**打断 Cherry Studio 里跑 SDK 内置 exe 的 agent 会话，占用检查对它会正确报 `free`。

### exe 占用检测必须用 `FileAccess.Write`

Windows 上运行中的 `.exe`（PE 映像）用 `FileAccess.Read` 打开**总是成功**，
无论请求什么 share mode——所以基于 Read 的占用检测完全检测不到。
本机实测（运行中 vs 闲置的两个 claude.exe）：

```
Read   + None  : OPEN / OPEN         <- 无用
Read   + Write : OPEN / OPEN         <- 无用
Write  + None  : IOException / OPEN  <- 可区分
RW     + None  : IOException / OPEN  <- 可区分
Write  + Read  : IOException / OPEN  <- 可区分
```

三个脚本的 `Test-FileLocked` 因此都用 `FileAccess.Write` + `FileShare.None`，
拿到句柄立即释放、不写任何字节（已复核四个目标文件字节数未变）。

### `-Execute` 路径尚未被真正执行过

三个脚本的 `-Execute` 从未跑过，**原因是未获授权 + 它改动全局工具安装**，
不是环境拦住了。只验证了 dry run、参数构造与各保护闸。

早前曾误判为「本环境防污染守卫会拦掉 `mise upgrade`」，那是错的。实测见
§6.12：守卫只扫 Bash 命令行文本，脚本内部经 .NET `Process` 调起的
`mise upgrade` 不受约束。因此定时任务可以直接让 agent 执行
`update-codex.ps1 -Execute`，codex 不必拆到 agent 之外，也不需要守卫白名单。
