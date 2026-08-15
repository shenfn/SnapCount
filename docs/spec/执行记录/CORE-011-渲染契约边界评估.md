# CORE-011 渲染契约边界评估执行记录

- 目标：确认 render contract 是否具备整体迁入生产核心的纯逻辑边界，并识别版本与曝光规则的重复事实。
- 基线：`082f0db`。
- 工作树：`D:\Business\count\.worktrees\表达核心渲染契约边界评估`。
- 分支：`docs/表达核心渲染契约边界评估`。
- 本轮范围：只读检查 render 源码、直接测试、Edge 调用、版本使用和架构基线；建立 Spec、ADR 和交接记录。
- 非范围：生产实现迁移、客户端 UI、数据库迁移、部署和历史数据改写。

## 只读结果

- `render-contract.mjs` 约 129 行、无 import、无 IO，四个导出职责内聚，适合整体迁移。
- Edge Planner 仅直接调用 `buildRenderPlans`；`buildExposureEvents` 和 `compileExposureHistory` 当前只有 Lab 测试使用。
- 4 项旧 Node 测试覆盖 surface 投影、preview 排除、真实曝光历史和 exposure/dedupe 双 key。
- `surface-render-contract-v0.1` 在 render 模块、Delivery 和 Shadow 三处运行时代码重复，应收敛为共享常量。
- SQL fixture 中也有同值字面量，但它们是历史数据契约，不在 JavaScript 单一事实源范围内。
- 生产架构基线只剩 render contract 这一条例外；CORE-011 是 A2 最后一片反向依赖。

## 当前状态

- CORE-010：PR #61 全部门禁通过，合并提交为 `082f0db`；Node/Deno、Edge 和 Planner 均已验证。
- CORE-011 评估：已完成。
- Spec/ADR：已建立。
- 实现迁移：待文档 PR 合并后建立 `feature/表达核心渲染契约`。

## 未验证与风险

- Windows 本地是否可运行 Deno 沿用 A2 环境限制，双运行时由实现 PR CI 验证。
- `buildExposureEvents` 的默认当前时钟不适合 fixture 直接断言，测试必须显式注入 occurredAt。
- A2 完成还需要 CORE-011 实现、架构基线清零、CI 全绿和阶段收口证据。

## 下一步

1. 合并 CORE-011 文档 PR。
2. 建立实现 worktree，先写 CORE-077 至 CORE-082 共享 fixture 红灯。
3. 整体迁移、统一版本常量、改 wrapper/Edge import 并清零架构例外。
4. CI 全绿后单独收口 A2，再进入下一阶段设计，不在同一实现 PR 扩展端侧范围。
