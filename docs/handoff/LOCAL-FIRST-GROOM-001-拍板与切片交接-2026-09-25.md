# 任务交接快照

> 任务编号：LOCAL-FIRST-GROOM-001（BDD 全景梳理 + 领域收敛 + Phase 1 产品拍板）
>
> 日期：2026-09-25
>
> 分支：codex/local-first-phase1-fact-reader（主工作区，本轮为只读分析，未产生任何业务代码改动；仅新增/修改 docs 与规格文档）
>
> Worktree：D:\Business\count（根工作区存在大量用户 WIP 与未追踪素材，本轮未触碰）

## 已完成

- BDD 全景梳理：`docs/spec/LOCAL-FIRST-BDD-COVERAGE.md`（LOCAL-FIRST-BDD-001）。以 iOS+PWA 完整产品能力为基线，14 个 Feature、约 70 个 Scenario（沿用既有编号 + 新增 LF-001~033），含反向遗漏检查与 8 项文档/代码差异记录（V-1~V-8）。
- 领域收敛与切片设计：`docs/spec/LOCAL-FIRST-DOMAIN-CONVERGENCE.md`（LOCAL-FIRST-DOMAIN-001）。12 域 Capability Map、18 条 Invariant（含权威位置）、共享能力收敛结论（不新增抽象层）、6 类事务边界、10 项架构债务处置、Feature 依赖图、SL-01~09 无门 Slice + SL-A~I 决策依赖 Slice。
- Phase 1 产品拍板：Q-01~Q-13 全部收敛，已写入领域收敛文档 §10.1/§10.2/§10.3。关键结论：
  - 收入/钱包进 Phase 1 本地化（钱包=只记快照事实最小形态）；还款/补绑/截图还款不本地化（云端 RPC 为原子权威）。
  - BYOK 暂缓移出 Phase 1；设置未登录存本地+登录"谁改得晚谁赢"；AI Popup 本地方案 a（确定性候选文案、最小候选集、隐藏点评 UI）。
  - 双轨（未登录=本地、登录=沿用云端）定义为 Phase 1 迁移期策略，不是最终架构；长期仍是 Local-First（本地为主写入路径，Sync 为可选增强），同步解冻后收敛。
  - DM-GAP-10 不采纳（消费必须选账户）；discard 改幂等；删账号勾选框默认不勾+动态提示仅存本地的记录条数；删 App 提示为设置页常驻文案。

## 当前状态

- 当前阶段：Phase 1 本地化主线（收入/钱包纳入后的本地事实闭环目标）；阶段索引中的 LOCAL-003-RC 双口径已由 SL-01 收口，下一步为 SL-02。
- 已验证基线：全部结论基于 2026-09-25 静态只读代码阅读（分支 codex/local-first-phase1-fact-reader，HEAD 7005e81）。关键事实经主流程二次抽查（discard 不幂等、分域阈值、local-staging/ 前缀、未登录四域手动创建走本地 AppState.swift:4492-4494、单参数 IntakeRouter 死 API）。
- 当前提交：本轮文档改动（BDD 文档、领域收敛文档新增与 §10 更新，以及 SL-01 口径收口）尚未提交；业务代码零改动。

## 未验证

- iOS 编译/XCTest：Windows 无 Swift 工具链，以 macOS GitHub Actions 为准（延续既有纪律）。
- K 片真机验收清单仍未关闭（TestFlight build 35487465615 的相机/相册/快捷指令、断网、重启、登录切换验证）。
- 领域收敛文档中 SL-A/SL-B（收入/钱包本地域）的 schema 设计未开始，实施时需先补切片级 Grooming（表结构、FactReader 扩展、导出 schema v2）。

## 剩余风险

- 换账号可看见前任账号本地数据（Q-02 维持现状，用户已知并接受）。
- unsupported 域（wallet 在 SL-B 完成前）回退云端 ingest 产生"云端有本地无"分叉数据。
- 双读取路径与三套引用前缀为已登记债务，SL-02 只固定现状不合并；真合并延后。
- 删除 App 本地数据全丢（Q-10 仅做提示性缓解）。

## 冻结范围

- Cloud Sync/Outbox/Cursor/冲突协议/多设备（ADR-040 范围）、D-REMOTE 成果保留不扩展。
- L2 老用户迁移（F11，待开始，不解冻）。
- PWA 结构性改动（维护模式）、生产迁移/部署/TestFlight（需当轮用户明确授权）。
- 登录态新记录路由语义（Q-08 特征冻结，不随重构漂移）。

## 下一步

1. **已完成** SL-01 文档口径收口（非代码）：HANDOFF §3、阶段索引双口径、Grooming DM-GAP-02/03 已收敛与 DM-GAP-10 不采纳、BDD LF-017/LF-028/LF-029~031 状态及规格索引已同步。
2. SL-02 投影收敛+特征测试加固：AppState private refreshLocalMonthProjection 替换 8 处分支；删除单参数 route 死 API；LF-001/LF-002/DM-011/DM-014 具名红灯；三套引用前缀路由特征测试。
3. SL-A 收入本地域（先做切片级 Grooming：local income 表结构、校验规则、FactReader/导出/聚合扩展、schema 版本）→ SL-B 钱包快照本地域（最小形态）。
4. SL-03 候选编辑确认（并入 discard 幂等）→ SL-04 候选重试/域重判 → M1 五域真机验收 Gate。

## 相关入口

- 总规范：`docs/spec/00-系统总览规格说明.md`、`docs/spec/01-跨端一致性契约.md`、`docs/spec/02-TDD实施与交接规范.md`
- 本轮产物：`docs/spec/LOCAL-FIRST-BDD-COVERAGE.md`、`docs/spec/LOCAL-FIRST-DOMAIN-CONVERGENCE.md`（拍板记录在 §10）
- 模块 Spec：`docs/spec/LOCAL-FIRST-PHASE1-HANDOFF.md`、`docs/spec/LOCAL-FIRST-PHASE1-DATA-MODEL-GROOMING-RESULT.md`
- ADR：ADR-036（本地权威与 AI 正交）、ADR-037（GRDB）、ADR-039（统一页面）、ADR-040（同步收缩）
- 测试或 CI 证据：macOS iOS workflow（最近 35510609001 通过）；K 片生产 smoke（HANDOFF §18）
- 用户侧记忆：Obsidian「AI 视觉自动记账项目/规划/Local-First Phase 1 拍板与交接」
