//
//  CompiledModel.swift
//  
//
//  Created by Stefan Urbanek on 05/06/2022.
//

import PoieticCore

/// Defaults fro simulation taken from an object with a trait
/// ``PoieticCore/Trait/Simulation``.
///
/// - SeeAlso: ``Simulator/init(model:solverType:)``
///
public struct SimulationDefaults {
    public let initialTime: Double
    public let timeDelta: Double
    public let simulationSteps: Int
}

/// Core structure used by the simulator and the solver to perform the
/// computation.
///
/// Compiled model is an internal representation of the model design for
/// computation. The structure is guaranteed to provide computational
/// information with integrity, such as order of computation or value types.
///
/// If the model design violates constraints or contains user errors, the
/// compiler refuses to create the compiled model.
///
/// The main content of the compiled model is a list of computed objects
/// ``simulationObjects`` and a list of simulation state variables
/// ``stateVariables``. The computation of computed objects can be carried out
/// in the order provided without causing broken computational dependencies.
///
/// Additional information about specific object types is provided in stored
/// properties such as ``stocks``, or ``charts``.
///
/// ## Uses by Applications
///
/// Applications running simulations can use the compiled model to fetch various
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
/// - Note: The compiled model can also be used in a similar way as
///  "explain plan" in SQL. It contains some information how the simulation
///   will be carried out.
///
/// - SeeAlso: ``Compiler/compile()``, ``Solver/init(_:)``,
///   ``Simulator/init(model:solverType:)``
///
public struct CompiledModel {
    // TODO: Alternative names: SimulationModel, ComputationalModel, InternalRepresentation, SimulableRepresentation, SRep, ResolvedModel, ExecutableModel
    
    /// List of variables that are computed, ordered by computational dependency.
    ///
    /// The variables are ordered so that variables that do not require other
    /// variables to be computed, such as constants are at the beginning.
    /// The variables that depend on others by using them as a parameter
    /// follow the variables they depend on.
    ///
    /// Computing variables in this order assures that we have all the
    /// parameters computed when needed them.
    ///
    /// - Note: It is guaranteed that the variables are ordered. If a cycle was
    ///         present in the model, the compiled model would not have been
    ///         created.
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
    /// - SeeAlso: ``Compiler/stateVariables``
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
    public let builtins: [CompiledBuiltin]
    
    /// Index of _time_ variable within the state variables.
    ///
    /// - SeeAlso: ``stateVariables``, ``Simulator/timePoints``
    ///
    public let timeVariableIndex: SimulationState.Index
    
    
    /// Get index into a list of computed variables for an object with given ID.
    ///
    /// This function is just for inspection and debugging purposes, it is not
    /// used during computation.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso:  ``stateVariables``, ``simulationObject(_:)``
    ///
    public func variableIndex(of id: ObjectID) -> SimulationState.Index? {
        // TODO: Do we need a pre-computed map here or are we fine with O(n)?
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
    /// - Complexity: O(n)
    /// - SeeAlso: ``simulationObjects``, ``variableIndex(of:)``
    ///
    public func simulationObject(_ id: ObjectID) -> SimulationObject? {
        return simulationObjects.first { $0.id == id }
        
    }

    /// Stocks ordered by the computation (parameter) dependency.
    ///
    /// This list contains all stocks used in the simulation and adds
    /// derived information to each stock such as its inflows and outflows.
    ///
    /// This property is used in computation.
    ///
    /// See ``CompiledStock`` for more information.
    ///
    /// - SeeAlso: ``Solver/stockDifference(state:at:timeDelta:)``,
    ///
    public let stocks: [CompiledStock]
    
    public var stockIndices: [SimulationState.Index] {
        stocks.map { $0.variableIndex }
    }
    
    
    /// Get a compiled stock by object ID.
    ///
    /// This property is used in computation.
    ///
    /// - SeeAlso: ``Solver/computeStockDelta(_:at:with:)``
    ///
    /// - Complexity: O(n)
    ///
    func compiledStock(_ id: ObjectID) -> CompiledStock {
        // TODO: What to do with this method?
        return stocks.first { $0.id == id }!
    }
    
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
    
    /// Selection of simulation variables that represent graphical functions.
    ///
    /// This property is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    public var graphicalFunctions: [CompiledGraphicalFunction] {
        // FIXME: Remove this, used only for tests
        // FIXME: Materialise this in the simulation object or somewhere
        let vars: [CompiledGraphicalFunction] = simulationObjects.compactMap {
            if case let .graphicalFunction(fun, param) = $0.computation {
                return CompiledGraphicalFunction(id: $0.id,
                                                 variableIndex: $0.variableIndex,
                                                 function: fun,
                                                 parameterIndex: param)
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
    /// - Precondition: The compiled model must contain a stock with given ID.
    ///
    public func stockIndex(_ id: ObjectID) -> NumericVector.Index {
        guard let index = stocks.firstIndex(where: { $0.id == id }) else {
            fatalError("The compiled model does not contain stock with ID \(id)")
        }
        return index
    }
}

