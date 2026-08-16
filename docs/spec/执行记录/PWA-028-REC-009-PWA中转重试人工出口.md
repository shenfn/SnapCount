# PWA-028 / REC-009 TDD 执行记录

> 日期：2026-08-16
>
> 分支：`feature/PWA中转重试人工出口`
>
> 基线：`d4b5c52`（PWA-026 PR #71 合并提交）

## 目标行为

- `retry_count >= 3` 时 PWA 不发起第四次请求，记录继续留在中转队列。
- 服务端返回重试上限时映射为结构化 `rejected`，不伪造成功。
- 重试未确定时映射为结构化 `failed`，保留记录并更新本地展示次数。
- 只有服务端返回 `done` 才从本地中转队列移除并关闭裁决台。
- 用户切换或退出后，旧响应不得写入新用户队列；重复点击共享同一个请求。

## 权威来源

- 服务端 `supabase/functions/ingest-receipt/index.ts` 仍是重试上限和归档结果的权威来源。
- PWA Feature 的上限判断只作非权威 UX 预检，服务端拒绝仍必须保留。

## 本轮范围

- 新增 `src/repositories/stagingRepository.js`，封装 session、Edge transport 和 DTO 结果。
- 新增 `src/features/staging/createStagingRetryFeature.js`，封装 generation、请求去重和动作结果。
- `useStore.retryStagingRecord` 保留兼容 API，页面只消费结果。
- 达到上限时隐藏重试按钮，保留调整、人工归档和销毁入口。

## 非范围

- 不修复 `archiveStagingRecord` 跨表非原子问题。
- 不修改 `staging_records` schema、Edge 重试规则、生产数据、iOS 或部署配置。
- 不处理 `assigned/confirmed` 历史孤儿，不重写完整中转生命周期。

## 红灯与最小实现

- 特征测试覆盖 PWA-028、PWA-030、PWA-031、PWA-032。
- Repository 测试固定不透传 `user_id`、映射第四次拒绝和保留失败记录。
- 最小实现完成后全部测试转绿，未扩大到归档和待补全账单状态机。

## 验证结果

| 命令 | 结果 |
|---|---|
| `npm run test:staging-retry` | 6 项通过 |
| `npm run build` | 通过；仅既有 chunk/eval 警告 |
| `npm run test:pending-queue` | 通过 |
| `npm run check:security-contracts` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；既有 ratchet 警告 |
| `git diff --check` | 通过 |

## 未验证项与剩余风险

- 未执行真实 Edge 重试、归档、丢弃或生产数据审计。
- 服务端重试成功后的跨表归档原子性仍未解决，必须由独立数据库/生命周期任务处理。
- GitHub PR 门禁尚未运行；对应提交和 CI 结果待 PR 阶段填写。

## 对应提交

- 待用户授权提交和推送后填写。
