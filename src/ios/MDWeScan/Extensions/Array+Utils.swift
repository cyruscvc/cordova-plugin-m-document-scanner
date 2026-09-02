//
//  Array+Utils.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import Foundation
import Vision

extension Array where Element == MDWQuadrilateral {

    /// Finds the mdwBiggest rectangle within an array of `MDWQuadrilateral` objects.
    func mdwBiggest() -> MDWQuadrilateral? {
        let biggestRectangle = self.max(by: { rect1, rect2 -> Bool in
            return rect1.perimeter < rect2.perimeter
        })

        return biggestRectangle
    }

}
