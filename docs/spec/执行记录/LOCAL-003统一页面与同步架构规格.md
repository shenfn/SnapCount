# LOCAL-003 统一页面与同步架构规格执行记录

> 状态：规格草案完成；LOCAL-003A 红灯已建立，待 PR #160 合并后重基线
>
> 分支：`docs/LOCAL-003统一页面与同步架构规格`
>
> 基线：`origin/main@be16706`

## 本轮完成

- 核对 L1 当前真实实现：`RootView` 按 session 选择本地壳或旧云端壳；`LocalSettingsView` 没有登录入口。
- 核对已有本地数据库：`local_profiles`、`local_accounts`、`local_expenses`、`local_account_entries`、`local_outbox_operations` 已具备 LOCAL-003 的基础。
- 新增 `LOCAL-003` 模块规格，定义统一页面、本地权威、绑定预览、同步状态、Outbox、代次隔离和冲突出口。
- 新增 `ADR-039`，禁止把本地壳/云端壳扩展成两套长期业务页面。
- 新增 `scripts/test-ios-unified-shell-boundary.mjs`，固定 LOCAL-003A1-A5 的统一页面和本地事实入口不变量。

## 未验证项

- 尚未修改 SwiftUI 页面或 AppState。
- 尚未增加 `sync_generation`、远端映射和游标字段。
- 尚未实现登录绑定、首次导入、Outbox 上传或冲突处理。
- LOCAL-003A 红灯脚本当前预期失败：现有 Root/Records/AppState 仍保留本地/云端分支。
- Windows 无法验证 Swift 编译；实现阶段必须以 macOS GitHub Actions 为准。

## 当前冻结范围

- 根工作区及其他 worktree 的历史 WIP 不修改。
- PWA、Edge、Supabase 生产数据库和生产配置不修改。
- 本轮只提交规格、ADR、执行记录和索引登记。

## 下一步

1. 评审并合并本规格 PR。
2. PR #160 合并后，将本分支重基线到最新 `main`，重新运行 `npm run test:ios-unified-shell-boundary`，确认红灯仍代表业务缺口。
3. 只在 `expense + accounts` 范围实现统一列表、详情、编辑删除和余额投影。
4. A/B 绿灯后再进入登录绑定与同步状态机，不提前上传本地业务数据。
