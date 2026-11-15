# AI-FB-001 TDD 执行记录

- 日期：2026-11-02
- 交接文档：`docs/handoff/iOS-AI反馈弹窗与详情卡片对齐PWA-交接-2026-11-02.md`
- worktree：`D:/Business/count/.worktrees/ios-v2-skeleton`
- 分支：`feature/ios-local-full` @ `1c6784a`

## 目标行为

1. 上传识别后的提示文案按域生成，与 PWA `composedCompanionNotification` 同构：
   companion 存在时「companion 行 + 域 fallback 行」，缺失时「icon+badge / 情绪句 / 实用句」三行。
2. 本地通知横幅保留换行，不再拍平成单行。
3. App 内上传结果由 `.alert` 改为 `.sheet`，内含 `NativeAIFeedbackCard`。
4. 待补全/待确认详情页能拿回 `companion_message` 与 `ai_feedback`，卡片按既有压制规则渲染。

## 当前行为

- `UploadScreenshotIntent.swift:76-88`、`TodayView.swift:668-672` 文案写死。
- `SnapCountUploadService.swift:268-273` 把多行压成单行并截 160 字。
- `local_pending_transactions` 无 `companion_message` / `ai_feedback` 列；`nativeDetail` 写死 nil。
- 正式账目详情页无卡片 —— 与 PWA `ModalExpense.vue` / `ModalIncome.vue` 一致，属正确现状。

## 权威来源

- `supabase/functions/ingest-receipt/index.ts:2215`（`compactFeedbackText`）
- `index.ts:2227`（`clipAtNaturalBoundary`）
- `index.ts:2232`（`feedbackNotification`）
- `index.ts:2268`（`composedCompanionNotification`）
- `index.ts:7200` / `:7518` / `:7806`（三域 fallback）
- `index.ts:1948-1955`（汇总行）
- PWA `src/components/ModalPending.vue:297-305`（待确认卡片）
- PWA `src/components/ModalExpense.vue`（正式账目无卡片）

## 本轮范围

- 新建 `LocalIntakeNotificationText.swift`（纯函数）+ 单测
- `local-v30-pending-ai-feedback` 迁移（pending 表 2 列）
- `LocalPendingFinancialRecord` 加字段；`stage` / `archiveDirectly` 写入；`nativeDetail` 读回
- `LocalImageIntakeOutcome` 加 `notificationText`；`ingest` 产出
- `UploadScreenshotIntent` / `TodayView` 消费新文案
- `SnapCountUploadService.notificationBody` 保留换行
- 新建 `LocalIntakeResultSheet.swift`

## 非范围

- 不给 `local_expenses` / `local_income_records` 加 `ai_feedback` 列
- 不修 v28 `companion_message` 三处 INSERT 漏写（正式页不展示，PWA 同款）
- 不改 `feedbackToRender` 压制规则，不改 `SnapCountTests.swift:1202`
- 不改后端 `recognize_only`、不改 `NativeAIFeedbackCard`
- 不覆盖 BYOK 路径（prompt 无这两字段）
- 不做生产迁移、部署、TestFlight、提交、推送

## 接口契约

```swift
struct LocalIntakeNotificationInput {
    let domainKey: String          // expense / income / sport / sleep / food / reading / 其他
    let feedback: NativeAIFeedback?
    let confidence: Double?        // NativeAIFeedback 不含该字段，单独传入
    let companionMessage: String?
    let amountMinor: Int64?
    let merchantName: String?
    let category: String?
    let sourceName: String?
    let todaySpendMinor: Int64
    let todaySpendCount: Int
    let monthIncomeMinor: Int64
    let isPending: Bool            // true 时追加「请打开 App 补全」
}

enum LocalIntakeNotificationText {
    static func compose(_ input: LocalIntakeNotificationInput) -> String
}
```

## 预计修改文件

- `ios/SnapCount/Features/Records/LocalIntakeNotificationText.swift`（新建）
- `ios/SnapCount/Features/Today/LocalIntakeResultSheet.swift`（新建）
- `ios/SnapCountTests/LocalIntakeNotificationTextTests.swift`（新建）
- `ios/SnapCount/LocalData/LocalDatabase.swift`
- `ios/SnapCount/LocalData/LocalPendingFinancialRepository.swift`
- `ios/SnapCount/LocalData/LocalImageRecognition.swift`
- `ios/SnapCount/Intents/UploadScreenshotIntent.swift`
- `ios/SnapCount/Services/SnapCountUploadService.swift`
- `ios/SnapCount/Features/Today/TodayView.swift`

## 基线测试结果

Windows 环境无法运行 XCTest（无 swiftc / Xcode），本轮基线以 GitHub macOS CI 为准。
本地已执行的等价检查：

- `git status --short` 确认只在 `.worktrees/ios-v2-skeleton` 改动，未触碰根工作区。
- 两处 `local_pending_transactions` INSERT 的列 / 占位符 / 参数个数用脚本比对：stage 19 列 = 18 `?` + 1 字面量 = 18 参数；archiveDirectly 21 = 21 = 21。
- 全量 `LocalImageIntakeOutcome` 与 `LocalPendingFinancialRecord` 构造点枚举，确认新增字段均走默认值，无漏改。
- 设计系统符号逐个 grep 确认存在（`JieziIcon.sm/xl2`、`JieziFont.subheadline`、`JieziType.button/sectionTitle`、`JieziSpacing`、`JieziGeneratedPalette.ink/coral/brand`、`JieziThemeManager.shared.palette`）。

## 红灯测试及失败原因

新增 `LocalIntakeNotificationTextTests` 共 10 条，本地无法执行，红灯状态未验证。
**这是本轮最大的验证缺口**：测试是否真红、断言是否与实现一致，只能由 CI 判定。

## 最小实现

| 文件 | 改动 |
|---|---|
| `Features/Records/LocalIntakeNotificationText.swift` | 新建，复刻后端 `composedCompanionNotification` 三段逻辑 |
| `Features/Today/LocalIntakeResultSheet.swift` | 新建，结果浮层（文案分行 + 反馈卡 + 双按钮） |
| `SnapCountTests/LocalIntakeNotificationTextTests.swift` | 新建，10 条结构断言 |
| `LocalData/LocalDatabase.swift` | `local-v30-pending-ai-feedback`（pending 表 2 列） |
| `LocalData/LocalPendingFinancialRepository.swift` | 结构体 2 字段；stage/archiveDirectly 写列；record 读列；nativeDetail 读回 payload/feedback；新增 `recordIgnoringStatus` |
| `LocalData/LocalImageRecognition.swift` | outcome 加 `notificationText`/`feedback`；新增 `expenseRepository` 依赖；新增 `composeNotification` 两个重载与编解码；三条幂等路径补文案 |
| `Services/SnapCountUploadService.swift` | `notificationBody` 改为保留换行 + 160 字预算 |
| `Intents/UploadScreenshotIntent.swift` | `displayText`/`notificationText` 改用 outcome 产出 |
| `Features/Today/TodayView.swift` | 成功走 `.sheet` 结果浮层，失败仍 alert；「查看记录」按结果跳 records/inbox |

## 绿灯结果

`ios-build.yml` run [41390367946](https://github.com/shenfn/SnapCount/actions/runs/41390367946)（`e0b2a93`）：**success**

- `Build for simulator`：通过
- `SnapCountTests`：**Executed 588 tests, with 1 test skipped and 0 failures**，耗时 180.6 秒
- 新增 `LocalIntakeNotificationTextTests` 10 条全部 passed（单条 0.001–0.007 秒）

## PWA/iOS 差异

- **行数**：后端 `composedCompanionNotification` 在「无 companion + 有反馈」时走 `preserveFallbackAll`，支出域实际 5 行。iOS `compose` 忠实复刻 5 行；`notificationBody` 不再预裁行，只守 160 字预算，折叠/展开由系统决定。原方案的 `prefix(3)` 会丢掉「今日已花」事实行，已废弃。
- **confidence 缺失语义**：后端 `feedback.confidence < 0.5` 在 `undefined` 时为 false（放行）。Swift 初版写成 `(confidence ?? 0) >= 0.5` 会错误退回 fallback，已改为「只在拿到明确低分时退回」。
- **收入来源名**：后端排除占位值「截图识别收入」（`index.ts:7516`），iOS 同步排除。
- **金额格式**：`fmtYuan` 为 `¥` + 两位小数，**无千分位**。交接文档示例里的 `¥12,345.00` 有误，实现以代码为准。

## GitHub CI 结果

| run | 提交 | 结论 | 说明 |
|---|---|---|---|
| `release-validation.yml` 41381773715 | `c44f1e9` | **success** | 首次即过 |
| `ios-build.yml` 41381761121 | `c44f1e9` | failure | `argument 'occurredAt' must precede argument 'aiFeedback'`，已修 |
| `ios-build.yml` 41382507041 | `e0b2a93` | cancelled | 编译通过，`Run unit tests` 超 30 分钟未结束 |
| `ios-build.yml` 41386378381 | `e0b2a93` | cancelled | 同上，`cancel` 请求 5 分钟未生效 |
| `ios-build.yml` 41390367946 | `e0b2a93` | **success** | 588 tests / 0 failures |

**关于「Run unit tests 挂起」**：属于既有间歇性问题，与本次改动无因果关系。同行证据——改动前的 `1c6784a` 有两次运行：41320336610 **success 12 分钟**、41315836247 **cancelled 361 分钟**；`f83d5a5` 也有一次失败耗时 73 分钟。同一提交的成功运行里测试步骤只用 180 秒，说明不是新增测试拖慢，而是 runner 侧偶发卡死。应对方式：取消后重新 `workflow_dispatch`，重跑可恢复。

## TestFlight

- run [41392080681](https://github.com/shenfn/SnapCount/actions/runs/41392080681)：**success**
- 提交：`e0b2a93`（通过 iOS Build/测试的同一提交）
- 版本：`1.0`，构建号 **155**（`github.run_number`）
- Delivery UUID：`9f02147b-be76-4150-a0db-43242be133cd`
- IPA：28,802,387 bytes，Artifact ID `13117548650`

> 注：`ios-testflight.yml` 的 `Set TestFlight build number` 步骤把 Info.plist 写成 `run_id`，
> 但随后的 `Archive` 又用 `CURRENT_PROJECT_VERSION=run_number` 与
> `INFOPLIST_KEY_CFBundleVersion=run_number` 覆盖，实际生效的是 **155**。该步骤目前是死写入，不在本次范围，未修。

**环境备注**：本机 `api.github.com` 经 HTTP 代理（127.0.0.1:7897）会 TLS 握手失败或 502/EOF，
改用 `ALL_PROXY=socks5://127.0.0.1:7897` 后 `gh` 全部正常；`git push` 同样需要
`-c http.proxy=socks5h://127.0.0.1:7897`。


## 未解决风险

1. ~~iOS 编译与 XCTest 未验证~~ → 已由 run 41390367946 覆盖（Build 通过，588 tests 0 failures）。
2. `LocalImageRecognitionUseCase` 新增 `LocalExpenseRepository` 注入；快捷指令后台路径每次 `makeDefault` 会多构造一个 repository 并多跑两次月度查询。测试未覆盖后台冷启动耗时。
3. `TodayView` 现在有 5 个 `.sheet` 挂在同一层级，编译与单测通过，但多 sheet 并存的实际呈现需真机确认。
4. 通用域 `staged` 的文案用 `isPending: false`，与后端「已归档到」措辞一致，但记录实际仍在待确认状态，措辞偏乐观（PWA 同样如此，暂不改）。
5. BYOK 路径仍无 `ai_feedback` / `companion_message`，本次不覆盖。
6. 通知折叠态实际显示行数、详情页卡片在 companion 缺失时的真实观感，均未真机验证。

## 对应提交

- `c44f1e9` feat(ios): 上传识别提示按域生成并对齐 PWA 反馈口径
- `e0b2a93` fix(ios): 修正 nativeDetail 成员初始化参数顺序


---

# 2026-11-03 补记：归档路径丢掉了表达层

真机反馈「详情页没有 AI 点评，前几个版本还有」，排查后确认是本地化时只迁移了记账字段，
`companion_message` / `ai_feedback` 整套表达层在自动归档路径上丢失。

## 三处断点

1. `LocalPendingFinancialRepository.archiveDirectly` 构造 `LocalExpenseDraft` / `LocalIncomeDraft`
   时没带这两个值。
2. `local_expenses` / `local_income_records` **没有 `ai_feedback` 列**（只有待确认表有）。
3. `companion_message` 列在 `local-v27` 就加过，但 `INSERT INTO local_expenses` 从未写它，
   列一直是 NULL 空壳。

结果：只有停在待确认页的记录能看到 AI 点评，自动归档的一条都没有。切成本地优先后
不再读云端 `transactions`，所以「前几个版本还有」的观感成立。

## 修复

- `local-v32-financial-ai-feedback`：两张表加 `ai_feedback TEXT`
- `LocalExpenseDraft` / `LocalIncomeDraft` / `LocalExpense` / `LocalIncome` 补
  `companionMessage` + `aiFeedbackJSON`
- 三处 `INSERT` 写列、两处行映射读回
- `archiveDirectly` 把待确认记录里的两个值带进记账表
- `LocalExpenseReadModel` / `LocalIncomeReadModel` 装配 `aiFeedback`
- 集成用例 `testLF03731ArchivedExpenseKeepsCompanionAndFeedback`：归档后详情仍带反馈

## 通知文案为什么千篇一律（非缺陷）

生产 `recognize_only` 返回的 `ai_feedback` 由 `buildExpenseAIFeedback` 规则模板生成，只有
6 档 badge，`utility_line` 是写死的字符串；`prompts.ts:101` 明确要求该路径
「不要生成 companion_message」。PWA 前端 `ModalExpense` 不渲染这些卡，所以网页端看不出来。
这条要改属于动生产 Edge Function，不在客户端范围。

## 注意

- 已归档的旧记录补不回来，修复只对之后新记的生效。
- 详情页出现的是反馈卡；「💬 AI 陪伴」一句话在生产 `recognize_only` 路径恒为空。
- TestFlight：run 41562044517（run_number 157），`UPLOAD SUCCEEDED`，
  Delivery UUID `30ab9a7e-a0b8-4cd0-8159-effe47591eb6`，
  IPA 内 `CFBundleVersion` 取的是 run id（与既往一致），TestFlight 里按长数字排序。
