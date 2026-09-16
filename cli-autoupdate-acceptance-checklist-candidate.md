# CLI 自动升级 验收 checklist（候选）

> **版本**：acceptance-checklist-candidate（对齐 `SPEC-v0.2.7.md` 冻结候选，2026-09-16）。
> **定位**：Executor/测试层产物。SPEC 是 Plan/契约（定义"该做什么"），本 checklist 是验收契约（定义"怎么证明做到了"），**不塞进 spec 主体**（守 spec 的 Plan/契约层定位，spec §15 引用本文件）。
> **骨架来源**：GPT frozen-direction 评审 §3 Checklist A-N（基于 v0.2.6）+ v0.2.7 升级项（P0-1 API digest 主路径、P0-3 失败不覆盖、P1-4 §8.1 marker→exitCode→file 表、P1-5 Canonical Path、N=10）。
> **用法**：Pester 或自写 harness 实现断言。约定 `<cli>` ∈ {claude, codex, opencode}；state 根目录 `D:/AI/Workspace/automatic/CLI-autoupdate/state/`；promotion 入口 `D:/AI/Programs/CLI/<cli>/<cli>.exe`。路径示例用正斜杠（spec §4 Canonical Path 已认可，agent 调 `-File` 用正斜杠）。
> **每条四栏**：条款（spec 节号 + MUST/SHOULD）｜ 可观测证据（json 字段 / stdout 标记 / 文件副作用，锚 §8.1 对照表）｜ 测试用例（输入状态 → 预期标记+exitCode+文件副作用）｜ 判断（设计理由，把推理落盘防上下文压缩丢失）。
> **状态标记**：`[ ]` 待实现断言；`[x]` 已有 fixture/已验证；`⚠` 依赖实现期实测（对齐 §14"已知风险声明"）。

---

## A. 交付物与版本标识（静态验收）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 脚本清单齐全：`cli-common-v0.2.7.ps1`/`archive-state.ps1`/`sync-v0.2.7.ps1`/`probe-local-*.ps1`/`probe-remote-*.ps1`/`upgrade-*.ps1`/`verify-*.ps1`（§7） | 文件存在性（fd/`Test-Path`） | 列工作区根，断言 7 类文件存在 | GPT A 升级到 v0.2.7 文件名；version 字段一致性是回归基线 |
| 脚本版本钉死：共享库与 sync 文件名含 `-v0.2.7`；per-cli 脚本首行 `$ScriptVersion='0.2.7'` + `# SPEC: v0.2.7`（§7.4） | 文件名 + 首行 grep | `rg "^# SPEC: v0\.2\.7"` 各脚本 | 防实现期版本漂移；specVersion 是跨版本追溯锚 |
| 所有 state JSON 顶层 `specVersion:"0.2.7"` + `name`（§5） | JSON 字段 | 遍历 state/*.json 断言两字段 | 跨版本 schema 标识，旧 specVersion 触发 fail-closed |

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
| 时间字段：除 `current-run.startAt`/`*.pin.setAt` 外，local/remote/upgrade/verified/sync MUST 有 `runAt`（ISO UTC）（§5） | JSON 字段 | 遍历断言 | 回应 GPT 4.1 一致性；双时间字段语义不同 |
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
| REMOTE_FAIL 仍落盘：`latest:null, sourceUrl:null, directUrl:null, error:<cause>`（§5.2） | remote.json 字段 | mock 全失败 | 失败也写文件供 upgrade 读 NO_REMOTE |
| 限流识别：403 + `x-ratelimit-remaining:0` → `RATE_LIMITED|<cli>`（§5.2/§8） | 标记（recoverable，exitCode 3） | mock 403+header | 区别普通 REMOTE_FAIL（§9 铁律8） |
| token 安全：MAY 取 `gh auth token`/env，MUST NOT 写 state/log/推送（§5/§9） | 全量 grep token 模式 0 命中 | 跑后搜 state/log/push | token 泄露零容忍 |

### H3 ALL_REMOTE_FAIL（整轮级）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 三 CLI 全 remote fail → probe-remote 末 `ALL_REMOTE_FAIL|`，整轮跳 upgrade/verify 直进 sync（§8） | 标记 + 状态机路径 | mock 三 CLI 全败 | 网断不升级但 sync 全 skip + RUN_STATUS success（如实汇报） |

---

## I. upgrade-<cli>.ps1（核心：§7.3 九分支）

> 方法：fixture 写 local.json + remote.json + verified.json + current-run.json，跑 upgrade，断言 stdout 标记 + 是否写 upgrade.json。

### I0 通用

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| if-elif 顺序严格按表 1→9 命中即止（§7.3） | 标记取编号小者 | 构造同时满足多条件 case | 顺序：远端/格式/策略前提(1-3) > 本地健康(4-5) > 版本比较(6-9) |
| 不升级分支不写不覆盖 upgrade.json（P0-3，§5.3/§8.1） | upgrade.json 不存在/未变 | 跑不升级分支 | GPT P0-3；防失败轮污染 |

### I1 九分支逐条

| # | 条件 | 预期标记 | exitCode | 文件副作用 | 判断 |
|---|---|---|---|---|---|
| 1 | remote.latest==null | `NO_REMOTE|<cli> <cause>` | 0 | 不写 upgrade.json，跳 verify | upgrade 读 latest:null 走此分支 |
| 2 | 版本不可解析 | `VERSION_FORMAT_ERROR|<cli> <raw>` | 0 | 不写，跳 verify | Compare-SemVer incomparable |
| 3 | target prerelease | `TARGET_PRERELEASE|<cli> <v>` | 0 | 不写，跳 verify | stable-only 拒绝 |
| 4 | healthy=false 且 probe-error | `PROBE_ERROR|<cli> <reason>` | 0 | 不写，跳 verify | 不重装（probe 偶发超时） |
| 5 | healthy=false 且 broken | `REPAIR|<cli> <reason>` | 11 | 写 upgrade.json，进 verify | 强制重装 |
| 6 | local<remote 且 stable | `ACTIONABLE|<cli> <from>-><to>` | 11 | 写 upgrade.json，进 verify | 主升级路径 |
| 7 | local==remote 且有本轮新鲜凭证 | `UPTODATE_SKIP|<cli> <v>` | 0 | 不写，跳 verify | 真幂等 |
| 8 | local==remote 但凭证缺失/verified.version≠local | `UPTODATE_REFRESH|<cli> <v>` | 0 | 不写 upgrade.json，仍跑 verify | F1 seed 兜底；刷新凭证 |
| 9 | local>remote | `LOCAL_AHEAD|<cli> <local> > <remote>` | 0 | 不写，跳 verify | 不自动降级，显式报告 |

### I2 opencode 下载完整性（§5.2，v0.2.7 digest 主路径）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 下载 zip 后 MUST 校验大小 > 1MB（§5.2） | DOWNLOAD_FAIL cause | 构造 <1MB | 防半下载/stub |
| **digest 主路径 MUST**：API digest 存在 → 下载后计算 SHA256 与 `expectedSha256` 比对；不匹配 `DOWNLOAD_FAIL|<cli> digest-mismatch`（§5.2） | 标记 + verified.sha256 | mock digest 不匹配 | P0-1 采纳；digest 无需额外下载 checksum 文件（省一跳） |
| digest 不可用 → checksum asset 存在 MUST 下载校验；不匹配 `DOWNLOAD_FAIL|<cli> checksum-mismatch`（§5.2） | 标记 | mock digest=null + 有 checksum | fallback 第一级 |
| digest+checksum 均无 → SHOULD 双 hash（反代+直连独立下载 SHA256 一致才接受）；不一致 `DOWNLOAD_FAIL|<cli> dual-hash-mismatch`（§5.2） | 标记 | mock 两源不一致 | fallback 末级；检出反代投毒 |
| MAY single-source（直连不通仅反代 + `integrityNote:single-source`，记 sync.json.entries）（§5.2） | integrityNote=single-source | mock 直连不可达 | 偏离须记录 |
| 解压后目标 exe MUST 计算 SHA256 写 verified.json.sha256（§5.2） | verified.sha256 | 跑成功 case | 证据链数据源 |
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
| `RUNTIME_ERROR|<cli>` 不覆盖旧 verified.json（§8.1） | 旧文件未变 | 触发异常 | 失败不污染 |

---

## K. sync-v0.2.7.ps1（晋升闸 + 证据链 + 异常隔离）

### K1 三重约束（晋升闸）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| 仅当 verified 满足①新鲜度（runId==current-run.runId 或 runAt≥startAt）②完整性（opencode sha256 非空且与下载校验一致）③pin 未冲突，才 copy（§5.4/原则4） | sync.json entries.action | 构造三条件各不满足 case | 任一不满足 D 盘不动 |
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

## P. 待实测项（⚠ 依赖实现期，对齐 §14 知名风险声明）

| 条款 | 证据 | 测试用例 | 判断 |
|---|---|---|---|
| ⚠ 反代长期可靠性（§14-2）：反代失效→直连重试一次→仍失败 `DOWNLOAD_FAIL|` | 标记 | 实现期 mock/实测 | 验收口径已定，可靠性待实测 |
| ⚠ PID 沙箱陈锁判定（§14-3）：不确定→保守 `LOCKED|` 不抢锁 | 标记 | 实现期模拟 | Cherry 沙箱 PID 可靠性待实测 |
| ⚠ 极端时钟回拨（§14-8）：runId 匹配优先，runId 缺失 runAt 兜底 | 凭证新鲜度 | 实现期模拟时钟回拨 | 已知边界，待测试覆盖 |
| ⚠ digest 对未来 release 覆盖：当前 v1.18.31 全覆盖，未来 release 若 digest=null 走 fallback | fallback 触发 | 实现期 mock digest=null | [cite:472d3952-2] 旧 asset digest 可能为 null |

---

## 收尾

- 本 checklist 是 **candidate**（候选），与 SPEC-v0.2.7 冻结候选同阶段，随评审迭代。
- 实现期产出 Pester 骨架时，每条转 `Describe/It` + fixture 生成器 + stdout 捕获 + JSON schema 断言。
- §14 知名风险项（§P）在实现期实测后，若口径变化须回流 spec（架构层）+ 本 checklist（验收层）双更新。
- 版本号：本 checklist 对齐 `SPEC-v0.2.7`；spec 升版时本文件同步升版。
