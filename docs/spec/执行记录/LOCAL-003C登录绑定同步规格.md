# LOCAL-003C 规格执行记录

- 目标行为：固定 iOS 本地优先模式下的登录、绑定预览、同步状态、账号切换和退出边界。
- 当前行为：本地 profile、消费/账户本地读写和 outbox 基础已存在；认证服务仍由 `AppState` 直接驱动旧云端 Dashboard；本片新增本地同步状态、绑定预览 Use Case 和绑定门禁，但尚未接入 AppState/Settings。
- 权威来源：`docs/spec/模块/iOS本地优先/登录绑定与同步状态规格说明.md`、`LOCAL-DATA-001`、`ADR-039`、iOS `LocalProfileStore`/`LocalDatabase`/`AppState`/`SettingsView`。
- 本轮范围：补齐 LOCAL-003C 契约，并实现本地同步状态、workspace 绑定、checkpoint、绑定预览 Use Case、AppState/Settings 状态展示和 Outbox 上传门禁；删除“仅下载”出口；更新阶段索引。
- 非范围：AppState/Settings 页面接线、Supabase/RPC/Edge、首次双向同步、冲突合并、PWA、生产发布和 TestFlight。
- 预计修改文件：本地状态模型、GRDB 迁移、绑定预览 Use Case、XCTest、执行记录和阶段索引。
- 基线测试结果：未运行 Swift XCTest；Windows 无 Swift/Xcode，不能替代 macOS iOS Build。
- 红灯测试及失败原因：`LocalBindingPreviewUseCaseTests` 已覆盖 workspace 初始状态、预览、绑定、错绑、退出禁用、checkpoint 和 Outbox 门禁；Windows 无法运行。
- 最小实现：新增 `local-v2-sync-state` GRDB 迁移、`LocalSyncState`/独立 `LocalConflictState`/checkpoint/binding 模型、`LocalProfileStore` 状态读写、`LocalBindingPreviewUseCase`，并把绑定预览与同步授权出口接入 `AppState`/`SettingsView`。
- 绿灯结果：未验证；需由 GitHub macOS XCTest、iOS Build、治理门禁和源边界门禁证明。冲突状态独立轴的上传门禁已补充 XCTest。
- PWA/iOS 差异：本片只约束 iOS；PWA 保持维护模式，不接入本地数据库或同步协议。
- GitHub CI 结果：未触发；当前 feature 分支尚未推送。
- 未解决风险：现有登录成功路径仍会刷新旧云端 Dashboard；`baseVersion` 尚未持久化；本地云端互通和首次传输未实现；云端范围读取复用 `data_domains` 定义，后续同步协议仍需独立服务端契约；workspace 已绑定其他账号时仍只有退出/暂不开启出口。
- 对应提交：待本片验证后提交。
- 下一步：在 macOS CI 验证迁移、AppState/Settings 接线与 XCTest；首次导入与 Outbox 上传进入 `LOCAL-003D`。
