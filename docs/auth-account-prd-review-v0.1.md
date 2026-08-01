# 芥子账号与认证 PRD 复审记录

版本：`V0.1.1`

日期：`2026-08-01`

评审对象：`docs/auth-account-contract-v0.1.md`

基线：`origin/main@f72e63b0bc5fb4d1856493b0a846e605b64c8aa0`

## 一、总体判定

**结论：代码复评有条件通过，发布门禁未通过。**

现有认证 PRD 已覆盖邮箱密码、Confirm email、PKCE 回跳、密码恢复、capability 解耦和本地清理，足以作为当前开发与测试依据。历史同意与异步删号的代码 P0 已补齐并通过本地 PWA、静态安全和 PostgreSQL 17 迁移测试；但在进入生产配置和 App Review 前，仍必须关闭下列发布 P0：

1. iOS 认证改动必须通过 macOS 编译、单测和真机邮件回跳；Windows 静态检查不能替代此门禁。
2. 自定义 SMTP、SPF/DKIM/DMARC、Site URL 和精确 redirect allowlist 必须配置并用非项目成员邮箱验证。
3. QQ、163、Outlook、Gmail、iCloud 的确认、重发与恢复邮件尚未做真实送达验收。
4. 数据库迁移、Edge 部署、PWA 合并、Confirm email 和 TestFlight 必须分别授权，不能以一次“发布许可”打包执行。

本次属于补做评审，但仍来得及：生产开关尚未打开，迁移和 Edge 尚未部署，剩余 P0 仍可在发布基线固定前修正。已完成的代码需要按本记录回归，不能视为自动通过。

## 二、需求范围复核

### 2.1 V1 必须实现

| 模块 | 用户目标 | 验收结果 |
| --- | --- | --- |
| 注册与确认 | 证明控制注册邮箱 | 只有有效 session 才能进入业务数据；无 session 进入待确认态 |
| 登录 | 正确恢复本人会话 | 登录成功不被 `upload_token` 同步失败回滚 |
| 历史同意 | 了解当前数据处理和跨区域 AI 路径 | 缺任一当前版本时不加载业务数据、不调用 Qwen |
| 密码恢复 | 在忘记密码时恢复账号 | recovery 会话只能改密，不能短暂进入业务首页 |
| 登出 | 在本设备退出且不恢复旧数据 | 清 SDK session、Keychain/本地 token、快照和图片缓存 |
| 删号 | 发起可追踪的全部数据删除 | 幂等受理、立即本地退出、可凭查询编号了解状态 |
| 审核准备 | 让 App Review 可复现完整流程 | 独立审核账号、合成数据、Review Notes、隐私标签一致 |

### 2.2 V1 不包含

- Sign in with Apple、微信、Google、手机号登录和 Passkey；
- 多身份自动合并、邮箱换绑和账户找回人工工单系统；
- 客户端存储 SMTP、Service Role、Qwen 或 Apple 私钥；
- 自动执行生产迁移、部署或 TestFlight 上传。

以上能力可在 V1.1 评估，但业务数据仍只绑定稳定的 Supabase `auth.users.id`，不能因增加登录方式改写用户主键。

## 三、状态机强制评审

### 3.1 认证状态

| 当前状态 | 可流转至 | 触发 | 出口是否完整 |
| --- | --- | --- | --- |
| `signedOut` | `signingIn` / `awaitingVerification` / `recovering` | 登录、注册、恢复链接 | 是 |
| `signingIn` | `consentRequired` / `authenticatedPendingCapability` / `signedOut` | session 成功、版本检查、失败 | 是 |
| `awaitingVerification` | `signedOut` / 自身 | 确认成功、重发、链接过期 | 是 |
| `recovering` | `signedOut` / 自身 | 改密成功、校验/网络失败 | 是 |
| `consentRequired` | `authenticatedPendingCapability` / `signedOut` / 自身 | 同意成功、退出、提交失败 | 是，代码与数据库测试已实现 |
| `authenticatedPendingCapability` | `authenticated` / `signedOut` / 自身 | token 同步、session 失效、重试 | 是 |
| `authenticated` | `recovering` / `deleting` / `signedOut` / 自身 | 恢复链接、删号、登出、刷新 | 是 |
| `deleting` | `signedOut` | 服务端受理后本地清理 | 是；远端状态见下表 |

约束：`consentRequired` 持有有效 Auth session 只是为了提交同意或退出，不能加载用户业务表、图片缓存、快捷指令 capability，也不能触发任何 AI 接口。

### 3.2 邮件动作状态

| 当前状态 | 可流转至 | 触发 | 出口是否完整 |
| --- | --- | --- | --- |
| `idle` | `sending` | 用户提交 | 是 |
| `sending` | `sent` / `failed` | 邮件服务返回 | 是 |
| `sent` | `cooldown` / `verified` / `expired` | 客户端倒计时、点击链接 | 是 |
| `cooldown` | `sending` / `verified` | 冷却结束、完成验证 | 是 |
| `failed` | `sending` / `idle` | 重试、返回 | 是 |
| `expired` | `sending` / `idle` | 重发、返回 | 是 |

### 3.3 账户删除状态

| 当前状态 | 可流转至 | 触发 | 出口是否完整 |
| --- | --- | --- | --- |
| `requested` | `cleaning` / `failed` | worker 接单/准备失败 | 是 |
| `cleaning` | `deleting` / `failed` | 图片队列清空/任务失败 | 是 |
| `deleting` | `completed` / `cleaning` / `failed` | 最终删除、发现残留、删除失败 | 是 |
| `failed` | `requested` / `cleaning` / `deleting` / 人工处理 | 到达重试时间或运维恢复 | 是，租约过期恢复与自动重试已测试 |
| `completed` | 终态 | Auth 用户和业务数据删除完成 | 是 |

删除请求表必须保留足够时间用于客服/审计查询。若 Auth 用户被物理删除后无法再凭 session 查询，客户端要在受理响应中保存不含隐私的 `request_id` 和支持信息；不能承诺一个实际上无法查询的“进度页”。

## 四、多角色评审明细

### 4.1 阻断项

| # | 问题 | 角色 | 修改要求 |
| --- | --- | --- | --- |
| P0-1（代码已关闭） | 历史账号只有有效 session，没有当前敏感数据版本 | 产品、研发、测试、法务 | 三版本、服务端时间、append-only 审计、客户端门禁和 Edge 双重门禁已实现 |
| P0-2（代码已关闭） | 异步删号响应没有稳定 request id/ETA/查询契约 | 产品、研发、测试、法务 | 完整本机回执、生命周期状态、原子租约、失败重试和 30 天支持回执已实现 |
| P0-3 | iOS 无本机 Swift/Xcode 验证 | 研发、测试 | macOS CI 编译和单测通过，真机验证四类邮件/回跳场景 |
| P0-4 | 生产动作授权边界可能混淆 | 研发、运营 | PR 合并、PWA/Edge 部署、迁移、Auth 开关、TestFlight 分别记录授权和固定 SHA |
| P0-5（代码已关闭） | 停用账号可修改或重建 `user_configs` 恢复能力 | 研发、安全 | 客户端只获偏好列 UPDATE；旧版 upsert 仅在同用户配置行已存在时可用，缺失行 INSERT、DELETE 和服务端字段写入均被拒绝并由真实 PostgreSQL 验证 |
| P0-6 | 生产邮件与 redirect 配置尚未验证 | 运维、测试 | 自定义 SMTP、SPF/DKIM/DMARC、Site URL 和精确 allowlist 配置完成并用非成员邮箱实测 |

### 4.2 重要项

| # | 问题 | 角色 | 修改要求 |
| --- | --- | --- | --- |
| P1-1 | 登录/确认/恢复漏斗尚无最小可观测性 | 产品、运营、测试 | 定义仅含事件名、平台、结果码和耗时的隐私安全事件；不记录邮箱/token/URL query |
| P1-2 | 邮箱服务商送达率未知 | 产品、运营 | 用 QQ、163、Outlook、Gmail、iCloud 合成邮箱实测，记录 5 分钟内送达和垃圾箱情况 |
| P1-3（已决策） | 删号完成后的主动通知渠道 | 产品、法务 | V1 采用“本机受理回执 + 支持编号”；不承诺实时查询或完成邮件 |
| P1-4 | 版本升级策略缺少宽限期定义 | 产品、法务、研发 | 敏感数据/AI 版本升级立即阻断 AI；纯文案变化是否阻断需逐版本决策并记录 effective_at |

### 4.3 建议项

| # | 建议 | 角色 | 处理 |
| --- | --- | --- | --- |
| P2-1 | V1.1 评估 Apple 登录与邮箱 OTP | 产品、设计 | 不阻塞 V1；先定义账号绑定冲突策略 |
| P2-2 | 使用 Universal Link 替代自定义 scheme | 研发、安全 | 作为回跳加固项，不阻塞首版自定义 scheme |
| P2-3 | 审核账号自动填充合成数据 | 运营、测试 | 用受控脚本或审核前人工准备，不进入客户端后门 |

## 五、关键接口与数据契约

### 5.1 同意状态

| 字段 | 类型 | 必填 | 说明 | 示例 |
| --- | --- | --- | --- | --- |
| `needs_consent` | boolean | 是 | 是否阻断业务数据和 AI | `true` |
| `missing` | string[] | 是 | 缺失或过期的同意键 | `["sensitive_data"]` |
| `required_versions` | object | 是 | 服务端当前版本 | `{ "privacy": "2026-07-22" }` |
| `accepted_versions` | object | 是 | 用户已接受版本，可为空 | `{ "privacy": null }` |
| `legal_consent_at` | timestamptz | 否 | 服务端记录的法律文档同意时间 | `2026-08-01T10:00:00Z` |
| `sensitive_data_consent_at` | timestamptz | 否 | 服务端记录的敏感数据同意时间 | `2026-08-01T10:00:00Z` |

同意提交必须使用服务端时间、校验客户端提交版本等于当前版本，并写入 append-only 审计事件。客户端不能直接修改同意时间或版本列。

### 5.2 删号受理

| 字段 | 类型 | 必填 | 说明 | 示例 |
| --- | --- | --- | --- | --- |
| `request_id` | UUID | 是 | 幂等请求查询编号 | `...` |
| `status` | enum | 是 | 兼容响应外壳：`deletion_pending/deleted` | `deletion_pending` |
| `deletion_status` | enum | 是 | 生命周期：`requested/cleaning/deleting/completed/failed` | `requested` |
| `requested_at` | timestamptz | 是 | 服务端受理时间 | `2026-08-01T10:00:00Z` |
| `estimated_completion_at` | timestamptz | 是 | 预计完成时间戳，不是绝对 SLA | `2026-08-02T10:00:00Z` |
| `retryable` | boolean | 是 | 是否会自动重试 | `true` |
| `support_reference` | string | 是 | `DEL-` + 12 位大写十六进制；客服短引用，不是查询凭证 | `DEL-AB12CD34EF56` |

服务端内部 `last_error` 不直接返回客户端。客户端只展示稳定错误类型和支持出口。客户端必须先验证完整回执并确认本机持久化成功，之后才清 session；响应丢失时仅在退出前用当前 session 对账一次。Auth 用户最终删除后，V1 不提供实时匿名进度接口。

## 六、异常与安全规则

- 同意状态查询失败时 fail closed：不加载业务数据、不调用 AI，允许重试、退出和删号。
- `consent_required` 使用 HTTP 403；门禁服务不可用使用 503；未登录使用 401；删除中的账号使用 410。
- PWA/iOS 都必须防止重复提交；同意 RPC 和删号请求必须幂等。
- 回跳 URL 在成功、失败或取消后一次性清除 token/code/error 参数。
- 邮件接口响应不能透露邮箱是否已注册。
- 日志不得包含邮箱、access/refresh token、PKCE code、完整回跳 URL、图片、识别正文或用户财务数据。
- 老版本客户端仍可登录和删号；未完成当前同意时不得通过 upload token、JWT 或缓存绕过 AI 门禁。

## 七、验收矩阵

| 编号 | 场景 | 预期 | 优先级 |
| --- | --- | --- | --- |
| AUTH-01 | Confirm email 开启后注册只返回 user | 显示待确认，不写业务数据 | P0 |
| AUTH-02 | 历史账号版本为空后登录 | 展示同意门禁，首页和缓存不可见 | P0 |
| AUTH-03 | 历史账号直接调用 `ingest-receipt` | 403 `consent_required`，Qwen 未被调用 | P0 |
| AUTH-04 | 历史账号直接调用 `generate-insights` | 403 `consent_required`，不生成/写缓存 | P0 |
| AUTH-05 | 同意提交携带过期版本 | 原子拒绝，状态保持未同意 | P0 |
| AUTH-06 | 同意成功后重复提交 | 幂等成功或写独立审计事件，不产生错误状态 | P1 |
| AUTH-07 | recovery 链接冷启动 | 只显示改密页，不加载任何业务数据 | P0 |
| AUTH-08 | capability 同步失败 | 保持登录，可在设置中重试 | P0 |
| AUTH-09 | 删号重复点击/重试 | 返回同一 active request id，不重置已完成进度 | P0 |
| AUTH-10 | 删号 worker 失败 | 状态可重试，用户看到查询编号与支持出口 | P0 |
| AUTH-11 | 登出后冷启动 | 不恢复旧 session、快照或签名图片 URL | P0 |
| AUTH-12 | QQ/163/Gmail/Outlook/iCloud | 注册、重发、恢复邮件在受控时限内可完成 | P1 |

### 7.1 PRD 实现完整性核查

核查口径区分“代码存在”和“端到端发布可验收”。共 12 个功能点：已实现 6 个（50%），部分实现 5 个（42%），未完成 1 个（8%）。“已实现”仍不替代 macOS CI、测试项目或真实邮件送达验证。

| 功能点 | 判定 | 静态/自动证据 | 尚需验证 |
| --- | --- | --- | --- |
| AUTH-01 | 部分实现 | 两端只以 session 进入业务；PWA auth-flow 测试覆盖待确认 | Confirm email 受控开启后的真实注册回跳 |
| AUTH-02 | 已实现 | 两端 fail closed；版本、时间戳与跨用户 generation 已覆盖 | iOS macOS CI |
| AUTH-03 | 已实现 | multipart 与表达规划 JSON action 均调用共享门禁 | Deno CI、测试项目直调 |
| AUTH-04 | 已实现 | `generate-insights` 在任何业务表读取前校验同意 | Deno CI、测试项目直调 |
| AUTH-05 | 已实现 | PostgreSQL 17 拒绝过期版本且状态不变 | 无新增代码项 |
| AUTH-06 | 已实现 | 重复接受当前版本成功并追加独立审计事件 | 无新增代码项 |
| AUTH-07 | 部分实现 | PWA callback 单测；两端恢复态隔离代码已存在 | macOS CI、真机/浏览器过期与重复链接 |
| AUTH-08 | 部分实现 | 两端与登录解耦、三次退避、设置页重试 | 弱网和跨账号手工验证 |
| AUTH-09 | 已实现 | 服务端复用 active request；PWA 覆盖响应丢失对账 | 测试项目真实 Edge 幂等调用 |
| AUTH-10 | 部分实现 | PostgreSQL 验证租约互斥和过期恢复；客户端显示支持编号 | 真实 Storage/Auth 删除失败演练 |
| AUTH-11 | 部分实现 | PWA 用户域/签名 URL 清理与 iOS 本机回执测试已补 | iOS 真机和浏览器冷启动 |
| AUTH-12 | 未完成 | 无 | 五类邮箱真实送达、垃圾箱和 5 分钟时限记录 |

需要手工执行的高风险用例：

| 用例 | 前置条件 | 预期结果 |
| --- | --- | --- |
| TC-AUTH-01 | 测试项目开启 Confirm email，使用非项目成员邮箱注册 | 无 session 时停在待确认页，不读取业务表；确认后回到登录 |
| TC-AUTH-02 | iOS 被系统杀死后从 recovery 邮件冷启动 | 只显示设置新密码页，不出现首页、快照或签名图片 |
| TC-AUTH-03 | 删号受理后立即断网并重启两端 | 本机仍显示完整支持编号；不存在可自动恢复的旧 session |
| TC-AUTH-04 | A 账号加载后快速退出并登录 B 账号 | A 的记录、详情、图片 URL、异步结果均不能写入 B 的界面 |
| TC-AUTH-05 | QQ、163、Outlook、Gmail、iCloud 合成账号 | 确认、重发、恢复邮件在记录时限内可达，过期链接有重试出口 |

## 八、发布门禁与回滚

1. 完成 P0 代码和自动测试；iOS 在 macOS CI 通过。
2. 在测试项目应用迁移，验证新账号、历史账号、旧客户端和删号 worker。
3. 配置自定义 SMTP、SPF、DKIM、DMARC 和精确 redirect allowlist。
4. 先部署兼容迁移，再部署双重门禁代码；确认旧客户端至少能登录、同意和删号。
5. 最后单独开启 Confirm email；每步使用固定 SHA 和独立授权。
6. 失败时关闭客户端入口或回滚 Edge 固定源码；已应用数据库迁移使用补偿 SQL，不用 Git revert 假装回滚数据库。

## 九、待确认项

### 必须在提交审核前确认

1. `[已决策]` V1 使用本机回执与支持编号，不建设实时进度页，也不发送删号完成邮件。
2. `[待确认]` “通常在 24 小时内完成”是否与当前 cron、失败重试上限和实际运维能力一致。
3. `[待确认]` 当前隐私政策是否已由运营者确认可用于中国内地 Qwen + 新加坡 Supabase 的数据路径披露。

### 可后续版本确认

1. `[假设]` V1.1 优先评估 Sign in with Apple 和邮箱 OTP，不在 V1 同时引入。
2. `[后续研究]` 若建设公开删号状态查询页，必须使用不可枚举、可撤销的一次性查询凭证，不能把支持编号当凭证。

## 十、复评结论门槛

当 AUTH-01 至 AUTH-11 全部通过、P0-3/P0-4/P0-6 关闭、iOS macOS CI 和真机回跳通过后，本 PRD 可从“有条件通过”更新为“通过”。在此之前可以继续开发和测试，但不能开启生产 Confirm email，也不能以该分支提交 App Review。
