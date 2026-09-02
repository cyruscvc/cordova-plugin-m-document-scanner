//
//  UIImage+Utils.swift
//  WeScan
//
//  Created by Bobo on 5/25/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import Foundation
import ImageIO
import UIKit

extension UIImage {
    /// Draws a new cropped and scaled (zoomed in) image.
    ///
    /// - Parameters:
    ///   - point: The center of the new image.
    ///   - mdwScaleFactor: Factor by which the image should be zoomed in.
    ///   - size: The size of the rect the image will be displayed in.
    /// - Returns: The scaled and cropped image.
    func mdwScaledImage(atPoint point: CGPoint, mdwScaleFactor: CGFloat, targetSize size: CGSize) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let scaledSize = CGSize(width: size.width / mdwScaleFactor, height: size.height / mdwScaleFactor)
        let midX = point.x - scaledSize.width / 2.0
        let midY = point.y - scaledSize.height / 2.0
        let newRect = CGRect(x: midX, y: midY, width: scaledSize.width, height: scaledSize.height)

        guard let croppedImage = cgImage.cropping(to: newRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage)
    }

    /// Scales the image to the specified size in the RGB color space.
    ///
    /// - Parameters:
    ///   - mdwScaleFactor: Factor by which the image should be scaled.
    /// - Returns: The scaled image.
    func mdwScaledImage(mdwScaleFactor: CGFloat) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let customColorSpace = CGColorSpaceCreateDeviceRGB()

        let width = CGFloat(cgImage.width) * mdwScaleFactor
        let height = CGFloat(cgImage.height) * mdwScaleFactor
        let bitsPerComponent = cgImage.bitsPerComponent
        let bytesPerRow = cgImage.bytesPerRow
        let bitmapInfo = cgImage.bitmapInfo.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: customColorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))

        return context.makeImage().flatMap { UIImage(cgImage: $0) }
    }

    /// Returns the data for the image in the PDF format
    func mdwPdfData() -> Data? {
        // Typical Letter PDF page size and margins
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40

        let imageMaxWidth = pageBounds.width - (margin * 2)
        let imageMaxHeight = pageBounds.height - (margin * 2)

        let image = mdwScaledImage(mdwScaleFactor: size.mdwScaleFactor(forMaxWidth: imageMaxWidth, maxHeight: imageMaxHeight)) ?? self
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            ctx.cgContext.interpolationQuality = .high

            image.draw(at: CGPoint(x: margin, y: margin))
        }

        return data
    }

    /// Function gathered from [here](https://stackoverflow.com/questions/44462087/how-to-convert-a-uiimage-to-a-cvpixelbuffer)
    /// to convert UIImage to CVPixelBuffer
    ///
    /// - Returns: new [CVPixelBuffer](apple-reference-documentation://hsVf8OXaJX)
    func mdwPixelBuffer() -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        var pixelBufferOpt: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(self.size.width),
            Int(self.size.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBufferOpt
        )
        guard status == kCVReturnSuccess, let mdwPixelBuffer = pixelBufferOpt else {
            return nil
        }

        CVPixelBufferLockBaseAddress(mdwPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(mdwPixelBuffer)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData,
            width: Int(self.size.width),
            height: Int(self.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(mdwPixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: self.size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(mdwPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return mdwPixelBuffer
    }

    /// Creates a UIImage from the specified CIImage.
    static func mdwFrom(ciImage: CIImage) -> UIImage {
        if let cgImage = CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        } else {
            return UIImage(ciImage: ciImage, scale: 1.0, orientation: .up)
        }
    }
}


extension UIImage {
    static func mdwDownsampledImage(data: Data, maxDimension: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // Keep the JPEG's EXIF orientation instead of rotating the thumbnail pixels.
        // CaptureSessionManager maps the live video quadrilateral into the still image
        // using this orientation. Normalizing it here would rotate the quad a second time.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let imageOrientation = UIImage.Orientation(mdwExifOrientation: exifOrientation)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image, scale: 1, orientation: imageOrientation)
    }
}

private extension UIImage.Orientation {
    init(mdwExifOrientation value: UInt32) {
        switch value {
        case 2:
            self = .upMirrored
        case 3:
            self = .down
        case 4:
            self = .downMirrored
        case 5:
            self = .leftMirrored
        case 6:
            self = .right
        case 7:
            self = .rightMirrored
        case 8:
            self = .left
        default:
            self = .up
        }
    }
}


extension UIImage {
    func mdwPreparedImage(maxDimension: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let longestSide = max(pixelSize.width, pixelSize.height)
        let factor = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(
            width: max(1, floor(pixelSize.width * factor)),
            height: max(1, floor(pixelSize.height * factor))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
