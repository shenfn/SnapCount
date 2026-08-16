# A3 PWA 账户流水 helper 边界评估交接快照

> 任务：PWA-069 只读评估
>
> 状态：评估完成，待文档 PR 验证
>
> 基线：`7d8cba9`
>
> 分支：`docs/PWA流水helper边界评估`

## 已完成

- 确认 PWA `upsertAccountEntry` / `voidAccountEntries` 已无消费者，仅剩 Store 定义与公开出口。
- 区分最终数据库运行依赖与历史 migration 文本；确认财务保存和统一删除仍依赖数据库 primitive。
- 确认 iOS wallet 快照关联仍是 UI 可达的 direct create primitive 消费者。
- 盘点 authenticated/anon 权限、replacement/void 语义和现有 fixture 缺口。
- 形成 PWA-069 边界评估与执行记录；没有新增 ADR 或修改业务代码。

## 核心结论

- PWA-069A/B 可以删除两个 Store helper 和公开出口，并增加 `src/` 源边界测试。
- 不为无消费者 helper 新建 Repository 方法。
- 数据库 RPC、权限与 iOS 调用必须冻结；A4 先让 iOS 接入 `apply_wallet_snapshot`，再评估 primitive 外部权限。
- 实现后必须先做 A3 阶段对账，不能自动跳入 A4。

## 未验证与风险

- direct create/void 的跨用户、replacement、重复 void、余额触发器、并发和失败回滚没有专用 PostgreSQL fixture。
- 仓库静态搜索不能证明仓库外私有客户端不存在；iOS 的已知 direct 调用已明确保留兼容。
- 未执行 PWA build 或数据库行为测试，因为本轮是纯文档评估。
- 未执行生产查询、migration、部署、真实数据写入或 TestFlight。

## 已验证

- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；只有既有的 RPC 契约与重复业务规则人工清单警告。
- `git diff --check`：通过。

## 冻结范围

- 根工作区和其他 worktree WIP。
- PWA-069 评估 PR 合并前不修改 Store、测试或业务代码。
- 数据库 migrations/RPC/grants、iOS、Edge、Planner、生产配置和发布操作。

## 下一步

1. 运行 `npm run governance:check`、`npm run governance:arch` 和 `git diff --check`。
2. 复核纯文档 diff，逐文件提交、推送并创建评估 PR。
3. 合并后从最新 main 新建 `feature/PWA流水helper门面清理`。
4. 先写 PWA-069A 源边界红灯，再最小删除两个 Store helper；回归通过后建立 A3 阶段收口评估。
