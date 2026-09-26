# 芥子本地优先原型

这是 Expense + Account 本地优先体验的 HTML 原型入口。原型不是正式业务实现，而是页面结构、操作路径和状态展示的验收基准。

## 当前阶段：Prototype v0.2 / iOS 样式一比一 · 首页五组件对齐

- 视觉基线：`trae-design-system/tokens/design-tokens.json`（SSOT）
- CSS 产物：`node trae-design-system/scripts/generate-css.mjs` → `dist/pwa/tokens.css`
- 默认主题：`cyan`（与 iOS `JieziGeneratedPalette.defaultPalette` 一致）
- 导航：iOS 五栏 — 今日 / 收件箱 / 记录 / 分析 / 设置（对应 `RootView` / `AppTab`）
- 首页结构：对齐 PWA `PageHome.vue` 五组件（财务 / 今日概览 / 待处理 / 数据域 / 每日明细）+ 速览条 + 组件管理
- 组件：对齐 `ios/SnapCount/DesignSystem/*`（Card / Button / ListRow / Metric / Chip / EmptyState / Form / TabBar）
- 暂不包含：真实业务数据、Supabase、PostgreSQL、GRDB

## 本地预览

仓库根目录 `D:\Business\count`：

```powershell
node .\trae-design-system\scripts\generate-css.mjs
py -m http.server 4173 --directory .
```

浏览器打开：`http://127.0.0.1:4173/prototype/`

若已在 `prototype` 目录：

```powershell
node ..\trae-design-system\scripts\generate-css.mjs
py -m http.server 4173 --directory ..
```

## 文件结构

```text
prototype/
  index.html                      # 五栏壳 + 页面骨架 + 组件陈列
  shared/css/tokens.css           # 从 dist 拷贝的自包含 token（预览不依赖上级路径）
  shared/css/ios-shell.css        # 设备框、页面背景、TabBar、字体角色 + 变量兜底
  shared/css/ios-components.css   # DesignSystem 组件 class
  shared/css/prototype.css        # 工作台补充
  shared/js/app.js                # 路由、九主题切换、日期、首页交互
```

Token 真源仍是 `trae-design-system/tokens/design-tokens.json`；改完请：

```powershell
node trae-design-system/scripts/generate-css.mjs
Copy-Item trae-design-system/dist/pwa/tokens.css prototype/shared/css/tokens.css -Force
```

## 样式对齐原则

1. 颜色 / 间距 / 圆角 / 阴影 / 域色只读 `tokens.css` 变量，不手写第二套色板。
2. iOS 语义字号（display 28 serif、money rounded、sectionTitle 20 等）在 `ios-shell.css` 的 `--ios-type-*` 中按 `JieziType` 校准（比 PWA token 大一档）。
3. 页面背景三层：线性 paper 渐变 + 右上 light 径向 + 左上白光，对齐 `JieziPageBackground`。
4. 卡片玻璃感：paper 72% + blur + brand 11% 描边 + space 8% 阴影；solid 卡为 92% 底 + sm 阴影。

## 工作台操作

- **切换主题**：循环九套主题（cyan → xuan → paper → …），并写入 `localStorage`
- **组件陈列**：跳到 `#lab` 查看按钮 / Chip / 指标 / 空态 / 消息对照

## 后续阶段

1. ~~Today 首页结构对齐 PWA PageHome 五组件~~
2. ~~Records 列表点击 → 记录详情（支出 / 收入 / 饮食 / 睡眠 / 运动）~~
3. ~~Inbox 中转站：范围/状态筛选、胶片卡片、裁决台、归档/重试/销毁~~
4. ~~Settings 完整分区（同步、AI、隐私留存、快捷指令、关于、导出面板）~~
5. ~~Accounts 资产/负债列表 + 账户详情（还款计划、流水）~~
6. Today 状态矩阵（空态 / 离线 / 失败）与真实 Canonical Fixture
7. Capture 图片记账全流程
8. 细节打磨：动效、空态文案、日详情页、报告页

`dist/` 是生成产物，不手工修改；设计调整回到 `tokens/design-tokens.json`。
