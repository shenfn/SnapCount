# LOCAL-DEDUP-001 TDD 执行记录

- 日期：2026-11-02
- worktree：`D:/Business/count/.worktrees/ios-v2-skeleton`
- 分支：`feature/ios-local-full`
- 前置：AI-FB-001 已合并（`e0b2a93`，TestFlight build 155）

## 目标行为

重新截图同一笔账单时，iOS 要像 PWA 一样识别出「疑似重复」，不直接自动归档，
并在通知与待确认页给用户「先去看一眼」的轻确认提示。

## 当前行为（改动前）

- iOS 全仓无 `perceptual` / `pHash`，只有 `LocalImageStore.sha256` 精确哈希。
- 精确哈希只用于幂等：同一份字节重传 → 同 UUID → 返回上次结果。
  重新截图后字节全变，被当作全新交易自动归档。
- iOS 走后端 `recognize_only`，该分支在 `index.ts:6429` 就 return，
  而感知去重在 `index.ts:6896`，永远不执行。
  且 `index.ts:6481` 的 `buildExpenseAIFeedback(..., false)` 把 `possibleDuplicate` 写死为 false。
- 结论：服务端也不会替 iOS 做判重。

## 权威来源

- `supabase/functions/ingest-receipt/index.ts:445`（`computePerceptualHashFromDecoded`，aHash）
- `index.ts:3085-3114`（三张候选表查询）
- `index.ts:6896`（`findLikelyFinancialDuplicate` 调用）
- `index.ts:2710-2725`（支出疑似重复反馈文案）
- `index.ts:7229-7242`（收入疑似重复反馈覆盖）
- `index.ts:7321`（判重命中的通知固定两行）
- `index.ts:7546-7582`（第二道：3 分钟业务层判重）
- `index.ts:7815-7817`（业务层判重的通知后缀）
- `supabase/functions/ingest-receipt/duplicate-review.ts:40`（汉明距离）
- `duplicate-review.ts:57`（金额容差 0.01 元）
- `duplicate-review.ts:89`（身份判定）
- `duplicate-review.ts:144`（时间窗 10 分钟）
- PWA `src/components/pages/PagePending.vue:489` / `:534` / `:610`（待确认口径与按钮）

## PWA 有两道判重，语义不同

| 道 | 条件 | 行为 | iOS |
|---|---|---|---|
| 感知哈希 | 图片汉明距离 ≤5 + 同金额 + 同身份 + 10 分钟 | **阻断归档**，进待确认，通知「这张图可能和已有记录重复」 | 本轮补齐 |
| 业务层 | 3 分钟内 + 同金额 + 同支付方式 + 同商家 | **照常入库**，仅通知首行加 `· 疑似 3 分钟内重复` | 本轮补齐 |

两者不叠加：感知命中时后端直接 return，走不到业务层。

## 本轮范围

- 新建 `LocalPerceptualHash.swift`：aHash 计算 + 汉明距离
- 新建 `LocalFinancialDuplicateReview.swift`：两道判定规则（纯函数）+ 候选查询仓储
- 新建 `LocalFinancialDuplicateRuleTests.swift`：19 条用例
- 迁移 `local-v31-financial-perceptual-hash`：三张表加 `perceptual_hash`，pending 表加 `review_reason`
- `LocalExpenseDraft` / `LocalIncomeDraft` / `LocalPendingFinancialRecord` 加字段
- `insertExpense` / `insertIncome` / `stage` / `archiveDirectly` / `resolve` 写入；`record(row:)` 读回
- `LocalImageRecognition` 注入判重仓储，一次查询跑两道判定
- `PendingExpenseResolutionView` 疑似重复时换页头文案与主按钮

## 场景与测试层映射

| 场景 | 层 | 用例 |
|---|---|---|
| 同一张图重新截图 | XCTest（纯函数） | `testIdenticalFactsMatchAsDuplicate` |
| 距离阈值边界 5 / 6 | XCTest | `testDistanceAtThresholdMatchesAndBeyondDoesNot` |
| 金额容差 1 分 | XCTest | `testAmountDifferenceWithinOneCentMatches` |
| 商家缺失时退回平台+支付方式 | XCTest | `testFallsBackToPlatformAndPaymentWhenMerchantMissing` |
| 商家不同即不判重 | XCTest | `testDifferentMerchantDoesNotMatchEvenWhenPlatformMatches` |
| 10 分钟窗口 | XCTest | `testTimeWindowIsTenMinutes` |
| 无精确时间时按同日 | XCTest | `testFallsBackToSameDateWhenTimeMissing` |
| 收入占位名互配 | XCTest | `testGenericIncomeNamesMatchEachOther` |
| 类型必须相同 | XCTest | `testRecordTypeMustMatch` |
| 取距离最近的候选 | XCTest | `testClosestCandidateWins` |
| 指纹缺失不放行判重 | XCTest | `testMissingPerceptualHashNeverMatches` |
| aHash 稳定性与区分度 | XCTest | `testPerceptualHashIsStableForSameImage` / `testPerceptualHashDiffersForDifferentImages` |
| 指纹不可解码 | XCTest | `testPerceptualHashReturnsNilForUndecodableData` |
| 汉明距离输入校验 | XCTest | `testHammingDistanceRejectsMismatchedInput` |
| 业务层 3 分钟内命中 | XCTest | `testBusinessDuplicateWithinThreeMinutes` |
| 业务层超 3 分钟不命中 | XCTest | `testBusinessDuplicateBeyondThreeMinutes` |
| 业务层要求同支付方式 | XCTest | `testBusinessDuplicateRequiresSamePaymentMethod` |
| 无支付方式不判业务重复 | XCTest | `testBusinessDuplicateSkippedWithoutPaymentMethod` |
| 业务层只判支出 | XCTest | `testBusinessDuplicateOnlyAppliesToExpense` |
| 无账单时刻退回录入时间 | XCTest | `testBusinessDuplicateFallsBackToCreationTime` |

## 与 PWA 的差异

- **候选范围**：PWA 查服务端三张表（跨设备生效）；iOS 查本地三张表（只对本机历史生效）。
  同一账号在另一台设备截过的图，iOS 本地查不到。这是本地优先架构的固有边界，不是缺陷。
- **时间窗口文案**：后端 `detail_reason` 写「3 分钟内」，实现是 10 分钟（`duplicate-review.ts:144`）。
  iOS 按实现写 10 分钟，不复制这个不一致。
- **缩略图采样**：后端对原图做 8×8 网格点采样；iOS 先缩到 128px 再采样，
  避免整张截图解成 RGBA 的几十 MB 峰值。aHash 对缩放不敏感，判重语义不变。
  代价是 iOS 与后端的指纹值不可直接比对（两者本来也不共享数据）。
- **review_reason 落列**：PWA 存 `staging_records.review_reason` 与 `duplicate_review`；
  iOS 只落 `review_reason`，不落 `duplicate_review`（当前没有消费方，不留死字段）。
- **第二道不落库**：PWA 的 `possible_duplicate` 只出现在响应里（`index.ts:7830`），不入表；
  iOS 同样只在通知里体现，不写 `review_reason`。
- **通知后缀**：后端把 `_ePrimary` 的 `💸` / `⚠️` 前缀替换成 `⚠️` 并追加「疑似 3 分钟内重复」；
  iOS `appendingBusinessDuplicateSuffix` 逐字复刻这段正则。

## 验证状态

- `ios-build.yml` run [41408037862](https://github.com/shenfn/SnapCount/actions/runs/41408037862)：**success**
- 全量 **609 tests / 0 failures / 1 skipped**（上一轮基线 588）
- 新增 `LocalFinancialDuplicateRuleTests` **21 条全部 passed**，单条 0.001–0.018 秒
- `release-validation.yml` run 41404992039：success（`b571128`）
- `ios-testflight.yml` run [41430606161](https://github.com/shenfn/SnapCount/actions/runs/41430606161)：**success**
  - 提交 `6e7bd2e`，8m47s
  - **TestFlight build 156**（上一轮 AI-FB-001 为 155）
  - `UPLOAD SUCCEEDED with no errors`，Delivery UUID `99a4d103-2366-4ad2-a1b8-19516fbffd59`

过程中三次编译失败，均为类型/参数顺序问题，已逐个修正：

| 提交 | 问题 |
|---|---|
| `b571128` | 首版 |
| `64a4ccb` | `insertIncome` 内部构造的是 `LocalIncome`，`perceptualHash` 要从 `draft` 取；业务判重后缀误加在首行（应加金额行） |
| `e8cf347` | `duplicateFacts` 返回非 Optional，误用 `.flatMap` |
| `0022170` | 测试里 `payment` 参数必须写在 `occurredAt` 之前 |

## 未解决风险

- `LocalFinancialDuplicateReviewRepository` 每次识别多一次只读查询（三表，按 profile + 日期范围）。
- 时间窗判定依赖 `transaction_time` 有值；只有日期没有时刻时退化为同日比较，
  与后端一致，但同一天两笔同金额同商家的真实交易会被误判为重复。这是 PWA 既有口径。
- 两端判重结果不完全等价：iOS 只查本机历史，跨设备截过的同一笔查不到。
- 真机未验证：aHash 在真实微信/支付宝截图上的距离分布、通知折叠表现。

## 对应提交

- `b571128` feat(ios): 补感知与业务层判重
- `64a4ccb` fix(ios): 修正收入指纹取错类型与业务判重后缀位置
- `e8cf347` fix(ios): duplicateFacts 非 Optional
- `0022170` fix(test): 修正判重用例的参数顺序

---

# 2026-11-02 夜间修复：判重从头到尾没生效

真机反馈「重新截图同一账单还是记了两条」，逐层排查后确认是三处独立缺陷叠加，
其中前两处让判重在任何输入下都不可能命中。

## 缺陷一：仓库从未注入

`AppState` 构造 `LocalImageRecognitionUseCase` 时只传了 `pendingRepository`，
`duplicateReviewRepository` 落到默认值 `nil`。`duplicateCandidates` 因此在
`guard let repository else { return [] }` 处直接返回空数组，两道判重都拿空候选。

只有 `LocalImageRecognitionUseCase.makeDefault` 和单测里手动传了仓库，
App 主流程（相册/拍照/重试三条入口）全都没接上。

609 个测试全绿掩盖了这一点：测试覆盖的是规则函数和仓库本身，没有一条验证装配。

## 缺陷二：时间格式对不上，候选时间恒为 nil

`combinedOccurrence` 用 `DateFormatter("yyyy-MM-dd HH:mm")` 解析库里的
`transaction_date` + `transaction_time`，而后端 `record_time` 是 `18:49:57`。
带秒的输入解析失败返回 nil，`findBusinessDuplicate` 里
`guard let referenceTime = candidate.facts.occurredAt else { return false }`
随即否决——即使注入正确，3 分钟判重也永远不命中。

同时这里还有时区错位：账单存的是墙上时间，`occurredAt` 是带 `+08:00` 的绝对时刻，
拿 `TimeZone.current` 解析会和绝对时刻整体差一个时区偏移（CI 跑在 UTC，差 8 小时）。

修法是新增 `LocalFinancialDuplicateRule.wallClock(date:time:)`，
手写解析 `HH:mm` / `HH:mm:ss` 两种格式，统一映射到 UTC 伪时间轴只比墙上时间。
`duplicateFacts` 也改用 `recordDate + recordTime` 构造，不再读 `occurredAt`。

## 缺陷三：候选查询把历史记录挡在外面

三处候选 SQL 都带 `AND perceptual_hash IS NOT NULL`。`local-v31` 迁移只加列、
没有回填，升级前录入的账 `perceptual_hash` 全是 NULL，因此全部被排除。
这个条件本意只约束感知判重，实际把业务层判重一起掐死了。

已去掉该条件；感知判重侧仍由 `guard let currentHash` 和
`hammingDistance` 的 nil 语义自然跳过，不会拿缺失指纹蒙一个距离。

## 缺陷四：aHash 对重新截图没有鉴别力

按 `LocalPerceptualHash` 同一套算法（128px 缩略图 → 8×8 灰度均值二值化）
对真实截图做对照实验：

| 扰动 | 汉明距离 |
|---|---|
| 重压 JPEG q60 | 0 |
| 状态栏时间变化 | 0 |
| 亮度 ±6% | 0–2 |
| 顶部/底部横幅替换 | 0 |
| 整段详情区抹白 | 0 |
| 金额 15.00 → 88.00 | 0 |
| 商家名改掉 | 0 |
| 整体平移 40px | 10–20 |
| 缩放 2% | 10 |
| 两张列表页截图（4 条 vs 6 条） | 11 |

8×8 网格只保留整图布局，账单内容改动影响不到格子均值，而任何滚动/缩放都跨格。
阈值 5 因此两头不靠：调高会误判（不同账单距离本来就是 0），保持 5 则永远漏判。

PWA 能用这套是因为它拦的是「相册选同一张图重复上传」，那种情况距离为 0；
iOS 是现场重新截图，场景本身不等价。

## 口径变更：业务层判重改为阻断

原先 `findBusinessDuplicate` 命中只给通知加「· 疑似 3 分钟内重复」后缀，照常归档。
既然重新截图这条路只能靠字段判重兜底，它必须和感知判重一样具备阻断力：

- 两道任一命中 → `autoArchive = false`，落待确认并写 `review_reason = possible_duplicate`
- companion 置空，通知改用固定两行「这张图可能和已有记录重复 / 图片已保留并等待确认」
- 删掉因此变成孤儿的 `appendingBusinessDuplicateSuffix`

时间窗维持 PWA 的 3 分钟（`businessWindow`），感知判重的 10 分钟窗未改动。

## 顺带修复

`expenseRepository` 同样没注入，导致通知文案里的「今天已花 / 本月收入」恒为 0。
已在 `AppState` 两处构造点一并补上。

## 验证状态

- `ios-build.yml` run [41472681824](https://github.com/shenfn/SnapCount/actions/runs/41472681824)：**success**
- 新增用例全部 passed：
  - `LocalImageRecognitionTests.testLF03731DuplicateScreenshotStopsAtPending`（整条链路：首张归档、第二张待确认）
  - `LocalFinancialDuplicateRuleTests.testBusinessDuplicateMatchesCandidateWithoutPerceptualHash`
  - `LocalFinancialDuplicateRuleTests.testPerceptualRuleStillSkipsCandidateWithoutHash`
  - `LocalFinancialDuplicateRuleTests.testWallClockAcceptsTimeWithAndWithoutSeconds`
  - `LocalFinancialDuplicateRuleTests.testBusinessDuplicateMatchesWhenTimeCarriesSeconds`
- 中间一次失败（run 41469721593）就是集成用例抓到的时间格式问题，非环境抖动

## 未解决风险

- 3 分钟窗之外重新截图仍然会记两条。用户选择了 PWA 口径，长窗口未启用。
- 收入侧只走感知判重，而感知判重已被证明对重新截图无效，等于收入没有重复保护。
- 库里已有的重复记录不会被这次修复清理，需要用户手动删除。
- 真机未验证：升级后连续截同一账单是否稳定停在待确认。
