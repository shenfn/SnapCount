# Expression Planner 与陪伴表达统一出口开发记录 v0.1

状态：本地实现与回归完成；待 CI 门禁后发布

基线：`origin/main@0a629ee158297d71f92b55746381170df3d36c66`

工作树：`D:\Business\count\.worktrees\陪伴候选统一出口`

分支：`codex/陪伴候选统一出口`

## 目标

把当前并行的 Planner 候选、Signals/Voice 陪伴语和客户端反馈卡片收敛为一条可追溯链路：

```text
结构化事实 -> 多角度候选 -> 现有评分选择 -> Voice 表达
-> Surface 组合 -> 曝光与点评
```

本轮重点解决：

1. 首次出现已经被代码识别，但没有成为可选择候选。
2. Voice 在候选较弱时过度退化为事实复述。
3. 陪伴语与 Planner 卡片在 PWA/iOS 同屏重复。
4. 各端存在不同的 legacy/Planner 组合规则。

## 冻结边界

- 保持现有五因子评分公式，不新增评分维度。
- 不新增 `hypothesis` 候选类型、数据库表或反馈管道。
- 支出继续使用现有 `amount`，不拆分原价、实付和优惠。
- 允许 Voice 基于已确认事实进行带不确定措辞的轻量推理。
- 不允许模型新增精确商品、金额、次数、优惠金额或历史统计。
- 页面内容覆盖只在 Surface 组合层处理一次。
- 不增加模型调用次数，不在本轮执行数据库迁移。

## 开发进度

- [x] 从最新 `origin/main` 创建独立中文 worktree
- [x] 核对 Git、worktree 和发布规范
- [x] 将 `entity_first_seen` 转换为正式 Planner 候选
- [x] 补齐候选排序、曝光和门禁测试
- [x] 让 Voice 接收稳定的选中角度契约
- [x] 允许有依据的轻量推理并收紧精确事实边界
- [x] 统一 PWA 详情和待补充弹窗的内容组合规则
- [x] 统一 iOS 记录详情和中转站的内容组合规则
- [x] 让 Voice 已表达的首候选进入正式 delivery、ACK、曝光和点评
- [x] 将统计数字绑定到同一候选的数值、含义、单位和时间口径
- [x] 将通知从字符串去重升级为 claim/slot 组合
- [x] 完成 Planner、Edge、PWA 和静态 iOS 定向回归
- [x] 生成真实样本新旧对照回放
- [ ] 等待 macOS iOS Build/单测和固定提交发布

## 冻结版本与来源契约

- Context Packet：`context-packet-v2`
- Planner：`expression-shadow-auto-v0.6`
- Voice 来源：`expression-coverage-v1`
- 插入前 synthetic Planner 只负责选择 Voice 角度，不写曝光；落库后的正式 Planner 才负责快照、ACK、点评和依赖校验。
- coverage 不信任模型自报的候选身份。只有最终持久化的 `companion_message` 通过候选级事实验证时才成立，并绑定 `semantic_key`、`claim_fingerprint`、`packet_fingerprint`、`presentation_target` 和 `rendered_text_fingerprint`。
- 无文本 Provider、接口异常或 JSON 失败时，不增加第二次调用，代码直接用已核实候选生成规则兜底并记录 coverage。

## 正式交付契约

```text
插入前只读 Planner
  -> 一次 Voice
  -> 验证最终 companion_message 是否真正表达首候选
  -> 记录落库
  -> 正式 Planner 用真实记录重新计算
  -> 同一 claim 生成 delivery snapshot
  -> companion 容器进入视口后 ACK
  -> 写入真实曝光
  -> 点评绑定该 exposure_event_id
```

Voice 已表达首候选时，它仍是正式 Planner delivery，只把承载位置设为 `companion_message`。客户端不再绘制第二份正文，但会在原陪伴容器中显示点评入口；进入视口前不计曝光。coverage 无效、文案变化、记录编辑或 claim 变化时，服务端 fail-open 到普通 `feedback_card`，不会静默吞掉候选。

快照冻结：

```json
{
  "presentation_target": "companion_message",
  "rendered_payload": {
    "companion_message": "用户实际看到的文案"
  },
  "visible_field_paths": ["companion_message"],
  "rendered_text_fingerprint": "..."
}
```

ACK 前会重新验证候选依赖、claim 指纹、持久化文案及文本指纹。曝光 metadata 同步记录承载位置与文本指纹，点评仍使用原有候选级反馈管道。

## 数字与通知边界

- Voice 的统计表达不再使用“全局允许数字 + 全局周期集合”。每个统计子句必须匹配同一候选的 `value + meaning + unit + scope`；`本周第 4 次`与`近 90 天均价 9.54 元`可以分别表达，但不能拼成`近 90 天第 4 次`或`本周累计 9.54 元`。
- 不含精确统计的定性陪伴继续允许，当前记录本身的金额等事实仍可自然表达。
- 快捷通知按固定记账结果、Voice/Planner claim 和稳定汇总事实分 slot 组合。同一 `semantic_key + claim_fingerprint` 的不同说法只出现一次；相同数字但不同 claim 都保留；身份缺失或指纹错误时不允许压掉确定性 Planner 事实。
- Voice 首候选只有同时通过快捷通知准入时才进入通知并记录 `returned_to_shortcut` 曝光；否则通知使用真正被选中的快捷通知候选，不展示 Voice 文案却给另一候选计曝光。

## 验收样例

最新低金额茶饮记录应满足：

- 只显示一个主陪伴内容，不重复商户、金额和时间。
- 首次出现时可以选择首次出现角度。
- `6.28 元看起来像碰上优惠` 这类合成样本中的定性推理可以存活。
- `优惠了 20 元`、`本周第 3 次` 等无证据精确断言必须被拒绝。
- 陪伴语本身命中 Planner 首候选时，可以直接点评这句陪伴语；普通 Planner 卡路径保持不变。

## 本地验证结果

- Planner 全量测试：`163/163` 通过。
- Edge/Deno 测试：`45/45` 通过；`ingest-receipt` 与 `generate-insights` 均通过 Deno 类型检查。
- PWA Surface 组合与候选身份测试：`9/9` 通过；production build 通过。
- 安全契约、重复记录、待处理队列、财务选项、钱包快照金额、注册元数据和 migration version 检查通过。
- coverage 只有在模型文案真正包含候选对象、语义锚点和可信数字时才生效；通用套话、伪造 coverage、错误文本指纹和编辑后的旧 claim 都不能成为 companion delivery。
- 支出、收入和数据域历史改为完整分页读取；第 501 条历史仍能阻止误报“第一次记录”。落库后的数据域 Planner 会继续读取同一份画像，正式决策集保留餐次/个人基线候选。
- PWA 预览与 ACK 校验候选、claim、承载位置和文本指纹；陪伴容器不可见时不 ACK，可见后才进入点评闭环。
- iOS 使用同一 envelope 契约；Windows 不具备 Swift/Xcode，本地静态测试不能替代 macOS CI。
- 真实样本采用生产只读聚合后的本地等价脱敏回放，文件保存在 Git 忽略的 `local-only/expression-planner/`，不进入提交或 CI artifact。
- 一条真实低价茶饮记录在生产 v0.5 中重复呈现商户和金额；本地等价脱敏回放中，v0.6 选择 `expense_merchant_first_occurrence`，当前金额事实退回兜底。精确商户、金额和时间只保存在 Git 忽略的本地文件中。
- 真实模型的人格化最终措辞仍需部署后的单用户 Canary 验证；本地只验证事实、候选、coverage、去重和失败回退，不把示例文案冒充模型实测结果。

## 发布边界

用户已授权本轮与时间修复一起发布。顺序固定为：

1. GitHub CI 通过 Edge/Deno、PostgreSQL migration/RLS 和 macOS iOS Build/单测；
2. 生产数据库先执行 `20260808120000_finance_occurred_at_contract.sql`；
3. 部署 `ingest-receipt` Edge Function；
4. 合并并部署 PWA；
5. 仅从同一个 CI 已验证的固定提交手动触发 TestFlight。

迁移完成前，旧客户端仍可工作；迁移未确认成功前不得发布包含 `occurred_at` 查询的 iOS 构建。

## 时间契约（2026-08-08）

- 本轮暂不引入用户时区配置、IANA 时区迁移或夏令时策略；当前产品统一使用 `Asia/Shanghai`。
- `occurred_at` 是唯一可验证的业务发生时刻；`client_captured_at` 只表示上传/截图时刻，用于判断是否补录。
- 发生时间为空时，模型和代码都不得用上传时间冒充发生时间，也不得保留未经证据支持的“凌晨/早上/晚上”等时段措辞。
- PWA 和 iOS 分别展示“发生时间”和“上传时间”；旧 `transaction_time` 不再单独拼接成发生时间。
- 历史回填只采信 staging 或 AI 识别日志的明确发生时间证据，无法确认的历史行保持 `occurred_at = null`。

## 2026-08-08 最终回归

- Planner 全量：171/171；PWA 表达展示：16/16；PWA 时间辅助函数：13/13；业务契约、重复记录、安全和生产构建均通过。
- 新增 `time.ts`、`time-language.ts` 及前端/iOS 时间展示契约测试；UTC 输入会先规范为上海本地墙上时间。
- Windows 本地无法运行 Deno 或 Swift/Xcode；Edge 类型检查、PostgreSQL/RLS 演练和 iOS Build 以 GitHub Actions 为准。
- 真实 Canary 重点检查：06:xx 发生时间不再出现“凌晨/深夜”、详情页北京时间正确、上传时间单独展示、陪伴语与 Planner 卡不重复、点评 ACK 可完成。

## 16. 2026-08-08 本地最终回归与客户端活性收口

本轮在不增加模型调用、不新增 migration 的前提下，将“文案可见—候选曝光—点评”的最后客户端边界也冻结。

### 16.1 最终修正

- PWA 详情页和待补充弹窗将陪伴文案身份加入观察依赖；文案异步刷新时作废旧缓存、取消旧 in-flight 请求并强制重取。重试只在第一次请求使用 force，避免同一组计划在退回重试时被重复作废。
- PWA 在真正 ACK 之前再次校验当前陪伴文案与交付快照一致，不把只在早期渲染时成立的判断当成曝光。
- PWA 与 iOS 都对 `feedback_card` 交付比对 `candidate_id + claim_fingerprint + presentation_target + rendered_text_fingerprint`；只有没有显式 target 的旧响应使用兼容的旧组合规则。
- iOS 在陪伴文案变化时同时清理旧 pending 与 ACK token，旧请求返回不能拦住新计划重新显示与点评。
- 旧响应不默认跳过当前事实去重；只有服务端明确下发 `feedback_card` 才视为权威卡片。

### 16.2 最终本地验证

- Planner 全量：`170/170` 通过；
- Edge/Deno：`59/59` 通过；`ingest-receipt/index.ts` 与 `generate-insights/index.ts` 类型检查通过；
- PWA 表达展示单元：`16/16`；PWA exposure 契约：`10/10`；production build 通过；
- 安全契约、重复记录、待处理队列、财务选项、钱包快照金额、注册合同、migration version 和 `git diff --check` 通过；
- 本地开发机无 Swift/Xcode，因此 iOS Build/单测仍必须在 macOS GitHub Actions 中执行；
- 本轮仍未 commit、push、生产 Edge 部署、生产 migration 或 TestFlight。

是否允许进入下一阶段：本地闭环已完成，可进入逐路径暂存、提交和 macOS CI；生产发布仍需单独授权。
