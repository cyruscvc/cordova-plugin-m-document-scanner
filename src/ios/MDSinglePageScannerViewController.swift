import AVFoundation
import CoreImage
import ImageIO
import UIKit
import Vision

struct MDSinglePageScannerOptions {
    let allowGallery: Bool
    let autoCapture: Bool
    let stabilityDuration: TimeInterval
    let detectionConfidence: Float
    let minDocumentArea: CGFloat
}

protocol MDSinglePageScannerDelegate: AnyObject {
    func singlePageScanner(_ scanner: MDSinglePageScannerViewController, didFinish image: UIImage)
    func singlePageScannerDidCancel(_ scanner: MDSinglePageScannerViewController)
    func singlePageScanner(_ scanner: MDSinglePageScannerViewController, didFail error: Error)
}

enum MDSinglePageScannerError: LocalizedError {
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraConfigurationFailed
    case captureFailed
    case imageProcessingFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "No rear camera is available."
        case .cameraPermissionDenied: return "Camera access was denied."
        case .cameraConfigurationFailed: return "Unable to configure the document camera."
        case .captureFailed: return "Unable to capture the document image."
        case .imageProcessingFailed: return "Unable to process the captured document."
        }
    }
}

final class MDSinglePageScannerViewController: UIViewController {
    weak var scannerDelegate: MDSinglePageScannerDelegate?

    private let options: MDSinglePageScannerOptions
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.mubadala.documentscanner.session")
    private let analysisQueue = DispatchQueue(label: "com.mubadala.documentscanner.analysis")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()
    private let rectangleLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.fillColor = UIColor.systemGreen.withAlphaComponent(0.12).cgColor
        layer.lineWidth = 3
        layer.lineJoin = .round
        return layer
    }()
    private let shadeLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        layer.fillColor = UIColor.black.withAlphaComponent(0.35).cgColor
        return layer
    }()

    private let cancelButton = UIButton(type: .system)
    private let galleryButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .custom)
    private let torchButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let reviewImageView = UIImageView()
    private let retakeButton = UIButton(type: .system)
    private let useButton = UIButton(type: .system)
    private let activityIndicator: UIActivityIndicatorView = {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .large)
        }
        return UIActivityIndicatorView(style: .whiteLarge)
    }()

    private var cameraDevice: AVCaptureDevice?
    private var currentImage: UIImage?
    private var configured = false
    private var capturing = false
    private var lastAnalysisTime = Date.distantPast
    private var lastRectangle: VNRectangleObservation?
    private var stableSince: Date?

    init(options: MDSinglePageScannerOptions) {
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureInterface()
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        shadeLayer.frame = view.bounds
        rectangleLayer.frame = view.bounds
        updateVideoOrientation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil {
            stopSession()
            setTorch(enabled: false)
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    private func configureInterface() {
        view.layer.addSublayer(previewLayer)
        view.layer.addSublayer(shadeLayer)
        view.layer.addSublayer(rectangleLayer)

        configureTopButton(cancelButton, title: "Cancel", action: #selector(cancelTapped))
        configureTopButton(galleryButton, title: "Gallery", action: #selector(galleryTapped))
        galleryButton.isHidden = !options.allowGallery
        configureTopButton(torchButton, title: "Flash", action: #selector(torchTapped))

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = options.autoCapture ? "Position one document in the frame" : "Position document and tap capture"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 18
        statusLabel.clipsToBounds = true
        view.addSubview(statusLabel)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 36
        captureButton.layer.borderWidth = 5
        captureButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        reviewImageView.translatesAutoresizingMaskIntoConstraints = false
        reviewImageView.contentMode = .scaleAspectFit
        reviewImageView.backgroundColor = .black
        reviewImageView.isHidden = true
        view.addSubview(reviewImageView)

        configureReviewButton(retakeButton, title: "Retake", action: #selector(retakeTapped), primary: false)
        configureReviewButton(useButton, title: "Use Document", action: #selector(useTapped), primary: true)
        retakeButton.isHidden = true
        useButton.isHidden = true

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            galleryButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            galleryButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            torchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -22),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureButton.widthAnchor.constraint(equalToConstant: 72),
            captureButton.heightAnchor.constraint(equalToConstant: 72),

            reviewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reviewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reviewImageView.topAnchor.constraint(equalTo: view.topAnchor),
            reviewImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            retakeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            retakeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            retakeButton.heightAnchor.constraint(equalToConstant: 52),
            useButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            useButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            useButton.heightAnchor.constraint(equalToConstant: 52),
            useButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureTopButton(_ button: UIButton, title: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)
    }

    private func configureReviewButton(
        _ button: UIButton,
        title: String,
        action: Selector,
        primary: Bool
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.setTitleColor(primary ? .black : .white, for: .normal)
        button.backgroundColor = primary ? .white : UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    granted ? self.configureCamera() : self.fail(MDSinglePageScannerError.cameraPermissionDenied)
                }
            }
        default:
            fail(MDSinglePageScannerError.cameraPermissionDenied)
        }
    }

    private func configureCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            guard let device = discovery.devices.first else {
                DispatchQueue.main.async { self.fail(MDSinglePageScannerError.cameraUnavailable) }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input),
                      self.captureSession.canAddOutput(self.photoOutput),
                      self.captureSession.canAddOutput(self.videoOutput) else {
                    throw MDSinglePageScannerError.cameraConfigurationFailed
                }

                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .photo
                self.captureSession.addInput(input)
                self.captureSession.addOutput(self.photoOutput)

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        Int(kCVPixelFormatType_32BGRA)
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                self.captureSession.addOutput(self.videoOutput)
                self.captureSession.commitConfiguration()

                self.cameraDevice = device
                self.configured = true
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.torchButton.isHidden = !device.hasTorch
                    self.updateVideoOrientation()
                }
            } catch {
                DispatchQueue.main.async { self.fail(error) }
            }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func updateVideoOrientation() {
        previewLayer.connection?.videoOrientation = .portrait
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        photoOutput.connection(with: .video)?.videoOrientation = .portrait
    }

    @objc private func cancelTapped() {
        guard !capturing else { return }
        scannerDelegate?.singlePageScannerDidCancel(self)
    }

    @objc private func galleryTapped() {
        guard !capturing else { return }
        stopSession()
        setTorch(enabled: false)
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    @objc private func captureTapped() {
        captureDocument()
    }

    @objc private func torchTapped() {
        guard let device = cameraDevice else { return }
        setTorch(enabled: device.torchMode != .on)
    }

    @objc private func retakeTapped() {
        currentImage = nil
        reviewImageView.image = nil
        reviewImageView.isHidden = true
        retakeButton.isHidden = true
        useButton.isHidden = true
        cancelButton.isHidden = false
        galleryButton.isHidden = !options.allowGallery
        torchButton.isHidden = !(cameraDevice?.hasTorch ?? false)
        captureButton.isHidden = false
        captureButton.isEnabled = true
        statusLabel.isHidden = false
        capturing = false
        stableSince = nil
        lastRectangle = nil
        drawRectangle(nil)
        sessionQueue.async { [weak self] in self?.captureSession.startRunning() }
    }

    @objc private func useTapped() {
        guard let image = currentImage else { return }
        scannerDelegate?.singlePageScanner(self, didFinish: image)
    }

    private func setTorch(enabled: Bool) {
        guard let device = cameraDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.torchButton.setTitle(enabled ? "Flash On" : "Flash", for: .normal)
            }
        } catch {
            // Torch is optional; scanning remains usable if configuration fails.
        }
    }

    private func captureDocument() {
        guard configured, !capturing else { return }
        capturing = true
        activityIndicator.startAnimating()
        statusLabel.text = "Capturing…"
        captureButton.isEnabled = false

        let settings = AVCapturePhotoSettings()
        if #available(iOS 13.0, *) {
            settings.photoQualityPrioritization = .quality
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func processCapturedImage(_ image: UIImage) {
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            let normalized = image.md_normalizedOrientation()
            let corrected = self.perspectiveCorrectedImage(normalized) ?? normalized
            DispatchQueue.main.async {
                self.showReview(image: corrected)
            }
        }
    }

    private func showReview(image: UIImage) {
        stopSession()
        setTorch(enabled: false)
        currentImage = image
        reviewImageView.image = image
        reviewImageView.isHidden = false
        reviewImageView.alpha = 0
        retakeButton.isHidden = false
        useButton.isHidden = false
        cancelButton.isHidden = true
        galleryButton.isHidden = true
        torchButton.isHidden = true
        captureButton.isHidden = true
        statusLabel.isHidden = true
        activityIndicator.stopAnimating()
        UIView.animate(withDuration: 0.2) { self.reviewImageView.alpha = 1 }
    }

    private func perspectiveCorrectedImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = options.detectionConfidence
        request.minimumAspectRatio = 0.2
        request.quadratureTolerance = 35

        do {
            try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
            guard let rectangle = request.results?.first,
                  rectangle.boundingBox.width * rectangle.boundingBox.height >= options.minDocumentArea else {
                return image
            }

            let input = CIImage(cgImage: cgImage)
            let extent = input.extent
            let point: (CGPoint) -> CIVector = { normalized in
                CIVector(
                    x: extent.origin.x + normalized.x * extent.width,
                    y: extent.origin.y + normalized.y * extent.height
                )
            }
            guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return image }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(point(rectangle.topLeft), forKey: "inputTopLeft")
            filter.setValue(point(rectangle.topRight), forKey: "inputTopRight")
            filter.setValue(point(rectangle.bottomLeft), forKey: "inputBottomLeft")
            filter.setValue(point(rectangle.bottomRight), forKey: "inputBottomRight")
            guard let output = filter.outputImage,
                  let corrected = ciContext.createCGImage(output, from: output.extent) else {
                return image
            }
            return UIImage(cgImage: corrected, scale: image.scale, orientation: .up)
        } catch {
            return image
        }
    }

    private func handleRectangle(_ rectangle: VNRectangleObservation?) {
        DispatchQueue.main.async {
            guard !self.capturing, self.currentImage == nil else { return }
            self.drawRectangle(rectangle)
            guard let rectangle = rectangle else {
                self.stableSince = nil
                self.lastRectangle = nil
                self.statusLabel.text = "Position one document in the frame"
                return
            }

            let isStable = self.lastRectangle.map {
                self.rectangleDistance($0, rectangle) < 0.055
            } ?? false
            if isStable {
                if self.stableSince == nil { self.stableSince = Date() }
            } else {
                self.stableSince = Date()
            }
            self.lastRectangle = rectangle

            if self.options.autoCapture {
                let elapsed = Date().timeIntervalSince(self.stableSince ?? Date())
                self.statusLabel.text = elapsed >= self.options.stabilityDuration * 0.55
                    ? "Hold steady…"
                    : "Document detected"
                if elapsed >= self.options.stabilityDuration {
                    self.captureDocument()
                }
            } else {
                self.statusLabel.text = "Document detected — tap capture"
            }
        }
    }

    private func rectangleDistance(
        _ first: VNRectangleObservation,
        _ second: VNRectangleObservation
    ) -> CGFloat {
        let firstPoints = [first.topLeft, first.topRight, first.bottomLeft, first.bottomRight]
        let secondPoints = [second.topLeft, second.topRight, second.bottomLeft, second.bottomRight]
        return zip(firstPoints, secondPoints).reduce(0) { total, pair in
            total + hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y)
        } / 4
    }

    private func drawRectangle(_ observation: VNRectangleObservation?) {
        guard let observation = observation else {
            rectangleLayer.path = nil
            shadeLayer.path = UIBezierPath(rect: view.bounds).cgPath
            return
        }
        func converted(_ point: CGPoint) -> CGPoint {
            previewLayer.layerPointConverted(
                fromCaptureDevicePoint: CGPoint(x: point.x, y: 1 - point.y)
            )
        }
        let path = UIBezierPath()
        path.move(to: converted(observation.topLeft))
        path.addLine(to: converted(observation.topRight))
        path.addLine(to: converted(observation.bottomRight))
        path.addLine(to: converted(observation.bottomLeft))
        path.close()
        rectangleLayer.path = path.cgPath

        let shade = UIBezierPath(rect: view.bounds)
        shade.append(path)
        shade.usesEvenOddFillRule = true
        shadeLayer.path = shade.cgPath
    }

    private func fail(_ error: Error) {
        activityIndicator.stopAnimating()
        scannerDelegate?.singlePageScanner(self, didFail: error)
    }
}

extension MDSinglePageScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !capturing, currentImage == nil,
              Date().timeIntervalSince(lastAnalysisTime) >= 0.25,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysisTime = Date()

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = options.detectionConfidence
        request.minimumAspectRatio = 0.2
        request.quadratureTolerance = 35
        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            ).perform([request])
            let rectangle = request.results?.first
            let accepted = rectangle.flatMap {
                $0.boundingBox.width * $0.boundingBox.height >= options.minDocumentArea ? $0 : nil
            }
            handleRectangle(accepted)
        } catch {
            handleRectangle(nil)
        }
    }
}

extension MDSinglePageScannerViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            capturing = false
            captureButton.isEnabled = true
            fail(error)
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            capturing = false
            captureButton.isEnabled = true
            fail(MDSinglePageScannerError.captureFailed)
            return
        }
        processCapturedImage(image)
    }
}

extension MDSinglePageScannerViewController:
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else {
            fail(MDSinglePageScannerError.imageProcessingFailed)
            return
        }
        capturing = true
        activityIndicator.startAnimating()
        processCapturedImage(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            self?.sessionQueue.async { [weak self] in self?.captureSession.startRunning() }
        }
    }
}

private extension UIImage {
    func md_normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
