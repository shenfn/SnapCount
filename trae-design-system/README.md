# 芥子设计系统（trae-design-system）

> 由 TRAE 协助搭建 · v0.1 · 2026-07-19
> 上位文档：[芥子长期产品与设计基调](../../docs/前端设计理念/芥子长期产品与设计基调.md)

---

## 这是什么

一套**单一数据源（SSOT）驱动**的设计 Token 系统，覆盖 iOS SwiftUI / PWA Vue / Tailwind 三端。所有颜色、字体、间距、圆角、阴影、动效、主题、时间相位都从 `tokens/design-tokens.json` 一处定义，通过生成脚本派生出各端可消费的产物。

**核心理念**：改 SSOT，不改产物；每端只消费，不发明；生成可重现。

---

## 目录结构

```
trae-design-system/
├── tokens/
│   └── design-tokens.json     # ★ SSOT，唯一数据源
├── scripts/
│   ├── generate-ios.mjs       # 生成 iOS Swift Token
│   ├── generate-css.mjs       # 生成 PWA CSS Variables + JS Token
│   └── generate-tailwind.mjs  # 生成 Tailwind Preset
├── dist/                      # 生成产物（自动覆盖，禁止手改）
│   ├── jiezi/
│   │   └── JieziTheme+Generated.swift
│   ├── pwa/
│   │   ├── tokens.css
│   │   └── tokens.js
│   └── tailwind/
│       └── jiezi-tailwind.config.cjs
└── docs/
    └── 芥子设计系统-v0.1.md    # 完整设计规范文档
```

---

## 快速开始

### 1. 生成全部产物

```bash
cd trae-design-system
node scripts/generate-ios.mjs
node scripts/generate-css.mjs
node scripts/generate-tailwind.mjs
```

无需安装任何 npm 包，仅需 Node.js ≥ 18。

### 2. 接入 iOS 项目

将 `dist/jiezi/JieziTheme+Generated.swift` 拖入 `ios/SnapCount/DesignSystem/`，无需修改现有 `JieziTheme.swift`。

```swift
@StateObject private var themeManager = JieziThemeManager()
// 切换主题：themeManager.switchTo("springWood")
```

### 3. 接入 PWA 项目

将 `dist/pwa/tokens.css` 复制到 `src/styles/jiezi-tokens.css`，在 `main.js` 中 import。

```js
// 切换主题
document.documentElement.setAttribute('data-theme', 'springWood')
```

### 4. 接入 Tailwind

```js
// tailwind.config.js
const jiezi = require('./path/to/jiezi-tailwind.config.cjs')
module.exports = { presets: [jiezi] }
```

---

## 内置主题（9 个）

| ID | 名称 | 默认端 |
|----|------|--------|
| `cyan` | 芥青微光 | iOS |
| `xuan` | 玄青须弥 | — |
| `paper` | 宣纸生境 | — |
| `jade` | 竹影鎏金 | — |
| `lotus` | 藕荷余晖 | — |
| `tea` | 苔茶暖金 | — |
| `moon` | 月白远青 | — |
| `springWood` | 枯木逢春 | PWA |
| `temple` | 古刹苔痕 | — |

---

## Token 分类概览

| 分类 | 数量 | 说明 |
|------|------|------|
| 颜色主题 | 9 个 | 每个主题 7 个语义槽位 |
| 时间相位 | 7 段 | 深夜 / 破晓 / 晨光 / 日中 / 午后 / 暮色 / 入夜 |
| 字体层级 | 11 级 | 与 iOS HIG 对齐 |
| 间距 | 12 级 + 6 语义 | t-shirt 风格命名 |
| 圆角 | 8 级 + 5 语义 | 4 ~ 9999px |
| 阴影 | 6 级 + 3 语义 | 含品牌色阴影 |
| 动效 | 5 时长 + 5 曲线 + 5 语义 | iOS / PWA 双端映射 |
| 渐变 | 5 种 | 页面 / 须弥 / 品牌 + 2 overlay |
| 布局 | 7 项 | 页面宽度、安全区等 |
| z-index | 6 级 | 层叠顺序 |

---

## 完整文档

- [芥子设计系统 v0.1 完整规范](./docs/芥子设计系统-v0.1.md) — 必读
- [芥子长期产品与设计基调](../../docs/前端设计理念/芥子长期产品与设计基调.md) — 上位原则

---

## 设计原则

1. **改 SSOT，不改产物** — `dist/` 目录所有文件由生成脚本覆盖
2. **每端只消费，不发明** — 不允许在 Swift / CSS / Tailwind 中私自新增 token
3. **生成可重现** — 任意环境运行脚本得到相同产物
4. **语义 Token 优先** — 用 `card_padding` 而非 `xl2`，便于未来调整
5. **主题不是皮肤** — 主题可以重新解释材质、光线、空间，但共享同一套核心价值

---

## 未完成项（v0.1 如实记录）

- 对比度自动校验脚本
- 深色模式自动适配
- Figma Tokens Studio 双向同步
- 组件库实现（Button/Card/Modal 等）
- 视觉回归测试
- iOS 时间相位实时调色的具体实现
- PWA `applyTimePhase` JS 函数实现

详见 [设计规范文档第 17 节](./docs/芥子设计系统-v0.1.md#17-未解决问题如实记录)。

---

## 版本

- v0.1.0 / 2026-07-19 / 初版框架，仅产出 Token，不含组件库
