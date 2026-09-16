# CLI 自动升级 —— 项目规格 SPEC v0.1

> 版本：SPEC-v0.1（2026-09-16）。文件与脚本均带版本号；后续修订递增。
> 决策基线：**混合架构**——复用 mise（claude/codex）+ 复用 GitHub release 产物（opencode），自写仅限 probe/verify/sync 编排与 D 盘晋升闸。

---

## 1. 设计原则

1. **模块化**：每个脚本只做一件事（probe-local / probe-remote / upgrade / verify / sync）。单脚本 ~30–80 行。
2. **数据固化**：每步结果落 `state/*.json`，下一步读上一步的文件取数据。**状态走文件，不走 agent 记忆，不走 agent 手填。**
3. **流程化**：定时任务 agent 的职责 = 执行固定状态机 + 报告异常。**agent 不写脚本、不现场造命令。**
4. **晋升闸（核心）**：sync 只消费"verified-success"产物（`<cli>-verified.json` 且 `matchesTarget && healthy`）。未通过验证的 CLI，其 D 盘权威入口**原封不动** → 升级失败不污染已知好版本（恢复用户保留备份的安全网）。
5. **可追溯**：每轮 run 开始把 `state/` 归档到 `state/archive/<时间戳>/`；spec/脚本带版本号。
6. **隔离**：staging（E 盘 mise / 工作区 staging 目录）与 promotion（D 盘 `D:\AI\Programs\CLI\`）物理分离；E 盘升级翻车碰不到 D 盘权威副本。

---

## 2. 两层架构

| 层 | 位置 | 职责 | 谁能写 |
|---|---|---|---|
| **Staging（升级场）** | claude/codex：`E:\...\mise\installs\<tool>\<ver>\`；opencode：`<workspace>\staging\opencode\<ver>\` | 下载/升级/验证的新版本落点 | upgrade 脚本 |
| **Promotion（权威入口）** | `D:\AI\Programs\CLI\<name>\<name>.exe` | 全局唯一认可的"正确版本"，所有 harness 从此调用；last-known-good 回退源 | **仅 sync 脚本，且仅对 verified-success 的 CLI** |

所有 harness（Cherry agent / 外部终端 / 其他 harness 的 agent）固定调用 `D:\AI\Programs\CLI\<name>\<name>.exe`，不依赖 mise shim / `MISE_*` / PATH（已实测三 exe 为独立二进制）。

---

## 3. 统一入口布局（v0.1 确定）

```
D:\AI\Programs\CLI\claude\claude.exe
D:\AI\Programs\CLI\codex\codex.exe
D:\AI\Programs\CLI\opencode\opencode.exe
```

未来新增 CLI 同理加入此目录。当前散路径（`Claude-Code-CLI\` / `Codex\CLI\` / `opencode\CLI\`）在首次 sync v0.1 时迁移到此布局（旧路径留空或清，见 §9）。

---

## 4. 数据契约（state/*.json）

状态目录：`D:\AI\Workspace\automatic\CLI-autoupdate\state\`（固定，最新覆盖；每轮归档见 §8）。
所有 JSON 顶层带 `specVersion`、`probedAt`/`<stage>At`（ISO 时间，由调用方传入或脚本末尾 stamp）。

### 4.1 `<name>-local.json`（probe-local 产出）
```json
{ "specVersion":"0.1", "name":"codex", "channel":"mise",
  "version":"0.154.0", "exePath":"E:\\...\\installs\\codex\\0.154.0\\bin\\codex.exe",
  "bytes":298169136, "mtime":"2026-09-16T...", "healthy":true,
  "error":null, "probedAt":"..." }
```
- `channel`: `mise` | `github-binary`（opencode）。`healthy`: exe > 1MB 且 `--version` 可启动（防 stub）。

### 4.2 `<name>-remote.json`（probe-remote 产出）
```json
{ "specVersion":"0.1", "name":"codex", "channel":"mise",
  "latest":"0.154.0", "count":158, "sourceUrl":null,
  "error":null, "probedAt":"..." }
```
- mise 通道：`mise ls-remote <tool> --json` 取最高 stable。
- github-binary 通道（opencode）：GitHub releases API `releases/latest` → `tag_name`（去 `v` 前缀）+ `assets[].browser_download_url`（筛选 `windows-x64.zip`）；`sourceUrl` 存**加速后**下载地址。

### 4.3 `<name>-upgrade.json`（upgrade 产出，仅升级时写）
```json
{ "specVersion":"0.1", "name":"codex", "fromVersion":"0.152.0", "target":"0.154.0",
  "exitCode":0, "ok":true, "error":null, "upgradedAt":"..." }
```

### 4.4 `<name>-verified.json`（verify 产出，仅验证时写）
```json
{ "specVersion":"0.1", "name":"codex", "version":"0.154.0",
  "exePath":"E:\\...\\installs\\codex\\0.154.0\\bin\\codex.exe",
  "bytes":298169136, "healthy":true, "matchesTarget":true, "verifiedAt":"..." }
```
- **晋升条件**：`matchesTarget==true && healthy==true`。缺此文件或条件不满足 → sync 跳过该 CLI。

### 4.5 `sync.json`（sync 产出）
```json
{ "specVersion":"0.1", "syncedAt":"...",
  "entries":[
    {"name":"codex","source":"<verified.exePath>","target":"D:\\AI\\Programs\\CLI\\codex\\codex.exe",
     "action":"copy","bytes":298169136,"ok":true},
    {"name":"opencode","action":"skip","reason":"no verified-success file"}
  ] }
```

---

## 5. 模块清单

共享库 `cli-common-v0.1.ps1`：`Invoke-Proc`（`.cmd/.bat` 经 `cmd.exe /c`）、semver、`Get-CherryMiseEnv`、`Get-MiseExePath`/`Get-MiseInstallsDir`、GitHub 加速 URL 构造器、zip 解压、健康检查（>1MB + `--version`）、状态文件读写助手。

每 CLI 一套（渠道差异在 probe-local/upgrade）：

| 脚本 | claude/codex (mise) | opencode (github-binary) |
|---|---|---|
| `probe-local-<cli>.ps1` | 扫 `mise\installs\<tool>\` 最高 semver 目录 → version+exePath+healthy | 扫 `staging\opencode\<ver>\` → version+exePath+healthy |
| `probe-remote-<cli>.ps1` | `mise ls-remote <tool> --json` 最高 stable | GitHub `releases/latest` API → tag + asset URL（加速后） |
| `upgrade-<cli>.ps1` | 读 local+remote json，behind+stable → `mise upgrade <tool>@latest` | 读 remote json 的 sourceUrl → 下载 zip（加速）→ 解压到 `staging\opencode\<ver>\` |
| `verify-<cli>.ps1` | 重扫 mise installs → version+exePath+healthy+matchesTarget | 跑 staging exe `--version` → 同样字段 |
| `sync-v0.1.ps1`（共享，单脚本） | 遍历三 CLI 的 `verified.json`，仅对 matchesTarget&&healthy 的，从 `verified.exePath` copy 到 `D:\AI\Programs\CLI\<name>\<name>.exe`，字节复核 |

**脚本命名带版本**：主脚本文件名含 `-v0.1`（如 `cli-common-v0.1.ps1`、`sync-v0.1.ps1`）；probe/upgrade/verify 每 CLI 一份，内部首行 `$ScriptVersion='0.1'` + `# SPEC: v0.1`。

---

## 6. 回退与清理

### mise（claude/codex）
- 设 `upgrade.auto_prune=false`（保留旧版本目录，回退基础）。
- 回退：`mise use <tool>@<旧版>`（旧目录仍在）。
- 中断/半解压版本目录：`mise prune` 清未用；保留最近 2 个 stable（脚本 `prune-mise.ps1` 候选，v0.1 先手动复核，不自动 prune）。

### opencode（github-binary）
- staging 保留多版本目录；`prune-staging.ps1` 清到最近 2 个。
- 回退：升级失败 → 不写 verified-success → sync 不动 D 盘权威 → 调用照常走旧版。需显式回退则重跑 upgrade 指定旧 tag。
- 479B stub 场景**不复现**（不走 npm）；若 GitHub zip 解压后 exe 异常，verify 报 unhealthy，sync 跳过。

### 权威入口（D 盘）
- 仅 sync 写。覆盖前可选备份当前为 `D:\AI\Programs\CLI\<name>\<name>.exe.previous`（一步回退；v0.1 启用）。

### 流程产物
- `state/archive/<时间戳>/` 每轮归档；`staging/` 保留最近 2 版；`TEMP/` 交付前空。

---

## 7. agent 编排契约（定时任务 prompt 固定状态机）

prompt 里写死分支，agent 逐字执行，不造脚本、不 `cd /d`、不 `.\`（Git Bash 陷阱），全绝对路径正斜杠：

```
对每个 cli ∈ [claude, codex, opencode]:
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/probe-local-<cli>.ps1
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/probe-remote-<cli>.ps1
  读 state/<cli>-local.json + state/<cli>-remote.json
  if local.error 或 remote.error → 异常：重试该 probe 一次；仍错→标记该 cli 失败，继续下一个
  if local.healthy==false → 走 upgrade（修复）→ verify
  elif local.version == remote.latest → 该 cli 完成（无需升级）
  elif local.version < remote.latest → upgrade → verify
  else（local > remote，异常）→ 报告，跳过
  读 state/<cli>-verified.json
  if matchesTarget && healthy → 标记 SYNC-eligible
  else → upgrade reloop 一次；仍不过→标记失败，继续
最后：
  pwsh -NoProfile -File D:/AI/Workspace/automatic/CLI-autoupdate/sync-v0.1.ps1 -Execute
汇报：每 cli installed→target、各步退出码、sync copy/skip、异常
```

退出码契约（各脚本统一）：`0`=本步无事可做/已满足；`10`=dry-run 有动作；`11`=本步成功且产物已写；`2`=本步判定失败（环境/网络）；`3`=本步执行失败或复核不过。

---

## 8. 可追溯

- 每轮 run 第一条命令：`archive-state.ps1` 把 `state/*` 移到 `state/archive/<时间戳>/`（无则建）。
- `state/` 全程是"本轮"状态；历史在 archive。
- 脚本与 spec 版本号进每个 json 的 `specVersion`。

---

## 9. v0.1 迁移项（首次执行）

1. 新建 `D:\AI\Programs\CLI\{claude,codex,opencode}\` 目录。
2. 首次 sync：从当前 mise/npm 已验证 exe 拷到新布局（claude 2.1.273 / codex 0.154.0 / opencode 1.18.31，三 exe 已健康）。
3. 旧散路径 `D:\AI\Programs\{Claude-Code-CLI, Codex\CLI, opencode\CLI}\` → 确认无引用后清空（opencode\CLI 现存 479B stub，必清）。
4. opencode 安装源切换：从 npm → GitHub binary staging；首次 probe-local 扫 staging（首次为空 → local.version=null → 触发首次 upgrade 从 GitHub 拉 1.18.31）。npm 全局 opencode-ai 可保留作 fallback 或卸载（用户定）。
5. mise 配置加 `upgrade.auto_prune=false`。

---

## 10. 待确认（不阻塞 v0.1 起草）

- 状态目录：固定 `state/` + archive（v0.1 采用）；若要每轮独立 `runs/<时间戳>/` 再议。
- 每 CLI 各一套脚本 vs 参数化单脚本：v0.1 采用**各一套**（渠道差异大，彻底模块化）。
- opencode npm 全局是否卸载（留作 fallback vs 清除）。
- GitHub release asset 命名（`opencode-windows-x64.zip`）与 repo（`anomalyco/opencode`）在 probe 阶段实测确认；反代前缀 `https://gh.jasonzeng.dev/` 已定。
