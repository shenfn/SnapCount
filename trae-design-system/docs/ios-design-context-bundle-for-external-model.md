# 芥子 iOS 外部设计模型上下文包

> 本文件用于打包发送给"前端设计能力很强但较贵"的外部 AI 模型。
> 使用方式：先复制下方的"系统提示词"作为第一条消息，再按 Tier 顺序粘贴对应文件内容。
> 生成日期：2026-07-19

---

## 1. 系统提示词（复制这段作为第一条消息）

```markdown
你是一位顶尖的 iOS 前端设计专家，擅长东方侘寂美学、SwiftUI 视觉实现、Design System 和用户体验设计。

我正在开发一款名为"芥子"的个人记忆可视化 iOS App，基于 SwiftUI。它不是一个冷冰冰的工具，而是一个"记忆生境"——用户的日常数据在这里沉淀、生长、被温柔地看见。

## 项目核心气质

- 东方侘寂：留白、时间的痕迹、不完美之美
- 克制安静：不要炫技，不要让 UI 抢内容的风头
- 暖调纸张感：像一本私人日记本的底色
- 双层空间：正常空间（日常功能）+ 下拉空间（品牌情绪与深层表达）
- 玻璃质感：卡片使用半透明毛玻璃 + 1px 微边框
- 柔和渐变：背景是 paper → brand 微量混入 → light 微量混入的渐变

## 当前已有设计资产

- JieziTheme.swift：包含颜色系统、基础渐变、GlassPanel、PrimaryActionButton
- 9 个主题：芥青微光、玄青须弥、宣纸生境、竹影鎏金、藕荷余晖、苔茶暖金、月白远青、枯木逢春、古刹苔痕
- design-tokens.json：包含完整 Design Token（颜色、字体、间距、圆角、阴影、动效）

## 你的任务

请基于我提供的上下文文件，帮我完成以下设计任务：
[在此处填入具体任务]

## 输出要求

1. 先给出 2-3 个不同方向的设计方案，用一句话概括每个方案的气质
2. 推荐其中一个方案并说明理由
3. 给出具体的 SwiftUI 实现代码或伪代码
4. 标注使用的 Design Token（如 `JieziSpacing.lg`、`JieziRadius.card`、`theme.palette.brand`）
5. 如果需要图片/SVG 资源，请明确说明尺寸、格式、命名
6. 说明与现有 JieziTheme.swift 的兼容关系（复用/扩展/替换）
7. 不要引入新的第三方依赖
8. 避免使用纯文本空状态，空状态必须包含视觉占位

## 设计禁区

- 不要使用高饱和霓虹色
- 不要使用粗黑边框、硬阴影
- 不要让按钮/卡片看起来像原生 iOS 默认组件
- 不要堆积信息，保持留白
- 不要为动效而动效

请先阅读我下面提供的上下文文件，然后给出你的设计方案。
```

---

## 2. 上下文文件清单

### Tier 1：必读（决定设计方向）

请按顺序粘贴以下文件内容到对话中。

#### 2.1 设计基调文档

**文件**：`docs/前端设计理念/芥子长期产品与设计基调.md`

**重点章节**：
- 第 1 章：产品与设计的长期基调
- 第 2 章：核心隐喻
- 第 4 章：视觉母题
- 第 5 章：双层空间
- 第 6 章：材质与光
- 第 9 章：主题与变奏
- 第 10 章：设计禁区

**为什么重要**：这是项目的"宪法"，所有视觉决策必须回归到这里。

---

#### 2.2 iOS 设计系统核心

**文件**：`ios/SnapCount/DesignSystem/JieziTheme.swift`

**为什么重要**：定义了当前 iOS 端实际使用的颜色、渐变和基础组件。外部模型必须理解现有代码结构，避免与现有实现冲突。

---

#### 2.3 App 导航骨架

**文件**：`ios/SnapCount/Features/Root/RootView.swift`

**为什么重要**：展示了 5 个主标签页（首页、中转站、记录、洞察、设置），帮助模型理解信息架构。

---

#### 2.4 Design Token SSOT

**文件**：`trae-design-system/tokens/design-tokens.json`

**为什么重要**：颜色、字体、间距、圆角、阴影、动效的权威数据源。模型应优先引用这里定义的 Token，而不是发明新值。

---

### Tier 2：强烈建议（理解现状）

#### 2.5 视觉实验室原型

**文件**：`jiezi-visual-lab/index.html`

**为什么重要**：HTML 原型展示了 9 主题切换、下拉空间交互、时间相位效果，是视觉风格的最好参考。

---

#### 2.6 主题颜色定义

**文件**：`jiezi-visual-lab/src/themes.js`

**为什么重要**：9 个主题的完整颜色定义，防止模型使用错误色值。

---

#### 2.7 要优化的具体页面

**根据当前任务选择 1-3 个**：

- `ios/SnapCount/Features/Home/HomeView.swift`
- `ios/SnapCount/Features/Records/RecordsView.swift`
- `ios/SnapCount/Features/Insights/InsightsView.swift`
- `ios/SnapCount/Features/Settings/SettingsView.swift`
- `ios/SnapCount/Features/Transit/TransitView.swift`

**为什么重要**：让模型在现有代码基础上改造，而不是凭空设计。

---

#### 2.8 现有视觉资产

**目录**：`ios/SnapCount/Resources/Assets.xcassets/`

**重点查看**：
- `AppIcon.appiconset/` —— 当前图标
- `AccentColor.colorset/` —— 强调色
- `LaunchBackground.colorset/` —— 启动背景色

**为什么重要**：避免与现有图标/颜色冲突，保持品牌一致性。

---

### Tier 3：可选补充

#### 2.9 iOS 原生设计分析

**文件**：`docs/ios-native-design-analysis-v0.1.md`

**为什么重要**：记录了 iOS 原生迁移的设计考量。

---

#### 2.10 项目主 README

**文件**：`README.md`

**为什么重要**：项目整体定位和技术栈说明。

---

## 3. 提示词变体（按任务类型选择）

### 3.1 页面视觉优化

```markdown
任务：优化 [页面名] 的视觉设计。

当前问题：[描述问题]

要求：
- 在保持现有功能不变的前提下优化视觉层次
- 使用现有 JieziTheme 颜色，必要时扩展 semantic token
- 提供修改后的 SwiftUI 代码
- 说明每个改动的设计理由
```

### 3.2 设计新页面

```markdown
任务：为 [功能名] 设计一个全新的 SwiftUI 页面。

上下文：
- 这个页面属于 [Root 哪个 tab]
- 核心数据：[数据类型]
- 主要操作：[用户在此页做什么]

要求：
- 给出页面信息架构（IA）
- 给出 2-3 种布局方案草图描述
- 推荐一种并给出完整 SwiftUI 代码
- 标注所有 Design Token
```

### 3.3 组件设计

```markdown
任务：设计一个 [组件名] 组件。

要求：
- 组件需要支持 [状态/变体]
- 使用现有 design tokens
- 提供可复用的 SwiftUI View 代码
- 给出 2-3 个使用示例
```

### 3.4 图标/AppIcon 设计

```markdown
任务：为 iOS App 设计 [AppIcon / Tab Bar Icon / 功能图标]。

要求：
- 风格：东方侘寂、克制、耐看
- 给出具体的设计描述（可用于 AI 图像生成）
- 说明尺寸、格式、命名规范
- 如果需要，说明如何在 SwiftUI 中使用
```

### 3.5 设计 Review

```markdown
任务：Review 我提供的 [文件/页面/截图] 的视觉设计。

请从以下维度给出评分和改进建议：
1. 是否符合"芥子"东方侘寂风格？
2. 信息层次是否清晰？
3. 颜色使用是否克制？
4. 留白是否足够？
5. 是否有 native iOS 默认感过重的地方？
6. 空状态/加载态/错误态是否完整？
7. 双层空间理念是否体现？

按优先级列出 Top 5 改进点。
```

---

## 4. 文件路径速查（绝对路径）

```text
d:\Business\count\docs\前端设计理念\芥子长期产品与设计基调.md
d:\Business\count\ios\SnapCount\DesignSystem\JieziTheme.swift
d:\Business\count\ios\SnapCount\Features\Root\RootView.swift
d:\Business\count\trae-design-system\tokens\design-tokens.json
d:\Business\count\jiezi-visual-lab\index.html
d:\Business\count\jiezi-visual-lab\src\themes.js
d:\Business\count\ios\SnapCount\Resources\Assets.xcassets\
d:\Business\count\docs\ios-native-design-analysis-v0.1.md
d:\Business\count\README.md
```

---

## 5. 省钱建议

1. **先给 Tier 1，再问方向**：不要一次性把所有文件都贴上去。
2. **方向确定后再给细节**：避免模型在错误方向上生产大量代码。
3. **一次只问一个页面/组件**：按任务收费模型会很贵。
4. **先让模型给伪代码/描述**：确认方向后再要完整 SwiftUI 代码。
5. **让贵的模型做设计决策，让便宜的模型写代码**：设计方向确定后，具体实现可以交给 TRAE 或其他 cheaper 模型。
