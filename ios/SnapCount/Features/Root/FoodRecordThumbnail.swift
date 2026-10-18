import SwiftUI

struct FoodRecordThumbnail: View {
    @EnvironmentObject private var appState: AppState
    let record: NativeDayRecord
    let detail: NativeRecordDetail?
    @State private var resolvedURL: URL?
    @State private var retryCount = 0
    @State private var loadFailed = false
    @State private var preview: PhotoPreviewRoute?

    private var hasImage: Bool { detail?.imagePath != nil || detail?.imageURL != nil }
    private var loadKey: String {
        "\(record.reference)|\(detail?.imagePath ?? "")|\(detail?.imageURL?.absoluteString ?? "")|\(retryCount)"
    }

    var body: some View {
        Group {
            if hasImage {
                Button {
                    if loadFailed { resolvedURL = nil; loadFailed = false; retryCount += 1 }
                    else if let resolvedURL { preview = PhotoPreviewRoute(url: resolvedURL) }
                    else { retryCount += 1 }
                } label: {
                    if let resolvedURL {
                        CachedRemoteImage(url: resolvedURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { ProgressView() } failure: {
                            Image(systemName: "arrow.clockwise").accessibilityLabel("照片加载失败，点此重试")
                                .onAppear { loadFailed = true }
                        }
                    } else { Image(systemName: "photo.badge.exclamationmark") }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loadFailed ? "\(record.title)，照片加载失败，重试" : "\(record.title)，查看餐食照片")
                .accessibilityHint("打开大图后可捏合或双击缩放")
                .contextMenu { Button("重新加载照片") { resolvedURL = nil; retryCount += 1 } }
            } else {
                Image(systemName: "fork.knife").accessibilityLabel("这条餐食没有照片")
            }
        }
        .foregroundStyle(JieziScene.food.accent)
        .frame(width: JieziPrototypeLayout.food_photo_size, height: JieziPrototypeLayout.food_photo_size)
        .background(JieziScene.food.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: JieziPrototypeLayout.food_photo_radius))
        .contentShape(RoundedRectangle(cornerRadius: JieziPrototypeLayout.food_photo_radius))
        .task(id: loadKey) {
            resolvedURL = nil
            loadFailed = false
            let url = await appState.thumbnailImageURL(for: record, force: retryCount > 0)
            guard !Task.isCancelled else { return }
            resolvedURL = url
        }
        .fullScreenCover(item: $preview) { route in RecordPhotoViewer(url: route.url) }
    }
}

private struct PhotoPreviewRoute: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct RecordPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    CachedRemoteImage(url: url) { image in
                        image.resizable().scaledToFit()
                            .frame(width: viewport.size.width, height: viewport.size.height)
                            .scaleEffect(scale)
                            .frame(width: viewport.size.width * scale, height: viewport.size.height * scale)
                    } placeholder: {
                        ProgressView().tint(.white).frame(width: viewport.size.width, height: viewport.size.height)
                    } failure: {
                        Label("照片暂不可读取", systemImage: "photo.badge.exclamationmark").foregroundStyle(.white)
                    }
                    .gesture(MagnifyGesture().onChanged { value in
                        scale = min(5, max(1, settledScale * value.magnification))
                    }.onEnded { _ in settledScale = scale })
                    .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 2; settledScale = scale }
                    .accessibilityLabel("餐食原图")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: scale = min(5, scale + 1)
                        case .decrement: scale = max(1, scale - 1)
                        @unknown default: break
                        }
                        settledScale = scale
                    }
                }.scrollIndicators(.hidden)
            }
            .background(.black)
            .navigationTitle("餐食照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
