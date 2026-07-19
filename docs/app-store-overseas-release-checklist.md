# 芥子 App 海外上架隐私与链接清单

更新日期：2026-07-19

## 发布区域

- 第一阶段：新加坡、香港、澳门、台湾。
- 暂不选择：中国大陆、欧盟、英国、韩国。
- 后续新增地区前，重新核对当地隐私、消费者保护和数字服务义务。

## App Store Connect 链接

GitHub Pages 默认地址：

- 隐私政策：`https://shenfn.github.io/SnapCount/privacy.html`
- 服务协议：`https://shenfn.github.io/SnapCount/terms.html`
- 支持页面：`https://shenfn.github.io/SnapCount/support.html`

配置 `legal.snapflow.me` 后改为：

- 隐私政策：`https://legal.snapflow.me/privacy.html`
- 服务协议：`https://legal.snapflow.me/terms.html`
- 支持页面：`https://legal.snapflow.me/support.html`

在 GitHub 仓库 Settings > Pages 中启用 GitHub Actions，并将 Custom domain 设置为 `legal.snapflow.me`。DNS 添加 `CNAME legal shenfn.github.io`；证书生效前不要开启强制 HTTPS。

## App Privacy 建议勾选

以下类别均用于 App 功能，与用户身份关联，不用于跨 App 跟踪：

- Contact Info > Email Address
- Identifiers > User ID
- User Content > Photos or Videos
- User Content > Other User Content
- Financial Info > Other Financial Info
- Health & Fitness > Health
- Health & Fitness > Fitness
- Diagnostics > Other Diagnostic Data

声明“Data Used to Track You”为否，不声明广告用途。诊断数据同时用于 App Functionality；用户主动开启 AI 日志或 Prompt 优化时可包含 Analytics 用途。

## 第三方与数据区域

- Supabase Auth、Postgres、Edge Functions、Storage：新加坡 `ap-southeast-1`。
- 阿里云百炼 Qwen：中国内地兼容接口；仅允许 `qwen3.6-flash`、`qwen3.7-plus`。
- 自建 Relay、Moonshot、MiMo：生产代码不再初始化或回退。

## 审核备注

- 芥子是个人生活记录与数据整理工具，不提供支付、信贷、投资或医疗服务。
- 注册必须分别同意服务协议/隐私政策与敏感数据/跨区域处理。
- App 内提供数据导出、原图留存设置和删除账户。
- AI 结果可能出错，重要金额、账户、还款和睡眠字段要求用户确认。
- 准备一个不包含真实个人信息的审核账号，并在 Review Notes 写明测试入口和删除账户路径。

## 发布前人工核对

- Pages 三个 URL 无需登录即可访问，移动端排版正常。
- App 内协议版本与网页版本均为 `2026-07-19`。
- App Store Connect 的 App Privacy 与 `PrivacyInfo.xcprivacy` 一致。
- Supabase 已应用迁移 `078`、`079`，并部署最新 `ingest-receipt`、`generate-insights`。
- Qwen API Key 可用，旧服务商密钥即使仍存在也不会被运行时代码读取。
- 完成 TestFlight 注册、上传、图片留存、洞察、导出和删号验收后再提交审核。
