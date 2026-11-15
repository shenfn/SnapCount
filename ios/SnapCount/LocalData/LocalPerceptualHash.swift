import CoreGraphics
import Foundation
import ImageIO

/// 图片感知指纹（aHash）。复刻后端 `computePerceptualHashFromDecoded`
/// （`supabase/functions/ingest-receipt/index.ts:445`）：8×8 网格中心点取亮度，
/// 与 64 点均值比较得到 64 位，再转成 16 位十六进制。
///
/// 用途是「重新截图同一笔账单」的判重。精确哈希（`LocalImageStore.sha256`）只能
/// 挡住同一份字节的重传，重新截图后字节全变；感知指纹仍能落在很小的汉明距离内。
enum LocalPerceptualHash {
    /// 与后端保持一致：不处理 EXIF orientation，直接按原始像素网格采样。
    /// 后端 `decodeImage` 走 jpeg/png 解码器，同样不看 orientation。
    ///
    /// 先缩到 128px 再采样，避免把整张截图解成 RGBA（12MP 截图约 48MB 峰值）。
    /// 8×8 网格只需要 128px 的精度，aHash 本身对缩放不敏感。
    static func compute(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return compute(from: image)
    }

    static func compute(from image: CGImage) -> String? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // byteOrder32Big 才会让内存是 RGBA；默认字节序在小端设备上会变成 BGRA，
        // 那样红蓝通道互换会改变亮度权重下的结果。
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var samples: [Double] = []
        samples.reserveCapacity(64)
        for y in 0..<8 {
            for x in 0..<8 {
                let sourceX = min(width - 1, Int((Double(x) + 0.5) * Double(width) / 8))
                let sourceY = min(height - 1, Int((Double(y) + 0.5) * Double(height) / 8))
                let index = (sourceY * width + sourceX) * 4
                let r = Double(pixels[index])
                let g = Double(pixels[index + 1])
                let b = Double(pixels[index + 2])
                samples.append(0.299 * r + 0.587 * g + 0.114 * b)
            }
        }

        let average = samples.reduce(0, +) / Double(samples.count)
        var bits = ""
        bits.reserveCapacity(64)
        for value in samples {
            bits.append(value >= average ? "1" : "0")
        }

        var hex = ""
        hex.reserveCapacity(16)
        var cursor = bits.startIndex
        while cursor < bits.endIndex {
            let next = bits.index(cursor, offsetBy: 4)
            guard let nibble = UInt8(bits[cursor..<next], radix: 2) else { return nil }
            hex += String(nibble, radix: 16)
            cursor = next
        }
        return hex
    }

    /// 与后端 `hammingDistanceHex`（`duplicate-review.ts:40`）同语义：
    /// 长度不同、非十六进制或任一为空都返回 nil，而不是猜一个距离。
    static func hammingDistance(_ a: String?, _ b: String?) -> Int? {
        guard let a, let b, !a.isEmpty, a.count == b.count,
              a.allSatisfy({ $0.isHexDigit && $0.isASCII }),
              b.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            return nil
        }
        var distance = 0
        for (left, right) in zip(a, b) {
            guard let l = Int(String(left), radix: 16),
                  let r = Int(String(right), radix: 16) else { return nil }
            distance += (l ^ r).nonzeroBitCount
        }
        return distance
    }
}
