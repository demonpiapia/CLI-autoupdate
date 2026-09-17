# SPEC-v0.2.18-rc3 独立盲审报告（stage-1 candidate）

- **被审计文件**：`d:\AI\Workspace\automatic\CLI-autoupdate\SPEC-v0.2.18-rc3.md`（900 行，140078 字符）
- **本文件性质**：**盲审阶段一产物**（独立正确性盲审），不是最终交付版
- **审计时点**：2026-09-17
- **审计环境（实测）**：Windows / PowerShell 7.6.4 / mise 2026.7.14 windows-x64 / npm（`D:\Program Files\nodejs`）/ GitHub API 直连可用

## 0. 取证边界声明（结论来源标注规则）

- 本阶段**未打开**任何历史审计报告，**未做** rc2 逐行 diff，**未读**验收 checklist、未读工作区 memory 与 `.version-history`。审计目录可见文件仅：`SPEC-v0.2.18-rc3.md`、`SPEC-v0.2.18-rc2.md`、`cli-autoupdate-acceptance-checklist-candidate.md`、`LICENSE`。
- 每条结论均标注来源：
  - **【实测】**= 本轮对本机/远端执行命令取得的原始输出（原始输出见 §5）。
  - **【推断】**= 基于多条实测事实的推理，未直接观测目标行为本身。
  - **【条款核对】**= 仅 spec 文本内部一致性的比对，不含外部实测。
- 凡断言性措辞（"实测/已核实"）仅用于【实测】项；【推断】项不复用该措辞。

## 1. 结论摘要

| 级别 | 数量 | 一句话 |
| --- | --- | --- |
| P0 | 1 | §10.5 npm 全局卸载的目标包名与实机不符（`opencode` vs `opencode-ai`），且"退出码==0 即置 `uninstalled=true`"在本机实测为 no-op 成功 → 假成功且不可回退 |
| P1 | 3 | ① `integrityNote:"single-source"` 无承载字段（数据流断裂）；② `already-current` 判据依赖 mise 侧 SHOULD 级 sha256、缺失退化未定义；③ npm 可执行定位未定义且 spec 给出的第一选项实机不存在 |
| P2 | 14 | 见 §3（含 1 条实测可证伪的表述泛化、1 条 §14 事实标注与证据不符、若干修订叙述/格式残留） |

spec 的机器事实层（CLI 版本、mise 常量路径、时间序列化契约、陈锁异常分型、GitHub digest 声明、`mise ls-remote --json` / `mise upgrade @latest` 语法）经本轮实测**与 spec 声明一致**，详见 §4。

## 2. P0 发现

### P0-1 §10.5 卸载目标包名错误 + 卸载成功判据失效 → 静默假成功且状态不可回退

- **条款**：§10.5"执行 `npm uninstall -g opencode`，**MUST 检查退出码**：仅 npm 退出码==0 才置 `uninstalled=true`"；§15 单元断言"npm 卸载失败不置 true（npm 退出码!=0 → 保持 uninstalled=false）"；§5.9"`uninstalled==true` 后**完全冻结**"、"一旦 true 不回退"。
- **实测事实**：
  1. 实机全局已装包名为 **`opencode-ai@1.18.31`**（`npm ls -g --depth=0 --prefix E:\Users\WIN_11\AppData\Roaming\npm` 输出，唯一相关包）。
  2. 该前缀下**不存在** `node_modules\opencode`；存在的 `opencode`/`opencode.cmd`/`opencode.ps1` 是 `opencode-ai` 包提供的 bin shim（bin 名 ≠ 包名）。
  3. 对**不存在**的包名执行卸载：`npm uninstall -g opencode --prefix <空临时前缀>` → 输出 `up to date in 687ms`，**exit=0**，无任何改动。
- **结论链**（②③为【实测】，组合结论为【推断】）：按 spec 现值执行，卸载步骤不会移除 `opencode-ai`（及其 shim）→ 退出码仍为 0 → 依 MUST 置 `uninstalled=true` → 因"一旦 true 不回退"永久定格。即：**npm 全局 fallback 实际仍在，而机器事实记为"已卸载"**；且 §15 打算用来兜底的"退出码!=0"断言无法检出该情形（退出码为 0）。
- **建议**：① 目标名改为 `opencode-ai`（或按 `npm ls -g --json` 解析出提供 `opencode` bin 的包名，避免硬编码再失效）；② 把"卸载成功"判据从"退出码==0"升级为结果断言"退出码==0 **且** prefix 下 `opencode`/`opencode.cmd`/`opencode.ps1` 与 `node_modules\opencode-ai` 均消失"（与 §5.8"验收以结果断言为准"同源）；③ §15 断言同步改为结果断言，保留退出码断言作为辅助。

## 3. P1 发现

### P1-1 §5.2/§5.5 `integrityNote:"single-source"` 无承载字段（跨模块数据流断裂）

- **条款**：§5.2 步骤 4 允许偏离"直连不通 → 仅用反代"，并要求"`integrityNote:single-source`，**须在 sync.json.entries 记录**"；§5.5/§5.9 将 `single-source` 列为 `entries[].integrityNote` 枚举值。
- **条款核对**：§5.9 中 `remote.json` 字段集 = channel/latest/sourceUrl/directUrl/assetName/prerelease/assetDigest/expectedSha256/checksumAssetUrl/fallbackUsed/error；`upgrade.json` 字段集 = fromVersion/target/exitCode/ok/sha256/error。**二者均无任何字段可承载"本轮下载走了单源降级"这一事实**。
- **结论**（【条款核对】+【推断】）：该偏离发生在 upgrade 段（下载期），消费方是 sync 段；sync 既不能重打 API（§1 原则2 数据固化）、也不能读 `fetch_run.log`（§1 原则10 机器事实/叙事分层、§9 铁律2 agent 不读 json 的反向约束），故 sync 无从得知是否应写 `single-source` → 该 MUST 不可实现，或只能由 agent 手工改机器事实文件（违反 §1 原则10）。
- **建议**：在 `upgrade.json`（或 `remote.json`）增设显式承载字段（如 `downloadMode: dual|single-proxy`），或把该标注的落点改为 upgrade 段 stdout 标记 + `fetch_run.log`，并同步修改 §5.5/§5.9/§15。

### P1-2 §5.5 `already-current` 判据依赖 mise 侧 SHOULD 级 sha256，缺失时退化行为未定义

- **条款**：§5.5"若 D 盘目标 exe 存在且 sync 复算其 sha256 == `sourceSha256`"→ `SYNC_SKIP|already-current`（该条同时以 MUST 措辞强制，且明确其目的是"防稳态轮逐轮空翻新 copy 与 `SYNC_TARGET_LOCKED` 反复归零 §10.5 计数"）；§5.9 `sourceSha256` 对 **opencode 必填、mise 仅 SHOULD**；§5.4 允许 mise 侧 sha256 缺失时跳过完整性②（`integrityNote=sha256-missing-skip`）。
- **实测事实**：当前 claude/codex 的 D 盘入口与 mise staging **字节同一**（size 相等、SHA256 相等：claude `19654006…20EF0`、codex `BE96B992…DFDE`），即该判据的输入在真实环境下是可得的。
- **结论**（【条款核对】+【实测】）：spec 一方面把 `already-current` 定为 MUST 级机制，另一方面其唯一输入在 mise 侧只被要求为 SHOULD；两处未定义衔接——若实现遵从 SHOULD 不计算 mise sha256，则 `sourceSha256=null`，判据无输入，退化行为（每轮空 copy？跳过？）未定义，正好落回该条声明要避免的场景。
- **建议**：把 mise 侧 `sourceSha256` 提升为 MUST（稳态轮成本 = 一次 staging exe 读，约 300MB 级），或显式定义缺失时的退化路径（如 `size + version + mtime` 相等 → 记 `sha256-missing-skip` 并 skip）。

### P1-3 §10.5 npm 可执行定位未定义，且 spec 给出的第一选项实机不存在

- **条款**：§10.5"**调用 npm MUST NOT 依赖 PATH**…显式使用 `Get-NpmPrefix()` 定位 npm 全局位置，**调用该 prefix 下 npm 二进制**或显式传 `--prefix <Get-NpmPrefix()>`"；§2 末行同源约束"harness 固定调用…不依赖 mise shim / PATH"。
- **实测事实**：`E:\Users\WIN_11\AppData\Roaming\npm\npm.cmd` **不存在**，`npm`（无扩展）**不存在**；该 prefix 内只有各包的 bin shim（`opencode.cmd`/`lark-cli.cmd`/…）。PATH 中的 npm 位于 `D:\Program Files\nodejs\npm.ps1`，node 位于 `D:\Program Files\nodejs\node.exe`；`npm config get prefix` = `E:\Users\WIN_11\AppData\Roaming\npm`（与 Cherry 前缀一致）。
- **结论**（【实测】）：spec 给的第一条调用路径不可实现；第二条（`--prefix`）可行，但缺少一个"如何在"不依赖 PATH"前提下定位 npm 可执行"的规则（§7.1 常量清单中无 npm/node 路径，也无 `Get-NpmExePath()`）。
- **建议**：在 §7.1 补 npm 定位规则（常量返回 node/npm 绝对路径，或以 `Get-Command node` 之外的显式路径推导 `npm.cmd`），并删除"该 prefix 下 npm 二进制"的错误选项。

## 4. P2 发现

| # | 条款位置 | 问题 | 来源 |
| --- | --- | --- | --- |
| P2-1 | §5.8 SHOULD"优先 .NET `File.Replace`（同卷）" | **前提未声明**：`File.Replace` 要求目标已存在——目标缺失实测抛 `FileNotFoundException`（"Unable to find the specified file"），而 §5.8 同时说明 state 文件为"写 tmp → 回读 → 替换"，首轮（无既有 state 文件）恰好是目标缺失场景。跨卷实测抛 `IOException: 无法删除要被替换的文件`（此项 spec 已正确声明跨卷限制）。建议补"目标不存在时直接 Move/Copy"分支，或改述为"目标存在时优先 File.Replace"。 | 实测 |
| P2-2 | §5.5/§5.9 `entries[].integrityNote` 枚举 | 枚举值 `sha256-recomputed` **全文无语义定义**（仅两处枚举列举，无"何时必须写"）；同枚举中 `sha256-missing-skip`/`sha256-mismatch`/`single-source` 均有明确定义 → 实现无法判断何时写该值，验收无法断言。 | 条款核对 |
| P2-3 | §12 自检表"供应链"行 | 写作 "checksum MUST + 双 hash SHOULD"，未反映 §1 原则12/§5.2 现行三级链（**API digest 主路径 MUST** → checksum asset 条件 MUST → 双 hash SHOULD）；且 "checksum MUST" 的无条件表述与 §5.2 的"checksum asset 存在则 MUST"矛盾。 | 条款核对 |
| P2-4 | §14-6 标题与结论 | 标题为"opencode 官方 **checksum 覆盖率** → 已闭合（实测）"，证据实为"37/37 asset 带 API **digest**"。**实测该 release 无任何 checksum 类资产**（37 项资产中无 `.sha256`/`checksums.txt`，仅 `latest*.yml`/`latest.json` 更新器元数据）→ 真实覆盖率为 **0**，故 §5.2 策略 3（checksum fallback）对 opencode **恒不可达**、策略 4（双 hash）是其唯一 fallback，spec 未声明这一点。 | 实测 |
| P2-5 | §5.2 REMOTE_FAIL 落盘清单 | 硬编码 `fallbackUsed:false`。若失败发生在 `releases/latest` → `releases?per_page=10` 回退路径之后，`fallbackUsed` 事实为 true 却被写 false → 证据链失真（§5.2 回退节本身规定回退命中时 `fallbackUsed=true`）。 | 条款核对 |
| P2-6 | §5.2 asset 筛选规则 | 写法"assets 筛 `windows-x64.zip`"未钉死为精确名匹配；**实测同 release 存在同子串干扰资产** `opencode-windows-x64-baseline.zip`(60718508) 与 `opencode-windows-arm64.zip`。按子串筛选会命中 `-baseline`。（后果为 digest 不匹配 → `DOWNLOAD_FAIL`，属 fail-closed 可检出，故列 P2。）建议钉死"精确等于 `opencode-windows-x64.zip`"。 | 实测 |
| P2-7 | §15 单元⑦ 负例断言 / §6 缺口②描述 | 表述"**同一时刻的 string 形态 `-eq` 比较实测恒 False**"过度泛化。本轮实测：同形态（均 UTC `'o'`、同一时刻）字符串 `-eq` → **True**；跨形态（Local `'o'` vs UTC `'o'`）→ False；DateTime 对象跨 Kind `-eq` → False。即"恒 False"仅在**未归一化/混形态**时成立；照字面编写该负例断言会与被测事实冲突。建议限定为"未归一化（混 Kind/未 `ToUniversalTime()`）的比较不可用"。 | 实测 |
| P2-8 | §7.3 条件 7/8 说明段（"由此原条件7…（死分支）"/"**修订（条件7/8 改为互补）**"） | 属**修订叙述残留在正文**：引用了本文件中已不存在的"原条件7/原条件8"旧文本，违反页首用户指令 2/5（修订记录只允许出现在会话汇报、正文禁与正确性无关的叙述）。建议改写为纯规则陈述（现行 7/8 互补 + else 兜底）。 | 条款核对 |
| P2-9 | §5.8 末条 | "**checklist A 节**'旧 specVersion 触发 fail-closed'断言据此修正为…"——引用了尚未产出（§15：评审通过后产出）且非本文件内容的断言，属跨文档修订叙述。建议改为自洽陈述"旧 specVersion → 不作决策依据 + 本轮覆盖"。 | 条款核对 |
| P2-10 | §7.1 跨盘跨用户成因说明 | 句末"**非文档拼接错误——后续审计者复核时请勿误判**"属面向审计者的防御性叙述（页首指令 5 禁止防御性描述）。事实部分可保留，建议删除该句。 | 条款核对 |
| P2-11 | §13-4 checklist 末二项 | "含 `.git` 段的路径走手动删除（**R43 工具保护**，禁 rm/mv 规避）"——`R43` 在全文无任何定义/出处，验收无法机械化。 | 条款核对 |
| P2-12 | §8 引言 exitCode `10` | 定义"10=dry-run 有动作"，但 §8.1 全表无任何行产出 10，且"哪些脚本支持 dry-run、dry-run 是否落盘 state、标记是否相同"全文未定义（仅 §8"dry-run 定位"两句）→ 该 exitCode 与验收条目悬空。建议补 dry-run 语义段或删除该码。 | 条款核对 |
| P2-13 | §8.1 sync `SYNC_SKIP|` 行 | exitCode 列写作 "0/11"（同一标记两值未定）。同表注又规定"sync 脚本级退出码一律由末步 `RUN_STATUS` 决定"，则该列应单值化或明确标注为"语义码"。机械断言需选定值。 | 条款核对 |
| P2-14 | §7.1 目录扫描规则 + §5.9/§7.2/§16 表格形态 | ①**实测** `installs\claude\2.1.273` 为 **Junction**（ReparsePoint → `http-tarballs\<hash>`），而 `installs\codex\0.154.0` 为普通目录；同层另有 9 字节普通文件 `2`/`2.1`/`latest` 及 `.mise.backend.toml`。§7.1 仅规定"取最高 semver 版本目录"，未规定 ReparsePoint 与非版本条目的过滤规则 → 若实现按属性排除重解析点，claude 会被误判 `LOCAL_EMPTY` → 触发不必要 REPAIR。②§5.9 用 `<br />` 作首列"续行"占位、§7.2 与 §16 表头存在多余空列（`| <br /> |`），非标准 md 表格，部分渲染/解析器下错位（页首指令 6 要求首选标准大纲序号格式）。 | 实测 + 条款核对 |

## 5. 已核实为**正确**的关键声明（实测，逐条对应 spec 声明）

1. **CLI 入口与版本**：`D:\AI\Programs\CLI\{claude,codex,opencode}` 三入口 `--version` 实测 = `2.1.273 (Claude Code)` / `codex-cli 0.154.0` / `1.18.31`，与 §13-3、§5.1/§5.4 示例一致。
2. **大小写**：实机目录为 `Codex`（大写 C），小写路径同样可访问（Windows 大小写不敏感）——§4"大小写约定"段成立。
3. **LICENSE**：仓库根 `LICENSE` 首两行 = `GNU AFFERO GENERAL PUBLIC LICENSE` / `Version 3, 19 November 2007`——§0"AGPL-3.0"成立。
4. **mise 常量（§7.1）逐条存在**：`mise.exe=C:\Users\JasonPC\.cherrystudio\bin\mise.exe` ✓；`installs=E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs` ✓；npm prefix `E:\Users\WIN_11\AppData\Roaming\npm` ✓；ExeRelPath `claude\<ver>\claude.exe` ✓、`codex\<ver>\bin\codex.exe` ✓。
5. **`MISE_*` 不在普通 shell env**：`Get-ChildItem Env:` 中 `MISE*` 计数 = **0**——§7.1"常量返回而非运行时推导"前提成立。
6. **`mise ls-remote <tool> --json` 语法成立**：实测 `claude` → `[{"version":"2.1.274"}]`（该后端 version_list 即"最新"端点，单元素）；`codex` → 完整历史数组。两工具 JSON **均不含 `prerelease` 字段** → §7.3"mise 通道无 prerelease 布尔字段、保留字符串启发式"**对在册两工具成立**（注：mise `ls-remote --help` 显示其他后端（如 `github:`）的 `--json` 可含 `prerelease`，故该结论宜限定为"claude/codex 通道"）。
7. **`mise upgrade <tool>@latest` 语法被接受**（§7.2 标注为"实现期 MUST 实测"的开放项）：`mise upgrade claude@latest --dry-run` → `Would uninstall claude@2.1.273` / `Would install claude@2.1.274`，exit=0；`mise upgrade claude --dry-run` 同结果 → `@latest` 解析出的目标 = 上游 latest，与 `remote.latest` 口径一致。
8. **REPAIR 语法 `mise install <tool>@<ver> --force` 成立**：`mise install --help` 含 `-f, --force  Force reinstall even if already installed`；实测 `mise install claude@2.1.273 --force --dry-run` exit=0。
9. **时间序列化契约（§5/§5.9/§6）全部成立**（PS 7.6.4）：`DateTime`（Kind=Local）`ToUniversalTime().ToString('o')` = `2026-09-17T11:51:57.4969303Z`（恒 7 位小数 + `Z`）；整秒 → `2026-09-17T03:21:07.0000000Z`；`DateTimeOffset.ToString('o')` = `…+08:00`（**无 `Z`**）；`RoundtripKind` 解析回 `Kind=Utc` 且 Ticks 相等；`Process.StartTime` 类型为 `DateTime`，两次读取 Ticks 稳定。
10. **陈锁伪代码异常分型（§6）成立**：`Get-Process -Id 99999999` → `Microsoft.PowerShell.Commands.ProcessCommandException`（唯一"已证明死亡"分型）；`-Id $null` → `ParameterBindingValidationException`；`-Id 'abc'` → `ParameterBindingException`（均落 `$lookupUnknown` → `LOCKED`，与伪代码分支一致）。
11. **GitHub 侧声明（§5.2/§14-1/§14-6）成立**：`releases/latest` → tag=`v1.18.31`、`prerelease=False`、`assets=37`、**37/37 带 `sha256:` digest**；`opencode-windows-x64.zip` digest = `sha256:0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006`，与 spec 声明**逐字符相符**；回退端点 `releases?per_page=10` 可用（10 项全 stable）。zip 大小 60718498 > 1MB ✓。
12. **§13-2 seed/already-current 前提成立**：claude/codex 的 D 盘入口与 mise staging **字节同一**（size 与 SHA256 均相等）；codex D 盘字节数 = 298169136，与 §5.1/§5.4 示例值完全一致。
13. **"三款 CLI exe 均远 >50MB"（§5.1）**：231776416 / 298169136 / 179998248 字节 ✓。
14. **路径无空格（§4 Canonical Path）**：所列 6 条路径均无空格 ✓。
15. **工作区现状与 spec 假设一致**：根下**无** `state/`、无 `staging/`，`TEMP/` 存在 ✓（对应 §4/§10.4/§13-5"待产出/待清空"状态）；`.version-history/` 存在 ✓（符合页首指令 3）。
16. **反代风险的实测数据点（支持 §14-2 已声明风险，不构成新缺陷）**：`https://gh.jasonzeng.dev/` 根路径 GET 与 asset Range GET 均失败（`HttpRequestException` / "The SSL connection could not be established"），DNS 正常解析（Cloudflare A/AAAA 记录）。即"反代为主链路"的可用性在本机当前时点不成立 → 直连回退（§5.2）实际会成为常态路径。

## 6. 未核实 / 受限项（明确声明）

1. **反代 URL 拼接形态**（`https://gh.jasonzeng.dev/https://github.com/...`）是否被反代接受：因 TLS 握手失败未能核实（非"已证伪"）。
2. **D 盘 `opencode.exe` 与 GitHub zip 内 exe 的同源性**：`staging/opencode/` 不存在，无法比对（`already-current` 首轮判定结果未核实）。
3. **`mise upgrade` 非 dry-run 的真实实装结果**（§7.2 要求断言 `@latest` 实装版本 == `remote.latest`）：本轮仅验证了 dry-run 计划输出，未执行实际安装（避免改动环境）。
4. **`npm uninstall -g opencode` 在真实前缀下的输出**：仅在与真实环境隔离的空临时前缀中实测（exit=0 / no-op）；真实前缀未执行。P0-1 的"不会移除 opencode-ai"结论部分依赖该实测 + 包名语义（【推断】部分已在条目内标注）。
5. **反代 TLS 失败的归因**：单一时点、单一方法（HEAD + Range GET），不排除本机 TLS 策略/网络策略因素；不构成"反代永久不可用"的结论。

## 7. 原始证据（关键命令与输出摘录）

```
[1] 三入口版本
[claude] exists size=231776416 ver=2.1.273 (Claude Code)
[codex]  exists size=298169136 ver=codex-cli 0.154.0
[opencode] exists size=179998248 ver=1.18.31
D:\AI\Programs\CLI 列表 = claude | Codex | opencode

[2] mise 常量 / 环境
mise.exe: True   installs dir: True   npm prefix: True
claude exe: True  codex exe(bin): True
installs tree = claude{2.1.273,.mise.backend.toml,2,2.1,latest} | codex{0.154.0,.mise.backend.toml,0,0.154,latest} | fd{...} | gh{2.100.0,...} | rtk{...}
MISE* env count in normal shell = 0

[3] mise installs 条目类型
claude/2.1.273 size=1 isDir=True  link=Junction
claude/2 size=9 isDir=False | claude/2.1 size=9 isDir=False | claude/latest size=9 isDir=False
codex/0.154.0  size=1 isDir=True  link=(none)
codex/0 size=9 isDir=False | codex/0.154 size=9 isDir=False | codex/latest size=9 isDir=False

[4] gh / npm 链路
gh NOT in PATH（mise installs 内 gh 2.100.0 存在；`gh auth status` = Logged in to github.com account shadownaked (GITHUB_TOKEN)）
npm prefix 顶层 = node_modules | agentmail-mcp* | lark-cli* | lark-mcp* | myagentmail-mcp* | opencode | opencode.cmd | opencode.ps1 | pear*
prefix 内 npm.cmd: False | prefix 内 npm(无扩展): False
PATH 中 npm -> D:\Program Files\nodejs\npm.ps1 ; node -> D:\Program Files\nodejs\node.exe
node_modules = @agentmemory,@anthropic-ai,@larksuite,@larksuiteoapi,@openai,agentmail-mcp,myagentmail-mcp,opencode-ai,pear
npm ls -g --depth=0 --prefix E:\Users\WIN_11\AppData\Roaming\npm
  +-- opencode-ai@1.18.31   （其余 5 个无关包）
npm uninstall -g opencode --prefix <空临时前缀> → "up to date in 687ms"  exit=0（临时前缀仍无 node_modules）

[5] GitHub API（opencode）
tag=v1.18.31 prerelease=False draft=False assets=37
zip.digest=sha256:0ecd7ffc7f26390ce7799e7bcd409e4f11c410144308a6a5b0fcdce63d871006 zip.size=60718498
assets with digest=37 null digest=0    digest algos=sha256    checksum-like assets=（空）
干扰资产：opencode-windows-x64-baseline.zip | 60718508 | sha256:7c4fc9be...

[6] PowerShell 语义
PSVersion=7.6.4 ; DateTime Kind=Local 'o'=2026-09-17T19:51:57.4969303+08:00 ; ToUniversalTime 'o'=2026-09-17T11:51:57.4969303Z
整秒 'o'=2026-09-17T03:21:07.0000000Z ; DateTimeOffset 'o'=2026-09-17T19:51:57.5112590+08:00（无 Z）
DateTime 对象跨 Kind -eq: False | 同形态字符串 -eq: True | 跨形态字符串 -eq: False | Ticks 跨 Kind: False | ToUniversalTime Ticks: True
Get-Process 不存在 PID → ProcessCommandException ; $null PID → ParameterBindingValidationException ; 'abc' PID → ParameterBindingException
Parse(RoundtripKind) → Kind=Utc, ticksEq=True

[7] File.Replace
目标缺失 → System.IO.FileNotFoundException（Unable to find the specified file）
目标存在 → OK（content=new, backup=old）
跨卷（C: → D:）→ System.IO.IOException: 无法删除要被替换的文件
Move-Item -Force 覆盖 → OK（content=new）；跨卷 Move-Item → OK

[8] mise 命令
mise --version = 2026.7.14 windows-x64 (2026-07-26)
ls-remote --help 含 -J, --json（"includes version metadata like created_at timestamps when available"）
ls-remote claude --json → [{"version":"2.1.274"}] ；ls-remote codex --json → 含 created_at/release_url，无 prerelease 键
upgrade claude@latest --dry-run → "Would uninstall claude@2.1.273 / Would install claude@2.1.274" exit=0
install claude@2.1.273 --force --dry-run → "already installed" exit=0
mise 全局配置 = config\config.toml：claude={version="latest",...} / codex="latest" / fd/gh/rtk（尚无 upgrade.auto_prune=false，§13-6 待办）

[9] 字节同一性（§13-2 前提）
claude stagingSize=231776416 dSize=231776416 shaEqual=True （19654006672B6DA7C945115EEA99CA10051796016DF563A65B3F0C7D72720EF0）
codex  stagingSize=298169136 dSize=298169136 shaEqual=True （BE96B992178B1E467C225800DA0D65F2C86D5EBA1EF0B14632F65DB381CBDFDE）
staging/opencode present: False ；opencode D sha=0242A0DC705AF67C90882B456A36B619883C1C786AAD8FE071A1BC64E5D1D440

[10] 反代
GET https://gh.jasonzeng.dev/ → HttpRequestException: The SSL connection could not be established
GET <proxy>/https://github.com/anomalyco/opencode/releases/download/v1.18.31/opencode-windows-x64.zip (Range) → 同上
DNS: gh.jasonzeng.dev A 172.67.221.90 / AAAA 2606:4700:3031::6815:4b6c
```

## 8. 阶段一自评（不含版本收敛判断）

- 覆盖方式：全文 900 行逐节阅读 + 对 §5.x/§6/§7.x/§8/§8.1/§10.5/§12/§13/§14/§15 中可外部核验的声明逐条实测；六批共 12 条命令，原始输出已存档于本文件 §7。
- 本阶段**未**作任何"是否可以冻结/进入实现"的判断（该判断不在审计agent职权内）。
- 阶段二将另出最终版审计报告；最终版会补充"与历史轮次/其他交付物交叉核对"的结果，并在条目级别标明哪些结论来自本次盲审、哪些来自交叉核对。
