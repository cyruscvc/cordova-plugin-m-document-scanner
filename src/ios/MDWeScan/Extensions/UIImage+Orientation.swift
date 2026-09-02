//
//  UIImage+Orientation.swift
//  WeScan
//
//  Created by Boris Emorine on 2/16/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import Foundation
import UIKit

extension UIImage {

    /// Data structure to easily express rotation options.
    struct MDWRotationOptions: OptionSet {
        let rawValue: Int

        static let flipOnVerticalAxis = MDWRotationOptions(rawValue: 1)
        static let flipOnHorizontalAxis = MDWRotationOptions(rawValue: 2)
    }

    /// Returns the same image with a portrait orientation.
    func mdwApplyingPortraitOrientation() -> UIImage {
        switch imageOrientation {
        case .up:
            return mdwRotated(by: Measurement(value: Double.pi, unit: .radians), options: []) ?? self
        case .down:
            return mdwRotated(by: Measurement(value: Double.pi, unit: .radians), options: [.flipOnVerticalAxis, .flipOnHorizontalAxis]) ?? self
        case .left:
            return self
        case .right:
            return mdwRotated(by: Measurement(value: Double.pi / 2.0, unit: .radians), options: []) ?? self
        default:
            return self
        }
    }

    /// Rotate the image by the given angle, and perform other transformations based on the passed in options.
    ///
    /// - Parameters:
    ///   - rotationAngle: The angle to rotate the image by.
    ///   - options: Options to apply to the image.
    /// - Returns: The new image mdwRotated and optionally flipped (@see options).
    func mdwRotated(by rotationAngle: Measurement<UnitAngle>, options: MDWRotationOptions = []) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let rotationInRadians = CGFloat(rotationAngle.converted(to: .radians).value)
        let transform = CGAffineTransform(rotationAngle: rotationInRadians)
        let cgImageSize = CGSize(width: cgImage.width, height: cgImage.height)
        var rect = CGRect(origin: .zero, size: cgImageSize).applying(transform)
        rect.origin = .zero

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)

        let image = renderer.image { renderContext in
            renderContext.cgContext.translateBy(x: rect.midX, y: rect.midY)
            renderContext.cgContext.rotate(by: rotationInRadians)

            let x = options.contains(.flipOnVerticalAxis) ? -1.0 : 1.0
            let y = options.contains(.flipOnHorizontalAxis) ? 1.0 : -1.0
            renderContext.cgContext.scaleBy(x: CGFloat(x), y: CGFloat(y))

            let drawRect = CGRect(origin: CGPoint(x: -cgImageSize.width / 2.0, y: -cgImageSize.height / 2.0), size: cgImageSize)
            renderContext.cgContext.draw(cgImage, in: drawRect)
        }

        return image
    }

    /// Rotates the image based on the information collected by the accelerometer
    func mdwWithFixedOrientation() -> UIImage {
        var imageAngle: Double = 0.0

        var shouldRotate = true
        switch MDWCaptureSession.current.editImageOrientation {
        case .up:
            shouldRotate = false
        case .left:
            imageAngle = Double.pi / 2
        case .right:
            imageAngle = -(Double.pi / 2)
        case .down:
            imageAngle = Double.pi
        default:
            shouldRotate = false
        }

        if shouldRotate,
            let finalImage = mdwRotated(by: Measurement(value: imageAngle, unit: .radians)) {
            return finalImage
        } else {
            return self
        }
    }

}
