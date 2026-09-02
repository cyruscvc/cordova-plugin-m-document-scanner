import UIKit
import VisionKit

private struct MDScanOptions {
    let captureMode: String
    let maxPages: Int
    let allowGallery: Bool
    let wantsJPEG: Bool
    let wantsPDF: Bool
    let jpegQuality: CGFloat
    let autoCapture: Bool
    let stabilityDuration: TimeInterval
    let detectionConfidence: Float
    let minDocumentArea: CGFloat

    init(dictionary: [String: Any]) throws {
        func number(_ key: String) -> NSNumber? { dictionary[key] as? NSNumber }

        captureMode = dictionary["captureMode"] as? String ?? "single"
        guard captureMode == "single" || captureMode == "multi" else {
            throw MDPluginError.invalidOptions("captureMode must be single or multi.")
        }

        let requestedPages = number("maxPages")?.intValue ?? 1
        maxPages = captureMode == "single" ? 1 : min(50, max(1, requestedPages))
        allowGallery = dictionary["allowGallery"] as? Bool ?? false
        jpegQuality = min(1, max(0.35, CGFloat(number("jpegQuality")?.doubleValue ?? 0.9)))
        autoCapture = dictionary["autoCapture"] as? Bool ?? true
        let durationMs = number("stabilityDurationMs")?.doubleValue ?? 1200
        stabilityDuration = min(5, max(0.5, durationMs / 1000))
        detectionConfidence = min(
            1,
            max(0.5, number("detectionConfidence")?.floatValue ?? 0.8)
        )
        minDocumentArea = min(
            0.9,
            max(0.08, CGFloat(number("minDocumentArea")?.doubleValue ?? 0.2))
        )

        let rawFormats = dictionary["resultFormats"] as? [Any] ?? ["jpeg"]
        let formats = rawFormats.compactMap { $0 as? String }
        guard formats.count == rawFormats.count,
              !formats.isEmpty,
              formats.allSatisfy({ $0 == "jpeg" || $0 == "pdf" }) else {
            throw MDPluginError.invalidOptions("resultFormats may contain only jpeg and pdf.")
        }
        wantsJPEG = formats.contains("jpeg")
        wantsPDF = formats.contains("pdf")
    }
}

private enum MDPluginError: LocalizedError {
    case invalidOptions(String)
    case scannerBusy
    case unsupported
    case emptyResult

    var code: String {
        switch self {
        case .invalidOptions: return "INVALID_OPTIONS"
        case .scannerBusy: return "SCANNER_BUSY"
        case .unsupported: return "UNSUPPORTED_DEVICE"
        case .emptyResult: return "EMPTY_RESULT"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidOptions(let message): return message
        case .scannerBusy: return "Another document scan is already active."
        case .unsupported: return "Document scanning is unavailable on this device."
        case .emptyResult: return "The scanner did not return a document image."
        }
    }
}

@objc(MDocumentScanner)
final class MDocumentScanner: CDVPlugin {
    private var activeCallbackId: String?
    private var activeOptions: MDScanOptions?
    private var activeEngine = ""
    private var activeSinglePageScanner: MDWImageScannerController?

    @objc(scan:)
    func scan(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            do {
                guard self.activeCallbackId == nil else { throw MDPluginError.scannerBusy }
                let dictionary = command.argument(at: 0) as? [String: Any] ?? [:]
                let options = try MDScanOptions(dictionary: dictionary)
                self.activeCallbackId = command.callbackId
                self.activeOptions = options

                if options.captureMode == "single" {
                    self.activeEngine = "wescan"
                    MDWCaptureSession.current.isAutoScanEnabled = options.autoCapture
                    MDWCaptureSession.current.autoScanThreshold = min(
                        150,
                        max(8, Int((options.stabilityDuration * 30).rounded()))
                    )
                    MDWCaptureSession.current.detectionConfidence =
                        options.detectionConfidence
                    MDWCaptureSession.current.minDocumentArea =
                        options.minDocumentArea

                    let scanner = MDWImageScannerController(delegate: self)
                    scanner.modalPresentationStyle = .fullScreen
                    self.activeSinglePageScanner = scanner

                    scanner.loadViewIfNeeded()
                    if options.allowGallery,
                       let navigationItem = scanner.topViewController?.navigationItem {
                        let gallery = UIBarButtonItem(
                            title: "Photos",
                            style: .plain,
                            target: self,
                            action: #selector(self.openSinglePageGallery)
                        )
                        gallery.accessibilityLabel = "Choose document from photos"
                        var items = [gallery]
                        if let existing = navigationItem.rightBarButtonItem {
                            items.append(existing)
                        }
                        navigationItem.rightBarButtonItems = items
                    }

                    self.topViewController().present(scanner, animated: true)
                } else {
                    guard #available(iOS 13.0, *), VNDocumentCameraViewController.isSupported else {
                        throw MDPluginError.unsupported
                    }
                    self.activeEngine = "visionkit"
                    let scanner = VNDocumentCameraViewController()
                    scanner.delegate = self
                    scanner.modalPresentationStyle = .fullScreen
                    self.topViewController().present(scanner, animated: true)
                }
            } catch {
                self.clearState()
                self.sendError(error, callbackId: command.callbackId)
            }
        }
    }

    @objc private func openSinglePageGallery() {
        guard let scanner = activeSinglePageScanner,
              UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        scanner.present(picker, animated: true)
    }

    @objc(getCapabilities:)
    func getCapabilities(_ command: CDVInvokedUrlCommand) {
        let result: [String: Any] = [
            "available": UIImagePickerController.isSourceTypeAvailable(.camera),
            "platform": "ios",
            "singlePageEngine": "wescan",
            "multiPageEngine": "visionkit",
            "singlePageAutoStop": true,
            "multiPage": true,
            "galleryImport": true,
            "jpegOutput": true,
            "pdfOutput": true,
            "fileRead": true,
            "maxReadBytes": 52_428_800,
            "uiPageLimitEnforced": ["single": true, "multi": false],
            "minimumIosVersion": "13.0"
        ]
        sendSuccess(result, callbackId: command.callbackId)
    }

    @objc(cleanup:)
    func cleanup(_ command: CDVInvokedUrlCommand) {
        let options = command.argument(at: 0) as? [String: Any] ?? [:]
        let sessionId = options["sessionId"] as? String ?? ""
        let maxAgeHours = min(
            720,
            max(1, (options["maxAgeHours"] as? NSNumber)?.intValue ?? 24)
        )
        commandDelegate.run(inBackground: { [weak self] in
            do {
                let deleted = try MDScannerFileStore.shared.cleanup(
                    sessionId: sessionId,
                    maxAgeHours: maxAgeHours
                )
                self?.sendSuccess(["deletedSessions": deleted], callbackId: command.callbackId)
            } catch {
                self?.sendError(error, code: "CLEANUP_FAILED", callbackId: command.callbackId)
            }
        })
    }

    @objc(readFile:)
    func readFile(_ command: CDVInvokedUrlCommand) {
        let options = command.argument(at: 0) as? [String: Any] ?? [:]
        let uri = options["uri"] as? String ?? ""
        let maxBytes = min(
            52_428_800,
            max(1, (options["maxBytes"] as? NSNumber)?.intValue ?? 26_214_400)
        )

        commandDelegate.run(inBackground: { [weak self] in
            do {
                let data = try MDScannerFileStore.shared.readFile(
                    uri: uri,
                    maxBytes: maxBytes
                )
                let result = CDVPluginResult(
                    status: CDVCommandStatus_OK,
                    messageAsArrayBuffer: data
                )
                self?.commandDelegate.send(result, callbackId: command.callbackId)
            } catch {
                let code = (error as? MDScannerFileStoreError)?.code ?? "FILE_READ_FAILED"
                self?.sendError(error, code: code, callbackId: command.callbackId)
            }
        })
    }

    private func complete(images: [UIImage], uiPageLimitEnforced: Bool) {
        guard let callbackId = activeCallbackId, let options = activeOptions else { return }
        guard !images.isEmpty else {
            completeError(MDPluginError.emptyResult)
            return
        }
        let engine = activeEngine
        clearState()
        commandDelegate.run(inBackground: { [weak self] in
            do {
                let result = try MDScannerFileStore.shared.persist(
                    images: images,
                    wantsJPEG: options.wantsJPEG,
                    wantsPDF: options.wantsPDF,
                    jpegQuality: options.jpegQuality,
                    platform: "ios",
                    engine: engine,
                    uiPageLimitEnforced: uiPageLimitEnforced
                )
                self?.sendSuccess(result, callbackId: callbackId)
            } catch {
                self?.sendError(error, code: "FILE_WRITE_FAILED", callbackId: callbackId)
            }
        })
    }

    private func completeCancelled() {
        guard let callbackId = activeCallbackId else { return }
        let engine = activeEngine
        clearState()
        sendSuccess([
            "status": "cancelled",
            "platform": "ios",
            "engine": engine,
            "sessionId": NSNull(),
            "pageCount": 0,
            "pages": [],
            "pdf": NSNull(),
            "uiPageLimitEnforced": engine == "wescan"
        ], callbackId: callbackId)
    }

    private func completeError(_ error: Error, code: String = "SCAN_FAILED") {
        guard let callbackId = activeCallbackId else { return }
        clearState()
        sendError(error, code: code, callbackId: callbackId)
    }

    private func clearState() {
        activeCallbackId = nil
        activeOptions = nil
        activeEngine = ""
        activeSinglePageScanner = nil
    }

    private func topViewController() -> UIViewController {
        var controller: UIViewController = viewController!
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }

    private func sendSuccess(_ value: [String: Any], callbackId: String) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: value)
        commandDelegate.send(result, callbackId: callbackId)
    }

    private func sendError(
        _ error: Error,
        code: String? = nil,
        callbackId: String
    ) {
        let pluginError = error as? MDPluginError
        let payload: [String: Any] = [
            "code": code ?? pluginError?.code ?? "SCAN_FAILED",
            "message": error.localizedDescription,
            "nativeType": String(describing: type(of: error))
        ]
        let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: payload)
        commandDelegate.send(result, callbackId: callbackId)
    }
}

extension MDocumentScanner: MDWImageScannerControllerDelegate {
    func imageScannerController(
        _ scanner: MDWImageScannerController,
        didFinishScanningWithResults results: MDWImageScannerResults
    ) {
        let image: UIImage
        if results.doesUserPreferEnhancedScan, let enhanced = results.enhancedScan {
            image = enhanced.image
        } else {
            image = results.croppedScan.image
        }
        scanner.dismiss(animated: true) { [weak self] in
            self?.complete(images: [image], uiPageLimitEnforced: true)
        }
    }

    func imageScannerControllerDidCancel(_ scanner: MDWImageScannerController) {
        scanner.dismiss(animated: true) { [weak self] in
            self?.completeCancelled()
        }
    }

    func imageScannerController(
        _ scanner: MDWImageScannerController,
        didFailWithError error: Error
    ) {
        scanner.dismiss(animated: true) { [weak self] in
            self?.completeError(error)
        }
    }
}

extension MDocumentScanner: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard let image = info[.originalImage] as? UIImage,
              let scanner = activeSinglePageScanner else {
            picker.dismiss(animated: true)
            return
        }
        let prepared = image.mdwPreparedImage(maxDimension: 3500)
        picker.dismiss(animated: true) {
            scanner.useImage(image: prepared)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

@available(iOS 13.0, *)
extension MDocumentScanner: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        let limit = min(activeOptions?.maxPages ?? scan.pageCount, scan.pageCount)
        let images = (0..<limit).map { scan.imageOfPage(at: $0) }
        controller.dismiss(animated: true) { [weak self] in
            self?.complete(images: images, uiPageLimitEnforced: false)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.completeCancelled()
        }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true) { [weak self] in
            self?.completeError(error)
        }
    }
}
