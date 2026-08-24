# LOCAL-003B 统一记录详情编辑删除红灯执行记录

> 状态：红灯已建立，待评审
>
> 分支：`test/LOCAL-003B统一记录详情编辑删除红灯`
>
> 基线：`origin/main@3dca336`

## 本轮范围

- 固定本地 `local-expense/<UUID>` 详情不依赖云端会话；
- 固定本地编辑、删除必须进入本地事务门面；
- 记录统一详情导航已存在，作为特征测试通过项保留。

## 红灯命令与结果

```text
npm run test:ios-local-record-detail-boundary
```

- LOCAL-003B1：失败，当前 `loadRecordDetail` 直接 `validSession()` 和 `recordRepository.fetchDetail`；
- LOCAL-003B2：通过，统一 `NativeRecordRoute` 详情目的地已存在；
- LOCAL-003B3：失败，当前 `saveRecordDetail` / `deleteRecord` 直接调用远端 Repository。

失败原因均为目标行为缺失，不是编译、网络或凭据问题。

## 冻结范围

- 本轮只新增边界测试和执行记录，不修改 Swift 业务实现。
- 不实现登录绑定、首次同步、Outbox、冲突或其他数据域。

## 下一步

1. 合并红灯 PR。
2. 从最新 main 建立 `feature/LOCAL-003B统一记录详情编辑删除实现`。
3. 先补本地详情映射和 AppState 门面，再补 Repository 事务测试和 macOS XCTest。
