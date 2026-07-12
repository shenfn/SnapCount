import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section("概览") {
                    HStack {
                        Label("本月记录", systemImage: "calendar")
                        Spacer()
                        Text("\(appState.dashboard.monthCount)")
                            .monospacedDigit()
                    }
                    HStack {
                        Label("今日记录", systemImage: "sun.max")
                        Spacer()
                        Text("\(appState.dashboard.todayCount)")
                            .monospacedDigit()
                    }
                }

                if !appState.dashboard.recentRecords.isEmpty {
                    Section("最近") {
                        ForEach(appState.dashboard.recentRecords) { item in
                            NavigationLink(value: item.id) {
                                Label {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(item.title)
                                            Text(item.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(item.value)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: item.systemImage)
                                }
                            }
                        }
                    }
                }

                Section("数据域") {
                    Label("消费", systemImage: "creditcard")
                    Label("饮食", systemImage: "fork.knife")
                    Label("运动", systemImage: "figure.run")
                    Label("睡眠", systemImage: "moon")
                    Label("阅读", systemImage: "book")
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await appState.refreshDashboard()
            }
        }
        .navigationTitle("记录")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .navigationDestination(for: String.self) { reference in
            RecordDetailView(reference: reference)
        }
    }
}

private struct RecordDetailView: View {
    @EnvironmentObject private var appState: AppState
    let reference: String
    @State private var imagePreview: ImagePreviewRoute?
    @State private var editDraft: NativeRecordEditDraft?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                if let detail = appState.selectedRecordDetail {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: detail.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(JieziTheme.mint)
                                .frame(width: 38, height: 38)
                                .background(.thinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.title)
                                    .font(.headline)
                                Text(detail.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !detail.value.isEmpty {
                                Text(detail.value)
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }

                    if let imageURL = detail.imageURL {
                        Section("截图原图") {
                            Button {
                                imagePreview = ImagePreviewRoute(url: imageURL)
                            } label: {
                                RecordImagePreview(url: imageURL)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if detail.imageLoadError {
                        Section("截图原图") {
                            unavailableImageView
                        }
                    }

                    Section("记录字段") {
                        ForEach(detail.detailRows) { row in
                            LabeledContent(row.label, value: row.value)
                        }
                    }
                } else if let message = appState.recordDetailMessage {
                    ContentUnavailableView(
                        "无法读取记录",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                } else {
                    ProgressView("正在读取记录")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("记录详情")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            if let detail = appState.selectedRecordDetail {
                if detail.isEditable {
                    Button {
                        editDraft = NativeRecordEditDraft(detail: detail)
                    } label: {
                        Label("编辑", systemImage: "square.and.pencil")
                    }
                    .disabled(appState.isSavingRecordDetail)
                }

                if detail.isDeletable {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(appState.isDeletingRecordDetail)
                }
            }
        }
        .task(id: reference) {
            await appState.loadRecordDetail(reference: reference)
        }
        .sheet(item: $imagePreview) { route in
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    CachedRemoteImage(url: route.url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    } failure: {
                        Label("截图文件不可用", systemImage: "photo.badge.exclamationmark")
                            .foregroundStyle(.white)
                    }
                    .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            imagePreview = nil
                        }
                    }
                }
            }
        }
        .sheet(item: $editDraft) { draft in
            RecordEditSheet(draft: draft) { savedDraft in
                await appState.saveRecordDetail(savedDraft)
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    _ = await appState.deleteRecord(reference: reference)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会同步处理关联账户流水，截图文件是否清理仍沿用现有服务端规则。")
        }
    }

    private var unavailableImageView: some View {
        Label("截图文件不可用或已删除", systemImage: "photo.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct RecordImagePreview: View {
    let url: URL

    var body: some View {
        CachedRemoteImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
        } placeholder: {
            ProgressView().frame(maxWidth: .infinity, minHeight: 180)
        } failure: {
            Label("截图文件不可用或已删除", systemImage: "photo.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeRecordEditDraft
    @State private var message: String?
    @State private var isSaving = false
    let onSave: (NativeRecordEditDraft) async -> Bool

    init(draft: NativeRecordEditDraft, onSave: @escaping (NativeRecordEditDraft) async -> Bool) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(draft.kind == "income" ? "收入" : "消费") {
                    TextField(draft.kind == "income" ? "来源" : "商户", text: $draft.title)
                    TextField("金额", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                    TextField("日期", text: $draft.recordDate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if draft.kind == "expense" {
                    Section("消费字段") {
                        TextField("平台", text: $draft.platform)
                        TextField("分类", text: $draft.category)
                        TextField("支付方式", text: $draft.paymentMethod)
                    }
                } else {
                    Section("收入字段") {
                        TextField("类型", text: $draft.category)
                    }
                }

                Section("备注") {
                    TextField("备注", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if draft.accountId != nil {
                    Section {
                        Label("会保留当前账户绑定，并同步更新账户流水。", systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(JieziTheme.coral)
                    }
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        message = nil
        let ok = await onSave(draft)
        isSaving = false
        if ok {
            dismiss()
        } else {
            message = "保存失败，请检查字段或稍后重试。"
        }
    }
}

private struct ImagePreviewRoute: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
