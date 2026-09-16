# SPEC-v0.2.9 独立审计报告（CodeBuddy）

> **被审计对象**：`SPEC-v0.2.9.md`（703 行，2026-09-16）
> **对照基线**：`SPEC-v0.2.8.md`（diff 比对）、`cli-autoupdate-acceptance-checklist-candidate.md`（验收联动）
> **审计者**：CodeBuddy（独立审计；未参与 v0.2.9 修订）
> **审计日期**：2026-09-16
> **方法**：① v0.2.9 全文逐行内部一致性核对（§5 schema ↔ 示例 ↔ §7/§8/§8.1 ↔ §9 状态机）；② v0.2.8→v0.2.9 diff 逐项核实变更声明；③ 有限机器实测（只读命令，见 §3）。
> **证据标注**：`【核实】`= 文本逐行核对或命令实测；`【推断】`= 由文本推导的结论，未独立复现。

---

## 1. 总体结论

| 项 | 结论 | 来源 |
|---|---|---|
| v0.2.9 变更摘要 5 项声明（P0-1/P0-2/P1-1/P1-2/P1-3） | **全部真实落地**，无虚假声明 | 【核实】逐条查证，见 §2 |
| 核心路径（§7.3 九分支、§8/§8.1 标记协议、§5.4 三重约束、§10.5 计数） | 无 P0 级阻断缺陷 | 【核实】 |
| 内部一致性 | 3 项 P1 + 4 项 P2 + 5 项 P3 遗留问题 | 【核实】见 §4 |
| 机器事实（D 盘入口、LICENSE） | 与 spec 声明一致 | 【核实】见 §3 |
| digest 实测值 / "gh 已认证"声明 | **本轮未能复核**（环境限制，非文档缺陷） | 见 §5 |

**关键判断**：v0.2.9 完成了它自我声明的修订目标；但第 8 轮迭代后仍有一类**系统性问题未被扫清**——「schema 总表 ↔ 示例 ↔ 正文」三方一致性（D1/D2/D7 同族）。其中 D1（§5.9"全部"行 vs 5 个示例）正是 P0-2 被采纳的**同一类缺陷**，本次只修了 `verified.channel` 一例。另有 1 项分支完备性缺口（D3，标准流程下存在无分支命中的空洞）与 2 项 v0.2.9 新引入条款的内部矛盾（D4/D5）。

**冻结建议**：不建议立即冻结；D1–D5 均为文字级修订（不涉架构），修复后可进入冻结候选。不推荐把 D3/D5 列为已知风险——二者均可低成本文本闭环。

---

## 2. v0.2.9 变更声明逐项核实（C4：先核实再下结论）

| 声明 | 声称落地 | 实际核实结果 | 证据行 |
|---|---|---|---|
| **P0-1** REPAIR `target = remote.latest` 显式声明（§7.3/§5.3） | §7.3 条件5/REPAIR 语义段；§5.3 target 来源；§8.1 表 | ✅ 已落地。条件5 动作 `mise install <tool>@<remote.latest> --force`；REPAIR 语义段覆盖 broken+staging-空 / broken+local-ahead / prerelease 边界；§5.3/§8.1 同步 | 189 / 372 / 382–387 / 459 |
| **P0-2** verified.json 补 `channel` 字段（§5.4/§5.9） | §5.4 示例补 `"channel":"mise"` | ✅ 已落地，示例与 §5.9 表一致（但同类问题未扫清 → D1） | 193 / 285 |
| **P1-1** prerelease-vs-REPAIR 列 §14-11 | §14 已知风险 | ✅ 已落地，与 §7.3 REPAIR 段交叉引用一致 | 387 / 640 |
| **P1-2** N=10 计数机制（计数文件） | §10.5/§5 | ✅ 已落地：§10.5 算法 + §5.9 schema + §4 目录 + §7.2/§8.1 sync 职责同步（算法内部矛盾 → D5） | 99 / 305–307 / 354 / 465–468 / 563–573 |
| **P1-3** ALL_REMOTE_FAIL 聚合口径 | §8 表 | ✅ 已落地（RATE_LIMITED 与 REMOTE_FAIL 均计入） | 414 |

**附带核实**：§14「已闭合」与「已知风险声明」的划分维持"不伪关闭"风格，未见虚假闭合。行 625–640。

---

## 3. 机器事实核实（有限实测）

| 声明 | 实测结果 | 结论 |
|---|---|---|
| §3：D 盘三入口已补全 | `claude.exe` 231,776,416 B / `codex.exe` 298,169,136 B / `opencode.exe` 179,998,248 B，三文件均存在 | 【核实】一致；且 codex 字节数与 §5.1/§5.4 示例值（298,169,136）精确相同——示例数据系真实机器值 |
| §0：仓库根 LICENSE = AGPL-3.0 | LICENSE 首两行 = "GNU AFFERO GENERAL PUBLIC LICENSE / Version 3, 19 November 2007" | 【核实】一致 |
| §5.2/§14-1：v1.18.31 digest `sha256:0ecd7ffc…`；§5："本环境 gh 已认证" | 当前 shell 中 `gh`/`mise` 均不在 PATH，常见安装路径（Program Files 等）未命中 | **未核实（环境限制）**；另见 D13 |

---

## 4. 新发现问题

### P1 级

#### D1 —— §5.9「全部」行与 5 处示例不一致（P0-2 同类问题未系统扫清）【核实】

- **位置**：§5.9 表（行 257–259）vs 各示例。
- **现象**：
  - §5 正文（行 128）声明"所有 JSON 顶层带 `specVersion`、`name`"，§5.9 表列「全部｜name｜是」「全部｜error｜是」；但 **sync.json 示例（行 209–217）既无 `name` 也无 `error`**；**verified / current-run / pin / opencode-npm-fallback 示例（行 193/225/231/565）均无 `error`**（local/remote/upgrade 三个示例有）。
  - §5.9 表未列 `entries[].name`（示例行 212/216 存在该字段）。
  - §10.5 新增的 opencode-npm-fallback.json 示例同样缺 `error`。
- **影响**：§5.9 自称"与示例一一对应"（行 253）不成立；按表机械断言（遍历"全部"行）将失败或迫使实现者自行裁定。与 P0-2 采纳时指出的"schema/示例矛盾"同族。
- **建议**：二选一（推荐 a）：(a) 表行按文件枚举，标明 `name` 仅适用 local/remote/upgrade/verified/current-run/pin/npm-fallback、`error` 仅适用 local/remote/upgrade；(b) 各示例补 `"error":null`，sync 示例补 `"name"`。

#### D2 —— upgrade.json.fromVersion 的 null 语义未同步到 §5.9 类型表（v0.2.9 新引入）【核实】

- **位置**：§5.3（行 189）、§8.1（行 459）vs §5.9（行 280）。
- **现象**：§5.3 与 §8.1 均明文"REPAIR 时 `fromVersion` 可能为 null（opencode staging 空）"，但 §5.9 表 `upgrade.json | fromVersion | string | 是`——类型不含 null（同表 `target` 无此问题，条件1 已拦 null）。
- **影响**：验收按表断言 string 时与实际 null 冲突；与 P0-1 修订意图（覆盖 staging 空场景）直接相关。
- **建议**：表类型改 `string|null`。

#### D3 —— §7.3 条件7/8 覆盖边界未定义：标准流程下存在"无分支命中"空洞【核实（时序）+ 推断（后果）】

- **位置**：§7.3 行 364（输入声明）、374–375（条件7/8）。
- **论证链**：
  1. §9 状态机（行 490–498）：每轮 `upgrade → verify` 顺序执行一次；upgrade 执行时点，**本轮 verify 尚未运行**——upgrade 读到的 verified.json 必然来自上一轮（runId/runAt 均为上轮）。
  2. 故条件7"有本轮新鲜凭证"（新鲜度=§5.4 双判据：`runId==current-run.runId` 或 `runAt≥startAt`）在**当轮首次调用中恒不成立**，条件7 是死分支。
  3. 条件8"凭证缺失或 `verified.version ≠ local.version`"按字面（"缺失"=文件不存在）在"上一轮凭证存在且 `verified.version == local.version`"时不成立——而这恰是"连续两轮 UPTODATE"的常态。
  4. 此时条件1–9 全不命中，表无 else 兜底 → **行为未定义**（实现者自由裁定：无输出 / 异常 / 自造行为），违反 §1 原则3"固定状态机"与 §15"九分支全覆盖"的验收前提。
- **另**：§7.3 输入声明只列 `local.json + remote.json`，但条件7/8 需读 `verified.json` 与 `current-run.json`——输入清单不完整（行 364）。§8 表（行 416）将条件8 归纳为"凭证缺失/过期"，与 §7.3 文字（含 `verified.version≠local.version` 分支）不完全对应。
- **修复建议**（任选其一，须显式）：
  - (a) 条件8 改为"local == remote 且**无本轮新鲜凭证**（缺失 / 不新鲜 / version≠local）"——明确 7/8 互补，UPTODATE 常态=每轮 refresh verify（成本：每轮 3 CLI `--version` + sha256；可接受则最简单）；
  - (b) 若保留跨轮 SKIP，条件7 应改为引用"最近有效凭证"（如"上轮凭证存在且 `verified.version==local.version`"）并定义判定方式，同时说明 sync 端无本轮凭证时按 `SYNC_SKIP|no-fresh` 幂等；
  - (c) 无论选哪个，追加 else 兜底（如 `RUNTIME_ERROR|<cli> branch-undefined`）保证九分支穷尽。
- **附注**：选 (a) 会使 `UPTODATE_SKIP` 跨轮恒不可达，需同步修订 §8 表语义或将其限定为"同轮重复调用幂等"。与 §10.5 计数、§13-2 首轮 seed 描述无冲突（均依赖 refresh 路径）。

### P2 级

#### D4 —— §7.2 模块表 REPAIR 动作残留未定义 `<ver>`（v0.2.9 修订漏改点）【核实】

- **位置**：§7.2 表 upgrade 行（行 352）：`REPAIR=mise install <tool>@<ver> --force`。
- 与 §7.3 条件5（行 372：`@<remote.latest>`）、§5.3（行 189：target=remote.latest）不一致。
- **影响**：§7.2 是实现拆模块的直接依据；`<ver>` 未定义正是 P0-1 要闭合的问题，此处漏改使其在模块清单层残留。
- **建议**：改为 `@<remote.latest>`（或引用 §7.3 条件5）。

#### D5 —— §10.5 归零括注与 §8/§9 矛盾；fatal 场景计数语义两处冲突（v0.2.9 新引入）【核实】

- **位置**：§10.5（行 570）vs §8（行 414）、§9（行 487/502）、§8.1（行 468）。
- **现象**：
  1. §10.5 将"未跑 sync 如 ALL_REMOTE_FAIL"列为归零情形；但 §8/§9 明确 ALL_REMOTE_FAIL 是"跳 upgrade/verify，**直进 sync**"——该场景 sync 会跑，opencode 条目因无新鲜凭证走 `SYNC_SKIP`（非 already-current），已被归零规则第 4 项覆盖。括注例举错误。
  2. 真正"未跑 sync"的是 fatal 终止场景（`LOCKED|`/`STATE_MISSING|`/`PARSE_ERROR|`/`RUNTIME_ERROR_FATAL|`）。§10.5 称"未跑 sync → 归零"；§8.1 却规定 fatal 时"计数按已跑的 opencode 条目结果更新（fatal 前已处理则更新，否则不动）"——"不动"（保持旧值）与"归零"直接冲突。
- **影响**：N=10 计数在 fatal 场景的行为两处矛盾；计数是卸载触发条件，语义必须唯一。
- **建议**：明确唯一规则（推荐：fatal 时"不动"；仅当 sync 完整执行到末步才按条目结果 +1/归零），并把 §10.5 括注改为"sync 未完整执行（fatal 中断）→ 不更新"。

#### D6 —— §5.4 三重约束②措辞无法直接机械化【核实（原文）+ 推断（读法）】

- **位置**：§5.4（行 198）："② 完整性（opencode sha256 非空且**与下载校验值一致**）"。
- **现象**：`verified.sha256` 是**解压后 exe** 的 SHA256（§5.2 策略5，行 170）；下载校验值 `expectedSha256` 是 **zip** 的 SHA256（行 161/167）。两者数值上必然不同，字面"一致"无法实现。
- **可行读法**：若"下载校验值"指 `upgrade.json.sha256`（staging exe hash，§5.3 行 187）则可等价校验，但该字段 mise 通道仅 SHOULD；若指"下载校验已通过"这一事实，则应表述为"凭证链成立（下载校验通过 → `verified.sha256` 非空）"。
- **建议**：改写为可机械判定表述，如"opencode：`verified.sha256` 非空，且 sync 复算 `sourceSha256 == verified.sha256`"；或明确指称 `upgrade.json.sha256`。

#### D7 —— opencode-npm-fallback.json 未纳入 §5 时间字段规则【核实】

- **位置**：§5 规则（行 126）："除 `current-run.json`（startAt）与 `*.pin`（setAt）外，其余 state JSON … MUST 带 `runAt`"。
- **现象**：v0.2.9 新增的 `opencode-npm-fallback.json`（行 563–566、§5.9 行 305–307）只有 `lastUpdatedAt`，无 `runAt`。按行 126 字面它属"其余 state JSON"→ 违反 MUST；§5.9 表按文件列举 runAt 时未覆盖它。
- **建议**：行 126 例外清单补 `opencode-npm-fallback.json（用 lastUpdatedAt）`，或将时间字段规则改为按文件枚举。

### P3 级

#### D8 —— §9 段B 列出 RUNTIME_ERROR_FATAL，§8/§8.1 却将其限定为 archive/sync【核实】

- §9 状态机段B（行 485）含"[RUNTIME_ERROR_FATAL] → fatal 终止"；§8 表（行 407）产出脚本="archive/sync（骨架级）"；§8.1 无 probe/upgrade/verify 的 FATAL 行。
- **建议**：明确 probe/upgrade/verify 是否可产 fatal（如各脚本续锁失败是否升级为 fatal），三处对齐。

#### D9 —— ALL_REMOTE_FAIL 的产出者未钉死【核实】

- §8 表（行 414）产出脚本="probe-remote 末"、§8.1（行 458）exitCode=2"末步汇总标记"；但 §7.2（行 351）probe-remote 为每 CLI 独立脚本，单 CLI 脚本无法自然知晓"三 CLI 全失败"（需跨读其他 remote.json 或依赖执行顺序 / agent 汇总）。
- **建议**：明确产出方（第 3 个执行的 probe-remote 汇总巡检，或由 agent 依三个 recoverable 标记判定并写进 SOP）。

#### D10 —— REMOTE_FAIL 落盘字段清单不全【核实】

- §5.2（行 163）声明 latest/sourceUrl/directUrl/error 处置；§8.1（行 457）补 digest/expectedSha256=null；但 `assetName`/`checksumAssetUrl`/`fallbackUsed` 取值未声明，而 §5.9 表将其列为"是"必填（行 275–279）。
- **建议**：补"assetName/checksumAssetUrl=null；fallbackUsed=false"或注明实现自定。

#### D11 —— §5.2 策略5 跨脚本表述易误读【核实】

- 行 170："解压后对目标 exe MUST 计算 SHA256，写入 verified.json.sha256"——解压动作在 upgrade 脚本，verified.json 由 verify 脚本产出（§7.2、P0-3 边界）。表述可被读作 upgrade 越界写 verified.json。
- **建议**：改为"upgrade 解压后计算 SHA256 写入 upgrade.json.sha256；verify 复算并写入 verified.json.sha256（两者应一致）"。

#### D12 —— §5.8 示例自相矛盾（版本号机械替换所致）【核实】

- 行 245："若 `specVersion != 当前实现版本`（如读到 `"0.2.9"` 而本轮跑 `"0.2.9"`）"——示例两侧同值，条件不成立，示例失去意义（v0.2.8 同位置为 "0.2.8" vs "0.2.8"，同病；正确示例应如 `"0.2.8"` vs `"0.2.9"`）。
- **建议**：修正示例为跨版本值；本次全文档核对未发现其他同类失真实例。

#### D13（观察）—— 环境前提未复核

- 当前 shell 中 `gh`/`mise` 均不在 PATH，常见安装路径未命中 → §5"本环境 gh 已认证（demonpiapia）"与 §5.2 digest 实测值本轮未独立复核（属审计局限，非文档缺陷判断）。
- 另提示：实现期需明确 `gh` 的定位方式（绝对路径候选 / env 注入），否则 token 提额路径在部分 shell 环境可能直接失败。

---

## 5. 审计局限（未核实项声明）

1. `sha256:0ecd7ffc…`（opencode-windows-x64.zip）与 tag `v1.18.31`、37 asset digest 覆盖率：本轮未能复跑（`gh` 不在当前 shell PATH），沿用 v0.2.7 会话实测记录，**本轮未独立复核**。
2. §13-3 版本声明（claude 2.1.273 / codex 0.154.0 / opencode 1.18.31）与 mise installs 布局：`mise` 不在当前 shell PATH，未复核。
3. Cherry 定时任务沙箱内的 PATH/环境与本次 shell 可能不同；"`gh` 不在当前 shell PATH"不能直接判定沙箱内不可用。
4. 本审计为静态文本审计 + 有限只读命令；未运行任何 spec 脚本（脚本尚未产出）。

---

## 6. 与验收 checklist candidate 的联动提示

- **D1** 影响 checklist A 节"所有 state JSON 顶层 specVersion+name"断言与 D 节遍历断言（sync.json 无 name 与 spec 正文冲突）。
- **D2** 影响 checklist I1 第 5 行（REPAIR fromVersion 可能 null 断言与 §5.9 类型表冲突）。
- **D3** 影响 checklist I1 第 7/8 行与 I0"九分支全覆盖"断言（空洞情形无预期标记可断言）；若采纳修复方案 (a)，I1 第 7 行"真幂等"判断需改写。
- **D5** 影响 checklist K6 节"失败归零/未跑 sync"用例（fatal 场景预期值需在两处规则间取唯一）。
- **D7** 影响 A 节"遍历 state/*.json 断言 specVersion+name+runAt"类断言对 npm-fallback 的适用性。

---

> 审计者：CodeBuddy ｜ 2026-09-16 ｜ 命名约定：被审计文件名 + `-codebuddy-review`
