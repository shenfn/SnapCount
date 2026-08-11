# EXP-012 上传完成通知双表面 TDD 执行记录

- 目标行为：上传完成通知同时保留持久化 Voice 主文案、独立 Planner 新角度和固定归档结果。
- 当前行为：Planner 目标为 `feedback_card` 时，Edge 通知只显示 Planner 文案和固定结果，Voice 虽已入库但在 iOS 原生上传弹窗中消失。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 的 EXP-006、EXP-008 与 EXP-012。
- 本轮范围：Edge 通知合成纯函数、iOS 原生上传响应模式、对应 Deno/XCTest 契约。
- 非范围：模型 Prompt、Planner 排序、数据库迁移、详情页布局、历史记录回填。
- 预计修改文件：陪伴表达 Spec、通知合成与测试、iOS 上传服务与 Today 上传调用、XCTest。
- 基线测试结果：Windows 当前无系统 `deno`；该环境失败不作为业务红灯。现有 iOS 测试只能由 macOS CI 最终验证。
- 红灯测试及失败原因：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/notification-text_test.ts` 运行 14 项，13 项通过；新增 food 双表面用例失败，期望 Voice + Planner + 归档结果，实际缺少 Voice。
- 最小实现：`resolvePlannerNotification` 对独立 `feedback_card` 也保留 Voice 输入；iOS 首页上传改用 JSON 响应并复用 `ShortcutUploadResult` 结构化合成。
- 绿灯结果：通知专项 14/14、完整 Edge 集合 92/92、PWA 表达契约 22/22、`deno check` 与 PWA 生产构建通过。Windows 无法执行 XCTest，待 GitHub macOS CI。
- PWA/iOS 差异：PWA 与快捷指令已消费 JSON；iOS 首页原生上传当前消费纯文本，需要收敛到同一结构化结果。
- GitHub CI 结果：待记录。
- 未解决风险：现有已生成记录不会重新触发上传弹窗；修复对部署后的新上传生效，历史详情仍直接读取已保存 Voice。
- 对应提交：待记录。
