# SPEC-v0.2.13 评审意见（cherry 独立审计）

先说结论：v0.2.13 由另一 agent 据 CodeBuddy 对 v0.2.12 的审计（CB-P1~CB-P3，11 项全采纳）修订而成。本轮 §6 锁接管伪代码的异常分型（CB-P1-1）与 Ticks 层时间比较（CB-P1-2）方向**正确且 fail-safe**——即使异常分型不精确，误判方向也恒为假阴性（LOCKED），与 §14-3 声明一致。CB-P2-1~P2-4 的判据收窄/枚举对齐逻辑自洽，§5.9/§8.1/§10.5 多处同步。本轮未发现 P0（数据损坏级）问题。

以下是我独立复核后发现的、**CodeBuddy 本轮及此前 12 轮审计均未指出**的问题，按严重度排列。每条附原文引用 + 诊断 + 真实依据。

---

## P1（契约内部不一致/断档，建议本轮修订）

### 1. run.lock 存储格式未声明 + 未纳入 §5.9 schema 总表

§6 争锁段（行 342）：

> 写 `runId/start/beat/pid/processStartTimeUtc`

§6 伪代码（行 354、366、387）以 JSON 字段访问语法读取锁内容：

```powershell
$lock.processStartTimeUtc   # 行 354
Get-Process -Id $lock.pid   # 行 366
$proc.StartTime.ToUniversalTime().Ticks -eq $lockTimeUtc.Ticks   # 行 387
```

`$lock.<field>` 语法在 PowerShell 中要求 `$lock` 是 `[pscustomobject]`/`[hashtable]`/`PSCustomObject`——即 **run.lock 必须是结构化对象**（最自然是 JSON，反序列化为对象后才可字段访问）。

但 spec 全文未声明 run.lock 的存储格式：
- §4 目录树（行 108）仅标 `run.lock`，无格式说明；
- §5.9「字段级 schema 总表（与示例一一对应）」（行 263–320）涵盖 local/remote/upgrade/verified/sync/current-run/pin/opencode-npm-fallback，**唯独没有 run.lock 行**；
- §6 仅以散文+伪代码描述字段，未声明序列化格式。

**断档后果**：
1. CB-P1-2 刚钉死的 `processStartTimeUtc` 格式契约（UTC `'o'` round-trip、7 位小数正则）**没有 schema 级 MUST 断言位置**——§5.9 是 spec 中唯一的"字段级 schema"权威位置，run.lock 缺席意味着该格式契约仅存在于 §6 散文与伪代码注释中，验收 checklist 若按 §5.9 建断言会**漏掉 run.lock 全部字段**。
2. 实现者无法从 §5.9 确定 run.lock 是 JSON 还是其他格式——若实现者选择非 JSON（如键值对、二进制），伪代码的 `$lock.processStartTimeUtc` 访问语义不成立，需自行设计反序列化，与"spec 钉死契约、实现有界自治"的定位冲突。

**真实依据**：§5.9 表首行（行 265）"文件 | 字段 | 类型 | 必填 | 枚举/说明"——该表是"与示例一一对应"的权威 schema 源，run.lock 无对应行，属客观缺失。§6 伪代码（行 354/366/387）客观使用 `$lock.<field>` 对象访问语法。

**建议**：在 §5.9 补 run.lock 行（声明格式=JSON，字段 runId/start/beat/pid/processStartTimeUtc + 各自类型/必填/格式约束），使 CB-P1-2 的格式契约有 schema 级落点；或在 §6 显式声明"run.lock 为 JSON 格式，字段见 §5.9"。

### 2. archive-state 成功路径缺少 stdout 标记，agent 判定依据未定义

§8 标记表（行 504–506）中 archive-state 仅出现在 fatal 标记行：

| 标记 | 产出脚本 | 类别 |
|---|---|---|
| `LOCKED\|` | 任何段 | fatal |
| `STATE_MISSING\|` | archive/probe-local | fatal |
| `PARSE_ERROR\|` | 任何段 | fatal |

§8.1 对照表（行 550）archive-state 成功行：

| 脚本 | 关键标记 | exitCode | 文件副作用 |
|---|---|---|---|
| archive-state | **争锁成功+归档完成** | 11 | 写 current-run.json / run.lock / archive/ |

"关键标记"列写的是**描述性文字"争锁成功+归档完成"**，而非 `MARKER|...` 格式。对比其他所有脚本的成功路径均有正向 ASCII 标记：`LOCAL_OK|`/`REMOTE_OK|`/`UPGRADE_OK|`/`VERIFY_OK|`/`RUN_STATUS|success`——**唯独 archive-state 成功路径无 `*_OK|` 标记，不对称**。

§9 状态机（行 582–585）：

```
段A: archive + probe
  archive-state ──[LOCKED|/STATE_MISSING|/PARSE_ERROR|/RUNTIME_ERROR_FATAL]──→ fatal 终止
        │ OK
        ▼
  ∀cli: probe-local → probe-remote
```

状态机标注"archive OK → probe"，但 **agent 判定 archive 成功（OK）的依据未在 §8/§9 显式定义**。可选路径只有：
- **靠 exitCode=11** → 但 §8 P0-1（行 498）明确"整轮成功/失败判定各层一律以 `RUN_STATUS|...` stdout 标记为准，exitCode MUST NOT 参与成功判定"；
- **靠"无 fatal 标记输出"（沉默成功）** → 与"进程崩溃/被 kill 无输出"不可机械区分，且 §8（行 538）"遇未列出的 failed 类标记→按 fatal 处理（保守优先）"暗示"无标记"该走保守，与"成功进 probe"矛盾。

**真实依据**：§8 标记表（行 504–536）逐行核对，archive-state 无成功标记行；§8.1（行 550）"关键标记"列为描述文字非标记格式；§8 P0-1（行 498）"exitCode MUST NOT 参与成功判定"；§9 状态机（行 584）"OK" 无判据定义。四处客观印证。

**建议**：为 archive-state 补成功标记（如 `ARCHIVE_OK|<runId>`），使 §8.1"关键标记"列与 `*_OK|` 同族；§9 状态机"OK"边显式注明"agent 见 `ARCHIVE_OK|` 进 probe，见 fatal 标记终止"。

### 3. §6 写侧 `'o'` 格式 vs 读侧 7 位小数正则可能不自洽（需实测）

§6 争锁（行 342）：

> 写入时 MUST 序列化为 **UTC round-trip（`'o'`）格式**（如 `2026-09-16T02:11:03.1234567Z`，保留完整 tick 精度、`Z` 后缀）

§6 伪代码读侧格式校验（行 354）：

```powershell
$lock.processStartTimeUtc -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$'
```

正则强制 **必须有 `.` + 恰好 7 位小数**。但 .NET / PowerShell 的 `'o'`（round-trip）格式设计哲学是**省略尾随零**以可变长度 round-trip——当 `Process.StartTime` 的 sub-second 部分恰好为 0（整秒对齐）时，`ToString('o')` 输出**不含小数段**，如 `2026-09-16T02:11:03Z`（而非 `...03.0000000Z`）。

若属实，则：争锁用 `'o'` 写（MUST）→ 整秒 StartTime 的锁值无小数段 → 读侧正则 `\.\d{7}` **不匹配** → `$lockTimeUtc` 为 `$null` → 走行 375 分支 `LOCKED`（保守不抢）。

后果是 fail-safe 方向（误判 LOCKED，不误判 TAKEOVER，无数据损坏风险），但**陈锁接管在"原进程 StartTime 恰为整秒"的边界永远无法 TAKEOVER**，使 CB-P1-2"减假阴性卡锁"的设计目的在该边界失效。

**真实依据**：§6 行 342 写侧声明 `'o'` + 行 354 读侧正则 `\.\d{7}`——二者格式要求客观不对称（写侧 `'o'` 不保证 7 位，读侧强制 7 位）。.NET 'o' 格式省略尾随零是文档化行为，但具体到 `Process.StartTime`（底层 `GetProcessTimes` FILETIME，100ns 精度）整秒对齐概率极低（~1/10⁷），**是否实际触发需 PS 7.6.4 实测确认**。

**标注**：本条为 **PLAUSIBLE**（未实测，依 .NET 格式规范推断），非 CONFIRMED。若实测 `'o'` 整秒确有小数省略，则升 P1 confirmed。

**建议**：实现期实测 `[datetime]::Parse('2026-09-16T02:11:03').ToUniversalTime().ToString('o')` 输出。若确认省略，二选一：① 读侧正则放宽为可选小数（`(\.\d{1,7})?Z`）；② 写侧改用固定格式（如 `ToString('yyyy-MM-ddTHH:mm:ss.ffffffZ')`）保证 7 位，与读侧正则对齐。

---

## P2（观察项/建议，不阻断实现）

### 1. §7.3 条件7 `UPTODATE_SKIP` 依赖"同轮 re-probe"，但 §9 状态机未定义 re-probe 节点

§7.3（行 475）自述：

> **`UPTODATE_SKIP` 的可达范围**：仅**同轮内重复调用 upgrade**（如 §13 穿插 re-probe：本轮 verify 已产出新鲜凭证后再次进入 upgrade）可达

§9 状态机（行 581–609）段B 为 `∀cli: upgrade → verify` 单次顺序，**无 re-probe 循环节点**。§13 是迁移 checklist（首次执行），非运行时状态机定义。

即：条件7 在标准单轮状态机中实际不可达（§7.3 自认"跨轮首次调用恒不成立，死分支"），其为"同轮 re-probe"预留，但 §9 未定义 re-probe 何时触发。条件7 与 §9 状态机存在轻微不一致。

**建议**：§9 状态机注明 re-probe 触发条件（或标注"条件7 为 §13 穿插 re-probe 预留，标准单轮不可达"），闭合 §7.3 与 §9 的状态机覆盖声明。

### 2. §8.1 `RUN_STATUS|failed` 行"计数更新"与 CB-P2-1"完全冻结"措辞易混

§8.1（行 569）`RUN_STATUS|failed` 行文件副作用列：

> opencode-npm-fallback.json 计数按已跑的 opencode 条目结果更新（fatal 前已处理则更新，否则不动——§10.5 D5 唯一规则不变）

§10.5（行 671）CB-P2-1：

> `uninstalled==true` 后**完全冻结**——成功不递增、**失败亦不归零**，定格 10

当 `uninstalled==true` 且 sync 中途 fatal（opencode 条目已处理且失败）时：§8.1 说"按已跑条目更新"，§10.5 说"完全冻结不归零"——二者字面似冲突，实际"更新"在冻结态是 no-op（保持 10）。但措辞易让实现者误以为 fatal 时仍执行归零。

**建议**：§8.1 该行注明"冻结态（`uninstalled==true`）下'更新'=no-op，保持定格值"，消除字面歧义。

### 3. §14 序号在"已闭合"与"已知风险声明"两组间交叉，可读性差

§14（行 730–743）分两组：
- **已闭合**：1, 4, 5, 6, 7, 9
- **已知风险声明**：2, 3, 8, 10, 11

两组共用一套递增序号但分属不同列表，序号交叉（已闭合 1→4 跳过 2/3，因 2/3 在风险声明组）。这是历史遗留（闭合项保留 `~~删除线~~` 占位）所致。

**建议**：两组分别独立编号（如"已闭合 C1–C6"、"风险声明 R1–R5"），或注明"序号为历史编号，跨组不连续"。

---

## 对 CodeBuddy v0.2.13 修订的核验小结

| CB 意见 | 核验结论 | 依据 |
|---|---|---|
| CB-P1-1 异常分型 | ✅ 正确且 fail-safe | catch 顺序合理；即使分型不精确（PID 不存在异常若非 `ProcessCommandException` 子类而落父类），落入 catch-all→LOCKED=假阴性安全方向，与 §14-3 声明一致 |
| CB-P1-2 Ticks 比较 | ✅ 方向正确 | `.ToUniversalTime().Ticks` 与 Kind 无关（100ns 计数），比 string/DateTime `-eq` 健壮；但写读侧格式契约见本审 P1-3 |
| CB-P2-1 完全冻结 | ✅ 自洽 | §10.5/§5.9 一致；仅 §8.1 措辞易混（见 P2-2） |
| CB-P2-2 runStatus 收窄 | ✅ 正确 | v0.2.12"单文件自洽"确为过强声明，收窄为"联判 runId"更准；fatal 在 sync 前时旧轮 sync.json 联判自然不通过，逻辑闭合 |
| CB-P2-3 action=target-locked | ✅ 一致 | §5.5/§8.1/§5.9 同步 |
| CB-P2-4 凭证新鲜度收紧 | ✅ 正确 | runId 唯一必要+字段缺失回退 runAt；防时钟回拨放过跨轮旧凭证；纵深防御与 §5.8 specVersion 检查不冲突 |
| CB-P3-1~P3-5 | ✅ 均合理 | 数据源明确/分支计数统一/声明按实/Codex 大小写/expectedSha256 落盘，均轻量对齐 |

**无 P0**：§6 锁接管伪代码经 CB-P1-1/P1-2 修订后，误接管（假阳性）路径已压到零——`TAKEOVER` 仅在"查询正常且 PID 无活跃进程"或"PID 命中但 tick 不匹配（锁值已过格式校验）"两个已证明死亡的分型发出，其余全部 LOCKED。未发现数据损坏级风险。

---

## 总评

v0.2.13 的 §6 锁接管伪代码是本项目最敏感的安全关键逻辑，经 v0.2.11（我引入回归）→ v0.2.12（修正方向）→ v0.2.13（CB 闭合 fail-open 缺口）三轮收敛，方向与 fail-safe 性已稳固。本轮 CodeBuddy 的 11 项修订我核验均认可，无驳回。

本轮我发现的 3 个 P1 集中在**契约层的两处断档与一处格式自洽**：
- **P1-1（run.lock 未进 §5.9 schema）** 是最实质的——CB-P1-2 刚钉死 processStartTimeUtc 格式契约，却无 schema 级落点，验收会漏；
- **P1-2（archive-state 缺成功标记）** 是标记协议的对称性缺口——唯独 archive-state 成功无 `*_OK|`，agent 判 OK 依据悬空；
- **P1-3（'o' 格式 vs 7 位正则）** 需实测确认，若属实则整秒边界陈锁接管失效（fail-safe 但违设计目的）。

3 个 P2 为表述/编号层面的轻量建议。建议优先 P1-1（补 run.lock schema 行）与 P1-2（补 `ARCHIVE_OK|` 标记），二者均为契约层硬缺口，宜本轮闭合。

**冻结建议**：P1-1/P1-2 闭合后，若下一轮 0 新 P0/P1，可冻结进入实现期。决策权在用户。
