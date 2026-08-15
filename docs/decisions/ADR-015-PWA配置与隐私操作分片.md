# ADR-015：PWA 配置与隐私操作分片

> 状态：接受
>
> 日期：2026-08-16

## 决策

将“设置与隐私”拆为三个连续但独立的边界：用户配置、隐私副作用、数据导出。首片只统一 `user_configs` Repository/Feature 与共享状态；原图清理、数据导出和认证分别保留独立后续 Spec。

## 原因

- `PageSettings` 当前混合配置、清理、导出和认证，整体搬迁只会把大页面变成大 Feature。
- 配置更新是可回滚状态同步；原图清理是不可逆副作用；数据导出是多表读取与本地序列化，三者失败模型不同。
- 注册同意和 Expression improvement 清理已有服务端 trigger 权威，客户端不能重新实现。
- 首先统一配置快照可以消除 PageSettings、PageAiVisionSettings 和 ModalWelcome 的重复查询，同时保持其他高风险流程不动。

## 禁止

- 不建立一个包含配置、导出、清理和 signOut 的 `settingsRepository`。
- 不允许组件通过通用 patch 更新任意 `user_configs` 列。
- 不因迁移配置而移动或复制服务端 consent、retention、opt-out 清理规则。
- 不在配置保存失败时继续执行原图立即清理。
- 不为了让架构计数归零而把 AuthPage 或导出逻辑塞进 Settings Feature。

## 后续

配置首片稳定后，分别评估：

1. Privacy Operations：原图立即清理、状态返回和失败恢复。
2. Data Export：查询错误、日期边界、字段脱敏、序列化和下载。
3. Auth Session：注册同意、登录、退出和用户切换。
