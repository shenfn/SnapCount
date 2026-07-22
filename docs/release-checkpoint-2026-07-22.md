# 2026-07-22 发布检查点

## 当前边界

本检查点只包含代码、迁移、文档和测试准备。尚未执行以下生产动作：

- 未应用数据库迁移。
- 未部署 Edge Functions。
- 未合并 `main`。
- 未触发 TestFlight。
- 未修改 Expression Planner 的候选生成、资格判断、评分或选择算法。

发布候选分支为 `codex/pending-privacy-review-fixes`，基线提交为 `96fe392`。生产授权前以 Draft PR 的固定 head SHA 作为唯一发布来源。

## 本次范围

- PWA 和 iOS 中转站支持在归档前补全、修改字段，并在成功后自动进入下一条。
- 长列表使用稳定标识，避免 iOS 中转站滚动时上下跳动。
- 中转站销毁通过受控 RPC 清理业务引用并进入图片物理删除队列。
- 归档时保留 AI 说明和中转站来源，详情页不再因归档丢失反馈。
- 新账号的财务文案增加证据门禁，禁止无历史依据的次数、趋势和顺序表述。
- 删除记录后清理来源记忆并失效域画像，避免后续继续引用已删除事实。
- Expression Shadow 改为独立、默认关闭的“参与 AI 改进”明确同意。
- Shadow 仅保存机器语义键、评分、资格和拒绝原因，不保存原图、金额、商户、候选 ID 或通知原文。
- 后台 Shadow 按 30 天规则每日清理；关闭开关会立即清理未关联主动点评的数据。
- 主动点评关联的曝光上下文保留，避免破坏反馈外键；保留至账户删除或经核验的删除请求。
- 隐私政策版本更新为 `2026-07-22`；旧客户端的 `2026-07-19` 版本在过渡期仍可注册，但 AI 改进始终默认关闭。

## 脱敏素材

生产算法素材只导出了聚合数值和合成主题，保存在 Git 忽略的 `local-only/algorithm-materials/`。没有导出用户 ID、记录 ID、原文、金额、商户、图片或模型响应。

聚合结果显示样本仍过少且集中：70 条 Shadow、3 个账号、6 条反馈、5 条偏好信号。当前数据不足以支持算法调参，因此本次不修改 Expression Planner。

## 待执行迁移

生产迁移账本最大版本为 `20260721190000`。Supabase CLI `2.109.1` 的 `db push --dry-run` 仅列出：

1. `20260722100000_staging_discard_cleanup_and_archive_feedback.sql`
2. `20260722110000_invalidate_deleted_record_context.sql`
3. `20260722120000_expression_improvement_privacy_controls.sql`

第三份迁移会删除未明确同意账号的历史后台 Shadow 和未关联主动点评的基线曝光。生产执行前必须再次确认脱敏聚合快照和私有备份可读，但不得把历史过度收集数据恢复到生产。

## 已完成验证

- PWA production build 通过。
- Trace Console production build 通过。
- Deno `2.9.3` 对两个 Edge Functions 的类型检查通过。
- 11 项收据、信号和 Shadow 隐私测试通过。
- 47 项 Expression Planner 测试通过，算法输出未改。
- 财务候选、重复图片、安全契约和迁移版本检查通过。
- PostgreSQL 17 按 CI 顺序实际执行三份待发布迁移和安全断言通过。
- Supabase CLI `2.109.1` 生产链接 dry-run 仅包含上述三份迁移。
- 私有快照、备份和 `.env.local` 均被 Git 忽略；diff 未发现密钥或令牌。

Windows 无法本地编译 SwiftUI。提交后必须由 macOS GitHub Actions 完成 iOS Build、单元测试和 `iOS Build Gate`，通过前不得进入生产。

## 生产执行顺序

1. 固定 Draft PR head SHA，复核最终 diff、备份和迁移 dry-run。
2. 经单独授权后应用三份迁移，并验证新列、触发器、ACL、清理数量和定时任务。
3. 合并同一 SHA 到 `main`，等待 PWA、Legal Pages 和两个 Edge Functions 部署完成。
4. 使用一次性账号验证注册、上传、重复图片、中转站编辑、归档、主动点评、销毁原图和删号。
5. 验证默认账号不产生 Shadow；手动开启“参与 AI 改进”后只产生最小化字段；关闭后后台数据被清理。
6. 从同一固定 `main` SHA 手动触发 TestFlight，真机验证中转站长列表、图片展示、快速下一条和隐私开关。

## 回滚边界

- Edge 回滚从已归档的固定源码重新部署，不只依赖 Git revert。
- PWA 和 Legal Pages 回滚到合并前固定 SHA。
- 新增隐私列可保留；回滚客户端时保持 `expression_improvement_enabled=false`。
- 不恢复已清理的历史 Shadow 原文或业务字段，脱敏聚合快照足以保留本次审计结论。
- 数据库不会随 Git 自动回滚，任何补偿 SQL 必须先在 PostgreSQL 17 验证并单独授权。
