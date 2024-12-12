//
//  SimulationPlan.swift
//
//
//  Created by Stefan Urbanek on 05/06/2022.
//

import PoieticCore

/// Defaults fro simulation taken from an object with a trait
/// ``PoieticCore/Trait/Simulation``.
///
/// - SeeAlso: ``Simulator/init(_:simulation:)``
///
public struct SimulationDefaults {
    public let initialTime: Double
    public let timeDelta: Double
    public let simulationSteps: Int
}

/// Core structure describing the simulation.
///
/// Simulation plan describes how the simulation is computed, how does the simulation state look
/// like, what is the order in which the objects are being computed.
///
/// The main content of the simulation plan is a list of computed objects in order of computational
/// dependency ``simulationObjects`` and a list of simulation state variables ``stateVariables``.
///
/// ## Uses by Applications
///
/// Applications running simulations can use the simulation plan to fetch various
/// information that is to be presented to the user or that can be expected
/// from the user as an input or as a configuration. For example:
///
/// - ``charts`` to get a list of charts that are specified in the design
///   that the designer considers relevant to be displayed to the user.
/// - ``valueBindings`` to get a list of controls and their targets to generate
///   user interface for changing initial values of model-specific objects.
/// - ``stateVariables`` and their stored property ``StateVariable/name`` to
///   get a list of variables that can be observed.
/// - ``variable(named:)`` to fetch detailed information about a specific
///   variable.
/// - ``timeVariableIndex`` to get an index into ``stateVariables`` where the
///   time variable is stored.
/// - ``simulationDefaults`` for simulation run configuration.
///
/// - Note: The simulation plan is loosely analogous to a SQL execution plan.
///
/// - SeeAlso: ``Compiler/compile()``, ``StockFlowSimulation``,
///
public struct SimulationPlan {
    /// List of objects that are considered in the computation computed, ordered by computational
    /// dependency.
    ///
    /// The computational dependency means, that the objects are ordered so that objects that do
    /// not require other objects to be computed, such as constants are at the beginning. The
    /// objects that depend on others by using them as a parameter follow the variables they depend
    /// on.
    ///
    /// Computing objects in this order assures that we have all the parameters computed when
    /// they are needed.
    ///
    /// - SeeAlso: ``variableIndex(of:)``
    ///
    public let simulationObjects: [SimulationObject]

    /// List of simulation state variables.
    ///
    /// The list of state variables contain values of builtins, values of
    /// nodes and values of internal states.
    ///
    /// Each node is typically assigned one state variable which represents
    /// the node's value at given state. Some nodes might contain internal
    /// state that might be present in multiple state variables.
    ///
    /// The internal state is typically not user-presentable and is a state
    /// associated with stateful functions or other computation objects.
    ///
    /// A state of a variable is computed in the simulator with
    /// ``StockFlowSimulation/update(_:)``.
    ///
    /// - SeeAlso: ``StockFlowSimulation/initialize(_:)``,
    ///     ``StockFlowSimulation/update(objectAt:in:)``,
    ///      ``Compiler/stateVariables``
    ///
    public let stateVariables: [StateVariable]
    
    /// List of compiled builtin variables.
    ///
    /// The compiled builtin variable references a state variable that holds
    /// the value for the builtin variable and a kind of the builtin variable.
    ///
    /// - SeeAlso: ``stateVariables``, ``CompiledBuiltin``, ``/PoieticCore/Variable``,
    ///   ``FlowsMetamodel``
    ///
    public let builtins: CompiledBuiltinState
    
    /// Index of _time_ variable within the state variables.
    ///
    /// - SeeAlso: ``stateVariables``, ``Simulator/timePoints``
    ///
    public let timeVariableIndex: SimulationState.Index
    
    /// Stocks ordered by the computation (parameter) dependency.
    ///
    /// This list contains all stocks used in the simulation and adds
    /// derived information to each stock such as its inflows and outflows.
    ///
    /// This property is used in computation.
    ///
    /// See ``SimulatedStock`` for more information.
    ///
    /// - SeeAlso: ``StockFlowSimulation/computeStockDelta(_:in:)``,
    /// ``StockFlowSimulation/stockDifference(state:time:)``
    ///
    public let stocks: [BoundStock]
    
    /// List of charts.
    ///
    /// This property is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    public let charts: [Chart]


    /// Compiled bindings of controls to their value objects.
    ///
    public let valueBindings: [CompiledControlBinding]
        
    /// Collection of default values for running a simulation.
    ///
    /// See ``SimulationDefaults`` for more information.
    ///
    public var simulationDefaults: SimulationDefaults?
    
    /// Get index into a list of computed variables for an object with given ID.
    ///
    /// This function is just for inspection and debugging purposes, it is not
    /// used during computation.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso:  ``stateVariables``, ``simulationObject(_:)``
    ///
    public func variableIndex(of id: ObjectID) -> SimulationState.Index? {
        // Since this is just for debug purposes, O(n) should be fine, no need
        // for added complexity of the code.
        guard let first = simulationObjects.first(where: {$0.id == id}) else {
            return nil
        }
        return first.variableIndex
    }
   
    /// Get a simulation variable for an object with given ID, if exists.
    ///
    /// This function is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    /// The objects are computed with ``StockFlowSimulation/update(objectAt:in:)``.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso: ``simulationObjects``, ``variableIndex(of:)``
    ///
    public func simulationObject(_ id: ObjectID) -> SimulationObject? {
        return simulationObjects.first { $0.id == id }
        
    }

    /// Indices of variables representing stocks.
    ///
    public var stockIndices: [SimulationState.Index] {
        stocks.map { $0.variableIndex }
    }
    
    /// Get a compiled stock by object ID.
    ///
    /// This property is used in computation.
    ///
    /// - SeeAlso: ``StockFlowSimulation/computeStockDelta(_:in:)``,
    /// ``StockFlowSimulation/stockDifference(state:time:)``
    ///
    /// - Complexity: O(n)
    ///
    func compiledStock(_ id: ObjectID) -> BoundStock {
        // TODO: What to do with this method?
        return stocks.first { $0.id == id }!
    }

    /// Selection of simulation variables that represent graphical functions.
    ///
    /// This property is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    public var graphicalFunctions: [BoundGraphicalFunction] {
        // FIXME: Remove this, used only for tests
        // FIXME: Materialise this in the simulation object or somewhere
        let vars: [BoundGraphicalFunction] = simulationObjects.compactMap {
            if case let .graphicalFunction(fun) = $0.computation {
                return fun
            }
            else {
                return nil
            }
        }
        return vars
    }
    
    /// Get a compiled variable by its name.
    ///
    /// This function is mostly for user-facing tools that would like to
    /// interfere with the simulation state. Example use-cases are:
    ///
    /// - querying the state by variable name
    /// - modifying state variables by user provided variable values
    ///
    /// Since the function is slow, it is highly not recommended to be used
    /// during iterative computation.
    ///
    /// This property is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    /// - Complexity: O(n)
    ///
    public func variable(named name: String) -> SimulationObject? {
        guard let object = simulationObjects.first(where: { $0.name == name}) else {
            return nil
        }
                 
        return object
    }
    
    /// Index of a stock in a list of stocks or in a stock difference vector.
    ///
    /// This function is not used during computation. It is provided for
    /// potential inspection, testing and debugging.
    ///
    /// - Precondition: The plan must contain a stock with given ID.
    ///
    public func stockIndex(_ id: ObjectID) -> NumericVector.Index {
        guard let index = stocks.firstIndex(where: { $0.id == id }) else {
            preconditionFailure("The plan does not contain stock with ID \(id)")
        }
        return index
    }
}

