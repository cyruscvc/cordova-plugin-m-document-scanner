//
//  MDWVisionRectangleDetector.swift
//  WeScan
//
//  Created by Julian Schiavo on 28/7/2018.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import CoreImage
import Foundation
import Vision

/// Enum encapsulating static functions to detect rectangles from an image.
@available(iOS 11.0, *)
enum MDWVisionRectangleDetector {

    private static func completeImageRequest(
        for request: VNImageRequestHandler,
        width: CGFloat,
        height: CGFloat,
        completion: @escaping ((MDWQuadrilateral?) -> Void)
    ) {
        // Create the rectangle request, and, if found, return the mdwBiggest rectangle (else return nothing).
        let rectangleDetectionRequest: VNDetectRectanglesRequest = {
            let rectDetectRequest = VNDetectRectanglesRequest(completionHandler: { request, error in
                guard error == nil,
                      let results = request.results as? [VNRectangleObservation] else {
                    completion(nil)
                    return
                }
                let accepted = results.filter {
                    $0.boundingBox.width * $0.boundingBox.height
                        >= MDWCaptureSession.current.minDocumentArea
                }
                guard !accepted.isEmpty else {
                    completion(nil)
                    return
                }

                let quads: [MDWQuadrilateral] = accepted.map(MDWQuadrilateral.init)

                // This can't fail because the earlier guard protected against an empty array, but we use guard because of SwiftLint
                guard let mdwBiggest = quads.mdwBiggest() else {
                    completion(nil)
                    return
                }

                let transform = CGAffineTransform.identity
                    .scaledBy(x: width, y: height)

                completion(mdwBiggest.applying(transform))
            })

            rectDetectRequest.minimumConfidence =
                VNConfidence(MDWCaptureSession.current.detectionConfidence)
            rectDetectRequest.maximumObservations = 8
            rectDetectRequest.minimumAspectRatio = 0.2
            rectDetectRequest.minimumSize = 0.1

            return rectDetectRequest
        }()

        // Send the requests to the request handler.
        do {
            try request.perform([rectangleDetectionRequest])
        } catch {
            completion(nil)
            return
        }

    }

    /// Detects rectangles from the given CVPixelBuffer/CVImageBuffer on iOS 11 and above.
    ///
    /// - Parameters:
    ///   - mdwPixelBuffer: The mdwPixelBuffer to detect rectangles on.
    ///   - completion: The mdwBiggest rectangle on the CVPixelBuffer
    static func rectangle(forPixelBuffer mdwPixelBuffer: CVPixelBuffer, completion: @escaping ((MDWQuadrilateral?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: mdwPixelBuffer, options: [:])
        MDWVisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler,
            width: CGFloat(CVPixelBufferGetWidth(mdwPixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(mdwPixelBuffer)),
            completion: completion)
    }

    /// Detects rectangles from the given image on iOS 11 and above.
    ///
    /// - Parameters:
    ///   - image: The image to detect rectangles on.
    /// - Returns: The mdwBiggest rectangle detected on the image.
    static func rectangle(forImage image: CIImage, completion: @escaping ((MDWQuadrilateral?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        MDWVisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler, width: image.extent.width,
            height: image.extent.height, completion: completion)
    }

    static func rectangle(
        forImage image: CIImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping ((MDWQuadrilateral?) -> Void)
    ) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        let orientedImage = image.oriented(orientation)
        MDWVisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler, width: orientedImage.extent.width,
            height: orientedImage.extent.height, completion: completion)
    }
}
