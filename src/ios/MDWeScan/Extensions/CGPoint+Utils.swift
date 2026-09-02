//
//  CGPoint+Utils.swift
//  WeScan
//
//  Created by Boris Emorine on 2/9/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import Foundation
import UIKit

extension CGPoint {

    /// Returns a rectangle of a given size surrounding the point.
    ///
    /// - Parameters:
    ///   - size: The size of the rectangle that should surround the points.
    /// - Returns: A `CGRect` instance that surrounds this instance of `CGPoint`.
    func mdwSurroundingSquare(withSize size: CGFloat) -> CGRect {
        return CGRect(x: x - size / 2.0, y: y - size / 2.0, width: size, height: size)
    }

    /// Checks wether this point is within a given distance of another point.
    ///
    /// - Parameters:
    ///   - delta: The minimum distance to meet for this distance to return true.
    ///   - point: The second point to compare this instance with.
    /// - Returns: True if the given `CGPoint` is within the given distance of this instance of `CGPoint`.
    func mdwIsWithin(delta: CGFloat, ofPoint point: CGPoint) -> Bool {
        return (abs(x - point.x) <= delta) && (abs(y - point.y) <= delta)
    }

    /// Returns the same `CGPoint` in the mdwCartesian coordinate system.
    ///
    /// - Parameters:
    ///   - height: The height of the bounds this points belong to, in the current coordinate system.
    /// - Returns: The same point in the mdwCartesian coordinate system.
    func mdwCartesian(withHeight height: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: height - y)
    }

    /// Returns the distance between two points
    func mdwDistanceTo(point: CGPoint) -> CGFloat {
        return hypot((self.x - point.x), (self.y - point.y))
    }

    /// Returns the closest corner from the point
    func mdwClosestCornerFrom(quad: MDWQuadrilateral) -> MDWCornerPosition {
        var smallestDistance = mdwDistanceTo(point: quad.topLeft)
        var closestCorner = MDWCornerPosition.topLeft

        if mdwDistanceTo(point: quad.topRight) < smallestDistance {
            smallestDistance = mdwDistanceTo(point: quad.topRight)
            closestCorner = .topRight
        }

        if mdwDistanceTo(point: quad.bottomRight) < smallestDistance {
            smallestDistance = mdwDistanceTo(point: quad.bottomRight)
            closestCorner = .bottomRight
        }

        if mdwDistanceTo(point: quad.bottomLeft) < smallestDistance {
            smallestDistance = mdwDistanceTo(point: quad.bottomLeft)
            closestCorner = .bottomLeft
        }

        return closestCorner
    }

}
