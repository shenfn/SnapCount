# PWA-033 中转归档原子性评估执行记录

> 日期：2026-08-16
>
> 分支：`docs/PWA中转归档原子性评估`
>
> 基线：`4ee12f7`

## 目标与范围

- 只读核对数据库权威 RPC、PWA/iOS 调用路径、现有 SQL fixture 和生产函数能力。
- 明确下一片数据库契约测试与 PWA 接线的顺序。
- 不修改业务代码、迁移、生产数据或部署状态。

## 关键证据

- 仓库存在两代 `archive_staging_record` 定义，最新版由 `20260808120000` 重建。
- iOS 全部中转归档和 PWA 通用域补全已调用 RPC。
- PWA 快速/财务归档仍执行多步客户端写入，`finishStagingArchive` 是半状态来源。
- PWA 对缺失财务金额使用 `0.01` 兜底，违反金额事实边界。
- 现有 CI SQL fixture 未覆盖 archive RPC 的完整事务、幂等、权限和账户行为。
- 生产只读查询确认函数签名和关键语义可用，但迁移版本号与仓库不一致。

## 基线验证

| 命令 | 结果 |
|---|---|
| `npm run test:finance-occurred-at` | 通过 |
| `npm run test:staging-retry` | 6 项通过 |
| `npm run test:pending-queue` | 通过 |
| `npm run check:security-contracts` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；RPC 契约仍为人工清单 |
| Supabase linked migration list（只读） | 生产 `20260808054219` 与仓库 `20260808120000` 版本不一致 |
| Supabase 管理 API 函数查询（只读） | 线上签名、行锁、search_path、nullable occurrence 和幂等语义存在 |

## 未验证项与剩余风险

- 未执行真实归档、生产数据审计、迁移、部署或 migration repair。
- 未证明 expense/income 账户流水、故意失败回滚、跨用户和不同域幂等行为。
- `assigned/confirmed` 历史终态完整性仍未审计。

## 下一步

1. PR #74 已合并，merge commit `2430cf8`。
2. PWA-034 至 PWA-039 已在 `test/中转归档原子契约` 接续。
3. 数据库契约合并后，再创建 PWA 原子归档接线分支完成 PWA-033/PWA-040。
