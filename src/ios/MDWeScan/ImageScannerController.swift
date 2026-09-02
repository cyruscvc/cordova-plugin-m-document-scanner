//
//  MDWImageScannerController.swift
//  WeScan
//
//  Created by Boris Emorine on 2/12/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import UIKit

/// A set of methods that your delegate object must implement to interact with the image scanner interface.
public protocol MDWImageScannerControllerDelegate: NSObjectProtocol {

    /// Tells the delegate that the user scanned a document.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    ///   - results: The results of the user scanning with the camera.
    /// - Discussion: Your delegate's implementation of this method should dismiss the image scanner controller.
    func imageScannerController(_ scanner: MDWImageScannerController, didFinishScanningWithResults results: MDWImageScannerResults)

    /// Tells the delegate that the user cancelled the scan operation.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    /// - Discussion: Your delegate's implementation of this method should dismiss the image scanner controller.
    func imageScannerControllerDidCancel(_ scanner: MDWImageScannerController)

    /// Tells the delegate that an error occurred during the user's scanning experience.
    ///
    /// - Parameters:
    ///   - scanner: The scanner controller object managing the scanning interface.
    ///   - error: The error that occurred.
    func imageScannerController(_ scanner: MDWImageScannerController, didFailWithError error: Error)
}

/// A view controller that manages the full flow for scanning documents.
/// The `MDWImageScannerController` class is meant to be presented. It consists of a series of 3 different screens which guide the user:
/// 1. Uses the camera to capture an image with a rectangle that has been detected.
/// 2. Edit the detected rectangle.
/// 3. Review the cropped down version of the rectangle.
public final class MDWImageScannerController: UINavigationController {

    /// The object that acts as the delegate of the `MDWImageScannerController`.
    public weak var imageScannerDelegate: MDWImageScannerControllerDelegate?

    // MARK: - Life Cycle

    /// A black UIView, used to quickly display a black screen when the shutter button is presseed.
    internal let blackFlashView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public required init(image: UIImage? = nil, delegate: MDWImageScannerControllerDelegate? = nil) {
        super.init(rootViewController: MDWScannerViewController())

        self.imageScannerDelegate = delegate

        // The scanner navigation bar is always black. Semantic `.label` becomes
        // black in light mode and makes actionable bar buttons invisible.
        navigationBar.tintColor = .white
        navigationBar.isTranslucent = false
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        } else {
            navigationBar.barTintColor = .black
        }
        self.view.addSubview(blackFlashView)
        setupConstraints()

        // If an image was passed in by the host app (e.g. picked from the photo library), use it instead of the document scanner.
        if let image = image {
            detect(image: image) { [weak self] detectedQuad in
                guard let self = self else { return }
                let editViewController = MDWEditScanViewController(image: image, quad: detectedQuad, rotateImage: false)
                self.setViewControllers([editViewController], animated: false)
            }
        }
    }

    override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func detect(image: UIImage, completion: @escaping (MDWQuadrilateral?) -> Void) {
        // Whether or not we detect a quad, present the edit view controller after attempting to detect a quad.
        // *** Vision *requires* a completion block to detect rectangles, but it's instant.
        // *** When using Vision, we'll present the normal edit view controller first, then present the updated edit view controller later.

        guard let ciImage = CIImage(image: image) else { return }
        let orientation = CGImagePropertyOrientation(mdwUIOrientation: image.imageOrientation)
        let orientedImage = ciImage.oriented(forExifOrientation: Int32(orientation.rawValue))

        if #available(iOS 11.0, *) {
            // Use the MDWVisionRectangleDetector on iOS 11 to attempt to find a rectangle from the initial image.
            MDWVisionRectangleDetector.rectangle(forImage: ciImage, orientation: orientation) { quad in
                let detectedQuad = quad?.toCartesian(withHeight: orientedImage.extent.height)
                completion(detectedQuad)
            }
        } else {
            // Use the MDWCIRectangleDetector on iOS 10 to attempt to find a rectangle from the initial image.
            let detectedQuad = MDWCIRectangleDetector.rectangle(forImage: ciImage)?.toCartesian(withHeight: orientedImage.extent.height)
            completion(detectedQuad)
        }
    }

    public func useImage(image: UIImage) {
        guard topViewController is MDWScannerViewController else { return }

        detect(image: image) { [weak self] detectedQuad in
            guard let self = self else { return }
            let editViewController = MDWEditScanViewController(image: image, quad: detectedQuad, rotateImage: false)
            self.setViewControllers([editViewController], animated: true)
        }
    }

    public func resetScanner() {
        setViewControllers([MDWScannerViewController()], animated: true)
    }

    private func setupConstraints() {
        let blackFlashViewConstraints = [
            blackFlashView.topAnchor.constraint(equalTo: view.topAnchor),
            blackFlashView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.bottomAnchor.constraint(equalTo: blackFlashView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: blackFlashView.trailingAnchor)
        ]

        NSLayoutConstraint.activate(blackFlashViewConstraints)
    }

    internal func flashToBlack() {
        view.bringSubviewToFront(blackFlashView)
        blackFlashView.isHidden = false
        let flashDuration = DispatchTime.now() + 0.05
        DispatchQueue.main.asyncAfter(deadline: flashDuration) {
            self.blackFlashView.isHidden = true
        }
    }
}

/// Data structure containing information about a scan, including both the image and an optional PDF.
public struct MDWImageScannerScan {
    public enum ImageScannerError: Error {
        case failedToGeneratePDF
    }

    public var image: UIImage

    public func generatePDFData(completion: @escaping (Result<Data, ImageScannerError>) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            if let mdwPdfData = self.image.mdwPdfData() {
                completion(.success(mdwPdfData))
            } else {
                completion(.failure(.failedToGeneratePDF))
            }
        }

    }

    mutating func rotate(by rotationAngle: Measurement<UnitAngle>) {
        guard rotationAngle.value != 0, rotationAngle.value != 360 else { return }
        image = image.mdwRotated(by: rotationAngle) ?? image
    }
}

/// Data structure containing information about a scanning session.
/// Includes the original scan, cropped scan, detected rectangle, and whether the user selected the enhanced scan.
/// May also include an enhanced scan if no errors were encountered.
public struct MDWImageScannerResults {

    /// The original scan taken by the user, prior to the cropping applied by WeScan.
    public var originalScan: MDWImageScannerScan

    /// The deskewed and cropped scan using the detected rectangle, without any filters.
    public var croppedScan: MDWImageScannerScan

    /// The enhanced scan, passed through an Adaptive Thresholding function.
    /// This image will always be grayscale and may not always be available.
    public var enhancedScan: MDWImageScannerScan?

    /// Whether the user selected the enhanced scan or not.
    /// The `enhancedScan` may still be available even if it has not been selected by the user.
    public var doesUserPreferEnhancedScan: Bool

    /// The detected rectangle which was used to generate the `scannedImage`.
    public var detectedRectangle: MDWQuadrilateral

    init(
        detectedRectangle: MDWQuadrilateral,
        originalScan: MDWImageScannerScan,
        croppedScan: MDWImageScannerScan,
        enhancedScan: MDWImageScannerScan?,
        doesUserPreferEnhancedScan: Bool = false
    ) {
        self.detectedRectangle = detectedRectangle

        self.originalScan = originalScan
        self.croppedScan = croppedScan
        self.enhancedScan = enhancedScan

        self.doesUserPreferEnhancedScan = doesUserPreferEnhancedScan
    }
}
