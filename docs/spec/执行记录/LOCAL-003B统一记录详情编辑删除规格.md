# LOCAL-003B 统一记录详情、编辑、删除执行记录

> 状态：规格草案，待评审
>
> 分支：`docs/LOCAL-003B统一记录详情编辑删除规格`
>
> 基线：`origin/main@7a4e366`

## 本轮完成

- 核对 LOCAL-003A 已合并，macOS Build 和 250 个 XCTest 通过。
- 核对本地 Repository 已具备 expense/account 的 update、delete、流水和 tombstone/outbox 基础。
- 新增 LOCAL-003B 规格，锁定本地详情、编辑、删除、余额投影和云端兼容回归边界。

## 基线和未验证项

- 尚未修改 Swift 业务代码。
- 尚未建立 LOCAL-003B 红灯测试。
- 尚未验证本地引用进入 `RecordDetailView` 后不会调用远端详情。
- Windows 无法运行 Swift XCTest；红灯和绿灯需由 GitHub macOS Build 证明。

## 冻结范围

- 不实现登录绑定、首次同步、Outbox 上传、冲突合并或其他数据域。
- 不修改 PWA、Edge、Supabase schema、生产配置、TestFlight 或根工作区 WIP。

## 下一步

1. 评审并合并本规格。
2. 从最新 main 建立 `test/LOCAL-003B统一记录详情编辑删除红灯`，先固定 B1-B8 的关键失败。
3. 红灯确认后建立 `feature/LOCAL-003B统一记录详情编辑删除实现`，做最小本地详情和事务接线。
