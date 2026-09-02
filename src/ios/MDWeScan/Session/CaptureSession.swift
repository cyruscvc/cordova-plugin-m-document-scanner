//
//  MDWCaptureSession.swift
//  WeScan
//
//  Created by Julian Schiavo on 23/9/2018.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import Foundation

/// A class containing global variables and settings for this capture session
final class MDWCaptureSession {

    static let current = MDWCaptureSession()

    /// The AVCaptureDevice used for the flash and focus setting
    var device: MDWCaptureDevice?

    /// Whether the user is past the scanning screen or not (needed to disable auto scan on other screens)
    var isEditing: Bool

    /// The status of auto scan. Auto scan tries to automatically scan a detected rectangle if it has a high enough accuracy.
    var isAutoScanEnabled: Bool

    /// The orientation of the captured image
    var editImageOrientation: CGImagePropertyOrientation

    /// Number of matching detections required before automatic capture.
    var autoScanThreshold: Int

    /// Vision rectangle confidence configured by the Cordova invocation.
    var detectionConfidence: Float

    /// Minimum normalized document area configured by the Cordova invocation.
    var minDocumentArea: CGFloat

    private init(
        isAutoScanEnabled: Bool = true,
        editImageOrientation: CGImagePropertyOrientation = .up,
        autoScanThreshold: Int = 36,
        detectionConfidence: Float = 0.8,
        minDocumentArea: CGFloat = 0.2
    ) {
        self.device = AVCaptureDevice.default(for: .video)

        self.isEditing = false
        self.isAutoScanEnabled = isAutoScanEnabled
        self.editImageOrientation = editImageOrientation
        self.autoScanThreshold = autoScanThreshold
        self.detectionConfidence = detectionConfidence
        self.minDocumentArea = minDocumentArea
    }

}
