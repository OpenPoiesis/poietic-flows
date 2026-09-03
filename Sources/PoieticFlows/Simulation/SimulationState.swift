//
//  StateVector.swift
//  
//
//  Created by Stefan Urbanek on 30/07/2022.
//

import PoieticCore

public struct SimulationState {
    // Replaces BoundVariable
    // Alt names: just Reference or just Variable
    public enum Reference: Hashable, CustomStringConvertible {
        case builtin(BuiltinVariable)
        case stock(Int)
        case flow(Int)
        case numeric(Int)
        case variant(Int)

        public var description: String {
            switch self {
            case .builtin(let variable): "builtin(\(variable))"
            case .stock(let index):   "stock(\(index))"
            case .flow(let index):    "flow(\(index))"
            case .numeric(let index): "numeric(\(index))"
            case .variant(let index): "variant(\(index))"
            }
        }
        
        public var type: ReferenceType {
            switch self {
            case .builtin: .builtin
            case .stock:   .stock
            case .flow:    .flow
            case .numeric: .numeric
            case .variant: .variant
            }

        }
    }
    
    public enum ReferenceType: Equatable {
        case builtin
        case stock
        case flow
        case numeric
        case variant
    }
    
    public private(set) var step: Int
    public private(set) var time: Double
    public private(set) var timeDelta: Double
    private var constants: Set<Reference>

    
    /// Stocks
    public var stocks: NumericVector
    /// Adjusted flows
    public var flows: NumericVector
    /// Auxiliaries and internal numeric variables (such as estimated flows or smooth)
    public var numerics: [Double]
    public var variants: [Variant]
    // What about smooth/delay queues?
    // public var numericQueues: [NumericVector]

    public init(plan: SimulationPlan, step: Int, time: Double, timeDelta: Double) {
        self.constants = Set()
        self.step = step
        self.time = time
        self.timeDelta = timeDelta
        self.stocks = NumericVector(zeroCount: plan.stocks.count)
        self.flows = NumericVector(zeroCount: plan.flows.count)
        let numCount = plan.stateVariables.count { $0.reference.type == .numeric  }
        self.numerics = Array(repeating: 0.0, count: numCount)
        let varCount = plan.stateVariables.count { $0.reference.type == .variant  }
        self.variants = Array(repeating: Variant(0), count: varCount)
    }
    public func isConstant(_ ref: Reference) -> Bool {
        return constants.contains(ref)
    }
    /// Mark reference as constant
    public mutating func markAsConstant(_ ref: Reference) {
        constants.insert(ref)
    }

    subscript(ref: Reference) -> Variant {
        switch ref {
            
        case let .builtin(builtin):
            switch builtin {
            case .step: return Variant(step)
            case .time: return Variant(time)
            case .timeDelta: return Variant(timeDelta)
            }
        case let .stock(index): return Variant(stocks[index])
        case let .flow(index): return Variant(flows[index])
        case let .numeric(index): return Variant(numerics[index])
        case let .variant(index): return variants[index]
        }
    }

    mutating func setValue(_ variant: Variant, for reference: Reference) throws (ValueError) {
        switch reference {
        case .builtin(_):
            // TODO: [REFACTORING] This is a programming error, not an user error. This should not happen. But what else to do here?
            fatalError("Trying to set builtin")
        case let .stock(index):
            let numeric = try variant.doubleValue()
            stocks[index] = numeric
        case let .flow(index):
            let numeric = try variant.doubleValue()
            flows[index] = numeric
        case let .numeric(index):
            let numeric = try variant.doubleValue()
            numerics[index] = numeric
        case let .variant(index):
            variants[index] = variant
        }
    }
    
    subscript(ref: Reference) -> Double? {
        switch ref {
            
        case let .builtin(builtin):
            switch builtin {
            case .step: return Double(step)
            case .time: return time
            case .timeDelta: return timeDelta
            }
        case let .stock(index): return stocks[index]
        case let .flow(index): return flows[index]
        case let .numeric(index): return numerics[index]
        case let .variant(index): return try? variants[index].doubleValue()
        }
    }

    /// Create a new simulation state by adding provided stock vector to the receiver's stock
    /// vector.
    ///
    public func adding(stocks: [Double], step: Int, time: Double, timeDelta: Double) -> SimulationState {
        precondition(stocks.count == self.stocks.count)
        var newState = self
        for (index, value) in stocks.enumerated() {
            newState.stocks[index] += value
        }
        newState.step = step
        newState.time = time
        newState.timeDelta = timeDelta
        
        return newState
    }
}

/// A collection of simulation state variables.
///
public struct _OLD_SimulationState: CustomStringConvertible {
    public typealias Index = Int
    
    public let step: Int
    public private(set) var time: Double
    public private(set) var timeDelta: Double
    
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
    
    
    // FIXME: Temporary, before we get new simulation state
    public func adding(stocks: [Double], indices: [Int], time: Double, timeDelta: Double) -> SimulationState {
        precondition(stocks.count == indices.count)
        var result = self
        
        // We are blindly trusting
        for (index, delta) in zip(indices, stocks) {
            let value = self.double(at: index)
            result.values[index] = Variant(value + delta)
        }
        
        result.time = time
        result.timeDelta = timeDelta
        
        return result
    }
}



