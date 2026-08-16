# PWA-069 PWA 账户流水 helper 边界评估记录

> 日期：2026-08-16
>
> 基线：`7d8cba9`
>
> 分支：`docs/PWA流水helper边界评估`
>
> 状态：只读评估完成，待文档 PR 验证

## 本轮范围

- 只读追踪 `upsertAccountEntry`、`voidAccountEntries` 的 PWA 消费者和 Store 公共出口。
- 区分历史 migration 引用与最终运行函数依赖，核对权限、replacement/void 语义和测试覆盖。
- 核对 iOS direct RPC 是否仍在可达生产路径。
- 只新增评估、执行记录、交接和索引文档，不修改 PWA、数据库或 iOS 业务代码。

## 已确认

- 两个 PWA helper 已无产品消费者，只剩定义和 Store 公开返回值；最后一个 wallet 快照调用者已由 PWA-068 原子命令替代。
- 两个 helper 都吞掉 RPC 错误，无法向调用方表达 accepted/failed，不应迁入新 Repository 固化。
- 数据库 create/void primitive 仍被最终财务保存和统一删除事务调用，不能删除或改签名。
- iOS wallet 快照关联是可见 UI 可达路径，仍直接调用 create primitive；A4 前必须保留 authenticated 兼容。
- create 是“void 旧流水后插入新流水”的 replacement，不是严格 exactly-once；现有 fixture 没有完整固定 direct 权限、replacement、void、余额和回滚语义。

## 评估结论

- PWA-069 后续只做 Store 门面清理与源边界测试，不新增 Repository 方法或数据库 migration。
- 数据库 RPC、权限和 iOS 调用全部冻结到 A4 独立切片。
- PWA-069 实现完成后先做 A3 阶段对账，再决定是否满足进入 A4 的条件。
- 本轮沿用既有数据库事务权威和跨端迁移顺序，不新增 ADR。

## 验证

- 已完成仓库全量静态引用搜索和关键调用链逐文件核对。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；只有既有的 RPC 契约与重复业务规则人工清单警告。
- `git diff --check`：通过。
- 未执行 PostgreSQL fixture、PWA build、生产查询、migration、部署、真实数据写入或 TestFlight。

## 下一步

1. 运行文档与治理检查，复核纯文档 diff。
2. 逐文件提交并推送 `docs/PWA流水helper边界评估`，创建 PR 等待门禁。
3. PR 合并后从最新 main 建立 `feature/PWA流水helper门面清理`，按 PWA-069A/B 先红灯后最小删除。
