# SPEC-v0.2.18-rc3 审计报告（CodeBuddy 独立审计 · 最终版）

- **被审计文件**：`d:\AI\Workspace\automatic\CLI-autoupdate\SPEC-v0.2.18-rc3.md`（900 行 / 140078 字符）
- **本报告命名依据**：被审计文件名 + `-codebuddy-review` 后缀（同目录交付）
- **阶段一产物（强制前置，已落盘）**：`SPEC-v0.2.18-rc3-review-candidate.md`（独立盲审报告 candidate，物理文件已存在）
- **审计时点**：2026-09-17
- **审计环境（实测）**：Windows 11 / PowerShell 7.6.4 / mise 2026.7.14 windows-x64 / npm（`D:\Program Files\nodejs\npm.cmd`）/ GitHub API 直连可用

## 0. 审计顺序与取证边界声明

1. **先盲审**：阶段一在**未打开**任何历史审计报告、**未做** rc2 逐行 diff、**未读**验收 checklist / memory / `.version-history` 的条件下，对 rc3 全文做独立正确性盲审，产出并落盘 `-review-candidate` 物理文件（内容即阶段一报告，含 1 P0 / 3 P1 / 14 P2）。
2. **后综合**：本报告在阶段一结论之上，追加以下交叉核对：rc2→rc3 逐 hunk 差异归属、验收 checklist 候选稿、`.version-history/spec-version-history.md`、工作区 memory 记录。
3. **来源标注规则**：`【实测】`= 本机/远端命令原始输出；`【推断】`= 由多条实测事实推理、未直接观测目标行为；`【核对】`= 仅文本内部或跨文档比对。断言性措辞仅用于【实测】项。
4. **P0-1 的隔离原则**：涉及卸载类操作，**未在真实 npm 前缀上执行**，全部实验在隔离沙箱前缀（系统 TEMP 下）完成；真实环境只做只读枚举。

## 1. 分级定义

| 级别 | 定义 |
| --- | --- |
| P0 | 条款指令与实测事实冲突，致预期动作**不可达**或产生**假成功记录**，且 spec 自带的控制手段无法检出 |
| P1 | 条款互相矛盾 / 关键数据流或定位方式缺失 / 关键判据依赖未定义输入，影响可机械验收性 |
| P2 | 表述泛化、枚举语义缺失、跨文档叙述与格式残留、建议条款前提不全 |

## 2. 判定摘要

| 级别 | 数量 | 条目 |
| --- | --- | --- |
| P0 | 1 | §10.5 卸载目标包名错误 + 退出码控制漏检 → 假成功且不可回退 |
| P1 | 3 | ① `single-source` 无承载字段；② `already-current` 依赖 SHOULD 级 sha256；③ npm 可执行定位未定义且首选项实机不存在 |
| P2 | 14 | 见 §5 |

**rc3 本轮修订本身的自洽性**：rc2→rc3 共 **22 个 hunk（+30/−30）**，逐块归属均为 rc3 声明的改动，**未发现夹带**；§6 锁模型、§7.3 九分支结构、§8 标记协议、§5.10 威胁模型、§5.9 schema 主轴**未被改动**（详见 §6.1）。

**总体判断（事实层）**：rc3 的机器事实层声明（CLI 版本、mise 常量、时间序列化契约、陈锁异常分型、GitHub digest、`mise ls-remote --json` 与 `mise upgrade @latest` 语法）经本轮实测**全部成立**；存在 1 项 P0 级指令-事实冲突与 3 项 P1 级契约缺口，均集中在 **§10.5 npm 卸载/定位** 与 **§5.4/§5.5 完整性数据流**两处。

## 3. P0 发现

### P0-1 §10.5 卸载目标包名与实机不符 + 退出码控制漏检 → 静默假成功、状态不可回退

**条款**
- §10.5："卸载触发…执行 `npm uninstall -g opencode`，**MUST 检查退出码**：仅 npm 退出码==0 才置 `uninstalled=true`…反向：npm 退出码!=0 / npm 二进制缺失 / 权限拒绝 → 保持 `uninstalled=false`"。
- §5.9 / §10.5："`uninstalled==true` 后**完全冻结**（成功不增、失败不归零，定格 10）"、"`uninstalled` 一旦 true 不回退"。
- §15 单元断言："§10.5 npm 卸载失败不置 true 断言（npm 退出码!=0 → 保持 uninstalled=false）"。

**实测事实（三条独立证据）**
1. 实机全局已装包名为 **`opencode-ai@1.18.31`**：`npm ls -g --depth=0 --prefix E:\Users\WIN_11\AppData\Roaming\npm` 输出 = `@larksuite/cli`、`@larksuiteoapi/lark-mcp`、`agentmail-mcp`、`myagentmail-mcp`、**`opencode-ai@1.18.31`**、`pear`；该前缀下**不存在** `node_modules\opencode`（存在的 `opencode` / `opencode.cmd` / `opencode.ps1` 是 `opencode-ai` 提供的 bin shim，bin 名 ≠ 包名）。
2. **机制实测（沙箱前缀，不触碰真实环境）**：在隔离前缀装 `is-number@7.0.0` → 执行 `npm uninstall -g opencode`（未安装的包名）→ 输出 `up to date in 618ms`、**exit=0**，随后 `npm ls -g` 显示 `is-number@7.0.0` **仍在**（已装包不受影响）。
3. 空前缀同样验证：`npm uninstall -g opencode` → `up to date`、exit=0、无任何改动。

**结论链**
- 【实测】目标包名应为 `opencode-ai`；spec 现值为 `opencode`。
- 【实测】对未安装的包名执行卸载：exit=0、且不影响其他已装包。
- 【推断】故 §10.5 现值在真实前缀上的效果 = **不移除 `opencode-ai` 及其 `opencode*` shim**，退出码仍为 0 → 依 MUST 置 `uninstalled=true` → 因"一旦 true 不回退"**永久定格**。即：npm 全局 fallback 实际存在，而机器事实记为"已卸载"；§15 用于兜底的"退出码!=0"断言**无法检出该情形**。
- 未直接观测项：未在真实前缀执行该卸载（隔离原则），故"真实前缀输出"未实测 → 已明确标注为【推断】环节。

**与前轮处置的关系（交叉核对）**：该项系历史轮 anthropic **E1**（"§10.5 npm 卸载失败无处理规则、误置 uninstalled=true 永久不符"）在 v0.2.16 的处置**不完整**——当时采纳的控制手段是"检查 npm 退出码"，但实测存在"包名不存在 ⇒ 退出码 0 ⇒ 控制失效"的漏检路径；根因（包名）从未被核实。同类问题另见 P1-3（E2）。

**建议（最小改法）**
1. 包名改为 **`opencode-ai`**；或改为运行时解析（`npm ls -g --json` 找出提供 `opencode` bin 的包名），避免上游改名后再次失效。
2. 卸载成功判据升级为**结果断言**：`退出码==0` **且** prefix 下 `opencode`/`opencode.cmd`/`opencode.ps1` 与 `node_modules\opencode-ai` 均不存在（与 §5.8"验收以结果断言为准"同源）；退出码断言降为辅助。
3. §5.9/§15 同步：把该结果断言写入验收条目。

## 4. P1 发现

### P1-1 §5.2→§5.5 `integrityNote:"single-source"` 无承载字段（跨模块数据流断裂）

- **条款**：§5.2 步骤 4 允许"直连不通 → 仅用反代"偏离，并要求"`integrityNote:single-source`，**须在 sync.json.entries 记录**"；§5.5/§5.9 将 `single-source` 列为 `entries[].integrityNote` 枚举值。
- **【核对】**§5.9 中 `remote.json` 字段集（channel/latest/sourceUrl/directUrl/assetName/prerelease/assetDigest/expectedSha256/checksumAssetUrl/fallbackUsed/error）与 `upgrade.json` 字段集（fromVersion/target/exitCode/ok/sha256/error）**均无承载该事实的字段**。
- **结论**：该偏离产生于 upgrade 段（下载期），消费方为 sync 段；sync 不得重打 API（§1 原则2 数据固化），亦不得读 `fetch_run.log`（§1 原则10 机器事实/叙事分层）。故该 MUST **不可实现**，除非由 agent 手写机器事实文件（违反 §1 原则10）。
- **建议**：在 `upgrade.json`（或 `remote.json`）增设承载字段（如 `downloadMode: dual|single-proxy`），或把该标注改为 upgrade 段 stdout 标记 + `fetch_run.log`，并同步 §5.5/§5.9/§15。
- **注**：与 §14-2 已声明的"反代可靠性待实测"叠加后，该缺口在实测环境下更易触发（见 §6.3 反代实测）。

### P1-2 §5.5 `already-current` 判据依赖 mise 侧 SHOULD 级 sha256，缺失退化未定义

- **条款**：§5.5"判定晋升前，若 D 盘目标 exe 存在且 sync 复算其 sha256 == `sourceSha256`"→ `SYNC_SKIP|already-current`（该条以 MUST 措辞要求，且声明目的是"防稳态轮逐轮空翻新 copy 与 `SYNC_TARGET_LOCKED` 反复归零 §10.5 计数"）；但 §5.9 对 `sourceSha256` 仅要求 **opencode 必填、mise SHOULD**；§5.4 允许 mise 侧 sha256 缺失时跳过完整性②（`integrityNote=sha256-missing-skip`）。
- **【实测】输入可得性**：当前 claude/codex 的 D 盘入口与 mise staging **字节同一**（size 相等、SHA256 相等：claude `19654006…20EF0`、codex `BE96B992…DFDE`）。
- **结论**：一方以 MUST 强制 `already-current`，另一方其唯一输入在 mise 侧只是 SHOULD，**二者的衔接条款缺失**——若实现遵从 SHOULD 不计算 mise sha256，则 `sourceSha256=null`，判据无输入、退化行为（空 copy / 跳过 / 报错）未定义，正好落回该条声明要避免的场景。
- **建议**：mise 侧 `sourceSha256` 升为 MUST（成本 = 每轮一次 staging exe 读，实测 claude 231MB / codex 298MB 级）；或显式定义缺失时的退化路径（如 `size + version` 相等 → 记 `sha256-missing-skip` 并 skip）。

### P1-3 §10.5 npm 可执行定位未定义，且 spec 给出的第一选项实机不存在

- **条款**：§10.5"**调用 npm MUST NOT 依赖 PATH**…显式使用 `Get-NpmPrefix()` 定位 npm 全局位置，**调用该 prefix 下 npm 二进制**或显式传 `--prefix <Get-NpmPrefix()>`"；§2 末行"harness 固定调用…不依赖 PATH"。
- **【实测】**`E:\Users\WIN_11\AppData\Roaming\npm\npm.cmd` **不存在**；`npm`（无扩展）**不存在**；该 prefix 内只有各包的 bin shim。PATH 中 npm = `D:\Program Files\nodejs\npm.ps1`，node = `D:\Program Files\nodejs\node.exe`；`npm config get prefix` = `E:\Users\WIN_11\AppData\Roaming\npm`（与 Cherry 前缀一致）。
- **结论**：第一条路径不可实现；第二条可行，但"在不依赖 PATH 前提下定位 npm 可执行"的规则在 §7.1 常量清单中缺失（无 node/npm 路径、无 `Get-NpmExePath()`）。
- **与前轮处置的关系**：历史轮 anthropic **E2**（"npm 卸载未声明绕开 PATH"）在 v0.2.16 处置为"改用 `Get-NpmPrefix()`"——实测该项只解决了"目标前缀"，未解决"npm 本体在哪"。
- **建议**：§7.1 增补常量/定位规则（node 与 npm 绝对路径，或由已知 node 目录推导 `npm.cmd`），删除"该 prefix 下 npm 二进制"选项。

## 5. P2 发现

| # | 位置 | 问题 | 来源 | 备注 |
| --- | --- | --- | --- | --- |
| P2-1 | §5.8 新补 SHOULD"优先 .NET `File.Replace`（同卷）" | 前提未声明：`File.Replace` 要求**目标文件已存在**——实测目标缺失抛 `FileNotFoundException`（"Unable to find the specified file"）；跨卷实测抛 `IOException: 无法删除要被替换的文件`（跨卷限制 spec 已声明）。首轮无既有 state 文件，恰为目标缺失场景 → 按此 SHOULD 实现会在首次写入失败。 | 实测 | **本条由 rc3 本轮新引入**（rc2→rc3 hunk @@ -273） |
| P2-2 | §5.5/§5.9 `integrityNote` 枚举 | `sha256-recomputed` **全文无语义定义**（仅两处枚举列举，无"何时必须写"），而同枚举其余值均有定义 → 实现无法判断、验收无法断言。 | 核对 | |
| P2-3 | §12 自检表"供应链"行 | 仍写 "checksum MUST + 双 hash SHOULD"，未反映现行三级链（API digest 主路径 MUST → checksum 条件 MUST → 双 hash SHOULD），且"checksum MUST"的无条件表述与 §5.2"checksum asset 存在则 MUST"矛盾。 | 核对 | rc3 已更新 §1 原则12/§5.2/§16 三处，**独漏 §12** → 同族只修一例 |
| P2-4 | §14-6 标题与结论 | 标题为"opencode 官方 **checksum 覆盖率** → 已闭合（实测）"，证据实为"37/37 asset 带 API **digest**"。实测该 release **无任何 checksum 类资产**（37 项中无 `.sha256`/`checksums.txt`，仅 `latest*.yml`/`latest.json` 更新器元数据）→ 真实覆盖率 **0**，故 §5.2 策略 3（checksum fallback）对 opencode **恒不可达**、策略 4（双 hash）为唯一 fallback；spec 未声明该不可达性。 | 实测 | |
| P2-5 | §5.2 REMOTE_FAIL 落盘清单 | 硬编码 `fallbackUsed:false`：若失败发生在 `releases/latest` → `releases?per_page=10` 回退路径**之后**，事实为 true 却写 false → 证据链失真（同节回退规则规定命中回退才置 true）。 | 核对 | |
| P2-6 | §5.2 asset 筛选 | 写法"assets 筛 `windows-x64.zip`"未钉死精确名匹配；实测同 release 存在同子串干扰资产 `opencode-windows-x64-baseline.zip`(60718508) 与 `opencode-windows-arm64.zip` → 子串筛选会命中 `-baseline`。 | 实测 | 后果为 digest 不匹配 → `DOWNLOAD_FAIL`（fail-closed 可检出），故列 P2 |
| P2-7 | §15 单元⑦ 负例断言 / §6 缺口②描述 | "**同一时刻的 string 形态 `-eq` 比较实测恒 False**"过度泛化：实测同形态（均 UTC `'o'`、同一时刻）字符串 `-eq` → **True**；跨形态 → False；DateTime 对象跨 Kind `-eq` → False。照字面编写该负例断言会与被测事实冲突。 | 实测 | §6 与该断言同源，建议同步限定为"未归一化/混形态" |
| P2-8 | §7.3 条件 7/8 说明段 | 保留修订叙述："**由此原条件7…（死分支）**"、"原条件8…亦不成立"、"**修订（条件7/8 改为互补）**"——引用本文件中已不存在的旧文本，违反页首指令 2/5（修订记录只允许在会话汇报）。 | 核对 | rc3 同类清扫已应用于同节"条件2 的 null 处理（P0 v0.2.8 消歧）"段（hunk @@ -545），**独漏条件7/8 段** |
| P2-9 | §5.8 末条 | "**checklist A 节**'旧 specVersion 触发 fail-closed'断言据此修正为…"——引用尚未产出（§15：评审通过后产出）且非本文件内容的断言，属跨文档修订叙述。 | 核对 | 该断言确存在于 checklist 候选稿（其 §A 行自述"系脑补、已修正"） |
| P2-10 | §7.1 跨盘跨用户成因说明 | 句末"**非文档拼接错误——后续审计者复核时请勿误判**"属面向审计者的防御性叙述（页首指令 5 禁止防御性描述）。 | 核对 | 事实部分（跨盘成因）可保留 |
| P2-11 | §13-4 checklist 末二项 | "含 `.git` 段的路径走手动删除（**R43 工具保护**，禁 rm/mv 规避）"——`R43` 全文无定义/出处，验收不可机械化。 | 核对 | |
| P2-12 | §8 引言 exitCode `10` | 定义为"dry-run 有动作"，但 §8.1 全表无任何行产出 10，且"哪些脚本支持 dry-run / dry-run 是否落盘 state / 标记是否相同"全文未定义 → 该码与验收条目悬空。 | 核对 | |
| P2-13 | §8.1 sync `SYNC_SKIP|` 行 | exitCode 列写作 "0/11"（同一标记两值未定）；同表注又规定"sync 脚本级退出码一律由末步 `RUN_STATUS` 决定"，机械断言需单值化。 | 核对 | |
| P2-14 | §7.1 目录扫描 + §5.9/§7.2/§16 表格形态 | ① **【实测】**`installs\claude\2.1.273` 为 **Junction**（ReparsePoint → `http-tarballs\<hash>`），`installs\codex\0.154.0` 为普通目录；同层另有 9 字节普通文件 `2`/`2.1`/`latest` 与 `.mise.backend.toml`。§7.1 仅规定"取最高 semver 版本目录"，未规定 ReparsePoint/非版本条目过滤规则 → 若按属性排除重解析点，claude 将被误判 `LOCAL_EMPTY` → 触发不必要 REPAIR。② §5.9 用 `<br />` 作首列续行占位、§7.2 与 §16 表头含多余空列（`| <br /> |`），非标准 md 表格（页首指令 6 要求首选标准大纲序号格式）。 | 实测+核对 | |

## 6. 交叉核对结果（阶段二）

### 6.1 rc2→rc3 差异归属核对（22 hunks / +30 / −30）

【实测】`git diff --no-index -U0 SPEC-v0.2.18-rc2.md SPEC-v0.2.18-rc3.md` = 22 个 hunk、30 插入 30 删除，逐块归属如下（**全部可归属 rc3 声明改动，无夹带**）：

| 归属 | hunks | 内容 |
| --- | --- | --- |
| 版本/指针 | 2 | § 版本行 rc2→rc3；§4 文件树"本文件"指向 rc3 |
| P1-2（去 immutable） | 3 | §1 原则12、§5.2 步骤2、§16"API asset digest"行 → 改"GitHub 计算并经 API 返回，证明下载==API 所见，非签名保证" |
| P1-1（ALL_REMOTE_FAIL 单口径） | 3 | §8 表该行（删除"读 remote.json"措辞→钉死仅 stdout 标记）、§8.1 聚合行、§15 集成行 |
| P1-3（File.Replace SHOULD） | 1 | §5.8 首段（**本条即 P2-1 的来源**） |
| attestation 叠加关系 | 1 | §5.10 未来增强段补"启用时机 + 叠加门槛" |
| P0-1（§14 历史化） | 3 | §14 标题（删审计来源清单 + 修 typo）、"已闭合"编号说明改写、8 条已闭合条目去删除线 |
| 编号引用语义化 | 9 | §3 实机现状（去 F1）、§5.2 步骤5（去 P0-3）、§5.4 失败不覆盖（去 P0-3）、§5.4 UPTODATE_REFRESH 行（去 P0-3）、§7.3 条件2 段（去 P0 v0.2.8）、§8.1 probe-local 行（去 P0-3）、§8.1 upgrade 两行（去 P0-3）、§8.1 verify 行（去 P0-3）、§9 铁律9（去 P0-1）、§14-13（§17→§16） |

**核对结论**：rc3 声明"§14 标题来源清单删除 / 条目去删除线 / 编号说明改活锚理由 / P1-2 三处去 immutable / P1-1 三处单口径 / P1-3 File.Replace / P2-1 驳回（表格密度未动）/ 编号引用语义化 / §17→§16"——**逐项可见且位置一致**；§6 锁伪代码、§7.3 if-elif 九分支结构、§8 标记表主体、§5.9 schema 表主体、§5.10 威胁模型主体**逐字未动**。

### 6.2 清扫完整性（本轮新发现的结构性观察）

同一轮"审计编号语义化"清扫**存在两处漏项**，均属项目历史自述的高频缺陷型"同族只修一例"：
- §7.3 条件2 段的 `（P0 v0.2.8 消歧）` 已清除，而**同节条件7/8 段的修订叙述（含"原条件7/原条件8/修订（…）"）未清**（→ P2-8）。
- §1 原则12/§5.2/§16 的旧供应链表述已更新，而**§12 自检表同行表述未更新**（→ P2-3）。

### 6.3 其他资料核对

| 资料 | 核对结果 |
| --- | --- |
| 验收 checklist 候选稿 | **未随 rc3 同步**：其版本钉死仍为 `-v0.2.17` / `specVersion "0.2.17"`（第 17/18/19 行），且全文保留 P 级 emoji 分级与"采纳 6"等旧计数；该稿自述"旧 specVersion 触发 fail-closed 断言系脑补、已修正"（支撑 P2-9 的存在性）。§15 已明确 checklist 为"评审通过后产出"的独立交付物，故上述**不构成 rc3 正文缺陷**，但构成交付物一致性待办。 |
| `.version-history/spec-version-history.md` | 全文 170 行，末条 = **v0.2.18-rc2**；目录与正文**均无 v0.2.18-rc3 条目** → 与页首指令 3（版本历史统一由 `.version-history/` 管理）相关的登记缺口（交付物级，非正文缺陷）。 |
| 历史轮 E1/E2（v0.2.16 采纳） | 与本轮 **P0-1 / P1-3** 直接同源：E1 的"退出码检查"存在实测漏检路径；E2 的"改用 `Get-NpmPrefix()`"未解决 npm 本体定位。 |
| 历史轮 R1（`sourceSha256` 一名三义） | 本轮独立复核：rc3 中 `sourceSha256` 在 §5.4/§5.5/§5.9/§16 四处**语义一致**（= sync copy 前复算的 staging exe hash），旧读法残留经 grep 未发现 → 该项**维持闭合**。 |
| 反代可用性（§14-2 已声明风险） | 【实测】`https://gh.jasonzeng.dev/` 根路径 GET 与 asset Range GET 均 `HttpRequestException / SSL connection could not be established`（DNS 正常解析至 Cloudflare A/AAAA）→ "反代为主链路"在本机当前时点不成立，直连回退（§5.2）实际成为常态路径；该状态同时提高 P1-1（`single-source`）的实际触发概率。**单一时点、单一方法，不构成"永久不可用"结论**。 |
| 工作区现状 | 无 `state/`、无 `staging/`；`TEMP/` 存在；`.version-history/` 存在 —— 与 §4/§10.4/§13-5 及页首指令 3 一致。 |

## 7. 已核实为正确的关键声明（实测）

| # | 声明 | 实测结果 |
| --- | --- | --- |
| 1 | §13-3 / §5.1 / §5.4 示例版本 | claude `2.1.273 (Claude Code)`、codex `codex-cli 0.154.0`、opencode `1.18.31`（三入口 `--version`） |
| 2 | §4 大小写约定 | `D:\AI\Programs\CLI` 实为 `claude \| Codex \| opencode`；小写路径等价可访问 |
| 3 | §0 LICENSE | 首两行 = `GNU AFFERO GENERAL PUBLIC LICENSE` / `Version 3, 19 November 2007` |
| 4 | §7.1 mise 常量逐条 | mise.exe / installs / npm prefix / `claude.exe` / `codex\bin\codex.exe` 全部存在；`MISE*` 普通 shell env 计数 = **0** |
| 5 | §5.2 `mise ls-remote --json` | 语法成立（claude → `[{"version":"2.1.274"}]`；codex → 含 created_at/release_url 的完整数组）；**claude/codex 的 JSON 不含 `prerelease` 键** → §7.3"mise 通道无 prerelease 布尔字段"对在册两工具成立（建议限定为"claude/codex 通道"，因 mise 对其他后端如 `github:` 的 `--json` 可含该字段） |
| 6 | §7.2 `mise upgrade <tool>@latest`（原标"待实现期实测"） | 实测被接受：`mise upgrade claude@latest --dry-run` → `Would uninstall claude@2.1.273` / `Would install claude@2.1.274`，exit=0；`mise upgrade claude --dry-run` 同结果 → `@latest` 解析目标 = 上游 latest（与 `remote.latest` 口径一致） |
| 7 | §7.2 REPAIR `mise install <tool>@<ver> --force` | `mise install --help` 含 `-f, --force  Force reinstall even if already installed`；`mise install claude@2.1.273 --force --dry-run` exit=0 |
| 8 | §5/§5.9/§6 时间契约 | DateTime（Kind=Local）`ToUniversalTime().ToString('o')` = `…4969303Z`（恒 7 位小数 + `Z`）；整秒 = `…03.0000000Z`；DateTimeOffset `'o'` = `…+08:00`（**无 Z**）；`RoundtripKind` 解析回 `Kind=Utc`、Ticks 相等；`Process.StartTime` 类型 `DateTime`、两次读取 Ticks 稳定 |
| 9 | §6 异常分型 | 不存在 PID → `ProcessCommandException`；`-Id $null` → `ParameterBindingValidationException`；`-Id 'abc'` → `ParameterBindingException`（均属"未证明死亡"类，落 `$lookupUnknown`→`LOCKED`） |
| 10 | §5.2/§14-1/§14-6 GitHub 声明 | tag=`v1.18.31`、`prerelease=False`、assets=37、**37/37 带 `sha256:` digest**；`opencode-windows-x64.zip` digest = `sha256:0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006`（与 spec 逐字符相符）；回退端点 `releases?per_page=10` 可用（10 项全 stable） |
| 11 | §13-2 seed/already-current 前提 | claude/codex 的 D 盘入口与 mise staging **字节同一**（size 与 SHA256 均相等）；codex D 盘字节数 298169136 = §5.1/§5.4 示例值 |
| 12 | §5.1 ">1MB 阈值、三款 CLI 远 >50MB" | 231776416 / 298169136 / 179998248 字节 ✓；zip 60718498 > 1MB ✓ |
| 13 | §4 路径无空格 | 所列 6 条 Canonical Path 均无空格 ✓ |

## 8. 未核实 / 受限项（明确声明）

1. **反代 URL 拼接形态**是否被反代接受：TLS 握手失败，未核实（非"已证伪"）。
2. **D 盘 `opencode.exe` 与 GitHub zip 内 exe 的同源性**：`staging/opencode/` 不存在，无法比对（首轮 `already-current` 结果未核实）。
3. **`mise upgrade` 非 dry-run 的真实实装版本**：本轮仅验证 dry-run 计划输出（未执行实际安装，避免改动环境）。
4. **`npm uninstall -g opencode` 在真实前缀的执行输出**：仅隔离沙箱实测机制（exit=0 / no-op / 不影响已装包）；真实前缀未执行 → P0-1 结论链的最后一环为【推断】。
5. **TLS 失败归因**：单时点、单方法，不排除本机 TLS/网络策略因素。

## 9. 处置建议（按优先级）

| 优先 | 条目 | 最小改法 | 影响面 |
| --- | --- | --- | --- |
| 1 | P0-1 | `npm uninstall -g opencode` → `opencode-ai`（或运行时解析包名）；卸载成功判据改为结果断言 | §10.5 + §5.9 + §15 |
| 2 | P1-1 | 增设 `downloadMode`/`integrityPath` 承载字段，或改为 upgrade 段标记 + 日志 | §5.2 + §5.5 + §5.9 + §15 |
| 3 | P1-2 | mise 侧 `sha256`/`sourceSha256` 升 MUST，或定义缺失退化规则 | §5.5 + §5.9 + §15 |
| 4 | P1-3 | §7.1 增补 node/npm 定位常量或规则，删除"prefix 下 npm 二进制"选项 | §7.1 + §10.5 |
| 5 | P2-1 | §5.8 补"目标不存在时直接 Move"分支或改述建议前提 | §5.8 + §15 |
| 6 | P2-3 / P2-8 | 补全两处"同族"清扫（§12 供应链行；§7.3 条件7/8 段修订叙述） | §12 + §7.3 |
| 7 | P2-2 / P2-4 / P2-5 / P2-6 / P2-7 | 逐条补定义/对齐事实（枚举语义、§14-6 标题、fallbackUsed、精确名筛选、负例措辞） | 各自小节 |
| 8 | P2-9 ~ P2-14 | 跨文档引用自洽化、防御性句删除、R43 释义、dry-run 语义、exitCode 单值化、Junction/别名过滤规则、表格形态 | 各自小节 |
| 附 | 非缺陷建议 | §7.2 的 `mise upgrade @latest` 实测标注可据 §7.4 实测结论替换为"已实测接受 + 日期"；§7.3 mise prerelease 表述可限定为"claude/codex 通道实测无该字段"；`.version-history` 补 rc3 条目；checklist 候选稿待另轮同步（0.2.17 + emoji 分级） | — |

## 10. 证据附录

阶段一 candidate（`SPEC-v0.2.18-rc3-review-candidate.md`）§7 已封装六批共 14 条命令的原始输出；本报告在阶段二新增以下证据（原始输出摘录）：

```
[11] rc2→rc3 diff 全量（落盘于系统临时目录并提供核对）
stat: 1 file changed, 30 insertions(+), 30 deletions(-)   → 22 个 hunk，逐块归属见 §6.1

[12] 沙箱 npm 机制实测（隔离前缀 E:\Users\临时文件\audit_npm_mech）
npm install -g is-number --prefix <sandbox>   → "added 1 package in 781ms" exit=0
npm ls -g --depth=0 --prefix <sandbox>        → `-- is-number@7.0.0
npm uninstall -g opencode --prefix <sandbox>  → "up to date in 618ms" exit=0
npm ls -g --depth=0 --prefix <sandbox>        → `-- is-number@7.0.0   （未被移除）

[13] 真实前缀全局包（只读）
npm ls -g --depth=0 --prefix E:\Users\WIN_11\AppData\Roaming\npm
  +-- @larksuite/cli@1.0.82 / @larksuiteoapi/lark-mcp@0.5.1 / agentmail-mcp@0.2.2
  +-- myagentmail-mcp@0.7.0 / opencode-ai@1.18.31 / pear@2.0.1

[14] 版本历史
.version-history/spec-version-history.md = 170 行；末条 = v0.2.18-rc2；无 rc3 条目
```

## 11. 审计结论（事实判定）

1. rc3 声明的本轮修订（22 hunks / +30 / −30）**全部真实落地、位置一致、无夹带**；判定语义主轴与关键契约表未被扰动 —— 与既往各轮"rc 修订可追溯"的结论一致。
2. 本轮独立发现 **1 项 P0 + 3 项 P1 + 14 项 P2**，其中 P0-1 与 P1-3 属**前轮已采纳项的处置不完整**（E1/E2），P2-1 属**本轮新引入**（File.Replace SHOULD），P2-3/P2-8 属**本轮清扫的漏项**。
3. spec 的机器事实层声明（CLI 版本 / mise 常量 / 时间序列化 / 陈锁异常分型 / GitHub digest / mise 子命令语法）经本轮实测**全部成立**，无一项被实测证伪。
4. 本报告**不作**任何"是否可冻结/是否进入实现"的阶段判断（该判断不在审计 agent 职权内）；上述条目是否处置、何时处置，由用户决定。
