//
//  GraphicalFunction.swift
//
//
//  Created by Stefan Urbanek on 07/07/2023.
//

import PoieticCore


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

// TODO: This is a late-night sketch implementation, GFComponent + GF should be merged
/// Object representing a function defined by a graph.
///
/// The graphical function is defined by a set of points. The function output
/// value for given input value is computed using the function's interpolation
/// method.
///
public class GraphicalFunction {
    public enum InterpolationMethod: String, CaseIterable {
        case step = "step"
    }

    /// Set of points defining the function.
    ///
    var points: [Point]

    /// Interpolation method used to compute output.
    ///
    let method: InterpolationMethod = .step

    // TODO: Presets (as follows here)
    // - exponential growth
    // - exponential decay
    // - logarithmic growth
    // - logarithmic decay
    // - linear growth
    // - linear decay
    // - S-shaped growth
    // - S-shaped decline
    
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
    /// The default interpolation method is ``InterpolationMethod/step``.
    ///
    public init(points: [Point]) {
        self.points = points
    }
    
    /// Function that finds the nearest time point and returns its y-value.
    ///
    /// If the graphical function has no points specified then it returns
    /// zero.
    ///
    public func stepFunction(x: Double) -> Double {
        let point = nearestXPoint(x)
        return point.y
    }
    
    /// Creates an unary function used in computation that wraps
    /// this graphical function.
    ///
    /// Current implementation just wraps the ``stepFunction(x:)``.
    ///
    @available(*, deprecated, message: "Use BoundGraphicalFunction")
    public func createFunction(name: String) -> Function {
        let function = Function.NumericUnary(name,
                                             argumentName: "x",
                                             body: self.stepFunction)
        
        return function
    }
    /// Get a point that is nearest in the x-axis to the value specified.
    ///
    /// If the graphical function has no points specified then it returns
    /// point at zero.
    ///
    func nearestXPoint(_ x: Double) -> Point {
        guard !points.isEmpty else {
            return Point()
        }
        var nearest = points.first!
        var nearestDistance = abs(x - nearest.x)
        
        for point in points.dropFirst() {
            let distance = abs(x - point.x)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = point
            }
        }
        
        return nearest
    }
}
