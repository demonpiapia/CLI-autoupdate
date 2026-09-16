# SPEC-v0.2.2 审计复核意见书（reject）

> **文件**：`SPEC-v0.2.2-reject.md`（2026-09-16）
> **对象**：Zoo 对 `SPEC-v0.2.1.md` 的审计报告（`SPEC-v0.2.1-Zoo-review.md`，17 条：C1–C3 / M1–M5 / m1–m5 / i1–i4）
> **动作**：据用户指示独立判断审计结果，修订 spec 并迭代为 v0.2.2（另存 `SPEC-v0.2.2.md`），本文件记录逐条采纳/驳回理由。

---

## 核心结论

Zoo 审计报告**整体不成立**——审计者没有真正读 `SPEC-v0.2.1.md` 的实际内容。审计引用的章节号与 v0.2.1 实际章节**完全对不上**：

| 审计引用 | 审计声称该节内容 | v0.2.1 实际章节内容 |
|---|---|---|
| "第 7.1 节 更新流程" | 先备份旧版本→下载新版本→解压替换 | §7.1 共享库 cli-common（Invoke-Proc/Compare-SemVer 等） |
| "第 5 节 配置文件" | config.json（security/update/logging 字段） | §5 数据契约 JSON schema（state/*.json，无 config.json） |
| "第 6 节 安装流程" | 安装步骤 | §6 运行锁模型（runId ownership） |
| "第 8 节 目录结构" | 缺锁/日志/临时目录 | §8 机器状态标记协议 |
| "第 10.2 节 签名验证" | 签名验证 | §10.2 opencode github-binary 回退（无签名验证） |
| "第 11 节 使用示例" | 使用示例 | §11 可追溯 |
| "第 12 节 实施计划" | 实施计划 | §12 与参照系差异 |
| "第 13 节 附录" | 附录 | §13 v0.2.1 迁移项 |

审计者把本项目当成了**通用 CLI 自动更新软件产品**（带 config.json、`cli update` 命令、跨平台、许可证、贡献指南、RSA 签名验证），而本项目实际是 **Cherry 定时任务驱动、agent 编排、PowerShell 7 模块化的三个固定 CLI（claude/codex/opencode）个人维护流程**——无 config.json、无用户命令、仅 Windows、无许可证/贡献、不做 RSA 签名。审计按"通用产品"提的多数要求与项目实际形态、范围、运行环境不符。

基于误读/范围误解的多数意见**驳回**（附真实依据）；少数有合理内核的**采纳**。v0.2.2 已在相关章节补"已覆盖"显式说明，使审计者下次能对上实际文档。

---

## 统计

17 条 → **采纳 5**（m1/m2/m3/i1/i2）+ **部分采纳 2**（C1/C2）+ **驳回 10**（C3/M1/M2/M3/M4/M5/m4/m5/i3/i4）。

---

## 逐条复核

### 驳回（基于误读或范围误解，附依据）

#### C3 配置文件缺安全配置（trustedHosts / 签名算法 / autoUpdate 开关 / 超时 / 日志级别）——驳回

**驳回依据**：
- 本项目**无 config.json**——参数在脚本常量与 prompt。§5 是 JSON 数据契约（state/*.json schema），非配置文件。
- 更新源**固定硬编码**：mise registry（claude/codex）+ `anomalyco/opencode` GitHub releases（opencode，经反代 `https://gh.jasonzeng.dev/`）。源固定非用户可配任意源，故无"白名单/trustedHosts"需求。
- 超时已内置：Invoke-Proc（mise ls-remote 60s / upgrade 600s / exe --version 30s，§7.1）。
- 日志已有：`state/fetch_run.log`（§4/§11）。
- "自动更新开关" = 定时任务本身（不配 cron 即不跑），无需配置项。
- RSA-2048 签名验证是产品级要求，对个人 CLI 维护过度，且与 §10.2 stable-only 策略 + mise/GitHub 自身完整性保证冲突。

#### M1 并发控制缺失——驳回

**驳回依据**：v0.2.1 §6 已有完整运行锁模型（runId ownership + `FileMode::CreateNew` 原子争锁 + heartbeat + 陈锁接管）。ownership 靠 runId 匹配（跨 Bash 段 PID 必变，故不靠 PID），PID 仅作陈锁死亡判据——**比审计给的 `Test-Path lockFile`（有 TOCTOU 竞态）更完善**。审计者没读 §6。

#### M2 错误处理不全（缺网络超时/磁盘/权限/版本/并发）——驳回

**驳回依据**：v0.2.1 §8 标记表已覆盖：REMOTE_FAIL / ALL_REMOTE_FAIL（网络）、RUNTIME_ERROR（超时/权限）、DISK_FULL（磁盘）、EXE_LOCKED（目标锁定）、VERSION_FORMAT_ERROR（版本格式，v0.2.2 新增显式）、LOCKED（并发）。审计说缺的都有。v0.2.2 在 §8 补"异常覆盖说明"逐项列全。权限错误不单列标记——归入 RUNTIME_ERROR，agent 汇报 cause。

#### M3 目录缺锁/日志/签名/临时目录——驳回

**驳回依据**：v0.2.1 §4 目录布局已有 `run.lock`（锁文件）/ `fetch_run.log`（日志）/ `TEMP/`（临时目录）/ `staging/` / `archive/`。审计说缺的恰恰都在。签名文件不做（范围外）。审计者没读 §4。

#### M4 安装缺 checksum / 功能测试——驳回

**驳回依据**：
- checksum：v0.2.1 §5.2 已有大小校验（>1MB 防 stub/半下载）+ 可选 checksum（"若 release 附 checksum asset 则校验"，probe 确认是否存在）。
- 功能测试：v0.2.1 §7.2 verify 脚本就是装后功能测试（跑 `exe --version` 验可启动 + 版本号匹配 target，落 verified.json）；§5.4 `matchesTarget && healthy` 即安装后验证凭证。
- v0.2.2 在 §7.2 补"verify 即功能测试"显式说明。

#### M5 迁移指南缺失——驳回

**驳回依据**：v0.2.1 §13 就是"v0.2.1 迁移项（首次执行）"7 步。审计没读 §13。`cli migrate` 命令是产品功能，本项目手动迁移。v0.2.2 在 §13 补"无 config.json/无 SQLite/无用户数据，迁移即脚本与入口目录物理迁移"。

#### m4 配置字段说明——驳回

**驳回依据**：本项目无 config.json，无配置字段可说明。

#### m5 安全实现细节（签名 / TLS / 权限）——驳回

**驳回依据**：范围外。非通用产品，单用户 Windows，源固定，mise/GitHub 自身保证完整性。

#### i3 贡献指南——驳回

**驳回依据**：个人项目，无外部贡献。

#### i4 许可证——驳回

**驳回依据**：个人项目，无需许可证。

---

### 部分采纳（有合理内核）

#### C1 原子替换缺陷——部分采纳

**审计主张**：Copy-Item/Move-Item 非原子，Windows 锁定旧 exe，建议先部署临时目录验证后交换。

**判断**：审计描述的"先删旧版本再下载"流程在 v0.2.1 里**根本不存在**——staging/promotion 两层架构 + 晋升闸 + verify 脚本正是审计建议的"先临时部署、验证通过后原子交换"策略，已原生实现。
**合理内核**：Windows 替换运行中 exe 确实会失败。v0.2.1 已覆盖（§10.3 `.previous` 备份 + §8 `SYNC_TARGET_LOCKED` 跳过不阻其他）。
**v0.2.2 落点**：§1 原则 6 补"Move-Item 同卷原子前提，跨卷先 Copy 到目标卷临时文件再同卷 Move"显式说明。

#### C2 版本比较漏洞——部分采纳

**审计主张**：缺强制更新，预发布处理不明，local>remote 跳过可能是错误安装，版本格式验证缺失。

**判断**：
- 合理内核：版本格式验证可显式。v0.2.2 §7.3 补 `VERSION_FORMAT_ERROR` 标记 + Compare-SemVer 解析失败路径（非 `\d+\.\d+\.\d+` 核心段 → incomparable → 输出标记、不执行、报告，不"用默认版本号"——那会掩盖问题违反 fail-closed）。
- **驳回 C2 其余**：强制更新（无 force 标记）非本项目策略；自动降级非本项目策略（降级用户手动 `mise use`，§10.1）；local>remote **不静默跳过**而是显式报告异常（agent 汇报），v0.2.2 §7.3 已写明。本项目策略 stable-only 跟随 latest，不强制不自动降级，是项目策略决定非缺陷。

---

### 采纳（合理）

| 条目 | 采纳内容 | v0.2.2 落点 |
|---|---|---|
| **m1** 术语表 | 加术语表 | §17 术语表 |
| **m2** 错误场景示例 | SOP 须含错误场景示例 | §9"SOP 错误场景示例"（网络全断/exe 锁定/下载失败/verify 失败四例，每例给标记序列→agent 分支→汇报文本） |
| **m3** 测试策略 | 加测试策略说明 | §15 测试策略（单元/集成/端到端三层，仅 Windows） |
| **i1** 格式一致性 | 表格/编号统一 | 全文 |
| **i2** 版本历史 | 加版本历史表 | §16 版本历史 |

---

## v0.2.2 修订清单（相对 v0.2.1）

架构不动（故小版本号 +0.0.1）。修订点：

1. §1 原则 6 补 Move-Item 同卷原子前提（C1 部分采纳）。
2. §5.2 补更新源固定清单 + 超时已内置 + 日志已有 + checksum 可选说明（回应 C3）。
3. §7.2 补"verify 即功能测试"（回应 M4）。
4. §7.3 补 `VERSION_FORMAT_ERROR` 标记 + 版本格式验证路径 + local>remote 显式报告不静默跳过（C2 部分采纳）。
5. §8 补"异常覆盖说明"逐项列全（回应 M2）。
6. §9 补 SOP 错误场景示例要求（m2 采纳）。
7. §13 补"无 config.json/无 SQLite/无用户数据"（回应 M5）。
8. 新增 §15 测试策略（m3 采纳）。
9. 新增 §16 版本历史（i2 采纳）。
10. 新增 §17 术语表（m1 采纳）。
11. 全文表格/编号一致性（i1 采纳）。
12. 头部 changelog 标注 v0.2.1→v0.2.2 变更摘要。

---

## 下一步

按 §0 交付物三层，下一份产出 `cli-autoupdate-sop.md`（给定时任务执行 agent 逐字读的标准化 SOP）。脚本实现（`*-v0.2.2.ps1`）穿插 re-probe 修订 spec 后产出。
