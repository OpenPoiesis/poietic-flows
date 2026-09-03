//
//  SimulationObjects.swift
//
//
//  Created by Stefan Urbanek on 15/03/2024.
//

import PoieticCore

/// Representation of a node in the simulation denoting how the node will
/// be computed.
///
public enum ComputationalRepresentation: CustomStringConvertible {
//    case stock(BoundStock)
//    case flow(BoundFlow)
    /// Arithmetic formula representation of a node.
    ///
    case formula(BoundExpression)
    
    /// Graphic function representation of a node.
    ///
    /// The first value is a generated function for computing the values. The
    /// second value of the tuple is an index of a state variable representing
    /// the function's parameter node.
    ///
    case graphicalFunction(BoundGraphicalFunction)
  
    /// Delay value input by given number of steps.
    case delay(BoundDelay)
    
    /// Exponential smoothing of a numeric value over a time window.
    ///
    case smooth(BoundSmooth)
    
    // case dataInput(???)

    public var description: String {
        switch self {
//        case let .stock(stock):
//            return "\(stock)"
//        case let .flow(flow):
//            return "\(flow)"
        case let .formula(formula):
            return "\(formula)"
        case let .graphicalFunction(fun):
            return "graphical(param:\(fun.parameterIndex))"
        case let .delay(delay):
            let initialValue = delay.initialValue.map { $0.description } ?? "nil"
            return "delay(input:\(delay.inputValueIndex),steps:\(delay.steps),init:\(initialValue)"
        case let .smooth(smooth):
            return "smooth(window:\(smooth.windowTime))"
        }
        
    }
}

/// Structure describing an object to be simulated.
///
/// This is the core detail information of the simulation.
///
/// The simulation object provides information about what kind of computation
/// is performed (see ``ComputationalRepresentation``), which variable
/// represents the object's state and what is the type of the stored value.
///
/// - SeeAlso: ``ComputationalRepresentation``
///
public struct SimulationObject: CustomStringConvertible {
    /// ID of the object, usually a node, that is being represented.
    ///
    public let objectID: ObjectID
    
    /// Information denoting how the object is being computed.
    ///
    public let computation: ComputationalRepresentation

    /// Index of the variable representing the object's state in the
    /// simulation state.
    ///
    /// - SeeAlso: ``SimulationPlan/stateVariables``
    ///
    public let variable: SimulationState.Reference
    // TODO: Add this for objects that have adjusted actual variables, such as flow rates
    // public let actualValueReference: SimulationState.Reference
    // public let actualVariableIndex: SimulationState.Index?

    public let role: SimulationRole
    
    public var isAccumulator: Bool {
        if role == .stock { return true }
        switch computation {
        case .delay, .smooth: return true
        case .formula, .graphicalFunction: return false
        }
    }

    /// Type of the variable value.
    ///
    public let valueType: ValueType
    
    /// Normalised name key of the object.
    ///
    public let nameKey: String
    
    public var description: String {
        "SimObject(\(nameKey), id:\(objectID), ref:\(variable), role: \(role))"
    }
}

/// Stock bound to a simulation plan and a simulation state.
///
/// Bound stock defines integration target.
///
public struct BoundStock {
    /// Object ID of the stock that this compiled structure represents.
    ///
    /// This is used mostly for inspection and debugging purposes.
    ///
    public let objectID: ObjectID
    
    /// Index in of the simulation state variable that represents the stock.
    ///
    /// This is the main information used during the computation.
    ///
    /// - SeeAlso: ``SimulationPlan/stateVariables``
    ///
    public let variableIndex: Int
    
    /// Flag whether the value of the node can be negative.
    ///
    public let allowsNegative: Bool
    
    /// Indices of flows from the list of flows that represent stock's inflows.
    ///
    /// To get flow details:
    ///
    /// ```swift
    /// let plan: SimulationPlan // Plan is given
    /// let stock: BoundStock    // Stock is given
    /// for index in inflows {
    ///     let inflow = plan.flows[index]
    ///     let value = state[inflow.estimatedValueIndex]
    ///     ...
    /// }
    /// ```
    public let inflows: [Int]

    /// Indices of flows from the list of flows that represent stock's outflows.
    ///
    /// To get flow details:
    ///
    /// ```swift
    /// let plan: SimulationPlan // Plan is given
    /// let stock: BoundStock    // Stock is given
    /// for index in outflows {
    ///     let outflow = plan.flows[index]
    ///     let value = state[outflow.estimatedValueIndex]
    ///     ...
    /// }
    /// ```
    public let outflows: [Int]
}

/// Represents a flow rate between stocks.
public struct BoundFlow {
    /// ID of object that represents this flow rate.
    public let objectID: ObjectID

    /// Index of a flow variable in the flows vector of simulation state.
    ///
    /// - SeeAlso: ``SimulationState/flows``, ``estimatedValueIndex``
    ///
    public let actualValueIndex: Int
    
    /// Index of a numeric variable in the state holding estimated value – the value as computed
    /// by the formula, before stock constraints were applied.
    ///
    /// - SeeAlso: ``actualValueIndex``,  ``SimulationState/numerics``
    ///
    public let estimatedValueIndex: Int

    
    /// ID of a stock in bound stocks that the flow drains.
    public let drains: ObjectID?
    
    /// ID of a stock in bound stocks that the flow fills.
    public let fills: ObjectID?
}


/// A structure representing a concrete instance of a graphical function
/// in the context of a graph.
///
public struct BoundGraphicalFunction {
    /// The function object itself
    public let function: GraphicalFunction
    
    /// Index of a variable that is a parameter for the function.
    public let parameter: SimulationState.Reference
}

/// Compiled delay node.
///
/// - SeeAlso: ``StockFlowSimulation/initialize(delay:in:)``
///
public struct BoundDelay {
    /// Number of steps to delay the input value by.
    public let steps: UInt
    
    /// Initial value of the delay node output.
    ///
    /// The initial value is used before the simulation reaches the required number of steps.
    /// If the initial value is not provided, then the initial value of the input is used.
    public let initialValue: Variant?

    /// Value type of the input and output.
    public let valueType: AtomType

    /// Index where the actual initial value is stored. The initial value
    /// can be either the ``initialValue`` if provided, or the input
    /// value during initialisation.
    ///
    /// - SeeAlso: ``StockFlowSimulation/initialize(delay:in:)``
    ///
    public let initialValueRef: SimulationState.Reference
    /// Index to the variants array.
    ///
    /// - Note: We are assuming that we can use only variant atom types for delay.
    ///
    /// - SeeAlso: ``SimulationState/variants``
    ///
    public let queueIndex: Int
    public let inputValueRef: SimulationState.Reference
}

/// Compiled smooth node.
///
/// - SeeAlso: ``StockFlowSimulation/initialize(smooth:in:)``
///
public struct BoundSmooth {
    /// Time window over which the smooth is computed.
    public let windowTime: Double

    /// Index to the numeric values of simulation state where the current smoothing value is stored.
    ///
    public let smoothValueIndex: Int
    
    /// Index to the numeric values of simulation state where the smooth node input is stored.
    public let inputValueIndex: Int
}

