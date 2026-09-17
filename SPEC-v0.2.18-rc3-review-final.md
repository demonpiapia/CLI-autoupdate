# SPEC-v0.2.18-rc3 审计报告 · 终版（双审计合并裁断）

- **被审计文件**：`d:\AI\Workspace\automatic\CLI-autoupdate\SPEC-v0.2.18-rc3.md`（900 行 / 140078 字符）
- **本报告输入**：
  1. `SPEC-v0.2.18-rc3-review-candidate.md`（CodeBuddy 阶段一独立盲审，物理文件已落盘）
  2. `SPEC-v0.2.18-rc3-codebuddy-review.md`（CodeBuddy 最终版审计，含 rc2→rc3 逐 hunk 核对）
  3. `.supervisor/spec-v0.2.18-rc3-anthropic-review.md`（anthropic 独立审计 + B1 修复设计方案）
- **生成时点**：2026-09-17
- **环境（实测）**：Windows / PowerShell 7.6.4 / mise 2026.7.14 / gh 2.100.0（`installs\gh\2.100.0\bin\gh.exe`）/ npm（`D:\Program Files\nodejs\npm.cmd`）

## 0. 方法与来源标注

- **来源标注**：`【实测】`= 本机/远端命令原始输出（见 §9）；`【核对】`= 文本内部或跨文档比对；`【推断】`= 由实测事实推理、未直接观测目标行为。断言性措辞仅用于【实测】。
- **裁断规则**：采纳需证据；不采纳必须有**真实反证**（可复现的实测或可逐字核对的反例文本），本报告 §8 汇总全部不采纳项与对应反证。
- **过程合规性观察（事实陈述）**：anthropic 报告自述其环境无法写入物理文件（其 §0 第 7 行），故其 candidate 仅以正文形式给出、**未落盘**；CodeBuddy 侧两份文件（candidate + final）均为物理文件。若按 spec 页首指令 4 严格执行"缺 candidate 物理文件禁止交付"，该报告的交付形式不完整，本报告以其正文内容继续裁断。
- **隔离原则**：涉及卸载/配置写入的操作一律在隔离沙箱或 `--dry-run` 下进行，未在真实环境执行变更。

## 1. 结论摘要

| 来源 | 条目 | 采纳 | 部分采纳 | 不采纳 |
| --- | --- | --- | --- | --- |
| anthropic（A1–A3、B1–B12，共 15 项） | 15 | 4（B1、B2、B6、B10） | 7（A1、A2、B3、B4、B5、B7、B11） | 4（A3、B8、B9、B12） |
| CodeBuddy（P0-1、P1-1~3、P2-1~14，共 18 项） | 18 | 18 项全部维持（无一条被本轮新增证据推翻） | — | — |
| **合并后最终问题清单** | **22 项**（见 §2） | 高优先 7 项（F1–F7） | 其余 15 项 P2 | — |

**双方互补关系**：anthropic 发现了我方未覆盖的 **3 项结构性缺陷**（mise 回退语义失效 B1、API 元数据信道未声明 B2、通道校验强度不对称 B5）与 **2 项工程缺口**（保留策略无实现模块 B6、磁盘阈值与制品体积脱钩 B4）；我方发现 anthropic 未覆盖的 **1 项 P0（npm 卸载包名与假成功）** 及 **5 项 P1/P2**（`single-source` 承载、`already-current` 输入缺失、npm 定位、checksum 资产实测为 0、rc3 新引入的 File.Replace 前提）。**无相互冲突的结论**。

**双方一致项**：修订叙事散落正文（A1 与我方 P2-8/P2-9）、§14 登记表不完备（B3 与我方 P0-1 均显示有未收录缺陷）、§7.1 扫描算法与回退/pin 语义耦合（B1 与我方 P2-14① 共享根因）。

## 2. 合并后最终问题清单

### 2.1 高优先（建议下一轮修订闭合）

| ID | 定位 | 提出方 | 级别 | 摘要 | 最小改法 |
| --- | --- | --- | --- | --- | --- |
| **F1** | §10.5（+§5.9/§15） | CodeBuddy | **P0** | `npm uninstall -g opencode` 目标包名与实机不符（实机为 `opencode-ai`）；"退出码==0 即置 `uninstalled=true`"在实测中为 no-op 成功 → 假成功且"一旦 true 不回退" | 包名改 `opencode-ai`（或运行时解析）；成功判据改为结果断言（shim + `node_modules\opencode-ai` 均消失） |
| **F2** | §5.2/§7.1/§5.10 | anthropic B2 + CodeBuddy 补充 | **P1** | GitHub **API 元数据**是否经反代全文未声明（实测 spec 中 `api.github.com` 出现 0 次）→ digest 主路径信任前提悬空；§5.10"防反代投毒"表述与 digest 主路径时代已脱节 | 显式声明"REST API 元数据 MUST 直连 api.github.com，不经反代"，并让 §5.10 防护范围与现行 dual-hash 触发条件对齐 |
| **F3** | §10.1/§5.7（+§7.1/§10.3） | anthropic B1 + CodeBuddy 补充与修正 | **P1** | mise 通道"回退"指引对流水线无效：§10.1 的 `mise use` 不改变 probe-local 的"最高版本"判据（实测 help：其作用为写 config + 安装缺失版本）；§5.7"修复性晋升（拉回 pinVersion）"常规场景不可达；§10.1 亦未指定 `--global`（实测默认写 cwd 的 `mise.toml`） | ① 明确 pin 的"保持/拒绝晋升"语义并声明"拉回"的前置条件（staging 最高版本 == pinVersion）；② 改写 §10.1 回退流程为"补装目标版本（`mise install <tool>@<ver>`）+ D 盘 `.previous` 回退 + pin"，禁用 `mise use` 作为回退指引；③ pin 目标须在保留窗口内且豁免清理 |
| **F4** | §5.2→§5.5/§5.9 | CodeBuddy | **P1** | `integrityNote:"single-source"` 要求写进 `sync.json.entries`，但 `remote.json`/`upgrade.json` 字段集中**无任何承载该下载路径事实的字段** → 该 MUST 不可实现（sync 不得重打 API、不得读日志） | 增设承载字段（如 `downloadMode`），或把标注落点改为 upgrade 段标记 + `fetch_run.log` |
| **F5** | §5.5（+§5.9/§5.4） | CodeBuddy | **P1** | `already-current` 机制为 MUST 却依赖 mise 侧 **SHOULD** 级 sha256；缺失时退化行为未定义（落回该条声明要避免的"逐轮空 copy"场景） | mise 侧 `sourceSha256` 升 MUST，或定义缺失退化规则（`size+version` 相等 → `sha256-missing-skip` + skip） |
| **F6** | §10.5（+§7.1） | CodeBuddy | **P1** | "调用该 prefix 下 npm 二进制"为不可实现指令（实测 prefix 内无 `npm.cmd`/`npm`）；在不依赖 PATH 前提下定位 npm 的规则全文缺失 | §7.1 增补 npm/node 定位常量或规则；删除错误选项 |
| **F7** | §7.2/§10.1/§10.2/§10.4 | anthropic B6 | **P2** | "保留最近 2 版/2 stable"**无任何模块承担清理职责**（§7.1/§7.2 均无对应条目），且 mise 侧另有 `upgrade.auto_prune=false` 主动关闭自带清理 → 声明与实现路径脱钩 | 在 §7.2 为 upgrade 脚本追加 MUST 清理职责 + 清理时机；同时加"pin 版本豁免清理"前置（与 F3 联动） |

### 2.2 迭代修（P2，逐条最小改法）

| ID | 定位 | 提出方 | 摘要 |
| --- | --- | --- | --- |
| F8 | §5.8 | CodeBuddy | **rc3 本轮新引入**：`File.Replace` SHOULD 未声明"目标必须已存在"——实测目标缺失抛 `FileNotFoundException`、跨卷抛 `IOException: 无法删除要被替换的文件`；首轮无既有 state 文件恰为该场景 |
| F9 | §14-6 | CodeBuddy | 标题"opencode 官方 **checksum 覆盖率**"与实测不符：37/37 资产带 API digest，但 **checksum 类资产数 = 0** → §5.2 策略 3 对 opencode 恒不可达、策略 4 为唯一 fallback，未声明 |
| F10 | §12 + §7.3 | CodeBuddy | rc3 语义化清扫两处漏项：§12"供应链"行仍写旧三级链之外的口径；§7.3 条件 7/8 段仍保留"原条件7…/修订（…）"（同节条件 2 段已清扫） |
| F11 | §5.10 | anthropic B5（部分）+ CodeBuddy 反证 | 通道校验强度不对称未在威胁模型声明（采纳）；但"mise 自身校验无任何支撑"不成立——实测本机 mise 全局配置中 claude 的工具定义显式含 `checksum_expr` + `checksum_url`（Google 托管 `manifest.json`）；codex 侧未声明校验字段（未核实） |
| F12 | §8 DISK_FULL 行 | anthropic B4（部分）+ CodeBuddy 实测 | 阈值未绑定卷、与制品体积无关联（采纳）；"3–4 倍瞬时空间"低估了 junction 复用、高估了 claude 实际占用（实测 claude 安装目录为 Junction → 单份 221MB；codex = 缓存 219.6MB + 解压 284.4MB）。实测卷余量：C 26.4GB / D 34.7GB / **E 2.14GB**（mise staging 所在卷）→ 阈值应绑定目标卷并与制品体积建立关系 |
| F13 | §7.1 + §5.9/§7.2/§16 | CodeBuddy | §7.1"取最高 semver 版本目录"未规定 Junction（实测 `installs\claude\<ver>` 为 Junction）与非版本条目（9 字节 `2`/`2.1`/`latest`、`.mise.backend.toml`）的过滤规则；§7.2/§16 表头含多余空列、§5.9 以 `<br />` 续行占位 |
| F14 | §5 + §7.1 | CodeBuddy | 环境事实声明待校准：`gh` **不在 PATH**（实测）而 §7.1 列出 `gh auth token` 读取、未定义其定位方式；§5"本环境 `gh` 已认证（demonpiapia 账户）"与实测不符（`gh auth status` = 账户 **shadownaked**；demonpiapia 是仓库 owner，二者不同） |
| F15 | §5.5/§5.9 | CodeBuddy | `integrityNote` 枚举值 `sha256-recomputed` 全文无语义定义（何时必须写） |
| F16 | §5.2 | CodeBuddy | REMOTE_FAIL 落盘清单硬编码 `fallbackUsed:false`，与"失败发生在回退路径之后"的事实冲突 |
| F17 | §5.2 | CodeBuddy | asset 筛选未钉死精确名匹配；实测同 release 存在 `opencode-windows-x64-baseline.zip` 等子串干扰资产（后果 fail-closed 可检出，故 P2） |
| F18 | §15/§6 | CodeBuddy | 负例断言"同一时刻 string 形态 `-eq` 恒 False"过度泛化：实测同形态字符串 `-eq` = True，跨形态/跨 Kind = False |
| F19 | §8/§8.1 | CodeBuddy | `dry-run` 语义未定义（哪些脚本支持、是否落盘、标记差异），但 exitCode `10` 已被占用；`SYNC_SKIP|` 行 exitCode 写作 "0/11" 二值未定 |
| F20 | §13-4/§5.8 | CodeBuddy | 未定义外部引用与跨文档引用：`R43 工具保护` 全文无定义；§5.8 引用"checklist A 节断言"（该断言属 checklist 候选稿，且清单交付物尚未产出） |
| F21 | §1 原则3 + §8 | anthropic B7（轻量采纳） | 建议在 §1 原则3 显式补一句"唯一例外：`ALL_REMOTE_FAIL` 由 agent 聚合三 CLI 标记"（该例外已在 §8/§9 声明，此处仅为可读性对齐） |
| F22 | §0/§13 | anthropic B10（采纳） | 表述精确化：实测仓库为 **public**（`demonpiapia/CLI-autoupdate`，license AGPL-3.0）→ 建议改为"不提供面向外部用户的产品化发行/安装包/支持承诺，源码托管公开但仅供个人使用" |
| F23 | §5.10 | CodeBuddy（实测升级） | attestation 命令名经本机 gh 2.100.0 实测**存在**（见 §8 反证）→ 可把"未在本机实测"升级为"已本机实测命令存在"（建议附命令输出与版本号） |
| F24 | §7.2/§7.3 | CodeBuddy | 可回填的实测结论：`mise upgrade <tool>@latest` 已被接受（dry-run 目标 = 上游 latest）；`mise ls-remote claude/codex --json` 不含 `prerelease` 键 → §7.3 mise 通道启发式宜限定为"claude/codex 通道" |
| F25 | 交付物（非正文） | CodeBuddy | `.version-history/spec-version-history.md` 末条仍为 v0.2.18-rc2（无 rc3 条目）；`cli-autoupdate-acceptance-checklist-candidate.md` 仍停留 0.2.17 且含 P 级 emoji |

## 3. anthropic 意见逐条处置（含反证）

| ID | 主题（anthropic 原文要点） | 判定 | 依据 / 反证 |
| --- | --- | --- | --- |
| A1 | §7.3/§6/§14 存在"修订记录"式叙事，违反页首指令 2 | **部分采纳** | 采纳：§7.3 条件 7/8 段（"原条件7…死分支"/"修订（条件7/8 改为互补）"）与 §5.8"checklist A 节…修正为"确认违反指令 2/5（与我方 P2-8/P2-9 一致）。**不采纳**：① §14 整体迁移/重构（**反证**：rc3 轮已有裁决——§14-1/6/10/11/12 是正文活锚，迁移会断引用；实测这 5 个锚在 §5.2/§6/§7.3/§9/§14-13 均被引用）；② "加'不构成完备性保证'声明"（**反证**：§14 开头已声明"真未知风险…不伪声明 closed"，再加免责声明属页首指令 5 禁止的防御性重复描述）；③ §6 该段属"说明伪代码须闭合的两个失败模式"，落在指令 5 白名单"影响表述准确性"边界内 → 改写建议为**可选、低优先** |
| A2 | §5.9 等"未采用真正的 markdown 表格…逐行重复标签" | **部分采纳（前提驳回）** | **反证**：§5.9 **就是**标准 markdown 表格——表头逐字为 `\| 文件 \| 字段 \| 类型 \| 必填 \| 枚举/说明 \|` + 分隔行，数据行仅出现数据（文件名为重复时用 `<br />` 续行）；§8/§8.1/§12/§16 同为标准表格。"逐行重复标签""比标准表格更臃肿"与原文不符，且其"改用真正 md 表格"的建议对这些表**不适用**。采纳的残余 = 我方 P2-14②：§7.2/§16 表头多余空列、`<br />` 续行占位带来的可读性/体积成本 |
| A3 | 页首大段"用户指令"是否宜置于 SPEC 正文 | **不采纳** | **反证**：该块为用户本人写入的流程治理条款，且是本次审计的直接依据（页首指令 4 即审计顺序约定）；删除会破坏审计可追溯性。anthropic 自述"非违规、属观察项"→ 不构成可执行修订项，属用户领域 |
| B1 | mise 回退机制与 probe-local 扫描矛盾、pin 对 mise 通道实质失效（Critical） | **采纳（问题成立）；子论断 3 处需修正** | **采纳依据**【核对+实测】：§7.1/§7.2 probe-local/verify 均"取最高 semver 版本目录"；§10.1 回退 `mise use`；`mise ls`（实测）= `claude 2.1.273 (symlink) … latest`，激活版本由 config 解析，而流水线只读目录与 D 盘 exe → `mise use` 不可能改变 `local.version`/`verified.version`。**修正 1**【实测反证】："`mise use` 不产生任何可观察效果"不成立——`mise use --help` 原文"Installs a tool and adds the version to mise.toml. This will install the tool version if it is not already installed."（对 mise shim 路径与 installs 目录均有效果，只是不能降低"最高版本"判据）。**修正 2**：pin 并非"实质失效"——§10.3 的既定用途是**保持**回退版本（`verified.version != pinVersion` → `SYNC_SKIP|pinned-mismatch` → D 盘不动，该路径可达）；失效的仅是 §5.7 的"修复性晋升（拉回）"在常规场景不可达（我方候选报告已独立记录同点）。**修正 3**【实测反证】："唯一方式是手动物理删除文件夹"不成立——`mise uninstall --help` 原文"Removes installed tool versions…"，存在官方命令 `mise uninstall <tool>@<ver>`（附 `-n/--dry-run`）；且"与保留最近 2 版冲突"在当前版本不成立：**保留策略本身尚无实现模块（见 B6）**（实测当前 claude/codex 各仅 1 个版本目录）。**我方补充缺陷（新增）**：§10.1 未指定 `--global`——`mise use --help` 原文"By default, this will use a `mise.toml` file in the current directory… Use the `--global` flag to use the global config file instead."，而本环境实际生效配置为全局 `…\mise\config\config.toml`（实测 `mise ls` 来源列）→ 按 §10.1 字面执行会写错配置文件。**方案 B 评估**：方向可行（sync 现场定位 pin-target），但需补两点——① pin 路径绕开 `verified.json` 后，§5.4 完整性②的"双点比对"降为单点现场复算（D 盘旧值恰为被覆盖对象，不构成可信基准），须重新定义 pin 路径下的完整性判据；② 废止 `pinned-mismatch` 需连带改 §5.9 枚举、§9 模板 6、§15 断言与 §14-13 措辞 |
| B2 | GitHub API 元数据是否经反代未声明，关系 digest 信任链 | **采纳（表述需修）** | **采纳依据**【核对】：spec 全文 `api.github.com` 出现 **0 次**；反代仅出现于下载/信任前提 4 处 → 元数据信道确实未定义；"若元数据经反代，digest 主路径可被同时伪造"逻辑成立。**修正**：anthropic 称其"彻底击穿 §5.10 声称的反代投毒防线"过于宽泛——§5.10 该行原文限定为"**无 checksum asset 时**双 hash 比对（检出反代与直连不一致）"，即防护声明本身只覆盖 dual-hash 路径；真实问题是 **digest 主路径（无 secondary download）从未被纳入该威胁声明的覆盖范围**。**我方补充**：§5.10"前提信任"同时把反代列为信任项、又声明"防反代投毒"，二者需显式分层说明 |
| B3 | §14"已闭合"框架有锚定风险且经验证不完整 | **部分采纳** | 采纳"不完备"事实：本轮我方独立发现 §14 未收录的 P0-1（npm 包名）等缺陷，与 B1 共同证明 §14 非完备清单。**不采纳**：加免责声明（反证同 A1②）；建议替代动作 = 把 F1/F2/F3 等新发现补录进 §14（符合其"已知问题清单"定位） |
| B4 | DISK_FULL 固定 500MB 未按制品体积动态评估 | **部分采纳** | 采纳：阈值未绑定卷、与制品体积无关联。**反证/修正**【实测】："3–4 倍单文件体积瞬时空间"不成立——claude 安装目录为 Junction（`installs\claude\2.1.273` → `http-tarballs\9d79029c…`），物理单份 221MB；codex = 缓存 219.6MB + 解压 284.4MB ≈ 2 份。且实测卷余量 C 26.4GB / D 34.7GB / E **2.14GB**（staging 所在卷）→ 需绑定 E 盘并按制品体积给出计算依据 |
| B5 | mise 与 opencode 通道校验强度不对称，避免"更敏感工具校验更弱" | **部分采纳** | 采纳：建议在 §5.10 显式声明通道差异（我方无异议）。**反证**："mise 自身校验完整性全文没有任何实测/引用支撑"不成立——实测本机 mise 全局配置（`…\mise\config\config.toml`）中 claude 的工具定义显式含 `checksum_expr`（对 `manifest.json` 取 `sha256:` 字段）与 `checksum_url`（`https://storage.googleapis.com/claude-code-dist-…/manifest.json`）→ 存在可引用的校验链路证据；codex 侧定义为简单 `"latest"`，其校验行为**未核实**（诚实标注） |
| B6 | 版本保留策略缺少强制清理模块 | **采纳** | **依据**【核对】：§10.1/§10.2/§10.4 均声明"保留最近 2 版"，但 §7.1 共享库函数清单与 §7.2 模块职责表**无任何清理条目**；`upgrade.auto_prune=false` 进一步关闭 mise 自带清理。补充实测：当前 `mise settings` 输出无 prune 相关项，且 config.toml 未设置该键（§13-6 待办）→ mise 实际清理行为**未核实**。联动：清理模块实现时必须加入"pin 版本豁免"（否则回归性破坏 F3 的 pin-target） |
| B7 | ALL_REMOTE_FAIL 聚合由 agent 承担，与"agent 不介入计算"张力 | **部分采纳** | 采纳：在 §1 原则3 补一句显式例外（成本极低、可读性收益）。**反证（驳回"隐性例外"定性）**：§8 表该行已显式钉死"产出者=agent/SOP 聚合"与"聚合数据源 MUST 且仅为 stdout 标记"，§9 状态机图亦画出该路由边 → 属**已声明**例外，非"藏在脚注里的打折" |
| B8 | ALL_REMOTE_FAIL 下计数归零可能使卸载长期停滞 | **不采纳（记录为设计权衡）** | **反证**：① §10.5 已显式声明该归零口径（"ALL_REMOTE_FAIL…即归零，已被本条覆盖"）；② 归零方向为 fail-safe，且 10 轮窗口的设计目标是"暴露稳定期问题"（§10.5 原文），网络抖动延迟卸载与该目标一致；③ 更根本的是：该卸载步骤当前**根本不生效**（F1 包名错误 → 恒 no-op + `uninstalled=true`），效率议题优先级低于正确性议题。anthropic 自述"不算缺陷"，与本判定一致 |
| B9 | `gh release verify` / `gh release verify-asset` 命令名存疑，应为 `gh attestation verify` | **不采纳（实测证伪）** | **反证**【实测·本机 gh 2.100.0】：`gh release --help` 子命令列表含 **`verify: Verify the attestation for a release`** 与 **`verify-asset: Verify that a given asset originated from a release`**；`gh release verify --help` 返回 exit=0，输出"Verify that a GitHub Release is accompanied by a valid cryptographically signed attestation…prints metadata about all assets referenced in the attestation, including their digests"——与 spec §5.10 描述（校验 release/asset digest 与 attestation subject 一致性）**一致**。`gh attestation verify` 亦存在，但二者是不同子命令族，不存在"名存实亡"。→ 建议反向操作：把 §5.10 的"未在本机实测"升级为"已用 gh 2.100.0 实测命令存在"（F23） |
| B10 | AGPL"不面向外部发行"表述与仓库公开托管存在张力 | **采纳** | **依据**【实测】：`git remote -v` = `https://github.com/demonpiapia/CLI-autoupdate.git`；GitHub API 返回 `private=False visibility=public license=AGPL-3.0 fork=False` → "仓库公开托管"属实，表述宜精确化（F22） |
| B11 | TAKEOVER 后重新 `CreateNew` 的竞态未显式兜底 | **部分采纳（可选措辞）** | **反证（驳回"未兜底"）**：§6 争锁规则（`CreateNew` + `FileShare::None` 原子争锁）与 §8 `LOCKED|`（blocked，本轮终止）、§8.1 archive-state 行（`LOCKED|`→ 不写产物）、§9 段A 出口共同覆盖"争锁失败"路径；重建失败与首次争锁失败为同一 `CreateNew` 语义，落同一分支 → 已兜底。建议仅在 §6 补一句"TAKEOVER 后重建失败按争锁失败处理（`LOCKED|`）"（F18 同类可选措辞） |
| B12 | `action="copy"` 复用于未实际复制的失败条目，建议新增 `copy-blocked` | **不采纳** | **反证**：① 现有字段三元组已可机械区分该形态——`action="copy"` + `ok=false` + `integrityNote="sha256-mismatch"` + `reason=null`，且 §5.5/§5.9/§8.1/§15 四处已钉死；② 新增 action 值会波及 §5.9 枚举、§8.1 映射、§15 断言、§5.5"copy 类 reason MUST 为 null"规则链（净增复杂度与不一致风险）；③ §0 的"减少变量、提高可验收性"取向不支持为可读性扩枚举。可选低成本替代：在 §9 汇报模板加一行注"`action=copy` + `ok=false` 表示判定失败/复制未完成" |

**anthropic 候选盲审 10 项 → 最终定性映射**：①§7.1 扫描 vs §10.1 `mise use` → B1（**F3**，采纳）；②API 是否走反代 → B2（**F2**，采纳）；③DISK_FULL 500MB → B4（**F12**，部分采纳）；④§7.3/§6 修订叙事 → A1（**F10 部分**，采纳）；⑤§14 框架锚定 → A1/B3（部分采纳）；⑥ALL_REMOTE_FAIL 归零 → B8（不采纳）；⑦保留策略无清理模块 → B6（**F7**，采纳）；⑧`gh release verify-asset` 名存疑 → B9（**实测证伪，不采纳**）；⑨mise sha256 强度不对称 → B5（**F11**，部分采纳）；⑩AGPL 公开托管张力 → B10（**F22**，采纳）。

## 4. CodeBuddy 独立发现（维持不变）

前次报告（`SPEC-v0.2.18-rc3-codebuddy-review.md`）18 项全部维持，本轮无一条被新证据推翻；对应关系：P0-1→**F1**、P1-1→**F4**、P1-2→**F5**、P1-3→**F6**、P2-1→**F8**、P2-2→**F15**、P2-3/P2-8→**F10**、P2-4→**F9**、P2-5→**F16**、P2-6→**F17**、P2-7→**F18**、P2-9/P2-11→**F20**、P2-10→（并入 A1 的叙事清理）、P2-12/P2-13→**F19**、P2-14→**F13**。本轮新增项：F14（gh 定位/账户）、F21（原则3 例外）、F22（AGPL 表述，与 anthropic 联合）、F23（attestation 实测）、F24（可回填实测）、F25（交付物级）。

**我方前报告中两项经本轮证据强化**：
- **P1-2（F5）** 与 anthropic B1 共享根因（§7.1"取最高版本"的语义被多处复用），建议在同一轮修订中统一处理；
- **P2-7（F18）** 的"表述过度泛化"经复核保持原判（同形态字符串比较 = True，跨形态 = False）。

## 5. 已核实正确的关键声明（两轮实测合并）

1. 三入口 `--version` = claude 2.1.273 / codex 0.154.0 / opencode 1.18.31；目录实为 `Codex`（大写）且大小写等价；LICENSE = AGPL-3.0。
2. mise 常量逐条存在（mise.exe / installs / npm prefix / `claude.exe` / `codex\bin\codex.exe`）；`MISE_*` 普通 shell env 计数 = 0。
3. `mise ls-remote <tool> --json` 语法成立；claude/codex 的 JSON **均不含** `prerelease` 键 → §7.3 mise 通道启发式对其成立。
4. `mise upgrade claude@latest --dry-run` 被接受（Would uninstall 2.1.273 / Would install 2.1.274，exit=0）→ §7.2"待实测"项可结论化。
5. `mise install --force` 存在；`mise uninstall`、`mise use`（默认写 cwd、`--global` 写全局）语义经 help 文本确认。
6. 时间契约：DateTime `'o'` 恒 7 位小数 + `Z`；DateTimeOffset `'o'` 为 offset 形态；RoundtripKind 解析回 Utc、Ticks 相等。
7. 陈锁异常分型：不存在 PID → `ProcessCommandException`；`$null` PID → `ParameterBindingValidationException`；非数字 PID → `ParameterBindingException`。
8. GitHub：tag=v1.18.31、prerelease=False、37 assets、37/37 带 `sha256:` digest、`opencode-windows-x64.zip` digest 与 spec 逐字符相符；`releases?per_page=10` 回退可用。
9. D 盘 claude/codex 入口与 mise staging **字节同一**（SHA256 相等）；codex 298169136 B 与 spec 示例一致。
10. `git remote` + API：仓库 `demonpiapia/CLI-autoupdate` 为 **public**、license **AGPL-3.0**。
11. gh 2.100.0：`gh release verify` / `gh release verify-asset` **存在**（附 help 摘录）；`gh attestation verify` 亦存在（不同子命令族）。
12. 工作区现状：无 `state/`、无 `staging/`、`TEMP/` 空、`.version-history/` 存在；`.version-history` 末条 = v0.2.18-rc2。

## 6. 未核实 / 受限项

1. 反代 URL 拼接形态是否被接受：TLS 握手失败（`gh.jasonzeng.dev`），未核实；不排除本机 TLS/网络策略因素。
2. D 盘 `opencode.exe` 与 GitHub zip 内 exe 的同源性：staging 缺失，无法比对。
3. `mise upgrade` 非 dry-run 的真实实装版本：未执行实际安装。
4. `npm uninstall -g opencode` 在**真实前缀**的输出：仅沙箱实测机制（no-op + exit 0），真实前缀未执行。
5. codex 在 mise 侧的完整性校验行为：其工具定义为简单 `"latest"`，未发现 checksum 字段（行为未核实）。
6. mise `auto_prune` 的实际默认行为：`mise settings` 输出无该项，未核实。
7. §14-2 反代可靠性的长期结论：单一时点观测不足以定性。

## 7. 建议的修订批次（供用户决策）

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| 第 1 批（正确性） | F1（npm 包名 + 结果断言）、F2（API 信道声明）、F3（回退/pin 语义）、F4（`single-source` 承载）、F5（`already-current` 输入）、F6（npm 定位） | 均为"预期动作不可达 / 判据无输入 / 假成功"类，属实现前必须闭合 |
| 第 2 批（一致性） | F7（保留策略清理模块 + pin 豁免）、F8（File.Replace 前提）、F9（§14-6 标题）、F10（清扫漏项）、F11/F12（威胁模型与阈值） | 契约自洽性与声明准确性 |
| 第 3 批（表述/可读性） | F13–F24 中除已列入前两批者、F25（交付物登记） | 不阻塞实现，建议随下一轮合并处理 |

## 8. 不采纳项与真实反证汇总（用户显式要求）

| 不采纳内容 | 反证（可复现） |
| --- | --- |
| A2 前提：§5.9 等"未采用真正的 markdown 表格、比标准表格臃肿" | 逐字核对：§5.9 表头 = `\| 文件 \| 字段 \| 类型 \| 必填 \| 枚举/说明 \|` + 分隔行；§8/§8.1/§12/§16 同为标准表格 → 前提与原文不符，其建议对这些表不适用（残余部分已采纳为 F13） |
| A1 部分：§14 整体迁移/重构 | ① rc3 轮既有裁决（驳回迁移：§14-1/6/10/11/12 为正文活锚）；② 实测该 5 锚在 §5.2/§6/§7.3/§9/§14-13 被引用，迁移即断链 |
| A1/B3 部分：新增"§14 不构成完备性保证"免责声明 | §14 开头已有等价声明（"真未知风险…不伪声明 closed"）→ 再加属页首指令 5 禁止的防御性重复描述 |
| A3：页首"用户指令"块宜移出 SPEC | 该块为用户本人写入的治理条款且是审计依据（指令 4）；anthropic 自述"非违规"；删除会破坏审计可追溯性 |
| B1 子论断：`mise use` "不会产生任何可观察效果" | `mise use --help`："Installs a tool and adds the version to mise.toml. This will install the tool version if it is not already installed." |
| B1 子论断：pin "实质失效" | §10.3 既定用途为"保持回退版本"，其 `pinned-mismatch → skip → D 盘不动` 路径可达；不可达的仅是 §5.7"拉回"分支 |
| B1 子论断："唯一方式 = 手动物理删除文件夹""与保留最近 2 版直接冲突" | ① `mise uninstall --help`："Removes installed tool versions"（官方命令存在，`-n/--dry-run` 可用）；② 保留策略当前**无实现模块**（B6 已证实），不存在现实冲突；③ 实测当前 claude/codex 各仅 1 个版本目录 |
| B4 部分："需 3–4 倍单文件体积瞬时空间" | 实测 claude `installs\claude\2.1.273` 为 Junction → 物理单份 221MB；codex = 缓存 219.6MB + 解压 284.4MB（约 2 份） |
| B5 部分："mise 自身校验完整性没有任何实测/引用支撑" | 实测 mise 全局 config 中 claude 定义含 `checksum_expr` + `checksum_url`（Google `manifest.json`）→ 存在校验链路证据（codex 侧未核实） |
| B7 定性："隐性例外/原则被打折扣" | §8 表已显式钉死产出者与"聚合数据源 MUST 且仅为 stdout 标记"；§9 状态机含该路由边 → 属已声明例外 |
| B8：计数归零属缺陷 | §10.5 已显式声明该口径；归零方向 fail-safe 且与"10 轮暴露稳定期问题"的设计目标一致；且该步骤当前因 F1 根本不生效 |
| B9：命令名 `gh release verify`/`verify-asset` 存疑 | 本机 gh 2.100.0 实测：`gh release --help` 列出 `verify` 与 `verify-asset` 两项，`gh release verify --help` exit=0 且语义与 spec 描述一致 |
| B11 定性："未显式兜底" | §6 争锁规则 + §8 `LOCKED|` + §8.1 archive-state 行 + §9 段A 出口已覆盖同一 `CreateNew` 失败路径（仅建议补措辞） |
| B12：新增 `action="copy-blocked"` | 现有 `action`+`ok`+`integrityNote`+`reason` 四字段组合已可机械区分；扩枚举将波及 §5.9/§8.1/§15 与"copy 类 reason MUST null"规则链，净增不一致风险 |

## 9. 证据附录（本轮新增原始输出）

```
[1] mise 语义（B1 反证）
mise use --help   → "Installs a tool and adds the version to mise.toml. This will install the tool
                     version if it is not already installed." / "Use the `--global` flag to use the
                     global config file instead."（默认使用 cwd 的 mise.toml）
mise uninstall --help → "Removes installed tool versions … it does not modify mise.toml."（-n/--dry-run）
mise ls           → claude 2.1.273 (symlink) E:\...\mise\config\config.toml latest
                    codex 0.154.0            E:\...\mise\config\config.toml latest
mise settings | grep prune → （空）
mise ls-remote codex → 输出 159 个换行分隔项（含尾部空项）；版本序列含 0.150.0 / 0.150.1 /
                    0.151.0 / 0.152.0 / 0.152.1 / 0.153.0–0.153.4 / 0.154.0
已安装版本目录：claude=[2.1.273]  codex=[0.154.0]

[2] gh 子命令（B9 实测证伪）
gh release --help → verify: Verify the attestation for a release
                    verify-asset: Verify that a given asset originated from a release
gh release verify --help → exit=0；"Verify that a GitHub Release is accompanied by a valid
                    cryptographically signed attestation…checks that the specified release … has a
                    valid attestation … prints metadata about all assets … including their digests."
gh attestation --help → download / trusted-root / verify（另一子命令族，亦存在）

[3] 仓库可见性（B10 佐证）
git remote -v → origin https://github.com/demonpiapia/CLI-autoupdate.git
GitHub API    → full_name=demonpiapia/CLI-autoupdate private=False visibility=public license=AGPL-3.0 fork=False

[4] 磁盘与制品（B4/F12 取证）
卷：C: used=96474MB free=26408MB | D: used=272494MB free=34708MB | E: used=44703MB free=2144MB
http-tarballs：9d79029c…=221MB（claude 2.1.273 junction 目标）、b4dbd731…=219.6MB（共 2 条）
claude\2.1.273\claude.exe = 221MB（经 Junction）; codex\0.154.0\bin\codex.exe = 284.4MB

[5] spec 文本取证（B2）
grep "api.github.com" in SPEC-v0.2.18-rc3.md → 0 命中
grep "gh.jasonzeng.dev" → 4 命中（第 139/165/369/892 行，均为下载路径或信任前提）

[6] mise 全局配置（B5 反证）
config.toml: claude = { version="latest", bin="claude",
  checksum_expr='"sha256:" + fromJSON(body).platforms[...].checksum',
  checksum_url="https://storage.googleapis.com/claude-code-dist-.../manifest.json", ... }
codex = "latest"
```

## 10. 结论（事实判定）

1. anthropic 报告的 15 项意见：**采纳 4、部分采纳 7、不采纳 4**；不采纳项均有可复现反证（最关键者：B9 经本机 gh 2.100.0 实测证伪；A2 前提经原文逐字核对证伪）。其 B1/B2/B6/B10 为我方前次未覆盖的真实缺口，**纳入合并清单**。
2. CodeBuddy 前次 18 项全部维持，其中 **P0-1（npm 卸载包名与假成功）为合并清单中唯一 P0**。
3. 双方结论无冲突；互补后可归纳为 **7 项高优先（F1–F7）+ 18 项 P2**，覆盖正确性、契约自洽性与声明准确性三类问题。
4. rc3 本身的修订（22 hunks / +30/−30）经独立核对**全部落地、无夹带**；其机器事实层声明经两轮实测**无一项被证伪**（唯一被实测证伪的是 anthropic 对 spec 的质疑 B9，而非 spec 自身）。
5. 本报告不作"是否可冻结/是否进入实现"的阶段判断；批次划分仅为修改建议，处置时机由用户决定。
