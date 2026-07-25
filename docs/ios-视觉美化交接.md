# iOS 视觉美化分支交接

更新时间：2026-07-24

这份文档是后续 Agent 接手 iOS 视觉美化时的操作边界和验证清单。目标是让视觉迭代可以持续进行，同时不破坏根工作区、其他 worktree、生产数据库和用户正在进行的改动。

## 当前状态

- 工作目录：`D:\Business\count\.worktrees\ios-视觉美化`
- 分支：`codex/ios-视觉美化`
- 当前基线提交：`6429c62a058797538030e4718551f582b4736daf`
- 远程分支：`origin/codex/ios-视觉美化`
- 设计系统基础组件已经加入 iOS 工程，但页面接入仍在进行中。
- 设计 Token SSOT 位于 `trae-design-system/tokens/design-tokens.json`。
- iOS 生成产物位于 `ios/SnapCount/DesignSystem/JieziTheme+Generated.swift`。
- `trae-design-system/dist/` 被根 `.gitignore` 的 `dist/` 规则忽略；它是本地生成缓存，不应强制提交。
- Windows 本地没有 Xcode/Swift 工具链，iOS 编译必须依赖 GitHub Actions 的 macOS runner。

## 工作区边界

1. 所有本次视觉修改只在上述视觉 worktree 中进行。
2. `D:\Business\count` 根工作区属于 `codex/ios-swiftui-native-app`，可能有用户未提交 WIP，禁止清理、重置、切换分支或批量格式化。
3. 其他 worktree 由其他功能线使用，不能为了“同步”直接覆盖其文件。
4. 开始修改前必须运行：

   ```powershell
   git worktree list --porcelain
   git status --short --branch
   ```

5. 如果当前 worktree 的分支引用、HEAD 或 worktree 清单异常，先停止 Git 写操作并记录状态；不要用 `reset --hard`、`checkout --`、`git clean -fd` 或手工删除 refs 进行“修复”。

## Git 提交规范

### 分支

- 长期基线是 `origin/main`。
- 新功能从最新 `origin/main` 创建短期 `codex/*` 分支。
- 本分支只承载 iOS 视觉系统和页面接入，不直接承担数据库迁移、Edge Function 或算法修改。
- 页面接入完成后通过 Draft PR 合并，不把多个长期功能分支互相 merge 成新的永久分支。

### 提交前

必须先确认没有混入用户文件：

```powershell
git status --short --untracked-files=all
git diff --check
git diff --stat
```

设计 Token 变更应遵循：

1. 修改 `trae-design-system/tokens/design-tokens.json`。
2. 运行对应 generator：

   ```powershell
   node trae-design-system/scripts/generate-ios.mjs
   node trae-design-system/scripts/generate-css.mjs
   node trae-design-system/scripts/generate-tailwind.mjs
   ```

3. 检查 iOS 生成文件与 generator 输出一致。
4. 不手改 `trae-design-system/dist/`；不在 Swift 页面里发明新的全局颜色、圆角、间距 token。

提交按一个可验证主题组织，推荐格式：

```text
feat(ios): 接入记录页视觉组件
fix(ios): 修复生成主题引用
docs(ios): 补充视觉分支交接规范
```

不要把密钥、Service Role Key、用户图片、数据库备份、`.env`、本地原型和测试素材提交到仓库。

### 提交与推送

只有在用户明确允许提交/推送时才执行：

```powershell
git add <明确列出的文件>
git diff --cached --check
git commit -m "<符合上面格式的消息>"
git push -u origin codex/ios-视觉美化
```

提交前不使用 `git add -A`，避免把忽略规则以外的本地素材带入。提交后必须记录 commit SHA 和远程分支，不要自动合并 main。

## CI/CD 边界

### iOS CI

`.github/workflows/ios-build.yml`：

- PR 指向 `main` 时，检测 `ios/**` 或 workflow 自身变化；有变化才运行 macOS iOS Build。
- 支持 `workflow_dispatch` 手动触发。
- 先生成 `GeneratedAppConfig.swift` 和 Xcode project，再编译模拟器并运行 `SnapCountTests`。
- Windows 只能做 Node generator、静态检查和 diff 检查，不能把本地“未编译”当成通过。

### TestFlight

`.github/workflows/ios-testflight.yml` 只有 `workflow_dispatch`，不会因为 push 或 PR 自动上传。必须先满足：

- iOS Build 和单测通过。
- Draft PR diff 已复核。
- 用户明确授权上传。
- 使用固定提交 SHA 手动触发，记录 Actions run URL、构建号和提交 SHA 的对应关系。

### 生产边界

视觉分支禁止执行以下动作：

- `supabase db push`、生产 migration、生产备份恢复。
- Edge Function 部署或生产函数源码替换。
- 修改 `supabase/functions/**` 以外的算法行为，尤其是 Expression Planner。
- 直接合并 `main` 或修改 main 分支保护。

视觉变更只在 iOS 工程和设计系统范围内验证。生产数据库、PWA 和 Edge 部署由发布集成流程负责。

## 页面接入原则

- 保留现有 repository、AppState、NavigationRoute、保存和删除逻辑；视觉工作不能通过重写数据层“顺便修功能”。
- 优先使用 `JieziType`、`JieziSpacing`、`JieziRadius`、`JieziStroke`、`JieziShadows`、`JieziSectionHeader`、`JieziCard`、`JieziListRow`、`JieziMetric` 和 `JieziEmptyState`。
- 同一页面保持一套滚动容器，避免 `ScrollView` 套 `List` 或嵌套会抢手势的滚动视图。
- 对图片、加载、错误、空态和长文本保留稳定尺寸与可读 fallback；不能为了视觉隐藏事实字段。
- 待补全页面的字段门禁、账户影响和确认 RPC 不得改动；只能调整信息层级、卡片、排版和反馈。
- 任何模型统计口径和事实来源仍由代码固定，视觉改动不能把统计交给 AI 文案。

## 接手后的验证顺序

1. `git status --short --branch`，确认只在本 worktree。
2. `rg` 检查旧 token、硬编码敏感信息和设计系统引用。
3. 运行 generator 的 `node --check`、`git diff --check`。
4. 检查 Swift 文件的新增引用和 XcodeGen source glob，不修改生成的 `ios/SnapCount.xcodeproj`。
5. 用户允许后，提交并推送一个主题明确的 commit。
6. 等待 iOS Build 和单测完成；失败时只根据 Actions 日志修复当前提交，不回滚用户 WIP。
7. CI 通过后再开下一组页面改动；不在一次提交里同时改视觉、后端和数据库。

## 异常处理

- 发现本地 `codex/*` refs 消失、worktree HEAD 变成全零、`.git/index` 被异常替换或出现未知 Git 进程时，立即停止写操作。
- 先保存只读诊断：`git status`、`git reflog --all`、`git worktree list --porcelain`、进程命令行和时间戳。
- 只有在用户确认来源和恢复方案后，才恢复特定 ref；恢复时逐个验证 SHA 是 commit，并在跨命令检查后再继续。
- 不把“引用短暂消失”直接归因于某个 Agent；记录证据、进程和复现条件。

这份文档本身不包含任何凭据、用户数据或生产连接信息。
