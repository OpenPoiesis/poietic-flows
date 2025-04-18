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
public struct SimulationObject: CustomStringConvertible, Identifiable {
    /// ID of the object, usually a node, that is being represented.
    ///
    public let id: ObjectID

    public enum SimulationObjectType: Codable {
        case stock
        case flow
        case auxiliary
    }
   
    public let type: SimulationObjectType

    /// Index of the variable representing the object's state in the
    /// simulation state.
    ///
    /// - SeeAlso: ``SimulationPlan/stateVariables``
    ///
    public let variableIndex: Int
    
    /// Type of the variable value.
    ///
    public var valueType: ValueType
    
    /// Information denoting how the object is being computed.
    ///
    public let computation: ComputationalRepresentation
    
    /// Name of the object.
    ///
    public let name: String
    
    public var description: String {
        "var(\(name), id:\(id), idx:\(variableIndex))"
    }
}

/// Indices of built-in variables.
///
/// - SeeAlso: ``BuiltinVariable``
///
public struct CompiledBuiltinState {
    // NOTE: Synchronise with ``StockFlowSimulation/updateBuiltins``
    let time: SimulationState.Index
    let timeDelta: SimulationState.Index
    let step: SimulationState.Index
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
    public let id: ObjectID
    
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
    
    /// Flag that controls how flow for the stock is being computed when the
    /// stock is non-negative.
    ///
    /// If the stock is non-negative, normally its outflow depends on the
    /// inflow. This is not a problem unless there is a loop of flows between
    /// stocks. In that case, to proceed with computation we need to break the
    /// loop. Stock being with 'delayed inflow' means that the outflow will not
    /// immediately depend on the inflow. The outflow will be computed from
    /// the actual stock value, ignoring the inflow. The inflow will be added
    /// later to the stock.
    ///
    public let delayedInflow: Bool

    /// List indices of simulation variables representing flows
    /// which fill the stock.
    ///
    /// - SeeAlso: ``StockFlowSimulation/computeStockDelta(A
    ///
    public let inflows: [SimulationState.Index]

    /// List indices of simulation variables representing flows
    /// which drain the stock.
    ///
    /// - SeeAlso: ``StockFlowSimulation/computeStockDelta(A
    ///
    public let outflows: [SimulationState.Index]
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
    public let initialValueIndex: SimulationState.Index
    public let queueIndex: SimulationState.Index
    public let inputValueIndex: SimulationState.Index
}

/// Compiled smooth node.
///
/// - SeeAlso: ``StockFlowSimulation/initialize(smooth:in:)``
///
public struct BoundSmooth {
    /// Time window over which the smooth is computed.
    public let windowTime: Double

    /// Index where the current smoothing value is stored.
    ///
    public let smoothValueIndex: SimulationState.Index
    
    /// Index of the value where the smooth node input is stored.
    public let inputValueIndex: SimulationState.Index
}


/// Describes a connection between two stocks through a flow.
///
/// - SeeAlso: ``StockFlowSimulation/stockDifference(state:time:)``
/// 
public struct StockAdjacency: EdgeProtocol, Identifiable {
    /// OD of a flow that connects the two stocks
    public let id: ObjectID
    /// ID of a stock being drained by the flow.
    public let origin: ObjectID
    /// ID of a stock being filled by the flow.
    public let target: ObjectID

    /// Flag whether the target has delayed inflow.
    public let targetHasDelayedInflow: Bool
}
