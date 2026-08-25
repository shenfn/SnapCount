# LOCAL-003B 统一记录详情、编辑、删除执行记录

> 状态：实现完成，TestFlight 已上传，待真机验证
>
> 分支：`feature/LOCAL-003B统一记录详情编辑删除实现`
>
> 基线：`origin/main@6e291cd`

## 本轮完成

- 核对 LOCAL-003A 已合并，macOS Build 和 250 个 XCTest 通过。
- 核对本地 Repository 已具备 expense/account 的 update、delete、流水和 tombstone/outbox 基础。
- 新增 LOCAL-003B 规格，锁定本地详情、编辑、删除、余额投影和云端兼容回归边界。
- 新增本地消费详情映射：使用 `local-expense/<UUID>` 稳定引用，不构造云端图片或 AI 字段。
- `AppState` 的详情、编辑、删除按引用事实来源分流；本地引用不查会话、不调用远端 Repository。
- 本地编辑通过 `LocalExpenseUseCase.update`，删除通过 `LocalExpenseUseCase.delete`，成功后刷新本地月份、详情缓存和账户余额投影。
- 新增 Swift 特征测试：本地详情映射、本地详情加载无会话/远端依赖。

## 基线和未验证项

- Windows 无法运行 Swift XCTest，Swift 编译与 XCTest 结果仍需 GitHub macOS Build 证明。
- 尚未在真实 iOS Simulator 上验证编辑/删除后的页面刷新和错误提示。
- 尚未验证首次同步、冲突合并和 outbox 上传；这些明确不属于本轮范围。

## 本地验证

- `npm run test:ios-local-record-detail-boundary`：通过（3/3）。
- `npm run governance:check`：通过。
- `git diff --check`：通过。
- 主测试集中的 `LocalExpenseRepositoryTests` 已覆盖更新、删除、余额流水、tombstone 和版本冲突；本轮未在 Windows 重跑 Swift 测试。
- PR #165 的 macOS iOS Build：通过（Build for simulator + XCTest）。
- TestFlight workflow：通过，run `32794323603`，上传提交 `f1e9af6`；Archive、Export IPA、Upload to TestFlight 和 IPA artifact 均成功。

## 冻结范围

- 不实现登录绑定、首次同步、Outbox 上传、冲突合并或其他数据域。
- 不修改 PWA、Edge、Supabase schema、生产配置、TestFlight 或根工作区 WIP。

## 流程收敛决定

- 本片复用现有本地 Repository、账户流水事务测试和统一页面规范，不新增通用本地域框架。
- 不为后续收入、运动、睡眠、饮食、阅读域预先复制本片的完整详情/编辑/删除流程。
- 本片通过 macOS CI 和一次真机验证后先暂停，依据实际体验决定下一个域；只有出现第二个域的真实重复代码时才提取公共抽象。

## 下一步

1. 等待 App Store Connect 完成处理并在 TestFlight 安装构建。
2. 按本轮验证清单检查本地消费详情、编辑、删除、余额和离线行为。
3. 真机验证通过后再由用户决定是否合并 PR；不扩展到同步和其他数据域。
