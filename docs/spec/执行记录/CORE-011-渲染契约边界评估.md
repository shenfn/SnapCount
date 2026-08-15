# CORE-011 渲染契约执行记录

- 目标：确认边界后将 render contract 迁入生产共享核心，统一版本事实并消除最后一条生产 `tools` 反向依赖。
- 实现基线：`b43d0a7`（CORE-011 文档 PR #62 合并提交）。
- 工作树：`D:\Business\count\.worktrees\表达核心渲染契约`。
- 分支：`feature/表达核心渲染契约`。
- 本轮范围：CORE-077 至 CORE-084 fixture、生产共享模块、Lab wrapper、Edge import/版本常量、架构基线、CI 和交接文档。
- 非范围：客户端 UI、数据库迁移、生产部署、曝光持久化编排和历史数据改写。

## 只读结果

- `render-contract.mjs` 约 129 行、无 import、无 IO，四个导出职责内聚，适合整体迁移。
- Edge Planner 仅直接调用 `buildRenderPlans`；`buildExposureEvents` 和 `compileExposureHistory` 当前只有 Lab 测试使用。
- 4 项旧 Node 测试覆盖 surface 投影、preview 排除、真实曝光历史和 exposure/dedupe 双 key。
- `surface-render-contract-v0.1` 在 render 模块、Delivery 和 Shadow 三处运行时代码重复，应收敛为共享常量。
- SQL fixture 中也有同值字面量，但它们是历史数据契约，不在 JavaScript 单一事实源范围内。
- 生产架构基线只剩 render contract 这一条例外；CORE-011 是 A2 最后一片反向依赖。

## 红灯

- `npm run test:expression-render-contract` 失败：生产 `render-contract.mjs` 不存在，Node 报 `ERR_MODULE_NOT_FOUND`。
- `npm run test:expression-render-contract-wrapper-compat` 同样因生产模块缺失失败。
- 两项失败均精确指向目标边界缺失，不是 fixture、语法、凭据或网络问题。

## 最小实现

- 新增生产共享 `render-contract.mjs`，原样迁移四个导出并新增 `SURFACE_RENDER_CONTRACT_VERSION`。
- Lab 原路径改为薄 wrapper，继续兼容旧测试和离线实验。
- Edge Planner 直接导入生产 `buildRenderPlans`；Delivery/Shadow 引用共享版本常量。
- 架构基线 `production_tools_imports.known` 清空，未修改 SQL 历史 fixture。
- `buildExposureEvents` 缺省当前时钟、未知 surface 抛错、曝光历史白名单和双 key 行为均保持不变。

## 本地绿灯

- CORE-077 至 CORE-084 Node fixture：1/1。
- render wrapper 与 Edge 静态契约：2/2；所有 expression-core wrapper：11/11。
- 全部 expression-core Node 模块：10/10。
- 旧 render 特征测试：4/4；完整 Planner：185/185。
- 旧 expression-core 兼容：8/8；PWA `npm run build` 通过。
- `npm run check:expression-core-boundary`、`npm run governance:arch`、`npm run governance:check` 和 `git diff --check` 通过。
- 架构门禁实测 `production_tools_imports: 0`；JavaScript 运行时版本字面量仅剩共享常量一处。
- 完整 Planner 首次运行的 5 个失败是 worktree 缺少 `esbuild` 的环境失败；执行 `npm ci` 后重跑 185/185，通过且未修改锁文件。

## 未验证与剩余风险

- Windows 本机没有 Deno，Deno fixture、Edge `deno check` 和完整 Release Validation 仍需由 GitHub CI 验证。
- `buildExposureEvents` 的默认当前时钟兼容分支被保留；共享 fixture 显式传入 `occurredAt`，没有测试非确定时间文本。
- A2 尚未完成：仍需实现 PR 全绿、合并提交、阶段完成证据和严格 fresh-agent 接续结果。

## 下一步

1. 提交并推送 `feature/表达核心渲染契约`，创建实现 PR。
2. 等待 Node/Deno、Edge、Planner、构建和治理门禁全部通过后合并。
3. 单独补 A2 完成证据与严格 fresh-agent 接续结果，再裁定下一阶段；不在本实现 PR 扩展端侧范围。
