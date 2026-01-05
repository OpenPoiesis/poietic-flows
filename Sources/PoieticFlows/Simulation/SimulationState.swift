//
//  StateVector.swift
//  
//
//  Created by Stefan Urbanek on 30/07/2022.
//

import PoieticCore

// TODO: Separate numeric values (doubles) from Variant values, too many conversions/unwrapping

/// A collection of simulation state variables.
///
public struct SimulationState: Component, CustomStringConvertible {
    public typealias Index = Int
    
    public let step: Int
    public let time: Double
    public let timeDelta: Double
    
    /// Values representing the simulation state.
    ///
    public var values: [Variant]
    
    /// Create a simulation state with all variables set to zero.
    ///
    /// - Parameters:
    ///     - count: Number of state variables.
    ///     - step: Simulation step.
    ///     - time: Simulation time.
    ///     - timeDelta: Simulation time delta.
    ///
    public init(count: Int, step: Int=0, time: Double=0, timeDelta: Double=1.0) {
        self.step = step
        self.time = time
        self.timeDelta = timeDelta
        self.values = Array(repeating: Variant(0), count: count)
    }
    
    public init(values: [Variant], step: Int=0, time: Double=0, timeDelta: Double=1.0) {
        self.step = step
        self.time = time
        self.timeDelta = timeDelta
        self.values = values
    }

    /// Create a copy of a simulation state by advancing time.
    ///
    /// By default, the step is increased by 1, time is increased by `timeDelta`.
    ///
    /// Callers might override any of the values.
    ///
    public func advanced(step: Int?=nil, time: Double?=nil, timeDelta: Double?=nil) -> SimulationState {
        SimulationState(values: values,
                        step: step ?? self.step + 1,
                        time: time ?? self.time + (timeDelta ?? self.timeDelta),
                        timeDelta: timeDelta ?? self.timeDelta)
    }
    
    /// Get or set a simulation variable by reference.
    ///
    @inlinable
    public subscript(_ index: Index) -> Variant {
        get {
            return values[index]
        }
        set(value) {
            values[index] = value
        }
    }
    
    @inlinable
    public subscript(_ index: Index) -> Double {
        get {
            try! values[index].doubleValue()
        }
        set(value) {
            values[index] = Variant(value)
        }
    }

    
    /// Get or set a simulation variable as double by reference.
    ///
    /// This subscript should be used when it is guaranteed that the value
    /// is convertible to _double_, such as values for stocks or flows.
    ///
    public func double(at index: Index) -> Double {
        // FIXME: Rename to unsafeDouble(at:)
        do {
            return try values[index].doubleValue()
        }
        catch {
            fatalError("Unexpected non-double state value at \(index)")
        }
    }

    /// - Precondition: Values at given indices must be convertible to a floating point number.
    @inlinable
    func numericVector(at indices: [Index]) -> NumericVector {
        var vector = NumericVector(zeroCount: indices.count)
        for (index, variableIndex) in indices.enumerated() {
            vector[index] = try! values[variableIndex].doubleValue()
        }
        return vector
    }

    @inlinable
    public subscript(indices: [Index]) -> NumericVector {
        get {
            return numericVector(at: indices)
        }
    }

    public var description: String {
        var items: [String] = []
        // for (variable, value) in zip(model.stateVariables, values) {
        for (index, value) in values.enumerated() {
            let item = "\(index): \(value)"
            items.append(item)
        }
        let text = items.joined(separator: ", ")
        return "[\(text)]"
    }
}



