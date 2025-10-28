//
//  GraphicalFunction.swift
//
//
//  Created by Stefan Urbanek on 07/07/2023.
//

import PoieticCore

// TODO: Extract math to a separate Math.swift file

//enum GraphicalFunctionPresetDirection {
//    case growth
//    case decline
//}
//
//enum GraphicalFunctionPreset {
//    case data
//    case exponential
//    case logarithmic
//    case linear
//    case sShape
//}
// TODO: Presets (as follows here)
// - exponential growth
// - exponential decay
// - logarithmic growth
// - logarithmic decay
// - linear growth
// - linear decay
// - S-shaped growth
// - S-shaped decline


/// Evaluates a Catmull-Rom spline segment at parameter t.
///
/// The Catmull-Rom spline is a cubic interpolation method that creates smooth
/// C¹-continuous curves passing through control points. This function evaluates
/// a single segment of the spline using four control points.
///
/// ## Formula
///
/// For a segment between P₁ and P₂, with neighboring control points P₀ and P₃:
///
/// ```
/// P(t) = 0.5 × [(2P₁) +
///               (-P₀ + P₂)t +
///               (2P₀ - 5P₁ + 4P₂ - P₃)t² +
///               (-P₀ + 3P₁ - 3P₂ + P₃)t³]
/// ```
///
/// - Parameters
///     - p0: The control point before the segment (affects the tangent at p1)
///     - p1: The start point of the segment
///     - p2: The end point of the segment
///     - p3: The control point after the segment (affects the tangent at p2)
///     - t: The parameter value in the range [0, 1], where 0 corresponds to p1 and 1 to p2
///
/// - Returns: The interpolated y-value at parameter t
///
/// - Note: This function only interpolates the y-coordinates. The caller is
///   responsible for determining the appropriate t value based on x-coordinates.
///
public func catmullRomSpline(p0: Point, p1: Point, p2: Point, p3: Point, t: Double) -> Double {
    let t2 = t * t
    let t3 = t2 * t

    let y = 0.5 * (
        (2.0 * p1.y) +
        (-p0.y + p2.y) * t +
        (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
        (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3
    )

    return y
}

/// A function defined by a set of 2D control points with configurable interpolation.
///
/// `GraphicalFunction` represents a mathematical function y = f(x) defined by
/// discrete control points rather than an analytical formula. The function value
/// at any x-coordinate is computed by interpolating between the control points
/// using one of several interpolation methods.
///
/// ## Overview
///
/// Graphical functions are commonly used in system dynamics modelling to represent
/// non-linear relationships, lookup tables, and empirical data. They provide a
/// flexible way to define complex relationships without requiring explicit
/// mathematical formulas.
///
/// ## Usage
///
/// Create a graphical function by specifying control points and an interpolation method:
///
/// ```swift
/// let points = [
///     Point(x: 0.0, y: 0.0),
///     Point(x: 5.0, y: 10.0),
///     Point(x: 10.0, y: 15.0)
/// ]
///
/// let function = GraphicalFunction(points: points, method: .linear)
/// let result = function.apply(x: 7.5)  // Returns 12.5
/// ```
///
/// ## Interpolation Methods
///
/// Four interpolation methods are available, each suited for different use cases:
///
/// - **Step** (`.step`): Left-continuous step function (zero-order hold).
///   Best for discrete state changes and digital signals.
///
/// - **Linear** (`.linear`): Piecewise linear interpolation.
///   General-purpose method providing simple, predictable behaviors.
///
/// - **Cubic** (`.cubic`): Smooth Catmull-Rom spline interpolation.
///   Creates smooth curves through all points, ideal for natural-looking curves.
///
/// - **Nearest** (`.nearestStep`): Nearest-neighbor interpolation.
///   Selects the y-value of the closest control point.
///
/// See ``InterpolationMethod`` for detailed descriptions of each method.
///
/// ## Notes on Points
///
/// Control points are automatically sorted by their x-coordinate when the function
/// is created, ensuring correct interpolation behaviour regardless of input order.
///
/// Points outside the defined range are clamped to the boundary values (except
/// for nearest-neighbor interpolation, which extends the nearest point indefinitely).
///
/// ## Performance Considerations
///
/// - Point lookup is O(n) where n is the number of points
/// - Consider using fewer points for frequently evaluated functions
/// - Points are sorted once during initialisation
///
/// - SeeAlso: ``InterpolationMethod``, ``apply(x:)``, ``catmullRomSpline(p0:p1:p2:p3:t:)``
///
public class GraphicalFunction {
    /// Interpolation method used to compute values between control points.
    ///
    /// The interpolation method determines how the function computes output values
    /// for input x-coordinates that fall between defined control points. Different
    /// methods provide different trade-offs between smoothness, computational cost,
    /// and behavioural characteristics.
    ///
    /// - **Step** (`.step`): Left-continuous step function, also known as zero-order hold. The
    ///   function maintains a constant value from each control point until reaching the next
    ///   control point.
    ///
    /// - **Linear** (`.linear`): Point-wise linear interpolation between consecutive control points.
    ///   Creates straight line segments connecting each pair of adjacent points.
    ///
    /// - **Cubic** (`.cubic`): Catmull-Rom spline interpolation producing smooth curves that pass
    ///   through all control points. Uses four points (two neighbours on each side) to compute
    ///   a cubic polynomial for each segment.
    ///
    /// - **Nearest Step** (`.nearestStep`): Nearest-neighbor interpolation. Returns the y-value of
    ///   whichever control point has the closest x-coordinate to the query point.
    ///
    /// ## Choosing an Interpolation Method
    ///
    /// - Use **step** for discrete state machines, digital signals, or piecewise-constant functions
    /// - Use **linear** as the general-purpose default for most modeming scenarios
    /// - Use **cubic** when smoothness matters (e.g., animation, natural phenomena)
    /// - Use **nearestStep** for classification or when exact point values matter
    ///
    public enum InterpolationMethod: String, CaseIterable, Sendable {
        /// Left-continuous step function (zero-order hold).
        ///
        /// Maintains constant value from each point until the next point.
        /// Standard in discrete-time modeming and control systems.
        case step = "step"

        /// Smooth cubic interpolation using Catmull-Rom splines.
        ///
        /// Creates C¹-continuous curves passing through all control points.
        /// Produces natural-looking smooth curves.
        case cubic = "cubic"

        /// Piecewise linear interpolation between consecutive points.
        ///
        /// General-purpose method with predictable behaviour.
        /// C⁰ continuous (no smoothness at control points).
        case linear = "linear"

        /// Nearest-neighbor interpolation.
        ///
        /// Returns the y-value of the closest control point by x-coordinate.
        /// Useful for discrete classification or region selection.
        case nearestStep = "nearest"

        /// The default interpolation method used when none is specified.
        ///
        /// Defaults to `.step`, following conventions from system dynamics
        /// modeling tools.
        public static let defaultMethod: InterpolationMethod = .step
    }

    /// Set of points defining the function.
    ///
    public let points: [Point]

    /// Interpolation method used to compute output.
    ///
    public let method: InterpolationMethod

    /// Create a graphical function with points where the _x_ values are in the
    /// provided list and the _y_ values are a sequence from 0 to the number of
    /// values in the list.
    ///
    /// For example for the list `[10, 20, 30]` the points will be: `(10, 0)`,
    /// `(20, 1)` and `(30, 2)`
    ///
    convenience init(values: [Double],
         start startTime: Double = 0.0,
         timeDelta: Double = 1.0) {

        var result: [Point] = []
        var time = startTime
        for value in values {
            result.append(Point(x: time, y:value))
            time += timeDelta
        }
        self.init(points: result)
    }
    
    /// Create a new graphical function with given set of points.
    ///
    /// The points are automatically sorted by their x-coordinate in ascending order.
    ///
    /// The default interpolation method is ``InterpolationMethod/step``.
    ///
    public init(points: [Point], method: InterpolationMethod = .step) {
        self.points = points.sorted { $0.x < $1.x }
        self.method = method
    }

    /// Evaluates the graphical function at the given x coordinate.
    ///
    /// This is the main entry point for evaluating the function. It dispatches
    /// to the appropriate interpolation method based on the function's
    /// ``method`` property.
    ///
    /// - Parameter x: The input value at which to evaluate the function.
    /// - Returns: The interpolated y-value according to the interpolation method.
    ///
    /// - SeeAlso: ``InterpolationMethod``
    ///
    public func apply(x: Double) -> Double {
        switch method {
        case .nearestStep: nearestInterpolation(x: x)
        case .step: stepInterpolation(x: x)
        case .linear: linearInterpolation(x: x)
        case .cubic: cubicInterpolation(x: x)
        }
    }

    /// Function that finds the nearest point and returns its y-value.
    ///
    /// This is a nearest-neighbor interpolation method.
    ///
    /// If the graphical function has no points specified then it returns
    /// zero.
    ///
    public func nearestInterpolation(x: Double) -> Double {
        guard var nearest = points.first else { return 0 }

        var nearestDistance = abs(x - nearest.x)
        
        for point in points.dropFirst() {
            let distance = abs(x - point.x)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = point
            }
        }
        
        return nearest.y
    }

    /// Left-continuous step function interpolation (zero-order hold).
    ///
    /// The function maintains a constant value from each point until the next point.
    /// For x values before the first point, returns the first y-value.
    /// For x values at or after the last point, returns the last y-value.
    ///
    /// This is the standard step function used in discrete-time modeling and
    /// control systems.
    ///
    /// - Parameter x: The input value at which to evaluate the function.
    /// - Returns: The interpolated y-value.
    ///
    public func stepInterpolation(x: Double) -> Double {
        guard !points.isEmpty else { return 0.0 }
        guard points.count > 1 else { return points[0].y }

        // Quick bounds checks
        if x < points[0].x { return points[0].y }
        if x >= points[points.count - 1].x { return points[points.count - 1].y }

        for i in 0..<(points.count - 1) {
            if x >= points[i].x && x < points[i + 1].x {
                return points[i].y
            }
        }

        // Should not reach here due to bounds checks above
        return points[points.count - 1].y
    }

    /// Linear interpolation between consecutive points.
    ///
    /// The function performs piecewise linear interpolation between each pair
    /// of consecutive points. For x values outside the range of defined points,
    /// the function clamps to the nearest endpoint value.
    ///
    /// Formula: y = y₁ + (x - x₁) × (y₂ - y₁) / (x₂ - x₁)
    ///
    /// - Parameter x: The input value at which to evaluate the function.
    /// - Returns: The interpolated y-value.
    ///
    public func linearInterpolation(x: Double) -> Double {
        guard !points.isEmpty else { return 0.0 }
        guard points.count > 1 else { return points[0].y }

        // Bounds check - clamp to first/last value
        if x <= points[0].x { return points[0].y }
        if x >= points[points.count - 1].x { return points[points.count - 1].y }

        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]

            if x >= p1.x && x <= p2.x {
                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let t = (x - p1.x) / dx
                return p1.y + t * dy
            }
        }

        // Should not reach here due to bounds checks above
        return points[points.count - 1].y
    }

    /// Cubic interpolation using Catmull-Rom spline.
    ///
    /// Catmull-Rom splines create smooth C¹-continuous curves that pass through
    /// all control points. The curve is defined piecewise between consecutive
    /// points, using neighboring points as control points to determine tangents.
    ///
    /// ## Algorithm
    ///
    /// For each segment between points P₁ and P₂, the curve uses four points
    /// (P₀, P₁, P₂, P₃) where P₀ and P₃ are the neighboring control points:
    ///
    /// ```
    /// P(t) = 0.5 × [(2P₁) +
    ///               (-P₀ + P₂)t +
    ///               (2P₀ - 5P₁ + 4P₂ - P₃)t² +
    ///               (-P₀ + 3P₁ - 3P₂ + P₃)t³]
    /// ```
    ///
    /// where t ∈ [0, 1] is the normalized position within the segment.
    ///
    /// ## Endpoint Handling
    ///
    /// At the endpoints where we lack neighboring control points, the function
    /// extrapolates virtual control points to maintain smoothness:
    /// - Before first segment: reflects the tangent at the first point
    /// - After last segment: reflects the tangent at the last point
    ///
    /// For x values outside the range of defined points, the function clamps
    /// to the nearest endpoint value.
    ///
    /// ## Edge Cases
    ///
    /// - Single point: Returns that point's y-value for all x
    /// - Two points: Falls back to linear interpolation
    ///
    /// - Parameter x: The input value at which to evaluate the function.
    /// - Returns: The interpolated y-value.
    ///
    public func cubicInterpolation(x: Double) -> Double {
        guard !points.isEmpty else { return 0.0 }

        guard points.count > 1 else { return points[0].y }

        // For two points, fall back to linear interpolation
        if points.count == 2 { return linearInterpolation(x: x) }

        // Before first point - clamp to first value
        if x <= points[0].x { return points[0].y }

        // At or after last point - clamp to last value
        if x >= points[points.count - 1].x { return points[points.count - 1].y }

        // Find the segment: points[i].x <= x < points[i+1].x
        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]

            if x >= p1.x && x <= p2.x {
                // Get the four points for Catmull-Rom spline
                let p0: Point
                let p3: Point

                // Extrapolate control point before first segment
                if i == 0 {
                    // Reflect tangent: p0 = p1 - (p2 - p1)
                    p0 = Point(x: p1.x - (p2.x - p1.x),
                              y: p1.y - (p2.y - p1.y))
                } else {
                    p0 = points[i - 1]
                }

                // Extrapolate control point after last segment
                if i == points.count - 2 {
                    // Reflect tangent: p3 = p2 + (p2 - p1)
                    p3 = Point(x: p2.x + (p2.x - p1.x),
                              y: p2.y + (p2.y - p1.y))
                } else {
                    p3 = points[i + 2]
                }

                // Normalize t to [0, 1] within the segment
                let t = (x - p1.x) / (p2.x - p1.x)

                // Evaluate Catmull-Rom spline
                return catmullRomSpline(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
            }
        }

        // Should not reach here due to bounds checks above
        return points[points.count - 1].y
    }
}
