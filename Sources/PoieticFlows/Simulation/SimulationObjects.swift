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
    
    public var valueType: ValueType {
        switch self {
//        case .stock(_):
//            return .double
//        case .flow(_):
//            return .double
        case let .formula(formula):
            return formula.valueType
        case .graphicalFunction(_):
            return ValueType.double
        case let .delay(delay):
            return .atom(delay.valueType)
        case .smooth(_):
            return .atom(.double)
        }
    }
    
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
/// - SeeAlso: ``ComputationalRepresentation``,
///   ``StockFlowSimulation/evaluate(expression:with:)``
///
public struct SimulationObject: CustomStringConvertible {
    /// ID of the object, usually a node, that is being represented.
    ///
    public let objectID: ObjectID
    
    /// Information denoting how the object is being computed.
    ///
    public let computation: ComputationalRepresentation

    /// Role in the Stock-Flow simulation.
    ///
    /// Role determines when and how the simulation object is being computed.
    ///
    /// - `stock` – computation defined through formula is done only during initialisation phase
    /// - `flow` – computation is performed during initialisation and after stock integration
    /// - `auxiliary` – same rule as flow applies
    ///
    public enum Role: Codable {
        /// Computation defined through formula is done only during initialisation phase.
        case stock
        /// Computation is performed during initialisation and after stock integration,
        /// same as auxiliary.
        case flow
        /// Computation is performed during initialisation and after stock integration,
        /// same as flow.
        case auxiliary
    }
   
    /// Index of the variable representing the object's state in the
    /// simulation state.
    ///
    /// - SeeAlso: ``SimulationPlan/stateVariables``
    ///
    public let variableIndex: Int
    
    public let role: Role

    /// Type of the variable value.
    ///
    public var valueType: ValueType
    
    /// Name of the object.
    ///
    public let name: String
    
    public var description: String {
        "simob(\(name), id:\(objectID), idx:\(variableIndex), role: \(role))"
    }
}

/// Indices of built-in variables bound to a simulation plan.
///
/// - SeeAlso: ``BuiltinVariable``
///
public struct BoundBuiltins {
    // NOTE: Synchronise with ``StockFlowSimulation/setBuiltins``
    public let step: SimulationState.Index
    public let time: SimulationState.Index
    public let timeDelta: SimulationState.Index

    internal init(step: SimulationState.Index = 0,
                  time: SimulationState.Index = 1,
                  timeDelta: SimulationState.Index = 2) {
        self.step = step
        self.time = time
        self.timeDelta = timeDelta
    }
    
}

/// Stock bound to a simulation plan and a simulation state.
///
/// This structure is used during computation.
///
/// - SeeAlso: ``StockFlowSimulation/computeStockDelta(_:in:)``
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
    public let variableIndex: SimulationState.Index
    
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

    /// Indices of flows from the list of flows that represent stock's inflows.
    ///
    /// To get flow details:
    ///
    /// ```swift
    /// let plan: SimulationPlan // Plan is given
    /// let stock: BoundStock    // Stock is given
    /// for index in outflows {
    ///     let inflow = plan.flows[index]
    ///     let value = state[inflow.estimatedValueIndex]
    ///     ...
    /// }
    /// ```
    public let outflows: [Int]
}

/// Represents a flow rate between stocks.
public struct BoundFlow {
    /// ID of object that represents this flow rate.
    public let objectID: ObjectID

    /// Index of a variable in the state holding value of the flow rate that is expected.
    public let estimatedValueIndex: SimulationState.Index

    /// Index of a variable in the state holding value of the flow rate that was used in the
    /// computation.
    ///
    /// This value might be different from expected value if a non-negative stocks are used.
    public let adjustedValueIndex: SimulationState.Index
    
    public let priority: Int
    
    /// Index of a stock in bound stocks that the flow drains.
    public let drains: ObjectID?
    
    /// Index of a stock in bound stocks that the flow fills.
    public let fills: ObjectID?
}


/// A structure representing a concrete instance of a graphical function
/// in the context of a graph.
///
public struct BoundGraphicalFunction {
    /// The function object itself
    public let function: GraphicalFunction
    
    /// ID of a node that is a parameter for the function.
    public let parameterIndex: SimulationState.Index
}

/// Structure representing compiled control-to-value binding.
///
/// - SeeAlso: ``PoieticCore/ObjectType/Control``, ``PoieticCore/ObjectType/ValueBinding``
///
public struct CompiledControlBinding {
    /// ID of a control node.
    ///
    /// - SeeAlso: ``PoieticCore/ObjectType/Control``
    public let control: ObjectID
    
    /// Index of the simulation variable that the control controls.
    public let variableIndex: SimulationState.Index
}

/// Compiled delay node.
///
/// - SeeAlso: ``StockFlowSimulation/initialize(delay:in:)``
///
public struct BoundDelay: Component {
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
    public let initialValueIndex: SimulationState.Index
    public let queueIndex: SimulationState.Index
    public let inputValueIndex: SimulationState.Index
}

/// Compiled smooth node.
///
/// - SeeAlso: ``StockFlowSimulation/initialize(smooth:in:)``
///
public struct BoundSmooth: Component {
    /// Time window over which the smooth is computed.
    public let windowTime: Double

    /// Index where the current smoothing value is stored.
    ///
    public let smoothValueIndex: SimulationState.Index
    
    /// Index of the value where the smooth node input is stored.
    public let inputValueIndex: SimulationState.Index
}

