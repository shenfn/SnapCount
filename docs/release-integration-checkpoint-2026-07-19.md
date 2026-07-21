# 2026-07-19 发布集成检查点

## 执行边界

当前只完成代码集成、迁移整理、CI 和部署流水线准备。以下操作尚未授权，复核前不得执行：

- 不应用线上数据库迁移。
- 不部署 Edge Functions。
- 不合并或推送到 `main`。
- 不触发 TestFlight。
- 不把 `supabase/deferred-migrations/*.template.sql` 直接移入自动迁移目录。

## 固定代码来源

| 代码线 | 固定提交 | 用途 |
|---|---|---|
| PWA 主线 | `origin/main@b55d36d635c0077dd2e2aebe034ed41fef6407e9` | 语音、点评、相机与 Trace Console 基线 |
| iOS 集成底座 | `codex/ios-parity-fixes-2@92601e4ff079adb71f33ceb544f0c8a01ef0f243` | iOS、安全删除、隐私与 Qwen-only 基线 |
| 生产 Shadow 源码 | `105c566e9fc78ee41a363788dbbae6c8acc70c1f` | Shadow Planner、Fact Contract 和分类同期比较 |
| 发布集成分支 | `codex/release-integration` | 最终复核与发布候选 |

Shadow 集成仅移植 `ec612b4` 和 `105c566` 的代码与测试。`6cf36b7` 的迁移同步内容未移植。

## 迁移边界

线上已存在的迁移版本必须保持原名：

- `068_atomic_staging_archive_and_tenant_hashes`
- `20260708122517_user_domain_profiles`
- `20260708123803_domain_profiles_remaining`
- `20260713101632_expression_shadow_runs`
- `20260713130137_expression_feedback_loop`
- `20260716004429_use_fast_photo_vision_defaults`

本次新增迁移按以下顺序处理：

1. 先部署会提交 `2026-07-19` 同意元数据的新 PWA，并让同一 SHA 的新 TestFlight 完成处理。该客户端元数据对旧数据库向后兼容。
2. `20260719220000_registration_consent_and_private_defaults.sql`：增加同意记录字段，默认关闭 AI 日志，关闭现有账号日志，收紧 `handle_new_user` ACL，并在后端拒绝缺少当前协议/隐私/敏感数据同意元数据的注册。执行后旧 TestFlight 将不能新注册，测试人员必须升级。
3. `20260720100000_harden_privileged_rpcs_and_receipt_storage.sql`：安全迁移。撤销匿名画像 RPC 和跨租户余额重算权限，移除客户端 Storage DELETE，建立不可由客户端修改的图片所有权映射，并同时校验所有权和有效业务引用。
4. `20260721110000_user_finance_vocabulary.sql`：增加仅本人可读、仅经受控 RPC 写入的个人财务词表。渠道和支付方式可扩展，一级消费分类保持八类稳定口径；客户端在迁移缺失时会退回内置候选，不阻断记账。
5. `20260721190000_finance_perceptual_duplicate_review.sql`：为收入和支出保存不可逆感知指纹，并让从中转站归档的记录继承指纹。Edge Function 在迁移尚未生效或 PostgREST schema cache 尚未刷新时会自动省略新字段，旧数据库窗口不会阻断记账。
6. 使用 `migrate-legacy-signed-image-urls.mjs` 先 dry-run，再在单独授权后迁移长期签名 URL 对象。数据库任务会持久化 `pending → copied → references_updated → done`；只有复制哈希一致、引用更新成功且旧对象确认不存在后才能完成。
7. 完成生产冒烟测试后，根据 `qwen_defaults_and_normalization.template.sql` 用当时的新时间戳创建正式迁移：只归一数据和默认值，不增加会拒绝旧客户端写入的约束。
8. `qwen_only_constraints.template.sql`：保持延后。旧客户端全部退役并再次复审后，再用当时的新时间戳创建正式迁移。

开发账号如需收集调试 Trace，必须在 078 后由账号所有者显式重新开启 `ai_logs_enabled`，形成真正的 opt-in。

## 生产备份

执行 078 前，必须把以下内容保存到已被 `.gitignore` 覆盖的 `backups/` 目录，并记录生成时间、项目 ref 和校验和：

- `user_configs` 中会被 078/079 修改的账号配置和同意字段。
- `public.handle_new_user()` 的 `pg_get_functiondef` 输出。
- `on_auth_user_created` 的 `pg_get_triggerdef` 输出。
- `handle_new_user` 的完整 ACL 和 owner。
- 线上 `supabase_migrations.schema_migrations` 账本。
- Edge Functions 列表、版本和部署时间。
- 当前 `ingest-receipt v166` 的源码归档；已知对应代码提交为 `105c566`。
- 当前 `generate-insights v14` 的源码归档，并在生产操作前确认其对应提交。
- 合并前 `origin/main` 固定提交或保护标签。

数据库备份和 Storage 清单不得提交到 GitHub。现有 `backups/`、备份脚本和本地凭据均已在 `.gitignore` 中隔离。

生产备份包含密码哈希、Session、Refresh Token、AI 日志和原始图片。长期保留前必须加密并收紧 Windows ACL；`.gitignore` 只能阻止 Git 提交，不能替代磁盘加密和访问控制。失败的 partial dump 不得作为有效恢复点。

## 发布前验证

在生产检查点必须全部通过：

- `npm ci && npm run build`
- Trace Console `npm ci && npm run build`
- 两个 Edge Function 的 `deno check`
- Shadow Planner 全量测试
- 迁移版本唯一性检查
- 安全迁移契约检查 `npm run check:security-contracts`
- Deno 固定使用已验证的 `2.9.3`
- iOS 变更必须通过 iOS Build、单元测试和 `iOS Build Gate`
- `supabase db push --dry-run` 只显示 `20260719220000`、`20260720100000`、`20260721110000` 和 `20260721190000`，且不包含任何延后模板或重复历史迁移
- 安全迁移后匿名 Storage 对象可见数为 0，匿名画像 RPC 不可执行，普通登录用户不能执行余额重算或图片引用迁移
- 旧日期路径和用户路径都必须通过一次性账号验证：本人可生成签名 URL，其他账号不可列举、签名或删除
- 普通登录用户直接新增和编辑 `data_records` 必须成功；向自己的记录注入其他用户路径必须被数据库触发器拒绝
- 新 PWA 和待发布 iOS 必须先确认会提交当前协议版本；迁移后缺少协议版本或敏感数据确认的直接 Auth API 注册必须失败，合法注册必须记录服务器时间
- `npm run migrate:legacy-signed-images` dry-run 不得出现跨用户共享路径或未完成旧任务，执行模式必须同时显式传入 `--execute --yes`
- 长期 URL 执行结束必须为 `execution_complete` 且开放任务数为 0；中断后必须通过数据库任务恢复，不能只依据本地报告
- 账号删除必须覆盖数据库未引用但仍位于 `user_id/` 或 `tmp/user_id/` 下的 Storage 对象；进入 `deleting` 后至少等待 5 分钟静默期，并在删除业务数据后再次确认队列为空，才允许删除 Auth 用户
- CI 必须在 PostgreSQL 17 中实际执行四份迁移和 `scripts/test-security-migration.sql`，不能只依赖 SQL 文本检查
- 最终 diff 人工复核，确认 Qwen、图片清理、账号删除、租户隔离和 Shadow 均未被旧代码覆盖

## 生产执行顺序

1. 固定最终发布候选 SHA，并创建不可变标签或记录。
2. 完成数据库、函数源码和迁移账本备份，并确认备份已加密且 ACL 已收紧。
3. 执行迁移 dry-run，人工确认仅包含四份兼容迁移。
4. 合并 `main`，等待 PWA、Legal Pages、`generate-insights` 和 `ingest-receipt` 部署完成；先确认新 PWA 注册请求携带 `2026-07-19` 同意元数据。
5. 从同一个固定 `main` SHA 手动触发 TestFlight 并等待构建处理完成，确认待发布 iOS 使用同一协议版本。
6. 应用 `20260719220000`、`20260720100000`、`20260721110000` 和 `20260721190000`，验证注册字段、服务器时间、所有权触发器、RPC ACL、Storage RLS、个人词表 RLS、感知指纹继承与跨账号隔离。此时旧 TestFlight 的注册能力按计划停止。
7. 运行长期签名 URL dry-run；经单独确认后执行对象迁移，并验证旧签名 URL 已失效、新路径可访问。
8. 使用一次性账号完成登录、上传、归档、点评、图片留存、删号和 Shadow 冒烟测试。
9. 确认 Shadow 写入且 `changes_user_output=false`。
10. 稳定后根据模板创建并应用新的 Qwen 默认值迁移，再复查老账号设置和 Qwen trace。

## 回滚原则

- Edge Function 回滚必须从已归档的固定源码重新部署，不能只依赖 Git revert。
- PWA 回滚到合并前 `origin/main` 固定提交；Legal Pages 同步回滚到同一发布版本。
- 078 回滚优先恢复 `user_configs` 快照、旧 `handle_new_user` 定义、触发器和 ACL；新增列可保留，避免破坏已写入的同意审计数据。
- Storage/RPC 安全迁移原则上不回退到 bucket-wide `anon` 或客户端 DELETE。若图片访问异常，应修复所有权函数或引用数据，不能恢复越权策略。
- 长期签名 URL 对象迁移不以 Git 回滚。未到 `done` 的任务必须从数据库状态继续；已到 `done` 后如需恢复，必须先复制回旧路径、原子恢复引用，再评估是否重新生成短期 URL，不能只恢复数据库 URL 字符串。
- 079 回滚恢复配置快照和旧默认值。080 未执行，因此不应出现硬约束回滚。
- 数据库迁移不会随 Git 自动回滚，任何回滚 SQL 必须先在事务中验证再执行。
- 冒烟失败时立即停止后续迁移和 TestFlight，不继续叠加修复部署。
