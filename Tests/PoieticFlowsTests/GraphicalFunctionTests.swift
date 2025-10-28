//
//  GraphicalFunctionTests.swift
//
//
//  Created by Stefan Urbanek on 10/07/2023.
//

// Note: These tests were mostly written with a help of a LLM.

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct GraphicalFunctionTests {

    // MARK: - Basic Edge Cases

    @Test func emptyPoints() {
        let gf = GraphicalFunction(points: [], method: .linear)
        #expect(gf.apply(x: 0.0) == 0.0)
        #expect(gf.apply(x: 10.0) == 0.0)
        #expect(gf.apply(x: -5.0) == 0.0)
    }

    @Test func singlePoint() {
        let gf = GraphicalFunction(points: [Point(x: 5.0, y: 10.0)], method: .linear)
        #expect(gf.apply(x: 0.0) == 10.0)
        #expect(gf.apply(x: 5.0) == 10.0)
        #expect(gf.apply(x: 100.0) == 10.0)
    }

    @Test func twoPoints() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 20.0)
        ], method: .linear)

        #expect(gf.apply(x: 0.0) == 0.0)
        #expect(gf.apply(x: 5.0) == 10.0)
        #expect(gf.apply(x: 10.0) == 20.0)
    }

    // MARK: - Point Sorting

    @Test func pointsAreSortedByX() {
        let unsorted = [
            Point(x: 10.0, y: 100.0),
            Point(x: 5.0, y: 50.0),
            Point(x: 0.0, y: 0.0),
            Point(x: 15.0, y: 150.0)
        ]
        let gf = GraphicalFunction(points: unsorted, method: .linear)

        // Check points are sorted
        #expect(gf.points[0].x == 0.0)
        #expect(gf.points[1].x == 5.0)
        #expect(gf.points[2].x == 10.0)
        #expect(gf.points[3].x == 15.0)
    }

    // MARK: - Nearest Interpolation

    @Test func nearestInterpolation() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 10.0),
            Point(x: 10.0, y: 5.0)
        ], method: .nearestStep)

        // Closest to first point
        #expect(gf.apply(x: 0.0) == 0.0)
        #expect(gf.apply(x: 1.0) == 0.0)
        #expect(gf.apply(x: 2.0) == 0.0)

        // Closest to middle point
        #expect(gf.apply(x: 3.5) == 10.0)
        #expect(gf.apply(x: 5.0) == 10.0)
        #expect(gf.apply(x: 6.5) == 10.0)

        // Closest to last point
        #expect(gf.apply(x: 7.6) == 5.0)
        #expect(gf.apply(x: 10.0) == 5.0)
        #expect(gf.apply(x: 15.0) == 5.0)
    }

    // MARK: - Step Interpolation (Left-continuous)

    @Test func stepInterpolation() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 10.0),
            Point(x: 5.0, y: 20.0),
            Point(x: 10.0, y: 30.0)
        ], method: .step)

        // Before first point
        #expect(gf.apply(x: -5.0) == 10.0)

        // At and after first point, before second
        #expect(gf.apply(x: 0.0) == 10.0)
        #expect(gf.apply(x: 2.5) == 10.0)
        #expect(gf.apply(x: 4.9) == 10.0)

        // At and after second point, before third
        #expect(gf.apply(x: 5.0) == 20.0)
        #expect(gf.apply(x: 7.5) == 20.0)
        #expect(gf.apply(x: 9.9) == 20.0)

        // At and after last point
        #expect(gf.apply(x: 10.0) == 30.0)
        #expect(gf.apply(x: 15.0) == 30.0)
    }

    @Test func stepInterpolationSinglePoint() {
        let gf = GraphicalFunction(points: [Point(x: 5.0, y: 42.0)], method: .step)
        #expect(gf.apply(x: 0.0) == 42.0)
        #expect(gf.apply(x: 10.0) == 42.0)
    }

    // MARK: - Linear Interpolation

    @Test func linearInterpolation() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 100.0)
        ], method: .linear)

        #expect(gf.apply(x: 0.0) == 0.0)
        #expect(gf.apply(x: 5.0) == 50.0)
        #expect(gf.apply(x: 10.0) == 100.0)
    }

    @Test func linearInterpolationMultipleSegments() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 10.0),
            Point(x: 10.0, y: 5.0),
            Point(x: 15.0, y: 20.0)
        ], method: .linear)

        // First segment: (0,0) to (5,10)
        #expect(gf.apply(x: 2.5) == 5.0)

        // Second segment: (5,10) to (10,5)
        #expect(gf.apply(x: 7.5) == 7.5)

        // Third segment: (10,5) to (15,20)
        #expect(gf.apply(x: 12.5) == 12.5)
    }

    @Test func linearInterpolationClampingBounds() {
        let gf = GraphicalFunction(points: [
            Point(x: 5.0, y: 10.0),
            Point(x: 15.0, y: 30.0)
        ], method: .linear)

        // Below range - clamp to first value
        #expect(gf.apply(x: 0.0) == 10.0)
        #expect(gf.apply(x: 4.0) == 10.0)

        // Above range - clamp to last value
        #expect(gf.apply(x: 20.0) == 30.0)
        #expect(gf.apply(x: 100.0) == 30.0)
    }

    // MARK: - Cubic Interpolation (Catmull-Rom)

    @Test func cubicInterpolationBasic() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 10.0),
            Point(x: 10.0, y: 5.0),
            Point(x: 15.0, y: 15.0)
        ], method: .cubic)

        // At control points, should pass through exactly
        #expect(gf.apply(x: 0.0) == 0.0)
        #expect(gf.apply(x: 5.0) == 10.0)
        #expect(gf.apply(x: 10.0) == 5.0)
        #expect(gf.apply(x: 15.0) == 15.0)

        // Between points should be smooth (just verify it computes)
        let midValue = gf.apply(x: 7.5)
        #expect(midValue > 5.0 && midValue < 10.0)
    }

    @Test func cubicInterpolationTwoPointsFallsBackToLinear() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 20.0)
        ], method: .cubic)

        // Should behave like linear interpolation
        #expect(gf.apply(x: 5.0) == 10.0)
        #expect(gf.apply(x: 2.5) == 5.0)
        #expect(gf.apply(x: 7.5) == 15.0)
    }

    @Test func cubicInterpolationSinglePoint() {
        let gf = GraphicalFunction(points: [Point(x: 5.0, y: 42.0)], method: .cubic)
        #expect(gf.apply(x: 0.0) == 42.0)
        #expect(gf.apply(x: 10.0) == 42.0)
    }

    @Test func cubicInterpolationClampingBounds() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 10.0),
            Point(x: 10.0, y: 5.0)
        ], method: .cubic)

        // Below range - clamp to first value
        #expect(gf.apply(x: -5.0) == 0.0)

        // Above range - clamp to last value
        #expect(gf.apply(x: 20.0) == 5.0)
    }

    @Test func cubicInterpolationSmoothCurve() {
        // Test that cubic produces a smooth curve through points
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 1.0, y: 1.0),
            Point(x: 2.0, y: 0.0),
            Point(x: 3.0, y: 1.0)
        ], method: .cubic)

        // Sample multiple points between 0 and 1
        let samples = stride(from: 0.0, through: 1.0, by: 0.1).map { gf.apply(x: $0) }

        // Values should increase monotonically in this segment
        for i in 1..<samples.count {
            #expect(samples[i] >= samples[i-1])
        }
    }

    // MARK: - Catmull-Rom Spline Function

    @Test func catmullRomSplineAtEndpoints() {
        let p0 = Point(x: 0, y: 0)
        let p1 = Point(x: 1, y: 10)
        let p2 = Point(x: 2, y: 20)
        let p3 = Point(x: 3, y: 30)

        // At t=0, should equal p1.y
        #expect(catmullRomSpline(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.0) == 10.0)

        // At t=1, should equal p2.y
        #expect(catmullRomSpline(p0: p0, p1: p1, p2: p2, p3: p3, t: 1.0) == 20.0)
    }

    @Test func catmullRomSplineMidpoint() {
        let p0 = Point(x: 0, y: 0)
        let p1 = Point(x: 1, y: 0)
        let p2 = Point(x: 2, y: 10)
        let p3 = Point(x: 3, y: 10)

        // At t=0.5, should be between p1 and p2
        let mid = catmullRomSpline(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.5)
        #expect(mid > 0.0 && mid < 10.0)
    }

    @Test func catmullRomSplineSymmetry() {
        // Symmetric control points should produce symmetric curve
        let p0 = Point(x: 0, y: 0)
        let p1 = Point(x: 1, y: 10)
        let p2 = Point(x: 2, y: 10)
        let p3 = Point(x: 3, y: 0)

        let v1 = catmullRomSpline(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.25)
        let v2 = catmullRomSpline(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.75)

        // Due to symmetry, these should be equal
        #expect(abs(v1 - v2) < 0.0001)
    }

    // MARK: - Apply Method Dispatch

    @Test func applyDispatchesCorrectly() {
        let points = [
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 10.0),
            Point(x: 10.0, y: 20.0)
        ]

        // Test each method type
        let nearest = GraphicalFunction(points: points, method: .nearestStep)
        let step = GraphicalFunction(points: points, method: .step)
        let linear = GraphicalFunction(points: points, method: .linear)
        let cubic = GraphicalFunction(points: points, method: .cubic)

        // At x=2.5, each method should give different results
        let x = 2.5

        // Nearest should pick closest point (0.0)
        #expect(nearest.apply(x: x) == 0.0)

        // Step should be left-continuous (value at 0.0)
        #expect(step.apply(x: x) == 0.0)

        // Linear should interpolate
        #expect(linear.apply(x: x) == 5.0)

        // Cubic should be smooth (between 0 and 10)
        let cubicValue = cubic.apply(x: x)
        #expect(cubicValue >= 0.0 && cubicValue <= 10.0)
    }

    // MARK: - Edge Cases and Numerical Stability

    @Test func negativeXValues() {
        let gf = GraphicalFunction(points: [
            Point(x: -10.0, y: 5.0),
            Point(x: 0.0, y: 10.0),
            Point(x: 10.0, y: 15.0)
        ], method: .linear)

        #expect(gf.apply(x: -10.0) == 5.0)
        #expect(gf.apply(x: -5.0) == 7.5)
        #expect(gf.apply(x: 0.0) == 10.0)
    }

    @Test func negativeYValues() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: -10.0),
            Point(x: 5.0, y: 10.0)
        ], method: .linear)

        #expect(gf.apply(x: 0.0) == -10.0)
        #expect(gf.apply(x: 2.5) == 0.0)
        #expect(gf.apply(x: 5.0) == 10.0)
    }

    @Test func duplicateXValues() {
        // While not ideal, should handle duplicate x values gracefully
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 10.0),
            Point(x: 5.0, y: 20.0), // Duplicate x
            Point(x: 10.0, y: 30.0)
        ], method: .linear)

        // Should still compute without crashing
        let result = gf.apply(x: 5.0)
        #expect(result >= 0.0) // Just verify it computes
    }

    @Test func veryClosePoints() {
        let gf = GraphicalFunction(points: [
            Point(x: 0.0, y: 0.0),
            Point(x: 0.001, y: 10.0),
            Point(x: 10.0, y: 20.0)
        ], method: .linear)

        // Should handle very close points numerically
        let result = gf.apply(x: 0.0005)
        #expect(result >= 0.0 && result <= 10.0)
    }
}
