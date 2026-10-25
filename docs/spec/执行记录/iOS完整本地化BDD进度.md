# iOS完整本地化独立复审进度（2026-10-25）

## 审查边界与当前证据
- worktree：`D:\Business\count\.worktrees\ios-v2-skeleton`；分支`feature/ios-local-full`。起始HEAD `06cdab176eb3f9cbe0b2d069be0ec0afca8b8626`。
- 审查基线：`875edf177cc4ad1a7ebd6a53096434f215e04cca..8bab2865c08111214c268a4fc62e4f1569a53895`；检查差异与当前调用方，58个变更文件。8bab286之后至起始HEAD的两提交仅文档；没有将更早功能算作本轮新增。
- 既有WIP：LOCAL-FIRST-BDD-COVERAGE.md（2行）、规格文档索引.md（6行）及未跟踪handoff/Spec保留；本轮只白名单暂存自己的测试/修复。未reset/clean/改根工作区。
- C1：本次重新读取[40164520905](https://github.com/shenfn/SnapCount/actions/runs/40164520905)固定SHA及原始日志；8bab286 Simulator Build成功，459 XCTest/1 skipped/0 failures/TEST SUCCEEDED。Keychain测试skip -34018；不代表185条全部通过。
- R1：[40168094621](https://github.com/shenfn/SnapCount/actions/runs/40168094621)，固定171aa73；Build通过，461测试/1跳过/6断言失败，准确复现LF-022.01远端会话调用及LF-034.17接受inf/1e309。
- R2：[40168604132](https://github.com/shenfn/SnapCount/actions/runs/40168604132)，固定56a6560；Build通过，462测试/1跳过/10断言失败；除R1六个断言外，LF-040.04两次重放均观察到有效entry及余额7320而非10000。
- G1：[40169216719](https://github.com/shenfn/SnapCount/actions/runs/40169216719)，固定51d18bb60d846485e77970ce6c0329308ffb5ba6；本次已读取成功状态及原始日志：462测试/1跳过/0失败/TEST SUCCEEDED，LF-022.01、LF-034.17、LF-040.04三新增用例分别通过。
- R3：[40169359376](https://github.com/shenfn/SnapCount/actions/runs/40169359376)，固定5ec71f73f585a61b7d37c259a0afb3522e756729；Build成功，463测试/1跳过/5断言失败，准确复现消费及收入带图仍返回成功/财务已写入。
- 使用prd-compliance-checker逐场景审查方法；以下引用Swift符号默认位于ios/SnapCount，测试类位于ios/SnapCountTests。固定CI只覆盖对应提交的实际用例；源码/测试名存在不作为通过结论。
- **撤回“核心无必要改动”的旧结论。** 185项均已原位登记实际发现和证据边界，不代表185项全部Then核销。凡缺参数组合/实际入口/失败出口/网络或设备证据均保留待验证/部分；不估完成百分比。
- 尚未完成深审/执行的范围：LF-035.02 Hosted服务端留存；LF-035.07全App/后台网络目的地与正文；LF-042.04所有公开UseCase越权参数及服务端RLS；LF-024.01/02受支持旧库逐版本/注入失败；LF-041故障组合及设备测试。全域迁移与同步扩展不以旧协议测试代验。
- 当前登记（不是验收完成比例）：已实现且已有验证 26；已实现待验证 94；部分实现 41；规则或外部阻塞 11；未实现 11；已冻结 2。仅26项按当前审查证据记已实现且已有验证，其余159项不作完整验收通过。

## 真实结论与最小后续
四域本地手工主路径、收入CRUD账务、截图还款原子事务及若干完整备份恢复关系有源码和真实库/文件测试支持；完整本地化仍未验收。现阶段只修四个已复现安全/路由根因；财务图归档、离线普通偏好、pending/补绑及历史迁移并未因此实现。
下一最小行动：先对LF-034.17的有限超Int睡眠值/非法日期、LF-030.06 CSV公式前缀、LF-006.03重复丢弃、LF-021.04多态来源/目标悬空关系补具名回归并核定兼容边界；只修确定核心失败，之后再明确缺失能力的实现范围。已有真机/网络/旧库故障待验保持显式，不用更多同域绿灯冲销。

## 实际必要改动与处置
| 优先 | 问题和因果 | 本轮处置/剩余 |
|---|---|---|
| P0 | 图片手工页可切财务→expense/income创建忽略imageData→成功回调丢弃唯一intake原图 | R3已取得真实文件/GRDB回归红灯；8431eca明确失败保图，G2已绿；未增加财务图片schema |
| P0 | 同版本活跃云快照重建已删消费entry，墓碑仍在但余额再次扣减 | 真实回归已红；51d18bb仅挡墓碑的同版本旧活跃副本，G1已绿；较新版本冲突沿原规则，未扩大协议 |
| P1 | 登录时通用事实导出绕过本机数据读远端 | afdbd92去掉身份分流，真实库入口回归R1已红，G1已绿；专用expense/income导出范围仍待补齐/标识 |
| P1 | 字符串数值未校验finite，可通过正时长门禁，sleep转换亦有风险 | afdbd92共享解析加finite校验，R1已红，G1已绿；有限但超Int范围的sleep值、非法日历日期仍是下一防御切片 |
| P1 | CSV仅引号转义，无公式前缀防护；重复discard通用staging抛错；部分失败分支误报原图已保留；generateAIInsight旧响应只核range未核generation | 已定位，尚未补故障/哨兵回归与最小修复，不能宣称没有其他必改项 |
| 能力缺口 | 普通偏好仍远端；pending消费/转收入/补绑/批量仍远端；财务原图持久化缺失；本地陪伴表达无入口 | 记录部分/未实现，暂停新增能力，本轮不重构或自动扩开发 |
| 能力缺口 | 历史迁移只有checkpoint，无完整预览/数据源/全域账务图片映射/差异对账/中止恢复 | 不能称老用户完整本地化完成；单独明确范围后再做 |
| 待验/冻结 | 系统权限、Keychain签名态、重启/后台/强杀/低存储、无障碍/手势/性能；全域/多设备同步 | 设备/外部另验，同步扩展冻结，不部署/迁移/TestFlight |

- G2：[40169983476](https://github.com/shenfn/SnapCount/actions/runs/40169983476)，固定8431ecaa3ba1b0bceee537ee26340bd007a64ade；已读取成功状态与原始日志：Simulator Build成功，463 XCTest/1 skipped/0 failures/TEST SUCCEEDED；保图回归单独passed。Keychain签名态仍未验证。

本轮已获白名单提交、推送及iOS Build授权；未操作真实云业务数据，未调用真实供应商Key，未生产部署、TestFlight或合并主分支。Windows检查不冒充Swift编译。


## 185项原位清单
| 场景 | 当前源码、测试断言及缺口 | 状态 |
|---|---|---|
| LF-034.01 | LocalProfileStore.activeProfile事务查最早工作区/无则创建sync=false；testLocalProfilePersistsAcrossDatabaseReopen验稳定ID；RootView直接MainShellView。全新安装引导/离线网络拦截未验。 | 已实现待验证 |
| LF-034.02 | AppState.mayReadRemoteBusinessData要求匹配绑定且同步非disabled；testLF03402SignedInWithoutSyncDoesNotReadRemoteBusinessRecords/BuildsDashboardFromLocalFacts有本地读取断言；普通导出/设置/补绑仍可读远端，不能扩大为全部页面登录无混读。 | 部分实现 |
| LF-034.03 | createUnifiedManualRecord对expense/income/四域/新wallet分流本地，unsupported/旧远端对象仍走远端；testLOCALP1LF001SignedOutManualCreationWritesLocalFactsAndRefreshesCurrentMonthProjection不是M1全矩阵。待补全交易另有远端写链。 | 部分实现 |
| LF-034.04 | AppState.loadAccountDetail → loadLocalAccountDetail；LocalFirstSL02ProjectionTests.testLF03404SignedInWithoutSyncReadsLocalAccountAndLedger 校验本地账户/流水与远端调用隔离；固定CI见C1。 | 已实现且已有验证 |
| LF-034.05 | 手工本地分支不取session且本地记录不清库；testSignedInManualExpenseStaysLocalWhenCloudSessionIsUnavailable证明消费。普通设置/exportData/pending/补绑仍强制validSession，完整CRUD/鉴权失败组合未闭合。 | 部分实现 |
| LF-034.06 | invalidateSession/resetUserScopedState推进代次、停云同步清凭据/缓存，数据库/图片不删；AI的Hosted闭包未见账号generation核验，BYOK只比Key；全入口旧响应隔离未证。 | 部分实现 |
| LF-026.01 | LocalBindingRepository拒A→B改绑；LocalBindingPreviewUseCaseTests.testMismatchedBindingCannotBeReassigned断言bindingMismatch及A仍在。实际预览文案/本地继续/退出组合未UI验。 | 已实现待验证 |
| LF-034.07 | AppState.readDeviceFactMonth 保留已读缓存并登记recordMonthMessages；IOSDomainBlocksTests.testIOSV2POLISH004F03RemoteRefreshDoesNotHideReadableFormalRecords 断言450小计和refreshMessage；真实首页网络失败组合未跑。 | 已实现待验证 |
| LF-034.08 | RootView.localStorageFailureBanner 显示错误；createManualRecord 阻止存储初始化失败远端兜底；LocalExpenseAppUseCaseTests.testLF03408DatabaseOpenFailurePreservesExistingFile 验旧文件保留。装配失败时完整恢复对象亦不可用，恢复入口有效性未闭合。 | 部分实现 |
| LF-034.09 | createLocalExpense/useCase先写事务/outbox，未await sync；LocalSyncAppStateTests.testDREMOTE012FailedSyncKeepsLocalReadModelAndShowsRetryableError只mock runner失败。同步中编辑及保存/待同步UI联合验缺。 | 已实现待验证 |
| LF-001.01 | ManualRecordSheet→createLocalDomainRecord→LocalRecordUseCase.create/normalizedPayload→Repository；testLOCALP1SPORT001ARecordSurvivesDatabaseReopenAndProjectsToNativeRecord验证sport文件库重开；四域/M1及全部字段/统计组合未联合验证。 | 已实现待验证 |
| LF-034.10 | LocalFactReader.readMonth 按profile及deleted_at过滤，只读正式三表；LocalPhase1DataModelTests.testLOCALP1DM011FactReaderMergesFormalDomainsAndExcludesStagingAndTombstones；C1。 | 已实现且已有验证 |
| LF-034.11 | saveLocalDomainRecord从旧payload仅改note，Repository CAS/UseCase保图；消费元数据测试testLOCAL002C1EditsMetadataAndIncrementsVersionWithoutReplacingLedger验证不加流水。四域+收入图片/时间来源全部字段守恒仍待验。 | 已实现待验证 |
| LF-034.12 | LocalRecordRepository/LocalExpenseRepository CAS expectedVersion；testLOCAL002C4RejectsStaleExpectedVersionWithoutSideEffects断言v2/旧商户/一条流水/outbox3，通用域testLOCALP1DM008StaleVersionCannotOverwriteFormalFact亦覆盖；双编辑UI草稿保留/重读未验。 | 已实现待验证 |
| LF-034.13 | AppState.createLocalDomainRecord / saveLocalDomainRecord 刷旧新月；LocalFirstSL02ProjectionTests.testIOSV2POLISH006F17FullFormMoveRefreshesOldAndNewMonths 断言旧月空/新月610；四域重启及完整统计组合仍缺。 | 已实现待验证 |
| LF-034.14 | 删除由详情确认动作触发AppState.deleteRecord；取消路径不调用写入；未运行带图/账务/outbox全对象取消前后对账，不能用静态确认框代替零副作用执行。 | 已实现待验证 |
| LF-034.15 | deleteLocalRecord/Income/Domain→Repository墓碑/冲销→refresh；LocalRecordUseCase.delete先DB再清图；testLOCAL002D1DeleteCreatesTombstoneVoidsLedgerAndRestoresBalance / testLOCALP1SPORT001EImageIsLocalAndRemovedWithRecord。文件失败UI单独提示仍待核。 | 已实现待验证 |
| LF-034.16 | AppState.refreshLocalMonthProjection 返回Void，readDeviceFactMonth 错误仅写recordMonthMessages；createLocalExpense 随后仍设普通成功文案；钱包createLocalWalletSnapshot另有明确刷新失败文案。缺全入口已保存/刷新失败一致断言。 | 部分实现 |
| LF-034.17 | afdbd92共享numberValue字符串加isFinite；testLF03417StringNonFiniteDurationsAreRejectedAtSharedBoundary在R1对inf/1e309红、G1绿且保留合法字符串20。日期仍仅正则、sleep有限超Int范围值仍未防护；不能核销完整信任边界。 | 部分实现 |
| LF-034.18 | AppState.createLocalExpense每次显式新建UUID/operationID，仓库仅稳定ID约束，不按内容去重；testLOCALSPIKE001CRejectsDuplicateExpenseStableIDWithoutOverwrite证明同ID拒绝，不等于相同内容新建两次已执行。 | 已实现待验证 |
| LF-034.19 | AppState.isCreatingManualRecord gate阻连点；UseCase脱离View生命周期提交。没有读到连点+离页+重开真实入口联合测试，UI禁点不是跨进程幂等证据。 | 已实现待验证 |
| LF-037.01 | createLocalExpense要求有效accountID；prepareLocalWorkspace/createLocalAccount可无session。消费账户准备测试不是新安装真实UI创建现金0→消费全流程，仍须验收。 | 已实现待验证 |
| LF-037.02 | LocalExpenseRepository.createExpense 事务事实/entry/outbox；testLOCAL002A1CreatesProfileAccountAndExpenseWithoutCloudSession 与 testLOCAL002J1DerivesBalanceFromOpeningBalanceAndLedger 断言真实库账务/派生余额；具体100→80与发送闸门未联合验。 | 已实现待验证 |
| LF-037.03 | LocalExpenseRepository.updateExpense；LocalExpenseRepositoryTests.testLOCAL002C1EditsMetadataAndIncrementsVersionWithoutReplacingLedger / testLOCAL002C2AmountEditVoidsOldEntryAndCreatesReplacement 分别断言版本、流水数/void与余额；C1。 | 已实现且已有验证 |
| LF-037.04 | LocalExpenseRepository.updateExpense；testLOCAL002C3AccountMoveRestoresOldBalanceAndChargesNewAccount断言A10000、B2320及旧void/新有效账户ID，真实账务事务C1。 | 已实现且已有验证 |
| LF-037.05 | deleteExpense墓碑+流水void+outbox delete；testLOCAL002D1DeleteCreatesTombstoneVoidsLedgerAndRestoresBalance及testLOCAL002B2ReopensEditedExpenseAndDeletedTombstone分别验证恢复余额/墓碑/重开；C1。 | 已实现且已有验证 |
| LF-037.06 | testLOCAL002D2OutboxConflictRollsBackEditAndDelete注入重复operationID使outbox失败，断言事实金额/版本/流水/余额/墓碑及outbox全保留；Repository同事务，C1。 | 已实现且已有验证 |
| LF-037.07 | LocalExpenseMapper.amountMinor 与 NativeManualRecordDraft.validationMessage 金额边界未统一；D-02具体舍入/上限需确认。没有把当前行为固定为正确合同。 | 规则或外部阻塞 |
| LF-037.08 | accountBalanceMinor期初加减有效entry，createExpense没有余额不足门禁，保留负余额语义；本轮未读到精确10→-10 fixture执行，不能报具名通过。 | 已实现待验证 |
| LF-037.09 | LocalExpenseRepository.updateAccount；testLF03709ArchivedLocalAccountKeepsBalanceAndHistoryAcrossReopenAndRestore 断言重开8720、归档拒新消费、恢复不重设默认。测试未覆盖改名组合及实际UI。 | 已实现待验证 |
| LF-037.10 | updateAccount先读profile/version，再查entries/expenses/income/cycles/payments/autoDebit关系，拒类别变化后才UPDATE；testLF03710LiabilityTypeChangeRejectsExistingRelationshipsWithoutPartialMutation断言现金/credit_line类型及扣款引用/cycle ID保留。全六类关系各自fixture未覆盖，不报全通过。 | 已实现待验证 |
| LF-032.01 | AppState.createLocalIncome → LocalExpenseRepository.createIncome；testLF03201ManualIncomePersistsAndCreditsItsLocalAccountWithoutSession 断言12000/in/未知时间nil；普通导出登录仍远端（LF-022.01），该Then不完整。 财务带图输入的安全门禁单列LF-036.01。 | 部分实现 |
| LF-032.02 | AppState.saveLocalIncomeDetail/deleteLocalIncome → Repository；testLF03202LocalIncomeEditAndDeleteVoidLedgerExactlyOnce 断言12000→13000→10000、陈旧重试无新流水、两条全void；C1。 | 已实现且已有验证 |
| LF-032.03 | testLF03203IncomeAndExpenseRemainSeparateOnSameDay 断言日记录两kind、monthExpense5/monthIncome20；LocalFactReader与独立income读模型接通；跨账户详情回溯组合未联合验。 | 已实现待验证 |
| LF-033.01 | AppState.createLocalWalletSnapshot→LocalWalletSnapshotRepository.create；testLF03301OfflineWalletSnapshotIsSavedWithoutChangingDerivedBalance断言500快照/原100余额/空流水、时间和真实图bytes、备份恢复同ID/金额/图；C1。 | 已实现且已有验证 |
| LF-033.02 | performLocalWalletSnapshotAction分开保存和刷新；testLF03302OfflineCreateFromSnapshotIsAtomicAndIdempotent断言账户1/初始化entry1/余额50000→消费后48000；LinkOnly测试冲突不改账；AcceptedLocalActionIsNotRepeatedWhenListRefreshFails断言失败刷新仍成功/replay/账户1/entry1。实际并发/UI连点尚待验。 | 已实现待验证 |
| LF-033.03 | WalletRepository history含墓碑且按来源日排序，futureEvidence拒未来；testLF03303HistoryEditAndDeleteKeepSourceTimeRelationAndAccountLedger断言排序、来源时间/关联不变、CAS冲突、删除不重放、初始化entry1/余额50000；未来测试拒绝两动作且账户/流水不变；设备来源展示仍待验。 | 已实现待验证 |
| LF-037.38 | AccountsView与AppState本地创建/LocalExpenseUseCase.createAccount；testLF03738AccountFormCreatesAndReadsLiabilityOffline与配置重开测试存在，需补每种非法尾号/日/同profile扣款组合核对。 | 已实现待验证 |
| LF-037.39 | updateAccount在事务中清其他默认、归档清扣款引用、校验配置；testLF03739LocalDefaultsArchiveAndAutoDebitCleanupAreTransactional断言默认转移、负债收入默认、归档清两默认/autoDebit。恢复与全部非法引用参数尚缺同fixture。 | 已实现待验证 |
| LF-037.40 | accountBalanceMinor排除snapshot_initialization审计项；完整备份testLF02101CompleteBackupRestoresFinancialHistoryCandidatesAndImagesWithoutOutbox余额480支持恢复。迁移对账入口未实现，transfer在报告中是否全部隔离仍缺联合断言。 | 部分实现 |
| LF-038.01 | NativeSleepFacts.businessDate→LocalFactReader.sleep跨日期读取不改原字段；testIOSV2POLISH003F10WakeDateRoutesLegacyLocalFactAcrossMonthsWithoutRewriting证明旧睡眠归醒日；导出恢复/趋势联合对照未验。 | 已实现待验证 |
| LF-038.02 | NativeSleepSummary/NativeDomainScenePresentation；IOSDomainBlocksTests.testIOSV2POLISH003F10MainSleepAndIndependentThirtyDayMedians断言总620/主600、tie-a稳定、未知时长不冒最长；C1。 | 已实现且已有验证 |
| LF-038.03 | 同上testIOSV2POLISH003F10MainSleepAndIndependentThirtyDayMedians明确8/7/6独立样本、duration中位525/bedtime1410/wake nil，排除today/future且不借午休；C1。 | 已实现且已有验证 |
| LF-038.04 | NativeSleepTimelineAxis.value只接受真实start/end且duration>0；IOSDomainBlocksTests.testIOSV2POLISH004SleepRangeCrossesMidnightAndNeverInfersRangeFromDuration保护不从duration编区间；缺测UI全组合未验。 | 已实现待验证 |
| LF-038.05 | NativeSleepTimelineAxis.value真实Date差并保留start/endDateKey；testLF03805SleepTimelinePreservesNoonAndMultiDayDateDuration断言120/1950分钟及日期。布局/录入上限D-08和真机仍待定，不能整条全通过。 | 已实现待验证 |
| LF-038.06 | NativeDomainScenePresentation饮食自然周；testIOSV2POLISH004FoodAverageIncludesExplicitZeroButNotMissingOrUnrecordedDays断言validDay2/avg400/periodTotal nil；C1。 | 已实现且已有验证 |
| LF-038.07 | 上述FoodAverage测试断言选中无热量日highestMeal nil、有测量日取high；估算标识及2000参考医学边界的实际文案未逐UI验。 | 已实现待验证 |
| LF-038.08 | LocalRecordCodec.normalizedPayload将duration别名转duration_minutes、要求sport_type/正数；历史缺失UI需验，且字符串非有限值缺陷见LF-034.17，不能称完整输入校验。 | 已实现待验证 |
| LF-038.09 | testIOSV2POLISH004SportAndReadingPeriodUseFormalRecordsInNaturalWeek构造周日900/周一30/周二45，断言count2/total75；LocalFactReader正式过滤在DM011另验。候选/墓碑同fixture完整周统计尚待补。 | 已实现待验证 |
| LF-038.10 | reading normalizedPayload保留稳定记录ID并转reading_minutes；完整表单按existingRawId更新。两次同书可达/不虚构进度需UI核对，不能用sport测试代替。 | 已实现待验证 |
| LF-038.11 | NativeLocalDate上海日期/financeOccurredAt，手工收入nil时间测试成立；识别Candidate.occurredAt虽解析但recognizeAndSave没有传入通用LocalRecordCandidate，完整时间来源传递/恢复需补。 | 部分实现 |
| LF-038.12 | createLocalDomainRecord完整表单draft.universalPayload写指标并刷新旧新月；testIOSV2POLISH006F17FullFormMoveRefreshesOldAndNewMonths检查food610。saveLocalDomainRecord轻编辑仅note为不同入口；全部四域维度/图片未联合验。 | 已实现待验证 |
| LF-043.01 | loadRecordDateWindow按选中月再补自然周/近7日/30天月份；testIOSV2POLISH002P1DateWindowLoadsSelectedMonthBeforeHistory断言2000-01先于1999-12，但使用远端RecordRepositoryStub；真实本地冷热缓存及完整性文案仍待验。 | 已实现待验证 |
| LF-043.02 | readDeviceFactMonth/ExpenseMonth有generation/readVersion核验；testIOSV2POLISH006F17ForcedLocalReadCannotBeOverwrittenByOlderSnapshot真实gate拒旧快照。跨域切日取消/全部loading归属UI还待验。 | 已实现待验证 |
| LF-043.03 | AppState.openDayRecord/openDomainDrill保留选中状态并push；未跑首页→全日/周/商户全部路径及返回上下文，缺实际导航验收。 | 已实现待验证 |
| LF-043.04 | NativeExpenseTimelineSelection.minute/nearestEntry与页面拖动入口；SnapCountTests.testExpenseTimelineScrubberMapsFiniteTrackCoordinatesToMinutes / SelectsNearestExpenseWithStableTieBreak断言0/720/1440及相邻选择；真实轨道对齐未验。 | 已实现待验证 |
| LF-043.05 | testIOSV2POLISH003TimelineUsesEventTimeAndRetainsEqualTimeReferences保留同刻引用；页面点列表为替代入口；未知时间是否全可达、详情ID及对齐未真机验。 | 已实现待验证 |
| LF-043.06 | NativeDomainPageView手势需真机复核横纵/斜拖/反向及外层切域竞争；纯映射测试不能证明系统手势仲裁。 | 已实现待验证 |
| LF-043.07 | 需VoiceOver/动态字体/减少动态效果设备走查；当前只读到模型/SwiftUI入口，没有这些组合通过证据。 | 已实现待验证 |
| LF-014.01 | AppState.loadInsights→LocalFactReader→LocalInsightAggregator；testLF01401LoadsBasicInsightWithoutSessionOrRemoteAI断言expense12.3/income50/net37.7及7天外排除、无AI；月报/排行全入口和7类钱包事实范围未完整验。 | 已实现待验证 |
| LF-010.01 | 已追本地loadLocalExpenseDetail/DomainDetail直接投影；LocalExpense/Income/Record/FactReadModel的companionMessage均nil，无本地确定性候选表达调用。prepareRecordExpressionPlan仍需session且为云端增强，不能充当离线本地表达。 | 未实现 |
| LF-015.01 | generateAIInsight保留本地insightsSnapshot但请求仍validSession→服务端按range生成，并未从本地未同步事实构造授权范围。可用基础报告不等于AI已读相同本地事实。 | 部分实现 |
| LF-016.01 | 本地编辑/删除invalidateRecordExpressionPlanState并清详情cache/insightsLoadedAt；generateAIInsight返回只核range而非user generation，旧响应身份隔离及事实版本门禁缺失，不能核销。 | 部分实现 |
| LF-043.08 | 原有记录query月份/kind与DomainsView域定义检索保留，未添加全文搜索/提醒；本轮未运行这些现有入口UI回归。 | 已实现待验证 |
| LF-036.01 | AI关先receiveForManual保图/provider0成立；手工页切expense/income会忽略imageData仍成功且onResolved丢唯一intake。R3真实库/文件测试对消费和收入均红（5处断言）；8431eca先明确拒绝该不支持的带图财务保存、零账务写、保留原图，G2固定8431eca已绿（真实bytes/输入行保留、消费/收入均拒绝且余额/事实不变）。财务原图持久化仍未实现。 | 部分实现 |
| LF-023.01 | receiveForManual文件失败移除缺图intake且不请求provider；App保留draft。Intent catch却统一说图片保留，即首次落盘失败也可误报；testLOCALP1SPORT001JImageSaveFailureDoesNotCreateDatabaseOnlyHalfRecord仅库无半条，未证明系统选择保留。 | 部分实现 |
| LF-036.02 | LocalImageRecognitionUseCase.ingest失败markFailed；testLF03602ProviderFailureKeepsImageAndFailureAcrossDatabaseReopen断言重开状态和原图bytes，AppState收件箱可见；401/429/取消等全组合及UI手工出口未联合验。 | 已实现待验证 |
| LF-036.03 | ingest先beginAttempt再落图，候选写失败markFailed保留intake副本；recognizeAndSave以imageData另存避免搬走唯一输入。真实DB阶段失败/重开恢复与进程间隙需更多故障注入。 | 已实现待验证 |
| LF-003.01 | LocalRecordUseCase.update先新图再CAS，失败删新图；testLF00301ReplacingLocalImageKeepsNewReferenceAndRemovesOldFileAfterCommit断言新bytes/陈旧失败旧图仍在/仅一文件；真实文件写失败和取消编辑未全验。 本地expense/income无原图字段，不能把通用四域换图测试扩称全域支持。 | 已实现待验证 |
| LF-004.01 | LocalImageStore持久ApplicationSupport、LocalRecordReadModel本地url，testLOCALP1SPORT001EImageIsLocalAndRemovedWithRecord读真实bytes。重启/退出/断网/缩略图重建全组合需设备验。 | 已实现待验证 |
| LF-005.01 | retryPendingImageCleanups检查引用、失败持久attempt/error；testLF00501ImageCleanupFailurePersistsAndCanBeRetried验bytes/重试清空。通用record mutation多用try?不把pending清理汇报到详情，UI独立提示待补验。 | 已实现待验证 |
| LF-005.02 | LocalRecordUseCase.retryPendingImageCleanups→Repository.hasImageReference；testLF00502DeletingOneRecordKeepsAnImageStillReferencedByAnother验证剩余对象引用及原bytes仍在，正式读取不扫目录；C1。 | 已实现且已有验证 |
| LF-036.04 | recognizeAndSave拒非supportedStagingDomainKeys且保留intake；testLF03604UnsupportedDomainRemainsLocalAndDoesNotCreateBusinessFact断言tax失败/图在/事实空。财务候选改判、补账户的对应手工路径未完整接通。 | 部分实现 |
| LF-006.01 | AppState.archiveLocalStagingRecord→archiveStaging事务使用changes而非旧候选；testIOSV2POLISH006F17CandidateCompletionPersistsEditedFactsAtomically断言610/日期/时间移除/用户备注；testLOCALP1SPORT001IConfirmedCandidateBecomesFormalFactWithImageAndSource验证图片转交，组合未完整同fixture验证。 | 已实现待验证 |
| LF-006.02 | archiveStaging在DB写事务内查终态/target并原子归档；testLOCALP1DM006ConfirmingStagingTwiceReturnsSameFormalRecord使用两个不同目标ID重复确认，断言同首ID/只有一正式记录。独立队列竞争还需并发fixture。 | 已实现待验证 |
| LF-006.03 | discardStaging要求pending_review；已discarded再次调用抛invalidRecord，未满足重复丢弃返回终态。事务防确认/丢弃同成功，但竞争fixture尚缺，已归档guard保护目标图。 | 部分实现 |
| LF-007.01 | retry读取同intake/hash并beginAttempt；testLF00701RetryUsesSameIntakeAndStoresRetryCount 断言attempt2/retry1/正式记录1/输入副本清理；失败后UI可见状态未逐组合验。 | 已实现待验证 |
| LF-007.02 | retryCount<3门禁；testLF00702ThreeRetriesKeepManualAndDiscardExit只断言上限/原图bytes，名字的手工与丢弃并未实际执行，不能按测试名核销完整Then。 | 已实现待验证 |
| LF-007.03 | LocalRecordUseCase确认仅通用四域（wallet还款单独入口）；expense/income/wallet普通快照跨域候选确认未接对应正式UseCase，不能用普通手工新建冒充候选原图/来源事务。 初始图片手工改为财务还存在原图不落目标却清理输入的风险，见LF-036.01。 | 未实现 |
| LF-008.01 | ingest先查completed/intake/正式ID/pending复用；testLOCALP1SPORT001JRetryingTheSameImageDoesNotCreateDuplicateFormalFacts断言同ID/provider1/记录1；财务截图特例另查，不扩大为所有七类。 | 已实现待验证 |
| LF-008.02 | ingest允许discarded/failed继续但createStaging稳定ID可能与旧终态冲突；D-05重发新尝试/重开策略未定，无用户显式重发完整证据。 | 规则或外部阻塞 |
| LF-008.03 | beginAttempt持久认领；testLF00803ConcurrentAppAndShortcutIngestShareOneActiveImageClaim断言provider1/事实1及图清理；testLF00803ImageIntakeClaimIsExclusiveAndInterruptedClaimCanBeRecovered验证新operation拒旧claim。未跑真实AppIntent双进程。 | 已实现待验证 |
| LF-009.01 | intakeID/recordID来自sha256，未做近似内容合并；hash不同走不同身份。缺两相似图跨候选业务测试，不能宣称近似去重已实现。 | 已实现待验证 |
| LF-036.05 | Hosted默认isRecognitionRequestCurrent=true，BYOK只比较Key；切号不等价于凭据变化。D-05本地结果接受策略未明确，设备输入保留与旧账号结果隔离需单独定义验证。 | 规则或外部阻塞 |
| LF-036.06 | LocalRecordIntakeRouter food.80/其他.75且normalizedPayload完整才autoArchive；testLOCALP1DM003DomainThresholdsRequireDomainFactsAndNormalizeSleepMinutes、DM004DM005与sport边界测试。非有限字符串缺陷可影响完整性判定，修复前保留部分风险。 | 已实现待验证 |
| LF-035.01 | TodayView CameraPicker/PhotoLibraryPicker回调统一uploadImageData，mode.disabled只receiveForManual并打开手工表单；权限拒绝/取消系统流程与网络拦截未设备验。 | 已实现待验证 |
| LF-035.02 | HostedAIImageRecognitionProvider调用recognize_only后本地保存，不走普通上传；服务端实际图留存、一般同步是否永久传图未审服务端/网络证据，本轮不能证明完整Then。 | 部分实现 |
| LF-035.03 | TodayView/UploadScreenshotIntent disabled均走receiveForManual，无uploadToken门槛，Intent说明仅接收本机；真实相机相册/快捷指令重启未运行。 | 已实现待验证 |
| LF-035.04 | Intent/App BYOK provider仅读取本机Key，无项目uploadToken；闭包比当前Key；扩展读取权限失败被try?折叠为无Key，精确错误指引不足且签名权限未验。 | 已实现待验证 |
| LF-035.05 | BYOK门禁JPEG/大小、response大小后验；Intent在持久接收前ImageUploadPreprocessor与全部rawImageData读取，首次存图失败仍可能说已保留；系统回收/大图内存未验。 | 部分实现 |
| LF-035.06 | Intent业务提交完成后notifyUploadResult，再按resultCardEnabled选文案；同图claim测试不是通知拒绝及系统重复触发组合；需设备验证不改业务结果。 | 已实现待验证 |
| LF-029.01 | SettingsView单SecureField，固定模型地域费用文案；saveBYOKAPIKey经Keychain才报成功，无可配置BaseURL；真实设置重启/签名Keychain未验。 | 已实现待验证 |
| LF-030.01 | saveBYOKAPIKey仅Keychain成功才更新hasKey/模式；SettingsView SecureField，Keychain ThisDeviceOnly。签名态重启未验，唯一Keychain持久测试C1跳过。 | 已实现待验证 |
| LF-030.02 | Provider仅Authorization承Key，body无Key；testLF02902BYOKUsesFixedSupplierAndRoutesImageWithSyntheticKey验body/filename/目的地。库/全部导出/诊断/崩溃附件全哨兵扫描尚未做。 | 已实现待验证 |
| LF-029.02 | QwenBYOKImageRecognitionProvider.recognize固定endpoint授权头；testLF02902BYOKUsesFixedSupplierAndRoutesImageWithSyntheticKey断言目的地/请求图bytes/Key不在body；testLF02902BYOKImageRoutesThroughLocalDatabaseAndFileStore验证落候选/图。C1为合成网络。 | 已实现且已有验证 |
| LF-029.03 | AppState.saveBYOKAPIKey只Keychain.setString并切本机模式，无网络调用；SettingsView说明不自动验证；没有运行设置取消/网络拦截实测。 | 已实现待验证 |
| LF-031.01 | Provider分401/403 keyRejected、429 quotaUnavailable、其余serviceUnavailable，无Hosted/地域回退；ingest失败保图。真实地区/模型不可用与错误UI提示未设备验证。 | 已实现待验证 |
| LF-030.03 | App及Intent provider闭包比较当前Key；testLF03003CredentialReplacementDropsLateRecognitionAndKeepsImage断言CancellationError/图bytes/零事实。未覆盖全部真实Keychain替换失败与多进程缓存。 | 已实现待验证 |
| LF-030.04 | SettingsView独立确认→AppState.deleteBYOKAPIKey→Keychain.remove；文案说明不撤销供应商Key。testLF03004KeychainStoresAndDeletesBYOKCredential在C1明确skip（-34018）；无签名设备凭据删除证据。 | 已实现待验证 |
| LF-030.05 | Keychain无明文兜底；Intent对读取失败try?折为空Key，后续识别失败统一提示，未明确区分锁屏/权限与未配置；输入保留仅接收成功后成立。 | 部分实现 |
| LF-029.04 | LocalVisionModeStore独立持久互斥枚举，关闭不删Key；setLocalVisionMode不取消已在途请求，仅Key值闭包不足以拒绝关闭模式后旧结果；D-06保留策略与完整关闭语义待核定。 | 规则或外部阻塞 |
| LF-031.02 | Provider响应<=2MiB/JSON envelope/schema校验，UseCase二次域/字段/阈值门禁后写；大小是在URLSession已接完整body后检查，内存边界/全越界fixture仍待补。 | 已实现待验证 |
| LF-029.05 | 只有合成URLProtocol网络测试；未用真实Key，不具型号地域质量/费用/延迟实测证据。遵用户限制保持外部待验。 | 规则或外部阻塞 |
| LF-037.11 | AppState本地还款入口 → LocalExpenseRepository.confirmRepayment；testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent 真实双侧余额13000/20000→10000/17000、账单8000/已还3000；不是BDD指定100账单fixture。C1仅此参数。 | 已实现待验证 |
| LF-037.12 | LocalExpenseRepository.confirmRepayment 替代累计付款；上述testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent断言改4000后负债9000/资产16000而非重复扣全额；C1。 | 已实现且已有验证 |
| LF-037.13 | 上述真实库testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent：16000累计还款后负债0、资产4000、overpayment3000；本地实现存在，BDD100/200/120具名fixture未读到。 | 已实现待验证 |
| LF-037.14 | 已对照049 SQL及本地confirmRepayment：paid0无显式status取pending，先冲销旧付款/entry且不建新付款；旧合同已清楚，无需为是否统一撤销状态重开产品提问。缺设0/余额恢复的独立真实库fixture。 | 已实现待验证 |
| LF-037.15 | LocalExpenseRepository.confirmRepayment；testLF03715DebitAccountUsesExplicitThenCycleThenLiabilityDefaultAndRejectsInvalidExplicit 断言三层账户优先级、非法显式账户拒绝且保留原付款/各余额；C1。 | 已实现且已有验证 |
| LF-037.16 | 049 SQL与本地confirmRepayment均显式paid归零remaining；ignored不建付款但保留paid字段。现合同可按原样回归，改变规则才需D-03；当前缺这两种特殊状态的具名真实库断言，不擅改金额。 | 已实现待验证 |
| LF-037.17 | testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent用SQLite trigger分别注入transfer、第二侧、cycle更新失败，断言付款空/余额原值/周期pending；候选阶段另见LF-037.24；未完成所有App装配失败组合。 | 已实现待验证 |
| LF-037.18 | LocalExpenseRepository.revokeLiabilityPayment；testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent断言两侧恢复、重复撤销返回原周期、三条付款void及有效expense数；C1。 | 已实现且已有验证 |
| LF-037.19 | LocalExpenseRepository.revokeLiabilityPayment；testLF03719And46RevocationRecalculatesRemainingPaymentAndDueDateStatus 逐昨日/今日/明日断言paid0/remaining10000与三种状态；C1。 | 已实现且已有验证 |
| LF-037.20 | AppState本地confirm还款后读账户/周期但缺稳定operationID合同；普通confirm每次void旧付款新建UUID，净结果幂等不等于操作幂等；缺已提交刷新失败重放历史不增验证。 | 部分实现 |
| LF-037.21 | AppState.confirmStagingRepayment→UseCase→confirmScreenshotRepayment同事务写付款/transfer/archived target；testLF03721LocalScreenshotRepaymentIsAtomicIdempotentAndKeepsEvidence断言source screenshot/4000/负债6000/原图bytes；C1。 | 已实现且已有验证 |
| LF-037.22 | confirmRepayment archived screenshot分支核账单/金额/扣款账户/confirmed后返回；上述testLF03721LocalScreenshotRepaymentIsAtomicIdempotentAndKeepsEvidence断言同请求一笔付款、改4100被拒且无第二笔；C1。 | 已实现且已有验证 |
| LF-037.23 | screenshot guard拒已discarded/不同target/voided付款；D-03撤销后再次确认出口未定。只有拒绝代码不代表完整状态出口核销；两账单无副作用fixture未审。 | 规则或外部阻塞 |
| LF-037.24 | testLF03721LocalScreenshotRepaymentIsAtomicIdempotentAndKeepsEvidence注入BEFORE UPDATE status trigger失败，断言付款0/负债10000/pending仍在/原图bytes，去trigger后可成功；真实Repository同事务，C1。 | 已实现且已有验证 |
| LF-037.25 | ensureRepaymentCycles按上海transaction_date窗口/join有效entry/对账时间；testLF03725BillWindowUsesShanghaiInclusiveEdgesAndExcludesVoidedAndIncomeEntries构造2/15、2/16、3/1 void、3/15、3/16及income，断言2/16～3/15金额500；ReconciliationCutoff测试另断言已对账排除，C1。 | 已实现且已有验证 |
| LF-037.26 | ensureRepaymentCycles月底裁日+account/month唯一；testLF03726BillDay31ClampsLeapAndNonLeapFebruaryAndKeepsStableCycles断言2024-02-29/2025-02-28起止/到期、金额200及重建count1；另有snapshot due31测试，C1。 | 已实现且已有验证 |
| LF-037.27 | ensureRepaymentCycles同account/month查旧周期，仅system可刷新状态且paid0时删除空估算；有付款/高优先分支continue保留。尚缺删除估算/重启真实库联合断言审阅。 | 已实现待验证 |
| LF-037.28 | ensureRepaymentCycles canRefresh仅system且未付款状态；testLF03729ManualPaidCycleIsPreservedAndSnapshotRequiresReview断言账单10000/实付2500/剩7500/手工来源/原付款ID保留。系统重估与截图来源全部组合仍待验。 | 已实现待验证 |
| LF-037.29 | LocalWalletSnapshotRepository证据补周期与reviewRequired存在，performLocalWalletSnapshotAction提示需要确认；未见完整人工接受/取消账单复核入口及目标状态合同，不能把review_required文案当出口完成。 | 部分实现 |
| LF-037.30 | testLF03725And30ReconciliationCutoffAndHistoricalGraceTransitionPersistLocally合成now3/20、grace2、due3/17并断言historical_unconfirmed、已对账金额200及lastReconciledAt未改；没有实际重开数据库，测试名Persist不能替代重开验证。 | 已实现待验证 |
| LF-037.31 | 本地完整pending消费入口未接：AppState.confirmPendingRecord → resolvedPendingConfirmationUseCase → inboxRepository/sessionProvider；不是LocalRecordUseCase通用候选归档。现有远端编排测试不能证明离线本地Then。 | 未实现 |
| LF-037.41 | AppState.confirmPendingRecord 同样走远端PendingConfirmationUseCase；本地收入CRUD不等于pending转收入的来源映射/原图/原ID事务。未找到接入此入口的本地事务。 | 未实现 |
| LF-037.42 | PendingResolution表单取消未调用确认；但pending来源/重读仍云端，没有独立本地pending持久输入链，不能用通用staging取消代替该实体。 | 部分实现 |
| LF-037.43 | AppState pending确认/删除读取仍依赖远端expense/inboxRepository，缺本地pending带图删除/清理报告闭环；普通local-expense删除不代表未完成交易生命周期。 | 未实现 |
| LF-037.44 | pending转收入无本地事务入口，无法具备目标/来源映射/原pending/流水同事务失败恢复；现收入CRUD测试不能覆盖。 | 未实现 |
| LF-037.45 | 已对照049 SQL默认扣款账户可空；本地confirmRepayment同样可nil，testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent最后断言无debit payment/资产不变/负债减少。原合同明确无需重问必选；独立100/30 fixture待补。 | 已实现待验证 |
| LF-037.46 | revoke重新SUM confirmed付款；testLF03719And46RevocationRecalculatesRemainingPaymentAndDueDateStatus真实插30/10，撤30断言paid10/remaining90/minimum_paid，末次0/100/due_today；C1。 | 已实现且已有验证 |
| LF-037.32 | AppState.loadUnboundRecords/ bindUnboundRecord → unboundRecordRepository/AccountBindingUseCase 强制validSession；本地手工消费要求账户，不能代替本地未绑消费补绑。 | 未实现 |
| LF-037.33 | AppState.bindUnboundRecord 无本地分支；LocalExpenseRepository收入写入不是此补绑入口；缺本地原ID/发生时间/流水事务。 | 未实现 |
| LF-037.34 | 本地expense update支持移账户/void旧流水（testLOCAL002C3AccountMoveRestoresOldBalanceAndChargesNewAccount），但expense schema账户必填，清除绑定与income补绑UI仍远端；完整重绑/清除同合同未接通。 | 部分实现 |
| LF-037.35 | AppState.batchBindUnboundRecords 对远端逐项结果保留成功并汇报partial；本地处理未接，远端mock测试不得核销本地三条部分失败Then。 | 部分实现 |
| LF-037.36 | AccountBindingUseCase为远端编排，reset停止batch剩余项；本地补绑UseCase未接，跨profile写前与批量已提交保留联合GRDB测试缺，不能只用reset mock验本地。 | 部分实现 |
| LF-037.37 | 本地补绑未接稳定operationID；远端编排禁点与本地CAS不能证明重启重放不增历史。净额幂等/操作幂等要分别验证；明确的现行不双扣要求不应因D-03而搁置。 | 部分实现 |
| LF-019.01 | LocalVisionModeStore 用UserDefaults保存AI模式；AppState.updateSettings/loadUserSettings 的普通偏好仍validSession→settingsRepository，失败恢复previous。离线无法保存陪伴等全部偏好。 | 部分实现 |
| LF-020.01 | AppState.loadUserSettings 直接赋远端userSettings；本地vision mode独立。D-04普通偏好与隐私授权合并策略未形成完整测试，不能声称不会被远端打开。 | 规则或外部阻塞 |
| LF-035.07 | mode.disabled图片接收provider0有真实库测试；AppState.generateAIInsight/表达等另有远端入口，尚未对普通浏览/后台/全部异常捕获请求体。不能将单图片测试当全App网络零外发。 | 部分实现 |
| LF-035.08 | BYOK body固定prompt+当前图，无余额/历史/Key正文；Hosted recognize_only及AI分析/同步请求未做同一授权范围拦截审计。缺全目的地/request body证据。 | 已实现待验证 |
| LF-005.03 | setImageRetention仅cleanupExisting显式true调用云cleanup，清RemoteImageRepository和signedURLs，不直接LocalImageStore.remove；真实云清理禁做，本地引用保全需合成测试。 | 已实现待验证 |
| LF-027.01 | SettingsView删除确认只说明云端删除，按钮却称删除账户及全部数据；没有明确本地保留/删除独立选择及仅此设备风险提示。取消无调用由alert Cancel结构支持，未跑UI。 | 部分实现 |
| LF-027.02 | deleteAccount成功后invalidateSession保留本地DB/图片；失败只settingsMessage，generation防旧返回。成功后本地投影重建/超时核验与不盲重试尚无完整测试。 | 部分实现 |
| LF-044.01 | SettingsView/AppState.deleteAccount 没有设备全清流程；D-09覆盖范围及失败恢复未定。本轮不添加破坏性清除能力。 | 规则或外部阻塞 |
| LF-025.01 | SettingsView数据区显示保存在此iPhone且DataExportView有完整备份入口；未见常驻卸载可能丢设备数据说明。不是仅缺真机证据。 | 部分实现 |
| LF-042.01 | LocalImageStore.validatedURL拒../绝对路径并resolvingSymlinks；testLF04201RejectsSymlinkThatEscapesImageRoot断言读/删拒绝且外部bytes保留；归档全路径及跨profile输入组合未联合验。 | 已实现待验证 |
| LF-042.02 | LocalImageStore.init 的保护属性设置try?吞错；save未显式核验文件保护，restore则设置失败删除新文件并throw。锁屏/首次解锁及目录继承属性无设备实测。 | 部分实现 |
| LF-042.03 | DB/图在ApplicationSupport，Keychain ThisDeviceOnly，完整包显式排凭据；系统备份/卸载换机结果无设备证据，D-09策略及隐私声明需验。 | 规则或外部阻塞 |
| LF-022.01 | afdbd92去掉通用事实导出的登录限制；真实库testLF02201SignedInExportIncludesDeviceFactsWithoutCloudSession在R1因请求session/无文件红，在G1通过且包含本地稳定ID、不请求云session。expense/income专用导出仍远端、范围标签未完善，完整Then仍保留部分。 普通LocalFactReader不包含wallet快照，不能将此事实导出称全域可恢复备份；完整备份是另一路径。 | 部分实现 |
| LF-021.01 | DataExportView预览确认→AppState.importCompleteLocalBackup→LocalCompleteBackupPortability；testLF02101CompleteBackupRestoresFinancialHistoryCandidatesAndImagesWithoutOutbox真实库验证余额480/墓碑/void/候选/三图数量/无outbox，decode/restore核hash，截图证据测试另核原图bytes；全域恢复后重开两次与UI逐图验尚缺，保留待验证。 | 已实现待验证 |
| LF-021.02 | LocalCompleteBackupPortability.importBackup比较canonical rows并跳过；上述testLF02101CompleteBackupRestoresFinancialHistoryCandidatesAndImagesWithoutOutbox断言二次inserted0/skipped总数/entries5；同库重复导入验证，C1。 | 已实现且已有验证 |
| LF-021.03 | importBackup先全表稳定ID预检再落图写行；testLF02103ConflictingStableIDRejectsWholeBackupBeforeAnyInsert 断言收入/消费/文件集保持；C1。 | 已实现且已有验证 |
| LF-021.04 | decode及validateRows/restore有格式/重复/关系/金额/hash校验；testLF02104MalformedAndDuplicateBackupsAreRejectedWithoutPartialWrites 与 testLF02104InvalidExpenseAmountAndDanglingAccountFailPreflight真实库/文件零写。未知版本及全表每种坏关系未完整验。 validateFinancialRows列出的关系预检未含entry.source_kind/source_id多态来源及staging.target_record_id，需具名悬空来源fixture核定历史兼容与整包拒绝边界。 | 已实现待验证 |
| LF-021.05 | exportBackup按有效引用读取文件，缺失throw missingImage；testLF02105CompleteExportFailsWhenReferencedImageIsMissing断言源记录仍在、未冒完整成功；C1。 | 已实现且已有验证 |
| LF-021.06 | LocalCompleteBackupPortability 限180MiB归档/128MiB图片/100000行并限定图片路径；DataExportView取消仅清待确认data。恶意路径拒绝测试已有；真实超限/取消零写组合未跑。 | 已实现待验证 |
| LF-021.07 | importBackup将DB写事务与createdImagePaths回滚清理结合；testLF02107DatabaseFailureRollsBackRowsAndNewImageFiles断言库0/文件空。提交前真实强杀未验，try?清理失败诊断不足。 | 已实现待验证 |
| LF-021.08 | DataExportView.fileImporter→previewCompleteLocalBackup→confirmationDialog→import；testLF02108LegacyExpenseArchivePreviewsAndImportsWithoutCreatingSyncOperations 校验旧格式/版本/余额480/二次幂等。预览没有针对目标库列冲突明细，待UI补验。 | 已实现待验证 |
| LF-021.09 | testLF02109And11RestoreKeepsWakeDateDeletionAndLedgerProjection实际恢复后读FactReader，断言sleep归10/1且11月无该ID、日/月expense.20/income35、删除expense不出现、余额480/outbox0；页面/网络不自动AI另待端到端验。 | 已实现待验证 |
| LF-021.10 | testLF02110ResumeAfterImagesWereWrittenBeforeDatabaseCommit以预落真实文件模拟中断，重复导入幂等；testLF02110ImageWriteFailureRemovesEarlierFilesAndLeavesDatabaseUnchanged校验旧blocker bytes/无新事实。非实际后台强杀/磁盘近满。 | 已实现待验证 |
| LF-021.11 | 同testLF02109And11RestoreKeepsWakeDateDeletionAndLedgerProjection明确真实恢复后按日/月聚合排transfer/墓碑，余额480；testLF02101CompleteBackupRestoresFinancialHistoryCandidatesAndImagesWithoutOutbox含void付款/entry历史。fixture与初始化标记同合同，设备重新打开页面仍待验。 | 已实现待验证 |
| LF-030.06 | 完整备份白名单排除凭据/绑定/outbox，testLF02101CompleteBackupRestoresFinancialHistoryCandidatesAndImagesWithoutOutbox仅检查cloudUser/upload_token/outbox字符串；LocalFactPortability.csvField仅引号转义，公式前缀未防护；缺全序列化假Key哨兵扫描。 | 部分实现 |
| LF-039.01 | LocalHistoryMigrationStore只有checkpoint；AppState/SettingsView未接迁移预览/取消UI，无源计数空间只读服务。 | 未实现 |
| LF-039.02 | LocalHistoryMigrationStore.commitBatch事务调用apply并推进cursor；没有实际七类事实/账务/原图数据源映射及产品入口，合成checkpoint不是全域迁移。 | 部分实现 |
| LF-039.03 | startOrResume/commitBatch持久分scope cursor与generation；LocalHistoryMigrationTests合成事务覆盖不能证明token断网/产品继续及事实流水重放。 | 部分实现 |
| LF-039.04 | 迁移Store无实体版本差异报告/保留或中止UI；D-01冲突合同未固定。 | 规则或外部阻塞 |
| LF-039.05 | 迁移Store无原图下载/重签/404分类恢复，现有图片本地存储和云图片读取不能替代迁移流程。 | 未实现 |
| LF-039.06 | 迁移Store只完成scope计数，不具域ID/金额/图片hash全量对账报告与切换门禁；备份余额480测试不是迁移验证。 | 未实现 |
| LF-039.07 | Store可paused且批次失败回滚；缺实际半迁移数据标识/用户中止/读取回退告知及原有数据联合断言。 | 部分实现 |
| LF-039.08 | commitBatch核cloudUser/generation/status，拒陈旧写；未接App切号/撤权与下载任务取消，不能核销全入口。 | 部分实现 |
| LF-040.01 | mayReadRemoteBusinessData守首页/记录/账户主路径；exportData/Settings/pending/unbound仍直接validSession读业务，不满足全部浏览不拉业务；本轮导出先修。 | 部分实现 |
| LF-040.02 | LocalSyncCoordinator beginSync匹配绑定、发送稳定outbox、失败保留；testLOCAL003D1UploadsPendingOutboxOnlyAfterMatchingBindingAndMarksSent/2真实库断言sent/pending/事实保留，transport是stub；服务端重放净效果/手动停止全端需验。 | 已实现待验证 |
| LF-040.03 | Coordinator读取持久outbox operationID，发送成功回包前不生成新ID，超时mark失败供重试；服务端响应丢失后的真实只一次/checkpoint联合证据未本轮核验。 | 已实现待验证 |
| LF-040.04 | 已确认并修复同版本活跃旧副本给墓碑重建有效消费entry：51d18bb先查deleted_at并拒同版本旧活跃响应。真实库testLF04004EqualVersionLiveSnapshotCannotChargeDeletedExpenseAgain在R2余额7320/10000失败，在G1两次重放通过；较新版本冲突/服务端端到端删除契约仍待验。 | 已实现待验证 |
| LF-040.05 | disableLocalSync使attempt过期；Coordinator transport返回后isCurrentSyncAttempt才落结果，AppState reset推进代次；testDisablingSyncOnLogoutAdvancesGenerationAndKeepsBinding支持代次，旧响应全副作用组合缺联合验。 | 已实现待验证 |
| LF-040.06 | 用户本次明确暂停新增；现transport只有expense/account，四域/收入/钱包/复杂账务全域同步不扩展。未把synced状态冒充全域完成。 | 已冻结 |
| LF-040.07 | 已读ADR-040及Coordinator：冲突丢outbox后take-remote、rejected partialFailure、cursor过期清checkpoint；testDREMOTE016ConflictTakesRemoteAndLeavesNoRetryableOperation断言云端名称/synced/conflict none/outbox空；DREMOTE015断言failed/cursor nil/pending2。服务端RPC fixture本轮未执行。 | 已实现待验证 |
| LF-040.08 | 多设备原图恢复协议未实现且冻结；本地图绝对路径不是跨设备URL。没有设备间缺图文案实测。 | 已冻结 |
| LF-024.01 | LocalDatabase.migrator注册local-v1起版本迁移，migrate后使用原文件，不清库；现测试多从空库建最新或备份版本兼容，不等于v1～v7真实关系fixture逐版升/重开两次已验。 | 已实现待验证 |
| LF-024.02 | LocalDatabase init migrate throw向上传，默认storage catch形成可见不可用态，不替空库；GRDB迁移事务设计存在，未取得中途注入失败旧版本fixture重开验证。 | 已实现待验证 |
| LF-041.01 | 真实库事务及intake/备份中断恢复测试证明若干合成阶段；图/DB分离窗口与后台强杀不是同证据。未做每阶段真实终止/重开全覆盖。 | 已实现待验证 |
| LF-041.02 | Repository写事务/CAS，AppState月readVersion防旧覆盖；真实intake双队列claim与账务回滚测试独立成立；消费/还款/导入/刷新多组合交错尚未联合压测。 | 已实现待验证 |
| LF-041.03 | readDeviceFactMonth读取错误登记message保留缓存，RootView装配错误banner。损坏库时恢复对象也可能装配失败，实际可诊断导出/恢复出口不足；图片missing详情可见性需UI验。 | 部分实现 |
| LF-041.04 | LocalFactReader虽异步读、睡眠全表后按businessDate过滤，不能据此推断性能；D-10设备/规模预算未定，无近满磁盘/冷热内存实测。 | 规则或外部阻塞 |
| LF-042.04 | LocalRecordUseCase先activeProfile/currentDomainKey拒跨profile，Repository archive/delete assertProfile；收入/钱包/还款各profile过滤存在，尚未逐公开UseCase构造越权ID证明全零副作用。 | 已实现待验证 |
| LF-042.05 | 识别持久错误safeFailureMessage大多固定脱敏，但unsupportedDomain直接回显供应商domainKey；普通settings/导出错误localizedDescription含标识或路径。缺诊断全字段哨兵与脱敏合同，不能宣称安全审计通过。 | 部分实现 |
