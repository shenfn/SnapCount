# LOCAL-003D TDD 执行记录

- 目标行为：已绑定且开启同步的 workspace 才能启动首次同步；同步按 workspace checkpoint 读取 pending Outbox，远端成功后标记已发送并导入远端 expense/accounts；传输失败不撤销本地事实，旧 attempt 不能写回新状态。
- 当前行为：LOCAL-003C 已提供绑定、同步代次、checkpoint 和 Outbox 门禁，但没有同步协调器、Outbox 上传结果处理或首次导入编排。
- 权威来源：`docs/spec/模块/iOS本地优先/统一页面与云端同步规格说明.md`、`docs/spec/模块/iOS本地优先/登录绑定与同步状态规格说明.md`、`docs/decisions/ADR-036-本地优先数据权威与AI能力正交.md`、`docs/decisions/ADR-039-iOS统一页面与本地权威同步.md`。
- 本轮范围：`expense/accounts` 首片；新增可注入 `LocalSyncTransport`、同步协调器、Outbox 上传读取/成功失败状态更新、无 Outbox 的远端 archive 导入和同步运行状态闭环。
- 非范围：Supabase RPC/Edge 具体接口、生产 schema/迁移、其他数据域、增量冲突自动合并、真实网络上传、生产部署和 TestFlight。
- 预计修改文件：`LocalModels.swift`、`LocalExpenseRepository.swift`、`LocalExpensePortability.swift`、`LocalProfileStore` 扩展、`LocalSyncCoordinator.swift`、对应 XCTest、阶段索引。
- 基线测试结果：Windows 无 Swift/Xcode，无法运行 XCTest；远端 PR #166 的 macOS iOS Build/XCTest 已通过，作为本片基线。
- 红灯测试及失败原因：`LocalSyncCoordinatorTests` 固定 D1-D4：匹配绑定上传并标记 sent、传输失败保留本地事实并增加 failed attempt、未绑定/错绑禁止启动、远端 archive 只能合并到当前 workspace 且不生成反向 Outbox。Windows 只能完成静态检查，未能本地观察 Swift 红灯。
- 最小实现：同步 transport 保持协议注入；`LocalExpenseRepository` 暴露按 workspace 过滤、带 payload 的 pending/failed Outbox 和 sent/failed 状态更新；`LocalExpensePortability` 支持同步导入时不再生成反向 Outbox，并要求目标 workspace ID 匹配；`LocalProfileStore` 以 attempt ID 和当前绑定校验守护 syncing/synced/failed/conflict 状态；`LocalSyncCoordinator` 串联绑定门禁、checkpoint、传输、导入和失败出口。
- 绿灯结果：待 macOS CI；本地已通过 `git diff --check`，未执行 Swift 编译。
- PWA/iOS 差异：本片只实现 iOS `expense/accounts` 同步编排；PWA 继续维护模式，不接入本地数据库或该同步协调器。
- GitHub CI 结果：尚未提交/推送，暂无本片 CI 结果。
- 未解决风险：`LocalSyncTransport` 尚无真实 Supabase adapter 和服务端幂等契约；远端 archive 的 profile/账户关系需要服务端 fixture 明确；`baseVersion` 和实体级冲突列表仍属于后续 LOCAL-003E；同步失败重试退避尚未接入 UI。
- 对应提交：待用户授权后填写。
- 下一步：先在 macOS CI 验证本片 XCTest；通过后补真实 transport 的脱敏契约 fixture，再进入首次双向同步接线，不扩大到其他数据域。
