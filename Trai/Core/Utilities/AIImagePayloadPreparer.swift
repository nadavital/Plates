//
//  AIImagePayloadPreparer.swift
//  Trai
//
//  Normalizes AI-bound images to a predictable JPEG budget before upload.
//

import UIKit

enum AIImagePayloadPreparer {
    static let defaultMaxBytes = 1_800_000
    static let defaultMaxPixelDimension: CGFloat = 1_600

    private static let compressionQualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.32]
    private static let downscaleFactors: [CGFloat] = [1.0, 0.85, 0.72, 0.6, 0.5]

    static func prepareJPEGData(
        from imageData: Data?,
        maxBytes: Int = defaultMaxBytes,
        maxPixelDimension: CGFloat = defaultMaxPixelDimension
    ) -> Data? {
        guard let imageData else { return nil }
        guard let image = UIImage(data: imageData) else { return imageData }
        return prepareJPEGData(
            from: image,
            maxBytes: maxBytes,
            maxPixelDimension: maxPixelDimension
        )
    }

    static func prepareJPEGData(
        from image: UIImage?,
        maxBytes: Int = defaultMaxBytes,
        maxPixelDimension: CGFloat = defaultMaxPixelDimension
    ) -> Data? {
        guard let image else { return nil }

        let resizedBaseImage = resizedImageIfNeeded(image, maxPixelDimension: maxPixelDimension)
        var smallestData: Data?

        for factor in downscaleFactors {
            let candidateImage: UIImage
            if factor == 1.0 {
                candidateImage = resizedBaseImage
            } else {
                candidateImage = scaledImage(resizedBaseImage, factor: factor)
            }

            for quality in compressionQualities {
                guard let data = candidateImage.jpegData(compressionQuality: quality) else { continue }

                if smallestData == nil || data.count < smallestData?.count ?? .max {
                    smallestData = data
                }

                if data.count <= maxBytes {
                    return data
                }
            }
        }

        return smallestData
    }

    private static func resizedImageIfNeeded(_ image: UIImage, maxPixelDimension: CGFloat) -> UIImage {
        let currentMaxDimension = max(image.size.width, image.size.height)
        guard currentMaxDimension > maxPixelDimension else {
            return image
        }

        let scale = maxPixelDimension / currentMaxDimension
        return scaledImage(image, factor: scale)
    }

    private static func scaledImage(_ image: UIImage, factor: CGFloat) -> UIImage {
        guard factor > 0, factor != 1 else { return image }

        let targetSize = CGSize(
            width: max(1, floor(image.size.width * factor)),
            height: max(1, floor(image.size.height * factor))
        )

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
