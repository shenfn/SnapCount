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
    static func cameraJPEGData(from image: UIImage) throws -> Data {
        let primary = try jpegData(
            from: image,
            maxDimension: 960,
            compressionQuality: 0.62
        )
        guard primary.count > 900_000 else { return primary }
        return try jpegData(
            from: image,
            maxDimension: 768,
            compressionQuality: 0.52
        )
    }

    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = 1440,
        compressionQuality: CGFloat = 0.78
    ) throws -> Data {
        let normalized = image.normalizedForUpload(maxDimension: maxDimension)
        guard let data = normalized.jpegData(compressionQuality: compressionQuality) else {
            throw ImageUploadPreprocessorError.compressionFailed
        }
        return data
    }

    static func jpegData(
        from data: Data,
        maxDimension: CGFloat = 1440,
        compressionQuality: CGFloat = 0.78
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
        let sourceSize = CGSize(
            width: oriented.size.width * oriented.scale,
            height: oriented.size.height * oriented.scale
        )
        let longest = max(sourceSize.width, sourceSize.height)
        let targetSize: CGSize
        if longest > maxDimension {
            let resizeRatio = maxDimension / longest
            targetSize = CGSize(
                width: sourceSize.width * resizeRatio,
                height: sourceSize.height * resizeRatio
            )
        } else {
            targetSize = sourceSize
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}
