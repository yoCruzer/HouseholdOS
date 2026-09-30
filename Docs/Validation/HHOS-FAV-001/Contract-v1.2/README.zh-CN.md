# HouseholdOS Foundation Architecture Validation Program

版本：1.2｜复审日期：2026-09-28｜Program：HHOS-FAV-001

## 现在执行什么

**一个 Program，一次授权，内部自治。** 用隔离工程和最小真实链路检验 HouseholdOS Foundation，不实施正式衣橱/同步，也不自动 Freeze。

本包完整替代 v1.0/v1.1 的执行指令。无需拼接旧包或整段聊天。读取 `GOAL.md`、`VALIDATION_CONTRACT.md`、`ARCHITECTURE_CONTEXT.md`；`REVISION_NOTES.md` 是变更解释及旧用例映射，不是另一套任务。

```text
Repository: yoCruzer/HouseholdOS
Accepted baseline: f19469fe13be175d1b28d71ddb6b5a917abdcc32
Validation branch: spike/foundation-validation
Publication: 一个 Draft PR；不合并
```

2026-09-28 远端复查：main 仍指向上述基线；PR #4 已合并；远端分支列表没有 validation 分支。这不证明用户电脑上没有未推送工作。执行前必须检查并恢复已有成果。

## 本次改进

不是增加第四轮架构脑暴，而是收敛执行：先得到真实框架/adapter 的最小链路，再以共享 fixture 覆盖关键故障；所有安全验收不打折，动态备份排除、复杂历史兼容和吞吐调优不再提前产品化。验证产物必须明确说明对正式实现的作用，不能变成孤立的“测试平台”。

模型建议改为 **GPT-6 Astra／Medium（中）**。这是任务级工程建议，不是本项目已做过 Medium/High 对照实验。High 是确有困难反例时的可选诊断资源，不是开始条件或每个 gate 的流程。附件不会自行改变模型、推理强度、额度或权限。

## 手机使用

上传本 ZIP 后发送 `SHORT_START_PROMPT.txt`。校验 `SHA256SUMS.txt`；它仅检查完整性，不是签名或授权来源。本 ZIP 无自动执行脚本。

## 交付预期

一个隔离 harness、一个 Draft PR、单一状态文件、证据与逐决策 Freeze 建议，以及集中 Owner Action Pack。中间不逐项询问继续；真实环境缺失不冒充通过。恢复 checkpoint 不代表环境会自动唤醒已退出的 Codex。

原目录曾有两份未暂存 String Catalog 修改；它们是历史保护提示，不假定今日仍是恰好两份。保护执行时发现的全部既有工作，不让旧路径或脏文件阻塞安全的新 worktree。
