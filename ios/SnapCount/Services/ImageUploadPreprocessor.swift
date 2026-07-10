import Foundation
import UIKit

enum ImageUploadPreprocessorError: LocalizedError {
    case unreadableImage
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "没有读取到有效图片。"
        case .compressionFailed:
            return "图片压缩失败。"
        }
    }
}

enum ImageUploadPreprocessor {
    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = 1800,
        compressionQuality: CGFloat = 0.82
    ) throws -> Data {
        let normalized = image.normalizedForUpload(maxDimension: maxDimension)
        guard let data = normalized.jpegData(compressionQuality: compressionQuality) else {
            throw ImageUploadPreprocessorError.compressionFailed
        }
        return data
    }

    static func jpegData(
        from data: Data,
        maxDimension: CGFloat = 1800,
        compressionQuality: CGFloat = 0.82
    ) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImageUploadPreprocessorError.unreadableImage
        }
        return try jpegData(
            from: image,
            maxDimension: maxDimension,
            compressionQuality: compressionQuality
        )
    }
}

private extension UIImage {
    func normalizedForUpload(maxDimension: CGFloat) -> UIImage {
        let oriented = fixedOrientation()
        let longest = max(oriented.size.width, oriented.size.height)
        guard longest > maxDimension else { return oriented }

        let scale = maxDimension / longest
        let targetSize = CGSize(width: oriented.size.width * scale, height: oriented.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
