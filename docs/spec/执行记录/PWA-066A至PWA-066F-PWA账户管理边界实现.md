# PWA-066A 至 PWA-066F PWA 账户管理边界实现记录

> 日期：2026-08-16
>
> 基线：`d42fcba`（PWA-066 收口 PR #101 合并提交）
>
> 分支：`feature/PWA账户管理边界实现`
>
> 状态：正式 Spec 已建立，待 PostgreSQL 红灯

## 当前范围

- PWA-066A：存量规范化、旧客户端兼容 trigger、默认约束和迁移幂等。
- PWA-066B：canonical save/archive RPC 与数据库业务不变量。
- PWA-066C：Account Repository 写 transport 与 DTO。
- PWA-066D：Account Management Feature 并发与 stale。
- PWA-066E：canonical 收敛与 accepted/refresh 分层。
- PWA-066F：Store/Page 兼容、归档列表和恢复出口。

## 已完成

- 已读取 TDD 规范、账户管理边界评估、ADR-027 和收口交接。
- 已建立正式 Spec、文件范围、非目标、数据库契约、测试层与完成定义。
- 业务代码、migration 和测试尚未修改。

## 基线

- `test:account-read`：17 项通过。
- `test:repayment`：15 项通过。
- `test:account-binding`：11 项通过。
- Vite build 和架构检查通过，仅既有警告。

## 下一步

1. 新增 PostgreSQL fixture/assertion 与 Release Validation job。
2. 在目标 migration 缺失时确认 PWA-066A/PWA-066B 有效红灯。
3. 红灯成立后实现最小 migration，不提前修改 Repository 或页面。

## 未验证与风险

- canonical RPC、trigger、约束和 PWA 接线均未实现。
- 本机是否具备 PostgreSQL/Docker 运行环境尚未确认；环境失败不得冒充业务红灯。
- 生产数据现状未知，未执行生产查询或写入。
