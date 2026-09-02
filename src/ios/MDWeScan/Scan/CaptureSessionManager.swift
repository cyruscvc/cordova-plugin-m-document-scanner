//
//  CaptureManager.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import CoreMotion
import Foundation
import UIKit

/// A set of functions that inform the delegate object of the state of the detection.
protocol MDWRectangleDetectionDelegateProtocol: NSObjectProtocol {

    /// Called when the capture of a picture has started.
    ///
    /// - Parameters:
    ///   - captureSessionManager: The `MDWCaptureSessionManager` instance that started capturing a picture.
    func didStartCapturingPicture(for captureSessionManager: MDWCaptureSessionManager)

    /// Called when a quadrilateral has been detected.
    /// - Parameters:
    ///   - captureSessionManager: The `MDWCaptureSessionManager` instance that has detected a quadrilateral.
    ///   - quad: The detected quadrilateral in the coordinates of the image.
    ///   - imageSize: The size of the image the quadrilateral has been detected on.
    func captureSessionManager(_ captureSessionManager: MDWCaptureSessionManager, didDetectQuad quad: MDWQuadrilateral?, _ imageSize: CGSize)

    /// Called as the current quadrilateral approaches the automatic-capture threshold.
    /// Progress is reset to zero when detection is lost or the quadrilateral moves.
    func captureSessionManager(
        _ captureSessionManager: MDWCaptureSessionManager,
        didUpdateAutoScanProgress progress: CGFloat
    )

    /// Called when a picture with or without a quadrilateral has been captured.
    ///
    /// - Parameters:
    ///   - captureSessionManager: The `MDWCaptureSessionManager` instance that has captured a picture.
    ///   - picture: The picture that has been captured.
    ///   - quad: The quadrilateral that was detected in the picture's coordinates if any.
    func captureSessionManager(
        _ captureSessionManager: MDWCaptureSessionManager,
        didCapturePicture picture: UIImage,
        withQuad quad: MDWQuadrilateral?
    )

    /// Called when an error occurred with the capture session manager.
    /// - Parameters:
    ///   - captureSessionManager: The `MDWCaptureSessionManager` that encountered an error.
    ///   - error: The encountered error.
    func captureSessionManager(_ captureSessionManager: MDWCaptureSessionManager, didFailWithError error: Error)
}

/// The MDWCaptureSessionManager is responsible for setting up and managing the AVCaptureSession and the functions related to capturing.
final class MDWCaptureSessionManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let videoPreviewLayer: AVCaptureVideoPreviewLayer
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "com.mubadala.documentscanner.wescan.session"
    )
    private let rectangleFunnel = MDWRectangleFeaturesFunnel()
    weak var delegate: MDWRectangleDetectionDelegateProtocol?
    private var displayedRectangleResult: MDWRectangleDetectorResult?
    private var photoOutput = AVCapturePhotoOutput()

    /// Whether the MDWCaptureSessionManager should be detecting quadrilaterals.
    private var isDetecting = true

    /// The number of times no rectangles have been found in a row.
    private var noRectangleCount = 0

    /// The minimum number of time required by `noRectangleCount` to validate that no rectangles have been found.
    private let noRectangleThreshold = 3

    // MARK: Life Cycle

    init?(videoPreviewLayer: AVCaptureVideoPreviewLayer, delegate: MDWRectangleDetectionDelegateProtocol? = nil) {
        self.videoPreviewLayer = videoPreviewLayer

        if delegate != nil {
            self.delegate = delegate
        }

        super.init()

        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else {
            let error = MDWImageScannerControllerError.inputDevice
            delegate?.captureSessionManager(self, didFailWithError: error)
            return nil
        }

        captureSession.beginConfiguration()

        photoOutput.isHighResolutionCaptureEnabled = true
        if #available(iOS 13.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true

        defer {
            device.unlockForConfiguration()
            captureSession.commitConfiguration()
        }

        guard let deviceInput = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(deviceInput),
            captureSession.canAddOutput(photoOutput),
            captureSession.canAddOutput(videoOutput) else {
                let error = MDWImageScannerControllerError.inputDevice
                delegate?.captureSessionManager(self, didFailWithError: error)
                return
        }

        do {
            try device.lockForConfiguration()
        } catch {
            let error = MDWImageScannerControllerError.inputDevice
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        device.isSubjectAreaChangeMonitoringEnabled = true

        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)

        let photoPreset = AVCaptureSession.Preset.photo

        if captureSession.canSetSessionPreset(photoPreset) {
            captureSession.sessionPreset = photoPreset

            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
        }

        videoPreviewLayer.session = captureSession
        videoPreviewLayer.videoGravity = .resizeAspectFill

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video_ouput_queue"))
    }

    // MARK: Capture Session Life Cycle

    /// Starts the camera and detecting quadrilaterals.
    internal func start() {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            sessionQueue.async { [weak self] in
                guard let self = self, !self.captureSession.isRunning else { return }
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isDetecting = true
                }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.start()
                    } else {
                        let error = MDWImageScannerControllerError.authorization
                        self.delegate?.captureSessionManager(self, didFailWithError: error)
                    }
                }
            })
        default:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let error = MDWImageScannerControllerError.authorization
                self.delegate?.captureSessionManager(self, didFailWithError: error)
            }
        }
    }

    internal func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    internal func capturePhoto() {
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive else {
            let error = MDWImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }
        MDWCaptureSession.current.setImageOrientation()
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        if #available(iOS 13.0, *) {
            photoSettings.photoQualityPrioritization = .balanced
        }
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isDetecting == true,
            let mdwPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(mdwPixelBuffer), height: CVPixelBufferGetHeight(mdwPixelBuffer))

        if #available(iOS 11.0, *) {
            MDWVisionRectangleDetector.rectangle(forPixelBuffer: mdwPixelBuffer) { rectangle in
                self.processRectangle(rectangle: rectangle, imageSize: imageSize)
            }
        } else {
            let finalImage = CIImage(cvPixelBuffer: mdwPixelBuffer)
            MDWCIRectangleDetector.rectangle(forImage: finalImage) { rectangle in
                self.processRectangle(rectangle: rectangle, imageSize: imageSize)
            }
        }
    }

    private func processRectangle(rectangle: MDWQuadrilateral?, imageSize: CGSize) {
        if let rectangle = rectangle {

            self.noRectangleCount = 0
            self.rectangleFunnel
                .add(rectangle, currentlyDisplayedRectangle: self.displayedRectangleResult?.rectangle) { [weak self] result, rectangle, progress in

                guard let self = self else {
                    return
                }

                let shouldAutoScan = (result == .showAndAutoScan)
                let autoScanEnabled = MDWCaptureSession.current.isAutoScanEnabled
                self.displayRectangleResult(rectangleResult: MDWRectangleDetectorResult(rectangle: rectangle, imageSize: imageSize))
                if autoScanEnabled {
                    self.displayAutoScanProgress(progress)
                } else {
                    self.rectangleFunnel.resetAutoScanProgress()
                    self.displayAutoScanProgress(0.0)
                }
                if shouldAutoScan, autoScanEnabled, !MDWCaptureSession.current.isEditing {
                    capturePhoto()
                }
            }

        } else {

            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    return
                }
                self.noRectangleCount += 1

                if self.noRectangleCount > self.noRectangleThreshold {
                    // Restart stability the next time a rectangle is found.
                    self.rectangleFunnel.resetAutoScanProgress()
                    self.delegate?.captureSessionManager(
                        self,
                        didUpdateAutoScanProgress: 0.0
                    )

                    // Remove the currently displayed rectangle as no rectangles are being found anymore
                    self.displayedRectangleResult = nil
                    self.delegate?.captureSessionManager(self, didDetectQuad: nil, imageSize)
                }
            }
            return

        }
    }

    @discardableResult private func displayRectangleResult(rectangleResult: MDWRectangleDetectorResult) -> MDWQuadrilateral {
        displayedRectangleResult = rectangleResult

        let quad = rectangleResult.rectangle.toCartesian(withHeight: rectangleResult.imageSize.height)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            self.delegate?.captureSessionManager(self, didDetectQuad: quad, rectangleResult.imageSize)
        }

        return quad
    }

    private func displayAutoScanProgress(_ progress: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.delegate?.captureSessionManager(
                self,
                didUpdateAutoScanProgress: progress
            )
        }
    }

}

extension MDWCaptureSessionManager: AVCapturePhotoCaptureDelegate {

    // swiftlint:disable function_parameter_count
    func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
                     previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     bracketSettings: AVCaptureBracketedStillImageSettings?,
                     error: Error?
    ) {
        if let error = error {
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        isDetecting = false
        rectangleFunnel.resetAutoScanProgress()
        delegate?.didStartCapturingPicture(for: self)

        if let sampleBuffer = photoSampleBuffer,
            let imageData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(
                forJPEGSampleBuffer: sampleBuffer,
                previewPhotoSampleBuffer: nil
            ) {
            completeImageCapture(with: imageData)
        } else {
            let error = MDWImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

    }

    @available(iOS 11.0, *)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        isDetecting = false
        rectangleFunnel.resetAutoScanProgress()
        delegate?.didStartCapturingPicture(for: self)

        if let imageData = photo.fileDataRepresentation() {
            completeImageCapture(with: imageData)
        } else {
            let error = MDWImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }
    }

    /// Completes the image capture by processing the image, and passing it to the delegate object.
    /// This function is necessary because the capture functions for iOS 10 and 11 are decoupled.
    private func completeImageCapture(with imageData: Data) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            MDWCaptureSession.current.isEditing = true
            guard let image = UIImage.mdwDownsampledImage(data: imageData, maxDimension: 3500) else {
                let error = MDWImageScannerControllerError.capture
                DispatchQueue.main.async {
                    guard let self = self else {
                        return
                    }
                    self.delegate?.captureSessionManager(self, didFailWithError: error)
                }
                return
            }

            var angle: CGFloat = 0.0

            switch image.imageOrientation {
            case .right:
                angle = CGFloat.pi / 2
            case .up:
                angle = CGFloat.pi
            default:
                break
            }

            var quad: MDWQuadrilateral?
            if let displayedRectangleResult = self?.displayedRectangleResult {
                quad = self?.displayRectangleResult(rectangleResult: displayedRectangleResult)
                quad = quad?.scale(displayedRectangleResult.imageSize, image.size, withRotationAngle: angle)
            }

            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                self.delegate?.captureSessionManager(self, didCapturePicture: image, withQuad: quad)
            }
        }
    }
}

/// Data structure representing the result of the detection of a quadrilateral.
private struct MDWRectangleDetectorResult {

    /// The detected quadrilateral.
    let rectangle: MDWQuadrilateral

    /// The size of the image the quadrilateral was detected on.
    let imageSize: CGSize

}
