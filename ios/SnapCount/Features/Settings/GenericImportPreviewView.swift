import SwiftUI

struct GenericImportPreviewView: View {
    let preview: GenericImportPreview
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        metric("总行数", "\(preview.records.count)")
                        metric("新增", "\(preview.insertableCount)")
                        metric("跳过", "\(preview.skipped)")
                    }
                    HStack(spacing: 10) {
                        metric("警告", "\(preview.warnings)")
                        metric("错误", "\(preview.errors.count)")
                    }
                    if !preview.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("需要修正的问题").font(.headline)
                            ForEach(Array(preview.errors.prefix(30).enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.localizedDescription).font(.subheadline).foregroundStyle(JieziTheme.coral)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(JieziTheme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else {
                        Label("文件可以导入", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(JieziTheme.mint)
                        Text("导入只写入本机，不绑定账户，也不会创建云端同步任务。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("导入预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入到本机", action: onImport).disabled(!preview.errors.isEmpty)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}
