//
//  Common.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 06/09/2026.
//

extension Double {
    func approxEqual(to other: Double, tolerance: Double = 1e-9) -> Bool {
        return abs(self - other) < tolerance
    }
}

