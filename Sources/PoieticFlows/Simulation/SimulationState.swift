//
//  StateVector.swift
//  
//
//  Created by Stefan Urbanek on 30/07/2022.
//

import PoieticCore

public enum SimulationStateError: Error {
    case valueError(SimulationState.Reference, ValueError)
    case settingBuiltin(SimulationState.Reference)
}

public enum StateVariableType: Equatable {
    case builtin
    case stock
    case flow
    case numeric
    case variant
}

public struct SimulationState {
    // Replaces BoundVariable
    // Alt names: just Reference or just Variable
    public enum Reference: Hashable, CustomStringConvertible, Sendable {
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
        
        public var type: StateVariableType {
            switch self {
            case .builtin: .builtin
            case .stock:   .stock
            case .flow:    .flow
            case .numeric: .numeric
            case .variant: .variant
            }
        }
    }
    
    public internal(set) var step: Int
    public internal(set) var time: Double
    public internal(set) var timeDelta: Double
    private var constants: Set<Reference>

    /// Stocks
    public var stocks: NumericVector
    /// Values of flow rates.
    ///
    /// During computation it holds flow estimates – as computed by the formulas. In the result state
    /// it holds adjusted flows.
    public var flows: NumericVector

    // NOTE: No need for a NumericVector in `numerics`, because we are not doing vector based
    //       operations on it. It is just assortment of numeric values.
    
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
        self.numerics = Array(repeating: 0.0, count: plan.numericVariableCount)
        self.variants = Array(repeating: Variant(0), count: plan.variantVariableCount)
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
            
        case let .builtin(builtin): return Variant(doubleValue(forBuiltin: builtin))
        case let .stock(index):     return Variant(stocks[index])
        case let .flow(index):      return Variant(flows[index])
        case let .numeric(index):   return Variant(numerics[index])
        case let .variant(index):   return variants[index]
        }
    }

    func doubleValue(at ref: Reference) throws (ValueError) -> Double {
        switch ref {
        case let .builtin(builtin): return doubleValue(forBuiltin: builtin)
        case let .stock(index):     return stocks[index]
        case let .flow(index):      return flows[index]
        case let .numeric(index):   return numerics[index]
        case let .variant(index):   return try variants[index].doubleValue()
        }
    }
    
    func doubleValue(forBuiltin builtin: BuiltinVariable) -> Double {
        switch builtin {
        case .step:      return Double(step)
        case .time:      return time
        case .timeDelta: return timeDelta
        }
    }

    mutating func setValue(_ variant: Variant, for reference: Reference) throws (ValueError) {
        switch reference {
        case .builtin(_):
            preconditionFailure("Trying to set builtin in simulation state")
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
    
    /// Create a new simulation state by adding provided stock vector to the receiver's stock
    /// vector.
    ///
    public func adding(stocks: NumericVector, step: Int, time: Double, timeDelta: Double) -> SimulationState {
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


// for evaluation
extension SimulationState: VariableValueLookup {
    public typealias Variable = BoundVariable
    public func value(for variable: Variable) -> Variant {
        self[variable.reference]
    }
}
