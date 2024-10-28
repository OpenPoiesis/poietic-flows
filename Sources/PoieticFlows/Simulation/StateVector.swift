//
//  StateVector.swift
//  
//
//  Created by Stefan Urbanek on 30/07/2022.
//

import PoieticCore


// TODO: Consolidate SimulationState and SimulationContext?

/// A simple vector-like structure to hold an unordered collection of numeric
/// values that can be accessed by key. Simple arithmetic operations can be done
/// with the structure, such as addition, subtraction and multiplication
/// by a scalar value.
///
public struct SimulationState: CustomStringConvertible {
    // TODO: Add time as property, maybe step as well
    
    public typealias Index = Int
    
    @available(*, deprecated, message: "Use simulation context")
    public let model: CompiledModel

    public var values: [Variant]
    
    var time: Double {
        // TODO: Make this a native property?
        let timeValue = values[model.timeVariableIndex]
        return try! timeValue.doubleValue()
    }

    /// Create a simulation state with all variables set to zero.
    ///
    /// The list of builtins and simulation variables will be initialised
    /// according to the count of the respective variables in the compiled
    /// model.
    ///
    public init(model: CompiledModel) {
        self.model = model
        self.values = Array(repeating: Variant(0), count: model.stateVariables.count)
    }
    
    public init(_ values: [Variant], model: CompiledModel) {
        precondition(values.count == model.stateVariables.count,
                     "Count of values (\(values.count) does not match required items count \(model.stateVariables.count)")
        self.model = model
        self.values = values
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
        for (variable, value) in zip(model.stateVariables, values) {
            let item = "\(variable.name): \(value)"
            items.append(item)
        }
        let text = items.joined(separator: ", ")
        return "[\(text)]"
    }
    
    // Arithmetic operations
    public mutating func numericAdd(_ values: NumericVector, atIndices indices: [Index]) {
        for (index, value) in zip (indices, values) {
            let current = self.double(at: index)
            self.values[index] = Variant(current + value)
        }
    }
}



