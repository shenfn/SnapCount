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

1. `20260719220000_registration_consent_and_private_defaults.sql`：兼容型迁移。增加同意记录字段，默认关闭 AI 日志，关闭现有账号日志，并收紧 `handle_new_user` ACL。
2. 部署新 PWA 和两个 Edge Functions，完成生产冒烟测试。
3. 根据 `qwen_defaults_and_normalization.template.sql` 用当时的新时间戳创建正式迁移：只归一数据和默认值，不增加会拒绝旧客户端写入的约束。
4. `qwen_only_constraints.template.sql`：保持延后。旧客户端全部退役并再次复审后，再用当时的新时间戳创建正式迁移。

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

## 发布前验证

在生产检查点必须全部通过：

- `npm ci && npm run build`
- Trace Console `npm ci && npm run build`
- 两个 Edge Function 的 `deno check`
- Shadow Planner 全量测试
- 迁移版本唯一性检查
- Deno 固定使用已验证的 `2.9.3`
- iOS 变更必须通过 iOS Build、单元测试和 `iOS Build Gate`
- 首次 `supabase db push --dry-run` 只显示 `20260719220000`，且不包含任何延后模板或重复历史迁移
- 最终 diff 人工复核，确认 Qwen、图片清理、账号删除、租户隔离和 Shadow 均未被旧代码覆盖

## 生产执行顺序

1. 固定最终发布候选 SHA，并创建不可变标签或记录。
2. 完成数据库、函数源码和迁移账本备份。
3. 执行迁移 dry-run，人工确认仅包含预期迁移。
4. 单独应用 078，验证新注册同意字段、函数触发器和 ACL。
5. 合并 `main`，等待 PWA、Legal Pages、`generate-insights` 和 `ingest-receipt` 部署完成。
6. 使用一次性账号完成登录、上传、归档、点评、图片留存、删号和 Shadow 冒烟测试。
7. 确认 Shadow 写入且 `changes_user_output=false`。
8. 稳定后应用 079，再复查老账号设置和 Qwen trace。
9. 从同一个固定 `main` SHA 手动触发一次 TestFlight。

## 回滚原则

- Edge Function 回滚必须从已归档的固定源码重新部署，不能只依赖 Git revert。
- PWA 回滚到合并前 `origin/main` 固定提交；Legal Pages 同步回滚到同一发布版本。
- 078 回滚优先恢复 `user_configs` 快照、旧 `handle_new_user` 定义、触发器和 ACL；新增列可保留，避免破坏已写入的同意审计数据。
- 079 回滚恢复配置快照和旧默认值。080 未执行，因此不应出现硬约束回滚。
- 数据库迁移不会随 Git 自动回滚，任何回滚 SQL 必须先在事务中验证再执行。
- 冒烟失败时立即停止后续迁移和 TestFlight，不继续叠加修复部署。
