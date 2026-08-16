# ADR-022：PWA 已处理目标持久化类型

> 日期：2026-08-16
>
> 状态：已决定，待 PWA-056A 至 PWA-056E 实现

## 决策

1. `staging_records` 新增可空 `target_kind` 与 `resolved_domain_key`，由归档 RPC 与 `target_record_id` 在同一事务写入。
2. `target_kind` 只表达物理目标类型：`expense`、`income`、`data`；`resolved_domain_key` 表达用户最终选择的业务域。
3. 历史回填只相信实际目标表中同时匹配目标 ID、中转 ID 和用户 ID 的唯一关系；无法证明时保持 unknown。
4. `user_routing_feedback` 保持审计与学习用途，不作为已处理导航的运行时权威。
5. 客户端遇到 unknown 时零目标表请求并给出明确失败；已知类型只读取一张表。

## 原因

识别域不是最终域，反馈表是一对多事件流，`target_reference` 字符串又会和独立 ID 重复。把物理类型和最终业务域写回中转解析结果，可以让刷新、换会话和历史回放获得同一事实，并把 unknown 变成显式状态而不是三次查询后的偶然结果。

当前归档 RPC 已在事务内创建目标、写中转结果和路由反馈，也会在幂等重试时核对真实目标表。将两个字段纳入该事务是现有权威的延伸，不需要客户端复制判断。

## 禁止事项

- 不从 `detected_domain_key` 推断最终类型。
- 不按 expense、income、data 顺序并行探测并以首个命中为准。
- 不把任意一条或最新一条 feedback 直接当成目标表事实。
- 不对无法证明的历史行强行回填。
- 不编辑既有已部署迁移；使用新迁移演进包装函数与字段。
