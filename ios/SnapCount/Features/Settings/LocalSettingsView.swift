import SwiftUI

struct LocalSettingsView: View {
    @EnvironmentObject private var themeManager: JieziThemeManager

    var body: some View {
        List {
            Section {
                Label("本机使用", systemImage: "iphone")
                LabeledContent("数据存储") {
                    Text("仅保存在此 iPhone")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("云同步") {
                    Text("云同步尚未开启")
                        .foregroundStyle(.secondary)
                }
            }

            Section("外观") {
                NavigationLink {
                    LocalThemeSettingsView()
                } label: {
                    LabeledContent("界面主题") {
                        Text(themeManager.palette.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("关于") {
                LabeledContent("当前版本") {
                    Text(versionLabel)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    LegalDocumentView(kind: .privacy)
                } label: {
                    Label("隐私政策", systemImage: "hand.raised")
                }
                NavigationLink {
                    LegalDocumentView(kind: .terms)
                } label: {
                    Label("服务协议", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("设置")
        .scrollContentBackground(.hidden)
        .background(JieziGradient.pageBackground(palette: themeManager.palette))
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

private struct LocalThemeSettingsView: View {
    @EnvironmentObject private var themeManager: JieziThemeManager

    var body: some View {
        List {
            ForEach(JieziGeneratedPalette.all, id: \.id) { palette in
                Button {
                    JieziHaptics.tap()
                    themeManager.switchTo(palette.id)
                } label: {
                    HStack(spacing: JieziSpacing.md) {
                        Text(palette.name)
                            .foregroundStyle(themeManager.palette.ink)
                        Spacer()
                        Image(systemName: themeManager.palette.id == palette.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                themeManager.palette.id == palette.id
                                    ? themeManager.palette.brand
                                    : themeManager.palette.muted.opacity(0.45)
                            )
                    }
                    .padding(.vertical, JieziSpacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("界面主题")
        .scrollContentBackground(.hidden)
        .background(JieziGradient.pageBackground(palette: themeManager.palette))
    }
}
