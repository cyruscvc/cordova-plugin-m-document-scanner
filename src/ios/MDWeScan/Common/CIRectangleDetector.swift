//
//  RectangleDetector.swift
//  WeScan
//
//  Created by Boris Emorine on 2/13/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import CoreImage
import Foundation

/// Class used to detect rectangles from an image.
enum MDWCIRectangleDetector {

    static let rectangleDetector = CIDetector(ofType: CIDetectorTypeRectangle,
                                              context: CIContext(options: nil),
                                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

    /// Detects rectangles from the given image on iOS 10.
    ///
    /// - Parameters:
    ///   - image: The image to detect rectangles on.
    /// - Returns: The mdwBiggest detected rectangle on the image.
    static func rectangle(forImage image: CIImage, completion: @escaping ((MDWQuadrilateral?) -> Void)) {
        let biggestRectangle = rectangle(forImage: image)
        completion(biggestRectangle)
    }

    static func rectangle(forImage image: CIImage) -> MDWQuadrilateral? {
        guard let rectangleFeatures = rectangleDetector?.features(in: image) as? [CIRectangleFeature] else {
            return nil
        }

        let quads = rectangleFeatures.map { rectangle in
            return MDWQuadrilateral(rectangleFeature: rectangle)
        }

        return quads.mdwBiggest()
    }
}
