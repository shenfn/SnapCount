import SwiftUI
import UIKit
import CryptoKit

actor RemoteImageRepository {
    static let shared = RemoteImageRepository()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private let diskDirectory: URL
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    init() {
        let cache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "jiezi-images"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        diskDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jiezi-image-data", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: diskDirectory,
            withIntermediateDirectories: true
        )
        memoryCache.countLimit = 40
        memoryCache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) async throws -> UIImage {
        if let image = memoryCache.object(forKey: url as NSURL) {
            return image
        }
        let diskURL = cachedFileURL(for: url)
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
            return image
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<UIImage, Error> {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            try? data.write(to: diskURL, options: .atomic)
            memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
            return image
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    func prefetch(_ urls: [URL]) async {
        for url in Array(Set(urls)) {
            _ = try? await image(for: url)
        }
    }

    func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        memoryCache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func cachedFileURL(for url: URL) -> URL {
        let stableKey = url.host.map { "\($0)\(url.path)" } ?? url.path
        let digest = SHA256.hash(data: Data(stableKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskDirectory.appendingPathComponent(digest)
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var uiImage: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else if didFail {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            uiImage = nil
            didFail = false
            do {
                uiImage = try await RemoteImageRepository.shared.image(for: url)
            } catch {
                didFail = true
            }
        }
    }
}
