# SnapCount · 个人数据平台

> **一张截图，记一笔账。** 基于 AI 视觉识别的 PWA，把微信/支付宝等消费截图一键沉淀成结构化数据，并以"多数据域"架构向记账之外的个人数据管理场景扩展（运动、睡眠、阅读等）。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Stack](https://img.shields.io/badge/Stack-Vue3_%7C_Supabase_%7C_Cloudflare-green.svg)](#-技术架构)
[![PWA](https://img.shields.io/badge/PWA-Ready-purple.svg)](#-部署指南)

---

## ✨ 核心特性

- **📸 截图即记账**：iOS 快捷指令一键上传截图 → AI 识别商家/金额/支付方式 → 自动入账
- **🧠 AI 识别可控**：识别结果进入"待补全"队列，置信度不够时回落到人工确认（绝不污染数据）
- **🔒 多用户 + RLS**：每个用户的账单/收入/数据完全隔离，`auth.uid() = user_id` 行级安全策略
- **🔀 多数据域扩展**：记账只是起点。运动、睡眠、阅读等数据域基于统一 `data_records` 架构，可持续扩展
- **🔁 去重 & 幂等**：pHash + dHash + 文本哈希三重去重，快捷指令重传同一张截图也不会重复记账
- **⚡ PWA 体验**：下拉刷新、后台切回自动刷新、离线友好、支持添加到主屏
- **💰 自部署低成本**：Supabase + Cloudflare 全免费额度即可长期运行个人级使用

---

## 🏗️ 技术架构

```
 ┌─────────────────┐        ┌──────────────────────────────┐
 │  iOS Shortcuts  │ ──📸──▶│  Supabase Edge Function      │
 └─────────────────┘        │  ingest-receipt              │
                            │                              │
 ┌─────────────────┐        │  1. 存原图到 Storage         │
 │  PWA (Vue 3)    │◀──🔄──▶│  2. pHash/文本去重           │
 │  Cloudflare     │        │  3. 调用 Moonshot Vision     │
 │  Pages          │        │  4. 结构化入库 transactions  │
 └────────┬────────┘        │     / income_records         │
          │                 │     / data_records           │
          │                 └──────────────┬───────────────┘
          │                                │
          ▼                                ▼
 ┌─────────────────────────────────────────────────┐
 │  Cloudflare Worker (supabase-proxy)             │
 │  反向代理 api.snapflow.me → *.supabase.co       │
 │  注入 anon key + CORS                           │
 └────────────────────┬────────────────────────────┘
                      ▼
           ┌─────────────────────┐
           │  Supabase           │
           │  Postgres + Storage │
           │  Auth + RLS         │
           └─────────────────────┘
```

**前端**：Vue 3 + Vite · Composition API · PWA
**后端**：Supabase（Postgres + Edge Functions + Storage + Auth + RLS）
**AI**：Moonshot / Kimi Vision API（可替换为其他 Vision 模型）
**托管**：Cloudflare Pages（静态）+ Cloudflare Worker（反向代理）

---

## 🚀 部署指南

### 前置要求

- Node.js 18+ 和 npm
- 一个 Supabase 项目（[免费注册](https://supabase.com)）
- 一个 Cloudflare 账号（可选，用于反代和 Pages 托管）
- 一个 Moonshot API Key（[申请](https://platform.moonshot.cn)）或其他 Vision 模型 key

### 1. 克隆与依赖

```bash
git clone https://github.com/shenfn/SnapCount.git
cd SnapCount
npm install
```

### 2. 配置环境变量

复制示例文件并填入真实值：

```bash
cp .env.example .env.local
# 编辑 .env.local，填入 VITE_SUPABASE_URL 和 VITE_SUPABASE_ANON_KEY
```

### 3. 初始化 Supabase 数据库

安装 [Supabase CLI](https://supabase.com/docs/guides/cli)，然后：

```bash
supabase link --project-ref <your-project-ref>
supabase db push   # 推送 supabase/migrations/ 下的所有迁移文件
```

迁移文件包含完整的表结构、RLS 策略和索引（见 `supabase/migrations/`）。

### 4. 部署 Edge Function

```bash
# 设置 secrets（一次性）
supabase secrets set SUPABASE_URL="https://<your-project-ref>.supabase.co"
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
supabase secrets set MOONSHOT_API_KEY="<your-moonshot-key>"

# 部署
supabase functions deploy ingest-receipt --no-verify-jwt
```

### 5.（可选）部署 Cloudflare Worker 反代

把 `cloudflare-worker/supabase-proxy.js` 部署到 Cloudflare Workers，在 Settings → Variables 中设置：

- `SUPABASE_URL` = `https://<your-project-ref>.supabase.co`
- `SUPABASE_ANON_KEY` = `<your-anon-key>`

绑定自定义域名后，把 `.env.local` 里的 `VITE_SUPABASE_URL` 改为你的 Worker 域名。

### 6. 本地开发 / 构建

```bash
npm run dev      # 本地开发
npm run build    # 构建 dist/
npm run preview  # 预览生产构建
```

### 7.（可选）托管到 Cloudflare Pages

在 Pages 绑定 GitHub 仓库，构建命令 `npm run build`，输出目录 `dist/`。

---

## 📱 iOS 快捷指令使用

1. 在设置页获取你的 `upload_token`
2. 将以下快捷指令动作串起来：
   - 获取剪贴板/截图
   - POST `https://<your-endpoint>/functions/v1/ingest-receipt`（multipart/form-data）
   - 附带 `upload_token` 字段
3. 返回 JSON 中的 `notification` 字段可直接用作系统通知文案

完整快捷指令模板与参数说明会在后续补齐到 Wiki。若你迫切需要，可在应用内"设置 → 快捷指令接入"页查看当前步骤文案。

---

## 🗂️ 项目结构

```
SnapCount/
├── src/                      Vue 3 前端
│   ├── components/
│   │   ├── pages/            各页面（Home / Pending / Report / Settings ...）
│   │   └── Modal*.vue        各操作弹窗（支出/收入/待补全 ...）
│   ├── composables/          Vue 组合式逻辑（核心在 useStore.js）
│   ├── lib/supabase.js       Supabase 客户端
│   ├── styles/               样式
│   └── utils/                工具函数
├── supabase/
│   ├── migrations/           数据库迁移（001 ~ 011）
│   └── functions/
│       └── ingest-receipt/   截图识别 Edge Function
├── cloudflare-worker/
│   └── supabase-proxy.js     Cloudflare Worker 反向代理
├── public/                   静态资源
├── scripts/                  运维脚本（如查看 AI 日志）
└── .env.example              环境变量示例
```

---

## 🗺️ Roadmap

- [x] 截图识别支出 / 收入
- [x] 待补全队列 + 人工确认
- [x] 多数据域架构（运动 / 睡眠）
- [x] iOS 快捷指令集成
- [x] 多用户 + RLS
- [x] PWA + 下拉刷新
- [ ] 阅读数据域
- [ ] 预算管理与月度报告
- [ ] 多 AI Provider（Gemini / GPT-4V）
- [ ] 用户自定义数据域（AI 生成 schema）
- [ ] 数据导出（CSV / JSON）

---

## 🤝 贡献

欢迎提 Issue 与 Pull Request。提交代码前请确认：

- 遵循项目既有代码风格（Vue 3 Composition API + `<script setup>`）
- 不引入未经讨论的新依赖
- 不在代码中硬编码任何 secret

---

## 📜 License

**AGPL-3.0-or-later** — 详见 [LICENSE](./LICENSE)。

### 协议说明

- **个人使用、学习、修改、分发**：完全自由，遵守 AGPL 义务即可
- **基于本项目提供网络服务**：必须将你的修改以 AGPL 同等协议开源给服务的使用者
- **闭源商用 / 去除 AGPL 反向共享义务**：需向作者获得单独授权

若你计划将本项目用于商业产品，请通过 GitHub Issue 或邮件与作者联系商业授权事宜。

---

## 🙏 致谢

- [Supabase](https://supabase.com) — 全栈 BaaS
- [Moonshot](https://platform.moonshot.cn) — Kimi Vision API
- [Cloudflare](https://cloudflare.com) — Pages + Workers
- [Vue](https://vuejs.org) — 前端框架
