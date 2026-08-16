# PWA-066 PWA 账户管理边界评估记录

> 日期：2026-08-16
>
> 基线：`06dde1b`
>
> 分支：`docs/PWA账户管理边界评估`
>
> 结果：PR #100 全门禁通过并合并，merge commit `e0ef559`

## 本轮范围

- 只读核对 PWA 账户创建、编辑、默认项、归档/恢复、列表与详情收敛、会话和失败出口。
- 核对 accounts 数据库约束、账户引用和还款扣款账户的归档影响。
- 对照 iOS 同类 transport、AppState 和已归档恢复入口，裁决共享数据库权威。
- 产出 PWA-066A 至 PWA-066F 实现切片，不修改业务代码或数据库。

## 证据摘要

- PWA `saveAccount` 先 insert/update 目标账户，再调用 `unsetOtherDefaults`；第二步失败只 warning，仍显示成功并修改本地默认标记。
- `accounts` 没有默认唯一索引、互斥 trigger 或归档默认 check；PWA/iOS 并发可制造多个默认账户。
- PWA modal 可以同时提交归档与默认，独立 `archiveAccount` 无 UI 调用方；wallet 页面过滤所有归档项，没有稳定恢复入口。
- 保存只更新 `accounts`，不更新 `selectedAccount`；详情页可能继续显示旧资料。
- PWA 和 iOS 保存/归档都缺少写命令的 user-generation 收敛；iOS 也使用多步默认 REST 写入。
- 现有还款 RPC 不拒绝归档扣款账户，归档必须显式处理未来自动扣款引用。
- 产品没有单账户 delete 入口；历史引用和 cascade 关系说明应继续使用软归档。

## 评估结论

- 建立兼容旧客户端的数据库 trigger/约束与 canonical save/archive RPC，而不是分别在 PWA/iOS 修补多步写入。
- PWA 增加 Account Management Feature，固定命令复用/冲突、user/reset stale、canonical 收敛与 accepted/refresh 分层。
- 归档清默认和未来自动扣款关系，恢复不自动还原；PWA 增加已归档列表与恢复出口。
- 有历史或引用的账户跨资产/负债迁移必须阻断；需要迁移时另建业务场景。
- wallet repair、截图还款、流水 helper 和 iOS AppState 重构继续独立分片。

## 验证

| 命令 | 结果 |
|---|---|
| `npm run test:account-read` | 17 项通过 |
| `npm run test:repayment` | 15 项通过 |
| `npm run test:account-binding` | 11 项通过 |
| `npm run governance:arch` | 通过，仅既有人工清单警告 |
| `npm run build` | 通过，仅既有 `eval` 与 bundle size 警告 |

- PR #100 远程综合 Release Validation、治理、iOS gate、Cloudflare Pages 和 Vercel 全部通过；无 iOS 改动，SwiftUI 构建按预期跳过。

## 未验证与剩余风险

- 尚未写 PostgreSQL fixture、正式 Spec、红灯或业务实现。
- 未查询生产库是否已有多默认、归档默认或跨家族历史账户；实现 migration 必须采用兼容性预处理，不能假设线上干净。
- 尚未在浏览器复现归档后无法恢复与详情旧对象；风险由静态调用链确认。
- iOS 尚未接 canonical RPC；A4 前依靠数据库兼容 trigger 保护存量直写。
- 未执行生产查询、迁移、部署、真实数据写入或 TestFlight。
