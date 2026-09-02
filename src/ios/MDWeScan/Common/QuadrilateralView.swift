//
//  RectangleView.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import Foundation
import UIKit

/// Simple enum to keep track of the position of the corners of a quadrilateral.
enum MDWCornerPosition {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

/// The `MDWQuadrilateralView` is a simple `UIView` subclass that can draw a quadrilateral, and optionally edit it.
final class MDWQuadrilateralView: UIView {

    /// Mubadala teal used by the live document-detection overlay (#7AC4BD).
    private static let scannerAccentColor = UIColor(
        red: 122.0 / 255.0,
        green: 196.0 / 255.0,
        blue: 189.0 / 255.0,
        alpha: 1.0
    )

    private let quadLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.white.cgColor
        layer.lineWidth = 1.0
        layer.opacity = 1.0
        layer.isHidden = true

        return layer
    }()

    /// A lightweight 3x3 perspective grid that reveals as auto-capture confidence grows.
    private let stabilityGridLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.0
        layer.lineCap = .round
        layer.opacity = 0.0
        layer.strokeEnd = 0.0
        layer.isHidden = true
        return layer
    }()

    private var scannerOverlayColor: UIColor?

    /// We want the corner views to be displayed under the outline of the quadrilateral.
    /// Because of that, we need the quadrilateral to be drawn on a UIView above them.
    private let quadView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// The quadrilateral drawn on the view.
    private(set) var quad: MDWQuadrilateral?

    public var editable = false {
        didSet {
            cornerViews(hidden: !editable)
            updateFillColor()
            guard let quad = quad else {
                return
            }
            drawQuad(quad, animated: false)
            layoutCornerViews(forQuad: quad)
        }
    }

    /// Set stroke color of image rect and corner.
    public var strokeColor: CGColor? {
        didSet {
            quadLayer.strokeColor = strokeColor
            topLeftCornerView.strokeColor = strokeColor
            topRightCornerView.strokeColor = strokeColor
            bottomRightCornerView.strokeColor = strokeColor
            bottomLeftCornerView.strokeColor = strokeColor
        }
    }

    private var isHighlighted = false {
        didSet (oldValue) {
            guard oldValue != isHighlighted else {
                return
            }
            quadLayer.fillColor = isHighlighted ? UIColor.clear.cgColor : UIColor(white: 0.0, alpha: 0.6).cgColor
            if isHighlighted {
                bringSubviewToFront(quadView)
            } else {
                sendSubviewToBack(quadView)
            }
        }
    }

    private lazy var topLeftCornerView: MDWEditScanCornerView = {
        return MDWEditScanCornerView(frame: CGRect(origin: .zero, size: cornerViewSize), position: .topLeft)
    }()

    private lazy var topRightCornerView: MDWEditScanCornerView = {
        return MDWEditScanCornerView(frame: CGRect(origin: .zero, size: cornerViewSize), position: .topRight)
    }()

    private lazy var bottomRightCornerView: MDWEditScanCornerView = {
        return MDWEditScanCornerView(frame: CGRect(origin: .zero, size: cornerViewSize), position: .bottomRight)
    }()

    private lazy var bottomLeftCornerView: MDWEditScanCornerView = {
        return MDWEditScanCornerView(frame: CGRect(origin: .zero, size: cornerViewSize), position: .bottomLeft)
    }()

    private let highlightedCornerViewSize = CGSize(width: 75.0, height: 75.0)
    private let cornerViewSize = CGSize(width: 20.0, height: 20.0)

    // MARK: - Life Cycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        addSubview(quadView)
        setupCornerViews()
        setupConstraints()
        quadView.layer.addSublayer(quadLayer)
        quadView.layer.addSublayer(stabilityGridLayer)
    }

    private func setupConstraints() {
        let quadViewConstraints = [
            quadView.topAnchor.constraint(equalTo: topAnchor),
            quadView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomAnchor.constraint(equalTo: quadView.bottomAnchor),
            trailingAnchor.constraint(equalTo: quadView.trailingAnchor)
        ]

        NSLayoutConstraint.activate(quadViewConstraints)
    }

    private func setupCornerViews() {
        addSubview(topLeftCornerView)
        addSubview(topRightCornerView)
        addSubview(bottomRightCornerView)
        addSubview(bottomLeftCornerView)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        guard quadLayer.frame != bounds || stabilityGridLayer.frame != bounds else {
            return
        }

        quadLayer.frame = bounds
        stabilityGridLayer.frame = bounds
        if let quad = quad {
            drawQuadrilateral(quad: quad, animated: false)
        }
    }

    // MARK: - Drawings

    /// Draws the passed in quadrilateral.
    ///
    /// - Parameters:
    ///   - quad: The quadrilateral to draw on the view. It should be in the coordinates of the current `MDWQuadrilateralView` instance.
    func drawQuadrilateral(quad: MDWQuadrilateral, animated: Bool) {
        self.quad = quad
        drawQuad(quad, animated: animated)
        stabilityGridLayer.path = stabilityGridPath(for: quad).cgPath
        if editable {
            cornerViews(hidden: false)
            layoutCornerViews(forQuad: quad)
        }
    }

    private func drawQuad(_ quad: MDWQuadrilateral, animated: Bool) {
        var path = quad.path

        if editable {
            path = path.reversing()
            let rectPath = UIBezierPath(rect: bounds)
            path.append(rectPath)
        }

        if animated == true {
            let pathAnimation = CABasicAnimation(keyPath: "path")
            pathAnimation.duration = 0.2
            quadLayer.add(pathAnimation, forKey: "path")
        }

        quadLayer.path = path.cgPath
        quadLayer.isHidden = false
    }

    /// Applies the branded appearance used only by the live camera overlay.
    func configureForDocumentScanning() {
        let color = Self.scannerAccentColor
        scannerOverlayColor = color
        strokeColor = color.cgColor
        quadLayer.lineWidth = 2.0
        stabilityGridLayer.strokeColor = color.withAlphaComponent(0.9).cgColor
        updateFillColor()
    }

    /// Reveals the perspective grid in step with the actual auto-capture stability counter.
    func updateAutoScanProgress(_ progress: CGFloat, animated: Bool) {
        let clampedProgress = min(1.0, max(0.0, progress))
        guard !editable, quad != nil, clampedProgress > 0 else {
            stabilityGridLayer.removeAllAnimations()
            stabilityGridLayer.strokeEnd = 0.0
            stabilityGridLayer.opacity = 0.0
            stabilityGridLayer.isHidden = true
            return
        }

        let previousProgress = stabilityGridLayer.presentation()?.strokeEnd
            ?? stabilityGridLayer.strokeEnd
        stabilityGridLayer.isHidden = false
        stabilityGridLayer.opacity = 1.0
        stabilityGridLayer.strokeEnd = clampedProgress

        guard animated else {
            stabilityGridLayer.removeAnimation(forKey: "strokeEnd")
            return
        }

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = previousProgress
        animation.toValue = clampedProgress
        animation.duration = 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        stabilityGridLayer.add(animation, forKey: "strokeEnd")
    }

    private func updateFillColor() {
        if editable {
            quadLayer.fillColor = UIColor(white: 0.0, alpha: 0.6).cgColor
        } else if let color = scannerOverlayColor {
            quadLayer.fillColor = color.withAlphaComponent(0.14).cgColor
        } else {
            quadLayer.fillColor = UIColor(white: 1.0, alpha: 0.5).cgColor
        }
    }

    private func stabilityGridPath(for quad: MDWQuadrilateral) -> UIBezierPath {
        let path = UIBezierPath()
        let divisions: [CGFloat] = [1.0 / 3.0, 2.0 / 3.0]

        for fraction in divisions {
            path.move(to: interpolate(quad.topLeft, quad.topRight, fraction))
            path.addLine(to: interpolate(quad.bottomLeft, quad.bottomRight, fraction))
        }

        for fraction in divisions {
            path.move(to: interpolate(quad.topLeft, quad.bottomLeft, fraction))
            path.addLine(to: interpolate(quad.topRight, quad.bottomRight, fraction))
        }

        return path
    }

    private func interpolate(_ start: CGPoint, _ end: CGPoint, _ fraction: CGFloat) -> CGPoint {
        return CGPoint(
            x: start.x + ((end.x - start.x) * fraction),
            y: start.y + ((end.y - start.y) * fraction)
        )
    }

    private func layoutCornerViews(forQuad quad: MDWQuadrilateral) {
        topLeftCornerView.center = quad.topLeft
        topRightCornerView.center = quad.topRight
        bottomLeftCornerView.center = quad.bottomLeft
        bottomRightCornerView.center = quad.bottomRight
    }

    func removeQuadrilateral() {
        quadLayer.path = nil
        quadLayer.isHidden = true
        stabilityGridLayer.path = nil
        updateAutoScanProgress(0.0, animated: false)
        quad = nil
    }

    // MARK: - Actions

    func moveCorner(cornerView: MDWEditScanCornerView, atPoint point: CGPoint) {
        guard let quad = quad else {
            return
        }

        let validPoint = self.validPoint(point, forCornerViewOfSize: cornerView.bounds.size, inView: self)

        cornerView.center = validPoint
        let updatedQuad = update(quad, withPosition: validPoint, forCorner: cornerView.position)

        self.quad = updatedQuad
        drawQuad(updatedQuad, animated: false)
    }

    func highlightCornerAtPosition(position: MDWCornerPosition, with image: UIImage) {
        guard editable else {
            return
        }
        isHighlighted = true

        let cornerView = cornerViewForCornerPosition(position: position)
        guard cornerView.isHighlighted == false else {
            cornerView.highlightWithImage(image)
            return
        }

        let origin = CGPoint(x: cornerView.frame.origin.x - (highlightedCornerViewSize.width - cornerViewSize.width) / 2.0,
                             y: cornerView.frame.origin.y - (highlightedCornerViewSize.height - cornerViewSize.height) / 2.0)
        cornerView.frame = CGRect(origin: origin, size: highlightedCornerViewSize)
        cornerView.highlightWithImage(image)
    }

    func resetHighlightedCornerViews() {
        isHighlighted = false
        resetHighlightedCornerViews(cornerViews: [topLeftCornerView, topRightCornerView, bottomLeftCornerView, bottomRightCornerView])
    }

    private func resetHighlightedCornerViews(cornerViews: [MDWEditScanCornerView]) {
        cornerViews.forEach { cornerView in
            resetHighlightedCornerView(cornerView: cornerView)
        }
    }

    private func resetHighlightedCornerView(cornerView: MDWEditScanCornerView) {
        cornerView.reset()
        let origin = CGPoint(x: cornerView.frame.origin.x + (cornerView.frame.size.width - cornerViewSize.width) / 2.0,
                             y: cornerView.frame.origin.y + (cornerView.frame.size.height - cornerViewSize.width) / 2.0)
        cornerView.frame = CGRect(origin: origin, size: cornerViewSize)
        cornerView.setNeedsDisplay()
    }

    // MARK: Validation

    /// Ensures that the given point is valid - meaning that it is within the bounds of the passed in `UIView`.
    ///
    /// - Parameters:
    ///   - point: The point that needs to be validated.
    ///   - cornerViewSize: The size of the corner view representing the given point.
    ///   - view: The view which should include the point.
    /// - Returns: A new point which is within the passed in view.
    private func validPoint(_ point: CGPoint, forCornerViewOfSize cornerViewSize: CGSize, inView view: UIView) -> CGPoint {
        var validPoint = point

        if point.x > view.bounds.width {
            validPoint.x = view.bounds.width
        } else if point.x < 0.0 {
            validPoint.x = 0.0
        }

        if point.y > view.bounds.height {
            validPoint.y = view.bounds.height
        } else if point.y < 0.0 {
            validPoint.y = 0.0
        }

        return validPoint
    }

    // MARK: - Convenience

    private func cornerViews(hidden: Bool) {
        topLeftCornerView.isHidden = hidden
        topRightCornerView.isHidden = hidden
        bottomRightCornerView.isHidden = hidden
        bottomLeftCornerView.isHidden = hidden
    }

    private func update(_ quad: MDWQuadrilateral, withPosition position: CGPoint, forCorner corner: MDWCornerPosition) -> MDWQuadrilateral {
        var quad = quad

        switch corner {
        case .topLeft:
            quad.topLeft = position
        case .topRight:
            quad.topRight = position
        case .bottomRight:
            quad.bottomRight = position
        case .bottomLeft:
            quad.bottomLeft = position
        }

        return quad
    }

    func cornerViewForCornerPosition(position: MDWCornerPosition) -> MDWEditScanCornerView {
        switch position {
        case .topLeft:
            return topLeftCornerView
        case .topRight:
            return topRightCornerView
        case .bottomLeft:
            return bottomLeftCornerView
        case .bottomRight:
            return bottomRightCornerView
        }
    }
}
