## 版本历史

### 目录
- [v0.1](#v0-1)
- [v0.2](#v0-2)
- [v0.2.1](#v0-2-1)
- [v0.2.2](#v0-2-2)
- [v0.2.3](#v0-2-3)
- [v0.2.4](#v0-2-4)
- [v0.2.5](#v0-2-5)
- [v0.2.6](#v0-2-6)
- [v0.2.7](#v0-2-7)
- [v0.2.8](#v0-2-8)
- [v0.2.9](#v0-2-9)
- [v0.2.10](#v0-2-10)
- [v0.2.11](#v0-2-11)
- [v0.2.12](#v0-2-12)
- [v0.2.13](#v0-2-13)
- [v0.2.14](#v0-2-14)
- [v0.2.15](#v0-2-15)
- [v0.2.16](#v0-2-16)
- [v0.2.17](#v0-2-17)
- [v0.2.17-rc1](#v0-2-17-rc1)
- [v0.2.17-rc2](#v0-2-17-rc2)
- [v0.2.18-rc1](#v0-2-18-rc1)
- [v0.2.18-rc2](#v0-2-18-rc2)

---

<a id="v0-1"></a>
### v0.1
- 日期：2026-09-16
- 摘要：初版：混合架构
- 文件：`SPEC-v0.1.md`

<a id="v0-2"></a>
### v0.2
- 日期：2026-09-16
- 摘要：运行锁、标记协议、原子写入、fail-closed、opencode 回退
- 文件：`SPEC-v0.2.md`

<a id="v0-2-1"></a>
### v0.2.1
- 日期：2026-09-16
- 摘要：behind 下移 upgrade、runId 锁、无差别调用、SOP 层
- 文件：`SPEC-v0.2.1.md`

<a id="v0-2-2"></a>
### v0.2.2
- 日期：2026-09-16
- 摘要：Zoo 审计复核：术语表/版本历史/测试策略/版本格式验证/SOP 错误场景；驳回误读意见
- 文件：`SPEC-v0.2.2.md`

<a id="v0-2-3"></a>
### v0.2.3
- 日期：2026-09-16
- 摘要：CodeBuddy 审计复核：F1–F6（凭证生命周期/标记闭合/错误语义分层/数字源/REPAIR/锁空转）
- 文件：`SPEC-v0.2.3.md`

<a id="v0-2-4"></a>
### v0.2.4
- 日期：2026-09-16
- 摘要：GPT 治理评审复核：供应链强化+ZipSlip+pin 语义重写+证据链+恢复手册+RFC2119+schema 表+状态机图
- 文件：`SPEC-v0.2.4.md`

<a id="v0-2-5"></a>
### v0.2.5
- 日期：2026-09-16
- 摘要：anthropic 治理评审复核：schema 总表补全、sha256 SHOULD 对齐、sync 异常隔离硬约束、behind if-elif 优先级、archive 保留 30 轮、GitHub 限流缓解+RATE\_LIMITED、凭证新鲜度 runId 双判据、回退方向澄清、晋升闸定义补 pin、迁移 checklist
- 文件：`SPEC-v0.2.5.md`

<a id="v0-2-6"></a>
### v0.2.6
- 日期：2026-09-16
- 摘要：GPT 二次评审复核（对 v0.2.4）：时间字段例外说明、LICENSE 事实矛盾修正（仓库实有 AGPL-3.0）、威胁模型声明、checksum 解析 MUST 规则、state 文件 runId 关联（SHOULD）、斜杠约定澄清；驳回"路径插空"（渲染误读）与"交付物三层矛盾"（阶段状态）
- 文件：`SPEC-v0.2.6.md`

<a id="v0-2-7"></a>
### v0.2.7
- 日期：2026-09-16
- 摘要：GPT 评审复核（对 v0.2.6）：P0-1 GitHub API asset digest 主路径 MUST（gh api 实测验证）+ expectedSha256 schema 字段（保留 checksumAssetUrl 作 fallback）；P0-2 §14-1/6 实测闭合、§14-5 N=10、真未知风险不伪关闭（驳回"全部关闭"）；P0-3 verify 失败不写新鲜 runId 凭证；P1-4 marker→exitCode→文件副作用表（§8.1）；P1-5 Canonical Path 代码块；Checklist A-N 引为独立验收交付物
- 文件：`SPEC-v0.2.7.md`

<a id="v0-2-8"></a>
### v0.2.8
- 日期：2026-09-16
- 摘要：anthropic 评审复核（对 v0.2.7）：P0 §7.3 分支优先级歧义——`local.version==null` 不计入条件2"不可解析"，下沉至条件4/5，Compare-SemVer 对 null 由调用方前置判空（否则首次 seed 卡死）；P1 §5.4 `matchesTarget` 各分支比较基准（ACTIONABLE/REPAIR 对 `upgrade.json.target`，UPTODATE\_REFRESH 对 `local.version`）；P1 §5.8 specVersion 不匹配处理（不作本轮决策依据消费、非 fatal、本轮覆盖迁移、checklist A 节断言据此修正）；P2 §14-10 锁获取与 current-run.json 写入间崩溃（fail-closed 覆盖，行为已定）
- 文件：`SPEC-v0.2.8.md`

<a id="v0-2-9"></a>
### v0.2.9
- 日期：2026-09-16
- 摘要：anthropic 评审复核（对 v0.2.8），闭合"文本已写但语义未闭合"缺口：P0-1 REPAIR target 语义——统一 `target=remote.latest`（与 ACTIONABLE 对齐，顺便修到最新），覆盖 broken+opencode-staging-空/broken+local-ahead 边界，§5.3 target 来源闭环；P0-2 verified.json channel schema 矛盾——§5.4 示例补 `"channel"`（自带通道，sync 无需跨文件判 sha256 MUST/SHOULD）；P1-1 prerelease-vs-REPAIR 优先级边界列 §14-11 风险（stable-only 后果，不重排）；P1-2 N=10 计数机制——新增 `opencode-npm-fallback.json`（consecutiveSyncSuccess 计数，sync 末步更新，达 10 卸载置 uninstalled=true 幂等）；P2 P1-3 ALL\_REMOTE\_FAIL 聚合——RATE\_LIMITED 与 REMOTE\_FAIL 均计入
- 文件：`SPEC-v0.2.9.md`

<a id="v0-2-10"></a>
### v0.2.10
- 日期：2026-09-16
- 摘要：CodeBuddy 独立审计复核（对 v0.2.9），扫清"schema 总表↔示例↔正文"三方一致性 + §7.3 分支完备性（全文字级修订，不涉架构）：P1 D1 §5.9「全部」行收窄（error→local/remote/upgrade，name 补 sync，表补 entries\[].name）；P1 D2 fromVersion 类型 string→string\ null；P0 D3 §7.3 条件7/8 改互补（7=有本轮新鲜→SKIP 仅同轮 re-probe 可达，8=无本轮新鲜→REFRESH 覆盖 stale-but-matching 空洞）+ else 兜底 + 输入清单补 verified/current-run；P1 D4 §7.2 REPAIR `<ver>`→`<remote.latest>`；P1 D5 §10.5 计数唯一规则（fatal 中断→不动，仅 sync 完整执行才 +1/归零）；P1 D6 §5.4 三重约束②改 sync 可机械判定（sourceSha256==verified.sha256）；P1 D7 §5 时间字段规则补 npm-fallback 例外（用 lastUpdatedAt）；P2 D8 §8 FATAL 产出者补 upgrade/verify（schema 校验失败）；P2 D9 ALL\_REMOTE\_FAIL 产出者钉死（agent/SOP 聚合，非单 CLI 脚本）；P2 D10 REMOTE\_FAIL 落盘补 assetName/checksumAssetUrl/fallbackUsed；P2 D11 §5.2 策略5 拆 upgrade/verify 各写各 sha256；P2 D12 §5.8 示例改跨版本值。驳回 D13（观察项，gh 定位属 SOP/实现期，§5 已允许 env 注入）
- 文件：`SPEC-v0.2.10.md`

<a id="v0-2-11"></a>
### v0.2.11
- 日期：2026-09-16
- 摘要：GPT 独立审计复核（对 v0.2.10），契约级补充（不涉架构）：P1 P0-1（降级采纳 option A）§8 钉死"成功判定各层只看 `RUN_STATUS` 标记，exitCode 非权威 MUST"（定时任务/SOP 层不依 exitCode 判成功），驳回 option B（exitCode 表重构＝过度工程）；P0-2（降 P1 采纳）§6 run.lock 补 `processStartTimeUtc`（SHOULD）+ 陈锁接管加 PID+startTime 双校验（spec 本已 fail-closed 安全，误接管→拒→`LOCKED`＝假阴性方向，故降 P0→P1，非堵安全漏洞）；P1 P0-3 §7.1 `Compare-SemVer` 正规化规则补全（缺 patch/4+段→incomparable，build→忽略非 incomparable，含 `-`→prerelease）+ 12 条测试表；P2 P1-1 §5.2/§17 删内部 cite 占位符 + "2025-06-03 起"软化为实测措辞；P2 §0 补硬编码路径理由（减变量提可验收性）。驳回 P1-2（cause 全枚举＝过度工程，运行时 cause 开放集合不可全枚举，spec 已枚举关键 cause）；§15 补 PID 重用/锁误接管模拟用例（时钟回拨/specVersion 漂移已覆盖）
- 文件：`SPEC-v0.2.11.md`

<a id="v0-2-12"></a>
### v0.2.12
- 日期：2026-09-16
- 摘要：anthropic 独立审计复核（对 v0.2.11），闭合两处此前审计盲区（§6 锁接管 + schema↔更新逻辑文字对不上，全契约级修订）：P0-1（采纳，**修正 v0.2.11 引入的回归**）§6 陈锁接管 PID+startTime 双校验逻辑写反——原"StartTime 匹配→确认已死→接管"会导致误接管存活进程锁（数据损坏级），改伪代码钉死（未命中→已死可重争；命中且 StartTime 匹配→仍存活 LOCKED；命中但不匹配→PID 被复用可重争）；P0-2 `processStartTimeUtc` 升 MUST + 字段缺失 fallback（保守 LOCKED）；P1-3 §8.1 `ALL_REMOTE_FAIL` 行脚本列改"agent/SOP 聚合"、exitCode 标"不适用"（与 §8 D9 对齐）；P1-4 §7.1 prerelease 排序删"不强制唯一性"矛盾措辞，改采 SemVer 2.0.0 §11 precedence；P1-5 §10.5/§5.9 `consecutiveSyncSuccess` 卸载后冻结定格 10（闭合"0-10"声明与"+=1 不封顶"矛盾）；P2-1 sync.json 顶层补 `runStatus`；P2-2 §9 汇报模板加 pin mismatch SHOULD 提醒；P2-3 DISK\_FULL/EXE\_LOCKED 给 SHOULD 默认阈值/检测方式；P2-4 §5.2 checksum 同名 hash 冲突判 `checksum-mismatch` fail-closed；P2-5 §16 加同日多轮说明；P2-6 §6 锁接管以伪代码落 spec
- 文件：`SPEC-v0.2.12.md`

<a id="v0-2-13"></a>
### v0.2.13
- 日期：2026-09-16
- 摘要：CodeBuddy 独立审计复核（对 v0.2.12），闭合 §6 伪代码两处 fail-open 缺口 + 判据/枚举/表述对齐（全契约级修订，11 项意见全部采纳）：P0 CB-P1-1 §6 catch 异常分型——仅 `ProcessCommandException`（PID 无活跃进程）判死→TAKEOVER，`ParameterBinding*`（锁内 pid null/非法，锁半写场景）/权限拒绝→未证明死亡→LOCKED（实测复现三类异常分型）；P0 CB-P1-2 §6 时间比较钉死——写侧 UTC 'o' round-trip（tick 精度）MUST + 读侧 Parse(RoundtripKind)+归一+Ticks 比较 MUST + 锁值格式校验前置（本地偏移/精度截断/解析失败→LOCKED；实测 string 形态 -eq 同一时刻恒 False）；P1 CB-P2-1 §10.5/§5.9 uninstalled=true 后完全冻结（失败不归零，定格 10，选审计方案 b）；P1 CB-P2-2 §5.5 runStatus 语义收窄（sync 本次执行终态）+"本轮完整成功"须联判 runId + fatal 落盘形态定义（sync 异常分支原子写入 failed 版）+ 废除"单文件自洽/无字段=腰斩"过强声明；P1 CB-P2-3 SYNC\_TARGET\_LOCKED 落盘钉死 action=target-locked + reason 必填（§8.1/§5.9 对齐）；P1 CB-P2-4 凭证新鲜度收紧（runId 唯一必要条件，仅字段缺失回退 runAt；§1-11/§5.4/§5.8/§7.3/§14-8/§17 六处对齐）；P2 CB-P3-1 pin 连续 mismatch 数据源=archive 回溯最近 N 轮 sync.json entries；P2 CB-P3-2 分支计数统一四分支+扩充断言集；P2 CB-P3-3 §0 仓库内容声明按实修正；P2 CB-P3-4 Codex 大小写注（实机大写 C，Windows 不敏感等价）；P2 CB-P3-5 checksum 路径期望 hash 落 expectedSha256 + 来源可机械区分（assetDigest==null && expectedSha256!=null）
- 文件：`SPEC-v0.2.13.md`

<a id="v0-2-14"></a>
### v0.2.14
- 日期：2026-09-16
- 摘要：Cherry 独立审计复核（对 v0.2.13），契约层补全与措辞澄清（6 项意见：采纳 3、部分采纳 1、驳回 1\[实测证伪]、固化其验证要求 1，无 §6 判定方向变更）：P0 CH-P1-1 run.lock 存储格式钉死 JSON + 纳入 §5.9 schema 总表（runId/start/beat/pid/processStartTimeUtc 五字段；§4/§5/§6 三处同步），CB-P1-2 格式契约获 schema 级落点；P0 CH-P1-2 archive-state 补成功标记 `ARCHIVE_OK\ <runId>`（§8 表/§8.1/§9 状态机三处同步，闭合"唯 archive 成功无 `*_OK\ `"不对称——agent 判 OK 依据此前悬空：exitCode 非权威 + 沉默与崩溃不可区分）；P2 CH-P1-3 驳回（PS 7.6.4 实测证伪）——DateTime 'o' 恒 7 位小数（整秒输出 `.0000000`，与 Kind 无关）、DateTimeOffset 亦然，写读两侧自洽，Cherry 所虑"整秒永不 TAKEOVER"断档不存在；§6 固化实测结论 + MUST NOT 以 DateTimeOffset 序列化锁时间（offset 后缀非 Z，恒触发保守 LOCKED）；CH-P2-1 §9 注明 re-probe 可达性（UPTODATE\_SKIP 仅同轮穿插可达，标准单轮不可达，re-probe 属 SOP 可选步骤）；CH-P2-2 §8.1 failed 行计数措辞澄清（冻结态"更新"=no-op 保持定格 10）；CH-P2-3 §14 注明历史连续编号跨组不连续（驳回重编号方案：§14-N 为历轮审计与正文交叉引用锚点）
- 文件：`SPEC-v0.2.14.md`

<a id="v0-2-15"></a>
### v0.2.15
- 日期：2026-09-17
- 摘要：GPT 独立审计复核（对 v0.2.14），7 项意见：采纳 5、部分采纳 1、驳回 1（全契约层补全/消歧，不改判定语义、不涉 §6 锁逻辑）：GPT-P0-1 mise staging 路径省略号消歧义（§2 精确化为 `E:\Users\WIN_11\AppData\Roaming\CherryStudio\Toolchain\mise\installs\`——实测复核 2026-09-17〔mise 根/installs/claude 2.1.273/codex 0.154.0/mise.exe/npm prefix 均在盘〕+ legacy verified 2026-09-16；§4 Canonical Path 补行；§7.1 新增 Cherry mise 环境契约〔getter 常量精确值 + MISE\_\* 七键 + "mise 子进程 MUST 带 env / 文件扫描不依赖 env" + ExeRelPath 实测结构〔claude=`claude.exe`、codex=`bin\codex.exe`〕+ 失败沿既有 \`UPGRADE\_FAIL `/`REMOTE\_FAIL `上报不新增标记〕；§5.1 补 mise 空目录语义同 opencode staging 空 → REPAIR）；GPT-P0-2 §8 标记行语法 MUST 六条（独占行/行首/首个` `切分/枚举约束/除 RUN_STATUS 外单` `/日志行禁标记形态 + agent 解析规则）；P1 GPT-P0-3 current-run.name 任务名语义注记强化（§5.6 注 + §5.9 独立 schema 行〔固定 ` <cli-autoupdate>`、验收断言 MUST 分开〕；**驳回改名 ` taskName`**——name 跨文件统一表达"文件归属者"，改名引入 schema 特例、值本身不可混淆、无机械验收收益）；GPT-P1-1 时间字段格式契约统一（全部 ISO 时间字段 UTC 'o' round-trip = 恒 7 位小数 + ` Z`；比较 MUST DateTime/Ticks 层；MUST NOT DateTimeOffset——与 §6 锁字段同源实测 CH-P1-3；§5 总则 + §5.9 表注 + §7.1 助手 + §15 断言四处同步）；P2 GPT-P1-2 版本格式突变处置模板（§9 SOP 错误场景示例 + §14-12 已知风险声明：fail-closed 持续不升级 + 人工介入路径）；P2 GPT-P1-3 驳回（§8 单页接口总览表——信息零新增、并列事实源易漂移，以 §8.1 交叉索引句替代）；P2 GPT-§4 采纳（§5.10"未来增强"入口：release attestations/`gh release verify-asset\` 路线，非本版本范围）
- 文件：`SPEC-v0.2.15.md`

<a id="v0-2-16"></a>
### v0.2.16
- 日期：2026-09-17
- 摘要：anthropic 独立审计复核（对 v0.2.15），16 项意见：采纳 15、驳回 1（D1——审计对 §14 编号分布的事实声明错误；驳回有真实依据）。全为契约层补全/消歧/防御性补全，不改判定语义主轴（仅 B1 收紧 TARGET\_PRERELEASE 判据、方向更安全；§6 锁逻辑仅补 StartTime 异常防护、不变更判定方向）：**P1 采纳 4**——A1 §6 伪代码 `$proc.StartTime` 读取未在 try/catch 内（异常分型扩展，与 Get-Process 调用异常同等对待 → LOCKED）；B1 §7.3 条件3 TARGET\_PRERELEASE 按通道分流（github-binary 优先 API `prerelease` 字段，mise 保留字符串启发式，§14-11 补更真实触发场景）；E1 §10.5 npm uninstall 失败处置（MUST 检查退出码，仅成功才置 true）；F1 §10.5 D5 计数规则对齐 §8.1 细粒度表述（fatal 前 opencode 已处理→更新，否则不动）。**P2 采纳 11**——A2 §5.4 mise 通道完整性约束②语义补全；C1 §6 30min 停摆窗口表述分两类（进程终止 vs 进程挂起）；E2 §10.5 npm 调用显式用 `Get-NpmPrefix()` 不依赖 PATH；G1 §5.1 healthy/healthDetail 相关性不变量 MUST + 回读校验；H1 §7.1 mise.exe 跨盘跨用户成因说明；H2 §7.2 `mise upgrade <tool>@latest` 语法待实测标注；H3 §6 续锁"段"=每个脚本调用粒度；H4 §5 Authorization 头脱敏 MUST；H5 §5.2 digest 非 sha256 前缀→视为不可用回退；H6 §5.5/§5.9 entries\[].reason 受控枚举（skip 类三值）；H7 §13 项7 .old/ 复用判定 MUST 记录。**驳回 1**——D1（§14 编号冲突）：审计称已闭合列表含 2/3、与已知风险 2/3 冲突——**事实核查证伪**：实际 §14 已闭合列表编号 {1,4,5,6,7,9}（不含 2/3），与已知风险 {2,3,8,10,11,12} 不相交；审计未对 §14 文本逐项核实即下结论。**严重度评级调整**：废除 //红绿灯分级，恢复 P0/P1/P2 评级（用户 2026-09-17 指示）
- 文件：`SPEC-v0.2.16.md`

<a id="v0-2-17"></a>
### v0.2.17
- 日期：2026-09-17
- 摘要：GPT 独立审计复核（对 v0.2.16），9 项意见：采纳 5、部分采纳 1、轻量采纳 1、驳回 2（全契约层字段/枚举/消歧补全，不改判定语义、不改 §6 锁逻辑）：P1 3.1 remote.json 补 `prerelease` 字段落盘（闭合 §7.3 B1 与 §1 原则2 数据固化契约不一致——B1 优先信任 API prerelease 但字段未持久化，upgrade 要么重打 API 要么退回启发式）；P2 3.2 expectedSha256（zip）与 upgrade/verified sha256（exe）对象消歧（采纳加说明不改名——改名 expectedAssetSha256 破坏多处历史引用+checklist 断言+schema 稳定性=过度工程；驳回可选 zipSha256=额外 schema 字段，integrityNote 已够审计）；P2 3.3 integrityNote 补 `sha256-missing-skip`（mise 通道 sha256 缺失可追溯）；P2 4.1 reason 统一句式（采纳 copy→reason=null；驳回 unknown/other 保底——skip 枚举已覆盖三类已定义场景，保底破坏"reason∈枚举可机械断言"+掩盖 bug=过度工程）；P2 4.2 healthy >1MB 阈值补"三款 CLI 经验值"注；P2 4.3 §9 铁律补第9条"只信 RUN\_STATUS"（作铁律补条非 §8 摘要重复，避免双源漂移）；P2 5.3 H4 补"异常对象/HTTP 响应对象 MUST NOT 直接序列化入日志"（PowerShell catch 后 \`$\_ Out-String\` dump 请求头实战坑）；驳回 5.1/5.2（实现期 helper 建议，§5.8/§7.1/§15 已覆盖，spec=Plan/契约层不写实现细节，Executor 自治）
- 文件：`SPEC-v0.2.17.md`

<a id="v0-2-17-rc1"></a>
### v0.2.17-rc1
- 日期：2026-09-17
- 摘要：CodeBuddy 独立审计修正轮（对 v0.2.17，`SPEC-v0.2.17-codebuddy-review.md`；5 项发现全部落地）：N1（P2）prerelease 补入 §5.2 REMOTE\_FAIL 落盘语义/§7.2 probe-remote 行/§8.1 \`REMOTE\_FAIL `行三处"必填字段全部落盘"清单；N2（P3）处置计数"采纳 6"→"采纳 5"（头部+§16 两处同错）；N3（P3）§15 断言②改写（完整性②实际执行时 MUST NOT 写`sha256-missing-skip`）+ §5.4 A2 消歧"任一侧字段缺失"；N4（P3）4.1 驳回理由弱化（"已闭合覆盖全场景"→"已覆盖三类已定义场景"）+ §5.5/§5.9 补完整性②不满足 entry 形态（`action="copy"`+`ok=false`+`integrityNote="sha256-mismatch"`，D 盘 ` .previous`恢复，不属 skip）+ §15 补断言⑥；N5（P3）§13-7 脚本版本残留`-v0.2.16`→`-v0.2.17\`。另按用户 2026-09-17 指示移除全文版本收敛阶段自评类表述（§16 历史轮 v0.2.7/v0.2.8/v0.2.9/v0.2.12 四行 + §15 checklist 产出时机 1 处，改"评审通过后产出"；§10.5 计数器"完全冻结"等技术语义不变）
- 文件：`SPEC-v0.2.17-rc1.md`

<a id="v0-2-17-rc2"></a>
### v0.2.17-rc2
- 日期：2026-09-17
- 摘要：复审修正轮（对 rc1，据复审报告 `SPEC-v0.2.17-rc1-codebuddy-review-codebuddy-RE-review.md`；R1–R6 全部闭合）：R1（P1）`sourceSha256` 语义钉死为 sync copy 前复算的 staging exe hash（§5.4 ②/A2 显式判据式/sha256 行、§5.5、§5.9、§17 五处同步，消除"凭证 sha256 直抄"读法与 A2 第三义）；R2（P2）新定 `SYNC_INTEGRITY_FAIL\ <cli> <cause>` recoverable 标记（§8 表/异常覆盖/§8.1/§9/§15 断言⑥ stdout+entry 双向 + 端到端第十场景/§14-13 已闭合），§5.5"实现期定义"边界句移除；R3（P3）判定时点钉死 copy 前 + 失败形态 entry 字段取值定义（§5.5）；R4（P3）§10.3 补 `.previous` 边界句、§5.5 引用改机制引用+自述兜底；R5（P3）§5.2/§7.2/§8.1 三处清单补 channel/assetName 与口径声明；R6（P3）§4 "本文件"指针改 rc2。判定语义主轴/§6 锁逻辑/§7.3 九分支结构不动
- 文件：`SPEC-v0.2.17-rc2.md`

<a id="v0-2-18-rc1"></a>
### v0.2.18-rc1
- 日期：2026-09-17
- 摘要：CodeBuddy 独立审计修正轮（对 v0.2.17-rc2，`SPEC-v0.2.17-rc2-codebuddy-review.md`；W1–W6 六项发现独立评估后全部采纳）：W1（P2）`SYNC_COPY_FAIL\ <cli> <cause>` 定名（sync 段 CLI 级 copy 失败，cause ∈ io/bytes-mismatch/previous-backup），承接 §7.2 L510 四类 copy 失败中 IO 错误/字节复核不过/`.previous` 备份失败（rc2 R2 仅闭合 sha256 完整性②子情形），§8 表/§8 异常覆盖/§8.1/§9/§5.5 entry 形态/§14-14/§15 断言⑦同步；W2（P3）§5.5 失败形态 entry 的 `sourceSha256`/`targetSha256`/`previousSha256` 取值钉死（`sourceSha256`=复算值、`targetSha256`=null、`previousSha256`=null）；W3（P3）§8.1 补 sync 脚本级退出码判定规则（脚本实际退出码由末步 `RUN_STATUS` 行决定，表中 sync 段各行 exitCode 为语义码）；W4（P3）§15 端到端 re-probe 明确计入十场景；W5（P3）§14 头部来源清单补 CodeBuddy v0.2.17（N1–N5）/rc1（R1–R6）/RE-Review；W6（P3）§5.2 清单口径措辞精确化（remote.json 探测字段两通道通用）。判定语义主轴/§6 锁逻辑/§7.3 九分支结构不动
- 文件：`SPEC-v0.2.18-rc1.md`

<a id="v0-2-18-rc2"></a>
### v0.2.18-rc2
- 日期：2026-09-17
- 摘要：trae 独立审计修正轮（对 v0.2.18-rc1，`SPEC-v0.2.18-rc1-trae-review.md`；13 项发现独立复核后采纳 12、驳回 1）：T1（P1）§14 已闭合清单恢复 rc2 历史连续编号 {1,4,5,6,7,9,13,14}（rc1 误重排为 {1..8} 违反自身"保留不重排"规则，与已知风险 2/3/8 撞号、§14-6 自引失准、正文活锚 §14-1/10/11/12 全部指错对象），§14-14 内部引用同步 §14-13；T2（P1）§9 推送策略 sha256 禁令收窄为敏感凭证（token/Authorization 类），sha256 明确为证据链组成部分按 §5.5/模板 3 正常写入与推送（消除与 §1 原则8/§5.5/§9 模板3/§11 的 MUST 级冲突）；T3（P1）§7.2 骨架级失败清单收窄，锁争取/续取失败归 `LOCKED|`（§8 表 RUNTIME_ERROR_FATAL 行同步），消除与 §6/§8/§9 铁律7 的双标记冲突；T4（P2）§5.5 补 already-current 机械判据（D 盘 exe 复算 sha256 == sourceSha256 → SYNC_SKIP|already-current，pin/非 pin 统一，防稳态轮空翻新 copy 卡死 §10.5 npm 卸载目标），§5.7 补交叉引用；T5（P3）§8.1 补 UPTODATE_REFRESH 行 + 未列标记兜底语义注（覆盖各段 LOCKED/PARSE_ERROR/STATE_MISSING 副作用行缺失）；T6（P3）§5.2 回退方向说明 standalone→single-source 与权威枚举对齐；T7（P3）§16 术语表"标记行语法"行未转义竖线符改写（§7.2 probe-remote 单元格同类问题顺带修复）；T8（P3）current-run.json name 字面值钉死 `cli-autoupdate`（不含角括号，§5.6 注/§5.9/示例三处）；T9（P3）§9 状态机段B/段C 补 `LOCKED|` fatal 出口；T10（P3）§7.2 ACTIONABLE 实测断言扩展（@latest 实装版本 MUST == remote.latest，不等则改 mise install --force）；T11（P3）§5.9 entries[].ok 非 copy 条目 MAY 省略或 null；T13（P3）§5.5 补 summary 四计数口径定义 + entries 覆盖三 CLI + 示例自洽修正（failed=0、补 claude skip 条目）。**驳回 1**——T12（头部规则1 与版本历史边界）：审计所称"§16 版本历史"在被审计文件中不存在（版本历史已按用户规则移至 `.version-history/`，正文 §16 为术语表），所指冲突对象缺失，驳回不成立。判定语义主轴/§6 锁逻辑/§7.3 九分支结构不动
- 文件：`SPEC-v0.2.18-rc2.md`

### 版本历史日期说明

> **v0.2.12 P2-5（版本历史日期说明）**：v0.1–v0.2.14 标注 2026-09-16、v0.2.15/v0.2.16/v0.2.17 标注 2026-09-17——v0.1–v0.2.14 系同日跨模型审计密集收敛（设计日），v0.2.15/v0.2.16/v0.2.17 为次日复核轮（GPT 审 v0.2.14→产 v0.2.15；anthropic 审 v0.2.15→产 v0.2.16；GPT 审 v0.2.16→产 v0.2.17；CodeBuddy 审 v0.2.17→产 v0.2.17-rc1，同日修正轮；CodeBuddy RE-Review 复审 rc1 审计报告→据其 R1–R6 产 v0.2.17-rc2，同日修正轮；CodeBuddy 审 v0.2.17-rc2→据其 W1–W6 产 v0.2.18-rc1，同日修正轮；trae 审 v0.2.18-rc1→据其产 v0.2.18-rc2，同日修正轮）。日期列精度为"日"，外部审计者如需迭代节奏，可按版本号顺序（每轮一行）追溯；后续进入实现期的 SOP/脚本版本将带时分。
