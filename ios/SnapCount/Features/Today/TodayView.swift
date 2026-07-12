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
            JieziPageBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    dashboardStatus
                    metricStrip
                    captureButton
                    dailySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .refreshable { await appState.refreshDashboard() }
        }
        .navigationBarHidden(true)
        .confirmationDialog("留下此刻", isPresented: $showUploadOptions, titleVisibility: .visible) {
            Button("从相册选择") { showPhotoLibraryPicker = true }
            Button("拍摄照片") { showCameraPicker = true }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { data in
                showCameraPicker = false
                Task { await uploadImageData(data, captureKind: "camera", filename: "camera-capture.jpg") }
            } onCancel: { showCameraPicker = false }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PhotoLibraryPicker { data in
                showPhotoLibraryPicker = false
                Task { await uploadImageData(data, captureKind: "screenshot", filename: "photo-library-upload.jpg") }
            } onCancel: { showPhotoLibraryPicker = false }
        }
        .alert(uploadMessageIsError ? "上传失败" : "上传完成", isPresented: $showUploadResult) {
            Button("好", role: .cancel) {}
        } message: { Text(uploadMessage ?? "") }
    }

    @ViewBuilder
    private var dashboardStatus: some View {
        if appState.isLoadingDashboard && appState.dashboard.monthCount == 0 {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在同步 PWA 数据")
            }
            .font(.subheadline)
            .foregroundStyle(JieziTheme.muted)
        } else if let message = appState.dashboardMessage {
            Button { Task { await appState.refreshDashboard() } } label: {
                Label("数据加载失败，点此重试：\(message)", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else if !appState.dashboard.loadWarnings.isEmpty {
            Text("部分数据域暂未同步，已显示可用数据")
                .font(.footnote)
                .foregroundStyle(JieziTheme.gold)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("个人数据平台")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(JieziTheme.ink)
                Text(Self.fullDateFormatter.string(from: Date()))
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
            }
            Spacer()
            Text(Self.monthFormatter.string(from: Date()))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white.opacity(0.82), in: Capsule())
                .overlay(Capsule().stroke(JieziTheme.brand.opacity(0.08)))
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 10) {
            metric(title: "净额", value: money(appState.dashboard.monthIncome - appState.dashboard.monthExpense, signed: true))
            metric(title: "待还", value: "¥0")
            metric(title: "今日", value: money(appState.dashboard.todayIncome - appState.dashboard.todayExpense, signed: true))
            metric(title: "待处理", value: "\(appState.dashboard.pendingCount)条")
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(JieziTheme.muted)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(JieziTheme.ink).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var captureButton: some View {
        Button { showUploadOptions = true } label: {
            HStack(spacing: 14) {
                Image(systemName: isUploading ? "hourglass" : "camera.viewfinder")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isUploading ? "正在识别" : "留下此刻").font(.headline)
                    Text("拍照或从相册选择图片").font(.subheadline).opacity(0.72)
                }
                Spacer()
                Image(systemName: "plus").font(.title2)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(JieziTheme.brand, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每日明细").font(.title3.bold())
                    Text("按日期汇总本月所有数据").font(.subheadline).foregroundStyle(JieziTheme.muted)
                }
                Spacer()
                Text("报告 ›").font(.headline).foregroundStyle(JieziTheme.brand)
            }

            if appState.dashboard.dailySummaries.isEmpty {
                dailyCard(NativeDailySummary(dateKey: Self.dateKeyFormatter.string(from: Date()), expense: 0, income: 0, pendingCount: appState.dashboard.pendingCount, recordCount: 0))
            } else {
                ForEach(appState.dashboard.dailySummaries) { dailyCard($0) }
            }
        }
    }

    private func dailyCard(_ day: NativeDailySummary) -> some View {
        Button {
            appState.selectedTab = .records
            appState.recordsPath.removeAll()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(day.dateKey.suffix(5))).font(.system(size: 26, weight: .black, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text(weekday(day.dateKey)).font(.headline).foregroundStyle(JieziTheme.muted)
                }
                Divider().overlay(JieziTheme.muted.opacity(0.2))
                if day.expense > 0 { summaryRow(color: JieziTheme.coral, title: "支出", value: money(day.expense)) }
                if day.income > 0 { summaryRow(color: JieziTheme.brand, title: "收入", value: money(day.income, signed: true)) }
                if day.pendingCount > 0 { summaryRow(color: JieziTheme.gold, title: "待处理", value: "\(day.pendingCount)条") }
                if day.expense == 0 && day.income == 0 && day.pendingCount == 0 {
                    summaryRow(color: JieziTheme.muted, title: "记录", value: "\(day.recordCount)条")
                }
            }
            .foregroundStyle(JieziTheme.ink)
            .padding(20)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(JieziTheme.brand.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(color: Color, title: String, value: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(JieziTheme.muted)
            Spacer()
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func money(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)¥\(Int(value.rounded()))"
    }

    private func weekday(_ dateKey: String) -> String {
        guard let date = Self.dateKeyFormatter.date(from: dateKey) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    private func uploadImageData(_ data: Data, captureKind: String, filename: String) async {
        isUploading = true
        defer { isUploading = false }
        do {
            guard let uploadToken = try KeychainStore.shared.string(for: KeychainKeys.uploadToken), !uploadToken.isEmpty else { throw SnapCountUploadServiceError.requestFailed("登录凭据未同步，请重新登录") }
            uploadMessage = try await SnapCountUploadService().uploadNativeImage(data: data, uploadToken: uploadToken, captureKind: captureKind, filename: filename)
            uploadMessageIsError = false
            await appState.refreshDashboard()
        } catch {
            uploadMessage = "上传失败：\(error.localizedDescription)"
            uploadMessageIsError = true
        }
        showUploadResult = true
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日"; return formatter
    }()
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月"; return formatter
    }()
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "EEE"; return formatter
    }()
}
