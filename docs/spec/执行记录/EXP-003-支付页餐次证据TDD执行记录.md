# EXP-003 支付页餐次证据 TDD 执行记录

- 目标行为：支付确认页中的模型暂定分类和页面广告不能单独证明这笔支出属于早餐、午餐或晚餐；餐次表达需要独立的餐品对象、饮食图片或结构化饮食事实。
- 当前行为：生产记录中支付对象为“星之柠网络科技工作室”，页面底部存在外卖广告；识别模型返回 `category=food`，Voice 将该分类与 `11:36` 上传时间组合成“午餐”，现有门禁又把同一模型生成的分类当作独立证据而放行。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-003`。
- 基线提交：`origin/main@5cf0dcd66e73e7eaf569ed94bf44746219fc55db`。
- 工作树：`D:\Business\count\.worktrees\time-reference-priority`。
- 分支：`codex/time-reference-priority`。
- 本轮范围：识别 Prompt 的广告边界、Voice 的结构化餐次授权字段、餐次证据门禁和脱敏 Deno 回归测试。
- 非范围：商户黑名单、联网企业识别、历史记录回写、强制改写模型文案或新增中文残句正则。
- 基线测试结果：原 `EXP-003` 测试通过，但只覆盖 `category=life + noon`，没有覆盖识别模型错误返回 `category=food` 的路径。
- 红灯测试及失败原因：新增脱敏支付页用例后，`signals_test.ts` 为 `26 passed / 1 failed`；失败证明 `category=food` 会直接授权“午餐”文案。
- 最小实现：财务分类保持可展示的暂定字段，但不再独立授权餐次表达；代码向 Voice 提供 `meal_claim_allowed`，仅在存在结构化菜品/餐品对象时为真。识别 Prompt 明确忽略支付页广告，Voice Prompt 明确禁止用弱分类或时段升级为餐次。
- 绿灯结果：定向时间、Prompt、Signals 测试 `51/51`；Edge 全量 `101/101`；Planner `183/183`；PWA 构建和安全契约通过。
- PWA/iOS 差异：餐次事实边界在 Edge 落库前统一执行，两端只展示结果，不重复推断。
- GitHub CI 结果：尚未推送，未运行 GitHub CI。
- 未解决风险：在线模型仍可能把模糊财务支出错分到 `food`；本轮确保弱分类不会继续升级成餐次事实，但不会自动修改已落库历史记录。
- 对应实现提交：`ab6ed3f`。
