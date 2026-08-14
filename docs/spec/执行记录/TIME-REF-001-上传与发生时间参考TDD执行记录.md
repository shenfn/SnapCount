# TIME-REF-001 上传与发生时间参考 TDD 执行记录

- 目标行为：发生时间存在时优先使用发生时间；发生时间缺失时使用上传时间；两者都有时保留差值和实时/补录关系。时间事实不一致时整条拒绝当前生成字段，不再删除局部词语后展示残句。
- 当前行为：`reference_time` 固定指向上传或请求时间；Prompt 禁止上传时间成为表达参考；时间 Guard 会把错误钟点改写为时段或直接删词，生产中因此出现“刚过，……”和“判断为；”等残句。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-002`，本轮实现切片编号 `TIME-REF-001`。
- 基线提交：`origin/main@5cf0dcd66e73e7eaf569ed94bf44746219fc55db`。
- 工作树：`D:\Business\count\.worktrees\time-reference-priority`。
- 分支：`codex/time-reference-priority`。
- 本轮范围：Edge 时间上下文、Voice/Feedback 时间 Prompt、生成字段时间门禁、无发生时间时的 PWA/iOS 上传时间标签、模型分类与餐次对象证据的隔离、相关回归测试和规格执行记录。
- 非范围：国际时区、数据库迁移、历史记录回写、跨记录关系和生产部署。
- 预计修改文件：`time.ts`、`time-language.ts`、`prompts.ts`、`index.ts`、对应测试、PWA 日明细适配器、iOS 时间展示模型与列表、表达事实 Spec 和本执行记录。
- 基线测试结果：时间、Prompt 和 Voice 相关 Deno 测试 `25/25` 通过。
- 红灯测试及失败原因：目标测试实际运行 `24` 项，其中 `16` 项通过、`8` 项按预期失败；失败证明参考时间缺少本地字段、事件存在时仍错误指向上传时间、事件缺失时上传时段被删除、错误钟点被裁成残句、双时间表达误用事件时段以及 Prompt 仍禁止上传时间兜底。
- 最小实现：新增 `reference_local_date`、`reference_local_time` 和 `reference_daypart`；参考时间优先级调整为精确发生时间、有效上传时间、服务端接收时间；发生与上传关系仍使用独立的 `delta_minutes` 和 `time_relation`。时间 Guard 保留现有可审计的钟点语义解析，但只返回原文或 `null`，不再改写模型语言。显式“上传、补录、现在才记录”等表达使用上传时间校验。
- 绿灯结果：Edge Function 类型检查通过；Edge 测试 `101/101`；Planner `183/183`；PWA 上传时间标签 `2/2`；表达展示契约 `22/22`；PWA 生产构建和安全契约通过。iOS XCTest 已补，等待 GitHub macOS CI。
- PWA/iOS 差异：Edge 统一表达参考时间；列表展示由两端读取同一发生/上传优先级。无发生时间时显示带来源标记的 `上传 HH:mm`，不再显示“全天”。
- GitHub CI 结果：尚未推送，未运行 GitHub CI。
- 环境说明：本机 C 盘可用空间为 `0`，默认 `npx` 首次运行因 `ENOSPC` 失败；测试缓存和临时目录定向到 `D:\Temp\codex-time-reference-*` 后正常完成。该环境失败不计入业务红灯。
- 未解决风险：当前时间归一化仍固定使用上海时区；国际时区属于后续独立设计。未重新处理的历史记录不会自动改变。
- 对应实现提交：`ab6ed3f`。
