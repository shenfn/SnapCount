# AI 本地验证功能交接说明

## 功能定位

这个功能用于在不推送 `main`、不重新部署前端的情况下，批量验证 AI 截图识别链路。

它会把本地 `test-cases/` 里的测试图片上传到线上 `ingest-receipt` Edge Function，模拟真实用户上传截图，然后把每张图的识别响应保存到本地 `test-results/`。

注意：这不是离线 OCR，也不是纯前端模拟。只要不加 `--dry-run`，它就会真实请求 Supabase 线上函数，并可能在专用测试账号下产生线上测试数据。

## 适用场景

- 验证 AI 弹窗需要的 `ai_feedback` 是否返回正常。
- 验证支出、收入、转账、钱包、运动、睡眠、阅读等截图能否被正确识别。
- 在推送 `main` 之前，用本地测试图片批量回放真实识别链路。
- 给每轮测试打 `run_id`，便于回看结果和清理测试数据。

## 当前相关文件

- `scripts/test-ingest-receipt.mjs`：本地回放测试脚本。
- `scripts/cleanup-test-receipts.mjs`：测试数据清理脚本。
- `docs/ai-validation-workflow-plan-v0.1.md`：较完整的方案设计文档。
- `docs/ai-validation-handoff.md`：当前这份交接说明。
- `.gitignore`：已忽略测试素材和测试结果目录。

## 本地目录约定

测试图片放在：

```text
test-cases/
  expense/
    2026-06-27/
      001-meituan-food-order-12_40.png
  income/
    2026-06-27/
      001-wechat-red-packet-received.png
  transfer/
    2026-06-27/
      001-wechat-transfer-22_00.png
```

识别结果输出到：

```text
test-results/
  <run-id>/
    summary.md
    summary.json
    expense/
      2026-06-27/
        001-meituan-food-order-12_40.response.json
```

`test-cases/`、`test-results/`、`.ai-validation-cache/` 都不应该提交到 GitHub。

## 当前测试图片分类

当前本地测试集已整理到 `test-cases/<domain>/2026-06-27/`，共 38 张：

- `expense`：11 张
- `wallet`：6 张
- `transfer`：4 张
- `income`：1 张
- `sport`：6 张
- `sleep`：3 张
- `food`：4 张
- `reading`：1 张
- `other`：2 张

分类原则：微信聊天转账先放 `transfer`，不强行归入 `income`；红包领取放 `income`；余额、资产、白条、花呗、月付类放 `wallet`。

## 测试账号

默认专用测试账号：

```text
0a552a27-0b64-456e-a5b3-e50e261d2e4f
```

脚本默认使用这个账号。不要把日常真实账号混入批量测试，避免污染正式数据。

## 如何使用

先 dry-run，确认会跑哪些图片，不上传、不写线上数据：

```powershell
npm run test:receipt -- --dir test-cases --dry-run
```

跑单张图片：

```powershell
npm run test:receipt -- --image test-cases/expense/2026-06-27/001-meituan-food-order-12_40.png
```

只跑某个域：

```powershell
npm run test:receipt -- --dir test-cases --domain expense
```

跑完整测试集，并指定批次号：

```powershell
npm run test:receipt -- --dir test-cases --run-id local-ai-popup-v1
```

建议每次真实批量测试都显式指定 `--run-id`，这样后续更容易查结果和清理。

## 结果怎么看

优先看：

```text
test-results/<run-id>/summary.md
```

重点关注：

- HTTP 状态是否成功。
- `record_type` 是否符合预期。
- 是否返回 `ai_feedback`。
- 是否进入了预期的数据类型。
- 错误样本对应的 `.response.json` 原始响应。

如果要排查单张图，打开对应的：

```text
test-results/<run-id>/<domain>/<date>/<file>.response.json
```

## 测试标签机制

测试脚本会随请求传入：

- `test_run_id`
- `test_case_domain`
- `test_case_date`
- `test_case_file`

Edge Function 当前会把这些信息写入：

- `data_records.payload_jsonb.test_meta`
- `staging_records.extracted_json.test_meta`

用途是追踪和清理测试数据，不应该影响正式展示、统计、AI prompt、AI 记忆或任何业务计算。

## 清理测试数据

先 dry-run 查看会清理什么：

```powershell
npm run cleanup:test-receipts -- --run-id local-ai-popup-v1
```

真实删除必须显式确认：

```powershell
npm run cleanup:test-receipts -- --run-id local-ai-popup-v1 --execute --yes
```

安全规则：

- 默认只 dry-run。
- 真实删除必须带 `--run-id`。
- 真实删除只允许默认专用测试账号。
- 当前清理脚本只处理 `data_records` 和 `staging_records` 中带 `test_meta` 的数据。

## 已知限制

- 如果某些截图直接进入 `transactions` 或 `income_records`，这两张表当前没有独立 `test_meta` 字段，不能只靠清理脚本完全自动清理。
- 对直接落入 `transactions` / `income_records` 的测试记录，应结合本地响应里的 `target_id`、`ai_recognition_logs` 或 Supabase 查询人工确认后再处理。
- 当前脚本验证的是线上已部署的 `ingest-receipt` 行为，不会验证本地尚未部署的 Edge Function 改动。
- **感知哈希去重验证存在盲区**：本地测试上传的永远是同一张原图（字节级一致），感知哈希完全相同，去重 100% 命中。但真实环境中 iOS 快捷指令截图会经过质量压缩、宽度压缩，加上同一页面截图也会因网络加载状态、动态内容、时间戳等产生像素级差异，导致感知哈希有波动。因此：
  - 本地测试能验证"去重逻辑是否生效"，但**无法验证去重阈值在真实压缩波动下是否稳健**。
  - 真实环境中可能出现"同一页面重复截图但因哈希偏移超过阈值而被当作新图"的漏判情况。
  - 后续如需验证去重阈值稳健性，需要模拟 iOS 压缩流程（质量压缩 + 宽度 resize）生成变体图片再上传对比。

## 交接给下一个 Agent 的注意事项

- 不要提交 `test-cases/` 和 `test-results/`。
- 不要在未确认前批量跑真实上传，先跑 `--dry-run`。
- 不要对非测试账号执行清理。
- 不要把 `test_meta` 接入正式 UI、统计、AI 上下文或业务计算。
- Git 操作遵循“可以多 commit，必须少 push”：本地 commit 可以作为可回滚存档点；push 会影响远程 `main`，并可能触发 GitHub Action 部署，必须在用户明确确认后执行。
- 涉及 `main` 推送、Edge Function 部署、线上删除时，先向用户确认。
- 如果要验证未部署的 Edge Function 改动，需要先解决部署链路；本脚本默认打的是线上函数地址。

## Git 协作规则：多 commit，少 push

`commit` 和 `push` 的风险级别不一样。

`commit` 是本地保存点。它只写入当前机器的 Git 历史，不会影响 GitHub，也不会触发线上部署。合理拆分 commit 的好处是：每一步改动都有记录，后续如果某个方向错了，可以更容易定位、回退或挑选保留。

`push` 是把本地 commit 发到 GitHub。当前项目的 `main` 推送可能触发 GitHub Action，并进一步部署 Edge Function 或前端更新。因此 push 属于对远程和线上有影响的操作，不能频繁、随意执行。

推荐做法：

- 开发过程中可以按功能点多次 commit，例如“整理测试目录”“补本地验证脚本”“补清理脚本”“补交接文档”。
- 每次 commit 前确认没有把 `test-cases/`、`test-results/`、密钥、隐私截图混进去。
- 在本地 build、脚本 dry-run、必要的单图测试都通过后，再考虑 push。
- push 前向用户说明将推送哪些 commit、是否会触发 Action、预期影响是什么。
- 如果用户没有明确同意，不要执行 `git push origin main`。

一句话：commit 是“本地打存档”，push 是“对外发布并可能部署”。前者可以作为安全网多做，后者必须克制并确认。

## 本地登录 Failed to fetch 排查记录

如果本地 Vite 页面可以打开，但登录时报 `Failed to fetch`，先检查当前 localhost 端口是否在 `cloudflare-worker/supabase-proxy.js` 的 CORS 白名单里。

已确认一次典型原因：本地页面运行在 `http://localhost:5175/`，但 Worker 的 `ALLOWED_ORIGINS` 只包含 `5173`、`5174`、`4173`、`3000` 等端口，浏览器会因为 CORS 拦截 Supabase Auth 请求，前端只能看到笼统的 `Failed to fetch`。

`https://api.snapflow.me/` 返回 `{"error":"requested path is invalid"}` 不代表 Worker 坏了；根路径本来不是 Supabase API 的有效路径。真正要看的是 `/auth/v1/...`、`/rest/v1/...`、`/functions/v1/...` 请求是否被 CORS 允许。

建议修复：把实际使用的本地端口加入白名单，或改成允许 `/^http:\/\/localhost:\d+$/` 这类本地开发 Origin；线上域名如 `https://snap-count-delta.vercel.app` 如需通过同一 Worker 调 API，也应加入白名单。
