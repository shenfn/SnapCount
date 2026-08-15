# CORE-010 通用域边界评估执行记录

- 目标：确认通用域候选规则是否具备生产共享核心的独立边界，并确定 wallet 与普通领域的拆分方式。
- 基线：`f7b24cd`。
- 工作树：`D:\Business\count\.worktrees\表达核心通用域边界评估`。
- 分支：`docs/表达核心通用域边界评估`。
- 本轮范围：只读检查实现、直接测试、Edge 调用、领域 profile 和现有 Planner 回归入口；建立 Spec、ADR 和交接记录。
- 非范围：生产实现迁移、候选语义变更、render contract、PWA/iOS、数据库、部署和 worktree 清理。

## 只读结果

- `generic-domain-candidates.mjs` 约 575 行，仅依赖 `parseFiniteNumber`，无 IO 和运行时专属 API。
- 公开入口为 `prepareDomainRecords`、`generateIncomeCandidates` 和 `generateBuiltinDomainCandidates`。
- 文件混合 income、sleep、food、sport、reading、wallet 六类职责；共享逻辑包括候选工厂、证据、数值/时间读取和普通指标。
- `prepareDomainRecords` 同时负责因果可见性与 sleep 事件去重，必须作为共享预处理保留。
- wallet 具有金额来源冲突、账户身份、asset/liability 类型和严格快照时间规则，不能与普通域比较逻辑混合。
- `domainProfile` 只提供 meal baseline 与 chronotype 等纯数据，未发现核心读取或生成 profile 的路径。
- Edge 仍从 `tools` 导入该文件；完整 Planner 测试入口依赖 `esbuild`，Windows 未安装 Deno 的状态沿用 A2 既有环境限制。

## 当前状态

- 评估：已完成。
- Spec/ADR：已建立。
- 实现迁移：待文档 PR 合并后建立 `feature/表达核心通用域`。
- 测试：现有通用域 Planner 特征测试已存在；共享 Node/Deno fixture 尚未建立。

## 处置决策

- 采用“稳定兼容门面 + 内部模块族”，不原样复制 575 行单体。
- wallet 单独实现、单独契约组、单独回归；income/food/sleep 分域迁移；sport/reading 保留通用指标路径。
- 先迁共享基础和门面，再按 income/food/sleep/wallet 顺序迁移；不在本切片修改 Edge 查询或 Planner 编排。

## 未验证与风险

- Windows 未安装 Deno，双运行时结果需由实现 PR CI 验证。
- 完整 Planner 测试因本地缺少 `esbuild` 可能无法启动，不能将环境失败写成业务失败。
- 现有测试尚未拆成 CORE-063 至 CORE-076 的共享 fixture 映射。
- `render-contract.mjs` 仍是另一条 `tools` 反向依赖，另立 CORE-011，不纳入本轮。

## 下一步

1. 合并本边界评估文档 PR。
2. 建立 `feature/表达核心通用域` 实现 worktree，先写共享 fixture 红灯。
3. 迁移后运行 Node、Deno、Planner、Edge 静态和治理门禁。
4. CI 收口 CORE-010 后再评估 CORE-011；A2 完成前保持 PWA/iOS 和生产部署冻结。
