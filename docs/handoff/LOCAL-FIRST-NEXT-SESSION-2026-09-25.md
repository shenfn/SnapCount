---
tags:
  - handoff
  - next-session
  - tdd
scope: 下一个开发会话的启动指引（Local-First SL-01/SL-02/A-B 切片）
---

# 下一个开发会话 Handoff：Local-First 切片实施

> 写给：即将开工的开发 Agent 新会话。本会话只做了分析、拍板与设计，零业务代码改动。
> 先读这个：`docs/handoff/LOCAL-FIRST-GROOM-001-拍板与切片交接-2026-09-25.md`（停点、冻结面、风险）
> 再读设计：`docs/spec/LOCAL-FIRST-DOMAIN-CONVERGENCE.md`（Invariant 权威位置、事务边界、Slice 定义、"不做清单"）

## 新会话开工协议

1. `git status --short --branch` + `git worktree list --porcelain`；保护根工作区用户 WIP；确认在哪个 worktree 开发由用户指定。
2. 读 AGENTS.md + `docs/spec/02-TDD实施与交接规范.md`。
3. **一个会话只做一个 Slice**：红灯（具名场景编号）→ 最小实现 → 绿灯 → 回归 → macOS CI → 写 Handoff → 停。
4. 提交纪律：多 commit、少 push；push/部署/TestFlight 必须单独确认；不 `git add -A`。

## Slice 顺序（已拍板，无门直接可开工）

```
SL-01 文档口径收口（先做，纯文档）
SL-02 投影收敛+特征测试加固（AppState refreshLocalMonthProjection 收敛 8 处分支；删单参数 route 死 API；LF-001/LF-002/DM-011/DM-014 具名红灯；三套引用前缀特征测试）
SL-A 收入本地域 → SL-B 钱包快照本地域（最小形态：只记事实；先做切片级 Grooming）
SL-03 候选编辑确认+discard 幂等 → SL-04 候选重试/域重判
M1 五域真机验收（用户动作，Gate）
SL-05 编辑换图（含删除残留断言）∥ SL-07 兜底/孤儿确认 → SL-08 异常恢复 → SL-09 四域导入
SL-C 设置本地镜像（含删 App 文案/删账号勾选框）→ SL-D AI 确定性候选文案
```

## 拍板速查（详情见领域收敛文档 §10.1）

收入/钱包进 Phase 1（钱包只记事实）｜还款不本地化｜BYOK 暂缓｜设置未登录存本地、登录"谁改得晚谁赢"｜AI 本地方案 a 确定性文案、隐藏点评｜消费必须选账户（DM-GAP-10 不采纳）｜双轨=迁移期策略非终态架构。

## 冻结红线（任何 Slice 不得触碰）

outbox/sync 表与 Transport、Edge Function、PWA、生产迁移/部署/TestFlight、L2 迁移；登录态新记录走云端的路由语义（特征冻结）。

## 已知陷阱

- Windows 无 Swift 工具链：编译/XCTest 只认 macOS CI。
- `local_records` CHECK 含 expense 死分支：业务层禁写，别在迁移前"修复"。
- staging 引用前缀是 `local-staging/`（文档曾写错为 `staging/`）。
- 图片↔DB 是补偿模式：DB 权威，孤儿文件接受，勿引入文件事务。
- confirm 候选不搬图片文件，只移交 DB 引用。
- 根工作区 index.html 被未提交 WIP 覆盖为无关页面，以 git HEAD 为准。
