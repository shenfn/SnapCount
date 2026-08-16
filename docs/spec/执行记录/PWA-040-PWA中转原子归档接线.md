# PWA-040 PWA 中转原子归档接线执行记录

> 日期：2026-08-16
>
> 分支：`feature/PWA中转原子归档`
>
> 基线：`e75027b`

## 目标行为

- PWA 中转归档只调用 `archive_staging_record`，不在客户端模拟跨表事务。
- 缺少财务金额时保留中转记录并要求人工补全，不写 `0.01`。
- 同一中转记录重复点击共享请求；用户切换后旧响应不污染新会话。
- RPC 已成功而列表刷新失败时仍返回成功，只允许后续重新读取。

## 红灯证据

- Repository 测试首次失败：`repository.archive is not a function`。
- Feature 测试首次失败：`createStagingArchiveFeature.js` 不存在。
- 原有 6 项中转重试测试在红灯阶段仍通过，失败来源是本场景目标缺失。

## 最小实现

- `stagingRepository.archive` 只映射原子 RPC 参数和响应 DTO。
- `createStagingArchiveFeature` 管理金额预检、并发请求、session generation 和刷新副作用。
- `useStore.archiveStagingRecord` 只准备已有展示数据、调用 Feature 并收敛本地读模型。
- 新增源码边界测试，阻止正式表写入、终态更新、路由反馈和 `0.01` 回流。

## 本地绿灯

| 命令 | 结果 |
|---|---|
| `npm run test:staging-archive` | 8 项通过 |
| `npm run test:staging-retry` | 7 项通过 |
| `npm run test:pending-queue` | 通过 |
| `npm run test:finance-occurred-at` | 通过；断言已沿 Facade → Feature → Repository 链保护 |
| `npm run build` | 通过；仅既有 bundle/eval 警告 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；仅既有人工清单警告 |
| `npm run check:security-contracts` | 通过 |

## 未验证与剩余风险

- 尚未获得本分支 GitHub 综合门禁结果。
- 未执行生产迁移、部署、真实归档或 migration repair。
- 生产 `20260808054219` 与仓库 `20260808120000` 的迁移映射仍未解决。

## 下一步

1. 提交并创建 PR。
2. 远程门禁通过后合并并回写 PWA-040 完成状态。
