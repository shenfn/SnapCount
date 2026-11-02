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

- 待补：iOS 编译与 XCTest 以 GitHub macOS CI 为准（Windows 无 Swift 工具链）。

## 未解决风险

- `LocalFinancialDuplicateReviewRepository` 每次识别多一次只读查询（三表，按 profile + 日期范围）。
- 时间窗判定依赖 `transaction_time` 有值；只有日期没有时刻时退化为同日比较，
  与后端一致，但同一天两笔同金额同商家的真实交易会被误判为重复。这是 PWA 既有口径。

## 对应提交

待填写。
