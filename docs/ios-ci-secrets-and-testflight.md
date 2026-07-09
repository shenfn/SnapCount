# iOS GitHub Actions Secrets 与 TestFlight 流程

> 适用分支：`codex/ios-swiftui-native-app`  
> 适用 workflow：`.github/workflows/ios-build.yml`、`.github/workflows/ios-testflight.yml`

## 1. Workflow 分工

| Workflow | 触发方式 | 是否签名 | 是否上传 TestFlight | 用途 |
|---|---|---:|---:|---|
| iOS Build | 手动 `workflow_dispatch` | 否 | 否 | 快速验证 SwiftUI / XcodeGen 是否能编译 |
| iOS TestFlight | 手动 `workflow_dispatch` | 是 | 是 | 生成 IPA 并上传 TestFlight |

首轮建议先跑 `iOS Build`。它不需要 Apple 证书类 Secrets，只需要 GitHub macOS runner 能安装 XcodeGen 并完成模拟器构建。

## 2. 需要配置的 Secrets

### 2.1 iOS Build 可选 Secrets

| Secret | 用途 | 是否首轮必须 |
|---|---|---:|
| `IOS_SUPABASE_URL` | 写入 iOS App 的 Supabase URL | 否 |
| `IOS_SUPABASE_ANON_KEY` | 写入 iOS App 的 Supabase anon key | 否 |

当前原生 App 还没接真实登录和上传，所以这两个 Secret 可以后置。

### 2.2 TestFlight 必须 Secrets

| Secret | 用途 |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Apple Distribution `.p12` 证书的 Base64 |
| `P12_PASSWORD` | `.p12` 证书密码 |
| `PROVISIONING_PROFILE_BASE64` | App Store provisioning profile 的 Base64 |
| `KEYCHAIN_PASSWORD` | CI 临时 keychain 密码，自己生成一个强密码即可 |
| `APPLE_API_KEY_BASE64` | App Store Connect `.p8` API Key 的 Base64 |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect Issuer ID |
| `IOS_SUPABASE_URL` | iOS App 后端地址 |
| `IOS_SUPABASE_ANON_KEY` | iOS App Supabase anon key |

## 3. Windows PowerShell Base64 命令

在本地 PowerShell 执行以下命令，只把输出填进 GitHub Secrets，不要发到聊天或提交到仓库。

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("reference/iOS/snapflow.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("reference/iOS/snapflow_appstore.mobileprovision"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("reference/iOS/AuthKey_CTZXDZ7KS3.p8"))
```

## 4. GitHub 页面配置路径

进入仓库：

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

逐个添加第 2 节中的 Secret。

## 5. 第一次验证顺序

1. 推送 `codex/ios-swiftui-native-app` 分支。
2. 打开 GitHub Actions。
3. 手动运行 `iOS Build`。
4. 如果编译失败，先根据日志修 Swift / XcodeGen。
5. `iOS Build` 通过后，再配置 TestFlight Secrets。
6. 手动运行 `iOS TestFlight`。
7. 等 App Store Connect 处理完成。
8. iPhone 打开 TestFlight 安装。

## 6. 安全提醒

- 不要提交 `reference/` 目录。
- 不要把 Base64 输出贴到聊天里。
- 如果 `.p12` 密码曾经暴露过，正式提交审核前建议重新导出 `.p12` 并更换密码。
