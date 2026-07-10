import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showUploadOptions = false
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var isUploading = false
    @State private var uploadMessage: String?
    @State private var uploadMessageIsError = false
    @State private var showUploadResult = false

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    capturePanel
                    rhythmPanel
                    recentPanel
                    shortcutPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .refreshable {
                await appState.refreshDashboard()
            }
        }
        .navigationTitle("芥子")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .confirmationDialog("上传", isPresented: $showUploadOptions, titleVisibility: .visible) {
            Button("选择照片") {
                showPhotoLibraryPicker = true
            }
            Button("拍摄照片") {
                openCamera()
            }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { data in
                showCameraPicker = false
                Task {
                    await uploadImageData(
                        data,
                        captureKind: "camera",
                        filename: "camera-capture.jpg"
                    )
                }
            } onCancel: {
                showCameraPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PhotoLibraryPicker { data in
                showPhotoLibraryPicker = false
                Task {
                    await uploadImageData(
                        data,
                        captureKind: "photo_library",
                        filename: "photo-library-upload.jpg"
                    )
                }
            } onCancel: {
                showPhotoLibraryPicker = false
            }
        }
        .alert(uploadMessageIsError ? "上传失败" : "上传完成", isPresented: $showUploadResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(uploadMessage ?? "")
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
                Text("拍照、相册和快捷指令都会上传到同一条 AI 识别链路。")
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                PrimaryActionButton(title: "上传截图或照片", systemImage: "photo.on.rectangle.angled") {
                    showUploadOptions = true
                }
                .disabled(isUploading)
                if isUploading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在等待 AI 识别结果")
                            .font(.footnote)
                            .foregroundStyle(JieziTheme.muted)
                    }
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
            MetricTile(title: "今日", value: "\(appState.dashboard.todayCount)", caption: "新记录")
            MetricTile(title: "待处理", value: "\(appState.dashboard.pendingCount)", caption: "收件箱")
            MetricTile(title: "本月", value: "\(appState.dashboard.monthCount)", caption: "总记录")
        }
    }

    private var recentPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("最近记录", systemImage: "clock")
                        .font(.headline)
                    Spacer()
                    if appState.isLoadingDashboard {
                        ProgressView()
                    }
                }

                if let message = appState.dashboardMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(JieziTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                } else if appState.dashboard.recentRecords.isEmpty {
                    Text("这个原生版本刚接入数据读取。下拉刷新，或上传一张图片后再查看。")
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.muted)
                } else {
                    VStack(spacing: 10) {
                        ForEach(appState.dashboard.recentRecords.prefix(5)) { item in
                            NativeRecordRow(item: item)
                        }
                    }
                }
            }
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
                    Text("快捷指令怎么用")
                        .font(.headline)
                    Text("打开快捷指令 App，新建快捷指令：先添加“截屏”或“选择照片”，再添加“上传到芥子”，把图片传给它。Keychain 凭据会在后台自动使用。")
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.muted)
                }
            }
        }
    }

    private func openCamera() {
        showCameraPicker = true
    }

    private func uploadImageData(
        _ data: Data,
        captureKind: String,
        filename: String
    ) async {
        isUploading = true
        uploadMessage = "正在上传并等待 AI 识别结果。"
        uploadMessageIsError = false

        do {
            guard let uploadToken = try KeychainStore.shared.string(for: KeychainKeys.uploadToken),
                  !uploadToken.isEmpty else {
                throw NativeUploadError.missingUploadToken
            }
            let message = try await SnapCountUploadService().uploadNativeImage(
                data: data,
                uploadToken: uploadToken,
                captureKind: captureKind,
                filename: filename
            )
            uploadMessage = message
            uploadMessageIsError = false
            await appState.refreshDashboard()
            showUploadResult = true
        } catch {
            uploadMessage = "上传失败：\(error.localizedDescription)"
            uploadMessageIsError = true
            showUploadResult = true
        }

        isUploading = false
    }
}

private struct NativeRecordRow: View {
    let item: NativeRecordSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(JieziTheme.mint)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            if !item.value.isEmpty {
                Text(item.value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
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
