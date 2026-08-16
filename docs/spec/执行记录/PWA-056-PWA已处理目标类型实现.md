# PWA-056 PWA 已处理目标类型实现记录

> 日期：2026-08-16
>
> 基线：`91013eb`
>
> 分支：`feature/PWA已处理目标类型实现`

## 目标行为

- 已处理中转记录刷新后可恢复真实目标表和最终域。
- unknown 不进行猜测；已知 kind 只读取一张表。

## 当前行为

- 实现前 `staging_records` 没有 `target_kind/resolved_domain_key`。
- 实现前 `stagingRepository` 只返回识别域，Store 未命中时并行查询三张正式表。

## 权威来源

- `archive_staging_record` 与目标表的 `staging_record_id/user_id` 关系。
- `docs/spec/模块/PWA业务边界/已处理目标类型实现规格说明.md`。
- ADR-021、ADR-022。

## 本轮范围

- PWA-056A 至 PWA-056E 的迁移、数据库 fixture、Repository、Store 和专项测试。

## 非范围

- 生产迁移、生产数据、财务保存/删除、账户、wallet、图片签名、iOS、Edge、Planner 和部署。

## 预计修改文件

- `supabase/migrations/` 新迁移。
- `scripts/` PostgreSQL fixture/执行入口。
- `src/repositories/stagingRepository.js`、`recordRepository.js` 及测试。
- `src/composables/useStore.js`、PWA-056 特征测试。
- Release Validation、阶段索引、Spec 和交接。

## 基线测试

- `npm run test:staging-archive`：12 项通过。
- `npm run test:staging-read`：9 项通过。
- `npm run test:record-read`：8 项通过。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过，仅既有人工清单警告。
- `npm run build`：通过，仅既有 `eval` 与 bundle size 警告。
- 本机无 `psql`，Docker daemon 也未运行；PostgreSQL 基线和红灯不能在本地执行。

## 红灯测试及失败原因

- `npm run test:staging-read`：PWA-056D 因 DTO 缺少 `detectedDomainKey/resolvedDomainKey/targetKind/targetReference` 失败。
- `npm run test:record-read`：PWA-056E 因 `getRecordByTarget` 不存在失败；实现前 Store 源码仍包含三张目标表并行探测。
- PostgreSQL 行为红灯未在本机执行；只读 schema/迁移检查确认新字段不存在。新增迁移前 fixture 将由 GitHub PostgreSQL job 证明回填与约束行为。

## 最小实现

- 新增 `20260816120000_staging_target_type_contract.sql`，追加字段、枚举/非空白约束、保守历史回填和归档包装 RPC 元数据写入；既有迁移与 legacy 归档实现未修改。
- 历史回填同时匹配 `target_record_id + staging_record_id + user_id`，且三张目标表恰好一张命中才写入。
- `stagingRepository` 区分识别域、最终域、目标 kind 和目标 ID；非法 kind 不派生引用。
- `recordRepository.getRecordByTarget` 按 kind 选择唯一表；非法/unknown 零请求。
- `openProcessedStagingRecord` 只按显式 kind 查本地或 Repository，删除三表探测。
- Release Validation 对新迁移执行两次，并运行迁移前历史样本、迁移后回填/约束和归档自愈 fixture。

## 绿灯结果

- `npm run test:staging-archive`：13 项通过。
- `npm run test:staging-read`：10 项通过。
- `npm run test:record-read`：12 项通过。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过，仅既有人工清单警告。
- `npm run build`：通过，仅既有 `eval` 与 bundle size 警告。
- `git diff --check` 与相关 JavaScript `node --check`：通过。
- PostgreSQL fixture：待 GitHub Release Validation 验证，当前不得标记通过。

## 未解决风险

- 生产 archived 行回填率未知；本轮不查询生产。
- unknown 记录必须保留人工恢复出口，不能以识别域代替最终类型。
- 新迁移尚未在本机 PostgreSQL 或生产执行；生产迁移不在本轮授权范围。
- GitHub PostgreSQL fixture 与全量远程门禁待 PR 验证。

## 对应提交

待实际提交后填写。
