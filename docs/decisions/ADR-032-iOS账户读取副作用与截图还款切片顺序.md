# ADR-032：iOS 账户读取副作用与截图还款切片顺序

> 状态：已接受（评估决策）
>
> 日期：2026-08-20
>
> 关联任务：A4-IOS-005、A4-IOS-006、PWA-065、PWA-067

## 决策

A4-IOS-005 先收拢账户读取中的隐式周期准备：`ensure_liability_repayment_cycles` 必须作为显式写命令表达，纯账户列表/详情读取不得隐藏该 RPC。截图还款候选与确认安排为后续 A4-IOS-006，保持 staging、账户、账期和确认事务的独立边界。

## 背景

当前 `AppState.loadAccountDetail` 在读取负债账户前调用 `ensureRepaymentCycles`，`loadInboxRepaymentCandidates` 也在生成截图候选前调用同一 RPC。该 RPC 会写入或补齐账期，但调用方使用 `try?`，因此“准备失败”“没有账期”和“账期读取失败”可能被压成同一空状态。

截图确认虽然已经通过 `confirm_staging_repayment` 进入数据库原子事务，但它还同时编排 staging 记录、候选匹配、账户/账期读取、收件箱导航和 dashboard 刷新。把两片合并会扩大回归面，并重新制造跨 Repository 反向依赖。

## 备选方案

- 方案 A：先做截图还款候选与确认。用户价值明显，但范围跨 staging、账户、账期和页面状态；读取副作用仍会被带入新 Feature。暂不选择。
- 方案 B：继续在 AppState 中保留 `try? ensure`，只补测试。成本最低，但继续违反“读取不隐藏写入”，也无法表达 prepare 失败。拒绝。
- 方案 C：先显式化周期准备，再做截图还款 Feature。边界较小，能为后续候选读取提供稳定前置结果；选择此方案。

## 边界与影响

- `AccountRepository` 继续拥有 RPC transport、DTO 和错误映射；新增或收窄协议不得让 `fetch*` 隐式调用 ensure。
- Account Read/Preparation Use Case 负责命令 identity、user/generation stale、prepare/读取结果分层和 AppState 兼容投影。
- 账户详情仍可在用户打开页面时编排“先准备、后读取”，但这两个动作必须有独立结果和重试出口。
- 截图候选保持纯函数；`confirm_staging_repayment` 的 accepted/refresh/stale、staging 归档和导航收敛另立 A4-IOS-006。
- 不修改数据库 migration/RPC、金额/状态规则、钱包快照、PWA、Edge、Planner 或页面视觉。

## 验证要求

实现阶段必须提供：prepare Task 复用与冲突/失败/stale XCTest、详情分区错误测试、Account Repository 源边界检查、完整 macOS simulator Build、相关 PWA/Edge 回归、治理和架构门禁。未完成这些证据前，A4-IOS-005 不得标记完成。
