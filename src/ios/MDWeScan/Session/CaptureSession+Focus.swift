//
//  MDWCaptureSession+Focus.swift
//  WeScan
//
//  Created by Julian Schiavo on 28/11/2018.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import Foundation
import UIKit

/// Extension to MDWCaptureSession that controls auto focus
extension MDWCaptureSession {
    /// Sets the camera's exposure and focus point to the given point
    func setFocusPointToTapPoint(_ tapPoint: CGPoint) throws {
        guard let device = device else {
            let error = MDWImageScannerControllerError.inputDevice
            throw error
        }

        try device.lockForConfiguration()

        defer {
            device.unlockForConfiguration()
        }

        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = tapPoint
            device.focusMode = .autoFocus
        }

        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = tapPoint
            device.exposureMode = .continuousAutoExposure
        }
    }

    /// Resets the camera's exposure and focus point to automatic
    func resetFocusToAuto() throws {
        guard let device = device else {
            let error = MDWImageScannerControllerError.inputDevice
            throw error
        }

        try device.lockForConfiguration()

        defer {
            device.unlockForConfiguration()
        }

        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    /// Removes an existing focus rectangle if one exists, optionally animating the exit
    func removeFocusRectangleIfNeeded(_ focusRectangle: MDWFocusRectangleView?, animated: Bool) {
        guard let focusRectangle = focusRectangle else { return }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 1.0, animations: {
                focusRectangle.alpha = 0.0
            }, completion: { _ in
                focusRectangle.removeFromSuperview()
            })
        } else {
            focusRectangle.removeFromSuperview()
        }
    }
}
