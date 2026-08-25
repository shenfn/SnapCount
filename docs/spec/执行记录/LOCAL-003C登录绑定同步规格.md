# LOCAL-003C 规格执行记录

- 目标行为：固定 iOS 本地优先模式下的登录、绑定预览、同步状态、账号切换和退出边界。
- 当前行为：本地 profile、消费/账户本地读写和 outbox 基础已存在；认证服务仍由 `AppState` 直接驱动旧云端 Dashboard；没有正式绑定预览和同步状态 Use Case。
- 权威来源：`docs/spec/模块/iOS本地优先/登录绑定与同步状态规格说明.md`、`LOCAL-DATA-001`、`ADR-039`、iOS `LocalProfileStore`/`LocalDatabase`/`AppState`/`SettingsView`。
- 本轮范围：只读核对现状；补齐 LOCAL-003C 的 workspace 归属、绑定状态、checkpoint、Outbox ownership 和冲突契约；删除“仅下载”出口；更新上游总规格、阶段索引和规格索引。
- 非范围：Swift 业务实现、GRDB 迁移、Supabase/RPC/Edge、首次双向同步、冲突合并、PWA、生产发布和 TestFlight。
- 预计修改文件：模块规格、LOCAL-003 总规格、执行记录、`docs/spec/03-阶段与任务索引.md`、`docs/spec/规格文档索引.md`。
- 基线测试结果：未运行 Swift XCTest；本轮为文档规格变更，Windows 不能替代 macOS iOS Build。
- 红灯测试及失败原因：尚未建立；下一步在独立 `test/LOCAL-003C登录绑定同步红灯` worktree 建立 C1-C13 红灯/特征测试。
- 最小实现：不适用，本轮不修改业务代码。
- 绿灯结果：未验证；需在红灯/实现阶段由 GitHub macOS XCTest、iOS Build 和治理门禁证明。
- PWA/iOS 差异：本片只约束 iOS；PWA 保持维护模式，不接入本地数据库或同步协议。
- GitHub CI 结果：未触发；当前只读文档 worktree 尚未提交或推送。
- 未解决风险：现有登录成功路径仍会刷新旧云端 Dashboard；`sync_generation`、checkpoint、`baseVersion` 等元数据尚未落地；本地云端互通未实现；workspace 已绑定其他账号时的显式切换/解绑 UI 留待后续切片。
- 对应提交：待用户授权后逐文件提交。
- 下一步：建立红灯 worktree；先固定登录不自动上传、workspace 归属、预览三出口、退出保留本地、旧任务隔离、全局 pullCursor 和实体级冲突判定。
