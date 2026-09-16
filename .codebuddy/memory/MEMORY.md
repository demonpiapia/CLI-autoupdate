# MEMORY — CLI-autoupdate 工作区

- **项目性质**：`d:\AI\Workspace\automatic\CLI-autoupdate` 是 CLI 自动升级方案的**规格/审计文档工作区**（SPEC-v0.1 → v0.2.2 + Zoo 审计 + Cherry reject），PowerShell 脚本实现暂未产出（截至 2026-09-16）。
- **命名约定**：审计报告 = 被审计文件名 + `-codebuddy-review` 后缀，存同目录（用户 2026-09-16 指示）。
- **关键结论（2026-09-16 审计，详见 `SPEC-v0.2.2-codebuddy-review.md`）**：
  - Zoo 对 v0.2.1 的审计报告引用体系失效（13/17 条章节引用与原文不符；行数 246 vs 365），不构成有效审计；Cherry reject 核心成立。
  - v0.2.2 遗留 F1–F6；F1（晋升凭证生命周期，UPTODATE 跳过 verify 导致首轮迁移/回退语义缺口）为高优先，建议 v0.2.3 修订。
- **机器事实（2026-09-16 只读核验）**：mise claude 2.1.273 / codex 0.154.0；opencode npm 1.18.31；`D:\AI\Programs\CLI` 部分就位（Codex、opencode，无 claude）。
- **工作风格（观察）**：多 agent 角色化交叉审计（Zoo / Mistral / Cherry / CodeBuddy），要求独立核实、逐条可追溯、结论标注来源。
