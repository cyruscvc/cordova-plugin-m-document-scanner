# Changelog

## 1.1.0

- Replace the custom iOS single-page camera with a maintained, namespaced WeScan fork.
- Add stable multi-frame edge detection, automatic capture, manual corner editing, review, rotation, and enhancement.
- Keep Apple VisionKit for iOS multi-page scanning and Google ML Kit for Android.
- Preserve the existing Cordova and OutSystems result contract for OCR consumers.
- Downsample iOS captures to a 3500-pixel maximum dimension before editing to bound memory.
- Vendor and namespace the MIT-licensed WeScan sources to avoid runtime downloads and native type collisions.

## 1.0.5

- Keep the iOS activity indicator compatible with deployment targets below iOS 13.
- Preserve the iOS camera-session lifecycle fix introduced in 1.0.4.

## 1.0.4

- Fix an iOS runtime crash when opening the single-page scanner.
- Commit the `AVCaptureSession` configuration before calling `startRunning()`.
- Add a regression test that enforces safe camera-session lifecycle ordering.


## 1.0.3

- Fix MABS 12 iOS compilation when Cordova exposes the plugin root controller as `CDVViewController`.
- Explicitly traverse presented controllers as `UIViewController` to avoid the misleading `OS-MABS-GEN-40014` failure.
- Remove a deprecated iOS activity-indicator style warning.

## 1.0.2

- Fix the Cordova startup module reference that could leave the Android app on a blank white screen.
- Stop auto-running the options helper during application bootstrap.
- Add a Cordova module-loader regression test for the JavaScript bridge.

## 1.0.1

- Fix MABS 12 iOS generation by declaring the concrete Swift language version `5`.
- Remove the unresolved `SWIFT_VERSION` plugin variable that caused `OS-MABS-GEN-40014`.

## 1.0.0

- Add one cross-platform Cordova scanner API.
- Add strict one-document iOS capture using AVFoundation and Vision.
- Add native iOS VisionKit multi-page capture.
- Add Android ML Kit Document Scanner with configurable page limits.
- Add JPEG and PDF file-URI results, cancellation, capability checks, and cache cleanup.
- Add complete OutSystems 11/MABS 12 wrapper wiring and migration guidance.
