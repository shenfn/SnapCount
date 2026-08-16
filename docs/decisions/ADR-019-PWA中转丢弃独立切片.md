# ADR-019：PWA 中转丢弃独立切片

> 日期：2026-08-16
>
> 状态：已决定，待 PWA-042 至 PWA-046 实现

## 决策

1. PWA-040 后先收拢中转丢弃，不同时拆中转读取、图片签名和还款候选。
2. 复用现有 Staging Repository，并新增独立 Discard Feature；`useStore` 保留确认、提示和兼容 API。
3. `discard_staging_record` 是状态与清理排队的权威；客户端只映射 accepted/failed/rejected/stale。
4. 页面和批量动作只把 accepted 当作完成，不以 Promise fulfilled 或函数返回结束替代业务成功。

## 原因

丢弃是当前尚未进入 Feature/Repository 的最小中转写动作，服务端 RPC 已存在，能用有限回归面补齐重复点击和用户切换保护。读取链同时依赖整页加载、图片签名和账户还款，若混入本片会扩大范围并掩盖失败出口。

## 禁止事项

- 不把读取拆分作为“顺手重构”带入丢弃实现。
- 不在客户端复制状态终态、清理排队或权限规则。
- 不让失败、拒绝或 stale 响应推进页面队列。
- 不修改生产迁移、Edge、iOS 或历史数据。
