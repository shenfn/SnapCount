import SwiftUI
import PhotosUI

struct TodayView: View {
    @State private var showUploadSheet = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploading = false
    @State private var uploadMessage: String?
    @State private var uploadMessageIsError = false

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
            UploadEntrySheet(selectedPhoto: $selectedPhoto, isUploading: isUploading)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                await upload(photo: newValue)
            }
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
                if let uploadMessage {
                    Text(uploadMessage)
                        .font(.footnote)
                        .foregroundStyle(uploadMessageIsError ? JieziTheme.coral : JieziTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func upload(photo: PhotosPickerItem) async {
        isUploading = true
        uploadMessage = "正在上传并等待 AI 识别结果。"
        uploadMessageIsError = false
        showUploadSheet = false

        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw NativeUploadError.emptyImage
            }
            guard let uploadToken = try KeychainStore.shared.string(for: KeychainKeys.uploadToken),
                  !uploadToken.isEmpty else {
                throw NativeUploadError.missingUploadToken
            }
            let message = try await SnapCountUploadService().uploadNativeImage(
                data: data,
                uploadToken: uploadToken
            )
            uploadMessage = message
            uploadMessageIsError = false
        } catch {
            uploadMessage = "上传失败：\(error.localizedDescription)"
            uploadMessageIsError = true
        }

        selectedPhoto = nil
        isUploading = false
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
    @Binding var selectedPhoto: PhotosPickerItem?
    let isUploading: Bool

    var body: some View {
        NavigationStack {
            List {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("选择照片", systemImage: "photo")
                }
                Button {
                } label: {
                    Label("拍摄照片", systemImage: "camera")
                }
                .disabled(true)
                Section {
                    Text(isUploading ? "正在上传并等待 AI 识别结果。" : "相机入口下一阶段接入；当前先验证相册选图上传。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("上传")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum NativeUploadError: LocalizedError {
    case emptyImage
    case missingUploadToken

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "没有读取到图片数据。"
        case .missingUploadToken:
            return "缺少上传凭据，请重新登录。"
        }
    }
}
