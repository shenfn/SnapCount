# PWA-026 中转生命周期边界评估执行记录

> 日期：2026-08-16
>
> 基线：`39f4af8`（PWA-018 PR #70 合并提交）
>
> 分支：`docs/PWA中转生命周期边界评估`

## 目标与范围

- 只读复审 PWA 中转读取、重试、归档、丢弃、还款截图和待补全账单的职责边界。
- 为 REC-009 重试上限与人工出口建立下一片实现 Spec、ADR、风险清单和门禁。
- 不修改 PWA、Edge、数据库、iOS、部署配置或历史数据。

## 已核对证据

- `useStore.loadData` 直接读取开放和已处理 `staging_records`，并负责 DTO 映射、签名图片和 repayment candidate。
- `retryStagingRecord` 仍由 Store 直接获取 session、拼接 Edge URL、提交 FormData；用户 ID 作为字段透传，不应成为权限事实。
- `archiveStagingRecord` 先写账户/通用正式记录，再由 `finishStagingArchive` 直接更新中转状态；与记录生命周期规格的原子归档入口存在差异。
- `discardStagingRecord` 已调用 `discard_staging_record` RPC，但本地队列移除、刷新和错误提示仍由 Store 编排。
- `PagePending.vue` 同时承担队列合并、状态分类、字段别名、人工修复入口、动作后队列定位和部分业务文案。
- iOS 已有 `InboxRepositoryProtocol`，包含 discard/retry/archive/repayment/image/confirm 动作。

## 评估结论

- 中转边界可以抽出，但首片不应覆盖完整生命周期。
- REC-009 是下一片最小垂直切片；归档原子性差异列为独立阻断项。
- `assigned/confirmed` 历史孤儿仍只做审计准备，不做数据修复。

## 基线验证

| 命令 | 结果 |
|---|---|
| `npm run test:pending-queue` | 通过 |
| `npm run check:security-contracts` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；production tools 0、Domain 禁止依赖 0、页面直连维持既有 ratchet 2 项 |
| `git diff --check` | 通过 |

## 未验证项与剩余风险

- 未执行真实重试、归档、丢弃或生产数据审计。
- REC-009 的 PWA 行为测试和 Edge 第四次拒绝契约尚未在本评估分支新增，留给实现分支红灯。
- 归档跨表原子性尚未解决，不能宣称中转生命周期整体完成。
- `assigned/confirmed` 历史状态的 `target_record_id` 完整性未审计。

## 下一步

1. 合并本评估文档 PR。
2. 从 `origin/main@39f4af8` 创建 `feature/PWA中转重试人工出口`。
3. 先写 REC-009 红灯/特征测试，再抽出最小 Staging Repository/Feature。
