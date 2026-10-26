import SwiftUI

/// Local-only archive browser. Viewing a preserved row never confirms or posts it.
struct LocalHistoryUnresolvedRecordsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                Text("这些历史记录已完整保存在本机，暂不计入账目、余额或按日统计。查看不会修改数据，也不会访问云端。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if appState.isLoadingHistoryUnresolvedRecords {
                ProgressView("正在读取本机历史待核对记录")
            } else if let message = appState.historyUnresolvedRecordsError {
                Text(message).foregroundStyle(JieziTheme.coral)
            } else if appState.localHistoryUnresolvedRecords.isEmpty {
                Text("本机暂无历史待核对记录。预检中的记录需确认恢复后才会保存在这里。")
                    .foregroundStyle(.secondary)
            } else {
                Section("本机已保留 \(appState.localHistoryUnresolvedRecords.count) 条") {
                    ForEach(appState.localHistoryUnresolvedRecords, id: \.id) { record in
                        NavigationLink {
                            LocalHistoryUnresolvedDetailView(record: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.sourceTable == "staging_records" ? "历史候选" : "历史数据记录")
                                Text(record.issues.first ?? "历史内容暂无法等价转换")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            Button("重新读取本机清单") { Task { await appState.loadLocalHistoryUnresolvedRecords() } }
                .disabled(appState.isLoadingHistoryUnresolvedRecords)
        }
        .navigationTitle("历史待核对")
        .task { await appState.loadLocalHistoryUnresolvedRecords() }
    }
}

private struct LocalHistoryUnresolvedDetailView: View {
    @EnvironmentObject private var appState: AppState
    let record: LocalHistoryUnresolvedRecord
    @State private var image: UIImage?
    @State private var imageMessage: String?

    var body: some View {
        if appState.localHistoryUnresolvedRecords.contains(where: { $0.id == record.id && $0.profileID == record.profileID }) {
            detailContent
        } else {
            Text("当前本机清单已变化，请返回重新读取历史待核对记录。")
                .foregroundStyle(.secondary)
        }
    }

    private var detailContent: some View {
        List {
            Section("保留状态") {
                Text("仅保留历史原文和原图，不计入账目、余额或按日统计；本页不提供确认入账操作。")
                    .font(.subheadline)
                LabeledContent("来源表", value: record.sourceTable)
                Text("记录标识：\(record.sourceID)").font(.caption).textSelection(.enabled)
            }
            Section("待核对原因") {
                ForEach(Array(record.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue).font(.subheadline)
                }
            }
            if record.imagePath != nil {
                Section("本机保留原图") {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("历史记录保留原图")
                    } else if let imageMessage {
                        Text(imageMessage).foregroundStyle(JieziTheme.coral)
                    } else {
                        ProgressView("正在读取本机原图")
                    }
                }
            }
            Section("历史原文") {
                Text("以下内容可能包含个人信息，仅在本机查看，不会加入脱敏诊断。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("展开完整原始数据") {
                    Text(record.sourceJSON).font(.caption).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("历史记录详情")
        .task(id: record.id) {
            guard record.imagePath != nil else { return }
            do {
                let bytes = try await appState.localImageDataForHistoryUnresolvedRecord(id: record.id)
                guard let decoded = UIImage(data: bytes) else {
                    imageMessage = "本机原图已保留，但当前无法显示此图片格式。"
                    return
                }
                image = decoded
            } catch {
                imageMessage = "本机原图读取或校验失败，请保留数据并查看本机诊断；本页不会重新下载云端图片。"
            }
        }
    }
}
