# PWA-008 设置配置首片执行记录

> 日期：2026-08-16
>
> 基线：`00d5c1c`（PR #67 合并提交）
>
> 分支：`feature/PWA设置配置边界`

> 状态：已完成（PR #68，merge commit `21e011b`）

## 目标与范围

- 将 `user_configs` 的读取、字段映射、白名单更新和共享状态集中到 Settings Repository/Feature。
- 保留 `useStore` 的兼容 API，迁移 PageSettings、PageAiVisionSettings 和 ModalWelcome 的配置直连。
- 为 retention 成对保存提供明确结果，并阻断保存失败后的立即清理。
- 不迁移数据导出、`cleanup_all_images` transport、signOut、AuthPage 注册同意、数据库、Edge、iOS 或部署。

## 实现

- 新增 `src/repositories/settingsRepository.js`：modern/legacy read、错误分类、白名单 upsert、传输时间戳。
- 新增 `src/features/settings/settingsConfig.js`：客户端字段映射、默认值、值归一化和数据库 DTO。
- 新增 `src/features/settings/createSettingsState.js`：共享快照、用户 reset、同用户强制加载 revision、按字段更新回滚和 retention 失败结果。
- `useStore` 继续暴露 `settingsState`、`loadUserSettings`、`toggleSetting`、`setSetting`、`setSettings`、`setRetention`。
- 三个配置消费者改走 Store；PageSettings 只保留导出、清理和退出登录所需的 Supabase/fetch 直连。
- 架构基线页面直连从 5 项收紧到 3 项：AuthPage、PageSettings Supabase、PageSettings fetch。

## 场景与验证

| 场景/命令 | 结果 |
|---|---|
| PWA-008 至 PWA-014 Node 行为与页面契约 | 14/14 通过 |
| 表达计划/反馈回归 | 22/22 通过 |
| `npm run test:expression-presentation` | 22/22 通过 |
| `npm run test:finance-occurred-at` | 通过 |
| `npm run check:security-contracts` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；tools 0、页面直连 3、Domain 0 |
| `npm run build` | 通过；157 modules transformed |
| 注册同意服务端契约 | 通过；4 项检查，临时用户已清理 |
| `git diff --check` | 通过 |

## 未验证与剩余风险

- GitHub PR 综合、治理、架构和预览门禁已通过并合并，merge commit 为 `21e011b`。
- Windows 本地不能编译 iOS，本切片没有 iOS 变更；不触发 iOS Build Gate。
- `PageSettings` 的数据导出查询错误处理和隐私清理 transport 仍是后续独立切片。
- Repository 对 modern vision 列缺失时可以 legacy read；legacy 模式下修改新增分链路字段会返回数据库错误，页面由 Store 显式提示失败。
- 构建仍有既有 chunk size 和 vconsole eval 警告，不属于本切片回归失败。

## 下一步

1. 保留当前 worktree 和分支，不删除历史对象。
2. 当前任务转入 PWA-026 中转生命周期边界评估。
