import Foundation
import UIKit

/// 添付画像の縮小・JPEG化。保管庫の肥大化を防ぐため長辺を制限する。
enum ImageProcessing {
    static func makeJPEG(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = downscale(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longSide = max(w, h)
        guard longSide > maxDimension else { return image }
        let scale = maxDimension / longSide
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
