# CLI 自动升级 验收 checklist（候选）

> **版本**：acceptance-checklist-candidate（对齐 `SPEC-v0.2.10.md`，2026-09-16）。
> **定位**：Executor/测试层产物。SPEC 是 Plan/契约（定义"该做什么"），本 checklist 是验收契约（定义"怎么证明做到了"），**不塞进 spec 主体**（守 spec 的 Plan/契约层定位，spec §15 引用本文件）。
> **骨架来源**：GPT frozen-direction 评审 §3 Checklist A-N（基于 v0.2.6）+ v0.2.7 升级项（P0-1 API digest 主路径、P0-3 失败不覆盖、P1-4 §8.1 marker→exitCode→file 表、P1-5 Canonical Path、N=10）+ v0.2.8 anthropic 消歧（§7.3 null 下沉、§5.4 matchesTarget 基准、§5.8 specVersion 不匹配）+ v0.2.9 anthropic 冻结评审（P0-1 REPAIR target、P0-2 verified channel、P1-1 prerelease-vs-REPAIR、P1-2 N=10 计数、P1-3 ALL_REMOTE_FAIL 聚合）+ v0.2.10 CodeBuddy 审计复核（D1 schema/示例一致性、D2 fromVersion null 类型、D3 §7.3 条件7/8 互补+else 兜底、D4 §7.2 REPAIR `<ver>`、D5 计数唯一规则、D6 三重约束②可机械化、D7 npm-fallback 时间字段例外、D8 FATAL 产出者、D9 ALL_REMOTE_FAIL 产出者、D10 REMOTE_FAIL 落盘字段、D11 sha256 跨脚本拆分、D12 §5.8 示例跨版本）。
> **用法**：Pester 或自写 harness 实现断言。约定 `<cli>` ∈ {claude, codex, opencode}；state 根目录 `D:/AI/Workspace/automatic/CLI-autoupdate/state/`；promotion 入口 `D:/AI/Programs/CLI/<cli>/<cli>.exe`。路径示例用正斜杠（spec §4 Canonical Path 已认可，agent 调 `-File` 用正斜杠）。
> **每条四栏**：条款（spec 节号 + MUST/SHOULD）｜ 可观测证据（json 字段 / stdout 标记 / 文件副作用，锚 §8.1 对照表）｜ 测试用例（输入状态 → 预期标记+exitCode+文件副作用）｜ 判断（设计理由，把推理落盘防上下文压缩丢失）。
> **状态标记**：`[ ]` 待实现断言；`[x]` 已有 fixture/已验证；`⚠` 依赖实现期实测（对齐 §14"已知风险声明"）。

---

## A. 交付物与版本标识（静态验收）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 脚本清单齐全：`cli-common-v0.2.10.ps1`/`archive-state.ps1`/`sync-v0.2.10.ps1`/`probe-local-*.ps1`/`probe-remote-*.ps1`/`upgrade-*.ps1`/`verify-*.ps1`（§7） | 文件存在性（fd/`Test-Path`） | 列工作区根，断言 7 类文件存在 | GPT A 升级到 v0.2.10 文件名；version 字段一致性是回归基线 |
| 脚本版本钉死：共享库与 sync 文件名含 `-v0.2.10`；per-cli 脚本首行 `$ScriptVersion='0.2.10'` + `# SPEC: v0.2.10`（§7.4） | 文件名 + 首行 grep | `rg "^# SPEC: v0\.2\.10"` 各脚本 | 防实现期版本漂移；specVersion 是跨版本追溯锚 |
| 所有 state JSON 顶层 `specVersion:"0.2.10"` + `name`（§5）——🔴 v0.2.10 D1：`name` 例外——sync.json 顶层用 `name:"sync"`；`error` 仅 local/remote/upgrade 必带，verified/sync/current-run/pin/npm-fallback 不带 error | JSON 字段 | 遍历 state/*.json 断言两字段（按文件判 name/error 适用性） | 跨版本 schema 标识；D1 闭合 §5.9「全部」行与示例矛盾（P0-2 同族） |
| **旧 specVersion 处理（🟡 v0.2.8，回填 anthropic——修正原 A 节"触发 fail-closed"脑补）**：state 文件 specVersion≠当前 → 视为陈旧，MUST NOT 作本轮决策依据消费（probe 类本轮覆盖；verified.json 不作晋升凭证——runId 新鲜度天然拦 + specVersion 第二道保险）；**非 fatal、非 PARSE_ERROR**，本轮覆盖写回当前 specVersion 即迁移（§5.8） | 旧 specVersion 文件不被消费 + 本轮覆盖回写 | 预置 `"specVersion":"0.2.9"` 的 verified.json，本轮跑 sync，断言：①不以其为晋升凭证（runId 不匹配天然拦）②本轮 verify 产出新 `"specVersion":"0.2.10"` 覆盖 | **原 checklist A 节断言"旧 specVersion 触发 fail-closed"系脑补**——spec §5/§5.8 无此硬约束；v0.2.8 §5.8 已回填真实契约：specVersion 漂移是版本演进正常现象，文件完整可解析仅"内容不再可信"，非 schema 损坏。fail-closed 仅针对字段缺失/类型错（§5.8 RUNTIME_ERROR_FATAL schema）。v0.2.10 D12 修正示例为跨版本值（`"0.2.9"` vs `"0.2.10"`） |

---

## B. 环境与目录布局（前置条件）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 仅 Windows 11 + PowerShell 7.6.4（§15 环境） | `pwsh --version` 输出 | 验收机打印版本记录 | R25 强制 PS7；PS5.1 行为差异会破坏 `Invoke-Proc`/编码 |
| 目录布局：`state/`/`staging/`/`archive/`/`TEMP/` + promotion `D:/AI/Programs/CLI/{claude,codex,opencode}/`（§4/§3） | `Test-Path` 各目录 | 建目录断言；promotion 目录即使 exe 未 seed 也须存在 | F1 首轮 seed 依赖 promotion 目录先在 |
| Canonical Path 无空格（P1-5，§4） | 路径逐字核对 | 断言三个 promotion 路径不含空格 | 驳回 GPT"插空"为渲染误读，仍加此低成本保险供 agent 逐字复制 |
| TEMP 交付前必空（§10.4） | `TEMP/` 列空 | 验收开始前 + 结束后双断言空 | R31/R33 收尾铁律；防孤儿文件堆积 |

---

## C. 运行锁模型（runId ownership）

> 目标：证明"不会并发写、不抢锁、可恢复但 fail-closed"。

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 争锁原子性：`archive-state` 用 `CreateNew + FileShare::None`（§6） | `run.lock` 与 `current-run.json` 同 runId | 并发两进程争锁，断言一胜一 `LOCKED|` | ownership 靠 runId 不靠 PID（PID 沙箱不可靠，§14-3） |
| 续锁校验：锁 runId 与 `current-run.json` 不匹配/被独占/锁消失 → `LOCKED|` fatal（§6） | stdout `LOCKED|` + exitCode 2（§8.1） | 篡改 current-run.runId 后续锁 | 锁消失也 fail-closed（不假设锁正常） |
| 陈锁接管：beat 超 30min **且** PID `Get-Process` 确认死亡才删锁重争；不确定保守 `LOCKED|`（§6） | 锁文件 beat/pid 字段 | 模拟 beat 超时 + PID 不存在/存在两类 | ⚠ Cherry 沙箱 PID 判定可靠性待实测（§14-3）；不确定→不抢锁是保守正确 |
| 人工清锁四条件全满足才允许（§6 恢复手册） | SOP 章节存在 | 文档审查 SOP 含四条件 | 防 agent 自作主张抢锁 |

---

## D. state 数据契约 + 原子写入 + 失败不覆盖

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 时间字段：除 `current-run.startAt`/`*.pin.setAt`/`opencode-npm-fallback.lastUpdatedAt` 外，local/remote/upgrade/verified/sync MUST 有 `runAt`（ISO UTC）（§5）——🔴 v0.2.10 D7：npm-fallback 用 `lastUpdatedAt`（非逐轮 state，跨轮计数器，§10.5） | JSON 字段 | 遍历断言（npm-fallback 断言有 lastUpdatedAt 而非 runAt） | 回应 GPT 4.1 + v0.2.10 D7；双时间字段语义不同 |
| runId：`current-run/verified/sync` MUST；`local/remote/upgrade` SHOULD（§5） | JSON 字段 | 遍历断言 | 关联本轮，防同分钟多轮混读 |
| 原子写入三段式：`*.tmp` → 回读校验 → `Move-Item`；失败 `RUNTIME_ERROR_FATAL|schema` fatal 释放锁（§5.8） | exitCode 3 + 锁释放 + 无残 tmp | 人为截断 tmp 触发回读不一致 | 同卷原子；跨卷先 Copy 到目标卷再 Move |
| **P0-3 失败不覆盖**：verify 失败 MUST NOT 写新鲜 runId 的 verified.json；upgrade 非升级分支 MUST NOT 写 upgrade.json；probe-local/remote `RUNTIME_ERROR` 不覆盖旧 local/remote（§5.4/§5.3/§8.1） | 旧 verified/upgrade/local/remote.json 的 runId 未变 | 构造 verify 失败 case，断言旧 verified.json runId 不被新 runId 覆盖 | **核心防误晋升**：失败轮若写新鲜 runId 凭证，sync 会误判新鲜度用失败轮凭证覆盖旧有效凭证。GPT P0-3 已采纳 |
| `RUNTIME_ERROR|<cli>`（CLI 级）不覆盖该 CLI 旧文件（§8.1） | 旧文件 mtime/runId 不变 | 触发 CLI 级异常 | 失败不污染，与骨架级 fatal 区分 |

---

## E. stdout 标记协议 + exitCode + §8.1 对照表

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 每脚本 stdout ASCII 标记；agent 只读标记不解析 json（§8） | stdout 捕获 | 跑各脚本捕获标记 | agent 不算账原则（原则 3/10） |
| fatal vs recoverable 分层：`LOCKED|/STATE_MISSING|/PARSE_ERROR|/RUNTIME_ERROR_FATAL|` fatal；`RUNTIME_ERROR|<cli>` recoverable（§8） | 标记类别 + 后续行为 | fatal 断言整轮终止；recoverable 断言继续下一 CLI | 原则 5 fail-closed 分层 |
| 标记全集覆盖（§8 表） | 标记枚举 | 跑全分支场景，断言每个标记至少出现一次 | §8 表是标记全集基线 |
| exitCode 0/10/11/2/3 语义一致（§8/§8.1） | exitCode + 标记 + 产物 | 每标记记录 exitCode+文件副作用，对照 §8.1 表 | agent 以 stdout 为准；exitCode 供人工/日志 |
| **§8.1 marker→exitCode→文件副作用表**（P1-4）：每标记对应 exitCode + 写/覆盖/不写（§8.1） | §8.1 表存在 + 实现匹配 | 逐标记断言 exitCode + 文件副作用 | GPT P1-4 采纳；验收机械化的前提，否则 Pester 写不出 |
| 未列出的 failed 标记 → agent 按 fatal 处理（§8） | 保守优先 | 注入未知 failed 标记 | 脚本侧尽量不产生未知标记 |

---

## F. archive-state.ps1

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 归档：每轮首步归档 `state/*.json` 到 `archive/<ts>/`（不含 run.lock/archive/current-run.json/pin）（§11/§10.4） | archive 目录内容集合 | 跑一轮，断言归档目录内容 = 预期集合 | 排除项防归档自我递归/锁归档 |
| 清理 `*.tmp` 拋留（§10.4） | 无残 tmp | 预置 tmp 文件，跑 archive，断言清理 | 原子写入失败残留清理 |
| 归档保留 30 轮，超出最旧先删（§10.4） | archive 目录数 ≤ 30 + 排序 | 生成 31+ 假归档目录，跑 archive，断言数量+最旧被删 | 30 轮覆盖约 30 天定时窗口 |

---

## G. probe-local-<cli>.ps1

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 写 `<cli>-local.json` schema 齐全（channel/version/exePath/bytes/mtime/healthy/healthDetail/error + runId SHOULD + sha256）（§5.1） | JSON 字段 | 跑 probe-local 断言 | 字段对齐 §5.9 schema 总表 |
| healthy=true ⟺ exe > 1MB 且 `--version` 可启动（§5.1） | healthy 字段 | 构造 <1MB stub / 正常 exe 两 case | 防半下载/stub 伪装 |
| healthDetail 枚举 ok/broken/probe-error（§5.1） | healthDetail 字段 | 三 case 触发 | broken→REPAIR；probe-error→不重装（§7.3 分支 4/5） |
| stdout `LOCAL_OK|<cli> ver=<v> healthy=<bool> detail=<d>`；opencode staging 空 → `LOCAL_EMPTY|<cli>`（§8） | 标记 + exitCode 11（§8.1） | 正常/空两 case | UPTODATE_REFRESH 兜底依赖 LOCAL_EMPTY→upgrade |
| opencode staging 空 → `version=null, exePath=null, healthy=false, healthDetail=broken`（§5.1） | JSON 字段 | 空 staging case | 首轮 seed 触发条件 |
| `RUNTIME_ERROR|<cli>` 不覆盖旧 local.json（P0-3，§8.1） | 旧文件 runId 不变 | 触发 probe-local 异常 | 失败不污染 |

---

## H. probe-remote-<cli>.ps1

### H1 mise 通道（claude/codex）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| `mise ls-remote <tool> --json` 取最高 stable（§5.2） | remote.json.latest | 跑 probe-remote | mise 自校验包完整性 |
| 超时 60s（Invoke-Proc，§5/§7.1） | 60s 超时触发 | mock 挂起 mise | 防 hang |

### H2 github-binary 通道（opencode）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| `releases/latest` → tag_name（去 v）+ assets 筛 `windows-x64.zip`（§5.2） | remote.json.latest/assetName | mock/实测 | 已实测 tag=v1.18.31/assetName=opencode-windows-x64.zip（§14-1 闭合） |
| **API asset digest 主路径（P0-1）**：取 `.assets[].digest`（`sha256:<64hex>`）剥前缀写 `expectedSha256` + `assetDigest`（§5.2） | remote.json.assetDigest/expectedSha256 | mock API 响应含 digest | **gh api 实测验证**：v1.18.31 全 37 asset 带 digest；digest 由 GitHub upload 时算 immutable，比 checksum asset 更可信且无需额外下载 |
| digest 解析规则（MUST，§5.2）：assetName 精确匹配条目；`sha256:` 前缀剥离取 64hex；digest null/缺失→视为不可用 fallback | expectedSha256 值 | 构造 digest=null case | null 处理是 fallback 链起点 |
| **驳回"删除 checksumAssetUrl"**：保留 `checksumAssetUrl` 作 fallback（digest 不可用时用）（§5.2/§5.9） | remote.json.checksumAssetUrl 字段存在 | digest=null 时 checksumAssetUrl 非空 | 旧 release digest 可能为 null，fallback 仍需它；双 hash 兜底也用——augment 非 replace |
| 回退：latest 失败 → `releases?per_page=10` 取最高 stable（prerelease=false），`fallbackUsed=true`（§5.2） | fallbackUsed 字段 | mock latest 404 | 二级回退 |
| REMOTE_FAIL 仍落盘：🔴 v0.2.10 D10——必填字段全落盘 `latest/sourceUrl/directUrl/assetName/assetDigest/expectedSha256/checksumAssetUrl=null, fallbackUsed=false, error:<cause>`（§5.2/§8.1） | remote.json 字段 | mock 全失败，断言 §5.9 必填字段全在（null/默认占位） | 失败也写文件供 upgrade 读 NO_REMOTE；schema 一致不缺字段 |
| 限流识别：403 + `x-ratelimit-remaining:0` → `RATE_LIMITED|<cli>`（§5.2/§8） | 标记（recoverable，exitCode 3） | mock 403+header | 区别普通 REMOTE_FAIL（§9 铁律8） |
| token 安全：MAY 取 `gh auth token`/env，MUST NOT 写 state/log/推送（§5/§9） | 全量 grep token 模式 0 命中 | 跑后搜 state/log/push | token 泄露零容忍 |

### H3 ALL_REMOTE_FAIL（整轮级）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 三 CLI 全 remote fail → 🔴 v0.2.10 D9：**由 agent/SOP 聚合判定**（非单 CLI 脚本产出，读三 remote.json/latest/error 或三 recoverable 标记），整轮跳 upgrade/verify 直进 sync（§8） | 标记 + 状态机路径 | mock 三 CLI 全败，断言 ALL_REMOTE_FAIL 由 SOP 聚合产出 | 网断不升级但 sync 全 skip + RUN_STATUS success（如实汇报） |
| **聚合口径（🟢 v0.2.9 P1-3）**：RATE_LIMITED 与 REMOTE_FAIL 均计入"remote fail"——三 CLI 中混合 RATE_LIMITED+REMOTE_FAIL 也触发 ALL_REMOTE_FAIL | 标记 | mock 一 CLI RATE_LIMITED + 两 CLI REMOTE_FAIL | 防 implementer 误以为只算 REMOTE_FAIL；§8 表行已声明 |

---

## I. upgrade-<cli>.ps1（核心：§7.3 九分支）

> 方法：fixture 写 local.json + remote.json + verified.json + current-run.json，跑 upgrade，断言 stdout 标记 + 是否写 upgrade.json。

### I0 通用

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| if-elif 顺序严格按表 1→9（+else 兜底）命中即止（§7.3） | 标记取编号小者 | 构造同时满足多条件 case | 顺序：远端/格式/策略前提(1-3) > 本地健康(4-5) > 版本比较(6-9)；🔴 v0.2.10 D3：条件7/8 互补 + else 兜底保证九分支穷尽 |
| **null 下沉（🔴 v0.2.8，回填 anthropic 阻塞项反查）**：`local.version==null`（opencode staging 空/`healthDetail=broken`）MUST NOT 命中条件2（版本不可解析），须跳过条件2 下沉至条件4/5（§7.3 顺序说明 + 条件2 行"均非 null 时判定"） | `local.version=null + healthDetail=broken` → 命中条件5 `REPAIR\|`（非条件2 `VERSION_FORMAT_ERROR\|`） | **交叉用例**：fixture `local.version=null, healthy=false, healthDetail=broken, remote.latest=1.18.31`，跑 upgrade，断言标记=`REPAIR\|<cli>` 而非 `VERSION_FORMAT_ERROR\|` | **anthropic 捕获的真漏洞**：原 spec 条件2"Compare-SemVer incomparable"对 null 会先命中→VERSION_FORMAT_ERROR→永远走不到条件5 REPAIR→首次 seed 卡死。v0.2.8 消歧：null 是"无版本"非"格式坏"，Compare-SemVer 对 null 由调用方前置判空不返回 incomparable。此交叉用例验证消歧生效——这是"决定首次安装能不能跑起来"的断言，非过度设计 |
| 不升级分支不写不覆盖 upgrade.json（P0-3，§5.3/§8.1） | upgrade.json 不存在/未变 | 跑不升级分支 | GPT P0-3；防失败轮污染 |

### I1 九分支逐条

| # | 条件 | 预期标记 | exitCode | 文件副作用 | 判断 |
|---|---|---|---|---|---|
| 1 | remote.latest==null | `NO_REMOTE|<cli> <cause>` | 0 | 不写 upgrade.json，跳 verify | upgrade 读 latest:null 走此分支 |
| 2 | 版本不可解析（**local.version 与 remote.latest 均非 null**，Compare-SemVer incomparable；null 不计此条，见 I0 null 下沉） | `VERSION_FORMAT_ERROR|<cli> <raw>` | 0 | 不写，跳 verify | 格式坏（非空字符串如 `0.1.2.3`）；null 下沉至 4/5 |
| 3 | target prerelease | `TARGET_PRERELEASE|<cli> <v>` | 0 | 不写，跳 verify | stable-only 拒绝 |
| 4 | healthy=false 且 probe-error | `PROBE_ERROR|<cli> <reason>` | 0 | 不写，跳 verify | 不重装（probe 偶发超时） |
| 5 | healthy=false 且 broken | `REPAIR|<cli> <reason>` | 11 | 写 upgrade.json（target=remote.latest，fromVersion 可能 null），进 verify | 强制重装到 remote.latest（🔴 v0.2.9 P0-1） |
| 6 | local<remote 且 stable | `ACTIONABLE|<cli> <from>-><to>` | 11 | 写 upgrade.json，进 verify | 主升级路径 |
| 7 | local==remote 且**有本轮新鲜凭证**（🔴 v0.2.10 D3：仅同轮 re-probe 可达——upgrade 在 verify 之前跑，跨轮首次调用恒无本轮新鲜凭证） | `UPTODATE_SKIP|<cli> <v>` | 0 | 不写，跳 verify | 真幂等（同轮重复调用幂等） |
| 8 | local==remote 且**无本轮新鲜凭证**（缺失/过期/`verified.version≠local.version` 任一）——🔴 v0.2.10 D3：与条件7 互补，覆盖原"stale-but-matching"空洞 | `UPTODATE_REFRESH|<cli> <v>` | 0 | 不写 upgrade.json，仍跑 verify | F1 seed 兜底；刷新凭证；跨轮稳态 UPTODATE 走此 |
| else | 1–9 均未命中（防御性，正常不可达）——🔴 v0.2.10 D3 | `RUNTIME_ERROR|<cli> branch-undefined` | 3 | 不写，跳 verify，写 fetch_run.log warning | 九分支穷尽兜底 |
| 9 | local>remote | `LOCAL_AHEAD|<cli> <local> > <remote>` | 0 | 不写，跳 verify | 不自动降级，显式报告 |

### I2 opencode 下载完整性（§5.2，v0.2.7 digest 主路径）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 下载 zip 后 MUST 校验大小 > 1MB（§5.2） | DOWNLOAD_FAIL cause | 构造 <1MB | 防半下载/stub |
| **digest 主路径 MUST**：API digest 存在 → 下载后计算 SHA256 与 `expectedSha256` 比对；不匹配 `DOWNLOAD_FAIL|<cli> digest-mismatch`（§5.2） | 标记 + verified.sha256 | mock digest 不匹配 | P0-1 采纳；digest 无需额外下载 checksum 文件（省一跳） |
| digest 不可用 → checksum asset 存在 MUST 下载校验；不匹配 `DOWNLOAD_FAIL|<cli> checksum-mismatch`（§5.2） | 标记 | mock digest=null + 有 checksum | fallback 第一级 |
| digest+checksum 均无 → SHOULD 双 hash（反代+直连独立下载 SHA256 一致才接受）；不一致 `DOWNLOAD_FAIL|<cli> dual-hash-mismatch`（§5.2） | 标记 | mock 两源不一致 | fallback 末级；检出反代投毒 |
| MAY single-source（直连不通仅反代 + `integrityNote:single-source`，记 sync.json.entries）（§5.2） | integrityNote=single-source | mock 直连不可达 | 偏离须记录 |
| 解压后目标 exe MUST 计算 SHA256：🔴 v0.2.10 D11——upgrade 写 `upgrade.json.sha256`（staging exe hash），verify 复算写 `verified.json.sha256`（同源，数值应一致）；upgrade MUST NOT 越界写 verified.json（§5.2） | upgrade.json.sha256 + verified.sha256 两值相等 | 跑成功 case，断言两文件各写各的 sha256 且一致 | 证据链数据源；D11 拆分跨脚本职责 |
| **digest-mismatch cause**：DOWNLOAD_FAIL 枚举含 `digest-mismatch`（§8/§9） | 标记枚举 | mock digest-mismatch | v0.2.7 新增 cause（主路径失败） |

### I3 checksum 解析器（函数级单测，fallback 路径）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 支持两 sha256sum 格式：`<hash>  <filename>`（双空格）与 `<hash> *<filename>`（§5.2） | 解析返回正确 hash | 两 fixture | GPT 4.5 MUST |
| 单文件 `*.sha256`（一行 hash 或 hash filename）支持（§5.2） | 解析返回 | fixture | 兼容发布者格式 |
| assetName 精确匹配（大小写不敏感，忽略路径前缀）；未匹配视为无 checksum（§5.2） | 返回 null | 不匹配 fixture | 防校验形同虚设 |
| 忽略空白行/`#` 注释；非 64hex 跳过（§5.2） | 跳过无效 | fixture 含噪声 | 鲁棒 |
| 多匹配取第一条 + fetch_run.log warning（§5.2） | warning 日志 | 多匹配 fixture | 可审计 |

### I4 API digest 解析器（函数级单测，主路径，v0.2.7 新增）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 取 `.assets[]` 按 assetName 精确匹配条目的 `digest` 字段（§5.2） | 返回 digest | fixture API 响应 | assetName 匹配同 I3 规则 |
| 格式 `sha256:<64hex>` 剥前缀取 64hex 写 `expectedSha256`（§5.2） | expectedSha256=64hex | fixture | 剥前缀规则 |
| digest null/字段缺失 → 视为不可用，回退 checksum asset（§5.2） | 返回 null + 触发 fallback | fixture digest=null | 旧 release digest 可能为 null [cite:472d3952-2] |

---

## J. verify-<cli>.ps1

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 成功 `VERIFY_OK|<cli> <v> matches=true healthy=true sha256=<或空>`（§8） | 标记 + exitCode 11 | 跑成功 case | 晋升凭证产出 |
| 失败 `VERIFY_FAIL|<cli> <cause>`，D 盘入口不动（§8） | 标记 + exitCode 3 + D 盘未变 | 故意 `--version` 非零/超时 | 不晋升 |
| **P0-3 verify 失败不写新鲜 runId verified.json**（§5.4/§8.1） | 旧 verified.json runId 未变 | verify 失败后断言旧 verified.json 不被覆盖 | **核心**：防 sync 误判新鲜度用失败轮凭证覆盖旧有效凭证 |
| `<cli>-verified.json`：runId MUST 本轮 uuid + version/exePath/bytes/healthy/matchesTarget（§5.4） | JSON 字段 | 成功 case | 晋升三重约束数据源 |
| opencode sha256 必填；mise SHOULD（§5.4） | sha256 字段 | 两通道 case | 证据链对齐 §5.5 |
| **verified.json 含 channel 字段（🔴 v0.2.9 P0-2）**：`channel` 必填（mise/github-binary），sync 据此判 sha256 MUST/SHOULD，无需跨文件读 local/remote.json（§5.4/§5.9） | verified.json.channel 字段存在 | 跑 verify 两通道，断言 channel 字段非空且匹配 | **原 §5.9 表 verified channel 必填但 §5.4 示例无 channel**——schema/示例矛盾。v0.2.9 补示例 `"channel":"mise"`，verified 自带通道，Pester 断言自包含 |
| **matchesTarget 基准（🟡 v0.2.8，回填 anthropic）**：`matchesTarget` 比较基准按 upgrade 决策分支取定（§5.4）——ACTIONABLE/REPAIR 对比 `upgrade.json.target`；UPTODATE_REFRESH（无 upgrade.json）对比 `local.version`（==`remote.latest`，UPTODATE 前提） | matchesTarget 值 + 对比基准来源 | ①ACTIONABLE case：实测 version==upgrade.json.target→true；②UPTODATE_REFRESH case：无 upgrade.json，实测 version==local.version→true；③version≠target→false 触发 VERIFY_FAIL | **原 §5.4 只给字段值 true 未定义"match 的是谁"**——anthropic 指出契约缺口。v0.2.8 补：升级分支对比 upgrade.json.target，刷新轮对比 local.version；matchesTarget==false 一律 VERIFY_FAIL（version-mismatch）不晋升，统一拦在晋升闸外 |
| `RUNTIME_ERROR|<cli>` 不覆盖旧 verified.json（§8.1） | 旧文件未变 | 触发异常 | 失败不污染 |

---

## K. sync-v0.2.10.ps1（晋升闸 + 证据链 + 异常隔离 + npm fallback 计数）

### K1 三重约束（晋升闸）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 仅当 verified 满足①新鲜度（runId==current-run.runId 或 runAt≥startAt）②完整性（🔴 v0.2.10 D6：opencode `verified.sha256` 非空，且 sync 复算 `sourceSha256==verified.sha256`——同源 exe hash 一致；zip 下载完整性已由 upgrade §5.2 闭合）③pin 未冲突，才 copy（§5.4/原则4） | sync.json entries.action | 构造三条件各不满足 case | 任一不满足 D 盘不动；D6 改可机械判定（原"与下载校验值一致"比 exe hash 与 zip hash 数值必不等，不可实现） |
| 不满足 → `SYNC_SKIP|<cli> <reason>`，D 盘不变（§8） | 标记 + D 盘未变 | case | 幂等 skip |

### K2 copy 行为与证据链

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 覆盖前备份 `.previous`（§10.3） | `.previous` 存在 | 跑 copy | 回退源 |
| copy 后字节复核 + sha256 复核（sourceSha256==targetSha256）（§5.5） | 两值相等 | 跑 copy | 防落盘偏差 |
| `sync.json.entries` copy 必填：source/target/targetVersion/bytes/sourceSha256/targetSha256/previousSha256/integrityNote/ok（opencode sha256 MUST，mise SHOULD）（§5.5/§5.9） | JSON 字段 | 跑 copy | 二进制证据链 |
| stdout `SYNC_COPY|<cli> <bytes>` / `SYNC_SKIP|<cli> <reason>`（§8） | 标记 | 两 case | exitCode 0/11（§8.1） |

### K3 pin 语义（只作用于 sync）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| pin 存在 → sync 目标=pinVersion（§5.7） | targetVersion=pinVersion | 建 pin | pin 不阻断 upgrade（staging 可备最新） |
| verified.version==pinVersion 且 D==pin → `SYNC_SKIP|already-current`（幂等）（§5.7） | 标记 | case | 幂等 |
| verified.version==pinVersion 且 D≠pin → `SYNC_COPY|` 修复性晋升（§5.7） | 标记 + D 变 | case | 拉回 pinVersion |
| verified.version≠pinVersion → `SYNC_SKIP|pinned-mismatch`（§5.7） | 标记 | case | 不晋升 latest |
| 解锁跟随 latest → 删 pin 或改 pinVersion=latest（§5.7） | pin 文件操作 | case | 语义闭环 |

### K4 目标锁定与异常隔离

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 目标 exe 在跑 → `SYNC_TARGET_LOCKED|<cli>` 跳过该 CLI 不阻其他（§8） | 标记 + 其他 CLI 仍 copy | 占用某 CLI exe | recoverable |
| sync 内每 CLI copy MUST 独立 try/catch；单 CLI 失败不冒泡终止整轮（§7.2 原则13） | 其他 CLI 仍 copy | 某 CLI D 盘只读/占用 | 异常隔离硬约束 |
| 骨架级失败（锁/汇总/schema/summary 落盘）→ `RUNTIME_ERROR_FATAL|` fatal（§7.2） | 标记 + 整轮终止 | mock summary 异常 | 与 CLI 级 recoverable 分层 |

### K5 整轮终态

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| sync 末步 `RUN_STATUS|success|<summary>`；fatal `RUN_STATUS|failed|<cause>`（§8） | 标记 + exitCode 0/2 | 成功/fatal case | 终态 |
| `sync.json.summary` 为 agent 汇报数字唯一来源（§5.5/§9） | summary 与 entries 计数一致 | 跑后断言 | agent 不数 entries |

### K6 opencode npm fallback 计数（🟡 v0.2.9 P1-2）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| `state/opencode-npm-fallback.json` schema：consecutiveSyncSuccess(int)/lastUpdatedAt(ISO)/uninstalled(bool) + specVersion/name（§5.9/§10.5） | JSON 字段 | 跑 sync 后断言文件存在且字段齐 | 原仅定 N=10 阈值无计数机制，名实不符；v0.2.9 补方案(a)轻量计数文件 |
| 成功计数：opencode 本轮 sync 成功（SYNC_COPY 或 already-current）→ +1 | consecutiveSyncSuccess 递增 | 连续跑 3 轮 opencode 成功，断言计数=3 | "成功"含幂等 skip（already-current 仍算稳定） |
| 失败归零：opencode sync 失败（copy 失败/复核不过/目标锁定/SYNC_SKIP 非 already-current）→ =0。🔴 v0.2.10 D5：**ALL_REMOTE_FAIL 不属"未跑 sync"**——其直进 sync，opencode 走 SYNC_SKIP（非 already-current）即归零，已被本条覆盖 | 计数归零 | 计数到 5 后造一次 opencode copy 失败，断言归 0 | 任一失败破坏"连续"语义 |
| **🔴 v0.2.10 D5 唯一规则（fatal 不归零）**：计数更新**仅当 sync 完整执行到末步**才发生；fatal 中断（sync 未完整执行：LOCKED/STATE_MISSING/PARSE_ERROR/RUNTIME_ERROR_FATAL 在 sync 末步前）→ **不更新（保持旧值）**，与 §8.1 RUN_STATUS\|failed 行"fatal 前已处理则更新否则不动"一致 | fatal 后计数不变 | 计数到 5 后造 sync 骨架级 fatal（RUNTIME_ERROR_FATAL），断言计数仍=5（不归零） | fatal 不清累计进度；闭合 §10.5 与 §8.1 原冲突 |
| 达 10 卸载：consecutiveSyncSuccess≥10 且 uninstalled==false → 执行 npm uninstall -g opencode，置 uninstalled=true | uninstalled=true + npm 全局无 opencode | 连续 10 轮成功后断言卸载执行 | 幂等：uninstalled=true 后不再重复卸载 |
| sync 末步更新本文件（RUN_STATUS success 覆盖；fatal 前已处理则更新否则不动）（§8.1） | 文件 mtime 更新 | 跑 sync 断言文件被覆盖 | §8.1 表 sync 行副作用已含 |

---

## L. ZipSlip 防护（opencode 解压）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 解压限定 `staging/opencode/<ver>/` 子树（§7.2） | 解压路径 | 构造 entry 含父目录穿越 | ZipSlip 硬约束 |
| MUST 拒绝父目录穿越段/绝对路径/symlink/junction entry（§7.2） | `DOWNLOAD_FAIL|<cli> zip-slip` | 构造恶意 entry | 解压默认不安全 |
| 非法 entry → 中止解压+清理已解压+不写 verified.json（§7.2/§8.1） | 无 verified.json + 已清理 | case | P0-3 失败不写凭证 |
| 解压后目标 exe 存在且 > 1MB（§7.2） | exe 存在 | 正常解压 case | 防空/残缺 |

---

## M. 回退与清理策略

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| mise `upgrade.auto_prune=false`；回退 `mise use`；保留最近 2 stable（§10.1） | mise 配置 | 检查配置 | 防自动 prune 删旧版 |
| opencode staging 保留最近 2 版；升级失败不写新鲜凭证→sync 不动 D 盘（§10.2） | staging 目录数 | 跑多轮 | 失败不晋升 |
| 手动回退语义：`.previous` 回退后不建 pin → 下一轮被新鲜凭证覆盖；要保持必须建 pin（§10.3） | pin 存在性 | case | 自动跟随 latest 的预期 |
| `run.lock` 拋留按 §6 恢复手册；不脚本自动强删（除陈锁接管满足条件）（§6/§M） | 无自动删锁代码 | 代码审查 | fail-closed 不抢锁 |

---

## N. SOP/Agent 编排契约（可编排性）

> SOP 文件未产出，先验收"脚本接口满足 SOP 可写"前提。

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 状态机分段可跑通：A(archive+probe)→B(upgrade+verify)→C(sync)（§9） | 三段标记序列 | 跑端到端 | 无差别调用（§9） |
| `UPTODATE_SKIP` 跳 verify；`UPTODATE_REFRESH/ACTIONABLE/REPAIR/UPGRADE_OK` 进 verify（§9） | 分支路径 | 各分支 case | agent 铁律1 |
| `ALL_REMOTE_FAIL`：整轮不升级，sync 全 skip，`RUN_STATUS|success`（如实汇报网断）（§8/§9） | 终态 success + 全 skip | mock 网断 | 网断非失败 |
| agent 铁律可满足：脚本不要求 agent 读 json；stdout 标记足够分支（§9） | 无 json 解析需求 | 审查 SOP 可写性 | 原则 3/10 |
| 错误场景示例覆盖（§9）：网络全断/exe 锁定/下载失败（digest-mismatch/checksum-mismatch/dual-hash-mismatch/zip-slip）/verify 失败/UPTODATE_REFRESH/pin 锁定/被锁阻塞/限流（§9） | SOP 含每例"输入→标记序列→agent 分支→汇报文本" | 文档审查 | SOP MUST 覆盖 |
| agent 在 pwsh 命令行调 `-File` 用正斜杠；不 `cd /d`、不 `./`（§9 铁律3） | SOP 路径写法 | 审查 | MSYS 路径转换规避 |

---

## O. v0.2.7 收敛项专项验收（P0/P1 闭合验证）

> 本节专验 v0.2.7 相对 v0.2.6 的闭合点，确保"frozen 候选"名实相符。

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| **P0-1 digest 主路径已采纳**：§1 原则12 + §5.2 策略 + §5.9 schema + §5.10 威胁模型 + §17 术语表均有 digest 条目 | spec 文本 grep | 审查 spec 各节 | gh api 实测验证（v1.18.31 全 37 asset 带 digest）；采纳非 GPT 过度设计 |
| **驳回"删除 checksumAssetUrl"已落地**：remote.json schema 仍含 checksumAssetUrl（fallback）（§5.2/§5.9） | schema 字段存在 | 审查 | augment 非 replace；旧 release digest 可能为 null |
| **威胁模型边界不变**：§5.10 声明"API digest 不解决上游被攻破"（digest 来自同一 release）（§5.10） | 声明文本 | 审查 | GPT 未明说，我补——防审计误以为 digest 解决真实性 |
| **P0-2 §14 闭合状态**：§14-1/4/5/6/7/9 已闭合；§14-2/3/8 知名风险声明不伪关闭（§14） | §14 文本 | 审查 | 驳回 GPT"全部关闭"为过度；真未知风险需实测 |
| **§14-1 实测闭合**：tag=v1.18.31/assetName=opencode-windows-x64.zip/37 asset 带 digest/prerelease=false（§14-1） | gh api 复跑 | 实测复跑 | 已验证 |
| **§14-5 N=10 定死**：§10.5 "连续 10 轮 sync 成功后卸载"（§10.5） | spec 文本 | 审查 | GPT P0-2 采纳；10 轮覆盖约 10 天 |
| **§14-6 digest 覆盖率 100% 实测**：v1.18.31 全 asset 带 digest（§14-6） | gh api | 实测复跑 | 已验证；digest 缺失走 fallback |
| **P0-3 失败不覆盖**：§5.4 + §8.1 表 verify/upgrade/probe 失败行均落地（§5.4/§8.1） | spec 文本 + §8.1 表 | 审查 | 防误晋升核心 |
| **P1-4 §8.1 表存在**：marker→exitCode→文件副作用对照表（§8.1） | §8.1 表存在 | 审查 | 验收机械化前提 |
| **P1-5 Canonical Path**：§4 无空格代码块（§4） | 代码块存在 | 审查 | 低成本保险 |
| **Checklist A-N 引独立交付物**：§15 引用本文件，不塞 spec 主体（§15） | §15 引用 | 审查 | 守 Plan/契约层定位 |

---

## O2. v0.2.8 anthropic 消歧项专项验收（冻结前最后消歧）

> 本节专验 v0.2.8 相对 v0.2.7 的消歧点（anthropic frozen-direction 评审），确保"消歧"名实相符，非仅改文字。

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| **🔴 §7.3 null 下沉规则已落地**：条件2 行"均非 null 时判定" + 顺序说明 null 段 + Compare-SemVer 对 null 不返回 incomparable（§7.3） | spec 文本 grep + I0 null 下沉交叉用例 | 见 I0 null 下沉交叉用例（local.version=null+broken→REPAIR 非 VERSION_FORMAT_ERROR） | **anthropic 阻塞项**：原 spec 此处歧义致首次 seed 卡死；v0.2.8 已消歧，I0 交叉用例验证 |
| **🟡 §5.4 matchesTarget 基准已定义**：ACTIONABLE/REPAIR 对比 upgrade.json.target；UPTODATE_REFRESH 对比 local.version；false→VERIFY_FAIL（§5.4） | spec 文本 + J 节 matchesTarget 基准验收 | 见 J 节 matchesTarget 三 case | **anthropic 契约缺口**：原 §5.4 只给字段值无基准；v0.2.8 补齐，J 节验收 |
| **🟡 §5.8 specVersion 不匹配行为已定义**：不作本轮决策依据消费 + 非 fatal + 本轮覆盖迁移（§5.8） | spec 文本 + A 节 specVersion 断言 | 见 A 节旧 specVersion 处理 case | **anthropic 契约缺口**：原 checklist A 节"触发 fail-closed"脑补；v0.2.8 §5.8 回填真实契约，A 节断言已修正 |
| **🟢 §14-10 锁崩溃已知风险已补录**：锁获取与 current-run.json 写入间崩溃→下一轮 LOCKED（§14-10） | §14-10 文本存在 | 审查 §14 含第 10 项 | fail-closed 覆盖无安全风险，仅人工清锁成本；保持 §14 完整性 |

---

## O3. v0.2.9 anthropic 冻结评审专项验收（闭合"语义未闭合"）

> 本节专验 v0.2.9 相对 v0.2.8 的闭合点（anthropic 冻结评审 P0/P1），确保契约缺口真闭合。

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| **🔴 P0-1 REPAIR target 已定义**：§7.3 条件5 动作 `mise install <tool>@<remote.latest>` + 顺序说明 REPAIR target 段（覆盖 broken+staging-空/broken+local-ahead 边界）+ §5.3 target 来源 + §8.1 表 REPAIR 行（§7.3/§5.3/§8.1） | spec 文本 + I1 第5行 | I1 第5行 fixture：broken opencode staging 空 → REPAIR，断言 upgrade.json.target==remote.latest | **anthropic P0-1**：原 `<ver>` 未定义，opencode 无本地版本可修回；v0.2.9 统一 remote.latest，matchesTarget 基准闭环 |
| **🔴 P0-2 verified channel schema 一致**：§5.4 示例含 `"channel":"mise"` + §5.9 表 channel 必填（§5.4/§5.9） | spec 文本 + J 节 verified channel 验收 | 见 J 节 verified channel case | **anthropic P0-2**：原示例/表矛盾，Pester 无法机械化；v0.2.9 补示例，自包含 |
| **🟡 P1-1 prerelease-vs-REPAIR 列§14-11**：§14-11 风险声明（不重排，stable-only 后果）（§14-11） | §14-11 文本存在 | 审查 §14 含第 11 项 | **anthropic P1-1**：null 下沉的同构问题；重排冲突 stable-only，列风险正确 |
| **🟡 P1-2 N=10 计数机制落地**：§10.5 计数文件算法 + §5.9 schema + §4 目录 + §8.1 sync 副作用（§10.5/§5.9/§4/§8.1） | spec 文本 + K6 节 | 见 K6 节计数/归零/卸载 case | **anthropic P1-2**：原"已闭合"名实不符；v0.2.9 补方案(a)计数文件 |
| **🟢 P1-3 ALL_REMOTE_FAIL 聚合已声明**：§8 表 ALL_REMOTE_FAIL 行"RATE_LIMITED 与 REMOTE_FAIL 均计入"（§8） | spec 文本 | 审查 §8 行 | 一句话澄清，防实现期分歧 |

---

## O4. v0.2.10 CodeBuddy 审计专项验收（schema/示例一致性 + §7.3 完备性）

> 本节专验 v0.2.10 相对 v0.2.9 的闭合点（CodeBuddy 独立审计 D1–D12），全文字级修订，确保一致性/完备性缺口真闭合。D13（观察项）驳回不入 spec。

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| **🟡 D1 §5.9「全部」行收窄**：`error` 仅 local/remote/upgrade；sync.json 顶层 `name:"sync"`；表补 `entries[].name`（§5.9/§5.5） | spec 文本 + A 节 name/error 断言 | 遍历示例断言 error 字段适用性与 §5.9 表一致 | P0-2 同族未系统扫清，本次扫清 |
| **🟡 D2 fromVersion 类型 string\|null**：§5.9 表 upgrade.json.fromVersion 类型含 null（§5.9） | spec 文本 | 审查 §5.9 行 | REPAIR staging 空 fromVersion=null 与类型表对齐 |
| **🔴 D3 §7.3 条件7/8 互补 + else 兜底**：7=有本轮新鲜→SKIP（仅同轮 re-probe 可达），8=无本轮新鲜→REFRESH（覆盖 stale-but-matching 空洞），else=`RUNTIME_ERROR\|<cli> branch-undefined`；输入清单补 verified.json+current-run.json（§7.3） | spec 文本 + I1 第7/8/else 行 | I1 交叉用例：连续两轮 UPTODATE（上轮凭证存在且 version 匹配但非本轮新鲜）→ 命中条件8 REFRESH（非空洞） | **核心完备性**：原条件7 跨轮死分支 + stale-matching 空洞违反"九分支全覆盖"；D3 闭合 |
| **🟡 D4 §7.2 REPAIR `<ver>`→`<remote.latest>`**：模块表 upgrade 行 mise 动作与 §7.3 条件5/§5.3 对齐（§7.2） | spec 文本 | 审查 §7.2 表 | P0-1 漏改点，模块清单层残留已清 |
| **🟡 D5 计数唯一规则**：fatal 中断→不更新（保持旧值）；仅 sync 完整执行到末步才 +1/归零（§10.5/§8.1） | spec 文本 + K6 D5 case | K6 fatal case：计数到 5 后骨架级 fatal，断言计数不变 | 闭合 §10.5"未跑 sync→归零"与 §8.1"不动"冲突 |
| **🟡 D6 三重约束②可机械化**：`verified.sha256` 非空且 sync 复算 `sourceSha256==verified.sha256`（§5.4） | spec 文本 + K1 | K1 完整性 case | 原"与下载校验值一致"比 exe hash 与 zip hash 必不等，不可实现 |
| **🟡 D7 npm-fallback 时间字段例外**：§5 例外清单含 `opencode-npm-fallback.json`（用 lastUpdatedAt）（§5） | spec 文本 + D 节 | D 节断言 npm-fallback 有 lastUpdatedAt 非 runAt | 原"MUST 带 runAt"违反，补例外 |
| **🟢 D8 FATAL 产出者补 upgrade/verify**：§8 表 RUNTIME_ERROR_FATAL 产出脚本="任何段（骨架级）"+ §8.1 补 probe/upgrade/verify schema-FATAL 行（§8/§8.1） | spec 文本 | 审查 §8/§8.1 表 | upgrade/verify 写 state 文件 schema 校验失败亦 FATAL，原表不全 |
| **🟢 D9 ALL_REMOTE_FAIL 产出者钉死**：由 agent/SOP 聚合判定（非单 CLI 脚本）（§8） | spec 文本 + H3 | H3 case：三 CLI 全败，断言 ALL_REMOTE_FAIL 由 SOP 聚合产出 | probe-remote 每 CLI 独立，单脚本无法知"三全败" |
| **🟢 D10 REMOTE_FAIL 落盘字段全**：assetName/checksumAssetUrl=null, fallbackUsed=false 等必填字段占位（§5.2/§8.1） | spec 文本 + H2 | H2 REMOTE_FAIL case 断言 §5.9 必填字段全在 | 原 §5.9 列必填但落盘语义未声明取值 |
| **🟢 D11 sha256 跨脚本拆分**：upgrade 写 upgrade.json.sha256，verify 复算写 verified.json.sha256（§5.2） | spec 文本 + I2 | I2 case 断言两文件各写各 sha256 且一致 | 原"解压后写 verified.json.sha256"可误读 upgrade 越界 |
| **🟢 D12 §5.8 示例跨版本**：`"0.2.9" vs "0.2.10"`（§5.8） | spec 文本 | 审查 §5.8 示例两侧不同值 | 原同值示例失意义（机械替换所致） |
| **驳回 D13**：观察项——gh/mise 不在审计 shell PATH 属审计局限；"gh 定位方式"属 SOP/实现期，§5 已允许 env 注入，不入 spec 主体 | — | — | 非文档缺陷；实现期 SOP 处理 gh 绝对路径/env 注入 |

---

## P. 待实测项（⚠ 依赖实现期，对齐 §14 知名风险声明）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| ⚠ 反代长期可靠性（§14-2）：反代失效→直连重试一次→仍失败 `DOWNLOAD_FAIL|` | 标记 | 实现期 mock/实测 | 验收口径已定，可靠性待实测 |
| ⚠ PID 沙箱陈锁判定（§14-3）：不确定→保守 `LOCKED|` 不抢锁 | 标记 | 实现期模拟 | Cherry 沙箱 PID 可靠性待实测 |
| ⚠ 极端时钟回拨（§14-8）：runId 匹配优先，runId 缺失 runAt 兜底 | 凭证新鲜度 | 实现期模拟时钟回拨 | 已知边界，待测试覆盖 |
| ⚠ digest 对未来 release 覆盖：当前 v1.18.31 全覆盖，未来 release 若 digest=null 走 fallback | fallback 触发 | 实现期 mock digest=null | [cite:472d3952-2] 旧 asset digest 可能为 null |
| ⚠ prerelease-vs-REPAIR（§14-11）：broken+remote 为 prerelease → TARGET_PRERELEASE 先命中，REPAIR 排不上 | 标记路径 | 实现期 mock remote.latest=prerelease+broken local | stable-only 后果；三 CLI 持续有 stable，概率极低；触发需人工 pin |

---

## 收尾

- 本 checklist 是 **candidate**（候选），与 SPEC-v0.2.10 同阶段，随评审迭代。
- 实现期产出 Pester 骨架时，每条转 `Describe/It` + fixture 生成器 + stdout 捕获 + JSON schema 断言。
- §14 知名风险项（§P）在实现期实测后，若口径变化须回流 spec（架构层）+ 本 checklist（验收层）双更新。
- 版本号：本 checklist 对齐 `SPEC-v0.2.10`；spec 升版时本文件同步升版。
