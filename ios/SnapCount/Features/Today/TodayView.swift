import SwiftUI

struct TodayView: View {
    @State private var showUploadSheet = false

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    capturePanel
                    rhythmPanel
                    shortcutPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("芥子")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .sheet(isPresented: $showUploadSheet) {
            UploadEntrySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal AI Memory")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.muted)
            Text("把生活里的截图，整理成能被你重新看见的数据。")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(JieziTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capturePanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("快速捕获", systemImage: "camera.viewfinder")
                    .font(.title3.weight(.semibold))
                Text("首版会接入拍照、相册选图和快捷指令上传。现在这层先用来验证原生导航、玻璃材质和系统弹层。")
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                PrimaryActionButton(title: "上传截图或照片", systemImage: "photo.on.rectangle.angled") {
                    showUploadSheet = true
                }
            }
        }
    }

    private var rhythmPanel: some View {
        HStack(spacing: 12) {
            MetricTile(title: "今日", value: "0", caption: "等待接入")
            MetricTile(title: "待处理", value: "0", caption: "收件箱")
            MetricTile(title: "本月", value: "0", caption: "记录")
        }
    }

    private var shortcutPanel: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(JieziTheme.gold)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("App Intents 已进入首版范围")
                        .font(.headline)
                    Text("快捷指令会把截图作为输入交给芥子，由原生 Intent 直接上传到现有 ingest-receipt。")
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.muted)
                }
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JieziTheme.muted)
                Text(value)
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(JieziTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UploadEntrySheet: View {
    var body: some View {
        NavigationStack {
            List {
                Button {
                } label: {
                    Label("选择照片", systemImage: "photo")
                }
                Button {
                } label: {
                    Label("拍摄照片", systemImage: "camera")
                }
                Section {
                    Text("下一阶段会接入 PhotosPicker、相机和 multipart 上传。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("上传")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
