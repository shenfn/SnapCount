# PWA-051 PWA 正式记录边界评估执行记录

> 日期：2026-08-16
>
> 基线：`74628a3`
>
> 分支：`docs/PWA正式记录边界评估`

## 目标与范围

- 复核 PR #81 合并后的 PWA 正式记录读写现状。
- 区分读取、财务保存、通用域、钱包快照和删除的权威边界。
- 选择下一最小实现切片，只修改文档，不修改业务代码。

## 只读证据

- `loadData` 仍直接查询交易、收入、通用记录和账户；正式记录 DTO 映射留在 Store。
- `loadUnboundRecords` 重复查询交易/收入和月份规则。
- `openProcessedStagingRecord` 本地未命中时并行探测三张正式表。
- 财务创建/编辑已经调用数据库原子保存 RPC，账户流水由数据库维护。
- 通用域中转补全走 `archive_staging_record`；普通通用记录仍直写 `data_records`。
- 正式记录删除统一调用 Edge `delete_record`；wallet 快照关联跨越账户、记录和还款周期。

## 决策

按 ADR-021 分层收拢。下一实现候选为 PWA-052 至 PWA-056，只迁正式记录读取 transport/DTO 和显式目标类型读取。保存、删除、账户、钱包快照、图片签名、数据库、Edge 和 iOS继续冻结。

## 验证与限制

- 本片是纯文档评估，不运行 PWA 功能测试或 build。
- 将运行治理检查、文档引用检查和 `git diff --check`。
- 未执行生产查询、迁移、部署、真实数据修改或 TestFlight。

## 下一步

文档 PR 全门禁通过并合并后，从最新 `origin/main` 新建实现 worktree，先写 PWA-052 至 PWA-056 Spec 和红灯测试。
