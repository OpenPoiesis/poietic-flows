//
//  StateVector.swift
//  
//
//  Created by Stefan Urbanek on 30/07/2022.
//

import PoieticCore


/// A simple vector-like structure to hold an unordered collection of numeric
/// values that can be accessed by key. Simple arithmetic operations can be done
/// with the structure, such as addition, subtraction and multiplication
/// by a scalar value.
///
public struct SimulationState: CustomStringConvertible {
    public typealias Index = Int
    
    public let step: Int
    public let time: Double
    public let timeDelta: Double
    
    /// Values representing the simulation state.
    ///
    /// The contents and order of this array corresponds to the
    /// ``CompiledModel/stateVariables``. It contains, in order:
    ///
    /// - Built-in variables – see ``Simulator/BuiltinVariables``
    /// - Variables that represent design objects, described by ``StateVariable``.
    /// - Internal variables used by some nodes, such as delay.
    ///
    /// - SeeAlso: ``StockFlowSimulation/update(_:)``,
    ///   ``CompiledModel/stateVariables``,
    ///   ``StateVariable``,
    ///   ``Compiler/createStateVariable(content:valueType:name:)``
    ///
    public var values: [Variant]
    
    /// Create a simulation state with all variables set to zero.
    ///
    /// - Parameters:
    ///     - model: Compiled model used to determine the number of variables.
    ///     - step: Simulation step.
    ///     - time: Simulation time.
    ///     - timeDelta: Simulation time delta.
    ///
    public init(model: CompiledModel, step: Int=0, time: Double=0, timeDelta: Double=1.0) {
        self.step = step
        self.time = time
        self.timeDelta = timeDelta
        self.values = Array(repeating: Variant(0), count: model.stateVariables.count)
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
    public func advance(step: Int?=nil, time: Double?=nil, timeDelta: Double?=nil) -> SimulationState {
        SimulationState(values: values,
                        step: step ?? self.step + 1,
                        time: time ?? self.time + (timeDelta ?? self.timeDelta),
                        timeDelta: timeDelta ?? self.timeDelta)
    }
    
    /// Get or set a simulation variable by reference.
    ///
    @inlinable
    public subscript(ref: Index) -> Variant {
        get {
            return values[ref]
        }
        set(value) {
            values[ref] = value
        }
    }
    
    /// Get or set a simulation variable as double by reference.
    ///
    /// This subscript should be used when it is guaranteed that the value
    /// is convertible to _double_, such as values for stocks or flows.
    ///
    public func double(at index: Index) -> Double {
        do {
            return try values[index].doubleValue()
        }
        catch {
            fatalError("Unexpected non-double state value at \(index)")
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
    
    // Arithmetic operations
    /// Add numeric values to the variables at provided set of indices.
    ///
    /// - Precondition: The caller must assure that the values at given indices
    ///   are convertible to double.
    ///
    public mutating func numericAdd(_ values: NumericVector, atIndices indices: [Index]) {
        for (index, value) in zip (indices, values) {
            let current = self.double(at: index)
            self.values[index] = Variant(current + value)
        }
    }
}



