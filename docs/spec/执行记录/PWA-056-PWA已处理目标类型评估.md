# PWA-056 PWA 已处理目标类型评估记录

> 日期：2026-08-16
>
> 基线：`090bd17`
>
> 分支：`docs/PWA已处理目标类型评估`

## 目标行为

- 已处理中转记录在刷新后仍能无歧义恢复正式目标类型和最终业务域。
- unknown 明确失败，已知类型只读取一张正式表。

## 当前行为

- 归档 RPC 当次返回 `target_reference`，但中转行不持久化目标类型。
- 列表刷新把 `detected_domain_key` 映射为 `domainKey`，会丢失用户纠正结果。
- 本地未命中时 Store 并行查询三张正式表。

## 权威来源

- 原子归档：`archive_staging_record` 与实际目标表的 `staging_record_id/user_id` 关系。
- 租户隔离：现有三张正式表和中转表 RLS。
- 分层决策：ADR-021、ADR-022。

## 本轮范围

- 只读评估字段、回填、RPC、Repository、Store 和测试边界。

## 非范围

- 不创建或执行迁移，不修改业务代码，不查询或修复生产数据。

## 只读证据

- `staging_records` 只有 `target_record_id`；财务目标没有可用 `target_domain_id`。
- 归档函数对新记录写唯一 archive feedback，并返回带类型前缀的引用；刷新列表不读取该返回值。
- feedback 表按用户 RLS 隔离，但允许一对多动作，不适合作为解析状态。
- 当前客户端确有三表并行探测和识别域/最终域混用。

## 评估结论

采用 `target_kind + resolved_domain_key + target_record_id` 的规范化引用，按实际目标关系保守回填；feedback 只用于审计。后续实现拆为 PWA-056A 至 PWA-056E，先数据库 fixture，再 Repository/Store 红绿测试。

## 验证

- `npm run governance:check`：通过。
- `npm run governance:arch`：通过，仅既有 RPC/重复规则人工清单警告。
- `git diff --check`：通过。
- 本轮为纯文档评估，未运行实现专项、PostgreSQL fixture 或 PWA build。

## 未解决风险

- 未审计生产 archived 行的零命中/歧义数量。
- 首轮字段保持可空；是否增加新记录非空约束要以迁移 fixture 和生产只读审计为前提。
- 未验证 PostgREST schema cache 对新字段的刷新时序。

## 对应提交

待实际提交后填写。
