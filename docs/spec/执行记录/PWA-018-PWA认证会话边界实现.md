# PWA-018 认证会话边界实现执行记录

> 日期：2026-08-16
>
> 基线：`076d256`（PWA-018 评估 PR #69 合并提交）
>
> 分支：`feature/PWA认证会话边界`

## 目标与范围

- 将 App 设为唯一认证会话事件入口。
- 将认证 transport 收进 Auth Repository，将 session 去重、generation、切换和退出收进 Session Feature。
- 保留 `useStore` 兼容门面，仅增加认证动作和用户/run 写回保护。
- AuthPage 只负责输入、同意勾选和结果展示，不直接写用户状态、配置或触发全量加载。

## 非范围

- 不修改数据库迁移、RLS、trigger、Edge Function、Planner、iOS、部署配置或生产数据。
- 不重写 `loadData` 的全部查询，不迁移 Settings Feature 已有职责。
- 不改变登录/注册视觉、邮箱确认策略、密码策略或产品文案。

## 实际修改

| 文件 | 作用 |
|---|---|
| `src/repositories/authRepository.js` | 封装 session、订阅、登录、注册 consent metadata、退出和错误透传 |
| `src/features/auth/createSessionState.js` | 去重同一 session，保护 generation，切换/退出 reset 和加载编排 |
| `src/App.vue` | 只初始化并注销认证订阅 |
| `src/components/pages/AuthPage.vue` | 通过 Store 认证动作，不再直连 Supabase 或手动加载数据 |
| `src/composables/useStore.js` | 暴露认证门面；为 `loadData` 主查询和 `resetUserData` 增加用户/run 隔离 |
| `scripts/architecture-boundary-baseline.json` | 移除已消除的 AuthPage 直连基线 |
| `src/**/__tests__`、`scripts/test-pwa-auth-boundary.mjs` | 固定认证边界、竞态、退出、同意和 reset 不变量 |
| `scripts/test-pwa-settings-boundary.mjs` | 将旧的“AuthPage 直接写配置”断言迁移为“认证边界不得访问配置” |
| `tools/ai-validation/expression-planner/tests/pwa-feedback-exposure-contract.test.mjs` | 将用户切换顺序断言迁移到 Session Feature 实际权威落点 |

## 场景与证据

| 场景 | 证据 |
|---|---|
| PWA-018 | App/AuthPage 源契约测试通过；AuthPage 不再直连 Supabase、写 session 或调用 `loadData` |
| PWA-019 | 同一用户的 `getSession`、`INITIAL_SESSION`、`SIGNED_IN` 去重测试通过 |
| PWA-020 | 用户/run guard 和切换旧响应失效测试通过 |
| PWA-021 | 退出立即 reset、旧加载失效、账户/洞察/签名图片状态清理测试通过 |
| PWA-022 | 订阅返回真实 unsubscribe，App 卸载调用测试通过 |
| PWA-023 | Repository consent metadata 测试通过；注册同意真实契约通过，服务端时间持久化且默认 AI 日志关闭 |
| PWA-024 | 登录/注册 transport 错误结构透传；页面不再自动重试认证写操作的源契约通过 |
| PWA-025 | Auth Feature 不依赖 Supabase、Vue 或 Settings 规则；设置回归通过 |

## 验证结果

### 业务测试

- 认证边界：11/11 通过。
- 设置回归：14/14 通过。
- 表达 Repository/Feature/反馈契约：22/22 通过。
- 表达呈现：22/22 通过。
- 金融发生时间契约：通过。
- 安全契约：通过。
- 注册同意真实契约：通过，临时账号已清理。

### 构建与门禁

- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；生产 `tools/` 依赖 0，Domain 禁止依赖 0，页面直连维持既有 ratchet 基线 2 项。
- `npm run build`：通过，159 modules transformed。
- `git diff --check`：通过。

### 浏览器烟测

- 带 `.env.local` 环境变量的独立 Vite 服务 `http://127.0.0.1:4175/` 冷启动通过：登录/注册首屏可见，控制台 0 error、0 warning。
- 旧的 4174 服务来自根工作区且未带 Vite Supabase 环境变量，首次烟测报 `Missing VITE_SUPABASE_URL`；已分类为环境失败，未作为业务失败。

## 未验证项与剩余风险

- PR #70 远程门禁已通过；尚未合并，合并提交号待产生。
- 未执行真实登录、注册写入或业务数据写入；浏览器烟测只检查未登录首屏。
- `governance:arch` 中 RPC 契约和重复业务规则仍是既有人工基线警告，不属于本切片新增问题。
- 对应提交：`78f0379`；PR：[#70](https://github.com/shenfn/SnapCount/pull/70)。

## 下一步

1. 用户合并 PR #70 后，以实际 merge commit 更新阶段索引。
2. 保留当前 worktree 和分支，不删除历史对象。
3. 合并后进入下一个 PWA 边界评估。
